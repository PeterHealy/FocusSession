import Darwin
import Foundation

public enum LocalStateRepositoryError: LocalizedError {
    case applicationSupportUnavailable
    case unableToOpenLockFile
    case unableToLockState

    public var errorDescription: String? {
        switch self {
        case .applicationSupportUnavailable:
            return "The user Application Support directory is unavailable."
        case .unableToOpenLockFile:
            return "The Focus Session state lock could not be opened."
        case .unableToLockState:
            return "The Focus Session state could not be locked."
        }
    }
}

public final class LocalStateRepository {
    public let rootDirectory: URL
    public let stateFileURL: URL
    public let lockFileURL: URL

    private let inProcessLock = NSLock()
    private let fileManager: FileManager

    public convenience init(fileManager: FileManager = .default) throws {
        guard let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw LocalStateRepositoryError.applicationSupportUnavailable
        }

        try self.init(
            rootDirectory: applicationSupport.appendingPathComponent(
                "FocusSession",
                isDirectory: true
            ),
            fileManager: fileManager
        )
    }

    public init(rootDirectory: URL, fileManager: FileManager = .default) throws {
        self.rootDirectory = rootDirectory
        stateFileURL = rootDirectory.appendingPathComponent("state.json")
        lockFileURL = rootDirectory.appendingPathComponent("state.lock")
        self.fileManager = fileManager
        try fileManager.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        try? fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: rootDirectory.path
        )
    }

    public func snapshot() throws -> PersistedState {
        try withExclusiveAccess {
            try loadUnlocked()
        }
    }

    @discardableResult
    public func transaction<Result>(
        _ body: (inout PersistedState) throws -> Result
    ) throws -> Result {
        try withExclusiveAccess {
            var state = try loadUnlocked()
            let original = state
            let result = try body(&state)
            if state != original {
                try saveUnlocked(state)
            }
            return result
        }
    }

    public func replace(with state: PersistedState) throws {
        try withExclusiveAccess {
            try saveUnlocked(state)
        }
    }

    private func withExclusiveAccess<Result>(
        _ body: () throws -> Result
    ) throws -> Result {
        inProcessLock.lock()
        defer { inProcessLock.unlock() }

        let descriptor = Darwin.open(
            lockFileURL.path,
            O_CREAT | O_RDWR,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else {
            throw LocalStateRepositoryError.unableToOpenLockFile
        }
        _ = Darwin.fchmod(descriptor, S_IRUSR | S_IWUSR)
        defer { Darwin.close(descriptor) }

        guard flock(descriptor, LOCK_EX) == 0 else {
            throw LocalStateRepositoryError.unableToLockState
        }
        defer { flock(descriptor, LOCK_UN) }

        return try body()
    }

    private func loadUnlocked() throws -> PersistedState {
        guard fileManager.fileExists(atPath: stateFileURL.path) else {
            return PersistedState()
        }

        do {
            let data = try Data(contentsOf: stateFileURL)
            return try Self.makeDecoder().decode(PersistedState.self, from: data)
        } catch {
            let backupURL = rootDirectory.appendingPathComponent(
                "state-corrupt-\(Self.backupTimestamp()).json"
            )
            try? fileManager.moveItem(at: stateFileURL, to: backupURL)
            try? fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: backupURL.path
            )
            return PersistedState()
        }
    }

    private func saveUnlocked(_ state: PersistedState) throws {
        let data = try Self.makeEncoder().encode(state)
        try data.write(to: stateFileURL, options: [.atomic])
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: stateFileURL.path
        )
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func backupTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
    }
}
