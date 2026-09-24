import SwiftUI
import TranscriberKit

struct TranscriberRootView: View {
    @Bindable var model: AppModel
    @State private var columns: NavigationSplitViewVisibility = .all
    @State private var dropTarget = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            TranscriberSidebar(model: model)
                .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
        } detail: {
            TranscriptDetailView(model: model)
        }
        .navigationTitle("Transcriber")
        .navigationSubtitle(model.session.sourceName)
        .toolbar { workspaceToolbar }
        .overlay(alignment: .center) {
            if dropTarget && !model.editorLocked {
                Label("Drop an MP4 to open it", systemImage: "arrow.down.document")
                    .padding().glassEffect()
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard urls.count == 1, !model.editorLocked else { return false }
            Task { await model.importVideo(urls[0]) }
            return true
        } isTargeted: { dropTarget = $0 }
        .sheet(isPresented: Binding(
            get: { model.splitPassage != nil },
            set: { if !$0 { model.splitPassage = nil } }
        )) {
            if let passage = model.session.passages.first(where: { $0.id == model.splitPassage }) {
                SplitPassageSheet(passage: passage, split: { model.split(passage.id, before: $0) },
                                  cancel: { model.splitPassage = nil })
            }
        }
    }

    @ToolbarContentBuilder private var workspaceToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button("Open Video", systemImage: "folder") { model.chooseVideo() }
                .disabled(model.editorLocked)
                .help("Open an MP4 video (Command-O)")
        }
        ToolbarItem(placement: .primaryAction) {
            if model.busy {
                Button(model.cancelling ? "Cancelling" : "Cancel", systemImage: "stop.fill") { model.cancel() }
                    .labelStyle(.titleAndIcon)
                    .disabled(model.cancelling)
                    .help("Cancel transcription and keep completed passages")
            } else {
                Button(model.session.passages.isEmpty ? "Transcribe" : "Transcribe Again", systemImage: "waveform") {
                    model.transcribe()
                }
                .labelStyle(.titleAndIcon)
                .buttonStyle(.glassProminent)
                .disabled(!model.hasVideo || model.editorLocked)
                .help("Transcribe the selected audio track (Command-R)")
            }
        }
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Copy All", systemImage: "doc.on.doc") { model.copyAll() }
                .disabled(!model.canExport)
                .help("Copy the transcript (Command-Shift-C)")
            Button("Save As", systemImage: "square.and.arrow.down") { model.saveText() }
                .disabled(!model.canExport)
                .help("Save the transcript as text (Command-S)")
            Menu("Export Options", systemImage: "ellipsis.circle") {
                Toggle("Include Timestamps", isOn: Binding(
                    get: { model.session.includeTimestamps }, set: model.timestamps
                ))
                .disabled(model.editorLocked)
            }
            .help("Options for copied and saved text")
            .accessibilityLabel("Export Options")
        }
    }
}

#Preview("Workspace") {
    TranscriberRootView(model: AppModel(preview: true))
        .frame(width: 1120, height: 790)
}
