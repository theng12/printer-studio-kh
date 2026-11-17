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

        exit(failures == 0 ? 0 : 1)
    }
}
