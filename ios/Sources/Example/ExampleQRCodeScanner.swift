#if os(iOS) && canImport(AVFoundation) && canImport(UIKit)
    @preconcurrency import AVFoundation
    import SwiftUI
    import UIKit

    struct ExampleQRCodeScanner: View {
        @Environment(\.presentationMode) private var presentationMode
        @State private var availability = ExampleScannerAvailability.checking
        let onPayload: (String) -> Void

        init(onPayload: @escaping (String) -> Void) {
            self.onPayload = onPayload
            let override = ProcessInfo.processInfo.environment[
                "TIRTC_EXAMPLE_SCANNER_AVAILABILITY_OVERRIDE"
            ].flatMap(ExampleScannerAvailability.init(rawValue:))
            _availability = State(initialValue: override ?? .checking)
        }

        var body: some View {
            ZStack {
                ExampleQRCodeCamera(onPayload: onPayload, availability: $availability)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
                Color.clear
                    .contentShape(Rectangle())
                    .accessibilityElement()
                    .accessibilityLabel("相机取景框")
                    .accessibilityIdentifier("scanner.preview")
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white, lineWidth: 3)
                    .frame(maxWidth: 300, maxHeight: 300)
                    .padding(32)
                    .accessibilityHidden(true)
                VStack(spacing: 16) {
                    HStack {
                        Button(action: { presentationMode.wrappedValue.dismiss() }) {
                            Image(systemName: "xmark")
                                .font(.headline)
                                .frame(width: 44, height: 44)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                        .foregroundColor(.white)
                        .accessibilityLabel("关闭扫码")
                        .accessibilityIdentifier("scanner.close")
                        Spacer()
                        Text("扫描二维码")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Capsule())
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("scanner.page")
                    }
                    Spacer()
                    if availability != .ready && availability != .checking {
                        scannerUnavailableCard
                    }
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("RTC 二维码应包含 app_id、remote_id 与 token；云录像可直接使用 Token，或包含 app_id、endpoint 与 token。")
                            Text("Token 只用于本次连接，不会保存。")
                                .foregroundColor(Color.white.opacity(0.75))
                        }
                        .font(.footnote)
                        .padding(.top, 8)
                    } label: {
                        Label("二维码内容格式", systemImage: "info.circle")
                            .font(.headline)
                    }
                    .padding(16)
                    .foregroundColor(.white)
                    .background(Color.black.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .accessibilityIdentifier("scanner.help")
                }
                .padding(20)
            }
            .background(Color.black)
        }

        private var scannerUnavailableCard: some View {
            VStack(spacing: 12) {
                Image(systemName: availability == .denied ? "camera.fill" : "camera.slash.fill")
                    .font(.title)
                Text(availability.accessibilitySummary)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("scanner.status")
                if availability == .denied {
                    Button("打开系统设置") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("scanner.open_settings")
                }
                Button("返回手动输入") { presentationMode.wrappedValue.dismiss() }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("scanner.manual_input")
            }
            .padding(16)
            .foregroundColor(.white)
            .background(Color.black.opacity(0.82))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .contain)
        }
    }

    private struct ExampleQRCodeCamera: UIViewControllerRepresentable {
        let onPayload: (String) -> Void
        @Binding var availability: ExampleScannerAvailability

        func makeCoordinator() -> Coordinator {
            Coordinator(onPayload: onPayload, availability: $availability)
        }

        func makeUIViewController(context: Context) -> ScannerViewController {
            let controller = ScannerViewController()
            controller.delegate = context.coordinator
            controller.availabilityDidChange = { state in
                context.coordinator.availabilityDidChange(state)
            }
            controller.availabilityOverride = ProcessInfo.processInfo.environment[
                "TIRTC_EXAMPLE_SCANNER_AVAILABILITY_OVERRIDE"
            ].flatMap(ExampleScannerAvailability.init(rawValue:))
            return controller
        }

        func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}

        @MainActor final class Coordinator: NSObject, ScannerViewControllerDelegate {
            private let onPayload: (String) -> Void
            private var availability: Binding<ExampleScannerAvailability>

            init(
                onPayload: @escaping (String) -> Void,
                availability: Binding<ExampleScannerAvailability>
            ) {
                self.onPayload = onPayload
                self.availability = availability
            }

            func scannerViewController(_ controller: ScannerViewController, didRead payload: String) {
                onPayload(payload)
            }

            func availabilityDidChange(_ state: ExampleScannerAvailability) {
                availability.wrappedValue = state
            }
        }
    }

    @MainActor protocol ScannerViewControllerDelegate: AnyObject {
        func scannerViewController(_ controller: ScannerViewController, didRead payload: String)
    }

    final class ScannerViewController: UIViewController,
        AVCaptureMetadataOutputObjectsDelegate
    {
        weak var delegate: ScannerViewControllerDelegate?
        var availabilityDidChange: (@MainActor (ExampleScannerAvailability) -> Void)?
        var availabilityOverride: ExampleScannerAvailability?
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
            if let availabilityOverride {
                availabilityDidChange?(availabilityOverride)
                return
            }
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                attachCaptureSession()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                    guard granted else {
                        DispatchQueue.main.async {
                            self?.availabilityDidChange?(.denied)
                        }
                        return
                    }
                    DispatchQueue.main.async {
                        self?.attachCaptureSession()
                    }
                }
            case .denied:
                availabilityDidChange?(.denied)
            case .restricted:
                availabilityDidChange?(.restricted)
            @unknown default:
                availabilityDidChange?(.unavailable)
            }
        }

        private func attachCaptureSession() {
            guard
                let device = AVCaptureDevice.default(for: .video),
                let input = try? AVCaptureDeviceInput(device: device),
                session.canAddInput(input)
            else {
                availabilityDidChange?(.unavailable)
                return
            }

            session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else {
                availabilityDidChange?(.unavailable)
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
            availabilityDidChange?(.ready)
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
