import CoreGraphics
import Foundation
import TiRTC
import XCTest

#if os(macOS)
    import AppKit
#endif

private final class StoreSdkOutputObserver: NSObject, TiStoreAudioOutputDelegate,
    TiStoreVideoOutputDelegate, @unchecked Sendable
{
    private let lock = NSLock()
    private var storedReplayError: Int32 = 0
    private var storedAudioError: Int32 = 0
    private var storedVideoError: Int32 = 0
    private var storedCurrentTimeMs: Int64 = 0
    private var storedBufferingCount = 0
    private var continuousPlayback = false

    var replayError: Int32 { lock.withLock { storedReplayError } }
    var audioError: Int32 { lock.withLock { storedAudioError } }
    var videoError: Int32 { lock.withLock { storedVideoError } }
    var currentTimeMs: Int64 { lock.withLock { storedCurrentTimeMs } }
    var bufferingCount: Int { lock.withLock { storedBufferingCount } }

    func beginContinuousPlayback() { lock.withLock { continuousPlayback = true } }
    func endContinuousPlayback() { lock.withLock { continuousPlayback = false } }
    func setReplayTime(_ timeMs: Int64) { lock.withLock { storedCurrentTimeMs = timeMs } }
    func setReplayError(_ code: Int32) { lock.withLock { storedReplayError = code } }

    func audioOutput(
        _ output: TiStoreAudioOutput,
        didChangeState state: TiStoreAudioOutputState
    ) {}

    func audioOutput(_ output: TiStoreAudioOutput, didFailWithCode code: Int32) {
        lock.withLock { storedAudioError = code }
    }

    func videoOutput(
        _ output: TiStoreVideoOutput,
        didChangeState state: TiStoreVideoOutputState
    ) {
        lock.withLock {
            if continuousPlayback && state == .buffering { storedBufferingCount += 1 }
        }
    }

    func videoOutput(_ output: TiStoreVideoOutput, didFailWithCode code: Int32) {
        lock.withLock { storedVideoError = code }
    }
}

