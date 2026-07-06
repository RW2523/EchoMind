import Foundation
import CoreTransferable
import UniformTypeIdentifiers

/// Pure formatting for session export (§4.2). Timestamps are zero-padded
/// HH:MM:SS offsets from session start; format is golden-tested.
nonisolated enum SessionExporter {
    static func markdown(session: SessionSnapshot, segments: [SegmentSnapshot]) -> String {
        var lines = ["# \(session.title)", ""]
        lines.append("**Date:** \(dateText(session.createdAt))")
        lines.append("**Duration:** \(durationText(session.duration))")
        lines.append("")
        lines.append("## Transcript")
        lines.append("")
        for segment in segments.sorted(by: { $0.startTime < $1.startTime }) {
            lines.append("**[\(timestamp(segment.startTime))]** \(segment.text)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func plainText(session: SessionSnapshot, segments: [SegmentSnapshot]) -> String {
        var lines = [session.title]
        lines.append("Date: \(dateText(session.createdAt))")
        lines.append("Duration: \(durationText(session.duration))")
        lines.append("")
        for segment in segments.sorted(by: { $0.startTime < $1.startTime }) {
            lines.append("[\(timestamp(segment.startTime))] \(segment.text)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func temporaryFileURL(contents: String, fileName: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EchoMindExport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(fileName)
        try contents.data(using: .utf8)?.write(to: url)
        return url
    }

    // MARK: - Formatting

    static func timestamp(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    static func durationText(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let hours = total / 3600, minutes = (total % 3600) / 60, seconds = total % 60
        if hours > 0 { return "\(hours)h \(minutes)m \(seconds)s" }
        if minutes > 0 { return "\(minutes)m \(seconds)s" }
        return "\(seconds)s"
    }

    static func dateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }

    static func dateText(_ date: Date) -> String { dateFormatter().string(from: date) }

    static func sanitizedFileName(_ title: String, ext: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = title.components(separatedBy: invalid).joined(separator: "-")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(trimmed.isEmpty ? "Session" : trimmed).\(ext)"
    }
}

/// Lazy file export for ShareLink — formats + writes the temp file only when the
/// user actually shares (§4.2).
nonisolated struct SessionExport: Transferable {
    let fileName: String
    let contents: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { export in
            SentTransferredFile(try SessionExporter.temporaryFileURL(contents: export.contents,
                                                                     fileName: export.fileName))
        }
    }
}
