import AVFoundation
import CoreImage
import UIKit

/// Back camera with a throttled stream of upright frames. Shutter and live mode both read from this stream.
final class CameraController: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    @Published var authorized = false
    @Published var torchOn = false
    @Published var focusLocked = false
    var onFrame: (@Sendable (CGImage, TimeInterval) -> Void)?

    private let queue = DispatchQueue(label: "camera.frames")
    private let ciContext = CIContext()
    private var device: AVCaptureDevice?
    private var lastEmit: TimeInterval = 0
    /// About 8 frames a second is plenty for card detection and keeps the phone cool.
    private let interval: TimeInterval = 1.0 / 8.0

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { ok in
                DispatchQueue.main.async { if ok { self.configureAndRun() } }
            }
        default: authorized = false
        }
    }

    func stop() { queue.async { if self.session.isRunning { self.session.stopRunning() } } }

    private func configureAndRun() {
        authorized = true
        queue.async {
            guard !self.session.isRunning else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .hd1920x1080
            if self.session.inputs.isEmpty,
               let dev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
               let input = try? AVCaptureDeviceInput(device: dev), self.session.canAddInput(input) {
                self.session.addInput(input)
                self.device = dev
            }
            if self.session.outputs.isEmpty {
                let out = AVCaptureVideoDataOutput()
                out.alwaysDiscardsLateVideoFrames = true
                out.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                out.setSampleBufferDelegate(self, queue: self.queue)
                if self.session.canAddOutput(out) {
                    self.session.addOutput(out)
                    if let c = out.connection(with: .video), c.isVideoRotationAngleSupported(90) { c.videoRotationAngle = 90 }
                }
            }
            self.session.commitConfiguration()
            self.session.startRunning()
        }
    }

    func setTorch(_ on: Bool) {
        guard let d = device, d.hasTorch else { return }
        try? d.lockForConfiguration()
        d.torchMode = on ? .on : .off
        d.unlockForConfiguration()
        DispatchQueue.main.async { self.torchOn = on }
    }

    /// Locking focus and exposure keeps foil glare from making the picture pump while a card is held still.
    func setFocusLocked(_ locked: Bool) {
        guard let d = device else { return }
        try? d.lockForConfiguration()
        if locked {
            if d.isFocusModeSupported(.locked) { d.focusMode = .locked }
            if d.isExposureModeSupported(.locked) { d.exposureMode = .locked }
        } else {
            if d.isFocusModeSupported(.continuousAutoFocus) { d.focusMode = .continuousAutoFocus }
            if d.isExposureModeSupported(.continuousAutoExposure) { d.exposureMode = .continuousAutoExposure }
        }
        d.unlockForConfiguration()
        DispatchQueue.main.async { self.focusLocked = locked }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let t = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        guard t - lastEmit >= interval, let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastEmit = t
        let ci = CIImage(cvPixelBuffer: pb)
        guard let cg = ciContext.createCGImage(ci, from: ci.extent) else { return }
        onFrame?(cg, t)
    }
}