final class ExampleUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        #if os(macOS)
            registerSystemPermissionHandlers()
        #endif
    }

    @MainActor
    func testDarwinHarness() async throws {
        let environment = try Self.harnessEnvironment()
        let mode = environment["TIRTC_XCUITEST_MODE"] ?? ""
        let statusLog = environment["TIRTC_XCUITEST_STATUS_LOG"] ?? ""
        let requiredPatterns = Self.patterns(
            from: environment["TIRTC_XCUITEST_REQUIRED_PATTERNS"] ?? "")
        let timeoutSeconds = TimeInterval(
            Double(environment["TIRTC_XCUITEST_TIMEOUT_SECONDS"] ?? "") ?? 120.0)
        let renderWindowSeconds = TimeInterval(
            Double(environment["TIRTC_XCUITEST_RENDER_WINDOW_SECONDS"] ?? "") ?? 0.0)
        let appEnvironment = try Self.decodeAppEnvironment(
            environment["TIRTC_XCUITEST_APP_ENV_JSON"] ?? "{}")
        Self.appendStatus(statusLog, "xcuitest_started mode=\(mode)")

        if mode == "public_smoke_client" {
            let payload = try Self.decodeAppEnvironment(
                environment["TIRTC_XCUITEST_PUBLIC_PAYLOAD_JSON"] ?? "{}")
            let attachExternalApp =
                environment["TIRTC_XCUITEST_ATTACH_EXTERNAL_APP"] == "1"
            try runPublicClientSmoke(
                appEnvironment: appEnvironment,
                attachExternalApp: attachExternalApp,
                payload: payload,
                statusLog: statusLog,
                timeoutSeconds: timeoutSeconds,
                renderWindowSeconds: renderWindowSeconds)
            return
        }
        if mode == "store_public_smoke" {
            let payload = try Self.decodeAppEnvironment(
                environment["TIRTC_XCUITEST_PUBLIC_PAYLOAD_JSON"] ?? "{}")
            try await runStorePublicSmoke(
                appEnvironment: appEnvironment,
                payload: payload,
                statusLog: statusLog,
                timeoutSeconds: timeoutSeconds)
            return
        }
        if mode == "store_public_integration" {
            let payload = try Self.decodeAppEnvironment(
                environment["TIRTC_XCUITEST_PUBLIC_PAYLOAD_JSON"] ?? "{}")
            try await runStorePublicSdkCase(
                payload: payload,
                statusLog: statusLog,
                timeoutSeconds: timeoutSeconds)
            return
        }
        if environment["TIRTC_XCUITEST_SKIP_APP_LAUNCH"] == "1" {
            for pattern in requiredPatterns {
                XCTAssertTrue(
                    Self.waitForFile(statusLog, containing: pattern, timeout: timeoutSeconds),
                    "status log did not contain required pattern: \(pattern)"
                )
            }
            return
        }

        let launchedApp = XCUIApplication(bundleIdentifier: "tirtc.example.macos")
        launchedApp.launchEnvironment = appEnvironment
        launchedApp.launch()

        XCTAssertTrue(launchedApp.wait(for: .runningForeground, timeout: 5.0) || launchedApp.exists)
        for pattern in requiredPatterns {
            XCTAssertTrue(
                Self.waitForFile(statusLog, containing: pattern, timeout: timeoutSeconds),
                "status log did not contain required pattern: \(pattern)"
            )
        }
    }

    @MainActor
    private func runPublicClientSmoke(
        appEnvironment: [String: String],
        attachExternalApp: Bool,
        payload: [String: String],
        statusLog: String,
        timeoutSeconds: TimeInterval,
        renderWindowSeconds: TimeInterval
    ) throws {
        let app = launchApp(
            appEnvironment: appEnvironment,
            attachExternalApp: attachExternalApp)
        XCTAssertTrue(waitForElement(app, "client.configure.page", timeout: 8.0))
        Self.appendStatus(statusLog, "smoke_configure_page_ready")
        try replaceText(app, "client.app_id", payload["app_id"] ?? "darwin-example-app")
        try replaceText(app, "client.endpoint", payload["endpoint"] ?? "")
        try replaceText(app, "client.remote_id", required(payload, "remote_id"))
        try replaceText(app, "client.audio_stream_id", payload["audio_stream_id"] ?? "10")
        try replaceText(app, "client.video_stream_id", payload["video_stream_id"] ?? "11")
        try replaceText(app, "client.token", required(payload, "token"))
        Self.appendStatus(statusLog, "smoke_payload_applied")

        tap(app, "client.enter_player")
        Self.appendStatus(statusLog, "smoke_public_submit_tapped")
        XCTAssertTrue(waitForElement(app, "client.player.page", timeout: 8.0))
        _ = waitForStatus(
            app, "client.player.page", statusLog, containing: "route_reached flow=client", timeout: 2.0)
        XCTAssertTrue(waitForElement(app, "client.metrics.overlay", timeout: timeoutSeconds))
        Self.appendStatus(statusLog, "smoke_video_rendering")

        tap(app, "client.audio_output_volume")
        XCTAssertTrue(
            waitForStatus(
                app,
                "client.audio_output_volume",
                statusLog,
                containing: "muted",
                timeout: 8.0),
            "audio output mute was not observed")
        waitForRenderWindow(seconds: 5.0)
        tap(app, "client.audio_output_volume")
        XCTAssertTrue(
            waitForStatus(
                app,
                "client.audio_output_volume",
                statusLog,
                containing: "audio_output_volume_verified status=passed",
                timeout: 8.0),
            "audio output recovery or muted pipeline progress was not verified")
        let volumeEvidence =
            app.descendants(matching: .any)["client.audio_output_volume"].firstMatch.value as? String
        XCTAssertNotNil(volumeEvidence, "audio output continuity evidence was not exposed")
        Self.appendStatus(statusLog, volumeEvidence ?? "audio_output_volume_verified status=failed")

        if payload["skip_local_audio"] != "1" {
            tap(app, "client.local_audio")
            XCTAssertTrue(
                waitForStatusHandlingSystemPermissions(
                    app,
                    "client.local_audio",
                    statusLog,
                    containing: "client.local_audio started",
                    timeout: 30.0),
                "client microphone did not start")
            XCTAssertTrue(
                waitForStatus(
                    app,
                    "client.local_audio",
                    statusLog,
                    containing: "options=0 start=0 attach=0",
                    timeout: 2.0),
                "client microphone start returned a non-zero code")
            Self.appendStatus(
                statusLog,
                "smoke_local_audio_started \(statusValue(app, "client.local_audio"))")
            waitForRenderWindow(seconds: 1.0)
            tap(app, "client.local_audio")
            XCTAssertTrue(
                waitForStatus(
                    app,
                    "client.local_audio",
                    statusLog,
                    containing: "client.local_audio stopped detach=0 stop=0",
                    timeout: 8.0),
                "client microphone did not stop cleanly")
            Self.appendStatus(
                statusLog,
                "smoke_local_audio_stopped \(statusValue(app, "client.local_audio"))")
        }

        let diagnostics = waitForClientDiagnosticsData(app, timeout: timeoutSeconds)
        XCTAssertNotNil(diagnostics, "client metrics overlay did not expose useful debug values")
        Self.appendStatus(statusLog, diagnostics ?? "debug_stats_unavailable")
        attachScreenshot(app, name: "client-player")

        if payload["simulator_downlink_only"] == "1" {
            Self.appendStatus(statusLog, "smoke_command_echo_skipped reason=simulator_downlink_only")
        } else if payload["skip_command"] == "1" {
            Self.appendStatus(statusLog, "smoke_command_echo_skipped reason=audio_cases_case")
        } else {
            XCTAssertTrue(
                openClientCommandPanel(
                    app,
                    attachExternalApp: attachExternalApp),
                "client command panel did not open")
            tapButtonAny(app, ["client.command_panel.echo_preset", "Echo"])
            tapButtonAny(app, ["client.command_panel.send", "发送"])
            XCTAssertTrue(
                waitForCommandHistory(
                    app,
                    statusLog: statusLog,
                    historyPattern: "sent id=0xFFFFFFFF code=0 payload=65 63 68 6F",
                    statusPattern: "command-dispatch command_id=0xFFFFFFFF payload_mode=text payload_bytes=4 code=0",
                    timeout: 4.0),
                "Echo command send was not observed")
            XCTAssertTrue(
                waitForCommandHistory(
                    app,
                    statusLog: statusLog,
                    historyPattern: "received id=0xFFFFFFFF payload=65 63 68 6F",
                    statusPattern: "echo-reply-received command_id=0xFFFFFFFF",
                    timeout: 8.0),
                "Echo reply was not observed")
            Self.appendStatus(statusLog, "smoke_command_echo_completed command_id=0xFFFFFFFF payload_bytes=4")
            if waitForElement(app, "client.command_panel", timeout: 0.5) {
                tapButtonAny(app, ["client.command_panel.close", "关闭"])
            }
        }
        waitForRenderWindow(seconds: renderWindowSeconds)
        Self.appendStatus(statusLog, "smoke_render_window_completed")
        if payload["simulator_downlink_only"] != "1" {
            tap(app, "client.upload_logs")
            Self.appendStatus(statusLog, "smoke_log_upload_tapped")
            XCTAssertTrue(
                waitForStatusAny(
                    app,
                    "client.player.page",
                    statusLog,
                    containingAny: ["log upload started", "log upload finished: code=0"],
                    timeout: 8.0),
                "log upload did not start: \(statusValue(app, "client.player.page"))")
            XCTAssertTrue(
                waitForStatus(
                    app,
                    "client.player.page",
                    statusLog,
                    containing: "log upload finished: code=0",
                    timeout: timeoutSeconds),
                "log upload did not finish: \(statusValue(app, "client.player.page"))")
            Self.appendStatus(statusLog, "smoke_log_upload_dialog_visible \(statusValue(app, "client.player.page"))")
            XCTAssertTrue(dismissAppAlert(app, buttonTitles: ["OK", "确定"]), "log upload result dialog did not dismiss")
        }
        if app.state != .runningForeground {
            app.activate()
        }
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 5.0),
            "Example did not return to foreground before teardown")
        tap(app, "client.stop")
        XCTAssertTrue(
            waitForElement(app, "client.configure.page", timeout: 8.0),
            "client did not return to configure after teardown request")
        Self.appendStatus(statusLog, "smoke_returned_to_configure")
        XCTAssertTrue(
            waitForStatus(
                app,
                "client.configure.page",
                statusLog,
                containing: "cleaned",
                timeout: 8.0),
            "client teardown did not finish cleanup")
        Self.appendStatus(statusLog, "smoke_teardown_completed cleaned")
    }

    @MainActor
    private func runStorePublicSmoke(
        appEnvironment: [String: String],
        payload: [String: String],
        statusLog: String,
        timeoutSeconds: TimeInterval
    ) async throws {
        let app = launchApp(appEnvironment: appEnvironment, attachExternalApp: false)
        XCTAssertTrue(waitForElement(app, "client.configure.page", timeout: 8.0))
        Self.appendStatus(statusLog, "store_configure_page_ready")
        handleSystemPermissionDialogs(app, attempts: 5)

        tap(app, "product.tabs")
        tapButtonAny(app, ["云录像", "Store"])
        XCTAssertTrue(waitForElement(app, "store.enter_player", timeout: 8.0))

        try replaceText(app, "store.app_id", required(payload, "app_id"))
        try replaceText(app, "store.endpoint", payload["endpoint"] ?? "")
        try replaceText(app, "store.token", required(payload, "token_url"))
        try replaceText(app, "store.audio_channel_id", payload["audio_channel_id"] ?? "10")
        try replaceText(app, "store.video_channel_id", payload["video_channel_id"] ?? "11")
        Self.appendStatus(statusLog, "store_payload_applied")

        tap(app, "store.enter_player")
        handleSystemPermissionDialogs(app, attempts: 5)
        XCTAssertTrue(
            waitForElement(app, "store.player.page", timeout: 10.0),
            "Store player did not open: \(statusValue(app, "store.configure.status"))")
        let startTime = try required(payload, "start_time_ms")
        let playIdentifier = "store.play.\(startTime)"
        XCTAssertTrue(waitForElement(app, playIdentifier, timeout: timeoutSeconds))
        tap(app, playIdentifier)
        let rendering = waitForStatus(
            app,
            "store.video_stage",
            statusLog,
            containing: "rendering",
            timeout: timeoutSeconds)
        XCTAssertTrue(
            rendering,
            "Store replay never entered rendering state: \(statusValue(app, "store.video_stage"))")
        Self.appendStatus(statusLog, "store_video_rendering")
        attachScreenshot(app, name: "store-player-rendering")

        waitForRenderWindow(seconds: 8.0)
        tap(app, "store.pause")
        XCTAssertTrue(
            waitForStatus(app, "store.video_stage", statusLog, containing: "paused", timeout: 8.0),
            "Store replay did not pause its output immediately")
        Self.appendStatus(statusLog, "store_pause_verified")

        // Change the menu-backed speed while paused. On a physical iPhone XCTest can
        // otherwise wait for video-surface quiescence until the short smoke recording
        // has already reached its terminal state.
        tap(app, "store.speed")
        tapButtonAny(app, ["x2"])
        XCTAssertTrue(waitForStatus(app, "store.status", statusLog, containing: "播放倍速：x2", timeout: 5.0))
        tap(app, "store.pause")
        XCTAssertTrue(
            waitForStatus(app, "store.video_stage", statusLog, containing: "rendering", timeout: 8.0),
            "Store replay did not resume")
        Self.appendStatus(statusLog, "store_resume_verified")

        waitForRenderWindow(seconds: 3.0)
        tap(app, "store.pause")
        XCTAssertTrue(
            waitForStatus(app, "store.video_stage", statusLog, containing: "paused", timeout: 8.0),
            "Store replay did not pause before restoring normal speed")
        tap(app, "store.speed")
        tapButtonAny(app, ["x1"])
        XCTAssertTrue(waitForStatus(app, "store.status", statusLog, containing: "播放倍速：x1", timeout: 5.0))
        tap(app, "store.pause")
        XCTAssertTrue(
            waitForStatus(app, "store.video_stage", statusLog, containing: "rendering", timeout: 8.0),
            "Store replay did not resume after restoring normal speed")
        Self.appendStatus(statusLog, "store_speed_verified")

        tap(app, "store.mute")
        XCTAssertTrue(waitForStatus(app, "store.status", statusLog, containing: "已静音", timeout: 5.0))
        waitForRenderWindow(seconds: 2.0)
        tap(app, "store.mute")
        XCTAssertTrue(waitForStatus(app, "store.status", statusLog, containing: "已恢复声音", timeout: 5.0))
        Self.appendStatus(statusLog, "store_mute_verified")

        let seek = app.descendants(matching: .any)["store.seek"].firstMatch
        XCTAssertTrue(seek.waitForExistence(timeout: 5.0))
        seek.adjust(toNormalizedSliderPosition: 0.45)
        guard waitForStatus(app, "store.status", statusLog, containing: "已跳转", timeout: 8.0) else {
            XCTFail("Store replay seek failed: \(statusValue(app, "store.status"))")
            return
        }
        Self.appendStatus(statusLog, "store_seek_verified")
        waitForRenderWindow(seconds: 4.0)

        tap(app, "store.snapshot")
        XCTAssertTrue(waitForStatus(app, "store.status", statusLog, containing: "截图完成", timeout: 15.0))
        Self.appendStatus(statusLog, "store_snapshot_verified")
        tap(app, "store.gallery")
        handleSystemPermissionDialogs(app, attempts: 5)
        XCTAssertTrue(
            waitForStatusHandlingSystemPermissions(
                app, "store.status", statusLog, containing: "已保存到系统相册", timeout: 20.0),
            "Store snapshot was not saved to Photos")
        Self.appendStatus(statusLog, "store_snapshot_gallery_verified source_deleted=true")

        tap(app, "store.recording")
        XCTAssertTrue(waitForStatus(app, "store.status", statusLog, containing: "边播边录已开始", timeout: 8.0))
        waitForRenderWindow(seconds: 8.0)
        tap(app, "store.recording")
        XCTAssertTrue(waitForStatus(app, "store.status", statusLog, containing: "边播边录完成", timeout: 20.0))
        Self.appendStatus(statusLog, "store_recording_verified")
        tap(app, "store.gallery")
        XCTAssertTrue(waitForStatus(app, "store.status", statusLog, containing: "已保存到系统相册", timeout: 20.0))
        Self.appendStatus(statusLog, "store_recording_gallery_verified source_deleted=true")

        guard
            tapUntilVisible(
                app,
                sourceIdentifier: "store.recordings",
                targetIdentifier: "store.recordings.close",
                attempts: 3
            )
        else {
            XCTFail("Store recordings sheet did not open")
            return
        }
        let exportIdentifier = "store.export.\(startTime)"
        guard waitForElement(app, exportIdentifier, timeout: 8.0) else {
            XCTFail("Store range export was not available for \(startTime)")
            return
        }
        tap(app, exportIdentifier)
        tap(app, "store.recordings.close")
        XCTAssertTrue(waitForStatus(app, "store.status", statusLog, containing: "范围下载完成", timeout: timeoutSeconds))
        Self.appendStatus(statusLog, "store_range_export_verified")
        tap(app, "store.gallery")
        XCTAssertTrue(waitForStatus(app, "store.status", statusLog, containing: "已保存到系统相册", timeout: 20.0))
        Self.appendStatus(statusLog, "store_export_gallery_verified source_deleted=true")

        XCTAssertTrue(
            waitForStatus(app, "store.video_stage", statusLog, containing: "completed", timeout: timeoutSeconds),
            "Store replay did not consume the selected recording through its terminal state")
        Self.appendStatus(statusLog, "store_replay_completed")

        tap(app, "store.upload_logs")
        XCTAssertTrue(waitForStatus(app, "store.status", statusLog, containing: "日志上传完成：", timeout: timeoutSeconds))
        Self.appendStatus(statusLog, "store_log_upload_verified \(statusValue(app, "store.status"))")
        attachScreenshot(app, name: "store-player-complete")

        tap(app, "store.close")
        XCTAssertTrue(waitForElement(app, "client.configure.page", timeout: 15.0))
        XCTAssertTrue(waitForElement(app, "store.enter_player", timeout: 5.0))
        Self.appendStatus(statusLog, "store_returned_to_configure")
    }

    @MainActor
    private func fetchOneTimeToken(_ urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else {
            throw XCTSkip("invalid Store token URL")
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard data.count <= 64 * 1024,
            let response = response as? HTTPURLResponse,
            (200..<300).contains(response.statusCode)
        else {
            throw XCTSkip("Store token endpoint returned an invalid response")
        }
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: String],
            let token = dictionary["token"], !token.isEmpty
        else {
            throw XCTSkip("Store token endpoint returned no token")
        }
        return token
    }

    @MainActor
    private func runStorePublicSdkCase(
        payload: [String: String],
        statusLog: String,
        timeoutSeconds: TimeInterval
    ) async throws {
        let queryStartMs = try requiredInt64(payload, "query_start_ms")
        let queryEndMs = try requiredInt64(payload, "query_end_ms")
        let audioChannel = try requiredChannel(payload, "audio_channel_id")
        let videoChannel = try requiredChannel(payload, "video_channel_id")
        XCTAssertGreaterThan(queryEndMs, queryStartMs)
        let token = try await fetchOneTimeToken(required(payload, "token_url"))

        var initialized = false
        var store: TiStore?
        var replay: TiStoreReplay?
        var audio: TiStoreAudioOutput?
        var video: TiStoreVideoOutput?
        var recordingFile: TiStoreRecordingFile?
        var snapshotFile: TiStoreSnapshotFile?
        var exportFile: TiStoreRecordingFile?
        var replayStarted = false
        var audioAttached = false
        var videoAttached = false
        let observer = StoreSdkOutputObserver()

        func cleanUp() async {
            if let recordingFile { _ = await recordingFile.delete() }
            if let snapshotFile { _ = await snapshotFile.delete() }
            if let exportFile { _ = await exportFile.delete() }
            if replayStarted { _ = replay?.stop() }
            if videoAttached { _ = video?.detach() }
            if audioAttached { _ = audio?.detach() }
            _ = retryStoreInUse { video?.dispose() ?? TiStoreErrorCode.ok }
            _ = retryStoreInUse { audio?.dispose() ?? TiStoreErrorCode.ok }
            _ = retryStoreInUse { replay?.dispose() ?? TiStoreErrorCode.ok }
            _ = retryStoreInUse { store?.dispose() ?? TiStoreErrorCode.ok }
            if initialized { _ = retryStoreInUse(TiStore.shutdown) }
        }

        do {
            try requireStoreOk(
                TiStore.initialize(
                    appId: required(payload, "app_id"),
                    endpoint: payload["endpoint"] ?? "",
                    consoleLogEnabled: true),
                "TiStore initialization")
            initialized = true
            let activeStore = TiStore(token: token)
            store = activeStore
            let listed = await activeStore.listRecordings(
                startTimeMs: queryStartMs,
                endTimeMs: queryEndMs)
            try requireStoreOk(listed.code, "exact Store query")
            let range = try XCTUnwrap(
                listed.recordings.max { lhs, rhs in
                    lhs.endTimeMs - lhs.startTimeMs < rhs.endTimeMs - rhs.startTimeMs
                })
            XCTAssertGreaterThanOrEqual(range.endTimeMs - range.startTimeMs, 110_000)
            Self.appendStatus(statusLog, "store_sdk_query_verified")

            let activeReplay = activeStore.createReplay()
            replay = activeReplay
            let activeAudio = TiStoreAudioOutput()
            audio = activeAudio
            let activeVideo = TiStoreVideoOutput()
            video = activeVideo
            activeAudio.delegate = observer
            activeVideo.delegate = observer
            let completed = expectation(description: "Store replay reaches requested end")
            activeReplay.onTimeChanged = { observer.setReplayTime($0) }
            activeReplay.onError = { code in
                observer.setReplayError(code)
                completed.fulfill()
            }
            activeReplay.onCompleted = { completed.fulfill() }
            try requireStoreOk(
                activeAudio.attach(replay: activeReplay, channelId: audioChannel),
                "audio output attach")
            audioAttached = true
            try requireStoreOk(
                activeVideo.attach(replay: activeReplay, channelId: videoChannel),
                "video output attach")
            videoAttached = true
            try requireStoreOk(
                activeReplay.play(startTimeMs: range.startTimeMs, endTimeMs: range.endTimeMs),
                "Store replay play")
            replayStarted = true
            try await waitForStoreCondition(timeoutSeconds: 30) {
                activeAudio.state == .playing && activeVideo.state == .rendering
                    && observer.currentTimeMs >= range.startTimeMs + 800
            }
            Self.appendStatus(statusLog, "store_sdk_outputs_verified")
            observer.beginContinuousPlayback()
            await fulfillment(
                of: [completed],
                timeout: TimeInterval(range.endTimeMs - range.startTimeMs) / 1000 + 90)
            observer.endContinuousPlayback()
            XCTAssertEqual(observer.replayError, 0)
            XCTAssertEqual(observer.audioError, 0)
            XCTAssertEqual(observer.videoError, 0)
            XCTAssertEqual(observer.bufferingCount, 0)
            XCTAssertGreaterThanOrEqual(observer.currentTimeMs, range.endTimeMs - 1_000)
            replayStarted = false
            Self.appendStatus(statusLog, "store_sdk_replay_completed")

            try requireStoreOk(
                activeReplay.play(startTimeMs: range.startTimeMs, endTimeMs: range.endTimeMs),
                "replacement replay play")
            replayStarted = true
            try await waitForStoreCondition(timeoutSeconds: 30) {
                activeAudio.state == .playing && activeVideo.state == .rendering
                    && observer.currentTimeMs >= range.startTimeMs + 800
                    && observer.currentTimeMs < range.startTimeMs + 15_000
            }
            let recordingStart = activeReplay.startRecording(
                videoChannelId: Int(videoChannel),
                audioChannelId: NSNumber(value: audioChannel))
            try requireStoreOk(recordingStart.code, "replay recording start")
            let recordingTask = try XCTUnwrap(recordingStart.task)
            try await Task.sleep(nanoseconds: 6_000_000_000)
            let recorded = await recordingTask.stop()
            try requireStoreOk(recorded.code, "replay recording stop")
            let capturedRecording = try XCTUnwrap(recorded.file)
            recordingFile = capturedRecording
            XCTAssertGreaterThanOrEqual(capturedRecording.durationMs, 4_500)
            Self.appendStatus(statusLog, "store_sdk_recording_verified")

            try requireStoreOk(activeAudio.setVolume(0), "Store mute")
            try requireStoreOk(activeAudio.setVolume(35), "Store volume restore")
            try requireStoreOk(activeReplay.pause(), "Store replay pause")
            try await waitForStoreCondition(timeoutSeconds: 5) {
                activeAudio.state == .paused && activeVideo.state == .paused
            }
            let pauseStart = observer.currentTimeMs
            try await Task.sleep(nanoseconds: 1_200_000_000)
            XCTAssertTrue((0...100).contains(observer.currentTimeMs - pauseStart))
            try requireStoreOk(activeReplay.resume(), "Store replay resume")
            try await waitForStoreCondition(timeoutSeconds: 5) {
                observer.currentTimeMs >= pauseStart + 500
            }
            let midpoint = range.startTimeMs + (range.endTimeMs - range.startTimeMs) / 2
            try requireStoreOk(activeReplay.seek(toTimeMs: midpoint), "Store replay seek")
            try requireStoreOk(activeReplay.setSpeed(.x2), "Store replay x2")
            try requireStoreOk(activeReplay.setSpeed(.x1), "Store replay x1")
            Self.appendStatus(statusLog, "store_sdk_controls_verified")

            var snapshot: TiStoreSnapshotResult?
            let snapshotDeadline = Date().addingTimeInterval(10)
            repeat {
                snapshot = await activeVideo.takeSnapshot()
                if snapshot?.code == TiStoreErrorCode.ok { break }
                XCTAssertEqual(snapshot?.code, TiStoreErrorCode.noFrame)
                try await Task.sleep(nanoseconds: 200_000_000)
            } while Date() < snapshotDeadline
            let capturedSnapshot = try XCTUnwrap(snapshot?.file)
            snapshotFile = capturedSnapshot
            try validateStoreMedia(path: capturedSnapshot.path, kind: "jpeg")
            Self.appendStatus(statusLog, "store_sdk_snapshot_verified")

            var exportTask: TiStoreExportTask?
            let exported: TiStoreRecordingResult = await withCheckedContinuation { continuation in
                let started = activeStore.exportRecording(
                    TiStoreExportRequest(
                        startTimeMs: range.startTimeMs,
                        endTimeMs: range.endTimeMs,
                        videoChannelId: Int(videoChannel),
                        audioChannelId: NSNumber(value: audioChannel)),
                    progress: nil
                ) { result in
                    continuation.resume(returning: result)
                }
                XCTAssertEqual(started.code, TiStoreErrorCode.ok)
                exportTask = started.task
            }
            _ = exportTask
            try requireStoreOk(exported.code, "Store range export")
            let capturedExport = try XCTUnwrap(exported.file)
            exportFile = capturedExport
            try validateStoreMedia(path: capturedRecording.path, kind: "mp4")
            try validateStoreMedia(path: capturedExport.path, kind: "mp4")
            Self.appendStatus(statusLog, "store_sdk_export_verified")

            try await deleteAndVerify(capturedRecording)
            recordingFile = nil
            try await deleteAndVerify(capturedSnapshot)
            snapshotFile = nil
            try await deleteAndVerify(capturedExport)
            exportFile = nil
            Self.appendStatus(statusLog, "store_sdk_runtime_delete_verified")

            let upload: TiRtcLogUploadResult = await withCheckedContinuation { continuation in
                let code = TiRtcLogging.upload { continuation.resume(returning: $0) }
                XCTAssertEqual(code, TiStoreErrorCode.ok)
            }
            try requireStoreOk(upload.code, "Store log upload")
            XCTAssertFalse((upload.logId ?? "").isEmpty)
            Self.appendStatus(statusLog, "store_sdk_log_upload_verified")
            try requireStoreOk(activeReplay.stop(), "replacement replay stop")
            replayStarted = false
            Self.appendStatus(statusLog, "store_sdk_case_completed")
        } catch {
            await cleanUp()
            throw error
        }
        await cleanUp()
    }

    @MainActor
    private func requiredInt64(_ payload: [String: String], _ key: String) throws -> Int64 {
        guard let value = Int64(try required(payload, key)) else {
            throw XCTSkip("invalid integer payload field: \(key)")
        }
        return value
    }

    @MainActor
    private func requiredChannel(_ payload: [String: String], _ key: String) throws -> UInt8 {
        guard let value = UInt8(try required(payload, key)) else {
            throw XCTSkip("invalid channel payload field: \(key)")
        }
        return value
    }

    @MainActor
    private func requireStoreOk(_ code: Int32, _ operation: String) throws {
        guard code == TiStoreErrorCode.ok else {
            XCTFail("\(operation) failed: \(code)")
            throw XCTSkip("\(operation) failed: \(code)")
        }
    }

    @MainActor
    private func waitForStoreCondition(
        timeoutSeconds: TimeInterval,
        _ predicate: @MainActor @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while !predicate() {
            if Date() >= deadline {
                XCTFail("Store SDK condition timed out")
                throw XCTSkip("Store SDK condition timed out")
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    @MainActor
    private func validateStoreMedia(path: String, kind: String) throws {
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 12) ?? Data()
        XCTAssertGreaterThanOrEqual(data.count, 8)
        if kind == "jpeg" {
            XCTAssertEqual(Array(data.prefix(2)), [0xff, 0xd8])
        } else {
            XCTAssertEqual(String(data: data[4..<8], encoding: .ascii), "ftyp")
        }
    }

    @MainActor
    private func deleteAndVerify(_ file: TiStoreRecordingFile) async throws {
        let path = file.path
        try requireStoreOk(await file.delete(), "Runtime recording delete")
        try requireStoreOk(await file.delete(), "repeat Runtime recording delete")
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    @MainActor
    private func deleteAndVerify(_ file: TiStoreSnapshotFile) async throws {
        let path = file.path
        try requireStoreOk(await file.delete(), "Runtime snapshot delete")
        try requireStoreOk(await file.delete(), "repeat Runtime snapshot delete")
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    @MainActor
    private func retryStoreInUse(_ operation: () -> Int32) -> Int32 {
        let deadline = Date().addingTimeInterval(5)
        while true {
            let code = operation()
            if code != TiStoreErrorCode.inUse || Date() >= deadline { return code }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
    }
    @MainActor
    private func launchApp(
        appEnvironment: [String: String],
        attachExternalApp: Bool
    ) -> XCUIApplication {
        #if os(macOS)
            if attachExternalApp {
                let app = XCUIApplication()
                let alreadyRunning =
                    app.state == .runningForeground
                    || app.state == .runningBackground
                    || app.wait(for: .runningForeground, timeout: 2.0)
                    || app.wait(for: .runningBackground, timeout: 2.0)
                guard alreadyRunning else {
                    XCTFail("external ExampleMacOS app was not already running")
                    return app
                }
                if app.state != .runningForeground {
                    app.activate()
                }
                XCTAssertTrue(
                    app.wait(for: .runningForeground, timeout: 5.0),
                    "external ExampleMacOS app did not become foreground")
                handleSystemPermissionDialogs(app, attempts: 1)
                return app
            }
        #else
            XCTAssertFalse(
                attachExternalApp,
                "external app attach is only supported by the macOS public smoke")
        #endif

        let app = XCUIApplication()
        app.launchEnvironment = appEnvironment
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5.0) || app.exists)
        handleSystemPermissionDialogs(app, attempts: 1)
        return app
    }

    private func registerSystemPermissionHandlers() {
        addUIInterruptionMonitor(withDescription: "System media permission") { alert in
            MainActor.assumeIsolated {
                for title in Self.systemPermissionAllowButtonTitles() {
                    let button = alert.buttons[title].firstMatch
                    if button.exists {
                        button.tap()
                        Self.appendStatusFromEnvironment("system_permission_allowed title=\(title)")
                        return true
                    }
                }
                for button in alert.buttons.allElementsBoundByIndex where Self.isAllowPermissionLabel(button.label) {
                    button.tap()
                    Self.appendStatusFromEnvironment("system_permission_allowed title=\(button.label)")
                    return true
                }
                return false
            }
        }
    }

    @MainActor
    private func handleSystemPermissionDialogs(_ app: XCUIApplication, attempts: Int) {
        for _ in 0..<attempts {
            if dismissSpringBoardAlert() {
                RunLoop.current.run(until: Date().addingTimeInterval(0.35))
                continue
            }
            if dismissMacOSPermissionDialog(app) {
                RunLoop.current.run(until: Date().addingTimeInterval(0.35))
                continue
            }
            #if os(iOS)
                RunLoop.current.run(until: Date().addingTimeInterval(0.35))
                continue
            #else
                RunLoop.current.run(until: Date().addingTimeInterval(0.35))
            #endif
        }
    }

    @MainActor
    private func dismissSpringBoardAlert() -> Bool {
        #if os(iOS)
            let springBoard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let alert = springBoard.alerts.firstMatch
            guard alert.waitForExistence(timeout: 1.0) else {
                return false
            }
            let preferredButtons = [
                "Allow",
                "Allow Once",
                "Allow While Using App",
                "Wi-Fi & Cellular Data",
                "WLAN & Cellular Data",
                "OK",
                "Continue",
                "允许",
                "允许一次",
                "使用 App 时允许",
                "无线局域网与蜂窝网络",
                "好",
                "继续",
            ]
            for title in preferredButtons {
                let button = alert.buttons[title].firstMatch
                if button.exists {
                    button.tap()
                    Self.appendStatusFromEnvironment("system_permission_allowed title=\(title)")
                    return true
                }
            }
            for button in alert.buttons.allElementsBoundByIndex {
                let label = button.label.lowercased()
                if !Self.isAllowPermissionLabel(label) {
                    continue
                }
                button.tap()
                Self.appendStatusFromEnvironment("system_permission_allowed title=\(button.label)")
                return true
            }
            return false
        #else
            return false
        #endif
    }

    @MainActor
    private func dismissIOSNotificationBanner() -> Bool {
        #if os(iOS)
            let springBoard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let banner = springBoard.descendants(matching: .any)["NotificationShortLookView"].firstMatch
            guard banner.waitForExistence(timeout: 0.2) else {
                return false
            }
            if banner.isHittable {
                banner.swipeUp()
            } else {
                let start = springBoard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
                let end = springBoard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.01))
                start.press(forDuration: 0.01, thenDragTo: end)
            }
            Self.appendStatusFromEnvironment("system_notification_dismissed")
            return true
        #else
            return false
        #endif
    }

    @MainActor
    private func dismissMacOSPermissionDialog(_ app: XCUIApplication) -> Bool {
        #if os(macOS)
            let userNotifications = XCUIApplication(bundleIdentifier: "com.apple.UserNotificationCenter")
            let candidates = [
                app.alerts.firstMatch,
                app.dialogs.firstMatch,
                app.sheets.firstMatch,
                userNotifications.dialogs.firstMatch,
                userNotifications.alerts.firstMatch,
            ]
            for candidate in candidates where dismissPermissionElement(candidate) {
                return true
            }
        #else
            _ = app
        #endif
        return false
    }

    @MainActor
    private func dismissPermissionElement(_ element: XCUIElement) -> Bool {
        guard element.waitForExistence(timeout: 0.2) else {
            return false
        }
        for title in Self.systemPermissionAllowButtonTitles() {
            let button = element.buttons[title].firstMatch
            if button.exists {
                tapElement(button)
                Self.appendStatusFromEnvironment("system_permission_allowed title=\(title)")
                return true
            }
        }
        for button in element.buttons.allElementsBoundByIndex where Self.isAllowPermissionLabel(button.label) {
            tapElement(button)
            Self.appendStatusFromEnvironment("system_permission_allowed title=\(button.label)")
            return true
        }
        return false
    }

    private static func systemPermissionAllowButtonTitles() -> [String] {
        #if os(macOS)
            return ["Allow", "允许"]
        #else
            return [
                "Allow",
                "Allow Once",
                "Allow While Using App",
                "Wi-Fi & Cellular Data",
                "WLAN & Cellular Data",
                "OK",
                "Continue",
                "允许",
                "允许一次",
                "使用 App 时允许",
                "无线局域网与蜂窝网络",
                "好",
                "继续",
            ]
        #endif
    }

    private static func isAllowPermissionLabel(_ label: String) -> Bool {
        let normalized = label.lowercased()
        if normalized.contains("deny")
            || (normalized.contains("don") && normalized.contains("allow"))
            || normalized.contains("不允许")
            || normalized.contains("拒绝")
        {
            return false
        }
        #if os(macOS)
            return normalized == "allow" || normalized == "允许"
        #else
            return normalized.contains("allow")
                || normalized == "ok"
                || normalized.contains("continue")
                || normalized.contains("允许")
                || normalized.contains("wi-fi & cellular data")
                || normalized.contains("wlan & cellular data")
                || normalized.contains("无线局域网与蜂窝网络")
                || normalized == "好"
                || normalized.contains("继续")
        #endif
    }

    private static func appendStatusFromEnvironment(_ line: String) {
        let statusLog = ProcessInfo.processInfo.environment["TIRTC_XCUITEST_STATUS_LOG"] ?? ""
        guard !statusLog.isEmpty else {
            return
        }
        appendStatus(statusLog, line)
    }

    @MainActor
    private func waitForRenderWindow(seconds: TimeInterval) {
        guard seconds > 0 else {
            return
        }
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    @MainActor
    private func waitForElement(_ app: XCUIApplication, _ identifier: String, timeout: TimeInterval)
        -> Bool
    {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if elementExistsNow(app, identifier) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return elementExistsNow(app, identifier)
    }

    @MainActor
    private func elementExistsNow(_ app: XCUIApplication, _ identifier: String) -> Bool {
        let candidates = [
            app.buttons[identifier].firstMatch,
            app.staticTexts[identifier].firstMatch,
            app.textFields[identifier].firstMatch,
            app.secureTextFields[identifier].firstMatch,
            app.images[identifier].firstMatch,
            app.otherElements[identifier].firstMatch,
            app.descendants(matching: .any)[identifier].firstMatch,
        ]
        return candidates.contains(where: { $0.exists })
    }

    @MainActor
    private func openClientCommandPanel(
        _ app: XCUIApplication,
        attachExternalApp: Bool
    ) -> Bool {
        if waitForElement(app, "client.command_panel", timeout: 0.2) {
            return true
        }
        for _ in 0..<4 {
            handleSystemPermissionDialogs(app, attempts: 1)
            _ = dismissIOSNotificationBanner()
            if attachExternalApp
                && app.state != .runningForeground
                && app.state != .runningBackground
            {
                return false
            }
            app.activate()
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            let button = app.descendants(matching: .any)["client.send_command"].firstMatch
            if button.waitForExistence(timeout: 4.0) {
                tapElement(button)
            }
            if waitForElement(app, "client.command_panel", timeout: 2.0) {
                return true
            }
            _ = dismissIOSNotificationBanner()
        }
        return waitForElement(app, "client.command_panel", timeout: 1.0)
    }

    @MainActor
    private func tap(_ app: XCUIApplication, _ identifier: String) {
        let element = app.descendants(matching: .any)[identifier].firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 8.0), "missing UI element \(identifier)")
        tapElement(element)
    }

    @MainActor
    private func tapUntilVisible(
        _ app: XCUIApplication,
        sourceIdentifier: String,
        targetIdentifier: String,
        attempts: Int
    ) -> Bool {
        let source = app.descendants(matching: .any)[sourceIdentifier].firstMatch
        let target = app.descendants(matching: .any)[targetIdentifier].firstMatch
        guard source.waitForExistence(timeout: 8.0) else { return false }
        for _ in 0..<attempts {
            if target.exists { return true }
            handleSystemPermissionDialogs(app, attempts: 1)
            if app.state != .runningForeground {
                app.activate()
            }
            tapElement(source)
            if target.waitForExistence(timeout: 3.0) { return true }
            _ = dismissIOSNotificationBanner()
        }
        return target.exists
    }

    @MainActor
    private func tapAny(_ app: XCUIApplication, _ identifiers: [String]) {
        for identifier in identifiers {
            let element = app.descendants(matching: .any)[identifier].firstMatch
            if element.waitForExistence(timeout: 1.0) {
                tapElement(element)
                return
            }
        }
        XCTFail("missing UI element \(identifiers.joined(separator: ","))")
    }

    @MainActor
    private func tapButtonAny(_ app: XCUIApplication, _ identifiers: [String]) {
        for identifier in identifiers {
            let button = app.buttons[identifier].firstMatch
            if button.waitForExistence(timeout: 1.0) {
                tapElement(button)
                return
            }
        }
        tapAny(app, identifiers)
    }

    @MainActor
    private func tapElement(_ element: XCUIElement) {
        if element.isHittable {
            element.tap()
            return
        }
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    @MainActor
    private func dismissAppAlert(_ app: XCUIApplication, buttonTitles: [String]) -> Bool {
        if dismissInAppLogUploadDialog(app, buttonTitles: buttonTitles) {
            return true
        }
        let alert = app.alerts.firstMatch
        if alert.waitForExistence(timeout: 1.0) {
            for title in buttonTitles {
                let button = alert.buttons[title].firstMatch
                if button.exists {
                    return dismissWithAlertButton(app, button: button, buttonTitles: buttonTitles)
                }
            }
            let fallback = alert.buttons.firstMatch
            guard fallback.exists else {
                return false
            }
            return dismissWithAlertButton(app, button: fallback, buttonTitles: buttonTitles)
        }
        #if os(macOS)
            if dismissInAppLogUploadDialog(app, buttonTitles: buttonTitles) {
                return true
            }
            for key in [XCUIKeyboardKey.return, XCUIKeyboardKey.escape] {
                app.typeKey(key, modifierFlags: [])
                RunLoop.current.run(until: Date().addingTimeInterval(0.4))
                if !dialogButtonExists(app, buttonTitles: buttonTitles) {
                    return true
                }
            }
            return !dialogButtonExists(app, buttonTitles: buttonTitles)
        #else
            for title in buttonTitles {
                let element = app.descendants(matching: .any)[title].firstMatch
                if element.waitForExistence(timeout: 1.0) {
                    tapDialogButton(element)
                    RunLoop.current.run(until: Date().addingTimeInterval(0.4))
                    return true
                }
            }
            return false
        #endif
    }

    @MainActor
    private func dismissInAppLogUploadDialog(_ app: XCUIApplication, buttonTitles: [String]) -> Bool {
        let dialog = app.descendants(matching: .any)["log_upload_result.dialog"].firstMatch
        let identifierButton = app.descendants(matching: .any)["log_upload_result.ok"].firstMatch
        if identifierButton.waitForExistence(timeout: 1.0) {
            tapElement(identifierButton)
            return waitForInAppLogUploadDialogDismissal(app)
        }
        guard dialog.exists || dialog.waitForExistence(timeout: 0.4) else {
            return false
        }
        for title in buttonTitles {
            let button = app.buttons[title].firstMatch
            if button.exists || button.waitForExistence(timeout: 0.4) {
                tapElement(button)
                return waitForInAppLogUploadDialogDismissal(app)
            }
        }
        return false
    }

    @MainActor
    private func waitForInAppLogUploadDialogDismissal(_ app: XCUIApplication) -> Bool {
        let deadline = Date().addingTimeInterval(4.0)
        while Date() < deadline {
            let dialog = app.descendants(matching: .any)["log_upload_result.dialog"].firstMatch
            let button = app.descendants(matching: .any)["log_upload_result.ok"].firstMatch
            if !dialog.exists && !button.exists {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        let dialog = app.descendants(matching: .any)["log_upload_result.dialog"].firstMatch
        let button = app.descendants(matching: .any)["log_upload_result.ok"].firstMatch
        return !dialog.exists && !button.exists
    }

    @MainActor
    private func dismissWithAlertButton(
        _ app: XCUIApplication,
        button: XCUIElement,
        buttonTitles: [String]
    ) -> Bool {
        for _ in 0..<2 {
            tapDialogButton(button)
            if waitForAlertDismissal(app, buttonTitles: buttonTitles) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
        return false
    }

    @MainActor
    private func tapDialogButton(_ element: XCUIElement) {
        #if os(iOS)
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        #else
            tapElement(element)
        #endif
    }

    @MainActor
    private func dialogButtonExists(_ app: XCUIApplication, buttonTitles: [String]) -> Bool {
        for title in buttonTitles {
            if app.buttons[title].firstMatch.exists {
                return true
            }
        }
        return false
    }

    @MainActor
    private func waitForAlertDismissal(_ app: XCUIApplication, buttonTitles: [String]) -> Bool {
        let deadline = Date().addingTimeInterval(4.0)
        while Date() < deadline {
            if !app.alerts.firstMatch.exists || !dialogButtonExists(app, buttonTitles: buttonTitles) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return !app.alerts.firstMatch.exists || !dialogButtonExists(app, buttonTitles: buttonTitles)
    }

    @MainActor
    private func replaceText(_ app: XCUIApplication, _ identifier: String, _ value: String) throws {
        let element = app.descendants(matching: .any)[identifier]
        XCTAssertTrue(element.waitForExistence(timeout: 8.0), "missing input \(identifier)")
        if (element.value as? String) == value {
            #if os(iOS)
                dismissKeyboard(app)
            #endif
            return
        }
        #if os(macOS)
            element.tap()
            element.typeKey("a", modifierFlags: .command)
            element.typeKey(.delete, modifierFlags: [])
            if !value.isEmpty {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
                element.typeKey("v", modifierFlags: .command)
            }
        #else
            focusTextInput(app, element)
            element.typeKey("a", modifierFlags: .command)
            element.typeKey(.delete, modifierFlags: [])
            if !value.isEmpty {
                element.typeText(value)
            }
            dismissKeyboard(app)
        #endif
    }

    @MainActor
    private func focusTextInput(_ app: XCUIApplication, _ element: XCUIElement) {
        for xOffset in [0.12, 0.5, 0.88] {
            element.coordinate(withNormalizedOffset: CGVector(dx: xOffset, dy: 0.5)).tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
    }

    @MainActor
    private func dismissKeyboard(_ app: XCUIApplication) {
        let keyboard = app.keyboards.firstMatch
        guard keyboard.exists else {
            return
        }
        for title in ["Done", "Return", "完成", "换行"] {
            let button = keyboard.buttons[title].firstMatch
            if button.exists {
                button.tap()
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
                break
            }
        }
        if app.keyboards.firstMatch.exists {
            app.swipeDown()
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        if app.keyboards.firstMatch.exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
    }

    @MainActor
    private func waitForStatus(
        _ app: XCUIApplication,
        _ identifier: String,
        _ statusLog: String,
        containing pattern: String,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if Self.waitForFile(statusLog, containing: pattern, timeout: 0.05) {
                return true
            }
            if statusValue(app, identifier).contains(pattern) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return false
    }

    @MainActor
    private func waitForStatusHandlingSystemPermissions(
        _ app: XCUIApplication,
        _ identifier: String,
        _ statusLog: String,
        containing pattern: String,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if waitForStatus(
                app,
                identifier,
                statusLog,
                containing: pattern,
                timeout: 0.1)
            {
                return true
            }
            handleSystemPermissionDialogs(app, attempts: 1)
        }
        return waitForStatus(
            app,
            identifier,
            statusLog,
            containing: pattern,
            timeout: 0.1)
    }

    @MainActor
    private func waitForStatusAny(
        _ app: XCUIApplication,
        _ identifier: String,
        _ statusLog: String,
        containingAny patterns: [String],
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for pattern in patterns where Self.waitForFile(statusLog, containing: pattern, timeout: 0.05) {
                return true
            }
            let currentStatus = statusValue(app, identifier)
            if patterns.contains(where: { currentStatus.contains($0) }) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return false
    }

    @MainActor
    private func waitForClientDiagnosticsData(_ app: XCUIApplication, timeout: TimeInterval) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let snapshot = clientDiagnosticsSnapshot(app)
            if clientDiagnosticsAreUseful(snapshot) {
                return [
                    "debug_stats_ready",
                    "media=\"\(escapedStatusValue(snapshot.mediaParameters))\"",
                    "video=\"\(escapedStatusValue(snapshot.videoReceive))\"",
                    "audio=\"\(escapedStatusValue(snapshot.audioReceive))\"",
                    "latency=\"\(escapedStatusValue(snapshot.latency))\"",
                    "startup=\"\(escapedStatusValue(snapshot.startup))\"",
                    "stutter=\"\(escapedStatusValue(snapshot.stutter))\"",
                    "debug_raw=\"\(escapedStatusValue(snapshot.debugRaw))\"",
                ].joined(separator: " ")
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        return nil
    }

    @MainActor
    private func waitForCommandHistory(
        _ app: XCUIApplication,
        statusLog: String,
        historyPattern: String,
        statusPattern: String,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if app.staticTexts.allElementsBoundByIndex.contains(where: { $0.label.contains(historyPattern) }) {
                return true
            }
            if Self.waitForFile(statusLog, containing: statusPattern, timeout: 0.05) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return false
    }

    @MainActor
    private func clientDiagnosticsSnapshot(_ app: XCUIApplication) -> (
        mediaParameters: String,
        videoReceive: String,
        audioReceive: String,
        latency: String,
        startup: String,
        stutter: String,
        debugRaw: String
    ) {
        (
            metricText(app, "client.metrics.media_parameters"),
            metricText(app, "client.metrics.video_receive"),
            metricText(app, "client.metrics.audio_receive"),
            metricText(app, "client.metrics.latency"),
            metricText(app, "client.metrics.startup"),
            metricText(app, "client.metrics.stutter"),
            metricText(app, "client.metrics.debug_snapshot")
        )
    }

    @MainActor
    private func metricText(_ app: XCUIApplication, _ identifier: String) -> String {
        let staticText = app.staticTexts[identifier].firstMatch
        if staticText.exists {
            return staticText.label
        }
        let element = app.descendants(matching: .any)[identifier].firstMatch
        if element.exists {
            return element.label.isEmpty ? String(describing: element.value ?? "") : element.label
        }
        return ""
    }

    private func clientDiagnosticsAreUseful(
        _ snapshot: (
            mediaParameters: String,
            videoReceive: String,
            audioReceive: String,
            latency: String,
            startup: String,
            stutter: String,
            debugRaw: String
        )
    ) -> Bool {
        hasKnownMetric(snapshot.mediaParameters)
            && !snapshot.mediaParameters.contains("未确定")
            && hasNonZeroMetric(snapshot.videoReceive)
            && hasNonZeroMetric(snapshot.audioReceive)
            && hasOutputLatencyMetric(snapshot.latency)
            && hasNonZeroMetric(snapshot.startup)
            && hasKnownMetric(snapshot.stutter)
            && snapshot.debugRaw.contains("audio_codec=")
    }

    private func hasNonZeroMetric(_ text: String) -> Bool {
        !text.isEmpty
            && !text.contains("--")
            && !text.contains("unavailable")
            && text.range(of: #"[1-9][0-9]*(\.[0-9]+)?|0\.[0-9]*[1-9]"#, options: .regularExpression) != nil
    }

    private func hasKnownMetric(_ text: String) -> Bool {
        !text.isEmpty
            && !text.contains("--")
            && !text.contains("unavailable")
    }

    private func hasOutputLatencyMetric(_ text: String) -> Bool {
        !text.isEmpty
            && (hasNonZeroMetric(text) || text.contains("--") || text.contains("unavailable"))
    }

    private func escapedStatusValue(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "'")
    }

    @MainActor
    private func statusValue(_ app: XCUIApplication, _ identifier: String) -> String {
        let element = app.descendants(matching: .any)[identifier]
        guard element.exists else {
            return ""
        }
        let value = element.value as? String
        let label = element.label
        return [value, label].compactMap { $0 }.joined(separator: " ")
    }

    private func required(_ payload: [String: String], _ key: String) throws -> String {
        guard let value = payload[key], !value.isEmpty else {
            throw XCTSkip("missing public smoke payload field \(key)")
        }
        return value
    }

    @MainActor
    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private static func patterns(from value: String) -> [String] {
        value.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    private static func decodeAppEnvironment(_ value: String) throws -> [String: String] {
        guard let data = value.data(using: .utf8) else {
            return [:]
        }
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: String] else {
            return [:]
        }
        return dictionary
    }

    private static func harnessEnvironment() throws -> [String: String] {
        let environment = ProcessInfo.processInfo.environment
        if !(environment["TIRTC_XCUITEST_MODE"] ?? "").isEmpty {
            return environment
        }
        let embedded = try Self.decodeAppEnvironment(ExampleUITestHarnessConfig.embeddedEnvironmentJSON)
        if !(embedded["TIRTC_XCUITEST_MODE"] ?? "").isEmpty {
            return embedded
        }
        let path = "/tmp/tirtc-darwin-example-smoke-xcuitest-config.json"
        guard FileManager.default.fileExists(atPath: path) else {
            return environment
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: String] else {
            return environment
        }
        return dictionary
    }

    private static func waitForFile(_ path: String, containing pattern: String, timeout: TimeInterval)
        -> Bool
    {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let text = try? String(contentsOfFile: path, encoding: .utf8), text.contains(pattern) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return false
    }

    private static func appendStatus(_ path: String, _ message: String) {
        print("[XCUITest] \(message)")
        guard !path.isEmpty, let data = "\(message)\n".data(using: .utf8) else {
            return
        }
        let url = URL(fileURLWithPath: path)
        FileManager.default.createFile(atPath: path, contents: nil)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            _ = try? handle.write(contentsOf: data)
        }
    }
}
