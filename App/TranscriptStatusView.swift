import SwiftUI
import TranscriberKit

struct TranscriptStatusView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error = model.saveError {
                StatusMessage(text: error, isError: true) {
                    Button("Retry") { model.retrySave() }.buttonStyle(.glass)
                        .accessibilityLabel("Retry saving session")
                }
            }
            if let notice = model.notice {
                StatusMessage(text: notice, isError: model.noticeIsError) {
                    Button("Dismiss Message", systemImage: "xmark") { model.notice = nil }
                        .labelStyle(.iconOnly).buttonStyle(.borderless)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) { status; Spacer(minLength: 8); counts; exportState }
                VStack(alignment: .leading, spacing: 5) {
                    HStack { status; Spacer(); exportState }
                    counts
                }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    private var status: some View {
        Label(statusTitle, systemImage: statusSymbol).lineLimit(1)
            .help(model.busy ? model.phase : "Transcription status. Session changes are saved automatically on this Mac.")
    }

    private var statusTitle: String {
        if model.recoveryRequired { return "Session needs attention" }
        if model.loading { return "Opening" }
        if model.cancelling { return "Cancelling" }
        if model.busy { return "Transcribing" }
        switch model.session.state {
        case .ready: return "Ready"
        case .complete: return "Complete"
        case .transcribing, .interrupted, .failed: return "Incomplete"
        }
    }

    private var statusSymbol: String {
        if model.recoveryRequired { return "exclamationmark.triangle" }
        if model.busy || model.loading { return "waveform" }
        if model.session.state == .complete { return "checkmark.circle" }
        if model.session.state != .ready { return "circle.lefthalf.filled" }
        return "text.document"
    }

    private var counts: some View {
        Text("\(model.wordCount) words · \(model.session.passages.count) passages")
            .monospacedDigit().fixedSize()
    }

    @ViewBuilder private var exportState: some View {
        if !model.session.passages.isEmpty {
            Text(model.session.hasUnexportedWork ? "Not exported" : "Exported")
                .fixedSize().help("Copying does not count as saving a text file.")
        }
    }
}

private struct StatusMessage<Action: View>: View {
    let text: String
    let isError: Bool
    @ViewBuilder let action: () -> Action

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isError ? "exclamationmark.triangle" : "info.circle")
                .foregroundStyle(isError ? Color.orange : Color.secondary)
                .accessibilityHidden(true)
            Text(text).font(.callout).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            action()
        }
        .accessibilityElement(children: .contain)
    }
}
