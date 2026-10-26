import Foundation
import TiRTC

#if !os(macOS)
    import AVFoundation
#endif

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
        let restart = payload["case_id"] == "smoke.talkback-restart"
        var restartReceipt: [String: Any]?
        let customNoCapture = payload["input_mode"] == "custom-no-capture"
        let cameraAvailable: Bool
        #if os(macOS)
            guard customNoCapture else {
                throw NSError(
                    domain: "InputMediaCapture", code: 6000,
                    userInfo: [NSLocalizedDescriptionKey: "macOS uses custom PCM without capture"])
            }
            cameraAvailable = false
            status("input_media_no_capture_ready")
        #else
            if customNoCapture {
                cameraAvailable = false
                status("input_media_no_capture_ready")
            } else {
                status("input_media_permission_request")
                #if targetEnvironment(simulator)
                    cameraAvailable = !restart && AVCaptureDevice.default(for: .video) != nil
                    if !cameraAvailable { status("input_media_camera_unavailable") }
                #else
                    cameraAvailable = !restart
                #endif
                let microphoneGranted = await AVCaptureDevice.requestAccess(for: .audio)
                #if targetEnvironment(simulator)
                    let cameraGranted = cameraAvailable ? await AVCaptureDevice.requestAccess(for: .video) : true
                #else
                    let cameraGranted = await AVCaptureDevice.requestAccess(for: .video)
                #endif
                guard microphoneGranted && cameraGranted else {
                    throw NSError(
                        domain: "InputMediaCapture", code: 6024,
                        userInfo: [NSLocalizedDescriptionKey: "capture permission denied"])
                }
            }
        #endif
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
        var serviceAcceptObserved = false
        let connectionRole = payload["token"] == nil ? "service" : "client"
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
            serviceAcceptObserved = connectionRole == "service"
            if restart {
                #if !os(macOS)
                    restartReceipt = try await runTalkbackRestartCase(audio: audio, connection: conn, status: status)
                    // Retain the connected fixture while the bounded receiving peer completes.
                    try await Task.sleep(nanoseconds: 12_000_000_000)
                #endif
            } else {
                let audioOptions = TiRtcAudioInputOptions()
                if !customNoCapture {
                    audioOptions.media = 2
                    try requireOk("warm configure", audio.setOptions(audioOptions))
                    try requireOk("warm attach", audio.attach(connection: conn, streamId: 13))
                    try requireOk("warm start", audio.start())
                    try await Task.sleep(nanoseconds: 300_000_000)
                    try requireOk("warm stop", audio.stop())
                    try requireOk("warm detach", audio.detach(connection: conn))
                }
                audioOptions.media = Int(try required("audio_media"))!
                if customNoCapture {
                    audioOptions.mode = .custom
                    audioOptions.captureEnabled = false
                }
                if audioOptions.media == -1 { audioOptions.setValue(2, forKey: "codec") }
                try requireOk("audio configure", audio.setOptions(audioOptions))
                let invalidAudio = TiRtcAudioInputOptions()
                invalidAudio.media = 65
                try requireOk("invalid audio", audio.setOptions(invalidAudio), expected: 6000)
                let videoOptions = TiRtcVideoInputOptions()
                if !customNoCapture {
                    videoOptions.media = Int(try required("video_media"))!
                    try requireOk("video configure", video.setOptions(videoOptions))
                    let invalidVideo = TiRtcVideoInputOptions()
                    invalidVideo.media = 67
                    try requireOk("invalid video", video.setOptions(invalidVideo), expected: 6000)
                }
                try requireOk("audio attach", audio.attach(connection: conn, streamId: 14))
                #if !os(macOS)
                    if cameraAvailable { try requireOk("video attach", video.attach(connection: conn, streamId: 15)) }
                #endif
                try requireOk("audio start", audio.start())
                #if !os(macOS)
                    if cameraAvailable { try requireOk("video start", video.start()) }
                #endif
                try requireOk("running audio", audio.setOptions(audioOptions), expected: 6026)
                #if !os(macOS)
                    if cameraAvailable {
                        try requireOk("running video", video.setOptions(videoOptions), expected: 6026)
                    }
                #endif
                status(
                    "input_media_started audio=\(audioOptions.media) video=\(videoOptions.media) "
                        + "custom_no_capture=\(customNoCapture)")
                if customNoCapture {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    let pcm = Data(base64Encoded: try required("pcm_base64")) ?? Data()
                    guard pcm.count == 32_000 else {
                        throw NSError(domain: "InputMediaCapture PCM", code: 6000)
                    }
                    try requireOk("submit pcm", audio.submitPCM(pcm))
                    status("input_media_pcm_submitted bytes=32000 calls=1")
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } else {
                    try await Task.sleep(nanoseconds: 20_000_000_000)
                }
            }
        } catch { primaryError = error }
        audio.onPCMCaptured = nil
        var codes: [String: Int32] = ["audio_stop": restart && audio.state != .running ? 0 : audio.stop()]
        #if !os(macOS)
            if cameraAvailable { codes["video_stop"] = video.stop() }
        #endif
        if let conn = lock.withLock({ acceptedConnection }) {
            #if !os(macOS)
                if cameraAvailable { codes["video_detach"] = video.detach(connection: conn) }
            #endif
            codes["audio_detach"] = audio.detach(connection: conn)
            codes["video_dispose"] = video.dispose()
            codes["audio_dispose"] = audio.dispose()
            codes["connection_disconnect"] = conn.disconnect()
            let deadline = Date().addingTimeInterval(5)
            while conn.state != .disconnected && conn.state != .idle && Date() < deadline {
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            codes["connection_dispose"] = await releaseAfterCallbacks { conn.dispose() }
        } else {
            codes["video_dispose"] = video.dispose()
            codes["audio_dispose"] = audio.dispose()
        }
        codes["service_dispose"] = await releaseAfterCallbacks { service.dispose() }
        codes["shutdown"] = await releaseAfterCallbacks { TiRtc.shutdown() }
        if let resultPath = payload["result_path"] {
            #if arch(x86_64)
                let architecture = "x86_64"
            #else
                let architecture = "arm64"
            #endif
            var result: [String: Any] = [
                "schema": "tirtc.darwin-input-media/v1",
                "architecture": architecture,
                "connection_role": connectionRole,
                "service_accept_observed": serviceAcceptObserved,
                "case_id": payload["case_id"] ?? "", "process_id": ProcessInfo.processInfo.processIdentifier,
                "status": primaryError == nil && codes.values.allSatisfy({ $0 == 0 }) ? "passed" : "failed",
                "camera_available": cameraAvailable, "cleanup_codes": codes,
                "input_mode": customNoCapture ? "custom-no-capture" : "built-in",
                "microphone_permission_request": customNoCapture ? "not-requested" : "requested",
                "submitted_pcm_bytes": customNoCapture ? 32_000 : 0,
                "submit_calls": customNoCapture ? 1 : 0,
            ]
            if let restartReceipt { result["restart_receipt"] = restartReceipt }
            let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
            try data.write(to: URL(fileURLWithPath: resultPath), options: .atomic)
        }
        if let primaryError { throw primaryError }
        guard codes.values.allSatisfy({ $0 == 0 }) else {
            throw NSError(
                domain: "InputMediaCapture cleanup \(codes)",
                code: Int(codes.values.first(where: { $0 != 0 })!))
        }
        status("input_media_teardown")
    }
}
