import SwiftUI
import TranscriberKit

struct SpeakerSections: View {
    @Bindable var model: AppModel

    var body: some View {
        SidebarSection("Speakers") {
            if model.session.speakers.isEmpty {
                Text("Add speakers, then assign them to passages. Voice separation is manual.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(model.session.speakers) { speaker in
                SpeakerNameRow(speaker: speaker) { model.rename(speaker.id, name: $0) }
                    .disabled(model.editorLocked)
            }
            Button("Add Speaker", systemImage: "person.badge.plus") { model.addSpeaker() }
                .disabled(model.editorLocked)
        }
        if !model.suggestions.isEmpty {
            SidebarSection("Suggested Names") {
                ForEach(model.suggestions) { suggestion in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(suggestion.name).font(.headline)
                        Text(suggestion.evidence).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button(TextPolicy.timestamp(suggestion.time)) { model.seek(suggestion.time) }
                                .font(.caption.monospacedDigit()).buttonStyle(.borderless)
                                .disabled(!model.hasVideo)
                                .accessibilityLabel("Play name suggestion at \(TextPolicy.timestamp(suggestion.time))")
                            Spacer()
                            Menu("Assign") {
                                Button("Create Speaker: \(suggestion.name)") { model.apply(suggestion, to: nil) }
                                ForEach(model.session.speakers) { speaker in
                                    Button("Rename \(speaker.name)") { model.apply(suggestion, to: speaker.id) }
                                }
                            }
                            .fixedSize().disabled(model.editorLocked)
                            .accessibilityLabel("Assign suggested name \(suggestion.name)")
                        }
                    }
                    .padding(.vertical, 6)
                    .accessibilityElement(children: .contain)
                }
                Text("Suggestions come from spoken introductions. Confirm the person before assigning a name.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct SpeakerNameRow: View {
    let speaker: Speaker
    let commit: (String) -> Void
    @State private var name: String
    @FocusState private var focused: Bool

    init(speaker: Speaker, commit: @escaping (String) -> Void) {
        self.speaker = speaker
        self.commit = commit
        _name = State(initialValue: speaker.name)
    }

    var body: some View {
        HStack {
            Image(systemName: "person.crop.circle").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField("Speaker name", text: $name).textFieldStyle(.roundedBorder).focused($focused)
                .onSubmit { finishEditing(); focused = false }
                .onChange(of: focused) { _, value in if !value { finishEditing() } }
                .onChange(of: speaker.name) { _, value in if !focused { name = value } }
                .onChange(of: name) { _, value in
                    let normalized = TextPolicy.clean(value)
                    if normalized != value { name = normalized }
                }
                .onDisappear { if focused { finishEditing() } }
                .accessibilityLabel("Name for \(speaker.name)")
        }
        .accessibilityElement(children: .contain)
    }

    private func finishEditing() {
        commit(name)
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { name = speaker.name }
    }
}
