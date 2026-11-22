import Foundation

#if HELPER_CEILING_TEST
/// Drives the helper's child-process ceiling without a printer, a window or the
/// daemon loop. Compiled only by test-helper-ceiling.sh with -D HELPER_CEILING_TEST,
/// so the shipped helper binary never carries this code.
func ceilingDriverMain() {
    // The termination path, isolated: park with the helper's own handlers and
    // let the shell send SIGTERM. No services, no data, no printer.
    if ProcessInfo.processInfo.environment["PRINTER_STUDIO_TERM_DRIVER"] == "1" {
        signal(SIGTERM, handleTermination)
        signal(SIGINT, handleTermination)
        while true { Thread.sleep(forTimeInterval: 0.05) }
    }
    var failures = 0
    func check(_ name: String, _ condition: @autoclosure () -> Bool) {
        if condition() {
            print("PASS: \(name)")
        } else {
            failures += 1
            print("FAIL: \(name)")
        }
    }

    // The intended bounds, asserted from source rather than discovered by waiting 30 s.
    check("status ceiling is the intended 30 s", statusCeiling == 30)
    check("change ceiling is the intended 60 s", changeCeiling == 60)
    check("DNS-SD ceiling is the intended 2 s", dnssdCeiling == 2)

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
