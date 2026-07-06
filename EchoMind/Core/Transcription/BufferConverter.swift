import Foundation
import AVFoundation

nonisolated enum BufferConversionError: Error, Equatable {
    case converterUnavailable
    case allocationFailed
    case conversionFailed(String)
}

/// Wraps `AVAudioConverter` to bridge the tap format to the analyzer's required
/// format (§3.3). Format-pair specific: on an input-format change (route change)
/// the converter is discarded and rebuilt, so the analyzer sees one continuous,
/// constant-format stream. Not Sendable — used inside the transcriber actor.
nonisolated final class BufferConverter {
    private let targetFormat: AVAudioFormat
    private var converter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?

    init(targetFormat: AVAudioFormat) {
        self.targetFormat = targetFormat
    }

    func convert(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        let inputFormat = buffer.format
        if converter == nil || sourceFormat != inputFormat {
            converter = AVAudioConverter(from: inputFormat, to: targetFormat)
            sourceFormat = inputFormat
        }
        guard let converter else { throw BufferConversionError.converterUnavailable }

        if inputFormat == targetFormat { return buffer }

        let ratio = targetFormat.sampleRate / inputFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            throw BufferConversionError.allocationFailed
        }

        var consumed = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }

        if let conversionError {
            throw BufferConversionError.conversionFailed(conversionError.localizedDescription)
        }
        if status == .error {
            throw BufferConversionError.conversionFailed("converter returned .error")
        }
        return output
    }
}
