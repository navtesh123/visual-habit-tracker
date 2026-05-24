@preconcurrency import AVFoundation
import UIKit
import Foundation

/// Wrapper around `AVCaptureSession` that produces a single highest-quality
/// photo on demand (PRD §3.3).
///
/// Lifecycle:
/// 1. `requestAuthorization()` — call from the SwiftUI `.task`.
/// 2. `configure()` — sets up inputs/outputs (idempotent).
/// 3. `start()` / `stop()` — bracket the camera view's lifetime.
/// 4. `capture(zoom:)` — `async` photo capture; returns a fully-decoded UIImage.
@MainActor
final class CameraSession: NSObject, ObservableObject {
    /// Process-wide singleton. Reusing one `AVCaptureSession` across capture
    /// flows means we only pay the (cold-launch expensive) AVFoundation
    /// device discovery + input/output wiring once. The first
    /// `startRunning()` still has hardware power-on latency, but every
    /// subsequent capture entry — including the very first one — skips
    /// the multi-step `configure()` cost.
    static let shared = CameraSession()

    enum Status {
        case idle
        case configuring
        case ready
        case denied
        case failed(Error)
    }

    enum CaptureError: Error {
        case sessionNotReady
        case noPhotoData
        case noImage
        case underlying(Error)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var currentZoom: CGFloat = 1.0
    @Published private(set) var minZoom: CGFloat = 1.0
    @Published private(set) var maxZoom: CGFloat = 5.0

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "app.progress.camera.session")
    private let photoOutput = AVCapturePhotoOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var currentDevice: AVCaptureDevice?
    private var captureContinuation: CheckedContinuation<UIImage, Error>?
    private var isConfigured: Bool = false
    /// Coalesces concurrent `configure()` callers (pre-start path + the
    /// CameraView .task can both arrive at once on a fresh launch).
    private var configurationTask: Task<Void, Never>?

    // MARK: - Authorization

    func requestAuthorization() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted {
                status = .denied
                return
            }
        case .denied, .restricted:
            status = .denied
            return
        @unknown default:
            status = .denied
            return
        }
    }

    // MARK: - Pre-warm

    /// Configure the session ahead of any user-visible camera surface so
    /// the first capture-button tap doesn't pay for AVFoundation device
    /// discovery + input/output wiring. Safe to call repeatedly (idempotent).
    ///
    /// Only pre-warms when the user has already granted camera access —
    /// otherwise the configuration would trigger a permission prompt at
    /// an unexpected moment. We deliberately do *not* call `start()` here:
    /// that would power on the camera hardware and surface the system
    /// "camera in use" indicator while the user is still on Home.
    func prewarm() async {
        guard !isConfigured else { return }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
        await configure()
    }

    /// Eagerly start the full capture pipeline (configure + powerOn) at the
    /// moment the user *commits* to opening the camera (FAB tap, "Capture
    /// now" context menu, retake button). The navigation push transition
    /// then overlaps with `startRunning()` so the preview is already
    /// streaming frames by the time `CameraView` is visible.
    ///
    /// Safe to call from anywhere; race-free with `CameraView`'s own
    /// `.task` because `configure()` is deduped and `start()` short-circuits
    /// when the underlying `AVCaptureSession` is already running.
    func beginCapturePath() {
        Task { [weak self] in
            guard let self else { return }
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                if !self.isConfigured {
                    await self.configure()
                }
                guard case .ready = self.status else { return }
                self.start()
            case .notDetermined:
                // Defer to CameraView's .task — it requests permission
                // in the proper UI context.
                return
            case .denied, .restricted:
                self.status = .denied
            @unknown default:
                self.status = .denied
            }
        }
    }

    // MARK: - Configuration

    func configure() async {
        if isConfigured { return }
        if let inflight = configurationTask {
            await inflight.value
            return
        }
        let task = Task<Void, Never> { [weak self] in
            await self?.performConfiguration()
        }
        configurationTask = task
        await task.value
        configurationTask = nil
    }

    private func performConfiguration() async {
        guard !isConfigured else { return }
        status = .configuring

        let session = self.session
        let photoOutput = self.photoOutput
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [weak self] in
                self?.configureOnQueue(session: session, photoOutput: photoOutput)
                continuation.resume()
            }
        }

        if case .configuring = status {
            isConfigured = true
            status = .ready
        }
    }

    nonisolated private func configureOnQueue(
        session: AVCaptureSession,
        photoOutput: AVCapturePhotoOutput
    ) {
        session.beginConfiguration()
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ) else {
            DispatchQueue.main.async {
                self.status = .failed(NSError(
                    domain: "CameraSession",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "No back camera available"]
                ))
            }
            session.commitConfiguration()
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else { throw CaptureError.sessionNotReady }
            session.addInput(input)
            Task { @MainActor [weak self] in
                self?.videoInput = input
                self?.currentDevice = device
            }
        } catch {
            DispatchQueue.main.async { self.status = .failed(error) }
            session.commitConfiguration()
            return
        }

        guard session.canAddOutput(photoOutput) else {
            DispatchQueue.main.async {
                self.status = .failed(CaptureError.sessionNotReady)
            }
            session.commitConfiguration()
            return
        }
        session.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .quality

        session.commitConfiguration()

        let resolvedMin = max(1.0, device.minAvailableVideoZoomFactor)
        let resolvedMax = min(5.0, device.maxAvailableVideoZoomFactor)
        let resolvedCurrent = device.videoZoomFactor
        DispatchQueue.main.async {
            self.minZoom = resolvedMin
            self.maxZoom = resolvedMax
            self.currentZoom = resolvedCurrent
        }
    }

    // MARK: - Start / stop

    func start() {
        guard case .ready = status else { return }
        let session = self.session
        sessionQueue.async {
            if !session.isRunning {
                session.startRunning()
            }
        }
    }

    func stop() {
        let session = self.session
        sessionQueue.async {
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    // MARK: - Zoom

    func applyZoom(_ factor: CGFloat) {
        guard let device = currentDevice else { return }
        let clamped = max(minZoom, min(maxZoom, factor))
        sessionQueue.async { [weak self] in
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = clamped
                device.unlockForConfiguration()
                DispatchQueue.main.async { self?.currentZoom = clamped }
            } catch {
                // Best-effort; failing to lock zoom is non-fatal.
            }
        }
    }

    // MARK: - Capture

    func capture() async throws -> UIImage {
        guard case .ready = status else { throw CaptureError.sessionNotReady }

        let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        settings.photoQualityPrioritization = .quality
        settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions

        let photoOutput = self.photoOutput
        return try await withCheckedThrowingContinuation { continuation in
            self.captureContinuation = continuation
            self.sessionQueue.async { [weak self] in
                guard let self else { return }
                photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }
}

extension CameraSession: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        Task { @MainActor in
            guard let continuation = self.captureContinuation else { return }
            self.captureContinuation = nil

            if let error {
                continuation.resume(throwing: CaptureError.underlying(error))
                return
            }
            guard let data = photo.fileDataRepresentation() else {
                continuation.resume(throwing: CaptureError.noPhotoData)
                return
            }
            guard let image = UIImage(data: data) else {
                continuation.resume(throwing: CaptureError.noImage)
                return
            }
            continuation.resume(returning: image)
        }
    }
}
