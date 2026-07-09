import Foundation
import AVFoundation

/// Writes tapped PCM buffers to an AAC `.m4a` file alongside transcription (P17).
/// Lazily initialises the file from the FIRST buffer's format so sample rate and
/// channel count always match (no conversion, no guessing). Best-effort by design:
/// any write failure disables the writer for the rest of the session rather than
/// crashing or interrupting the recording — audio retention must never break capture.
actor AudioFileWriter {
    private let url: URL
    private var file: AVAudioFile?
    private var failed = false
    private var closed = false
    private(set) var wroteAnything = false

    init(url: URL) { self.url = url }

    func write(_ buffer: AVAudioPCMBuffer) {
        guard !failed, !closed else { return }
        do {
            let file = try fileForWriting(matching: buffer)
            try file.write(from: buffer)
            wroteAnything = true
        } catch {
            failed = true
            #if DEBUG
            print("[EchoMind][AudioFileWriter] write failed, retention off for this session: \(error)")
            #endif
        }
    }

    /// Finalises the file. Returns true if audio was actually captured. If nothing
    /// was written (or writing failed), removes any empty/partial file.
    func finish() -> Bool {
        let ok = wroteAnything && !failed
        closed = true
        file = nil               // releasing the AVAudioFile flushes + closes it
        if !ok { try? FileManager.default.removeItem(at: url) }
        return ok
    }

    private func fileForWriting(matching buffer: AVAudioPCMBuffer) throws -> AVAudioFile {
        if let file { return file }
        let format = buffer.format
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        let created = try AVAudioFile(forWriting: url, settings: settings,
                                      commonFormat: format.commonFormat,
                                      interleaved: format.isInterleaved)
        // Protect the recording at rest. Directory-level protection doesn't inherit to
        // files created inside it on iOS, so set it explicitly. `.completeUnlessOpen`
        // matches the database + audio directory: encrypted when the device locks, but
        // a file already open (this in-progress recording) keeps working past lock.
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: url.path)
        file = created
        return created
    }
}
