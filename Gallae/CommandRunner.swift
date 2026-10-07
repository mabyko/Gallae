import Foundation
import Darwin

enum CommandRunner {
    static let gitURL = URL(fileURLWithPath: "/usr/bin/git")
    @TaskLocal private static var readCancellation: GitProcessCancellation?

    /// Keep synchronous Git reads off the main actor and cancel every command in the read together.
    static func read<Value: Sendable>(
        _ operation: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        let cancellation = GitProcessCancellation()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let value = try await Task.detached(priority: .userInitiated) {
                try $readCancellation.withValue(cancellation, operation: operation)
            }.value
            try Task.checkCancellation()
            return value
        } onCancel: {
            cancellation.cancel()
        }
    }

    static func run(
        _ arguments: [String],
        executableURL: URL,
        currentDirectoryURL: URL? = nil,
        maximumOutputBytes: Int? = nil,
        standardInput: Data? = nil,
        cancellation: GitProcessCancellation? = nil,
        additionalEnvironment: [String: String] = [:]
    ) throws -> GitResult {
        // Explicit mutation cancellation returns the exit status so callers can abort/restore Git state.
        let cancelsRead = cancellation == nil && readCancellation != nil
        let cancellation = cancellation ?? readCancellation
        if cancelsRead, cancellation?.isCancelled == true { throw CancellationError() }
        let process = Process()
        let captureDirectory = FileManager.default.temporaryDirectory
            .appending(path: "Gallae-Git-\(UUID().uuidString)", directoryHint: .isDirectory)
        let standardOutputURL = captureDirectory.appending(path: "stdout")
        let standardErrorURL = captureDirectory.appending(path: "stderr")

        try FileManager.default.createDirectory(at: captureDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: captureDirectory) }
        try Data().write(to: standardOutputURL)
        try Data().write(to: standardErrorURL)

        let standardOutput = try FileHandle(forWritingTo: standardOutputURL)
        let outputPipe = maximumOutputBytes == nil ? nil : Pipe()
        let standardError = try FileHandle(forWritingTo: standardErrorURL)
        let standardInputHandle: FileHandle?
        if let standardInput {
            let standardInputURL = captureDirectory.appending(path: "stdin")
            try standardInput.write(to: standardInputURL)
            standardInputHandle = try FileHandle(forReadingFrom: standardInputURL)
        } else {
            standardInputHandle = nil
        }
        defer {
            try? standardOutput.close()
            try? standardError.close()
            try? standardInputHandle?.close()
            try? outputPipe?.fileHandleForReading.close()
            try? outputPipe?.fileHandleForWriting.close()
        }

        process.executableURL = executableURL
        process.currentDirectoryURL = currentDirectoryURL
        process.arguments = arguments
        process.standardInput = standardInputHandle
        if let outputPipe {
            process.standardOutput = outputPipe
        } else {
            process.standardOutput = standardOutput
        }
        process.standardError = standardError

        var environment = ProcessInfo.processInfo.environment
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["LC_ALL"] = "C"
        environment.merge(additionalEnvironment) { _, value in value }
        process.environment = environment

        do {
            try process.run()
        } catch {
            if executableURL == gitURL { throw RepositoryInspectionError.gitUnavailable }
            throw error
        }

        cancellation?.register(process)
        defer { cancellation?.clear(process) }
        var capturedOutput = Data()
        var exceededLimit = false
        if let outputPipe, let maximumOutputBytes {
            // Drain stdout while Git runs; stderr and stdin use files so neither can block
            // behind a full pipe. Close our writer so EOF arrives when the child exits.
            do {
                try outputPipe.fileHandleForWriting.close()
                while let chunk = try outputPipe.fileHandleForReading.read(upToCount: 64 * 1024), !chunk.isEmpty {
                    if chunk.count > max(0, maximumOutputBytes) - capturedOutput.count {
                        exceededLimit = true
                        capturedOutput.removeAll(keepingCapacity: false)
                        if process.isRunning { process.terminate() }
                        break
                    }
                    capturedOutput.append(chunk)
                }
                try outputPipe.fileHandleForReading.close()
                if exceededLimit { finishTerminatingLimitedRead(process) }
            } catch {
                if process.isRunning { process.terminate() }
                try? outputPipe.fileHandleForReading.close()
                finishTerminatingLimitedRead(process)
                process.waitUntilExit()
                if cancelsRead, cancellation?.isCancelled == true { throw CancellationError() }
                throw error
            }
        }
        process.waitUntilExit()
        if cancelsRead, cancellation?.isCancelled == true { throw CancellationError() }
        try standardOutput.close()
        try standardError.close()

        return GitResult(
            status: process.terminationStatus,
            standardOutput: outputPipe == nil ? try Data(contentsOf: standardOutputURL) : capturedOutput,
            standardOutputExceededLimit: exceededLimit,
            standardError: String(
                decoding: try Data(contentsOf: standardErrorURL),
                as: UTF8.self
            ).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// Only for an owned, bounded read whose output we have already stopped accepting.
    /// A producer that ignores SIGTERM/SIGPIPE must not strand the worker indefinitely.
    private static func finishTerminatingLimitedRead(_ process: Process) {
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(250))
        while process.isRunning, ContinuousClock.now < deadline {
            Thread.sleep(forTimeInterval: 0.005)
        }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }
}

struct GitResult: Sendable {
    let status: Int32
    let standardOutput: Data
    let standardOutputExceededLimit: Bool
    let standardError: String
}

final class GitProcessCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    func register(_ process: Process) {
        let shouldTerminate = lock.withLock {
            guard !cancelled else { return true }
            self.process = process
            return false
        }
        if shouldTerminate, process.isRunning {
            process.terminate()
        }
    }

    func cancel() {
        let runningProcess = lock.withLock {
            cancelled = true
            return process
        }
        if runningProcess?.isRunning == true {
            runningProcess?.terminate()
        }
    }

    func clear(_ process: Process) {
        lock.withLock {
            if self.process === process {
                self.process = nil
            }
        }
    }
}
