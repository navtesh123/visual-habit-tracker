import AVFoundation
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

    // MARK: - Configuration

    func configure() async {
        guard !isConfigured else { return }
        status = .configuring

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [weak self] in
                self?.configureOnQueue()
                continuation.resume()
            }
        }

        if case .configuring = status {
            isConfigured = true
            status = .ready
        }
    }

    private func configureOnQueue() {
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
            videoInput = input
            currentDevice = device
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
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
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
        if photoOutput.isHighResolutionCaptureEnabled {
            settings.isHighResolutionPhotoEnabled = true
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.captureContinuation = continuation
            self.sessionQueue.async { [weak self] in
                guard let self else { return }
                self.photoOutput.capturePhoto(with: settings, delegate: self)
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
