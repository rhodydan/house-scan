import ARKit
import RoomPlan
import UIKit

/// Hosts RoomCaptureView and owns the AR session the rooms of one visit share.
///
/// Apple's rule for merging: rooms must share a coordinate space. Within a visit that means stopping each room with
/// `stop(pauseARSession: false)` so the session keeps running. On a later visit it means relocalizing against the
/// floor's saved world map before the first room.
final class ScanViewController: UIViewController, @preconcurrency RoomCaptureViewDelegate, @preconcurrency ARSessionDelegate {
    enum Event {
        case relocalizationProgress(String)
        case relocalized
        case roomReady(CapturedRoom)
        case failed(String)
    }

    var onEvent: ((Event) -> Void)?

    private var captureView: RoomCaptureView?
    private var relocalizationView: ARSCNView?
    private var relocalizationSession: ARSession?
    private let configuration = RoomCaptureSession.Configuration()

    private var arSession: ARSession? { captureView?.captureSession.arSession }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
    }

    // MARK: Starting

    /// A floor with no saved map: a new coordinate space.
    func prepareNewSpace() {
        install(RoomCaptureView(frame: view.bounds))
    }

    /// A floor with a saved map: show the camera until ARKit recognizes the place. Reports `.relocalized` when it does.
    func relocalize(with worldMapData: Data) throws {
        guard let map = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: worldMapData) else {
            throw CocoaError(.coderReadCorrupt)
        }
        let session = ARSession()
        session.delegate = self
        let preview = ARSCNView(frame: view.bounds)
        preview.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        preview.session = session
        view.addSubview(preview)
        relocalizationView = preview
        relocalizationSession = session

        let tracking = ARWorldTrackingConfiguration()
        tracking.initialWorldMap = map
        session.run(tracking, options: [])
    }

    private func install(_ capture: RoomCaptureView) {
        capture.frame = view.bounds
        capture.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        capture.delegate = self
        view.addSubview(capture)
        captureView = capture
    }

    /// Gives up on the saved map, for when the place can't be recognized. Rooms from here on start a new space.
    func abandonRelocalization() {
        tearDownRelocalization()?.pause()
        prepareNewSpace()
    }

    @discardableResult
    private func tearDownRelocalization() -> ARSession? {
        relocalizationSession?.delegate = nil
        relocalizationView?.removeFromSuperview()
        relocalizationView = nil
        defer { relocalizationSession = nil }
        return relocalizationSession
    }

    // MARK: ARSessionDelegate, used only while relocalizing. RoomPlan has the session after that.

    func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool { true }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        switch camera.trackingState {
        case .normal:
            guard let relocalized = tearDownRelocalization() else { return }
            install(RoomCaptureView(frame: view.bounds, arSession: relocalized))
            onEvent?(.relocalized)
        case .limited(.relocalizing):
            onEvent?(.relocalizationProgress("Go back to a room you've already scanned and look around slowly."))
        case .limited(.initializing):
            onEvent?(.relocalizationProgress("Starting the camera…"))
        case .limited(.excessiveMotion):
            onEvent?(.relocalizationProgress("Slow down."))
        case .limited(.insufficientFeatures):
            onEvent?(.relocalizationProgress("Point at something with more detail, in good light."))
        default:
            break
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        onEvent?(.failed(error.localizedDescription))
    }

    // MARK: Scanning

    func startRoom() {
        captureView?.captureSession.run(configuration: configuration)
    }

    /// Ends the room but keeps the AR session running, so the next room lands in the same coordinate space.
    func finishRoom() {
        captureView?.captureSession.stop(pauseARSession: false)
    }

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        true
    }

    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        if let error {
            onEvent?(.failed(error.localizedDescription))
        } else {
            onEvent?(.roomReady(processedResult))
        }
    }

    /// The current world map, archived. Called after each saved room, while the session is still running.
    func archivedWorldMap() async throws -> Data {
        guard let arSession else { throw CocoaError(.fileNoSuchFile) }
        return try await withCheckedThrowingContinuation { continuation in
            arSession.getCurrentWorldMap { map, error in
                do {
                    guard let map else { throw error ?? CocoaError(.fileReadUnknown) }
                    continuation.resume(returning: try NSKeyedArchiver.archivedData(withRootObject: map, requiringSecureCoding: true))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stopEverything() {
        onEvent = nil
        tearDownRelocalization()?.pause()
        captureView?.captureSession.stop()
        arSession?.pause()
    }

    // RoomCaptureViewDelegate inherits NSCoding, which UIViewController already provides.
    required init?(coder: NSCoder) { super.init(coder: coder) }
    init() { super.init(nibName: nil, bundle: nil) }
    override func encode(with coder: NSCoder) { super.encode(with: coder) }
}
