import SwiftUI
import TranscriberKit

struct TranscriberSidebar: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SidebarSection("Video") {
                    videoPreview
                    if !model.session.sourceName.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(model.session.sourceName).font(.headline)
                                .lineLimit(3).textSelection(.enabled).help(model.session.sourceName)
                            Text(TextPolicy.timestamp(model.session.duration))
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                    if model.tracks.count > 1 {
                        Picker("Audio track", selection: Binding(get: { model.session.trackID }, set: model.setTrack)) {
                            ForEach(model.tracks) { Text($0.label).tag($0.id) }
                        }
                        .disabled(model.editorLocked || !model.session.passages.isEmpty)
                        .help("Choose the audio track before transcription begins")
                    }
                }
                SidebarSection("Transcription") {
                    TranscriptionProgressView(model: model)
                    Label("English (US) · On-device", systemImage: "lock.shield")
                        .font(.caption).foregroundStyle(.secondary)
                    DisclosureGroup("About local processing") {
                        Text("Speech stays on this Mac. macOS may download the English speech model before the first transcription.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !model.session.passages.isEmpty {
                    SpeakerSections(model: model)
                }
            }
            .padding(20)
        }
        .accessibilityLabel("Video and transcription tools")
    }

    @ViewBuilder private var videoPreview: some View {
        if model.hasVideo {
            NativeVideoPlayer(player: model.player)
                .aspectRatio(16 / 9, contentMode: .fit)
                .accessibilityLabel("Video playback")
        } else {
            VStack(spacing: 10) {
                Image(systemName: "film").font(.largeTitle).foregroundStyle(.secondary)
                Text(model.isPreview ? "Video preview" : model.session.sourceName.isEmpty ? "No video selected" : "Video unavailable")
                    .foregroundStyle(.secondary)
                if !model.session.sourceName.isEmpty && !model.isPreview {
                    Button("Locate Original Video") { model.chooseVideo(relink: true) }
                        .buttonStyle(.glass).disabled(model.editorLocked)
                }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 24)
        }
    }
}

// A sidebar is a tool panel here, not a selectable source list. Keep each control accessible.
struct SidebarSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TranscriptionProgressView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.loading {
                ProgressView("Opening video").controlSize(.small)
            } else {
                Text(model.phase).font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.busy {
                if let value = model.download {
                    ProgressView("Downloading English model", value: value)
                } else if model.progress > 0 {
                    ProgressView(value: model.progress)
                        .accessibilityLabel("Audio processed")
                } else {
                    ProgressView().controlSize(.small).accessibilityLabel(model.phase)
                }
                Text("Completed passages are kept if you cancel.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
