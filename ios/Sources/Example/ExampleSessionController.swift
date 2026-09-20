import AVFoundation
import CoreGraphics
import Foundation
import Photos
import TiRTC

@MainActor
final class ExampleSessionController: NSObject, ObservableObject {
    enum StreamDefaults {
        static let audio: UInt8 = 10
        static let video: UInt8 = 11
        static let message: UInt8 = 12
    }

    enum ControlDefaults {
        static let probeStreamId: UInt8 = 90
    }

    enum DiagnosticsDefaults {
        static let refreshIntervalSeconds: Double = 2.0
    }

    enum MetricsDisplayDefaults {
        static let mediaCodecAudioG711A: Int32 = 1
        static let mediaCodecAudioAAC: Int32 = 2
        static let mediaCodecAudioPCM: Int32 = 3
        static let mediaCodecAudioOPUS: Int32 = 4
        static let mediaCodecAudioAMR: Int32 = 5
        static let mediaCodecVideoH264: Int32 = 65
        static let mediaCodecVideoH265: Int32 = 66
        static let mediaCodecVideoMJPEG: Int32 = 67
        static let decoderPreferenceAutomatic: Int32 = 0
        static let decoderBackendSoftware: Int32 = 1
        static let decoderBackendHardware: Int32 = 2
    }

    struct ClientCleanupResources: @unchecked Sendable {
        let conn: TiRtcConn?
        let localAudioInput: TiRtcAudioInput?
        let audioOutput: TiRtcAudioOutput?
        let videoOutputs: [TiRtcVideoOutput]
        let audioStreamId: UInt8?
        let videoStreamIds: [UInt8]
        let shouldShutdownRuntime: Bool
        let statusLogPath: String?

        var isEmpty: Bool {
            conn == nil && localAudioInput == nil && audioOutput == nil && videoOutputs.isEmpty
                && !shouldShutdownRuntime
        }

        // Both cleanup entry points run off the main actor: an in-flight iOS frame may be waiting
        // to present on the main thread while detachView waits for that frame to finish.
        func stopStreamingForConfigureRoute() {
            for output in videoOutputs { _ = output.detachView() }
            if let conn {
                _ = localAudioInput?.detach(connection: conn)
            }
            _ = localAudioInput?.stop()
            let videoUnsubscribeCodes = videoStreamIds.map { conn?.unsubscribeVideo(streamId: $0) ?? 0 }
            let audioUnsubscribeCode = audioStreamId.map { conn?.unsubscribeAudio(streamId: $0) ?? 0 } ?? 0
            _ = conn?.disconnect()
            for output in videoOutputs { _ = output.detach() }
            _ = audioOutput?.detach()
            localAudioInput?.dispose()
            ExampleSessionController.appendCallbackStatusLogLine(
                "unsubscribe audio=\(audioUnsubscribeCode) videos=\(videoUnsubscribeCodes) audio_stream=\(String(describing: audioStreamId)) video_streams=\(videoStreamIds)",
                path: statusLogPath)
            ExampleSessionController.appendCallbackStatusLogLine("cleaned", path: statusLogPath)
        }

        func cleanUp() -> Int32 {
            let videoViewDetachCodes = videoOutputs.map { $0.detachView() }
            let audioInputDetachCode: Int32
            if let conn {
                audioInputDetachCode = localAudioInput?.detach(connection: conn) ?? 0
            } else {
                audioInputDetachCode = 0
            }
            let audioInputStopCode = localAudioInput?.stop() ?? 0
            let videoUnsubscribeCodes = videoStreamIds.map { conn?.unsubscribeVideo(streamId: $0) ?? 0 }
            let audioUnsubscribeCode = audioStreamId.map { conn?.unsubscribeAudio(streamId: $0) ?? 0 } ?? 0
            let disconnectCode = conn?.disconnect() ?? 0
            let videoDetachCodes = videoOutputs.map { $0.detach() }
            let audioDetachCode = audioOutput?.detach() ?? 0
            let videoDisposeCodes = videoOutputs.map { $0.dispose() }
            let audioDisposeCode = audioOutput?.dispose() ?? 0
            let audioInputDisposeCode = localAudioInput?.dispose() ?? 0
            let connectionDisposeCode = conn?.dispose() ?? 0
            let shutdownCode = shouldShutdownRuntime ? TiRtc.shutdown() : 0
            let cleanupCodes: [Int32] =
                videoViewDetachCodes + [
                    audioInputDetachCode,
                    audioInputStopCode,
                ] + videoUnsubscribeCodes + [
                    audioUnsubscribeCode,
                    disconnectCode,
                ] + videoDetachCodes + [
                    audioDetachCode
                ] + videoDisposeCodes + [
                    audioDisposeCode,
                    audioInputDisposeCode,
                    connectionDisposeCode,
                    shutdownCode,
                ]
            let cleanupCode: Int32 = cleanupCodes.first(where: { $0 != 0 }) ?? 0
            ExampleSessionController.appendCallbackStatusLogLine(
                "unsubscribe audio=\(audioUnsubscribeCode) videos=\(videoUnsubscribeCodes) audio_stream=\(String(describing: audioStreamId)) video_streams=\(videoStreamIds)",
                path: statusLogPath)
            ExampleSessionController.appendCallbackStatusLogLine(
                "client_cleanup_resources_released code=\(cleanupCode) "
                    + "video_view_detach=\(videoViewDetachCodes) "
                    + "audio_input_detach=\(audioInputDetachCode) "
                    + "audio_input_stop=\(audioInputStopCode) "
                    + "video_unsubscribe=\(videoUnsubscribeCodes) "
                    + "audio_unsubscribe=\(audioUnsubscribeCode) "
                    + "disconnect=\(disconnectCode) video_detach=\(videoDetachCodes) "
                    + "audio_detach=\(audioDetachCode) video_dispose=\(videoDisposeCodes) "
                    + "audio_dispose=\(audioDisposeCode) "
                    + "audio_input_dispose=\(audioInputDisposeCode) "
                    + "connection_dispose=\(connectionDisposeCode) shutdown=\(shutdownCode)",
                path: statusLogPath)
            return cleanupCode
        }
    }

