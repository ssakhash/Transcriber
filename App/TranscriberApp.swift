import AppKit
import SwiftUI

@main struct TranscriberApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel(preview: CommandLine.arguments.contains("--preview"))
    var body: some Scene {
        Window("Transcriber", id: "studio") {
            TranscriberRootView(model: model)
                .frame(minWidth: 940, minHeight: 650)
                .onAppear { delegate.model = model }
        }
        .defaultSize(width: 1120, height: 790)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Video") { model.chooseVideo() }.keyboardShortcut("o").disabled(model.editorLocked)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save Transcript As") { model.saveText() }.keyboardShortcut("s").disabled(!model.canExport)
            }
            CommandMenu("Transcript") {
                Button("Transcribe Video") { model.transcribe() }.keyboardShortcut("r", modifiers: [.command])
                    .disabled(!model.hasVideo || model.editorLocked)
                Button("Cancel Transcription") { model.cancel() }
                    .keyboardShortcut(".", modifiers: [.command]).disabled(!model.busy || model.cancelling)
                Divider()
                Button("Copy All") { model.copyAll() }.keyboardShortcut("c", modifiers: [.command, .shift]).disabled(!model.canExport)
            }
        }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    private var ending = false
    private var finishing = false

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if ending { return .terminateNow }
        if finishing { return .terminateLater }
        guard let model else { return .terminateNow }
        finishing = true
        Task {
            var allowed = await model.shutdown()
            if !allowed {
                let alert = NSAlert()
                alert.messageText = "Your latest changes could not be saved."
                alert.informativeText = "Stay in the app to retry saving or export your transcript before quitting."
                alert.addButton(withTitle: "Stay"); alert.addButton(withTitle: "Quit Anyway")
                allowed = alert.runModal() == .alertSecondButtonReturn
            }
            ending = allowed; finishing = false
            sender.reply(toApplicationShouldTerminate: allowed)
        }
        return .terminateLater
    }
}
