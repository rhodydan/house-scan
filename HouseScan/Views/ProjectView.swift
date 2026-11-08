import SwiftUI

struct ProjectView: View {
    @Environment(Store.self) private var store
    let projectID: Project.ID
    @State private var prompt: NamePrompt?
    @State private var pendingDelete: Floor?
    @State private var exportingInventory = false

    private var inventory: InventoryReport? { store.project(projectID)?.inventory() }

    var body: some View {
        List {
            Section("Floors") {
                ForEach(store.project(projectID)?.floors ?? []) { floor in
                    NavigationLink { FloorView(projectID: projectID, floorID: floor.id) } label: {
                        LabeledContent(floor.name, value: floor.rooms.count == 1 ? "1 room" : "\(floor.rooms.count) rooms")
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { pendingDelete = floor }
                        Button("Rename") {
                            prompt = NamePrompt(title: "Rename Floor", text: floor.name) { store.renameFloor(floor.id, in: projectID, to: $0) }
                        }
                    }
                }
                Button("Add Floor", systemImage: "plus") {
                    prompt = NamePrompt(title: "New Floor", text: "") { store.addFloor(name: $0, to: projectID) }
                }
            }
            Section("Insurance") {
                if let inventory, !inventory.entries.isEmpty {
                    LabeledContent("Items", value: "\(inventory.entries.count)")
                    LabeledContent("Total value", value: InventoryReport.money(cents: inventory.totalCents))
                    Button("Export Inventory PDF", systemImage: "doc.text") { exportingInventory = true }
                } else {
                    Text("Add items from inside a room.").foregroundStyle(.secondary)
                }
            }
            Section {
                NavigationLink { SiteNotesView(projectID: projectID) } label: {
                    LabeledContent("Site Notes", value: "\(store.project(projectID)?.siteNotes.count ?? 0)")
                }
            }
        }
        .navigationTitle(store.project(projectID)?.name ?? "")
        .namePrompt($prompt)
        .sheet(isPresented: $exportingInventory) {
            InventoryExportView(projectID: projectID)
        }
        .confirmationDialog("Delete \(pendingDelete?.name ?? "")?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
            Button("Delete Floor", role: .destructive) {
                if let pendingDelete { store.deleteFloor(pendingDelete.id, in: projectID) }
            }
        } message: {
            Text("Its scans are deleted from this iPhone and can't be recovered.")
        }
    }
}
