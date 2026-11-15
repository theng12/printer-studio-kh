import Foundation
import AVFoundation

@main
struct TestVoiceClip {
    /// A silent WAV of the requested length, written by hand so the test needs
    /// no third-party tool.
    static func makeSilence(seconds: Double, rate: Double = 48000, path: String) throws {
        let frames = Int(rate * seconds)
        func le16(_ value: Int) -> Data {
            var v = UInt16(value).littleEndian
            return withUnsafeBytes(of: &v) { Data($0) }
        }
        func le32(_ value: Int) -> Data {
            var v = UInt32(value).littleEndian
            return withUnsafeBytes(of: &v) { Data($0) }
        }
        var data = Data()
        data.append("RIFF".data(using: .utf8)!)
        data.append(le32(36 + frames * 2))
        data.append("WAVEfmt ".data(using: .utf8)!)
        data.append(le32(16))
        data.append(le16(1))          // PCM
        data.append(le16(1))          // mono
        data.append(le32(Int(rate)))
        data.append(le32(Int(rate) * 2))
        data.append(le16(2))
        data.append(le16(16))
        data.append("data".data(using: .utf8)!)
        data.append(le32(frames * 2))
        data.append(Data(repeating: 0, count: frames * 2))
        try data.write(to: URL(fileURLWithPath: path))
    }

    static func duration(_ path: String) -> Double? {
        guard let file = try? AVAudioFile(forReading: URL(fileURLWithPath: path)) else { return nil }
        return Double(file.length) / file.fileFormat.sampleRate
    }

    static func main() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ps-voice-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // The limit is five seconds and the check is on real audio length, not
        // the file name or the container.
        try makeSilence(seconds: 4.9, path: dir.appendingPathComponent("short.wav").path)
        try makeSilence(seconds: 5.0, path: dir.appendingPathComponent("edge.wav").path)
        try makeSilence(seconds: 5.2, path: dir.appendingPathComponent("long.wav").path)
        try makeSilence(seconds: 60, path: dir.appendingPathComponent("verylong.wav").path)

        guard let fourPointNine = duration(dir.appendingPathComponent("short.wav").path),
              abs(fourPointNine - 4.9) < 0.1 else { fatalError("the fixture did not write what it claims") }
        print("PASS: the test fixture writes real audio at the requested length")

        // Three clips ship inside the app, one per language.
        precondition(VoiceClip.english.bundled == "printing-en")
        precondition(VoiceClip.chinese.bundled == "printing-zh")
        precondition(VoiceClip.khmer.bundled == "printing-km")
        print("PASS: three spoken clips, one per language")

        // "Sound only" and the custom slot have no bundled file.
        precondition(VoiceClip.system.bundled == nil)
        precondition(VoiceClip.custom.bundled == nil)
        precondition(VoiceClip.system.url == nil)
        print("PASS: the plain chime is not a spoken clip")

        // A stored value that no longer exists reads back as the plain chime,
        // never as a language the person did not pick.
        precondition(VoiceClip.stored(nil) == .system)
        precondition(VoiceClip.stored("nonsense") == .system)
        precondition(VoiceClip.stored("khmer") == .khmer)
        precondition(VoiceClip.stored("chinese") == .chinese)
        precondition(VoiceClip.stored("custom") == .custom)
        print("PASS: an unknown or missing choice falls back to the plain chime")

        // The replacement goes in its own folder, never over the built-in, and
        // the limit is on real audio length — it refuses rather than trims.
        // The folder is a temporary one: a test must not write into the
        // person's app support.
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("ps-home-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        precondition(VoiceClip.customURL(home: home).lastPathComponent == "printing-custom.wav")
        precondition(VoiceClip.customURL(home: home).path.hasPrefix(home.path),
                     "a recording must never land outside the chosen folder")
        print("PASS: a recording is kept in its own place and never over the built-in")

        try makeSilence(seconds: 5.2, path: dir.appendingPathComponent("over.wav").path)
        try makeSilence(seconds: 4.0, path: dir.appendingPathComponent("ok.wav").path)
        switch VoiceClip.installCustom(from: dir.appendingPathComponent("over.wav"), home: home) {
        case .success: fatalError("a 5.2 second recording was accepted")
        case let .failure(problem):
            precondition(problem.said.contains("5.2"), "the reason must say how long it was")
            print("PASS: over the limit is refused, not trimmed")
        }
        switch VoiceClip.installCustom(from: dir.appendingPathComponent("ok.wav"), home: home) {
        case .success:
            precondition(FileManager.default.fileExists(atPath: VoiceClip.customURL(home: home).path),
                         "an accepted recording must be kept")
            print("PASS: a recording under the limit is kept")
        case let .failure(problem):
            fatalError("a 4.0 second recording was refused: \(problem.said)")
        }

        try FileManager.default.removeItem(at: dir)
    }
}