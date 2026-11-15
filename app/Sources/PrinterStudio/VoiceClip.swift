import Foundation
import AVFoundation

/// The announcement that plays when a job reaches the Mac.
///
/// Three clips ship inside the app, made with the local VoxCPM2 model on the
/// studio's own Gateway (free, 1.12 s each). The person can replace the chosen
/// one with a recording of their own; it is kept in app support rather than
/// over the built-in, so a bad file never breaks the built-in.
enum VoiceClip: String, CaseIterable, Identifiable {
    /// Kept for installs that used the sound-only version. The switch that
    /// enables the whole thing is separate, and starts off.
    case system, english, khmer, chinese, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Sound only"
        case .english: return "English"
        case .khmer: return "Khmer"
        case .chinese: return "Chinese"
        case .custom: return "My own recording"
        }
    }

    /// The bundled file for a built-in clip. WAV, 48 kHz mono.
    var bundled: String? {
        switch self {
        case .english: return "printing-en"
        case .khmer: return "printing-km"
        case .chinese: return "printing-zh"
        default: return nil
        }
    }

    /// Where a replacement recording is kept. A parameter rather than a read of
    /// the environment: Foundation caches the home directory at first use, so a
    /// test that sets HOME would otherwise write into the real folder.
    static func customURL(home: URL? = nil) -> URL {
        let base = home ?? FileManager.default.homeDirectoryForCurrentUser
        return base
            .appendingPathComponent("Library/Application Support/PrinterStudio/printing-custom.wav")
    }

    /// The file to play, or nil when the person chose the plain chime.
    var url: URL? {
        if self == .custom, FileManager.default.fileExists(atPath: VoiceClip.customURL().path) { return VoiceClip.customURL() }
        guard let name = bundled, let sound = Bundle.main.url(forResource: name, withExtension: "wav") else {
            return nil
        }
        return sound
    }

    /// A custom recording must be short enough to finish before the next page
    /// starts. Anything longer is refused, never silently trimmed.
    static let maxCustomSeconds: Double = 5

    /// Accepts a recording and keeps it as the chosen clip. Refuses anything
    /// longer than five seconds, or anything macOS cannot read as audio.
    static func installCustom(from source: URL, home: URL? = nil) -> Result<Void, InstallProblem> {
        guard let audio = try? AVAudioFile(forReading: source) else {
            return .failure(.message("macOS could not read that file as audio."))
        }
        let seconds = Double(audio.length) / audio.fileFormat.sampleRate
        guard seconds.isFinite, seconds > 0 else { return .failure(.message("That file has no sound in it.")) }
        guard seconds <= maxCustomSeconds else {
            return .failure(.message("That recording is \(String(format: "%.1f", seconds)) seconds. It has to be \(Int(maxCustomSeconds)) or less."))
        }
        let destination = VoiceClip.customURL(home: home)
        do {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            return .failure(.message("Could not keep that recording: \(error.localizedDescription)"))
        }
        return .success(())
    }

    static func stored(_ raw: String?) -> VoiceClip {
        VoiceClip(rawValue: raw ?? "") ?? .system
    }

    /// The plain chime, kept for people who never turned the switch on and for
    /// the system choice.
    static let chimeName = "Glass"
}

/// Why a recording was refused. Carries the sentence shown to the person.
enum InstallProblem: Error {
    case message(String)

    var said: String {
        switch self {
        case let .message(text): return text
        }
    }
}