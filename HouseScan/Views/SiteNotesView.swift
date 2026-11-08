import SwiftUI

struct SiteNotesView: View {
    @Environment(Store.self) private var store
    let projectID: Project.ID
    @State private var capturing = false
    @State private var editing: SiteNote?
    @State private var exportFiles: [URL]?
    @State private var problem: String?

    private var notes: [SiteNote] { store.project(projectID)?.siteNotes ?? [] }

    var body: some View {
        List {
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            Section {
                ForEach(notes) { note in
                    Button { editing = note } label: {
                        HStack(alignment: .top) {
                            SavedPhoto(url: store.files.photoFile(note.photo), side: 60)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(note.note.isEmpty ? "No note" : note.note).lineLimit(2)
                                Text(note.takenAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                                Text(SiteLabel.position(note.position)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button("Delete", role: .destructive) { store.deleteSiteNote(note, in: projectID) }
                    }
                }
                Button("New Site Note", systemImage: "camera") { capturing = true }
            } footer: {
                Text("GPS and compass readings are the phone's own estimates, good for finding a spot again, not for surveying.")
            }
            if !notes.isEmpty {
                Section {
                    if let exportFiles {
                        ShareLink("Share CSV and Photos", items: exportFiles)
                        ShareLink("Share CSV Only", item: exportFiles[0])
                    } else {
                        Button("Export as CSV", systemImage: "tablecells", action: export)
                    }
                }
            }
        }
        .navigationTitle("Site Notes")
        .onChange(of: notes) { exportFiles = nil }
        .fullScreenCover(isPresented: $capturing) {
            SiteCaptureScreen(projectID: projectID)
        }
        .sheet(item: $editing) { note in
            SiteNoteEditor(projectID: projectID, note: note)
        }
    }

    private func export() {
        guard let project = store.project(projectID) else { return }
        do {
            exportFiles = try SiteNotesCSV.export(notes, project: project.name, files: store.files, to: Exports.newDirectory())
            problem = nil
        } catch {
            problem = "The export failed: \(error.localizedDescription)"
        }
    }
}

private struct SiteNoteEditor: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let projectID: Project.ID
    let note: SiteNote
    @State private var text: String

    init(projectID: Project.ID, note: SiteNote) {
        self.projectID = projectID
        self.note = note
        _text = State(initialValue: note.note)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SavedPhoto(url: store.files.photoFile(note.photo), side: 240).frame(maxWidth: .infinity)
                }
                Section("Note") {
                    TextField("What's here?", text: $text, axis: .vertical).lineLimit(3...8)
                }
                ReadingsSection(position: note.position, heading: note.heading)
            }
            .navigationTitle(note.takenAt.formatted(date: .abbreviated, time: .shortened))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.updateSiteNote(note.id, text: text, in: projectID)
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct ReadingsSection: View {
    let position: SitePosition?
    let heading: SiteHeading?

    var body: some View {
        Section("Readings") {
            if let position {
                LabeledContent("Latitude", value: String(format: "%.6f", position.latitude))
                LabeledContent("Longitude", value: String(format: "%.6f", position.longitude))
            }
            Text(SiteLabel.position(position)).font(.footnote)
            Text(SiteLabel.heading(heading)).font(.footnote)
        }
    }
}

/// Live camera with the current readings. The shutter fixes the position and heading at that moment.
struct SiteCaptureScreen: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let projectID: Project.ID
    @State private var camera = CameraCapture()
    @State private var tracker = LocationTracker()
    @State private var cameraReady: Bool?
    @State private var capture: Capture?
    @State private var note = ""
    @State private var problem: String?
    @State private var busy = false

    private struct Capture {
        var takenAt: Date
        var photo: String
        var position: SitePosition?
        var heading: SiteHeading?
    }

    var body: some View {
        Group {
            if let capture {
                review(capture)
            } else {
                live
            }
        }
        .task {
            tracker.start()
            cameraReady = await camera.start()
        }
        .onDisappear {
            tracker.stop()
            camera.stop()
        }
    }

    private var live: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if cameraReady == true {
                CameraPreview(session: camera.session).ignoresSafeArea()
            } else if cameraReady == false {
                ContentUnavailableView("No Camera", systemImage: "camera", description: Text("The camera isn't available, or permission was refused in Settings."))
                    .foregroundStyle(.white)
            }
            VStack {
                HStack {
                    Button("Close") { dismiss() }.buttonStyle(.borderedProminent).tint(.black.opacity(0.6))
                    Spacer()
                }
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    if tracker.isDenied {
                        Label("Location is off for House Scan, so this note will have no position.", systemImage: "location.slash")
                    }
                    Text(SiteLabel.position(tracker.position))
                    Text(SiteLabel.heading(tracker.heading))
                    if let problem { Text(problem).foregroundStyle(.orange) }
                }
                .font(.footnote)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(.white)
                Button("Take Photo", systemImage: "circle.inset.filled", action: shoot)
                    .labelStyle(.iconOnly)
                    .font(.system(size: 64))
                    .tint(.white)
                    .disabled(cameraReady != true || busy)
            }
            .padding()
        }
    }

    private func review(_ capture: Capture) -> some View {
        NavigationStack {
            Form {
                Section {
                    SavedPhoto(url: store.files.photoFile(capture.photo), side: 240).frame(maxWidth: .infinity)
                }
                Section("Note") {
                    TextField("What's here?", text: $note, axis: .vertical).lineLimit(3...8)
                }
                ReadingsSection(position: capture.position, heading: capture.heading)
            }
            .navigationTitle("New Site Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Retake") {
                        store.removePhotos([capture.photo])
                        self.capture = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.addSiteNote(SiteNote(takenAt: capture.takenAt, note: note, photo: capture.photo,
                                                   position: capture.position, heading: capture.heading), to: projectID)
                        dismiss()
                    }
                }
            }
        }
    }

    private func shoot() {
        // Read before the camera does anything, so the readings match the moment of the tap.
        let takenAt = Date()
        let position = tracker.location.flatMap { SitePosition($0, at: takenAt, isPrecise: tracker.isPrecise) }
        let heading = tracker.heading
        let files = store.files
        let camera = camera
        busy = true
        Task {
            defer { busy = false }
            do {
                let photo = try await Task.detached {
                    let data = try await camera.capture()
                    guard let jpeg = PhotoPreparation.jpeg(from: data) else { throw CocoaError(.fileReadCorruptFile) }
                    return try files.savePhoto(jpeg)
                }.value
                capture = Capture(takenAt: takenAt, photo: photo, position: position, heading: heading)
                problem = nil
            } catch {
                problem = "The photo failed: \(error.localizedDescription)"
            }
        }
    }
}
