#!/usr/bin/env python3
"""Exercise CommandRunner through normal AppKit termination in an isolated process."""

import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time


def is_running(pid):
    result = subprocess.run(
        ["/bin/ps", "-p", str(pid), "-o", "stat="], capture_output=True, text=True
    )
    return result.returncode == 0 and not result.stdout.strip().startswith("Z")


def main():
    repository = Path(__file__).resolve().parent.parent
    with tempfile.TemporaryDirectory(prefix="GallaeQuitRegression-") as directory:
        root = Path(directory)
        stub = root / "Stub.swift"
        stub.write_text("enum RepositoryInspectionError: Error { case gitUnavailable }\n")
        harness = root / "main.swift"
        lifecycle = repository / "Gallae/AppLifecycle.swift"
        delegate = "let delegate = MainActor.assumeIsolated { GallaeAppDelegate() }; app.delegate = delegate" if lifecycle.exists() else ""
        harness.write_text("""import AppKit
import Foundation

let marker = CommandLine.arguments[1]
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
DELEGATE
DispatchQueue.global().async {
    // The parent deliberately ignores TERM, as a hook/helper can. Both it and its child must exit.
    _ = try? CommandRunner.run(["-c", "trap '' TERM; /bin/sleep 60 & echo $$ $! > \\\"$1\\\"; wait", "fixture", marker],
                              executableURL: URL(fileURLWithPath: "/bin/sh"))
}
Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { timer in
    guard FileManager.default.fileExists(atPath: marker) else { return }
    timer.invalidate()
    app.terminate(nil)
}
app.run()
""".replace("DELEGATE", delegate))
        sources = [repository / "Gallae/CommandRunner.swift", stub, harness]
        if lifecycle.exists():
            sources.append(lifecycle)
        executable = root / "quit-harness"
        subprocess.run(["xcrun", "swiftc", *map(str, sources), "-o", str(executable)], check=True)
        marker = root / "children.pid"
        app = subprocess.Popen([str(executable), str(marker)], stdout=subprocess.DEVNULL)
        children = []
        try:
            app.wait(timeout=10)
            children = list(map(int, marker.read_text().split()))
            deadline = time.monotonic() + 2
            while any(is_running(pid) for pid in children) and time.monotonic() < deadline:
                time.sleep(0.02)
            remaining = [pid for pid in children if is_running(pid)]
            assert app.returncode == 0, f"App exited with {app.returncode}"
            assert not remaining, f"FAIL: commands/helpers survived normal app quit: {remaining}"
            print("PASS: normal app quit stops the command and its helper, including a TERM-ignoring parent")
        finally:
            if marker.exists() and not children:
                children = list(map(int, marker.read_text().split()))
            # Only this test's newly created fixtures, never installed/running user apps.
            for pid in children:
                if is_running(pid):
                    try:
                        os.kill(pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
            if app.poll() is None:
                app.terminate()
                app.wait(timeout=5)


if __name__ == "__main__":
    main()
