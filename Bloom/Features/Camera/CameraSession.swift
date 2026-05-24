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
/// 4. `capture()` — `async` photo capture; returns a fully-decoded UIImage.
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
        case cameraUnavailable
        case noBackCamera
        case noPhotoData
        case noImage
        case underlying(Error)
    }

    private enum ConfigurationResult {
        case success(AVCaptureDeviceInput)
        case failure(Error)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var isRunning: Bool = false

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "app.progress.camera.session")
    private let photoOutput = AVCapturePhotoOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var captureContinuation: CheckedContinuation<UIImage, Error>?
    private var isConfigured: Bool = false
    private var desiredRunning: Bool = false
    private var runtimeErrorObserver: NSObjectProtocol?
    private var startRetryTask: Task<Void, Never>?
    /// Coalesces concurrent `configure()` callers (pre-start path + the
    /// CameraView .task can both arrive at once on a fresh launch).
    private var configurationTask: Task<Void, Never>?

    override init() {
        super.init()
        runtimeErrorObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification,
            object: session,
            queue: nil
        ) { [weak self] notification in
            let error = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError
            Task { @MainActor [weak self] in
                self?.handleRuntimeError(error)
            }
        }
    }

    deinit {
        if let runtimeErrorObserver {
            NotificationCenter.default.removeObserver(runtimeErrorObserver)
        }
        startRetryTask?.cancel()
    }

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

    /// Prepares the capture pipeline after the navigation transition has had
    /// time to complete. Starting `AVCaptureSession` during a push can block
    /// UIKit's system gesture gate, so this method only performs idempotent
    /// configuration and leaves `startRunning()` to `CameraView`.
    ///
    /// Safe to call from anywhere; race-free with `CameraView`'s own
    /// `.task` because `configure()` is deduped.
    func beginCapturePath() {
        Task(priority: .utility) { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            await self?.prewarm()
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
        for attempt in 0..<Self.configurationAttemptCount {
            let result = await withCheckedContinuation { (continuation: CheckedContinuation<ConfigurationResult, Never>) in
                sessionQueue.async { [weak self] in
                    guard let self else {
                        continuation.resume(returning: .failure(CaptureError.sessionNotReady))
                        return
                    }
                    continuation.resume(returning: self.configureOnQueue(session: session, photoOutput: photoOutput))
                }
            }

            switch result {
            case .success(let input):
                videoInput = input
                isConfigured = true
                status = .ready
                return
            case .failure(let error) where Self.shouldRetryConfiguration(error, attempt: attempt):
                let delay = Self.configurationRetryDelay(for: attempt)
                try? await Task.sleep(for: .milliseconds(delay))
            case .failure(let error):
                status = .failed(error)
                return
            }
        }
    }

    nonisolated private func configureOnQueue(
        session: AVCaptureSession,
        photoOutput: AVCapturePhotoOutput
    ) -> ConfigurationResult {
        session.beginConfiguration()
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ) else {
            session.commitConfiguration()
            return .failure(CaptureError.noBackCamera)
        }

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else { throw CaptureError.sessionNotReady }
            session.addInput(input)
        } catch {
            session.commitConfiguration()
            return .failure(error)
        }

        guard session.canAddOutput(photoOutput) else {
            session.removeInput(input)
            session.commitConfiguration()
            return .failure(CaptureError.sessionNotReady)
        }
        session.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .quality

        session.commitConfiguration()
        return .success(input)
    }

    // MARK: - Start / stop

    func start() {
        desiredRunning = true
        guard case .ready = status else { return }
        guard UIApplication.shared.applicationState == .active else {
            stop()
            return
        }
        guard let device = videoInput?.device else {
            status = .failed(CaptureError.cameraUnavailable)
            return
        }
        startOnQueue(device: device, attempt: 0)
    }

    private func startOnQueue(device: AVCaptureDevice, attempt: Int) {
        let session = self.session
        sessionQueue.async {
            guard Self.cameraHardwareIsReady(device) else {
                Task { @MainActor [weak self] in
                    self?.scheduleStartRetry(device: device, after: attempt)
                }
                return
            }
            if !session.isRunning {
                session.startRunning()
            }
            let started = session.isRunning
            Task { @MainActor [weak self] in
                self?.isRunning = started
                if !started {
                    self?.scheduleStartRetry(device: device, after: attempt)
                }
            }
        }
    }

    func stop() {
        desiredRunning = false
        startRetryTask?.cancel()
        startRetryTask = nil
        let session = self.session
        sessionQueue.async {
            if session.isRunning {
                session.stopRunning()
            }
            Task { @MainActor [weak self] in
                self?.isRunning = false
            }
        }
    }

    private func scheduleStartRetry(device: AVCaptureDevice, after attempt: Int) {
        guard desiredRunning else { return }
        guard attempt < 4 else {
            isRunning = false
            status = .failed(CaptureError.cameraUnavailable)
            return
        }

        startRetryTask?.cancel()
        startRetryTask = Task { [weak self] in
            let delay = UInt64(150_000_000 * UInt64(attempt + 1))
            try? await Task.sleep(nanoseconds: delay)
            await MainActor.run {
                guard let self, self.desiredRunning else { return }
                self.startOnQueue(device: device, attempt: attempt + 1)
            }
        }
    }

    nonisolated private static func cameraHardwareIsReady(_ device: AVCaptureDevice) -> Bool {
        do {
            try device.lockForConfiguration()
            device.unlockForConfiguration()
            return true
        } catch {
            return false
        }
    }

    nonisolated private static let configurationAttemptCount = 4

    nonisolated private static func shouldRetryConfiguration(_ error: Error, attempt: Int) -> Bool {
        guard attempt < configurationAttemptCount - 1 else { return false }
        if let captureError = error as? CaptureError,
           case .noBackCamera = captureError {
            return false
        }
        return true
    }

    nonisolated private static func configurationRetryDelay(for attempt: Int) -> Int {
        [120, 250, 500][min(attempt, 2)]
    }

    private func handleRuntimeError(_ error: NSError?) {
        if error?.domain == AVFoundationErrorDomain,
           error?.code == AVError.Code.mediaServicesWereReset.rawValue,
           desiredRunning {
            status = .ready
            start()
        } else {
            desiredRunning = false
            if let error {
                status = .failed(error)
            } else {
                status = .failed(CaptureError.sessionNotReady)
            }
        }
    }

    // MARK: - Capture

    func capture() async throws -> UIImage {
        guard case .ready = status else { throw CaptureError.sessionNotReady }
        let session = self.session
        let running = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            sessionQueue.async {
                continuation.resume(returning: session.isRunning)
            }
        }
        guard running else { throw CaptureError.cameraUnavailable }
        guard captureContinuation == nil else { throw CaptureError.sessionNotReady }

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

extension CameraSession.CaptureError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .sessionNotReady:
            "Camera session is not ready yet."
        case .cameraUnavailable:
            "Camera hardware is not available yet. Close the camera and try again."
        case .noBackCamera:
            "No back camera is available on this device."
        case .noPhotoData:
            "Captured photo data was empty."
        case .noImage:
            "Captured photo could not be decoded."
        case .underlying(let error):
            error.localizedDescription
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
