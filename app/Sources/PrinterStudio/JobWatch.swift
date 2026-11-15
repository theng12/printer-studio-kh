import Foundation

/// Spots a job that appeared since the last look. Pure, so the rule that decides
/// whether to chime can be tested without a timer or a printer.
enum JobWatch {
    /// `lpstat -W not-completed` prints one line per job, id first.
    static func ids(_ jobs: [String]) -> Set<String> {
        Set(jobs.compactMap { $0.split(separator: " ").first.map(String.init) })
    }

    /// Empty on the first look: jobs already queued before the watch started are
    /// not news, and chiming for them would be a lie about what just arrived.
    /// `current` is nil when the queue could not be read at all — that says
    /// nothing about what is queued, so it announces nothing.
    static func newIDs(previous: Set<String>, current: [String]?, firstLook: Bool) -> [String] {
        guard !firstLook, let current else { return [] }
        return ids(current).subtracting(previous).sorted()
    }
}
