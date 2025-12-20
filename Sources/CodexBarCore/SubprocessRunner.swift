import Foundation

public enum SubprocessRunnerError: LocalizedError, Sendable {
    case binaryNotFound(String)
    case launchFailed(String)
    case timedOut(String)
    case nonZeroExit(code: Int32, stderr: String)

    public var errorDescription: String? {
        switch self {
        case let .binaryNotFound(binary):
            return "Missing CLI '\(binary)'. Install it and restart CodexBar."
        case let .launchFailed(details):
            return "Failed to launch process: \(details)"
        case let .timedOut(label):
            return "Command timed out: \(label)"
        case let .nonZeroExit(code, stderr):
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "Command failed with exit code \(code)."
            }
            return "Command failed (\(code)): \(trimmed)"
        }
    }
}

public struct SubprocessResult: Sendable {
    public let stdout: String
    public let stderr: String
}

public enum SubprocessRunner {
    public static func run(
        binary: String,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval,
        label: String) async throws -> SubprocessResult
    {
        guard FileManager.default.isExecutableFile(atPath: binary) else {
            throw SubprocessRunnerError.binaryNotFound(binary)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = nil

        let exitCodeTask = Task<Int32, Error> {
            try await withCheckedThrowingContinuation { cont in
                process.terminationHandler = { proc in
                    cont.resume(returning: proc.terminationStatus)
                }
                do {
                    try process.run()
                } catch {
                    cont.resume(throwing: SubprocessRunnerError.launchFailed(error.localizedDescription))
                }
            }
        }

        do {
            let exitCode = try await withThrowingTaskGroup(of: Int32.self) { group in
                group.addTask { try await exitCodeTask.value }
                group.addTask {
                    try await Task.sleep(for: .seconds(timeout))
                    throw SubprocessRunnerError.timedOut(label)
                }
                let code = try await group.next()!
                group.cancelAll()
                return code
            }

            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""

            if exitCode != 0 {
                throw SubprocessRunnerError.nonZeroExit(code: exitCode, stderr: stderr)
            }

            return SubprocessResult(stdout: stdout, stderr: stderr)
        } catch {
            if process.isRunning {
                process.terminate()
                let killDeadline = Date().addingTimeInterval(0.4)
                while process.isRunning, Date() < killDeadline {
                    usleep(50000)
                }
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
            }
            throw error
        }
    }
}
