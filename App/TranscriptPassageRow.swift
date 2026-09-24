import SwiftUI
import TranscriberKit

struct TranscriptPassageRow: View {
    @Bindable var model: AppModel
    let passage: Passage

    private var isCurrent: Bool { model.activePassage == passage.id && model.hasVideo }
    private var speakerName: String {
        model.session.speakers.first(where: { $0.id == passage.speakerID })?.name ?? "Assign Speaker"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Capsule().fill(Color.accentColor)
                .frame(width: 3, height: 20).opacity(isCurrent ? 1 : 0)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Button { model.seek(passage.start) } label: {
                        Label(TextPolicy.timestamp(passage.start), systemImage: isCurrent ? "play.fill" : "play")
                            .font(.caption.monospacedDigit())
                    }
                    .buttonStyle(.borderless).disabled(!model.hasVideo)
                    .help("Play from this passage")
                    .accessibilityLabel("Seek to \(TextPolicy.timestamp(passage.start))")
                    .accessibilityValue(isCurrent ? "Current passage" : "")
                    Menu {
                        Button("Unassigned") { model.assign(passage.id, speaker: nil) }
                        ForEach(model.session.speakers) { speaker in
                            Button(speaker.name) { model.assign(passage.id, speaker: speaker.id) }
                        }
                        Divider()
                        Button("Add a Speaker", systemImage: "person.badge.plus") { model.addSpeaker() }
                    } label: {
                        Text(speakerName).font(.callout)
                            .foregroundStyle(passage.speakerID == nil ? .secondary : .primary)
                            .lineLimit(1).truncationMode(.tail)
                    }
                    .menuStyle(.borderlessButton).frame(maxWidth: 220, alignment: .leading)
                    .disabled(model.editorLocked).help(speakerName)
                    .accessibilityLabel("Speaker for passage at \(TextPolicy.timestamp(passage.start))")
                    Spacer(minLength: 8)
                    Menu("Passage Actions", systemImage: "ellipsis") {
                        Button("Split at a Word", systemImage: "scissors") { model.splitPassage = passage.id }
                            .disabled(!passage.canSplit)
                        Button("Restore Original Text", systemImage: "arrow.uturn.backward") {
                            model.edit(passage.id, text: passage.originalText)
                        }
                        .disabled(passage.text == passage.originalText)
                    }
                    .labelStyle(.iconOnly).menuStyle(.borderlessButton).fixedSize()
                    .disabled(model.editorLocked)
                    .accessibilityLabel("Actions for passage at \(TextPolicy.timestamp(passage.start))")
                }
                if model.editorLocked {
                    Text(passage.text).font(.title3).lineSpacing(5).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    PassageTextEditor(text: Binding(
                        get: { model.session.passages.first(where: { $0.id == passage.id })?.text ?? passage.text },
                        set: { model.edit(passage.id, text: $0) }
                    ), accessibilityLabel: "Passage at \(TextPolicy.timestamp(passage.start))")
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.vertical, 18)
    }
}
