import PhotosUI
import QuickLook
import SwiftUI

/// A small photo from the photos folder.
struct SavedPhoto: View {
    let url: URL
    var side: CGFloat = 60
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color.secondary.opacity(0.2)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: url) {
            let url = url
            let pixels = Int(side * 3)
            image = await Task.detached { PhotoPreparation.thumbnail(at: url, longestEdge: pixels) }.value
        }
    }
}

struct ItemEditor: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let projectID: Project.ID
    let floorID: Floor.ID
    let roomID: Room.ID
    private let isNew: Bool
    @State private var item: InventoryItem
    /// Plain text, parsed on Save. A formatted field only commits when it loses focus, so tapping Save straight after
    /// typing a value would lose it.
    @State private var valueText: String
    /// Photos saved since the editor opened, to clear up on Cancel.
    @State private var addedPhotos: [String] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var takingPhoto = false
    @State private var problem: String?
    @State private var viewing: URL?

    init(projectID: Project.ID, floorID: Floor.ID, roomID: Room.ID, item: InventoryItem?) {
        self.projectID = projectID
        self.floorID = floorID
        self.roomID = roomID
        isNew = item == nil
        _item = State(initialValue: item ?? InventoryItem(name: ""))
        _valueText = State(initialValue: item?.valueCents.map { String(format: "%d.%02d", $0 / 100, $0 % 100) } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                if item.needsChecking {
                    Label("Read from the label photo. Check the model and serial number against it. Tap the photo to zoom.",
                          systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(.orange)
                }
                Section {
                    TextField("Name", text: $item.name)
                    TextField("Value in dollars", text: $valueText)
                        .keyboardType(.decimalPad)
                    if !valueIsValid {
                        Text("Enter an amount, like 899.50.").font(.footnote).foregroundStyle(.orange)
                    }
                    TextField("Model", text: $item.model)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                    TextField("Serial number", text: $item.serialNumber)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                }
                Section("Notes") {
                    TextField("Where it was bought, condition…", text: $item.notes, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section("Photos") {
                    if !item.photos.isEmpty {
                        ScrollView(.horizontal) {
                            HStack {
                                ForEach(item.photos, id: \.self) { name in
                                    // Borderless, or a tap anywhere in the row would press every button in it.
                                    Button { viewing = store.files.photoFile(name) } label: {
                                        SavedPhoto(url: store.files.photoFile(name), side: 90)
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("View Photo")
                                    .overlay(alignment: .topTrailing) {
                                        Button("Remove Photo", systemImage: "xmark.circle.fill") { removePhoto(name) }
                                            .labelStyle(.iconOnly)
                                            .buttonStyle(.borderless)
                                            .foregroundStyle(.white, .black.opacity(0.6))
                                    }
                                }
                            }
                        }
                    }
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button("Take Photo", systemImage: "camera") { takingPhoto = true }
                    }
                    PhotosPicker(selection: $pickerItems, matching: .images) {
                        Label("Choose From Library", systemImage: "photo.on.rectangle")
                    }
                }
                if let problem {
                    Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
            }
            .quickLookPreview($viewing)
            .navigationTitle(isNew ? "New Item" : "Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        store.removePhotos(addedPhotos)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !valueIsValid)
                }
            }
            .fullScreenCover(isPresented: $takingPhoto) {
                CameraPicker { image in
                    Task { await addPhoto { PhotoPreparation.jpeg(from: image) } }
                }
                .ignoresSafeArea()
            }
            .onChange(of: pickerItems) { _, selection in
                guard !selection.isEmpty else { return }
                pickerItems = []
                Task {
                    for choice in selection {
                        guard let data = try? await choice.loadTransferable(type: Data.self) else {
                            problem = "One of those photos couldn't be loaded."
                            continue
                        }
                        await addPhoto { PhotoPreparation.jpeg(from: data) }
                    }
                }
            }
        }
    }

    private var trimmedValue: String { valueText.trimmingCharacters(in: .whitespaces) }
    private var valueIsValid: Bool { trimmedValue.isEmpty || InventoryItem.cents(typed: trimmedValue) != nil }

    private func addPhoto(_ prepare: @escaping @Sendable () -> Data?) async {
        let files = store.files
        do {
            let name = try await Task.detached {
                guard let jpeg = prepare() else { throw CocoaError(.fileReadCorruptFile) }
                return try files.savePhoto(jpeg)
            }.value
            item.photos.append(name)
            addedPhotos.append(name)
        } catch {
            problem = "That photo couldn't be saved: \(error.localizedDescription)"
        }
    }

    private func removePhoto(_ name: String) {
        item.photos.removeAll { $0 == name }
        // One added in this session goes now. An older one goes on Save, so Cancel can still keep it.
        if addedPhotos.contains(name) {
            addedPhotos.removeAll { $0 == name }
            store.removePhotos([name])
        }
    }

    private func save() {
        item.name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        item.model = item.model.trimmingCharacters(in: .whitespaces)
        item.needsChecking = false
        item.valueCents = InventoryItem.cents(typed: trimmedValue)
        store.saveItem(item, room: roomID, floor: floorID, in: projectID)
        dismiss()
    }
}
