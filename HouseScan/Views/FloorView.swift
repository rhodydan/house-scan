import RoomPlan
import SwiftUI

struct FloorView: View {
    @Environment(Store.self) private var store
    let projectID: Project.ID
    let floorID: Floor.ID
    @State private var scanning = false
    @State private var exporting = false
    @State private var prompt: NamePrompt?
    @State private var pendingDelete: Room?

    private var floor: Floor? { store.floor(floorID, in: projectID) }
    private var scanned: [Room] { floor?.rooms.filter { $0.scan != nil } ?? [] }

    var body: some View {
        List {
            Section("Rooms") {
                ForEach(floor?.rooms ?? []) { room in
                    NavigationLink { RoomView(projectID: projectID, floorID: floorID, roomID: room.id) } label: {
                        LabeledContent(room.name, value: room.scan?.scannedAt.formatted(date: .abbreviated, time: .omitted) ?? "Not scanned")
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { pendingDelete = room }
                        Button("Rename") {
                            prompt = NamePrompt(title: "Rename Room", text: room.name) { store.renameRoom(room.id, floor: floorID, in: projectID, to: $0) }
                        }
                    }
                }
                if RoomCaptureSession.isSupported {
                    Button("Scan a Room", systemImage: "camera.metering.matrix") { scanning = true }
                } else {
                    Label("Scanning needs an iPhone or iPad with LiDAR.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
                Button("Add Room Without Scanning", systemImage: "plus") {
                    prompt = NamePrompt(title: "New Room", text: "") { store.addRoom(name: $0, floor: floorID, in: projectID) }
                }
            }
            if !scanned.isEmpty {
                Section {
                    Button("Merge and Export Floor", systemImage: "square.and.arrow.up") { exporting = true }
                } footer: {
                    Text("Makes a USDZ model, a floor plan as PDF and PNG, and a JSON file of every wall, door, window and opening.")
                }
            }
        }
        .navigationTitle(floor?.name ?? "")
        .namePrompt($prompt)
        .fullScreenCover(isPresented: $scanning) {
            ScanScreen(store: store, projectID: projectID, floorID: floorID)
        }
        .sheet(isPresented: $exporting) {
            FloorExportView(projectID: projectID, floorID: floorID)
        }
        .confirmationDialog("Delete \(pendingDelete?.name ?? "")?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
            Button("Delete Room", role: .destructive) {
                if let pendingDelete { store.deleteRoom(pendingDelete.id, floor: floorID, in: projectID) }
            }
        } message: {
            Text("Its scan is deleted from this iPhone and can't be recovered.")
        }
    }
}
