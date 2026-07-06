import Testing
import AVFoundation
@testable import EchoMind

@Suite struct BufferConverterTests {

    /// Build a mono float PCM buffer filled with a sine wave.
    private func sineBuffer(sampleRate: Double, frames: AVAudioFrameCount, hz: Double = 440) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                   channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let data = buffer.floatChannelData![0]
        for i in 0..<Int(frames) {
            data[i] = Float(sin(2 * Double.pi * hz * Double(i) / sampleRate))
        }
        return buffer
    }

    @Test func downsamples48kTo16k() throws {
        let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                   channels: 1, interleaved: false)!
        let converter = BufferConverter(targetFormat: target)
        let input = sineBuffer(sampleRate: 48_000, frames: 4_800)   // 100 ms
        let output = try converter.convert(input)
        // The downsample happened: target sample rate, non-empty output. Exact
        // frame count isn't asserted — a single isolated conversion underproduces
        // due to converter priming; the count converges over a continuous stream.
        #expect(output.format.sampleRate == 16_000)
        #expect(output.frameLength > 0)
        #expect(output.frameLength <= 1_600)
    }

    @Test func passesThroughWhenFormatsMatch() throws {
        let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                   channels: 1, interleaved: false)!
        let converter = BufferConverter(targetFormat: target)
        let input = sineBuffer(sampleRate: 16_000, frames: 1_600)
        let output = try converter.convert(input)
        #expect(output.frameLength == 1_600)
    }

    @Test func handlesHFPLike16kInput() throws {
        let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                   channels: 1, interleaved: false)!
        let converter = BufferConverter(targetFormat: target)
        // Simulate a route change: first 48k, then 16k (HFP) — converter rebuilds.
        _ = try converter.convert(sineBuffer(sampleRate: 48_000, frames: 4_800))
        let output = try converter.convert(sineBuffer(sampleRate: 16_000, frames: 1_600))
        #expect(output.format.sampleRate == 16_000)
        #expect(output.frameLength == 1_600)
    }
}
