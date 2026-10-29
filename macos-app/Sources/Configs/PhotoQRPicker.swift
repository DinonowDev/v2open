import AppKit
import PhotosUI
import Vision

final class PhotoQRPicker: NSObject, PHPickerViewControllerDelegate {
    static let shared = PhotoQRPicker()
    private var onText: ((String?) -> Void)?
    private var sheet: NSWindow?

    func present(onText: @escaping (String?) -> Void) {
        self.onText = onText
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        if let host = NSApp.keyWindow?.contentViewController {
            host.presentAsSheet(picker)
            return
        }
        let window = NSWindow(contentViewController: picker)
        window.title = "Photos"
        window.setContentSize(NSSize(width: 520, height: 420))
        window.makeKeyAndOrderFront(nil)
        sheet = window
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(nil)
        sheet?.close()
        sheet = nil
        guard let item = results.first else {
            onText?(nil)
            return
        }
        item.itemProvider.loadObject(ofClass: NSImage.self) { [weak self] object, _ in
            let image = object as? NSImage
            DispatchQueue.main.async {
                self?.onText?(Self.decode(image))
            }
        }
    }

    static func decode(_ image: NSImage?) -> String? {
        guard let image else { return nil }
        var rect = NSRect(origin: .zero, size: image.size)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        let request = VNDetectBarcodesRequest()
        try? VNImageRequestHandler(cgImage: cg).perform([request])
        return request.results?.first?.payloadStringValue
    }
}
