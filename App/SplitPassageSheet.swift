import SwiftUI
import TranscriberKit

struct SplitPassageSheet: View {
    let passage: Passage
    let split: (Int) -> Void
    let cancel: () -> Void
    @State private var selectedWord: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Split Passage").font(.title2.weight(.semibold))
            Text("Select the first word of the new passage. Original word timing is preserved.")
                .foregroundStyle(.secondary)
            List(selection: $selectedWord) {
                ForEach(Array(passage.words.enumerated()).dropFirst(), id: \.offset) { index, word in
                    if word.start > passage.start && word.start < passage.end {
                        HStack(spacing: 16) {
                            Text(TextPolicy.timestamp(word.start)).monospacedDigit().foregroundStyle(.secondary)
                            Text(word.text)
                        }
                        .tag(index)
                    }
                }
            }
            .accessibilityLabel("Recognized word boundaries")
            HStack {
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button("Split Passage") { if let selectedWord { split(selectedWord) } }
                    .buttonStyle(.glassProminent).keyboardShortcut(.defaultAction)
                    .disabled(selectedWord == nil)
            }
        }
        .padding(24).frame(width: 500, height: 420)
    }
}
