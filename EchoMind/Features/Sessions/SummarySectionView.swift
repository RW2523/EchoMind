import SwiftUI

/// Structured summary + Generate/Regenerate, or a Tier B explanation (§5.6).
struct SummarySectionView: View {
    let model: SessionDetailViewModel

    var body: some View {
        Section("Summary") {
            switch model.summaryState {
            case .none:
                Button { Task { await model.generateSummary() } } label: {
                    Label("Generate Summary", systemImage: "sparkles")
                }
            case .generating(let progress):
                HStack(spacing: 10) {
                    ProgressView()
                    Text(text(for: progress)).foregroundStyle(.secondary)
                }
            case .available(let summary):
                content(summary)
                Button { Task { await model.generateSummary() } } label: {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                }
            case .failed(let message):
                Text(message).foregroundStyle(.red)
                Button("Try Again") { Task { await model.generateSummary() } }
            case .requiresAppleIntelligence(let reason):
                requiresAppleIntelligence(reason)
            }
        }
    }

    // MARK: - Structured summary

    @ViewBuilder private func content(_ summary: MeetingSummary) -> some View {
        if !model.continuityNotes.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("Continuing from earlier meetings", systemImage: "arrow.triangle.branch")
                    .font(.subheadline.bold())
                    .foregroundStyle(DS.brand)
                ForEach(model.continuityNotes, id: \.self) { note in
                    HStack(alignment: .top, spacing: 6) { Text("•"); Text(note) }
                }
            }
            .padding(DS.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.brand.opacity(0.08), in: RoundedRectangle(cornerRadius: DS.rSm, style: .continuous))
        }
        if !summary.overview.isEmpty {
            Text(summary.overview)
        }
        group("Key Decisions", summary.keyDecisions)
        if !summary.actionItems.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Action Items").font(.subheadline.bold())
                ForEach(Array(summary.actionItems.enumerated()), id: \.offset) { index, item in
                    let done = index < model.actionStates.count && model.actionStates[index]
                    Button {
                        model.toggleAction(index)
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(done ? DS.brand : .secondary)
                            Text(item.text)
                                .strikethrough(done, color: .secondary)
                                .foregroundStyle(done ? .secondary : .primary)
                            if let owner = item.owner, !owner.isEmpty {
                                Text(owner).font(.caption).padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(DS.brand.opacity(0.15), in: Capsule())
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)
                    .animation(DS.bouncy, value: done)
                }
            }
        }
        group("Risks", summary.risks)
        group("Open Questions", summary.openQuestions)
    }

    @ViewBuilder private func group(_ title: String, _ items: [String]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.bold())
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 6) { Text("•"); Text(item) }
                }
            }
        }
    }

    // MARK: - Tier B

    @ViewBuilder private func requiresAppleIntelligence(_ reason: AvailabilityStatus.TierBReason) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Requires Apple Intelligence", systemImage: "sparkles")
                .font(.subheadline.bold())
            Text(reasonCopy(reason)).font(.callout).foregroundStyle(.secondary)
            Text("Transcription, sessions, and export still work.")
                .font(.caption).foregroundStyle(.tertiary)
        }
    }

    private func reasonCopy(_ reason: AvailabilityStatus.TierBReason) -> String {
        switch reason {
        case .deviceNotEligible: return "This iPhone doesn't support Apple Intelligence."
        case .appleIntelligenceNotEnabled: return "Enable Apple Intelligence in iOS Settings to generate summaries."
        case .modelNotReady: return "The on-device model is still preparing. Try again shortly."
        case .unknown: return "Summaries aren't available right now."
        }
    }

    private func text(for progress: SummarizerProgress) -> String {
        switch progress {
        case .planning: return "Planning…"
        case .mapping(let window, let total): return "Summarizing part \(window) of \(total)…"
        case .reducing: return "Finishing summary…"
        }
    }
}
