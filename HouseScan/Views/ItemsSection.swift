import SwiftUI

/// Which item the editor is open on, or nil inside for a new one.
struct ItemEditTarget: Identifiable {
    let id = UUID()
    let item: InventoryItem?
}

/// A room's insurance items, shown in the room screen. The sheets belong to the screen, because modifiers on a
/// Section are applied to each of its rows.
struct ItemsSection: View {
    @Environment(Store.self) private var store
    let projectID: Project.ID
    let floorID: Floor.ID
    let roomID: Room.ID
    @Binding var editing: ItemEditTarget?
    @Binding var exporting: Bool
    @Binding var scanningLabel: Bool
    /// Label photos still being read.
    var reading = 0

    private var room: Room? { store.room(roomID, floor: floorID, in: projectID) }

    var body: some View {
        Section {
            ForEach(room?.items ?? []) { item in
                Button { editing = ItemEditTarget(item: item) } label: {
                    HStack {
                        if let photo = item.photos.first {
                            SavedPhoto(url: store.files.photoFile(photo), side: 44)
                        }
                        VStack(alignment: .leading) {
                            Text(item.name)
                            let numbers = [item.model.isEmpty ? nil : "Model \(item.model)",
                                           item.serialNumber.isEmpty ? nil : "Serial \(item.serialNumber)"].compactMap { $0 }
                            if !numbers.isEmpty {
                                Text(numbers.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                            }
                            if item.needsChecking {
                                Text("Read from the label photo. Check it.").font(.caption).foregroundStyle(.orange)
                            }
                        }
                        Spacer()
                        Text(item.valueCents.map(InventoryReport.money) ?? "No value").foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button("Delete", role: .destructive) { store.deleteItem(item, room: roomID, floor: floorID, in: projectID) }
                }
            }
            ForEach(0..<reading, id: \.self) { _ in
                ProgressView("Reading label…")
            }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Scan a Label", systemImage: "barcode.viewfinder") { scanningLabel = true }
            }
            Button("Add Item", systemImage: "plus") { editing = ItemEditTarget(item: nil) }
            if room?.items.isEmpty == false {
                Button("Export This Room's Inventory", systemImage: "doc.text") { exporting = true }
            }
        } header: {
            Text("Insurance")
        }
    }
}

struct InventoryExportView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let projectID: Project.ID
    var onlyRoom: Room.ID?
    @State private var file: URL?
    @State private var summary = ""
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            Group {
                if let file {
                    List {
                        Text(summary)
                        ShareLink(file.lastPathComponent, item: file)
                    }
                } else if let problem {
                    ContentUnavailableView("Export Failed", systemImage: "exclamationmark.triangle", description: Text(problem))
                } else {
                    ProgressView("Making the PDF…")
                }
            }
            .navigationTitle("Inventory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Done") { dismiss() }
            }
        }
        .task { await make() }
    }

    private func make() async {
        guard let project = store.project(projectID) else { return }
        let report = project.inventory(onlyRoom: onlyRoom)
        let files = store.files
        let directory = Exports.newDirectory()
        let url = directory.appending(path: "\(FloorExporter.fileName(project.name))-inventory.pdf")
        do {
            try await Task.detached {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try InventoryPDF.make(report, photoURL: files.photoFile).write(to: url, options: .atomic)
            }.value
            summary = "\(report.entries.count) items, \(InventoryReport.money(cents: report.totalCents)) total."
            file = url
        } catch {
            problem = error.localizedDescription
        }
    }
}
