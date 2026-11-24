import Foundation

/// Taking the app off this Mac is the one destructive thing it can do. The button in
/// Settings asks first, but a confirmation that lives only in the view protects nothing:
/// any other path into `AppState.removeEverything()` — a menu item, a shortcut, a script,
/// a route added later — would run it straight past the question.
///
/// So the command path asks too, and the authorisation is a value with two properties: it
/// is consumed by the attempt that uses it, and it expires. A stale or missing token is a
/// refusal with a sentence the person can act on, never a quiet success.
enum RemovalGuard {
    static let window: TimeInterval = 120

    /// Issued by the confirmation, and by nothing else.
    struct Authorisation: Equatable {
        let issued: Date
    }

    static func issue(now: Date = Date()) -> Authorisation {
        Authorisation(issued: now)
    }

    /// True only for a token that exists and is still inside its window.
    static func permits(_ token: Authorisation?, now: Date = Date()) -> Bool {
        guard let token else { return false }
        let age = now.timeIntervalSince(token.issued)
        return age >= 0 && age <= window
    }
}
