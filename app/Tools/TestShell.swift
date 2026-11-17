import Foundation

/// Checks that a command can never hang an action: it answers, it fails with its
/// own reason, or it is stopped at its own ceiling and says so. Also checks that
/// a large stderr no longer deadlocks the reader.
@main
struct TestShell {
    static var failures = 0

    static func check(_ name: String, _ condition: @autoclosure () -> Bool) {
        if condition() {
            print("PASS: \(name)")
        } else {
            failures += 1
            print("FAIL: \(name)")
        }
    }

    static func main() {
        let echo = Shell.run("/bin/echo", ["hello"])
        check("a quick command answers whole",
              echo.ok && echo.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "hello")

        let failing = Shell.run("/bin/sh", ["-c", "echo out; echo err >&2; exit 3"])
        check("a failing command keeps its status and both streams",
              failing.status == 3 && failing.stdout.contains("out") && failing.stderr.contains("err"))

        let started = Date()
        let sleepy = Shell.run("/bin/sleep", ["30"], timeout: 1)
        let took = Date().timeIntervalSince(started)
        check("a stuck command ends with -2", sleepy.status == -2)
        check("the failure names the ceiling and that it was stopped",
              sleepy.stderr.contains("1 second") && sleepy.stderr.contains("stopped"))
        check("the ceiling is honoured, not waited out (\(String(format: "%.1f", took)) s)", took < 6)

        let big = Shell.run("/bin/sh",
                            ["-c", "dd if=/dev/zero bs=1024 count=200 2>/dev/null | tr '\\0' x >&2; echo done"],
                            timeout: 20)
        check("200 KB of stderr is read without deadlock",
              big.ok && big.stdout.contains("done") && big.stderr.count >= 200_000)

        let missing = Shell.run("/no/such/tool")
        check("a missing tool is named",
              missing.status == -1 && missing.stderr.contains("Missing tool"))

        // A cancel from outside stops a long command well inside its ceiling,
        // with an outcome distinct from both success and the ceiling stop.
        let token = ShellCancel()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
            token.cancel()
        }
        let startedCancel = Date()
        let cancelled = Shell.run("/bin/sleep", ["30"], timeout: 20, cancel: token)
        let cancelTook = Date().timeIntervalSince(startedCancel)
        check("a cancelled command ends with its own status -3", cancelled.status == -3)
        check("the cancelled outcome says it was cancelled",
              cancelled.stderr.contains("was cancelled"))
        check("a cancelled outcome is not the ceiling outcome",
              !cancelled.stderr.contains("took longer than"))
        check("cancel is honoured well inside the ceiling (\(String(format: "%.1f", cancelTook)) s)", cancelTook < 6)

        // A cancel with nothing running is refused in plain words.
        let refused = Shell.cancelCurrent()
        check("a cancel with nothing running is refused in plain words",
              refused?.contains("Nothing is running") == true)

        // The path a real action takes: `perform` opens a scope and the inner
        // run() callers pass no handle, so Escape must reach them through the
        // scope — and they must say cancelled, not "took too long".
        let scoped = ShellCancel()
        Shell.beginCancelScope(scoped)
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
            _ = Shell.cancelCurrent()
        }
        let startedScoped = Date()
        let inner = Shell.run("/bin/sleep", ["30"], timeout: 20)
        let scopedTook = Date().timeIntervalSince(startedScoped)
        Shell.endCancelScope(scoped)
        check("a run with no handle is cancelled by the action's scope", inner.status == -3)
        check("the scoped cancel says it was cancelled, not that it timed out",
              inner.stderr.contains("was cancelled") && !inner.stderr.contains("took longer than"))
        check("the scoped cancel lands well inside the ceiling (\(String(format: "%.1f", scopedTook)) s)", scopedTook < 6)

        exit(failures == 0 ? 0 : 1)
    }
}
