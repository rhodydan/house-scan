import QuickLook
import RoomPlan
import SwiftUI

struct RoomView: View {
    @Environment(Store.self) private var store
    let projectID: Project.ID
    let floorID: Floor.ID
    let roomID: Room.ID
    @State private var document: FloorDocument?
    @State private var planImage: UIImage?
    @State private var captured: CapturedRoom?
    @State private var problem: String?
    @State private var modelURL: URL?
    @State private var rescanning = false
    @State private var editingItem: ItemEditTarget?
    @State private var exportingInventory = false
    @State private var scanningLabel = false
    @State private var readingLabels = 0

    private var room: Room? { store.room(roomID, floor: floorID, in: projectID) }

    var body: some View {
        List {
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            if let planImage {
                Section {
                    Image(uiImage: planImage).resizable().scaledToFit()
                }
            }
            if let document {
                Section("Scan") {
                    if let date = room?.scan?.scannedAt {
                        LabeledContent("Scanned", value: date.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let area = document.rooms.first?.floorAreaSquareMetres {
                        LabeledContent("Floor area", value: Measure.squareFeet(area))
                    }
                    LabeledContent("Walls", value: "\(document.walls.count)")
                    LabeledContent("Doors", value: "\(document.doors.count)")
                    LabeledContent("Windows", value: "\(document.windows.count)")
                    LabeledContent("Openings", value: "\(document.openings.count)")
                    LabeledContent("Objects", value: "\(document.objects.count)")
                }
                Section {
                    Button("View in 3D", systemImage: "cube") { open3D() }
                }
            }
            ItemsSection(projectID: projectID, floorID: floorID, roomID: roomID, editing: $editingItem, exporting: $exportingInventory,
                         scanningLabel: $scanningLabel, reading: readingLabels)
            if RoomCaptureSession.isSupported {
                Section {
                    Button(room?.scan == nil ? "Scan This Room" : "Rescan This Room", systemImage: "camera.metering.matrix") { rescanning = true }
                }
            }
        }
        .navigationTitle(room?.name ?? "")
        .quickLookPreview($modelURL)
        .sheet(item: $editingItem) { target in
            ItemEditor(projectID: projectID, floorID: floorID, roomID: roomID, item: target.item)
        }
        .sheet(isPresented: $exportingInventory) {
            InventoryExportView(projectID: projectID, onlyRoom: roomID)
        }
        .fullScreenCover(isPresented: $scanningLabel) {
            CameraPicker { image in
                Task { await addItem(fromLabel: image) }
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $rescanning) {
            ScanScreen(store: store, projectID: projectID, floorID: floorID, replacing: roomID)
        }
        .task(id: room?.scan?.scannedAt) { await load() }
    }

    private func load() async {
        guard let room, room.scan != nil else { return }
        let files = store.files
        let id = roomID
        do {
            let captured = try await Task.detached { try files.loadCapturedRoom(id) }.value
            show(captured, name: room.name)
        } catch {
            problem = "This scan couldn't be opened: \(error.localizedDescription)"
        }
    }

    private func show(_ captured: CapturedRoom, name: String) {
        self.captured = captured
        let document = FloorDocument(project: name, floor: name, exportedAt: room?.scan?.scannedAt ?? Date(), mergeStatus: .singleRoom,
                                     rooms: [RoomSummary(name: name, room: captured)], source: GeometrySource(captured))
        self.document = document
        planImage = (try? PlanRenderer.png(document)).flatMap(UIImage.init(data:))
    }

    private func open3D() {
        guard let captured else { return }
        let directory = Exports.newDirectory()
        let url = directory.appending(path: "\(FloorExporter.fileName(room?.name ?? "Room")).usdz")
        Task.detached {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try captured.export(to: url, exportOptions: .mesh)
                await MainActor.run { modelURL = url }
            } catch {
                await MainActor.run { problem = "The 3D model couldn't be made: \(error.localizedDescription)" }
            }
        }
    }

    /// Adds an item straight away from a label photo, so labels can be shot one after another.
    private func addItem(fromLabel image: UIImage) async {
        readingLabels += 1
        defer { readingLabels -= 1 }
        let files = store.files
        do {
            let item = try await Task.detached {
                guard let jpeg = PhotoPreparation.jpeg(from: image) else { throw CocoaError(.fileReadCorruptFile) }
                let reading = LabelReader.read(jpeg: jpeg)
                return InventoryItem(reading: reading, photo: try files.savePhoto(jpeg))
            }.value
            store.saveItem(item, room: roomID, floor: floorID, in: projectID)
        } catch {
            problem = "That label photo couldn't be saved: \(error.localizedDescription)"
        }
    }
}
