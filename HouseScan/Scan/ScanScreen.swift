import RoomPlan
import SwiftUI

/// Hosts the camera. It is attached once it is on screen, because RoomCaptureView needs real bounds.
private struct CameraHost: UIViewControllerRepresentable {
    let model: ScanModel

    func makeUIViewController(context: Context) -> HostController {
        HostController(model: model)
    }

    func updateUIViewController(_ controller: HostController, context: Context) {}

    final class HostController: UIViewController {
        private let model: ScanModel
        private let camera = ScanViewController()
        private var attached = false

        init(model: ScanModel) {
            self.model = model
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { fatalError("Not used from a storyboard") }

        override func viewDidLoad() {
            super.viewDidLoad()
            addChild(camera)
            camera.view.frame = view.bounds
            camera.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(camera.view)
            camera.didMove(toParent: self)
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard !attached else { return }
            attached = true
            model.attach(camera)
        }
    }
}

struct ScanScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: ScanModel
    @State private var confirmSkip = false
    @FocusState private var nameFocused: Bool

    init(store: Store, projectID: Project.ID, floorID: Floor.ID, replacing: Room.ID? = nil) {
        _model = State(initialValue: ScanModel(store: store, projectID: projectID, floorID: floorID, replacing: replacing))
    }

    var body: some View {
        ZStack {
            CameraHost(model: model).ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                Spacer()
                panel
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .padding()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model.appWentToBackground() }
        }
        .confirmationDialog("Start without lining up?", isPresented: $confirmSkip, titleVisibility: .visible) {
            Button("Start Anyway", role: .destructive) { model.skipRelocalization() }
        } message: {
            Text("Rooms scanned this way can't merge with the rooms already on this floor.")
        }
    }

    private var topBar: some View {
        HStack {
            Button("Close", action: close)
                .buttonStyle(.borderedProminent)
                .tint(.black.opacity(0.6))
                .disabled(model.phase == .saving)
            Spacer()
            Text(model.roomsSaved == 0 ? model.floorName : "\(model.floorName): \(model.roomsSaved) saved")
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.black.opacity(0.6), in: Capsule())
                .foregroundStyle(.white)
        }
        .padding(.horizontal)
    }

    @ViewBuilder private var panel: some View {
        switch model.phase {
        case .starting:
            ProgressView("Starting…")
        case .relocalizing(let message):
            VStack(spacing: 12) {
                Text("Finding your place").font(.headline)
                Text(message).font(.subheadline).multilineTextAlignment(.center)
                Text("New rooms only merge with this floor's earlier rooms once the phone recognizes them.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Start Without Lining Up") { confirmSkip = true }.font(.footnote)
            }
        case .ready:
            VStack(spacing: 12) {
                Text(model.roomsSaved == 0 ? "Ready to scan" : "Ready for the next room").font(.headline)
                Text("Good light, doors closed, curtains open. Walk the room's edge slowly and keep it under 5 minutes.")
                    .font(.subheadline).multilineTextAlignment(.center)
                if let warning = model.unalignedWarning {
                    Label(warning, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                }
                Button("Start Scanning") { model.startRoom() }.buttonStyle(.borderedProminent)
            }
        case .scanning:
            Button("Done With This Room") { model.finishRoom() }.buttonStyle(.borderedProminent)
        case .processing:
            ProgressView("Building the room…")
        case .review:
            VStack(spacing: 12) {
                TextField("Room name", text: $model.roomName)
                    .textFieldStyle(.roundedBorder)
                    .focused($nameFocused)
                HStack {
                    Button("Discard", role: .destructive) { model.discardRoom() }.buttonStyle(.bordered)
                    Button("Save Room") {
                        nameFocused = false
                        Task { await model.saveRoom() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        case .saving:
            ProgressView("Saving…")
        case .saved:
            VStack(spacing: 12) {
                Text("Room saved").font(.headline)
                if let problem = model.worldMapProblem {
                    Label(problem, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                }
                HStack {
                    Button("Finish", action: close).buttonStyle(.bordered)
                    Button("Scan Next Room") { model.startRoom() }.buttonStyle(.borderedProminent)
                }
            }
        case .interrupted:
            VStack(spacing: 12) {
                Text("Scan interrupted").font(.headline)
                Text("iOS stopped the camera when the app left the screen. Saved rooms are safe. Close this screen, then scan again to pick up where you left off.")
                    .font(.subheadline).multilineTextAlignment(.center)
                Button("Close", action: close).buttonStyle(.borderedProminent)
            }
        case .failed(let message):
            VStack(spacing: 12) {
                Text("That didn't work").font(.headline)
                Text(message).font(.subheadline).multilineTextAlignment(.center)
                Button("Close", action: close).buttonStyle(.borderedProminent)
            }
        }
    }

    private func close() {
        model.close()
        dismiss()
    }
}
