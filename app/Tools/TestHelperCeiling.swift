import Foundation

#if HELPER_CEILING_TEST
/// Drives the helper's child-process ceiling without a printer, a window or the
/// daemon loop. Compiled only by test-helper-ceiling.sh with -D HELPER_CEILING_TEST,
/// so the shipped helper binary never carries this code.
func ceilingDriverMain() {
    var failures = 0
    func check(_ name: String, _ condition: @autoclosure () -> Bool) {
        if condition() {
            print("PASS: \(name)")
        } else {
            failures += 1
            print("FAIL: \(name)")
        }
    }

    let echo = run("/bin/echo", ["hello"])
    check("a quick command answers whole",
          echo.ok && echo.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "hello")

    let started = Date()
    let sleepy = run("/bin/sleep", ["30"], ceiling: 1)
    let took = Date().timeIntervalSince(started)
    check("a stuck command ends with -2", sleepy.status == -2)
    check("the outcome names the ceiling and says it was stopped",
          sleepy.stderr.contains("1 second") && sleepy.stderr.contains("stopped"))
    check("the ceiling is honoured, not waited out (\(String(format: "%.1f", took)) s)", took < 2)

    let big = run("/bin/sh",
                  ["-c", "yes x | head -c 102400 >&2; echo done"])
    check("over 64 KiB of stderr does not deadlock",
          big.ok && big.stdout.contains("done") && big.stderr.count >= 100_000)

    exit(failures == 0 ? 0 : 1)
}
#endif