    static let clientCleanupQueue = DispatchQueue(label: "com.tirtc.example.client-cleanup")

    @Published var appId = "darwin-example-app"
    @Published var remoteId = ""
    @Published var token = ""
    @Published var endpoint = ""
    @Published var tokenSource = ExampleTokenSource.oneTime.rawValue
    @Published var tokenIssuerBaseUrl = ""
    @Published var audioStreamId = String(StreamDefaults.audio)
    @Published var videoStreamIds = [String(StreamDefaults.video)]
    @Published var selectedVideoStreamId: UInt8? = StreamDefaults.video
    @Published var maximizedVideoStreamId: UInt8?
    @Published var videoStates: [UInt8: TiRtcVideoOutputState] = [:]
    @Published var statusText = "idle"
    @Published var errorSummary: String?
    @Published var isClientVideoRendering = false
    @Published var isClientConnecting = false
    @Published var isAudioOutputAvailable = false
    @Published var isClientPlayerActive = false
    @Published var isSettingsPresented = false
    @Published var metricsSummary = "metrics unavailable"
    @Published var debugSummary = "debug unavailable"
    @Published var decoderPreference = ExampleVideoDecoderPreference.automatic.rawValue
    @Published var outputBufferPolicy = ExampleOutputBufferPolicy.automatic.rawValue
    @Published var localAudioCodec = ExampleAudioCodec.g711a.rawValue
    @Published var localAudioSampleRate = String(ExampleAudioSampleRate.rate16k.rawValue)
    @Published var localAudioStreamId = String(StreamDefaults.audio)
    @Published var localAudioAecEnabled = false
    @Published var localAudioAgcLevel = String(ExampleLocalAudioProcessingLevel.disabled.rawValue)
    @Published var localAudioAnsLevel = String(ExampleLocalAudioProcessingLevel.disabled.rawValue)
    @Published var isClientLocalAudioRunning = false
    @Published var isClientLocalAudioBusy = false
    @Published var clientLocalAudioStatus = "local audio idle"
    @Published var isAudioOutputMuted = false
    @Published var audioOutputVolumeStatus = "audible"
    @Published var consoleLogEnabled = true
    @Published var isCommandPanelPresented = false
    @Published var commandIdText = ExampleCommandPanelCodec.defaultCommandIdText
    @Published var commandPayloadText = ""
    @Published var commandPayloadMode = ExampleCommandPanelPayloadMode.hex.rawValue
    @Published var commandEvents: [ExampleCommandPanelEvent] = []
    @Published var isLogUploadInProgress = false
    @Published var logUploadResult: ExampleLogUploadResult?
    @Published var rawDumpButtonState = ExampleRawDumpButtonState.idle
    @Published var isMetricsExplanationPresented = false
    @Published var mediaParameterSummary = "--"
    @Published var videoReceiveSummary = "video receive unavailable"
    @Published var audioReceiveSummary = "audio receive unavailable"
    @Published var audioStutterSummary = "--"
    @Published var videoOutputLatencySummary = "--"
    @Published var audioOutputLatencySummary = "--"
    @Published var connectionDurationSummary = "connection duration unavailable"
    @Published var firstFrameDurationSummary = "first frame unavailable"
    @Published var sessionStutterRatioSummary = "--"
    @Published var sessionStutterCountSummary = "--"
    @Published var sessionStutterPeakSummary = "--"
    @Published var pendingSummary = "pending unavailable"
    @Published var isClientQRCodeScannerPresented = false
    @Published var isMediaFileBusy = false
    @Published var isRecording = false
    @Published var hasLatestMedia = false

    let statusLogURL: URL?
    let settingsStore: ExampleSettingsStore
    nonisolated(unsafe) var callbackStatusLogPath: String?
    var activeClientConfiguration: ExampleClientConfiguration?
    var conn: TiRtcConn?
    var rawDump: TiRawDump?
    var rawDumpArchiveReady = false
    var rawDumpArchiveEvidence: TiRawDumpArchive?
    var clientLocalAudioInput: TiRtcAudioInput?
    var audioOutput: TiRtcAudioOutput?
    var videoOutputs: [UInt8: TiRtcVideoOutput] = [:]
    var recordingTask: TiRtcRecordingTask?
    private var recordingTargetStreamId: UInt8?
    private var latestMediaTargetStreamId: UInt8?
    private var latestRecordingFile: TiRtcRecordingFile?
    private var latestSnapshotFile: TiRtcSnapshotFile?
    private var ownedRecordingFiles: [TiRtcRecordingFile] = []
    private var ownedSnapshotFiles: [TiRtcSnapshotFile] = []
    private var mediaOperationTask: Task<Void, Never>?
    var platformVideoViews: [UInt8: TiRtcPlatformView] = [:]
    var attachedPlatformVideoViews: [UInt8: TiRtcPlatformView] = [:]
    var lastLoggedVideoOutputSize = CGSize.zero
    var initialized = false
    var pendingLocalEchoReplies = 0
    var didApplyEnvironmentPayload = false
    var retiredClientCleanupResources: [ClientCleanupResources] = []
    var diagnosticsRefreshGeneration = 0
    var audioOutputMuteStartedAt: Date?
    var audioOutputMuteStartDurationMs: Int64?
    var audioOutputMuteStartStatsMs: Int64?

