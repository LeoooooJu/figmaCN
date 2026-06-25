import Foundation

struct ShellResult: Sendable {
    let stdout: String
    let stderr: String
    let status: Int32
}

enum ShellError: LocalizedError {
    case failed(command: String, status: Int32, stderr: String)
    case timeout(command: String)

    var errorDescription: String? {
        switch self {
        case let .failed(command, status, stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty ? "\(command) 执行失败，退出码 \(status)" : detail
        case let .timeout(command):
            return "\(command) 执行超时"
        }
    }
}

@discardableResult
func runCommand(_ launchPath: String, _ arguments: [String], timeout: TimeInterval = 30) async throws -> ShellResult {
    try await withCheckedThrowingContinuation { continuation in
        let completion = CommandCompletion(continuation: continuation)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        process.terminationHandler = { proc in
            let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let result = ShellResult(stdout: stdout, stderr: stderr, status: proc.terminationStatus)
            if proc.terminationStatus == 0 {
                completion.succeed(result)
            } else {
                completion.fail(ShellError.failed(command: ([launchPath] + arguments).joined(separator: " "), status: proc.terminationStatus, stderr: stderr))
            }
        }

        do {
            try process.run()
        } catch {
            completion.fail(error)
            return
        }

        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            if process.isRunning {
                process.terminate()
                completion.fail(ShellError.timeout(command: ([launchPath] + arguments).joined(separator: " ")))
            }
        }
    }
}

private final class CommandCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    private let continuation: CheckedContinuation<ShellResult, Error>

    init(continuation: CheckedContinuation<ShellResult, Error>) {
        self.continuation = continuation
    }

    func succeed(_ result: ShellResult) {
        finish(.success(result))
    }

    func fail(_ error: Error) {
        finish(.failure(error))
    }

    private func finish(_ result: Result<ShellResult, Error>) {
        lock.lock()
        if completed {
            lock.unlock()
            return
        }
        completed = true
        lock.unlock()
        continuation.resume(with: result)
    }
}

func commandExists(_ command: String) async -> Bool {
    do {
        _ = try await runCommand("/usr/bin/env", ["which", command], timeout: 5)
        return true
    } catch {
        return false
    }
}

func escapedAppleScript(_ value: String) -> String {
    value.replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
}

func escapedShellDouble(_ value: String) -> String {
    value.replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
}

func runAsAdminBatch(_ commands: [String]) async throws {
    let joined = commands.joined(separator: " ; ")
    let script = "do shell script \"\(escapedAppleScript(joined))\" with administrator privileges"
    _ = try await runCommand("/usr/bin/osascript", ["-e", script], timeout: 120)
}
