import Foundation

// The ONLY file that touches the FluidAudio package. Compiled solely when the
// package is linked (`#if canImport(FluidAudio)`), so the app builds/tests without
// it; adding it lights this up. Audio decode/resample to 16 kHz mono is done here
// (correct regardless of the package); the diarization call + result shape are the
// single reconciliation point if the FluidAudio API has drifted.
//
// Add in Xcode: File ▸ Add Package Dependencies… ▸
//   https://github.com/FluidInference/FluidAudio

#if canImport(FluidAudio)
import FluidAudio
import AVFoundation

actor FluidAudioDiarizer: DiarizationService {
    nonisolated var isAvailable: Bool { true }
    private var manager: DiarizerManager?

    func diarize(audioURL: URL) async throws -> DiarizationResult {
        let samples = try Self.loadMono16k(audioURL)
        guard !samples.isEmpty else { return .empty }
        let manager = try await ensureManager()
        do {
            let raw = try await manager.performCompleteDiarization(samples, sampleRate: 16_000)
            return DiarizationResult(segments: Self.normalize(raw.segments))
        } catch {
            throw DiarizationError.failed(String(describing: error))
        }
    }

    private func ensureManager() async throws -> DiarizerManager {
        if let manager { return manager }
        let created = DiarizerManager()
        try await created.initialize()      // loads/downloads the Core ML models
        manager = created
        return created
    }

    /// Remap raw speaker ids to stable "Speaker N" labels in order of first
    /// appearance. FIXME(package): field names (`speakerId`/`startTimeSeconds`/
    /// `endTimeSeconds`) assume the current FluidAudio `TimedSpeakerSegment`; adjust
    /// here if the installed version differs — this is the one place to reconcile.
    private static func normalize(_ segments: [TimedSpeakerSegment]) -> [SpeakerSegment] {
        var order: [String: Int] = [:]
        var out: [SpeakerSegment] = []
        for segment in segments {
            let raw = String(describing: segment.speakerId)
            if order[raw] == nil { order[raw] = order.count + 1 }
            out.append(SpeakerSegment(speaker: "Speaker \(order[raw] ?? 1)",
                                      start: TimeInterval(segment.startTimeSeconds),
                                      end: TimeInterval(segment.endTimeSeconds)))
        }
        return out
    }

    /// Decode any audio file to 16 kHz mono float samples (FluidAudio's input format).
    private static func loadMono16k(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let inFormat = file.processingFormat
        guard let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                            channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inFormat, to: outFormat) else {
            throw DiarizationError.audioUnreadable
        }
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0,
              let input = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: frames) else {
            throw DiarizationError.audioUnreadable
        }
        try file.read(into: input)

        let capacity = AVAudioFrameCount(Double(frames) * 16_000 / inFormat.sampleRate) + 1_024
        guard let output = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else {
            throw DiarizationError.audioUnreadable
        }
        var consumed = false
        var convError: NSError?
        _ = converter.convert(to: output, error: &convError) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true
            status.pointee = .haveData
            return input
        }
        if let convError { throw DiarizationError.failed(convError.localizedDescription) }
        guard let channel = output.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }
}
#endif
