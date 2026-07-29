import Dispatch
import Foundation

enum ShortcutRunnerError: LocalizedError {
    case emptyName
    case timedOut
    case failed(exitCode: Int32)

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "The Shortcut name is empty."
        case .timedOut:
            return "The Shortcut did not finish within 10 seconds."
        case let .failed(exitCode):
            return "The Shortcut exited with status \(exitCode)."
        }
    }
}

struct ShortcutRunner {
    func run(named rawName: String) -> Result<Void, Error> {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            return .failure(ShortcutRunnerError.emptyName)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", name]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let completion = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            completion.signal()
        }

        do {
            try process.run()
            guard completion.wait(timeout: .now() + 10) == .success else {
                process.terminate()
                return .failure(ShortcutRunnerError.timedOut)
            }
            guard process.terminationStatus == 0 else {
                return .failure(
                    ShortcutRunnerError.failed(
                        exitCode: process.terminationStatus
                    )
                )
            }
            return .success(())
        } catch {
            return .failure(error)
        }
    }
}
