import Foundation

@main
struct TestJobWatch {
    static func main() {
        // `lpstat -W not-completed` prints the job id first.
        let lines = [
            "Brother_HL_L2370DN_series-64 vengtheng 488448 Sun Nov 15 14:34:05 2026",
            "Brother_HL_L2370DN_series-65 someone 1024 Sun Nov 15 14:35:00 2026",
        ]
        precondition(JobWatch.ids(lines) == ["Brother_HL_L2370DN_series-64", "Brother_HL_L2370DN_series-65"])
        print("PASS: job ids come from the first field of each lpstat line")

        // What was already queued before the watch started is not news.
        precondition(JobWatch.newIDs(previous: [], current: lines, firstLook: true).isEmpty)
        print("PASS: the first look is silent")

        // A job that was not there before is news.
        let previous: Set<String> = ["Brother_HL_L2370DN_series-64"]
        precondition(JobWatch.newIDs(previous: previous, current: lines, firstLook: false)
                     == ["Brother_HL_L2370DN_series-65"])
        print("PASS: a newly arrived job is reported")

        // Nothing new, nothing said — the chime must not repeat every two seconds.
        precondition(JobWatch.newIDs(previous: JobWatch.ids(lines), current: lines, firstLook: false).isEmpty)
        print("PASS: an unchanged queue stays silent")

        // A job that finished and left the queue is not a new job.
        precondition(JobWatch.newIDs(previous: JobWatch.ids(lines), current: [lines[0]], firstLook: false).isEmpty)
        print("PASS: a job leaving the queue is not reported as new")

        // Blank output must not read as a job.
        precondition(JobWatch.ids([""]).isEmpty)
        precondition(JobWatch.newIDs(previous: [], current: [""], firstLook: false).isEmpty)
        print("PASS: blank output is not a job")
    }
}
