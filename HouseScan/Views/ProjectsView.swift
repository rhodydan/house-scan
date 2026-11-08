import SwiftUI

struct ProjectsView: View {
    @Environment(Store.self) private var store
    @State private var prompt: NamePrompt?
    @State private var pendingDelete: Project?

    var body: some View {
        NavigationStack {
            List {
                if let problem = store.loadProblem {
                    Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                }
                ForEach(store.library.projects) { project in
                    NavigationLink(project.name) { ProjectView(projectID: project.id) }
                        .swipeActions {
                            Button("Delete", role: .destructive) { pendingDelete = project }
                            Button("Rename") {
                                prompt = NamePrompt(title: "Rename Project", text: project.name) { store.renameProject(project.id, to: $0) }
                            }
                        }
                }
            }
            .overlay {
                if store.library.projects.isEmpty {
                    ContentUnavailableView("No Projects", systemImage: "house", description: Text("Add a project, such as Home, then add floors and scan rooms."))
                }
            }
            .navigationTitle("House Scan")
            .toolbar {
                Button("Add Project", systemImage: "plus") {
                    prompt = NamePrompt(title: "New Project", text: "") { store.addProject(name: $0) }
                }
            }
            .namePrompt($prompt)
            .confirmationDialog("Delete \(pendingDelete?.name ?? "")?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
                Button("Delete Project", role: .destructive) {
                    if let pendingDelete { store.deleteProject(pendingDelete.id) }
                }
            } message: {
                Text("Its scans are deleted from this iPhone and can't be recovered.")
            }
            .alert("Couldn't Save", isPresented: Binding(get: { store.saveProblem != nil }, set: { if !$0 { store.saveProblem = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(store.saveProblem ?? "")
            }
        }
    }
}
