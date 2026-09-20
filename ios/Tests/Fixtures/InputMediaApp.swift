import AVFoundation
import Foundation
import SwiftUI
import TiRTC

#if os(macOS)
    import AppKit
#endif

private func appendInputMediaStatus(_ message: String) {
    FileHandle.standardOutput.write(Data((message + "\n").utf8))
    guard
        let path = ProcessInfo.processInfo.environment["TIRTC_INPUT_MEDIA_STATUS_LOG"],
        !path.isEmpty
    else { return }
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true)
    if !FileManager.default.fileExists(atPath: path) {
        _ = FileManager.default.createFile(atPath: path, contents: nil)
    }
    guard let handle = FileHandle(forWritingAtPath: path) else { return }
    defer { handle.closeFile() }
    handle.seekToEndOfFile()
    handle.write(Data((message + "\n").utf8))
}

final class InputMediaCaptureCase: NSObject, TiRtcConnServiceDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var acceptedConnection: TiRtcConn?
    private var serviceError: Int32 = 0

    func connService(_ service: TiRtcConnService, didAccept connection: TiRtcConn) {
        lock.withLock { acceptedConnection = connection }
    }

    func connService(_ service: TiRtcConnService, didFailWithCode code: Int32, message: String?) {
        lock.withLock { serviceError = code }
    }

    @MainActor
    private func releaseAfterCallbacks(_ operation: () -> Int32) async -> Int32 {
        let deadline = Date().addingTimeInterval(5)
        var code = operation()
        while code == 6026 && Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
            code = operation()
        }
        return code
    }

    @MainActor
    func run(payload: [String: String], status: (String) -> Void) async throws {
        func required(_ key: String) throws -> String {
            guard let value = payload[key], !value.isEmpty else {
                throw NSError(
                    domain: "InputMediaCapture", code: 6000, userInfo: [NSLocalizedDescriptionKey: "missing \(key)"])
            }
            return value
        }
        func requireOk(_ operation: String, _ code: Int32, expected: Int32 = 0) throws {
            guard code == expected else {
                throw NSError(
                    domain: "InputMediaCapture", code: Int(code), userInfo: [NSLocalizedDescriptionKey: operation])
            }
        }
        status("input_media_permission_request")
        #if targetEnvironment(simulator)
            let cameraAvailable = AVCaptureDevice.default(for: .video) != nil
            if !cameraAvailable { status("input_media_camera_unavailable") }
        #else
            let cameraAvailable = true
        #endif
        let microphoneGranted = await AVCaptureDevice.requestAccess(for: .audio)
        let cameraGranted = cameraAvailable ? await AVCaptureDevice.requestAccess(for: .video) : true
        guard microphoneGranted && cameraGranted else {
            throw NSError(
                domain: "InputMediaCapture", code: 6024,
                userInfo: [NSLocalizedDescriptionKey: "capture permission denied"])
        }
        let initOptions = TiRtcInitOptions(appId: try required("app_id"))
        initOptions.endpoint = try required("endpoint")
        initOptions.consoleLogEnabled = true
        try requireOk("initialize", TiRtc.initialize(initOptions))
        let audio = TiRtcAudioInput()
        let video = TiRtcVideoInput()
        let service = TiRtcConnService(
            config: TiRtcConnServiceConfig(
                deviceId: try required("device_id"), deviceSecretKey: try required("device_secret_key"),
                clientId: try required("client_id")))
        service.delegate = self
        var primaryError: Error?
        do {
            if let token = payload["token"] {
                let conn = TiRtcConn()
                lock.withLock { acceptedConnection = conn }
                try requireOk("connect", conn.connect(remoteId: try required("device_id"), token: token))
                let deadline = Date().addingTimeInterval(30)
                while conn.state != .connected && Date() < deadline {
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
                guard conn.state == .connected else { throw NSError(domain: "InputMediaCapture connect", code: 6028) }
            } else {
                try requireOk("service start", service.start())
            }
            status("input_media_service_started")
            let deadline = Date().addingTimeInterval(35)
            while lock.withLock({ acceptedConnection == nil && serviceError == 0 }) && Date() < deadline {
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            try requireOk("service", lock.withLock { serviceError })
            guard let conn = lock.withLock({ acceptedConnection }) else {
                throw NSError(domain: "InputMediaCapture", code: 6028)
            }
            let audioOptions = TiRtcAudioInputOptions()
            audioOptions.media = 2
            try requireOk("warm configure", audio.setOptions(audioOptions))
            try requireOk("warm attach", audio.attach(connection: conn, streamId: 13))
            try requireOk("warm start", audio.start())
            try await Task.sleep(nanoseconds: 300_000_000)
            try requireOk("warm stop", audio.stop())
            try requireOk("warm detach", audio.detach(connection: conn))
            audioOptions.media = Int(try required("audio_media"))!
            if audioOptions.media == -1 { audioOptions.setValue(2, forKey: "codec") }
            try requireOk("audio configure", audio.setOptions(audioOptions))
            let invalidAudio = TiRtcAudioInputOptions()
            invalidAudio.media = 65
            try requireOk("invalid audio", audio.setOptions(invalidAudio), expected: 6000)
            let videoOptions = TiRtcVideoInputOptions()
            videoOptions.media = Int(try required("video_media"))!
            try requireOk("video configure", video.setOptions(videoOptions))
            let invalidVideo = TiRtcVideoInputOptions()
            invalidVideo.media = 67
            try requireOk("invalid video", video.setOptions(invalidVideo), expected: 6000)
            try requireOk("audio attach", audio.attach(connection: conn, streamId: 14))
            if cameraAvailable { try requireOk("video attach", video.attach(connection: conn, streamId: 15)) }
            try requireOk("audio start", audio.start())
            if cameraAvailable { try requireOk("video start", video.start()) }
            try requireOk("running audio", audio.setOptions(audioOptions), expected: 6026)
            if cameraAvailable { try requireOk("running video", video.setOptions(videoOptions), expected: 6026) }
            status("input_media_started audio=\(audioOptions.media) video=\(videoOptions.media)")
            try await Task.sleep(nanoseconds: 20_000_000_000)
        } catch { primaryError = error }
        var codes = [audio.stop()]
        if cameraAvailable { codes.insert(video.stop(), at: 0) }
        if let conn = lock.withLock({ acceptedConnection }) {
            if cameraAvailable { codes.append(video.detach(connection: conn)) }
            codes += [audio.detach(connection: conn), video.dispose(), audio.dispose(), conn.disconnect()]
            let deadline = Date().addingTimeInterval(5)
            while conn.state != .disconnected && conn.state != .idle && Date() < deadline {
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            codes.append(await releaseAfterCallbacks { conn.dispose() })
        } else {
            codes += [video.dispose(), audio.dispose()]
        }
        codes += [await releaseAfterCallbacks { service.dispose() }, await releaseAfterCallbacks { TiRtc.shutdown() }]
        if let primaryError { throw primaryError }
        guard codes.allSatisfy({ $0 == 0 }) else {
            throw NSError(
                domain: "InputMediaCapture cleanup \(codes)",
                code: Int(codes.first(where: { $0 != 0 })!))
        }
        status("input_media_teardown")
    }
}

// This test-owned App replaces only the entry point in the generated Example workspace.
@main
struct InputMediaApp: App {
    #if os(macOS)
        @NSApplicationDelegateAdaptor(InputMediaAppDelegate.self) private var delegate
    #endif
    var body: some Scene {
        #if os(macOS)
            Settings { EmptyView() }
        #else
            WindowGroup { InputMediaView() }
        #endif
    }
}

#if os(macOS)
    @MainActor
    private final class InputMediaAppDelegate: NSObject, NSApplicationDelegate {
        private var window: NSWindow?
        func applicationDidFinishLaunching(_ notification: Notification) {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 240),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "TiRTC input media test"
            window.contentView = NSHostingView(rootView: InputMediaView())
            NSApplication.shared.setActivationPolicy(.regular)
            NSApplication.shared.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            self.window = window
        }
    }
#endif

private struct InputMediaView: View {
    @State private var result = "Input Media Case Running"
    var body: some View {
        Text(result).padding().onAppear {
            Task {
                #if os(macOS)
                    NSApplication.shared.setActivationPolicy(.regular)
                    NSApplication.shared.activate(ignoringOtherApps: true)
                #endif
                do {
                    let environment = ProcessInfo.processInfo.environment
                    let payloadFile = environment["TIRTC_INPUT_MEDIA_PAYLOAD_FILE"] ?? ""
                    let encoded =
                        environment["TIRTC_INPUT_MEDIA_PAYLOAD"]
                        ?? (try? String(contentsOfFile: payloadFile, encoding: .utf8)) ?? ""
                    guard let data = Data(base64Encoded: encoded),
                        let payload = try JSONSerialization.jsonObject(with: data) as? [String: String]
                    else {
                        throw NSError(domain: "InputMediaCapture payload", code: 6000)
                    }
                    try await InputMediaCaptureCase().run(
                        payload: payload, status: appendInputMediaStatus)
                    result = "Input Media Case Passed"
                } catch { result = "Input Media Case Failed: \(error)" }
                appendInputMediaStatus(result)
            }
        }
    }
}
