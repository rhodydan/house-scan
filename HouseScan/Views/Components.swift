import SwiftUI

/// Temporary export files. They live in the temp folder, which isn't backed up, and are cleared at each launch.
enum Exports {
    private static var root: URL { FileManager.default.temporaryDirectory.appending(path: "Exports", directoryHint: .isDirectory) }

    static func newDirectory() -> URL {
        root.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    }

    static func clearOldFiles() {
        try? FileManager.default.removeItem(at: root)
    }
}

/// A name prompt, used for adding and renaming projects, floors and rooms.
struct NamePrompt: Identifiable {
    let id = UUID()
    let title: String
    var text: String
    let onSave: (String) -> Void
}

extension View {
    func namePrompt(_ prompt: Binding<NamePrompt?>) -> some View {
        modifier(NamePromptModifier(prompt: prompt))
    }
}

private struct NamePromptModifier: ViewModifier {
    @Binding var prompt: NamePrompt?
    @State private var text = ""

    func body(content: Content) -> some View {
        content
            .alert(prompt?.title ?? "", isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } })) {
                TextField("Name", text: $text)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty { prompt?.onSave(name) }
                }
            }
            .onChange(of: prompt?.id) { text = prompt?.text ?? "" }
    }
}
