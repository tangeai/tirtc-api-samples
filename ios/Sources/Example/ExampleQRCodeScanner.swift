#if os(iOS) && canImport(AVFoundation) && canImport(UIKit)
    @preconcurrency import AVFoundation
    import SwiftUI
    import UIKit

    struct ExampleQRCodeScanner: UIViewControllerRepresentable {
        let onPayload: (String) -> Void

        func makeCoordinator() -> Coordinator {
            Coordinator(onPayload: onPayload)
        }

        func makeUIViewController(context: Context) -> ScannerViewController {
            let controller = ScannerViewController()
            controller.delegate = context.coordinator
            return controller
        }

        func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}

        final class Coordinator: NSObject, ScannerViewControllerDelegate {
            private let onPayload: (String) -> Void

            init(onPayload: @escaping (String) -> Void) {
                self.onPayload = onPayload
            }

            func scannerViewController(_ controller: ScannerViewController, didRead payload: String) {
                onPayload(payload)
            }
        }
    }

    protocol ScannerViewControllerDelegate: AnyObject {
        func scannerViewController(_ controller: ScannerViewController, didRead payload: String)
    }

    final class ScannerViewController: UIViewController,
        @preconcurrency AVCaptureMetadataOutputObjectsDelegate
    {
        weak var delegate: ScannerViewControllerDelegate?
        private let session = AVCaptureSession()
        private var previewLayer: AVCaptureVideoPreviewLayer?
        private var didReadPayload = false

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            configureCapture()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            previewLayer?.frame = view.bounds
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            if !session.isRunning {
                DispatchQueue.global(qos: .userInitiated).async { [session] in
                    session.startRunning()
                }
            }
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            if session.isRunning {
                DispatchQueue.global(qos: .userInitiated).async { [session] in
                    session.stopRunning()
                }
            }
        }

        private func configureCapture() {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                attachCaptureSession()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                    guard granted else {
                        return
                    }
                    DispatchQueue.main.async {
                        self?.attachCaptureSession()
                    }
                }
            case .denied, .restricted:
                break
            @unknown default:
                break
            }
        }

        private func attachCaptureSession() {
            guard
                let device = AVCaptureDevice.default(for: .video),
                let input = try? AVCaptureDeviceInput(device: device),
                session.canAddInput(input)
            else {
                return
            }

            session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else {
                return
            }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]

            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = view.bounds
            view.layer.insertSublayer(layer, at: 0)
            previewLayer = layer
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard !didReadPayload else {
                return
            }
            guard
                let payload =
                    metadataObjects
                    .compactMap({ $0 as? AVMetadataMachineReadableCodeObject })
                    .first(where: { $0.type == .qr })?
                    .stringValue
            else {
                return
            }
            didReadPayload = true
            session.stopRunning()
            delegate?.scannerViewController(self, didRead: payload)
        }
    }
#endif
