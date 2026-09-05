import Foundation

enum CommandRunner {
    static let gitURL = URL(fileURLWithPath: "/usr/bin/git")

    static func run(
        _ arguments: [String],
        executableURL: URL,
        currentDirectoryURL: URL? = nil,
        maximumOutputBytes: Int? = nil,
        standardInput: Data? = nil,
        cancellation: GitProcessCancellation? = nil,
        additionalEnvironment: [String: String] = [:]
    ) throws -> GitResult {
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
        }

        process.executableURL = executableURL
        process.currentDirectoryURL = currentDirectoryURL
        process.arguments = arguments
        process.standardInput = standardInputHandle
        process.standardOutput = standardOutput
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
        process.waitUntilExit()
        try standardOutput.close()
        try standardError.close()

        // ponytail: Git finishes writing to disk before the size cap is checked. Stream and
        // terminate the process only if large-diff latency becomes measurable.
        let outputSize = try standardOutputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let exceededLimit = maximumOutputBytes.map { outputSize > $0 } ?? false

        return GitResult(
            status: process.terminationStatus,
            standardOutput: exceededLimit ? Data() : try Data(contentsOf: standardOutputURL),
            standardOutputExceededLimit: exceededLimit,
            standardError: String(
                decoding: try Data(contentsOf: standardErrorURL),
                as: UTF8.self
            ).trimmingCharacters(in: .whitespacesAndNewlines)
        )
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
