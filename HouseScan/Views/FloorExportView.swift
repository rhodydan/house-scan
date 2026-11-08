import RoomPlan
import SwiftUI

struct FloorExportView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let projectID: Project.ID
    let floorID: Floor.ID
    @State private var result: FloorExportResult?
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            Group {
                if let result {
                    List {
                        if let data = result.planImage, let image = UIImage(data: data) {
                            Image(uiImage: image).resizable().scaledToFit()
                        }
                        ForEach(result.warnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                        }
                        Section {
                            ShareLink("Share All", items: result.files)
                            ForEach(result.files, id: \.self) { file in
                                ShareLink(file.lastPathComponent, item: file)
                            }
                        } footer: {
                            Text("Choose AirDrop to send these to your Mac.")
                        }
                    }
                } else if let problem {
                    ContentUnavailableView("Export Failed", systemImage: "exclamationmark.triangle", description: Text(problem))
                } else {
                    ProgressView("Merging rooms…")
                }
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Done") { dismiss() }
            }
        }
        .task { await export() }
    }

    private func export() async {
        guard let project = store.project(projectID), let floor = store.floor(floorID, in: projectID) else { return }
        let files = store.files
        let scanned = floor.rooms.compactMap { room in room.scan.map { (room.id, room.name, $0) } }
        do {
            let inputs = try await Task.detached {
                try scanned.map { id, name, scan in
                    RoomInput(name: name, spaceID: scan.spaceID, scannedAt: scan.scannedAt, room: try files.loadCapturedRoom(id))
                }
            }.value
            result = try await FloorExporter.export(project: project.name, floor: floor.name, inputs: inputs, to: Exports.newDirectory())
        } catch {
            problem = error.localizedDescription
        }
    }
}
