import SwiftUI
import AVFoundation

struct QRScannerView: UIViewRepresentable {
    let onScan: (String) -> Void

    class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let parent: QRScannerView
        var session: AVCaptureSession?

        init(_ parent: QRScannerView) { self.parent = parent }

        func metadataOutput(_ output: AVCaptureMetadataOutput,
                            didOutput metadataObjects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            guard let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let str = obj.stringValue else { return }
            session?.stopRunning()
            DispatchQueue.main.async { self.parent.onScan(str) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black

        let session = AVCaptureSession()
        context.coordinator.session = session

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return view }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        session.addOutput(output)
        output.setMetadataObjectsDelegate(context.coordinator, queue: .main)
        output.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = UIScreen.main.bounds
        view.layer.addSublayer(preview)

        DispatchQueue.global(qos: .background).async { session.startRunning() }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
