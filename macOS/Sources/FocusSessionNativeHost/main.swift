import Darwin
import Dispatch
import FocusSessionCore
import Foundation

private let maximumInputMessageSize = 4 * 1024 * 1024
private let maximumOutputMessageSize = 1 * 1024 * 1024
private let input = FileHandle.standardInput

private let fractionalISO8601Formatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [
        .withInternetDateTime,
        .withFractionalSeconds
    ]
    return formatter
}()

private let wholeSecondISO8601Formatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()

private let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)

        if let date = fractionalISO8601Formatter.date(from: value) {
            return date
        }

        if let date = wholeSecondISO8601Formatter.date(from: value) {
            return date
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Expected an ISO 8601 date."
        )
    }
    return decoder
}()

private func readExactly(_ count: Int) throws -> Data? {
    var result = Data()
    while result.count < count {
        guard let chunk = try input.read(
            upToCount: count - result.count
        ), !chunk.isEmpty else {
            return result.isEmpty ? nil : result
        }
        result.append(chunk)
    }
    return result
}

private func readRequest() throws -> Data? {
    guard let header = try readExactly(4) else {
        return nil
    }
    guard header.count == 4 else {
        throw NativeMessageProtocolError.malformedFrame
    }

    let bytes = [UInt8](header)
    let length =
        UInt32(bytes[0])
        | UInt32(bytes[1]) << 8
        | UInt32(bytes[2]) << 16
        | UInt32(bytes[3]) << 24

    guard length <= UInt32(maximumInputMessageSize) else {
        throw NativeMessageProtocolError.messageTooLarge
    }
    guard let payload = try readExactly(Int(length)),
          payload.count == Int(length)
    else {
        throw NativeMessageProtocolError.malformedFrame
    }
    return payload
}

private final class ResponseWriter {
    private let lock = NSLock()
    private let output = FileHandle.standardOutput
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    func write(_ response: NativeMessageResponse) throws {
        lock.lock()
        defer { lock.unlock() }

        let payload = try encoder.encode(response)
        guard payload.count <= maximumOutputMessageSize else {
            throw NativeMessageProtocolError.messageTooLarge
        }

        let length = UInt32(payload.count)
        let header = Data([
            UInt8(length & 0xff),
            UInt8((length >> 8) & 0xff),
            UInt8((length >> 16) & 0xff),
            UInt8((length >> 24) & 0xff)
        ])
        try output.write(contentsOf: header)
        try output.write(contentsOf: payload)
    }
}

private final class StateDirectoryWatcher {
    private let processor: NativeMessageProcessor
    private let writer: ResponseWriter
    private let source: DispatchSourceFileSystemObject
    private let queue = DispatchQueue(
        label: "com.focussession.nativehost.state-watch"
    )
    private var pendingEmission: DispatchWorkItem?

    init?(
        directoryURL: URL,
        processor: NativeMessageProcessor,
        writer: ResponseWriter
    ) {
        let descriptor = Darwin.open(directoryURL.path, O_EVTONLY)
        guard descriptor >= 0 else {
            return nil
        }

        self.processor = processor
        self.writer = writer
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .extend, .attrib],
            queue: queue
        )
        source.setCancelHandler {
            Darwin.close(descriptor)
        }
        source.setEventHandler { [weak self] in
            self?.scheduleEmission()
        }
        source.resume()
    }

    func cancel() {
        pendingEmission?.cancel()
        source.cancel()
    }

    private func scheduleEmission() {
        pendingEmission?.cancel()
        let emission = DispatchWorkItem { [weak self] in
            self?.emitCurrentState()
        }
        pendingEmission = emission
        queue.asyncAfter(deadline: .now() + .milliseconds(40), execute: emission)
    }

    private func emitCurrentState() {
        let response = processor.process(
            NativeMessageRequest(type: .getState)
        )
        do {
            try writer.write(response)
        } catch {
            writeErrorLog(error)
        }
    }
}

private func writeErrorLog(_ error: Error) {
    FileHandle.standardError.write(
        Data("FocusSessionNativeHost: \(error.localizedDescription)\n".utf8)
    )
}

do {
    let repository = try LocalStateRepository()
    let service = SessionService(repository: repository)
    let processor = NativeMessageProcessor(service: service)
    let writer = ResponseWriter()
    let stateWatcher = StateDirectoryWatcher(
        directoryURL: repository.rootDirectory,
        processor: processor,
        writer: writer
    )
    defer { stateWatcher?.cancel() }

    while true {
        do {
            guard let payload = try readRequest() else {
                break
            }
            let request = try decoder.decode(
                NativeMessageRequest.self,
                from: payload
            )
            try writer.write(processor.process(request))
        } catch {
            try writer.write(processor.failureResponse(for: error))
            if error is NativeMessageProtocolError {
                break
            }
        }
    }
} catch {
    // Native messaging stdout must contain frames only. If the repository cannot
    // be created, Chrome/Brave will observe the host closing and report failure.
    writeErrorLog(error)
    exit(EXIT_FAILURE)
}
