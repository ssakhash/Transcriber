import SwiftUI
import TranscriberKit

struct TranscriptDetailView: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            if model.recoveryRequired {
                ContentUnavailableView {
                    Label("Saved Session Needs Attention", systemImage: "exclamationmark.document")
                } description: {
                    Text("The saved file is protected. Preserve a copy before starting a new session.")
                } actions: {
                    Button("Preserve Session and Start Fresh") { model.preserveSession() }
                        .buttonStyle(.glassProminent)
                }
            } else if model.session.passages.isEmpty {
                emptyTranscript
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(model.session.passages) { passage in
                            TranscriptPassageRow(model: model, passage: passage)
                        }
                    }
                    .padding(.horizontal, 28).padding(.vertical, 16)
                }
                .defaultScrollAnchor(.top)
                .accessibilityLabel("Transcript passages")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaBar(edge: .bottom, spacing: 0) {
            TranscriptStatusView(model: model)
        }
    }

    private var emptyTranscript: some View {
        ContentUnavailableView {
            Label(emptyTitle, systemImage: model.busy ? "waveform" : "text.document")
        } description: {
            Text(emptyDescription)
        } actions: {
            if !model.hasVideo && !model.busy && !model.loading {
                Button(model.session.sourceName.isEmpty ? "Open Video" : "Locate Original Video", systemImage: "folder") {
                    model.chooseVideo(relink: !model.session.sourceName.isEmpty)
                }
                .buttonStyle(.glassProminent)
            }
        }
    }

    private var emptyTitle: String {
        if model.loading { return "Opening Video" }
        if model.busy { return "Transcribing Your Video" }
        if model.session.state == .complete { return "No Speech Detected" }
        if model.session.state == .failed { return "Transcription Stopped" }
        if model.session.state == .interrupted { return "Transcription Incomplete" }
        return model.hasVideo ? "Ready to Transcribe" : "Open a Video to Get Started"
    }

    private var emptyDescription: String {
        if model.busy { return "Completed passages will appear here. You can edit and label speakers when transcription finishes." }
        if model.session.state == .complete { return "No English speech was detected. Open another video or try a different audio track." }
        if model.session.state == .failed || model.session.state == .interrupted { return "No completed passages were received. Use Transcribe to restart when ready." }
        return model.hasVideo ? "Choose Transcribe in the toolbar to process the selected audio track on this Mac." : "Choose an MP4 or drop one into this window to create an editable English transcript."
    }
}