    var isSelectedVideoRendering: Bool {
        selectedVideoStreamId.map { videoStates[$0] == .rendering } ?? false
    }

    override init() {
        settingsStore = ExampleSettingsStore(userDefaults: .standard)
        if let path = ProcessInfo.processInfo.environment["TIRTC_EXAMPLE_STATUS_LOG"],
            !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            statusLogURL = URL(fileURLWithPath: path)
        } else {
            statusLogURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
                .appendingPathComponent("example.status.log")
        }
        super.init()
        callbackStatusLogPath = statusLogURL?.path
        loadSettings()
    }

    func handleSceneAppear() {
        if !didApplyEnvironmentPayload {
            didApplyEnvironmentPayload = true
            applyEnvironmentPayloadIfPresent()
        }
    }

    func handleSceneDisappear() {
        disconnect()
    }

    func attachPlatformVideoView(_ view: TiRtcPlatformView, streamId: UInt8) {
        platformVideoViews[streamId] = view
        configurePlatformVideoView(view)
        guard videoStates[streamId] != .failed, let videoOutput = videoOutputs[streamId] else {
            return
        }
        attachPlatformVideoViewIfNeeded(view, to: videoOutput, streamId: streamId)
    }

    func selectVideoStream(_ streamId: UInt8) {
        if selectedVideoStreamId == streamId {
            maximizedVideoStreamId = maximizedVideoStreamId == streamId ? nil : streamId
        } else {
            selectedVideoStreamId = streamId
            maximizedVideoStreamId = nil
        }
    }

    func startClient() {
        if (ExampleTokenSource(rawValue: tokenSource) ?? .oneTime) == .issuer {
            startClientWithIssuerToken()
            return
        }
        switch currentClientConfiguration() {
        case .failure(let error):
            showValidationError(error)
            return
        case .success(let configuration):
            startClient(configuration)
        }
    }

    private func startClient(_ configuration: ExampleClientConfiguration) {
        activeClientConfiguration = configuration
        persistClientSettings(configuration)
        isClientConnecting = true
        isClientVideoRendering = false
        isAudioOutputAvailable = false
        videoStates.removeAll()
        stopDiagnosticsRefreshLoop()
        isClientPlayerActive = true
        appendStatusLogLine("route_reached flow=client route=player")
        connect(configuration)
    }

    private func startClientWithIssuerToken() {
        switch currentClientConfiguration(tokenOverride: "v1.pending") {
        case .failure(let error):
            showValidationError(error)
        case .success(let seedConfiguration):
            let issuerRequest = makeTokenIssuerRequest(
                rawBaseUrl: tokenIssuerBaseUrl,
                remoteId: seedConfiguration.remoteId
            )
            guard let request = issuerRequest
            else {
                showValidationError(.invalidEndpoint)
                return
            }
            isClientConnecting = true
            isClientVideoRendering = false
            isClientPlayerActive = true
            setStatus("token issuer requesting")
            appendStatusLogLine("token_source=issuer request_started remote_id=\(seedConfiguration.remoteId)")
            URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                DispatchQueue.main.async {
                    guard let self else {
                        return
                    }
                    if let error {
                        self.isClientConnecting = false
                        self.isClientPlayerActive = false
                        self.errorSummary = "token issuer failed"
                        self.setStatus("token issuer failed: \(error.localizedDescription)")
                        return
                    }
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard (200..<300).contains(statusCode),
                        let data,
                        let token = self.parseTokenIssuerResponse(data)
                    else {
                        self.isClientConnecting = false
                        self.isClientPlayerActive = false
                        self.errorSummary = "token issuer failed"
                        self.setStatus("token issuer failed: http=\(statusCode)")
                        return
                    }
                    self.token = token
                    self.appendStatusLogLine("token_source=issuer resolved")
                    self.startClient(
                        ExampleClientConfiguration(
                            appId: seedConfiguration.appId,
                            endpoint: seedConfiguration.endpoint,
                            remoteId: seedConfiguration.remoteId,
                            audioStreamId: seedConfiguration.audioStreamId,
                            videoStreamIds: seedConfiguration.videoStreamIds,
                            token: token))
                }
            }.resume()
        }
    }

    func applyClientQRCodePayload(_ payload: String) {
        switch ExamplePayloadParser.parseClientQRCode(payload, preserving: endpoint) {
        case .failure(let error):
            showValidationError(error)
        case .success(let configuration):
            apply(configuration)
            clearUserFacingError()
            setStatus("client QR payload loaded")
            appendStatusLogLine("qr_payload_applied flow=client")
        }
    }

    func connect() {
        startClient()
    }

    func restartClient() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.finalizeRawDump(upload: false)
            await self.cleanUpLocalMediaFiles()
            await self.finishDisconnect()
            self.startClient()
        }
    }

    func stopClient() {
        setStatus("teardown_requested flow=client")
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.finalizeRawDump(upload: false)
            await self.cleanUpLocalMediaFiles()
            if ProcessInfo.processInfo.environment["TIRTC_EXAMPLE_FULL_CLEANUP_ON_STOP"] == "1" {
                await self.finishStopClientWithFullCleanup()
            } else {
                self.finishStopClient()
            }
        }
    }

    private func finishStopClientWithFullCleanup() async {
        let resources = takeClientCleanupResources(shouldShutdownRuntime: initialized)
        resetClientStateAfterStop()
        appendStatusLogLine("route_reached flow=client route=configure")
        let cleanupCode = await cleanUpClientResources(resources)
        finishClientCleanup(code: cleanupCode)
    }

    private func finishStopClient() {
        let resources = takeClientCleanupResources(shouldShutdownRuntime: false)
        if let resources {
            retiredClientCleanupResources.append(resources)
        }
        resetClientStateAfterStop()
        appendStatusLogLine("route_reached flow=client route=configure")
        scheduleClientStop(resources)
    }

    private func resetClientStateAfterStop() {
        isClientConnecting = false
        isClientVideoRendering = false
        isAudioOutputAvailable = false
        isClientLocalAudioBusy = false
        isClientLocalAudioRunning = false
        isAudioOutputMuted = false
        audioOutputVolumeStatus = "unavailable"
        audioOutputMuteStartedAt = nil
        audioOutputMuteStartDurationMs = nil
        audioOutputMuteStartStatsMs = nil
        clientLocalAudioStatus = "local audio idle"
        stopDiagnosticsRefreshLoop()
        isClientPlayerActive = false
        clearUserFacingError()
    }

    func toggleClientLocalAudio() {
        if isClientLocalAudioRunning || clientLocalAudioInput != nil {
            stopClientLocalAudio()
        } else {
            startClientLocalAudio()
        }
    }

    func toggleAudioOutputVolume() {
        guard let audioOutput else {
            audioOutputVolumeStatus = "failed output unavailable"
            appendStatusLogLine("audio_output_volume_toggle status=failed reason=output_unavailable")
            return
        }
        let targetVolume: UInt32 = isAudioOutputMuted ? 100 : 0
        let before = audioOutput.getMetricsSnapshot().snapshot
        let code = audioOutput.setVolume(targetVolume)
        let after = audioOutput.getMetricsSnapshot().snapshot
        if code == 0 {
            isAudioOutputMuted = targetVolume == 0
            audioOutputVolumeStatus = targetVolume == 0 ? "muted" : "audible"
        } else {
            audioOutputVolumeStatus = "failed code=\(code)"
        }
        appendStatusLogLine(
            "audio_output_volume_toggle target=\(targetVolume) code=\(code) state=\(audioOutput.state.rawValue) system_volume_write=false output_duration_ms_before=\(before?.stutter.outputDurationMs ?? -1) output_duration_ms_after=\(after?.stutter.outputDurationMs ?? -1) stats_updated_at_ms_before=\(before?.statsUpdatedAtMs ?? -1) stats_updated_at_ms_after=\(after?.statsUpdatedAtMs ?? -1) render_callback_rate=\(after?.audioRenderCallbackRate ?? -1)"
        )

        if targetVolume == 0, code == 0 {
            audioOutputMuteStartedAt = Date()
            audioOutputMuteStartDurationMs = after?.stutter.outputDurationMs
            audioOutputMuteStartStatsMs = after?.statsUpdatedAtMs
            return
        }
        guard targetVolume == 100, code == 0 else {
            return
        }
        let elapsedMs = Int64((Date().timeIntervalSince(audioOutputMuteStartedAt ?? Date())) * 1000)
        let outputDurationProgressMs =
            (before?.stutter.outputDurationMs ?? -1) - (audioOutputMuteStartDurationMs ?? -1)
        let statsProgressMs =
            (before?.statsUpdatedAtMs ?? -1) - (audioOutputMuteStartStatsMs ?? -1)
        let passed =
            elapsedMs >= 4_800
            && outputDurationProgressMs >= 4_500
            && statsProgressMs >= 4_000
            && (before?.audioRenderCallbackRate ?? 0) > 0
        let volumeEvidence =
            "audio_output_volume_verified status=\(passed ? "passed" : "failed") mute_hold_ms=\(elapsedMs) output_duration_progress_ms=\(outputDurationProgressMs) stats_progress_ms=\(statsProgressMs) render_callback_rate=\(before?.audioRenderCallbackRate ?? -1) system_volume_write=false"
        audioOutputVolumeStatus = volumeEvidence
        appendStatusLogLine(volumeEvidence)
        audioOutputMuteStartedAt = nil
        audioOutputMuteStartDurationMs = nil
        audioOutputMuteStartStatsMs = nil
    }

    func toggleRecording() {
        guard !isMediaFileBusy else { return }
        if let task = recordingTask {
            isMediaFileBusy = true
            let targetStreamId = recordingTargetStreamId
            recordingTargetStreamId = nil
            mediaOperationTask = Task { @MainActor [weak self] in
                guard let self else { return }
                let result = await task.stop()
                self.recordingTask = nil
                self.isRecording = false
                self.isMediaFileBusy = false
                if result.code == 0 {
                    self.latestRecordingFile = result.file
                    self.latestMediaTargetStreamId = targetStreamId
                    self.latestSnapshotFile = nil
                    self.hasLatestMedia = result.file != nil
                    if let file = result.file {
                        self.ownedRecordingFiles.append(file)
                    }
                }
                self.setStatus(
                    result.code == 0
                        ? "本地保存完成 · \(result.file?.path ?? "")"
                        : "本地保存失败 · code=\(result.code)")
                self.appendStatusLogLine(
                    "media_recording_stop code=\(result.code) duration_ms=\(result.file?.durationMs ?? -1)")
                self.mediaOperationTask = nil
            }
            return
        }
        guard let conn, let configuration = activeClientConfiguration,
            let targetStreamId = selectedVideoStreamId
        else {
            setStatus("开始本地保存失败 · 播放未就绪")
            return
        }
        let result = conn.startRecording(
            videoStreamId: Int32(targetStreamId),
            audioStreamId: configuration.audioStreamId.map { NSNumber(value: $0) })
        guard result.code == 0, let task = result.task else {
            setStatus("开始本地保存失败 · code=\(result.code)")
            return
        }
        recordingTask = task
        recordingTargetStreamId = targetStreamId
        isRecording = true
        setStatus("正在本地保存")
        appendStatusLogLine("media_recording_start code=0")
    }

    func takeSnapshot() {
        guard !isMediaFileBusy, let streamId = selectedVideoStreamId,
            let videoOutput = videoOutputs[streamId]
        else { return }
        isMediaFileBusy = true
        mediaOperationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await videoOutput.takeSnapshot()
            guard result.code == 0, let file = result.file else {
                self.isMediaFileBusy = false
                self.setStatus("截图失败 · code=\(result.code)")
                self.appendStatusLogLine("media_snapshot_complete code=\(result.code)")
                self.mediaOperationTask = nil
                return
            }
            self.latestSnapshotFile = file
            self.latestMediaTargetStreamId = streamId
            self.latestRecordingFile = nil
            self.hasLatestMedia = true
            self.ownedSnapshotFiles.append(file)
            self.isMediaFileBusy = false
            self.setStatus("截图完成 · \(file.path)")
            self.appendStatusLogLine("media_snapshot_complete code=0")
            self.mediaOperationTask = nil
        }
    }

    func saveLatestToGallery() {
        guard !isMediaFileBusy else { return }
        let recording = latestRecordingFile
        let snapshot = latestSnapshotFile
        guard let path = recording?.path ?? snapshot?.path else { return }
        isMediaFileBusy = true
        mediaOperationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let publishCode = await Self.publishToPhotos(
                path: path, isVideo: recording != nil, targetId: latestMediaTargetStreamId ?? 0)
            let deleteCode: Int32
            if publishCode == 0 {
                deleteCode = recording != nil ? await recording!.delete() : await snapshot!.delete()
            } else {
                deleteCode = publishCode
            }
            if deleteCode == 0 {
                self.ownedRecordingFiles.removeAll { $0.path == path }
                self.ownedSnapshotFiles.removeAll { $0.path == path }
                self.latestRecordingFile = nil
                self.latestSnapshotFile = nil
                self.hasLatestMedia = false
                self.latestMediaTargetStreamId = nil
            }
            self.isMediaFileBusy = false
            self.setStatus(deleteCode == 0 ? "已保存到系统相册" : "保存到相册失败 · code=\(deleteCode)")
            self.appendStatusLogLine("media_gallery_save code=\(deleteCode)")
            self.mediaOperationTask = nil
        }
    }

    nonisolated private static func publishToPhotos(path: String, isVideo: Bool, targetId: UInt8) async -> Int32 {
        var authorization = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if authorization == .notDetermined {
            authorization = await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization(for: .addOnly) {
                    continuation.resume(returning: $0)
                }
            }
        }
        guard authorization == .authorized || authorization == .limited else { return -1 }
        let source = URL(fileURLWithPath: path)
        let alias = FileManager.default.temporaryDirectory.appendingPathComponent(
            "tirtc-\(isVideo ? "recording" : "snapshot")-stream-\(targetId).\(isVideo ? "mp4" : "jpg")")
        do {
            try? FileManager.default.removeItem(at: alias)
            try FileManager.default.copyItem(at: source, to: alias)
        } catch {
            return -1
        }
        let result: Int32 = await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                if isVideo {
                    _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: alias)
                } else {
                    _ = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: alias)
                }
            } completionHandler: { success, _ in
                continuation.resume(returning: success ? 0 : -1)
            }
        }
        try? FileManager.default.removeItem(at: alias)
        return result
    }

    private func startClientLocalAudio() {
        guard !isClientLocalAudioBusy else {
            return
        }
        guard let conn else {
            clientLocalAudioStatus = "local audio connection unavailable"
            setStatus(clientLocalAudioStatus)
            return
        }
        guard let streamId = UInt8(localAudioStreamId.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            showValidationError(.invalidStreamId("local_audio_stream_id"))
            return
        }
        isClientLocalAudioBusy = true
        clientLocalAudioStatus = "local audio permission checking"
        appendStatusLogLine("client.local_audio permission_requested")
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            let microphone = await self.requestMediaPermission(.audio)
            guard microphone == "granted" else {
                self.isClientLocalAudioBusy = false
                self.clientLocalAudioStatus = "microphone permission denied"
                self.errorSummary = "microphone permission denied"
                self.setStatus("microphone permission denied")
                self.appendStatusLogLine("client.local_audio permission_denied state=\(microphone)")
                return
            }
            let input = TiRtcAudioInput()
            input.delegate = self
            let options = self.resolvedClientLocalAudioOptions()
            let optionsCode = input.setOptions(options)
            let startCode = input.start()
            let attachCode = input.attach(connection: conn, streamId: streamId)
            self.clientLocalAudioInput = input
            self.isClientLocalAudioBusy = false
            self.isClientLocalAudioRunning = optionsCode == 0 && startCode == 0 && attachCode == 0
            let status =
                "client.local_audio started stream=\(streamId) options=\(optionsCode) start=\(startCode) attach=\(attachCode) nano_media=\(options.media) sample_rate_hz=\(options.sampleRate.rawValue) aec=\(options.aecMode.rawValue) agc=\(options.agcLevel.rawValue) ans=\(options.ansLevel.rawValue)"
            self.clientLocalAudioStatus = status
            self.appendStatusLogLine(status)
            if !self.isClientLocalAudioRunning {
                let errorCode = optionsCode != 0 ? optionsCode : (startCode != 0 ? startCode : attachCode)
                self.showUserFacingError(code: errorCode, context: "local audio")
            }
        }
    }

    private func stopClientLocalAudio() {
        guard let input = clientLocalAudioInput else {
            isClientLocalAudioBusy = false
            isClientLocalAudioRunning = false
            clientLocalAudioStatus = "local audio idle"
            return
        }
        isClientLocalAudioBusy = true
        let detachCode = conn.map { input.detach(connection: $0) } ?? 0
        let stopCode = input.stop()
        input.delegate = nil
        input.dispose()
        clientLocalAudioInput = nil
        isClientLocalAudioBusy = false
        isClientLocalAudioRunning = false
        let status = "client.local_audio stopped detach=\(detachCode) stop=\(stopCode)"
        clientLocalAudioStatus = status
        appendStatusLogLine(status)
    }

    private func connect(_ configuration: ExampleClientConfiguration) {
        activeClientConfiguration = configuration

        clearUserFacingError()
        lastLoggedVideoOutputSize = .zero

        let initCode = initializeIfNeeded()
        guard initCode == 0, let conn else {
            return
        }

        let audioStreamId = configuration.audioStreamId
        var audioCode: Int32 = 0
        if let audioStreamId, isAudioOutputAvailable, let audioOutput {
            audioCode = audioOutput.attach(connection: conn, streamId: audioStreamId)
        }
        if audioStreamId != nil, audioCode != 0 {
            isAudioOutputAvailable = false
            audioOutputVolumeStatus = "failed attach code=\(audioCode)"
            appendStatusLogLine("audio-output-failed phase=attach code=\(audioCode)")
        }
        var videoCodes: [UInt8: Int32] = [:]
        for videoStreamId in configuration.videoStreamIds {
            guard videoStates[videoStreamId] != .failed,
                let videoOutput = videoOutputs[videoStreamId]
            else { continue }
            let videoCode = videoOutput.attach(connection: conn, streamId: videoStreamId)
            videoCodes[videoStreamId] = videoCode
            guard videoCode == 0 else {
                videoStates[videoStreamId] = .failed
                appendStatusLogLine(
                    "video-output-failed phase=attach stream_id=\(videoStreamId) code=\(videoCode)")
                continue
            }
            if let platformVideoView = platformVideoViews[videoStreamId] {
                _ = attachPlatformVideoViewIfNeeded(
                    platformVideoView, to: videoOutput, streamId: videoStreamId)
            }
        }
        let connectCode = conn.connect(remoteId: configuration.remoteId, token: configuration.token)
        setStatus("connecting to \(configuration.remoteId)")
        appendStatusLogLine(
            "connect-start remote_id=\(configuration.remoteId) audio=\(audioCode) videos=\(videoCodes) connect=\(connectCode)"
        )

        if connectCode != 0 {
            showUserFacingError(code: connectCode, context: "connect")
        }
    }

    func subscribeDownlink(_ activeConnection: TiRtcConn) {
        let audioStreamId = resolvedAudioStreamId()
        let videoStreamIds = resolvedVideoStreamIds()
        var audioCode: Int32 = 0
        if let audioStreamId, isAudioOutputAvailable {
            audioCode = activeConnection.subscribeAudio(streamId: audioStreamId)
        }
        if audioStreamId != nil, audioCode != 0 {
            isAudioOutputAvailable = false
            audioOutputVolumeStatus = "failed subscribe code=\(audioCode)"
            appendStatusLogLine("audio-output-failed phase=subscribe code=\(audioCode)")
        }
        var videoCodes: [UInt8: Int32] = [:]
        for streamId in videoStreamIds where videoStates[streamId] != .failed {
            let code = activeConnection.subscribeVideo(streamId: streamId)
            videoCodes[streamId] = code
            if code != 0 {
                videoStates[streamId] = .failed
                appendStatusLogLine(
                    "video-output-failed phase=subscribe stream_id=\(streamId) code=\(code)")
            }
        }
        appendStatusLogLine(
            "subscribe audio=\(audioCode) videos=\(videoCodes) audio_stream=\(String(describing: audioStreamId)) video_streams=\(videoStreamIds)"
        )
        if !videoStreamIds.contains(where: { videoStates[$0] != .failed }) {
            isClientConnecting = false
        }
    }

    func disconnect() {
        appendStatusLogLine("teardown_requested flow=client")
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.finalizeRawDump(upload: false)
            await self.cleanUpLocalMediaFiles()
            await self.finishDisconnect()
        }
    }

    private func finishDisconnect() async {
        let resources = takeClientCleanupResources(shouldShutdownRuntime: initialized)
        let cleanupCode = await cleanUpClientResources(resources)
        finishClientCleanup(code: cleanupCode)
    }

    private func cleanUpClientResources(_ resources: ClientCleanupResources?) async -> Int32 {
        guard let resources else { return 0 }
        return await withCheckedContinuation { continuation in
            Self.clientCleanupQueue.async {
                continuation.resume(returning: resources.cleanUp())
            }
        }
    }

    private func finishClientCleanup(code: Int32) {
        if code == 0 {
            clearUserFacingError()
            setStatus("cleaned")
        } else {
            showUserFacingError(code: code, context: "client cleanup")
            setStatus("cleanup failed: \(TiRtc.formatError(code))")
        }
    }

    private func takeClientCleanupResources(shouldShutdownRuntime: Bool) -> ClientCleanupResources? {
        attachedPlatformVideoViews.removeAll()
        conn?.delegate = nil
        clientLocalAudioInput?.delegate = nil
        audioOutput?.delegate = nil
        for output in videoOutputs.values { output.delegate = nil }
        let resources = ClientCleanupResources(
            conn: conn,
            localAudioInput: clientLocalAudioInput,
            audioOutput: audioOutput,
            videoOutputs: Array(videoOutputs.values),
            audioStreamId: resolvedAudioStreamId(),
            videoStreamIds: resolvedVideoStreamIds(),
            shouldShutdownRuntime: shouldShutdownRuntime,
            statusLogPath: callbackStatusLogPath)
        conn = nil
        clientLocalAudioInput = nil
        audioOutput = nil
        videoOutputs.removeAll()
        platformVideoViews.removeAll()
        activeClientConfiguration = nil
        isAudioOutputAvailable = false
        videoStates.removeAll()
        selectedVideoStreamId = nil
        maximizedVideoStreamId = nil

        if resources.shouldShutdownRuntime {
            initialized = false
        }
        return resources.isEmpty ? nil : resources
    }

    private func cleanUpLocalMediaFiles() async {
        if let activeOperation = mediaOperationTask {
            await activeOperation.value
        }
        isMediaFileBusy = true
        if let task = recordingTask {
            recordingTask = nil
            isRecording = false
            let result = await task.stop()
            if let file = result.file {
                ownedRecordingFiles.append(file)
            }
            appendStatusLogLine(
                "media_recording_teardown code=\(result.code) duration_ms=\(result.file?.durationMs ?? -1)")
        }
        var remainingRecordingFiles: [TiRtcRecordingFile] = []
        for file in ownedRecordingFiles {
            if await file.delete() != 0 {
                remainingRecordingFiles.append(file)
            }
        }
        ownedRecordingFiles = remainingRecordingFiles
        var remainingSnapshotFiles: [TiRtcSnapshotFile] = []
        for file in ownedSnapshotFiles {
            if await file.delete() != 0 {
                remainingSnapshotFiles.append(file)
            }
        }
        ownedSnapshotFiles = remainingSnapshotFiles
        if ownedRecordingFiles.isEmpty && ownedSnapshotFiles.isEmpty {
            latestRecordingFile = nil
            latestSnapshotFile = nil
            hasLatestMedia = false
        }
        isMediaFileBusy = false
    }

    private func scheduleClientStop(_ resources: ClientCleanupResources?) {
        guard let resources else {
            statusText = "cleaned"
            return
        }
        Self.clientCleanupQueue.async { [weak self] in
            resources.stopStreamingForConfigureRoute()
            Task { @MainActor [weak self] in
                self?.statusText = "cleaned"
            }
        }
    }

    func initializeIfNeeded() -> Int32 {
        if initialized {
            prepareClientResourcesIfNeeded()
            return 0
        }

        let config = TiRtcInitOptions(appId: "darwin-example-app")
        if let activeClientConfiguration {
            config.appId = activeClientConfiguration.appId
            config.endpoint = activeClientConfiguration.endpoint
        }
        config.consoleLogEnabled = consoleLogEnabled
        let initCode = TiRtc.initialize(config)
        guard initCode == 0 else {
            setStatus("initialize failed")
            showUserFacingError(code: initCode, context: "initialize")
            return initCode
        }

        initialized = true
        prepareClientResourcesIfNeeded()

        return 0
    }

    private func prepareClientResourcesIfNeeded() {
        guard let configuration = activeClientConfiguration, conn == nil, audioOutput == nil,
            videoOutputs.isEmpty
        else {
            return
        }
        let conn = TiRtcConn(delegate: self)
        let audioOutput = configuration.audioStreamId.map { _ in TiRtcAudioOutput() }
        let videoOutputs = Dictionary(
            uniqueKeysWithValues: configuration.videoStreamIds.map { ($0, TiRtcVideoOutput()) })
        audioOutput?.delegate = self
        for output in videoOutputs.values { output.delegate = self }
        let audioOptions = TiRtcAudioOutputOptions()
        audioOptions.bufferStrategy = resolvedOutputBufferStrategy()
        let audioOptionsCode = audioOutput?.configure(audioOptions) ?? 0
        let videoOptions = TiRtcVideoOutputOptions()
        videoOptions.decoderPreference =
            (ExampleVideoDecoderPreference(rawValue: decoderPreference) ?? .automatic).sdkValue
        videoOptions.bufferStrategy = resolvedOutputBufferStrategy()
        let videoOptionCodes = videoOutputs.mapValues { $0.setOptions(videoOptions) }
        appendStatusLogLine(
            "client_output_options audio=\(audioOptionsCode) videos=\(videoOptionCodes) decoderPreference=\(decoderPreference)"
        )
        self.conn = conn
        self.audioOutput = audioOutput
        self.videoOutputs = videoOutputs
        selectedVideoStreamId = configuration.videoStreamIds.first
        isAudioOutputMuted = false
        isAudioOutputAvailable = audioOutput != nil && audioOptionsCode == 0
        audioOutputVolumeStatus = isAudioOutputAvailable ? "audible" : "unavailable"
        videoStates = videoOptionCodes.mapValues { $0 == 0 ? .idle : .failed }
        for (streamId, code) in videoOptionCodes where code != 0 {
            appendStatusLogLine(
                "video-output-failed phase=configure stream_id=\(streamId) code=\(code)")
        }
        if configuration.audioStreamId != nil, audioOptionsCode != 0 {
            audioOutputVolumeStatus = "failed configure code=\(audioOptionsCode)"
            appendStatusLogLine("audio-output-failed phase=configure code=\(audioOptionsCode)")
        }

        for (streamId, view) in platformVideoViews {
            if videoStates[streamId] != .failed, let output = videoOutputs[streamId] {
                _ = attachPlatformVideoViewIfNeeded(view, to: output, streamId: streamId)
            }
        }
    }

    private func applyEnvironmentPayloadIfPresent() {
        switch ProcessInfo.processInfo.environment["TIRTC_EXAMPLE_DECODER_PREFERENCE"] {
        case "software":
            decoderPreference = ExampleVideoDecoderPreference.software.rawValue
        case "hardware":
            decoderPreference = ExampleVideoDecoderPreference.hardware.rawValue
        case "automatic", "auto":
            decoderPreference = ExampleVideoDecoderPreference.automatic.rawValue
        default:
            break
        }
        guard let configuration = clientConfigurationFromEnvironment() else {
            return
        }
        apply(configuration)
        setStatus("payload loaded for \(configuration.remoteId)")
        let audioStreamDescription = configuration.audioStreamId.map(String.init) ?? "none"
        appendStatusLogLine(
            "payload loaded remote_id=\(configuration.remoteId) audio_stream=\(audioStreamDescription) video_stream=\(configuration.videoStreamId) message_stream=\(resolvedMessageStreamId())"
        )
    }

    private func requestMediaPermission(_ mediaType: AVMediaType) async -> String {
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized:
            return "granted"
        case .denied:
            return "denied"
        case .restricted:
            return "restricted"
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: mediaType)
            return granted ? "granted" : "denied"
        @unknown default:
            return "unknown"
        }
    }

    private func resolvedAudioStreamId() -> UInt8? {
        activeClientConfiguration?.audioStreamId
    }

    private func resolvedVideoStreamIds() -> [UInt8] {
        activeClientConfiguration?.videoStreamIds ?? []
    }

    private func resolvedMessageStreamId() -> UInt8 {
        StreamDefaults.message
    }

    private func resolvedOutputBufferStrategy() -> TiRtcOutputBufferStrategy {
        (ExampleOutputBufferPolicy(rawValue: outputBufferPolicy) ?? .automatic) == .noBuffer
            ? .noBuffer : .automatic
    }

    private func resolvedClientLocalAudioOptions() -> TiRtcAudioInputOptions {
        let options = TiRtcAudioInputOptions()
        switch ExampleAudioCodec(rawValue: localAudioCodec) ?? .g711a {
        case .g711a:
            options.media = 2
        case .aac:
            options.media = 3
        case .pcm:
            options.media = 1
        case .opus:
            options.media = 4
        case .amr:
            options.media = 5
        }
        options.sampleRate =
            Int(localAudioSampleRate).flatMap { ExampleAudioSampleRate(rawValue: $0) } == .rate8k
            ? .rate8k : .rate16k
        options.channels = .mono
        options.aecMode = localAudioAecEnabled ? .enabled : .disabled
        options.agcLevel = TiRtcAudioAgcLevel(rawValue: Int(localAudioAgcLevel) ?? 0) ?? .disabled
        options.ansLevel = TiRtcAudioAnsLevel(rawValue: Int(localAudioAnsLevel) ?? 0) ?? .disabled
        return options
    }

    private func makeTokenIssuerRequest(rawBaseUrl: String, remoteId: String) -> URLRequest? {
        guard let sourceUri = normalizedHTTPURL(rawBaseUrl) else {
            return nil
        }
        let fixedPath =
            sourceUri.query == nil
            && (sourceUri.path.isEmpty || sourceUri.path == "/" || sourceUri.path == "/v1/tokens")
        let url: URL
        var method = "GET"
        var body: Data?
        if fixedPath {
            var components = URLComponents()
            components.scheme = sourceUri.scheme
            components.host = sourceUri.host
            components.port = sourceUri.port
            components.path = "/v1/tokens"
            guard let tokenURL = components.url else {
                return nil
            }
            url = tokenURL
            method = "POST"
            body = try? JSONSerialization.data(withJSONObject: ["remote_id": remoteId])
        } else {
            url = sourceUri
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 10
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func normalizedHTTPURL(_ rawValue: String) -> URL? {
        guard var components = URLComponents(string: rawValue.trimmingCharacters(in: .whitespacesAndNewlines)),
            let scheme = components.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            components.host?.isEmpty == false,
            components.user == nil,
            components.fragment == nil
        else {
            return nil
        }
        components.scheme = scheme
        return components.url
    }

    private func parseTokenIssuerResponse(_ data: Data) -> String? {
        guard let text = String(data: data.prefix(8193), encoding: .utf8),
            data.count <= 8192
        else {
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("v1.") {
            return trimmed
        }
        guard let object = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)) as? [String: Any],
            let token = object["token"] as? String
        else {
            return nil
        }
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.hasPrefix("v1.") ? normalized : nil
    }

    private func configurePlatformVideoView(_ view: TiRtcPlatformView) {
        #if canImport(UIKit)
            view.backgroundColor = .black
        #elseif canImport(AppKit)
            view.wantsLayer = true
            view.layer?.backgroundColor = CGColor(gray: 0.0, alpha: 1.0)
        #endif
    }

    @discardableResult
    private func attachPlatformVideoViewIfNeeded(
        _ view: TiRtcPlatformView, to videoOutput: TiRtcVideoOutput, streamId: UInt8
    ) -> Int32 {
        if attachedPlatformVideoViews[streamId] === view {
            return 0
        }
        if attachedPlatformVideoViews[streamId] != nil { _ = videoOutput.detachView() }
        let attachCode = videoOutput.attachView(view)
        if attachCode != 0 {
            videoStates[streamId] = .failed
            isClientVideoRendering = videoStates.values.contains(.rendering)
            if !videoStates.values.contains(where: { $0 != .failed }) {
                isClientConnecting = false
            }
            appendStatusLogLine(
                "video-output-failed phase=attach-view stream_id=\(streamId) code=\(attachCode)")
            return attachCode
        }
        attachedPlatformVideoViews[streamId] = view
        appendStatusLogLine("render_surface_attached flow=client stream_id=\(streamId)")
        return 0
    }

}
