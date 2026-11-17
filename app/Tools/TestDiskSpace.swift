import Foundation

/// Checks that a full disk fails with the number, using a real nearly-full
/// volume when one is given as the first argument.
@main
struct TestDiskSpace {
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
        let full = DiskSpace.explain("cp: /tmp/x: No space left on device", freeBytes: 812_000_000)
        check("a full disk keeps the reason and names the free space",
              full.contains("No space left on device") && full.hasSuffix("free.") && full.contains("MB"))

        check("the wording macOS uses in any case is recognised",
              DiskSpace.explain("cp: no space left on device", freeBytes: 1_000)
                  .hasSuffix("1 KB free."))

        let other = "lpadmin: The printer or class does not exist."
        check("a different failure is left alone",
              DiskSpace.explain(other, freeBytes: 812_000_000) == other)

        check("an unreadable free space is left alone",
              DiskSpace.explain("No space left on device", freeBytes: nil) == "No space left on device")

        if CommandLine.arguments.count > 1 {
            let volume = CommandLine.arguments[1]
            let result = Shell.run("/bin/dd", ["if=/dev/zero", "of=\(volume)/overflow",
                                               "bs=1024", "count=5000"], timeout: 60)
            check("the real full volume refuses the write with the OS wording",
                  !result.ok && result.stderr.lowercased().contains("no space left on device"))

            let message = DiskSpace.explain(result.stderr, freeBytes: DiskSpace.freeBytes(at: volume))
            print("  message: \(message.replacingOccurrences(of: "\n", with: " | "))")
            check("the real failure names the free space", message.hasSuffix("free."))
        }

        exit(failures == 0 ? 0 : 1)
    }
}
