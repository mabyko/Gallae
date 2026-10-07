import AppKit
import Darwin
import Foundation

@MainActor
final class GallaeAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        CommandProcessRegistry.shared.shutdown()
    }
}

/// Track commands from launch until exit, including Git's transport and hook helpers.
final class CommandProcessRegistry: @unchecked Sendable {
    static let shared = CommandProcessRegistry()

    private struct Command {
        let process: Process
        let group: pid_t?

        var isRunning: Bool {
            if let group { return kill(-group, 0) == 0 }
            return process.isRunning
        }

        func signal(_ signal: Int32) {
            if let group {
                kill(-group, signal)
            } else if process.isRunning {
                kill(process.processIdentifier, signal)
            }
        }
    }

    private let lock = NSLock()
    private var commands: [ObjectIdentifier: Command] = [:]
    private var isShuttingDown = false

    func launch(_ process: Process) throws {
        try lock.withLock {
            guard !isShuttingDown else { throw CancellationError() }
            // Launch and registration are atomic with respect to shutdown.
            try process.run()
            let pid = process.processIdentifier
            // Foundation isolates each Process in its own group. Verify before signaling a group;
            // never send a signal to the app's or the user's shell's shared process group.
            commands[ObjectIdentifier(process)] = Command(process: process, group: getpgid(pid) == pid ? pid : nil)
        }
    }

    func cancel(_ process: Process) {
        let command = lock.withLock { commands[ObjectIdentifier(process)] }
        command?.signal(SIGTERM)
    }

    func finish(_ process: Process) {
        let command = lock.withLock { commands.removeValue(forKey: ObjectIdentifier(process)) }
        // A hook can exit before its helper. Do not leave that helper behind after command completion.
        if let command { stop([command]) }
    }

    func shutdown() {
        let running = lock.withLock {
            isShuttingDown = true
            return Array(commands.values)
        }
        stop(running)
    }

    private func stop(_ commands: [Command]) {
        for command in commands { command.signal(SIGTERM) }
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(250))
        while commands.contains(where: \.isRunning), ContinuousClock.now < deadline {
            Thread.sleep(forTimeInterval: 0.005)
        }
        // Only our tracked, isolated commands/helpers. An unresponsive hook cannot outlive Quit.
        for command in commands where command.isRunning { command.signal(SIGKILL) }
    }
}
