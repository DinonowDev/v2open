import AVFoundation
import AppKit
import SwiftUI

final class ScanCoordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: (String) -> Void
    let session = AVCaptureSession()
    private var delivered = false

    init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

    deinit {
        if session.isRunning { session.stopRunning() }
    }

    func start(in view: NSView) {
        guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else { return }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = view.bounds
        preview.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        preview.videoGravity = .resizeAspectFill
        view.wantsLayer = true
        view.layer = preview
        session.startRunning()
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !delivered, let value = objects.compactMap({ $0 as? AVMetadataMachineReadableCodeObject }).first?.stringValue else { return }
        delivered = true
        session.stopRunning()
        onCode(value)
    }
}

struct ScanView: NSViewRepresentable {
    var onCode: (String) -> Void
    func makeCoordinator() -> ScanCoordinator { ScanCoordinator(onCode: onCode) }
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.start(in: view)
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onCode = onCode
    }
}
