import CoreGraphics
import Foundation
import ImageIO
import TiRTC
import XCTest

#if os(macOS)
    import AppKit
#endif

private final class TiCloudStorageSdkOutputObserver: NSObject, TiCloudStorageAudioOutputDelegate,
    TiCloudStorageVideoOutputDelegate, @unchecked Sendable
{
    private let lock = NSLock()
    private var storedReplayError: Int32 = 0
    private var storedAudioError: Int32 = 0
    private var storedVideoError: Int32 = 0
    private var storedCurrentTimeMs: Int64 = 0
    private var storedBufferingCount = 0
    private var continuousPlayback = false
    private var sourceCompleted = false
    private var sourceCompletedTimeMs: Int64 = 0
    private var storedProgressAfterSource = 0

    var replayError: Int32 { lock.withLock { storedReplayError } }
    var audioError: Int32 { lock.withLock { storedAudioError } }
    var videoError: Int32 { lock.withLock { storedVideoError } }
    var currentTimeMs: Int64 { lock.withLock { storedCurrentTimeMs } }
    var bufferingCount: Int { lock.withLock { storedBufferingCount } }
    var progressAfterSource: Int { lock.withLock { storedProgressAfterSource } }

    func beginContinuousPlayback() { lock.withLock { continuousPlayback = true } }
    func endContinuousPlayback() { lock.withLock { continuousPlayback = false } }
    func setReplayTime(_ timeMs: Int64) {
        lock.withLock {
            storedCurrentTimeMs = timeMs
            if sourceCompleted && timeMs > sourceCompletedTimeMs { storedProgressAfterSource += 1 }
        }
    }
    func markSourceCompleted() {
        lock.withLock {
            sourceCompletedTimeMs = storedCurrentTimeMs
            sourceCompleted = true
        }
    }
    func setReplayError(_ code: Int32) { lock.withLock { storedReplayError = code } }

    func audioOutput(
        _ output: TiCloudStorageAudioOutput,
        didChangeState state: TiCloudStorageAudioOutputState
    ) {}

    func audioOutput(_ output: TiCloudStorageAudioOutput, didFailWithCode code: Int32) {
        lock.withLock { storedAudioError = code }
    }

    func videoOutput(
        _ output: TiCloudStorageVideoOutput,
        didChangeState state: TiCloudStorageVideoOutputState
    ) {
        lock.withLock {
            if continuousPlayback && state == .buffering { storedBufferingCount += 1 }
        }
    }

    func videoOutput(_ output: TiCloudStorageVideoOutput, didFailWithCode code: Int32) {
        lock.withLock { storedVideoError = code }
    }
}

private final class TiCloudStorageConcurrentAction: @unchecked Sendable {
    let body: () -> Int32

    init(_ body: @escaping () -> Int32) {
        self.body = body
    }
}

private final class TiCloudStorageConcurrentResults: @unchecked Sendable {
    private let lock = NSLock()
    private var left: Int32?
    private var right: Int32?

    func set(_ value: Int32, at index: Int) {
        lock.lock()
        if index == 0 {
            left = value
        } else {
            right = value
        }
        lock.unlock()
    }

    func values() -> (Int32, Int32)? {
        lock.lock()
        defer { lock.unlock() }
        guard let left, let right else { return nil }
        return (left, right)
    }
}

private final class TiCloudStorageSnapshotResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedResult: TiCloudStorageSnapshotResult?
    private var callbackCount = 0

    func record(_ result: TiCloudStorageSnapshotResult) -> Int {
        lock.lock()
        defer { lock.unlock() }
        callbackCount += 1
        if storedResult == nil { storedResult = result }
        return callbackCount
    }

    func value() -> TiCloudStorageSnapshotResult? {
        lock.lock()
        defer { lock.unlock() }
        return storedResult
    }

    func count() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return callbackCount
    }
}

private final class TiCloudStorageExportObservationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedProgress: [TiCloudStorageExportProgress] = []
    private var latestProgress: TiCloudStorageExportProgress?
    private var previousProgress: TiCloudStorageExportProgress?
    private var progressObservationCount = 0
    private var progressStreamValid = true
    private var nextSampleFraction = 0.0
    private var storedGaps: [TiCloudStorageRecordingGap] = []
    private var storedTerminalCount = 0

    func record(progress: TiCloudStorageExportProgress) {
        lock.withLock {
            progressObservationCount += 1
            if progress.fraction < 0 || progress.fraction > 1 || progress.coveredDurationMs < 0 {
                progressStreamValid = false
            }
            if let previousProgress,
                progress.fraction < previousProgress.fraction
                    || progress.coveredDurationMs < previousProgress.coveredDurationMs
            {
                progressStreamValid = false
            }
            previousProgress = progress
            latestProgress = progress
            if storedProgress.isEmpty || progress.fraction >= nextSampleFraction {
                storedProgress.append(progress)
                while nextSampleFraction <= progress.fraction {
                    nextSampleFraction += 0.05
                }
            }
        }
    }

    func record(gap: TiCloudStorageRecordingGap) {
        lock.withLock { storedGaps.append(gap) }
    }

    func recordTerminal() {
        lock.withLock { storedTerminalCount += 1 }
    }

    func snapshot() -> (
        [TiCloudStorageExportProgress], [TiCloudStorageRecordingGap], Int, Int, Bool
    ) {
        lock.withLock {
            var samples = storedProgress
            if let latestProgress,
                samples.last?.fraction != latestProgress.fraction
                    || samples.last?.coveredDurationMs != latestProgress.coveredDurationMs
            {
                samples.append(latestProgress)
            }
            return (
                samples, storedGaps, storedTerminalCount,
                progressObservationCount, progressStreamValid
            )
        }
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
    func testIOSCloudExportObservationContracts() throws {
        #if os(iOS)
            let video = TiCloudStorageRecordingTrack(kind: .video, channelId: 7)
            let audio = TiCloudStorageRecordingTrack(kind: .audio, channelId: 8)
            let wholeGap = TiCloudStorageRecordingGap(
                range: TiCloudStorageRecordingRange(startTimeMs: 20, endTimeMs: 40),
                tracks: [video, audio], reasons: [.noRecording])
            let splitGaps = [
                TiCloudStorageRecordingGap(
                    range: TiCloudStorageRecordingRange(startTimeMs: 20, endTimeMs: 30),
                    tracks: [video, audio], reasons: [.noRecording]),
                TiCloudStorageRecordingGap(
                    range: TiCloudStorageRecordingRange(startTimeMs: 30, endTimeMs: 40),
                    tracks: [video, audio], reasons: [.noRecording]),
            ]
            XCTAssertTrue(tiCloudStorageGapCoverageMatches(splitGaps, [wholeGap]))
            XCTAssertTrue(tiCloudStorageGapCoverageMatches([wholeGap], splitGaps))

            let oneMillisecondHole = [
                TiCloudStorageRecordingGap(
                    range: TiCloudStorageRecordingRange(startTimeMs: 20, endTimeMs: 29),
                    tracks: [video, audio], reasons: [.noRecording]),
                TiCloudStorageRecordingGap(
                    range: TiCloudStorageRecordingRange(startTimeMs: 30, endTimeMs: 40),
                    tracks: [video, audio], reasons: [.noRecording]),
            ]
            XCTAssertFalse(tiCloudStorageGapCoverageMatches(oneMillisecondHole, [wholeGap]))
            let wrongChannel = TiCloudStorageRecordingGap(
                range: wholeGap.range,
                tracks: [TiCloudStorageRecordingTrack(kind: .video, channelId: 9), audio],
                reasons: [.noRecording])
            XCTAssertFalse(tiCloudStorageGapCoverageMatches([wrongChannel], [wholeGap]))
            let wrongReason = TiCloudStorageRecordingGap(
                range: wholeGap.range, tracks: [video, audio], reasons: [.downloadFailed])
            XCTAssertFalse(tiCloudStorageGapCoverageMatches([wrongReason], [wholeGap]))
            let partialReasonCoverage = [
                TiCloudStorageRecordingGap(
                    range: TiCloudStorageRecordingRange(startTimeMs: 0, endTimeMs: 20),
                    tracks: [video, audio], reasons: [.noRecording]),
                TiCloudStorageRecordingGap(
                    range: TiCloudStorageRecordingRange(startTimeMs: 20, endTimeMs: 40),
                    tracks: [video, audio], reasons: [.downloadFailed]),
            ]
            XCTAssertFalse(
                tiCloudStorageGapCoverageMatches(partialReasonCoverage, [wholeGap]))
            let shiftedRecording = TiCloudStorageRecordingRange(
                startTimeMs: 30_000, endTimeMs: 50_000)
            let shortContinuousTail = TiCloudStorageRecordingRange(
                startTimeMs: 50_000, endTimeMs: 50_500)
            let advancedRecording = tiCloudStorageAdvancedPartialFixtureRecording(
                recorded: shiftedRecording, next: shortContinuousTail)
            XCTAssertEqual(advancedRecording?.startTimeMs, 30_000)
            XCTAssertEqual(advancedRecording?.endTimeMs, 50_500)
            let secondProbeEmpty = TiCloudStorageRecordingRange(
                startTimeMs: 50_000, endTimeMs: 110_000)
            let shiftedRequest = try tiCloudStoragePartialExportRange(
                recorded: shiftedRecording, empty: secondProbeEmpty)
            XCTAssertEqual(shiftedRequest.startTimeMs, 38_000)
            XCTAssertEqual(shiftedRequest.endTimeMs, 110_000)
            XCTAssertThrowsError(
                try tiCloudStoragePartialExportRange(
                    recorded: TiCloudStorageRecordingRange(
                        startTimeMs: 45_000, endTimeMs: 50_000),
                    empty: secondProbeEmpty))

            let request = TiCloudStorageRecordingRange(startTimeMs: 0, endTimeMs: 40)
            let segment = TiCloudStorageExportSegment(
                sourceRange: TiCloudStorageRecordingRange(startTimeMs: 0, endTimeMs: 20),
                outputStartMs: 0, outputEndMs: 20)
            let report = TiCloudStorageExportReport(
                requestedRange: request,
                coveredDurationMs: 20,
                segments: [segment],
                gaps: [wholeGap],
                unprocessedRanges: [],
                complete: false,
                termination: .exhausted,
                cause: TiCloudStorageErrorCode.ok)
            let progress = [
                TiCloudStorageExportProgress(fraction: 0.25, coveredDurationMs: 10),
                TiCloudStorageExportProgress(fraction: 0.5, coveredDurationMs: 20),
            ]
            XCTAssertTrue(
                tiCloudStorageExportObservationValid(
                    request: request, report: report, progress: progress,
                    gaps: splitGaps, expectComplete: false, knownGap: wholeGap))
            let preRollRequest = TiCloudStorageRecordingRange(startTimeMs: 1, endTimeMs: 40)
            let preRollReport = TiCloudStorageExportReport(
                requestedRange: preRollRequest,
                coveredDurationMs: 19,
                segments: [segment],
                gaps: [wholeGap],
                unprocessedRanges: [],
                complete: false,
                termination: .exhausted,
                cause: TiCloudStorageErrorCode.ok)
            XCTAssertTrue(
                tiCloudStorageExportObservationValid(
                    request: preRollRequest, report: preRollReport,
                    progress: [TiCloudStorageExportProgress(fraction: 1, coveredDurationMs: 19)],
                    gaps: splitGaps, expectComplete: false, knownGap: wholeGap))
            XCTAssertFalse(
                tiCloudStorageExportObservationValid(
                    request: request, report: report, progress: [],
                    gaps: splitGaps, expectComplete: false, knownGap: wholeGap))
            XCTAssertFalse(
                tiCloudStorageExportObservationValid(
                    request: request, report: report, progress: progress,
                    gaps: [], expectComplete: false, knownGap: wholeGap))
        #endif
    }

    @MainActor
    func testPlaybackControlSelectors() throws {
        #if os(macOS)
            let app = XCUIApplication(bundleIdentifier: "tirtc.example.macos")
        #else
            let app = XCUIApplication(bundleIdentifier: "tirtc.example.ios.darwin")
        #endif
        app.launchEnvironment["TIRTC_EXAMPLE_FULL_CLEANUP_ON_STOP"] = "1"
        app.launch()

        XCTAssertTrue(waitForElement(app, "client.configure.page", timeout: 8.0))
        XCTAssertTrue(waitForElement(app, "configure.section.connection", timeout: 3.0))
        XCTAssertTrue(waitForElement(app, "configure.section.media", timeout: 3.0))
        XCTAssertTrue(waitForElement(app, "configure.section.authentication", timeout: 3.0))
        tap(app, "settings.open")
        XCTAssertTrue(waitForElement(app, "settings.page", timeout: 3.0))
        XCTAssertTrue(waitForElement(app, "settings.decoderPreference", timeout: 3.0))
        #if os(macOS)
            let settingsPage = app.descendants(matching: .any)["settings.page"].firstMatch
            app.typeKey(.escape, modifierFlags: [])
            XCTAssertTrue(waitForElementToDisappear(settingsPage, timeout: 2.0))
            app.typeKey(.space, modifierFlags: [])
            XCTAssertTrue(
                waitForElement(app, "settings.page", timeout: 3.0),
                "Space did not reopen Settings after Escape returned keyboard focus")
        #endif
        tap(app, "settings.close")
        XCTAssertTrue(waitForElement(app, "client.configure.page", timeout: 3.0))
        let scan = app.descendants(matching: .any)["client.scan_qr"].firstMatch
        XCTAssertTrue(scan.waitForExistence(timeout: 3.0))
        #if os(iOS)
            tap(app, "client.scan_qr")
            handleSystemPermissionDialogs(app, attempts: 3)
            XCTAssertTrue(waitForElement(app, "scanner.page", timeout: 3.0))
            XCTAssertTrue(waitForElement(app, "scanner.preview", timeout: 3.0))
            XCTAssertTrue(waitForElement(app, "scanner.help", timeout: 3.0))
            tap(app, "scanner.close")
            XCTAssertTrue(scan.waitForExistence(timeout: 3.0) && scan.isHittable)
        #else
            XCTAssertFalse(scan.isEnabled, "macOS scan entry must explain that scanning is unavailable")
        #endif
        try replaceText(app, "client.remote_id", "selector-test-device")
        try replaceText(app, "client.audio_stream_id", "10")
        try replaceListValues(app, prefix: "client.video_stream_id", values: ["11"])
        try replaceText(app, "client.token", "selector-test-token")
        tap(app, "client.enter_player")

        XCTAssertTrue(waitForElement(app, "client.player.page", timeout: 8.0))
        XCTAssertTrue(waitForElement(app, "client.video.stage", timeout: 8.0))
        XCTAssertTrue(waitForElement(app, "client.audio_output_volume", timeout: 8.0))
        XCTAssertTrue(waitForElement(app, "client.stop", timeout: 8.0))
        tap(app, "client.send_command")
        XCTAssertTrue(waitForElement(app, "client.command_panel", timeout: 3.0))
        XCTAssertTrue(waitForElement(app, "client.command_panel.echo_preset", timeout: 3.0))
        #if os(macOS)
            let commandPanel = app.descendants(matching: .any)["client.command_panel"].firstMatch
            app.typeKey(.escape, modifierFlags: [])
            XCTAssertTrue(waitForElementToDisappear(commandPanel, timeout: 2.0))
            app.typeKey(.return, modifierFlags: [])
            XCTAssertTrue(
                waitForElement(app, "client.command_panel", timeout: 3.0),
                "Return did not reopen Command after Escape returned keyboard focus")
        #endif
        tap(app, "client.command_panel.close")
        let commandTrigger = app.descendants(matching: .any)["client.send_command"].firstMatch
        XCTAssertTrue(commandTrigger.waitForExistence(timeout: 3.0) && commandTrigger.isHittable)
        XCTAssertTrue(
            tapUntilVisible(
                app,
                sourceIdentifier: "client.more",
                targetIdentifier: "client.recording",
                attempts: 3))
        #if os(macOS)
            let recording = app.descendants(matching: .any)["client.recording"].firstMatch
            app.typeKey(.escape, modifierFlags: [])
            XCTAssertTrue(waitForElementToDisappear(recording, timeout: 2.0))
            app.typeKey(.space, modifierFlags: [])
            XCTAssertTrue(
                recording.waitForExistence(timeout: 3.0),
                "Space did not reopen More after Escape returned keyboard focus")
            app.typeKey(.escape, modifierFlags: [])
            XCTAssertTrue(waitForElementToDisappear(recording, timeout: 2.0))
            Self.appendStatus(
                "", "smoke_compact_more_menu_verified focus_restored anchor=client.more")
        #else
            XCTAssertTrue(
                dismissTransientMenu(
                    app,
                    anchorIdentifier: "client.player.page",
                    menuItemIdentifier: "client.recording"))
            let more = app.descendants(matching: .any)["client.more"].firstMatch
            XCTAssertTrue(more.waitForExistence(timeout: 2.0) && more.isHittable)
            Self.appendStatus("", "smoke_compact_more_menu_verified menu_closed anchor=client.more")
        #endif
        app.terminate()
    }

    #if os(iOS)
        @MainActor
        func testScannerDeniedStateOffersRecovery() throws {
            let app = XCUIApplication(bundleIdentifier: "tirtc.example.ios.darwin")
            app.launchEnvironment["TIRTC_EXAMPLE_SCANNER_AVAILABILITY_OVERRIDE"] = "denied"
            app.launch()

            XCTAssertTrue(waitForElement(app, "client.configure.page", timeout: 8.0))
            tap(app, "client.scan_qr")
            XCTAssertTrue(waitForElement(app, "scanner.status", timeout: 3.0))
            XCTAssertTrue(waitForElement(app, "scanner.open_settings", timeout: 3.0))
            XCTAssertTrue(waitForElement(app, "scanner.manual_input", timeout: 3.0))
            tap(app, "scanner.manual_input")
            let scan = app.descendants(matching: .any)["client.scan_qr"].firstMatch
            XCTAssertTrue(scan.waitForExistence(timeout: 3.0) && scan.isHittable)
            app.terminate()
        }
    #endif

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
        if mode == "rtc-resolution-switch" {
            let payload = try Self.decodeAppEnvironment(
                environment["TIRTC_XCUITEST_PUBLIC_PAYLOAD_JSON"] ?? "{}")
            try runRtcResolutionSwitchView(
                appEnvironment: appEnvironment,
                payload: payload,
                statusLog: statusLog,
                timeoutSeconds: timeoutSeconds,
                screenshotRoot: environment["TIRTC_XCUITEST_SCREENSHOT_ROOT"] ?? "")
            return
        }
        if mode == "ti-cloud-storage-public-smoke" {
            let payload = try Self.decodeAppEnvironment(
                environment["TIRTC_XCUITEST_PUBLIC_PAYLOAD_JSON"] ?? "{}")
            try await runTiCloudStoragePublicSmoke(
                appEnvironment: appEnvironment,
                payload: payload,
                statusLog: statusLog,
                timeoutSeconds: timeoutSeconds)
            return
        }
        if mode == "ti-cloud-storage-public-integration" {
            let payload = try Self.decodeAppEnvironment(
                environment["TIRTC_XCUITEST_PUBLIC_PAYLOAD_JSON"] ?? "{}")
            try await runTiCloudStoragePublicSdkCase(
                payload: payload,
                statusLog: statusLog,
                timeoutSeconds: timeoutSeconds)
            return
        }
        if mode == "input-media-fixture" {
            let attachExternalApp =
                environment["TIRTC_XCUITEST_ATTACH_EXTERNAL_APP"] == "1"
            let app = launchApp(
                appEnvironment: appEnvironment, attachExternalApp: attachExternalApp)
            handleSystemPermissionDialogs(app, attempts: 8)
            for pattern in requiredPatterns {
                XCTAssertTrue(
                    Self.waitForFile(statusLog, containing: pattern, timeout: timeoutSeconds),
                    "input media status log did not contain required pattern: \(pattern)")
            }
            app.terminate()
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
    private func runRtcResolutionSwitchView(
        appEnvironment: [String: String],
        payload: [String: String],
        statusLog: String,
        timeoutSeconds: TimeInterval,
        screenshotRoot: String
    ) throws {
        let app = launchApp(appEnvironment: appEnvironment, attachExternalApp: false)
        XCTAssertTrue(waitForElement(app, "client.configure.page", timeout: 8.0))
        try replaceText(app, "client.app_id", payload["app_id"] ?? "darwin-example-app")
        try replaceText(app, "client.endpoint", payload["endpoint"] ?? "")
        try replaceText(app, "client.remote_id", required(payload, "remote_id"))
        try replaceText(app, "client.audio_stream_id", payload["audio_stream_id"] ?? "10")
        try replaceListValues(
            app,
            prefix: "client.video_stream_id",
            values: [payload["video_stream_id"] ?? "11"])
        try replaceText(app, "client.token", required(payload, "token"))
        tap(app, "client.enter_player")
        XCTAssertTrue(waitForElement(app, "client.player.page", timeout: 8.0))
        tap(app, "client.metrics.summary")

        let dimensions = ["640x360", "1920x1080", "640x360"]
        let videoStage = app.otherElements["client.video.stage"]
        let appStatusLog = URL(fileURLWithPath: statusLog)
            .deletingLastPathComponent()
            .appendingPathComponent("app.status.log")
            .path
        XCTAssertTrue(videoStage.waitForExistence(timeout: 8.0), "video target was not exposed")
        for (index, dimensions) in dimensions.enumerated() {
            XCTAssertTrue(
                waitForCurrentMetric(
                    app,
                    "client.metrics.media_parameters",
                    containing: dimensions,
                    timeout: timeoutSeconds),
                "video output did not render resolution stage \(index + 1): \(dimensions)")
            let audioBefore = Self.latestStatusMetric(
                appStatusLog, name: "audio_output_duration_ms")
            let audioStatsBefore = Self.latestStatusMetric(
                appStatusLog, name: "audio_stats_updated_at_ms")
            let videoStatsBefore = Self.latestStatusMetric(
                appStatusLog, name: "video_stats_updated_at_ms")
            XCTAssertNotNil(audioBefore, "audio output duration missing before stage \(index + 1)")
            let root =
                screenshotRoot.isEmpty
                ? URL(fileURLWithPath: statusLog).deletingLastPathComponent()
                    .deletingLastPathComponent()
                : URL(fileURLWithPath: screenshotRoot)
            for sample in 1...2 {
                let path = root.appendingPathComponent(
                    "render-stage-\(index + 1)-sample-\(sample).png")
                try FileManager.default.createDirectory(
                    at: path.deletingLastPathComponent(),
                    withIntermediateDirectories: true)
                try videoStage.screenshot().pngRepresentation.write(to: path)
                if sample == 1 {
                    RunLoop.current.run(until: Date().addingTimeInterval(2.3))
                }
            }
            let audioAfter = Self.latestStatusMetric(appStatusLog, name: "audio_output_duration_ms")
            let audioStatsAfter = Self.latestStatusMetric(
                appStatusLog, name: "audio_stats_updated_at_ms")
            let videoStatsAfter = Self.latestStatusMetric(
                appStatusLog, name: "video_stats_updated_at_ms")
            XCTAssertGreaterThan(audioAfter ?? -1, audioBefore ?? -1)
            XCTAssertGreaterThan(audioStatsAfter ?? -1, audioStatsBefore ?? -1)
            XCTAssertGreaterThan(videoStatsAfter ?? -1, videoStatsBefore ?? -1)
            Self.appendStatus(
                statusLog,
                "resolution_switch_stage index=\(index + 1) dimensions=\(dimensions) "
                    + "audio_output_before=\(audioBefore ?? -1) audio_output_after=\(audioAfter ?? -1) "
                    + "audio_stats_before=\(audioStatsBefore ?? -1) audio_stats_after=\(audioStatsAfter ?? -1) "
                    + "video_stats_before=\(videoStatsBefore ?? -1) video_stats_after=\(videoStatsAfter ?? -1)"
            )
        }

        let diagnostics = waitForClientDiagnosticsData(app, timeout: timeoutSeconds)
        XCTAssertNotNil(diagnostics, "resolution switch did not preserve audio/video metrics")
        Self.appendStatus(statusLog, diagnostics ?? "debug_stats_unavailable")
        tap(app, "client.stop")
        XCTAssertTrue(waitForElement(app, "client.configure.page", timeout: 8.0))
        XCTAssertTrue(
            Self.waitForFile(
                appStatusLog,
                containing: "client_cleanup_resources_released code=0",
                timeout: 8.0),
            "resolution switch resources were not released")
        Self.appendStatus(statusLog, "resolution_switch_teardown_completed resources_released")
    }

    private static func latestStatusMetric(_ path: String, name: String) -> Int64? {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: name) + "=([0-9]+)"
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = expression.matches(in: text, range: range).last,
            let valueRange = Range(match.range(at: 1), in: text)
        else { return nil }
        return Int64(text[valueRange])
    }

    @MainActor
    private func waitForCurrentMetric(
        _ app: XCUIApplication,
        _ identifier: String,
        containing pattern: String,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if metricText(app, identifier).contains(pattern) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return false
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
        let videoStreamIds = csvValues(
            payload["video_stream_ids"] ?? payload["video_stream_id"] ?? "11")
        try replaceListValues(app, prefix: "client.video_stream_id", values: videoStreamIds)
        try replaceText(app, "client.token", required(payload, "token"))
        Self.appendStatus(statusLog, "smoke_payload_applied")

        tap(app, "client.enter_player")
        Self.appendStatus(statusLog, "smoke_public_submit_tapped")
        XCTAssertTrue(waitForElement(app, "client.player.page", timeout: 8.0))
        _ = waitForStatus(
            app, "client.player.page", statusLog, containing: "route_reached flow=client",
            timeout: 2.0)
        XCTAssertTrue(waitForElement(app, "client.metrics.overlay", timeout: timeoutSeconds))
        let rawDumpCase = payload["raw_dump_case"] == "1"
        if !rawDumpCase {
            tap(app, "client.metrics.summary")
        }
        for streamId in videoStreamIds {
            XCTAssertTrue(
                waitForVideoStage(
                    app,
                    streamId: streamId,
                    statusLog: statusLog,
                    timeout: timeoutSeconds),
                "video stream \(streamId) did not expose rendering state"
            )
        }
        Self.appendStatus(statusLog, "smoke_video_rendering")
        if rawDumpCase {
            tap(app, "raw_dump.button")
            XCTAssertTrue(
                Self.waitForFile(statusLog, containing: "raw_dump_started flow=client", timeout: 8.0),
                "raw dump did not start")
            waitForRenderWindow(seconds: 12.0)
            tap(app, "raw_dump.button")
            for streamId in videoStreamIds {
                XCTAssertTrue(
                    waitForVideoStage(
                        app,
                        streamId: streamId,
                        statusLog: statusLog,
                        timeout: 8.0),
                    "video stream \(streamId) stopped rendering while raw dump uploaded"
                )
            }
            XCTAssertTrue(
                waitForStatus(
                    app, "client.player.page", statusLog,
                    containing: "log upload finished: code=0", timeout: timeoutSeconds),
                "raw dump upload did not finish")
            _ = dismissAppAlert(app, buttonTitles: ["OK", "确定"])
            Self.appendStatus(
                statusLog,
                "raw_dump_smoke_upload_completed capture_seconds=12 cleanup=archive_attached")
            Self.appendStatus(
                statusLog,
                "raw_dump_media_continuity_verified capturing=1 uploading=1")
            tap(app, "client.stop")
            XCTAssertTrue(
                waitForElement(app, "client.configure.page", timeout: 8.0),
                "client did not return to configure after raw dump upload")
            Self.appendStatus(statusLog, "smoke_returned_to_configure")
            XCTAssertTrue(
                waitForStatus(
                    app,
                    "client.configure.page",
                    statusLog,
                    containing: "cleaned",
                    timeout: 8.0),
                "client teardown did not finish cleanup after raw dump upload")
            Self.appendStatus(statusLog, "smoke_teardown_completed cleaned")
            return
        }
        if waitForElement(app, "client.more", timeout: 0.5) {
            XCTAssertTrue(
                tapUntilVisible(
                    app,
                    sourceIdentifier: "client.more",
                    targetIdentifier: "client.recording",
                    attempts: 3
                ),
                "compact RTC More menu did not expose the real recording action"
            )
            XCTAssertTrue(
                dismissTransientMenu(
                    app,
                    anchorIdentifier: "client.player.page",
                    menuItemIdentifier: "client.recording"),
                "compact RTC More menu did not dismiss from the visible player title"
            )
            let more = app.descendants(matching: .any)["client.more"].firstMatch
            XCTAssertTrue(more.waitForExistence(timeout: 2.0) && more.isHittable)
            Self.appendStatus(
                statusLog, "smoke_compact_more_menu_verified menu_closed anchor=client.more")
        }

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
            Self.latestFileLine(statusLog, containing: "audio_output_volume_verified status=")
            ?? app.descendants(matching: .any)["client.audio_output_volume"].firstMatch.value
            as? String
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
            Self.appendStatus(
                statusLog, "smoke_command_echo_skipped reason=simulator_downlink_only")
        } else if payload["skip_command"] == "1" {
            Self.appendStatus(statusLog, "smoke_command_echo_skipped reason=audio_cases_case")
        } else {
            XCTAssertTrue(
                openClientCommandPanel(
                    app,
                    attachExternalApp: attachExternalApp),
                "client command panel did not open")
            tap(app, "client.command_panel.echo_preset")
            tap(app, "client.command_panel.send")
            let commandSendObserved = waitForCommandHistory(
                app,
                statusLog: statusLog,
                historyPattern: "sent id=0xFFFFFFFF code=0 payload=65 63 68 6F",
                statusPattern:
                    "command-dispatch command_id=0xFFFFFFFF payload_mode=text payload_bytes=4 code=0",
                timeout: 4.0)
            let commandReplyObserved = waitForCommandHistory(
                app,
                statusLog: statusLog,
                historyPattern: "received id=0xFFFFFFFF payload=65 63 68 6F",
                statusPattern: "echo-reply-received command_id=0xFFFFFFFF",
                timeout: 8.0)
            XCTAssertTrue(
                commandSendObserved || commandReplyObserved,
                "Echo command send was not observed")
            XCTAssertTrue(
                commandReplyObserved,
                "Echo reply was not observed")
            Self.appendStatus(
                statusLog, "smoke_command_echo_completed command_id=0xFFFFFFFF payload_bytes=4")
            tap(app, "client.command_panel.close")
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
            Self.appendStatus(
                statusLog,
                "smoke_log_upload_dialog_visible \(statusValue(app, "client.player.page"))")
            XCTAssertTrue(
                dismissAppAlert(app, buttonTitles: ["OK", "确定"]),
                "log upload result dialog did not dismiss"
            )
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
    private func runTiCloudStoragePublicSmoke(
        appEnvironment: [String: String],
        payload: [String: String],
        statusLog: String,
        timeoutSeconds: TimeInterval
    ) async throws {
        let app = launchApp(appEnvironment: appEnvironment, attachExternalApp: false)
        XCTAssertTrue(waitForElement(app, "client.configure.page", timeout: 8.0))
        Self.appendStatus(statusLog, "ti-cloud-storage-configure-page-ready")
        handleSystemPermissionDialogs(app, attempts: 5)

        tap(app, "product.tabs")
        tapButtonAny(app, ["云录像", "Ti Cloud Storage"])
        XCTAssertTrue(waitForElement(app, "ti-cloud-storage.enter_player", timeout: 8.0))

        try replaceText(app, "ti-cloud-storage.app_id", required(payload, "app_id"))
        try replaceText(app, "ti-cloud-storage.endpoint", payload["endpoint"] ?? "")
        try replaceText(app, "ti-cloud-storage.token", required(payload, "token_url"))
        try replaceText(
            app, "ti-cloud-storage.audio_channel_id", payload["audio_channel_id"] ?? "10")
        let videoChannelIds = csvValues(
            payload["video_channel_ids"] ?? payload["video_channel_id"] ?? "11")
        try replaceListValues(
            app, prefix: "ti-cloud-storage.video_channel_id", values: videoChannelIds)
        Self.appendStatus(statusLog, "ti-cloud-storage-payload-applied")

        tap(app, "ti-cloud-storage.enter_player")
        handleSystemPermissionDialogs(app, attempts: 5)
        XCTAssertTrue(
            waitForElement(app, "cloudStorage.player.page", timeout: 10.0),
            "Ti Cloud Storage player did not open: \(statusValue(app, "ti-cloud-storage.configure.status"))"
        )
        let startTime = try required(payload, "start_time_ms")
        let playIdentifier = "cloudStorage.play.\(startTime)"
        XCTAssertTrue(waitForElement(app, playIdentifier, timeout: timeoutSeconds))
        tap(app, playIdentifier)
        let rendering = waitForStatus(
            app,
            "cloudStorage.video_stage",
            statusLog,
            containing: "rendering",
            timeout: timeoutSeconds)
        XCTAssertTrue(
            rendering,
            "Ti Cloud Storage replay never entered rendering state: \(statusValue(app, "cloudStorage.video_stage"))"
        )
        Self.appendStatus(statusLog, "ti-cloud-storage-video-rendering")
        if payload["raw_dump_case"] == "1" {
            tap(app, "raw_dump.button")
            XCTAssertTrue(
                waitForStatus(
                    app, "cloudStorage.status", statusLog,
                    containing: "数据采集中", timeout: 8.0),
                "Ti Cloud Storage raw dump did not start: \(statusValue(app, "cloudStorage.status"))")
            waitForRenderWindow(seconds: 12.0)
            XCTAssertTrue(
                waitForStatus(
                    app, "cloudStorage.video_stage", statusLog,
                    containing: "rendering", timeout: 8.0),
                "Ti Cloud Storage video stopped while raw data was captured")
            tap(app, "raw_dump.button")
            XCTAssertTrue(
                waitForStatus(
                    app, "cloudStorage.status", statusLog,
                    containing: "日志上传完成：", timeout: timeoutSeconds),
                "Ti Cloud Storage raw dump upload did not finish")
            XCTAssertTrue(
                waitForStatus(
                    app, "cloudStorage.video_stage", statusLog,
                    containing: "rendering", timeout: 8.0),
                "Ti Cloud Storage video stopped while raw data was uploaded")
            let uploadStatus = statusValue(app, "cloudStorage.status")
            Self.appendStatus(
                statusLog,
                "ti-cloud-storage-raw-dump-smoke-upload-completed capture_seconds=12 cleanup=archive_attached")
            Self.appendStatus(
                statusLog,
                "ti-cloud-storage-raw-dump-media-continuity-verified capturing=1 uploading=1")
            Self.appendStatus(
                statusLog, "ti-cloud-storage-log-upload-verified \(uploadStatus)")
            tap(app, "cloudStorage.close")
            XCTAssertTrue(waitForElement(app, "client.configure.page", timeout: 15.0))
            XCTAssertTrue(waitForElement(app, "ti-cloud-storage.enter_player", timeout: 5.0))
            Self.appendStatus(statusLog, "ti-cloud-storage-returned-to-configure")
            return
        }
        if let targetChannel = videoChannelIds.last {
            tap(app, "cloudStorage.video_lane.\(targetChannel)")
        }
        attachScreenshot(app, name: "ti-cloud-storage-player-rendering")

        let seek = app.descendants(matching: .any)["cloudStorage.seek"].firstMatch
        XCTAssertTrue(seek.waitForExistence(timeout: 5.0))
        seek.adjust(toNormalizedSliderPosition: 0.25)
        guard waitForStatus(app, "cloudStorage.status", statusLog, containing: "已跳转", timeout: 8.0)
        else {
            XCTFail(
                "Ti Cloud Storage replay seek failed: \(statusValue(app, "cloudStorage.status"))")
            return
        }
        Self.appendStatus(statusLog, "ti-cloud-storage-seek-verified")
        waitForRenderWindow(seconds: 4.0)

        tapCloudSecondaryAction(app, identifier: "cloudStorage.recording")
        XCTAssertTrue(
            waitForStatus(
                app, "cloudStorage.status", statusLog, containing: "边播边录已开始", timeout: 8.0))
        waitForRenderWindow(seconds: 8.0)
        tapCloudSecondaryAction(app, identifier: "cloudStorage.recording")
        XCTAssertTrue(
            waitForStatus(
                app, "cloudStorage.status", statusLog, containing: "边播边录完成", timeout: 20.0))
        Self.appendStatus(statusLog, "ti-cloud-storage-recording-verified")
        tapCloudSecondaryAction(app, identifier: "cloudStorage.gallery")
        handleSystemPermissionDialogs(app, attempts: 5)
        XCTAssertTrue(
            waitForStatusHandlingSystemPermissions(
                app, "cloudStorage.status", statusLog, containing: "已保存到系统相册", timeout: 20.0),
            "Ti Cloud Storage recording was not saved to Photos")
        Self.appendStatus(
            statusLog, "ti-cloud-storage-recording-gallery-verified source_deleted=true")

        waitForRenderWindow(seconds: 8.0)
        tap(app, "cloudStorage.pause")
        XCTAssertTrue(
            waitForStatus(
                app, "cloudStorage.video_stage", statusLog, containing: "paused", timeout: 8.0),
            "Ti Cloud Storage replay did not pause its output immediately")
        Self.appendStatus(statusLog, "ti-cloud-storage-pause-verified")

        // Change the menu-backed speed while paused. On a physical iPhone XCTest can
        // otherwise wait for video-surface quiescence until the short smoke recording
        // has already reached its terminal state.
        tap(app, "cloudStorage.speed")
        tapButtonAny(app, ["2×", "x2"])
        XCTAssertTrue(
            waitForStatus(app, "cloudStorage.speed", statusLog, containing: "2×", timeout: 5.0))
        tap(app, "cloudStorage.pause")
        XCTAssertTrue(
            waitForStatus(
                app, "cloudStorage.video_stage", statusLog, containing: "rendering", timeout: 8.0),
            "Ti Cloud Storage replay did not resume")
        Self.appendStatus(statusLog, "ti-cloud-storage-resume-verified")

        waitForRenderWindow(seconds: 3.0)
        tap(app, "cloudStorage.pause")
        XCTAssertTrue(
            waitForStatus(
                app, "cloudStorage.video_stage", statusLog, containing: "paused", timeout: 8.0),
            "Ti Cloud Storage replay did not pause before restoring normal speed")
        tap(app, "cloudStorage.speed")
        tapButtonAny(app, ["1×", "x1"])
        XCTAssertTrue(
            waitForStatus(app, "cloudStorage.speed", statusLog, containing: "1×", timeout: 5.0))
        tap(app, "cloudStorage.pause")
        XCTAssertTrue(
            waitForStatus(
                app, "cloudStorage.video_stage", statusLog, containing: "rendering", timeout: 8.0),
            "Ti Cloud Storage replay did not resume after restoring normal speed")
        Self.appendStatus(statusLog, "ti-cloud-storage-speed-verified")

        tap(app, "cloudStorage.mute")
        XCTAssertTrue(
            waitForStatus(app, "cloudStorage.status", statusLog, containing: "已静音", timeout: 5.0))
        waitForRenderWindow(seconds: 2.0)
        tap(app, "cloudStorage.mute")
        XCTAssertTrue(
            waitForStatus(app, "cloudStorage.status", statusLog, containing: "已恢复声音", timeout: 5.0))
        Self.appendStatus(statusLog, "ti-cloud-storage-mute-verified")

        tapCloudHeaderAction(app, identifier: "cloudStorage.recordings")
        guard waitForElement(app, "cloudStorage.recordings.page", timeout: 5.0) else {
            XCTFail("Ti Cloud Storage recordings sheet did not open")
            return
        }
        XCTAssertTrue(waitForElement(app, "cloudStorage.calendar", timeout: 3.0))
        XCTAssertTrue(waitForElement(app, "cloudStorage.calendar.status", timeout: 8.0))
        #if os(macOS)
            let recordingsPage = app.descendants(matching: .any)["cloudStorage.recordings.page"]
                .firstMatch
            app.typeKey(.escape, modifierFlags: [])
            XCTAssertTrue(waitForElementToDisappear(recordingsPage, timeout: 2.0))
            app.typeKey(.space, modifierFlags: [])
            XCTAssertTrue(
                waitForElement(app, "cloudStorage.recordings.page", timeout: 3.0),
                "Space did not reopen Recordings after Escape returned keyboard focus")
        #endif
        let exportIdentifier = "cloudStorage.export.\(startTime)"
        guard waitForElement(app, exportIdentifier, timeout: 8.0) else {
            XCTFail("Ti Cloud Storage range export was not available for \(startTime)")
            return
        }
        tap(app, exportIdentifier)
        tap(app, "cloudStorage.recordings.close")
        XCTAssertTrue(
            waitForStatus(
                app, "cloudStorage.status", statusLog,
                containing: "范围下载完成", timeout: timeoutSeconds))
        Self.appendStatus(statusLog, "ti-cloud-storage-range-export-verified")
        tapCloudSecondaryAction(app, identifier: "cloudStorage.gallery")
        XCTAssertTrue(
            waitForStatus(
                app, "cloudStorage.status", statusLog, containing: "已保存到系统相册", timeout: 20.0))
        Self.appendStatus(statusLog, "ti-cloud-storage-export-gallery-verified source_deleted=true")

        tapCloudSecondaryAction(app, identifier: "cloudStorage.snapshot")
        XCTAssertTrue(
            waitForStatus(app, "cloudStorage.status", statusLog, containing: "截图完成", timeout: 15.0))
        Self.appendStatus(statusLog, "ti-cloud-storage-snapshot-verified")
        tapCloudSecondaryAction(app, identifier: "cloudStorage.gallery")
        handleSystemPermissionDialogs(app, attempts: 5)
        XCTAssertTrue(
            waitForStatusHandlingSystemPermissions(
                app, "cloudStorage.status", statusLog, containing: "已保存到系统相册", timeout: 20.0),
            "Ti Cloud Storage snapshot was not saved to Photos")
        Self.appendStatus(
            statusLog, "ti-cloud-storage-snapshot-gallery-verified source_deleted=true")

        XCTAssertTrue(
            waitForStatus(
                app, "cloudStorage.video_stage", statusLog,
                containing: "completed", timeout: timeoutSeconds),
            "Ti Cloud Storage replay did not consume the selected recording through its terminal state"
        )
        Self.appendStatus(statusLog, "ti-cloud-storage-replay-completed")

        tapCloudHeaderAction(app, identifier: "cloudStorage.upload_logs")
        XCTAssertTrue(
            waitForStatus(
                app, "cloudStorage.status", statusLog,
                containing: "日志上传完成：", timeout: timeoutSeconds))
        let logUploadStatus = statusValue(app, "cloudStorage.status")
        Self.appendStatus(statusLog, "ti-cloud-storage-log-upload-verified \(logUploadStatus)")
        attachScreenshot(app, name: "ti-cloud-storage-player-complete")

        tap(app, "cloudStorage.close")
        XCTAssertTrue(waitForElement(app, "client.configure.page", timeout: 15.0))
        XCTAssertTrue(waitForElement(app, "ti-cloud-storage.enter_player", timeout: 5.0))
        Self.appendStatus(statusLog, "ti-cloud-storage-returned-to-configure")
    }

    @MainActor
    private func fetchOneTimeToken(_ urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else {
            throw XCTSkip("invalid Ti Cloud Storage token URL")
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard data.count <= 64 * 1024,
            let response = response as? HTTPURLResponse,
            (200..<300).contains(response.statusCode)
        else {
            throw XCTSkip("Ti Cloud Storage token endpoint returned an invalid response")
        }
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: String],
            let token = dictionary["token"], !token.isEmpty
        else {
            throw XCTSkip("Ti Cloud Storage token endpoint returned no token")
        }
        return token
    }

    @MainActor
    private func runTiCloudStoragePublicSdkCase(
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
        var tiCloudStorage: TiCloudStorage?
        var replay: TiCloudStorageReplay?
        var audio: TiCloudStorageAudioOutput?
        var video: TiCloudStorageVideoOutput?
        var recordingFile: TiCloudStorageRecordingFile?
        var completionSnapshotFile: TiCloudStorageSnapshotFile?
        var snapshotFile: TiCloudStorageSnapshotFile?
        var exportFile: TiCloudStorageRecordingFile?
        var partialExportFile: TiCloudStorageRecordingFile?
        var completeExportObservation: [String: Any]?
        var partialExportObservation: [String: Any]?
        var pauseStart: Int64 = 0
        var pauseObserved: Int64 = 0
        var seekTarget: Int64 = 0
        var seekObserved: Int64 = 0
        var slowWall: Int64 = 0
        var slowMedia: Int64 = 0
        var replayStarted = false
        var rawDumpArchivePath: String?
        var rawDumpArchiveEvidence: TiRawDumpArchive?
        var audioAttached = false
        var videoAttached = false
        let observer = TiCloudStorageSdkOutputObserver()
        let rawDumpCase = payload["raw_dump_case"] == "1"

        func cleanUp() async throws {
            var failures: [String] = []
            func record(_ code: Int32, _ operation: String) {
                if code != TiCloudStorageErrorCode.ok {
                    failures.append("\(operation)=\(code)")
                }
            }

            if let recordingFile { record(await recordingFile.delete(), "recording file delete") }
            if let completionSnapshotFile {
                record(await completionSnapshotFile.delete(), "completion snapshot file delete")
            }
            if let snapshotFile {
                record(await snapshotFile.delete(), "async snapshot file delete")
            }
            if let exportFile { record(await exportFile.delete(), "export file delete") }
            if let partialExportFile {
                record(await partialExportFile.delete(), "partial export file delete")
            }
            if let rawDumpArchivePath {
                try? FileManager.default.removeItem(atPath: rawDumpArchivePath)
            }
            if replayStarted {
                record(
                    retryTiCloudStorageInUse { replay?.stop() ?? TiCloudStorageErrorCode.ok },
                    "replay stop")
            }
            if videoAttached {
                record(
                    retryTiCloudStorageInUse { video?.detach() ?? TiCloudStorageErrorCode.ok },
                    "video detach")
            }
            if audioAttached {
                record(
                    retryTiCloudStorageInUse { audio?.detach() ?? TiCloudStorageErrorCode.ok },
                    "audio detach")
            }
            record(
                retryTiCloudStorageInUse { video?.dispose() ?? TiCloudStorageErrorCode.ok },
                "video dispose")
            record(
                retryTiCloudStorageInUse { audio?.dispose() ?? TiCloudStorageErrorCode.ok },
                "audio dispose")
            record(
                retryTiCloudStorageInUse { replay?.dispose() ?? TiCloudStorageErrorCode.ok },
                "replay dispose")
            record(
                retryTiCloudStorageInUse {
                    tiCloudStorage?.dispose() ?? TiCloudStorageErrorCode.ok
                },
                "storage dispose")
            if initialized {
                record(retryTiCloudStorageInUse(TiCloudStorage.shutdown), "storage shutdown")
            }
            guard failures.isEmpty else {
                throw NSError(
                    domain: "TiCloudStoragePublicSdkCaseCleanup",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: failures.joined(separator: ", ")])
            }
        }

        do {
            try requireTiCloudStorageOk(
                TiCloudStorage.initialize(
                    appId: required(payload, "app_id"),
                    endpoint: payload["endpoint"] ?? "",
                    consoleLogEnabled: true),
                "Ti Cloud Storage initialization")
            initialized = true
            if !rawDumpCase {
                try verifyTiCloudStorageConcurrency(
                    token: token,
                    videoChannel: videoChannel,
                    statusLog: statusLog)
                Self.appendStatus(statusLog, "ti-cloud-storage-sdk-concurrency-verified")
            }
            let activeTiCloudStorage = TiCloudStorage(token: token)
            tiCloudStorage = activeTiCloudStorage
            let listed = await activeTiCloudStorage.listRecordings(
                startTimeMs: queryStartMs,
                endTimeMs: queryEndMs)
            try requireTiCloudStorageOk(listed.code, "exact Ti Cloud Storage query")
            let range = try XCTUnwrap(
                listed.recordings.max { lhs, rhs in
                    lhs.endTimeMs - lhs.startTimeMs < rhs.endTimeMs - rhs.startTimeMs
                })
            XCTAssertGreaterThanOrEqual(range.endTimeMs - range.startTimeMs, 110_000)
            Self.appendStatus(statusLog, "ti-cloud-storage-sdk-query-verified")

            let activeReplay = activeTiCloudStorage.createReplay()
            replay = activeReplay
            let activeAudio = TiCloudStorageAudioOutput()
            audio = activeAudio
            let activeVideo = TiCloudStorageVideoOutput()
            video = activeVideo
            activeAudio.delegate = observer
            activeVideo.delegate = observer
            let completed = expectation(
                description: "Ti Cloud Storage replay reaches requested end")
            activeReplay.onTimeChanged = { observer.setReplayTime($0) }
            activeReplay.onError = { code in
                observer.setReplayError(code)
                completed.fulfill()
            }
            activeReplay.onCompleted = {
                observer.markSourceCompleted()
                completed.fulfill()
            }
            try requireTiCloudStorageOk(
                activeAudio.attach(replay: activeReplay, channelId: audioChannel),
                "audio output attach")
            audioAttached = true
            try requireTiCloudStorageOk(
                activeVideo.attach(replay: activeReplay, channelId: videoChannel),
                "video output attach")
            videoAttached = true
            try requireTiCloudStorageOk(
                activeReplay.play(startTimeMs: range.startTimeMs, endTimeMs: range.endTimeMs),
                "Ti Cloud Storage replay play")
            replayStarted = true
            try await waitForTiCloudStorageCondition(timeoutSeconds: 30) {
                activeAudio.state == .playing && activeVideo.state == .rendering
                    && observer.currentTimeMs >= range.startTimeMs + 800
            }
            Self.appendStatus(statusLog, "ti-cloud-storage-sdk-outputs-verified")
            if rawDumpCase {
                let options = TiCloudStorageRawDumpOptions(
                    audioChannelIds: [NSNumber(value: audioChannel)],
                    videoChannelIds: [NSNumber(value: videoChannel)])
                let started = await activeReplay.startRawDump(options: options)
                try requireTiCloudStorageOk(started.code, "Ti Cloud Storage raw dump start")
                let dump = try XCTUnwrap(started.dump)
                let conflicting = await activeReplay.startRawDump(options: options)
                XCTAssertEqual(conflicting.code, TiCloudStorageErrorCode.inUse)
                try await Task.sleep(nanoseconds: 3_000_000_000)
                try requireTiCloudStorageOk(
                    activeReplay.pause(), "Ti Cloud Storage raw dump replay pause")
                try await waitForTiCloudStorageCondition(timeoutSeconds: 5) {
                    activeAudio.state == .paused && activeVideo.state == .paused
                }
                try requireTiCloudStorageOk(
                    activeReplay.resume(), "Ti Cloud Storage raw dump replay resume")
                let rawDumpSeek = min(
                    range.endTimeMs - 15_000,
                    range.startTimeMs + (range.endTimeMs - range.startTimeMs) / 2)
                try requireTiCloudStorageOk(
                    activeReplay.seek(toTimeMs: rawDumpSeek),
                    "Ti Cloud Storage raw dump replay seek")
                try await waitForTiCloudStorageCondition(timeoutSeconds: 8) {
                    abs(observer.currentTimeMs - rawDumpSeek) <= 2_000
                }
                try await Task.sleep(nanoseconds: 8_000_000_000)
                let progressBeforeStop = observer.currentTimeMs
                async let firstStop = dump.stop()
                async let secondStop = dump.stop()
                let (first, second) = await (firstStop, secondStop)
                try requireTiCloudStorageOk(first.code, "Ti Cloud Storage raw dump first stop")
                try requireTiCloudStorageOk(second.code, "Ti Cloud Storage raw dump repeated stop")
                let firstArchive = try XCTUnwrap(first.archive)
                let secondArchive = try XCTUnwrap(second.archive)
                XCTAssertEqual(firstArchive.captureId, secondArchive.captureId)
                XCTAssertGreaterThan(firstArchive.size, 0)
                XCTAssertFalse(firstArchive.empty)
                rawDumpArchivePath = firstArchive.path
                rawDumpArchiveEvidence = firstArchive
                Self.appendStatus(
                    statusLog,
                    Self.rawDumpEvidenceMarker(event: "stop", archive: firstArchive))
                Self.appendStatus(
                    statusLog,
                    "ti-cloud-storage-sdk-raw-dump-recovery-verified capture_id=\(firstArchive.captureId) start_conflict=true pause_seek=true repeated_stop=true"
                )
                try await waitForTiCloudStorageCondition(timeoutSeconds: 8) {
                    observer.currentTimeMs >= progressBeforeStop + 500
                }
                XCTAssertEqual(observer.audioError, 0)
                XCTAssertEqual(observer.videoError, 0)
                Self.appendStatus(
                    statusLog,
                    "ti-cloud-storage-sdk-raw-dump-media-continuity-verified")
                let upload: TiRtcLogUploadResult = await withCheckedContinuation { continuation in
                    let code = TiRtcLogging.upload { continuation.resume(returning: $0) }
                    XCTAssertEqual(code, TiCloudStorageErrorCode.ok)
                }
                try requireTiCloudStorageOk(upload.code, "Ti Cloud Storage raw dump log upload")
                XCTAssertFalse((upload.logId ?? "").isEmpty)
                Self.appendStatus(
                    statusLog,
                    Self.rawDumpEvidenceMarker(
                        event: "upload", archive: firstArchive,
                        code: upload.code, logId: upload.logId ?? ""))
                Self.appendStatus(statusLog, "ti-cloud-storage-sdk-log-upload-verified")
                try requireTiCloudStorageOk(activeReplay.stop(), "raw dump replay stop")
                replayStarted = false
                activeReplay.onError = nil
                activeReplay.onCompleted = nil
                completed.fulfill()
                await fulfillment(of: [completed], timeout: 1.0)
                try await cleanUp()
                Self.appendStatus(statusLog, "ti-cloud-storage-sdk-teardown-completed")
                Self.appendStatus(statusLog, "ti-cloud-storage-sdk-case-completed")
                return
            }
            observer.beginContinuousPlayback()
            await fulfillment(
                of: [completed],
                timeout: TimeInterval(range.endTimeMs - range.startTimeMs) / 1000 + 90)
            XCTAssertEqual(observer.replayError, 0)
            try await waitForTiCloudStorageCondition(timeoutSeconds: 30) {
                activeAudio.state == .completed && activeVideo.state == .completed
            }
            observer.endContinuousPlayback()
            XCTAssertEqual(observer.audioError, 0)
            XCTAssertEqual(observer.videoError, 0)
            XCTAssertEqual(observer.bufferingCount, 0)
            XCTAssertGreaterThan(observer.progressAfterSource, 0)
            XCTAssertEqual(observer.currentTimeMs, range.endTimeMs)
            replayStarted = false
            Self.appendStatus(statusLog, "ti-cloud-storage-sdk-replay-completed")

            try requireTiCloudStorageOk(
                activeReplay.play(startTimeMs: range.startTimeMs, endTimeMs: range.endTimeMs),
                "replacement replay play")
            replayStarted = true
            try await waitForTiCloudStorageCondition(timeoutSeconds: 30) {
                activeAudio.state == .playing && activeVideo.state == .rendering
                    && observer.currentTimeMs >= range.startTimeMs + 800
                    && observer.currentTimeMs < range.startTimeMs + 15_000
            }
            let recordingStart = activeReplay.startRecording(
                videoChannelId: Int(videoChannel),
                audioChannelId: NSNumber(value: audioChannel))
            try requireTiCloudStorageOk(recordingStart.code, "replay recording start")
            let recordingTask = try XCTUnwrap(recordingStart.task)
            try await Task.sleep(nanoseconds: 6_000_000_000)
            let recorded = await recordingTask.stop()
            try requireTiCloudStorageOk(recorded.code, "replay recording stop")
            let capturedRecording = try XCTUnwrap(recorded.file)
            recordingFile = capturedRecording
            XCTAssertGreaterThanOrEqual(capturedRecording.durationMs, 4_500)
            Self.appendStatus(statusLog, "ti-cloud-storage-sdk-recording-verified")

            try requireTiCloudStorageOk(activeAudio.setVolume(0), "Ti Cloud Storage mute")
            try requireTiCloudStorageOk(
                activeAudio.setVolume(35), "Ti Cloud Storage volume restore")
            try requireTiCloudStorageOk(activeReplay.pause(), "Ti Cloud Storage replay pause")
            try await waitForTiCloudStorageCondition(timeoutSeconds: 5) {
                activeAudio.state == .paused && activeVideo.state == .paused
            }
            pauseStart = observer.currentTimeMs
            try await Task.sleep(nanoseconds: 1_200_000_000)
            pauseObserved = observer.currentTimeMs
            XCTAssertTrue((0...100).contains(pauseObserved - pauseStart))
            try requireTiCloudStorageOk(activeReplay.resume(), "Ti Cloud Storage replay resume")
            try await waitForTiCloudStorageCondition(timeoutSeconds: 5) {
                observer.currentTimeMs >= pauseStart + 500
            }
            let midpoint = range.startTimeMs + (range.endTimeMs - range.startTimeMs) / 2
            seekTarget = midpoint
            try requireTiCloudStorageOk(
                activeReplay.seek(toTimeMs: midpoint), "Ti Cloud Storage replay seek")
            try await waitForTiCloudStorageCondition(timeoutSeconds: 8) {
                abs(observer.currentTimeMs - midpoint) <= 2_000
            }
            seekObserved = observer.currentTimeMs
            try requireTiCloudStorageOk(
                activeReplay.setSpeed(.x0_5), "Ti Cloud Storage replay 1/2x")
            let slowStarted = Date()
            let slowMediaStarted = observer.currentTimeMs
            try await Task.sleep(nanoseconds: 3_000_000_000)
            slowWall = Int64(Date().timeIntervalSince(slowStarted) * 1_000)
            slowMedia = observer.currentTimeMs - slowMediaStarted
            XCTAssertGreaterThanOrEqual(slowMedia, 500)
            XCTAssertLessThanOrEqual(slowMedia * 10, slowWall * 8)
            try requireTiCloudStorageOk(activeReplay.setSpeed(.x1), "Ti Cloud Storage replay x1")
            Self.appendStatus(statusLog, "ti-cloud-storage-sdk-controls-verified")

            var completionSnapshot: TiCloudStorageSnapshotResult?
            let completionSnapshotDeadline = Date().addingTimeInterval(10)
            repeat {
                completionSnapshot = try await takeTiCloudStorageSnapshotWithCompletion(activeVideo)
                if completionSnapshot?.code == TiCloudStorageErrorCode.ok { break }
                XCTAssertEqual(completionSnapshot?.code, TiCloudStorageErrorCode.noFrame)
                try await Task.sleep(nanoseconds: 200_000_000)
            } while Date() < completionSnapshotDeadline
            let capturedCompletionSnapshot = try XCTUnwrap(completionSnapshot?.file)
            completionSnapshotFile = capturedCompletionSnapshot
            try validateTiCloudStorageMedia(path: capturedCompletionSnapshot.path, kind: "jpeg")

            var snapshot: TiCloudStorageSnapshotResult?
            let snapshotDeadline = Date().addingTimeInterval(10)
            repeat {
                snapshot = await activeVideo.takeSnapshot()
                if snapshot?.code == TiCloudStorageErrorCode.ok { break }
                XCTAssertEqual(snapshot?.code, TiCloudStorageErrorCode.noFrame)
                try await Task.sleep(nanoseconds: 200_000_000)
            } while Date() < snapshotDeadline
            let capturedSnapshot = try XCTUnwrap(snapshot?.file)
            snapshotFile = capturedSnapshot
            try validateTiCloudStorageMedia(path: capturedSnapshot.path, kind: "jpeg")
            Self.appendStatus(statusLog, "ti-cloud-storage-sdk-snapshot-verified")

            let artifactRoot = try required(payload, "artifact_root")
            let (completeObservation, capturedExport) = try await runObservedCloudExport(
                storage: activeTiCloudStorage,
                request: TiCloudStorageExportRequest(
                    startTimeMs: range.startTimeMs,
                    endTimeMs: range.endTimeMs,
                    videoChannelId: Int(videoChannel),
                    audioChannelId: NSNumber(value: audioChannel)),
                artifactRoot: artifactRoot,
                artifactName: "complete-export.mp4",
                expectComplete: true,
                knownGap: nil)
            completeExportObservation = completeObservation
            exportFile = capturedExport
            let partialFixture = try await independentlyConfirmedPartialFixture(
                activeTiCloudStorage, precedingRecording: range)
            let emptyRange = partialFixture.empty
            let partialRange = try tiCloudStoragePartialExportRange(
                recorded: partialFixture.recorded, empty: emptyRange)
            let knownGap = TiCloudStorageRecordingGap(
                range: emptyRange,
                tracks: [
                    TiCloudStorageRecordingTrack(kind: .video, channelId: videoChannel),
                    TiCloudStorageRecordingTrack(kind: .audio, channelId: audioChannel),
                ],
                reasons: [.noRecording])
            let (partialObservation, capturedPartialExport) = try await runObservedCloudExport(
                storage: activeTiCloudStorage,
                request: TiCloudStorageExportRequest(
                    startTimeMs: partialRange.startTimeMs,
                    endTimeMs: partialRange.endTimeMs,
                    videoChannelId: Int(videoChannel),
                    audioChannelId: NSNumber(value: audioChannel)),
                artifactRoot: artifactRoot,
                artifactName: "partial-export.mp4",
                expectComplete: false,
                knownGap: knownGap)
            partialExportObservation = partialObservation
            partialExportFile = capturedPartialExport
            try validateTiCloudStorageMedia(path: capturedRecording.path, kind: "mp4")
            Self.appendStatus(statusLog, "ti-cloud-storage-sdk-complete-export-verified")
            Self.appendStatus(statusLog, "ti-cloud-storage-sdk-partial-export-verified")

            try await deleteAndVerify(capturedRecording)
            recordingFile = nil
            try await deleteAndVerify(capturedCompletionSnapshot)
            completionSnapshotFile = nil
            try await deleteAndVerify(capturedSnapshot)
            snapshotFile = nil
            try await deleteAndVerify(capturedExport)
            exportFile = nil
            try await deleteAndVerify(capturedPartialExport)
            partialExportFile = nil
            Self.appendStatus(statusLog, "ti-cloud-storage-sdk-runtime-delete-verified")

            let upload: TiRtcLogUploadResult = await withCheckedContinuation { continuation in
                let code = TiRtcLogging.upload { continuation.resume(returning: $0) }
                XCTAssertEqual(code, TiCloudStorageErrorCode.ok)
            }
            try requireTiCloudStorageOk(upload.code, "Ti Cloud Storage log upload")
            XCTAssertFalse((upload.logId ?? "").isEmpty)
            if let rawDumpArchiveEvidence {
                Self.appendStatus(
                    statusLog,
                    Self.rawDumpEvidenceMarker(
                        event: "upload", archive: rawDumpArchiveEvidence,
                        code: upload.code, logId: upload.logId ?? ""))
            }
            Self.appendStatus(statusLog, "ti-cloud-storage-sdk-log-upload-verified")
            try requireTiCloudStorageOk(activeReplay.stop(), "replacement replay stop")
            replayStarted = false
        } catch {
            do {
                try await cleanUp()
            } catch let cleanupError {
                XCTFail("Ti Cloud Storage cleanup failed after case error: \(cleanupError)")
            }
            throw error
        }
        try await cleanUp()
        try writeCloudExportResult(
            path: try required(payload, "export_result_path"),
            completeExport: try XCTUnwrap(completeExportObservation),
            partialExport: try XCTUnwrap(partialExportObservation),
            pauseStart: pauseStart,
            pauseObserved: pauseObserved,
            seekTarget: seekTarget,
            seekObserved: seekObserved,
            slowWall: slowWall,
            slowMedia: slowMedia)
        Self.appendStatus(statusLog, "ti-cloud-storage-sdk-teardown-completed")
        Self.appendStatus(statusLog, "ti-cloud-storage-sdk-case-completed")
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

    private func tiCloudStorageGapCoverageMatches(
        _ covering: [TiCloudStorageRecordingGap], _ targets: [TiCloudStorageRecordingGap]
    ) -> Bool {
        targets.allSatisfy { target in
            guard target.range.startTimeMs < target.range.endTimeMs else { return false }
            let tracks: [TiCloudStorageRecordingTrack?] =
                target.tracks.isEmpty ? [nil] : target.tracks.map { $0 }
            return tracks.allSatisfy { track in
                let reasons: [TiCloudStorageRecordingGapReason?] =
                    target.reasons.isEmpty ? [nil] : target.reasons.map { $0 }
                return reasons.allSatisfy { reason in
                    let matching = covering.filter { gap in
                        let trackMatches: Bool
                        if let track {
                            trackMatches = gap.tracks.contains {
                                $0.kind == track.kind && $0.channelId == track.channelId
                            }
                        } else {
                            trackMatches = gap.tracks.isEmpty
                        }
                        let reasonMatches =
                            reason == nil || reason == .unknown
                            || gap.reasons.contains(reason!)
                        return trackMatches && reasonMatches
                    }.sorted { $0.range.startTimeMs < $1.range.startTimeMs }
                    var coveredEnd = target.range.startTimeMs
                    for gap in matching {
                        if gap.range.startTimeMs > coveredEnd { break }
                        coveredEnd = max(coveredEnd, gap.range.endTimeMs)
                        if coveredEnd >= target.range.endTimeMs { break }
                    }
                    return coveredEnd >= target.range.endTimeMs
                }
            }
        }
    }

    private func tiCloudStorageExportObservationValid(
        request: TiCloudStorageRecordingRange,
        report: TiCloudStorageExportReport,
        progress: [TiCloudStorageExportProgress],
        gaps: [TiCloudStorageRecordingGap],
        expectComplete: Bool,
        knownGap: TiCloudStorageRecordingGap?
    ) -> Bool {
        let requestDuration = request.endTimeMs - request.startTimeMs
        guard requestDuration > 0,
            report.requestedRange.startTimeMs == request.startTimeMs,
            report.requestedRange.endTimeMs == request.endTimeMs,
            report.complete == expectComplete,
            report.termination == .exhausted,
            report.cause == TiCloudStorageErrorCode.ok,
            report.coveredDurationMs > 0,
            report.coveredDurationMs <= requestDuration,
            !report.segments.isEmpty,
            report.unprocessedRanges.isEmpty,
            !progress.isEmpty,
            tiCloudStorageGapCoverageMatches(report.gaps, gaps),
            tiCloudStorageGapCoverageMatches(gaps, report.gaps)
        else { return false }
        var previousFraction = -1.0
        var previousCovered: Int64 = -1
        for detail in progress {
            guard detail.fraction >= 0, detail.fraction <= 1,
                detail.coveredDurationMs >= 0,
                detail.coveredDurationMs <= requestDuration,
                detail.fraction >= previousFraction,
                detail.coveredDurationMs >= previousCovered
            else { return false }
            previousFraction = detail.fraction
            previousCovered = detail.coveredDurationMs
        }
        guard previousCovered > 0, previousCovered <= report.coveredDurationMs else { return false }
        var requestedCoverage: [TiCloudStorageRecordingRange] = []
        for segment in report.segments {
            let sourceDuration = segment.sourceRange.endTimeMs - segment.sourceRange.startTimeMs
            let outputDuration = segment.outputEndMs - segment.outputStartMs
            guard segment.sourceRange.startTimeMs < request.endTimeMs,
                segment.sourceRange.endTimeMs > request.startTimeMs,
                segment.sourceRange.endTimeMs <= request.endTimeMs,
                segment.sourceRange.startTimeMs < segment.sourceRange.endTimeMs,
                segment.outputStartMs >= 0,
                segment.outputStartMs < segment.outputEndMs,
                sourceDuration == outputDuration
            else { return false }
            requestedCoverage.append(
                TiCloudStorageRecordingRange(
                    startTimeMs: max(segment.sourceRange.startTimeMs, request.startTimeMs),
                    endTimeMs: min(segment.sourceRange.endTimeMs, request.endTimeMs)))
        }
        guard tiCloudStorageNormalizedRangeDuration(requestedCoverage) == report.coveredDurationMs
        else { return false }
        if expectComplete {
            return report.coveredDurationMs == requestDuration
                && gaps.isEmpty && report.gaps.isEmpty && knownGap == nil
        }
        guard let knownGap else { return false }
        return !gaps.isEmpty && !report.gaps.isEmpty
            && tiCloudStorageGapCoverageMatches(report.gaps, [knownGap])
            && tiCloudStorageGapCoverageMatches(gaps, [knownGap])
    }

    private func tiCloudStorageNormalizedRangeDuration(
        _ ranges: [TiCloudStorageRecordingRange]
    ) -> Int64 {
        let sorted = ranges.sorted {
            ($0.startTimeMs, $0.endTimeMs) < ($1.startTimeMs, $1.endTimeMs)
        }
        guard let first = sorted.first else { return 0 }
        var mergedStart = first.startTimeMs
        var mergedEnd = first.endTimeMs
        var duration: Int64 = 0
        for range in sorted.dropFirst() {
            if range.startTimeMs <= mergedEnd {
                mergedEnd = max(mergedEnd, range.endTimeMs)
            } else {
                duration += mergedEnd - mergedStart
                mergedStart = range.startTimeMs
                mergedEnd = range.endTimeMs
            }
        }
        return duration + mergedEnd - mergedStart
    }

    @MainActor
    private func independentlyConfirmedPartialFixture(
        _ storage: TiCloudStorage, precedingRecording: TiCloudStorageRecordingRange
    ) async throws -> (recorded: TiCloudStorageRecordingRange, empty: TiCloudStorageRecordingRange) {
        var recorded = precedingRecording
        guard recorded.endTimeMs - recorded.startTimeMs >= 12_000 else {
            throw NSError(
                domain: "TiCloudStorageExportContract", code: 7,
                userInfo: [NSLocalizedDescriptionKey: "preceding recording is too short"])
        }
        for attempt in 0..<2 {
            let start = recorded.endTimeMs
            let end = start + 60_000
            let listed = await storage.listRecordings(startTimeMs: start, endTimeMs: end)
            try requireTiCloudStorageOk(listed.code, "partial export empty-window query")
            let overlapping = listed.recordings.filter {
                $0.startTimeMs < end && $0.endTimeMs > start
            }
            if overlapping.isEmpty {
                return (
                    recorded,
                    TiCloudStorageRecordingRange(startTimeMs: start, endTimeMs: end)
                )
            }
            guard attempt == 0,
                let next = overlapping.max(by: { $0.endTimeMs < $1.endTimeMs }),
                next.endTimeMs > start,
                let advanced = tiCloudStorageAdvancedPartialFixtureRecording(
                    recorded: recorded, next: next)
            else {
                break
            }
            recorded = advanced
        }
        XCTFail("could not independently establish an empty partial-export window")
        throw NSError(
            domain: "TiCloudStorageExportContract", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "partial export empty-window setup failed"])
    }

    private func tiCloudStorageAdvancedPartialFixtureRecording(
        recorded: TiCloudStorageRecordingRange, next: TiCloudStorageRecordingRange
    ) -> TiCloudStorageRecordingRange? {
        let advanced = TiCloudStorageRecordingRange(
            startTimeMs: next.startTimeMs <= recorded.endTimeMs
                ? min(recorded.startTimeMs, next.startTimeMs) : next.startTimeMs,
            endTimeMs: next.endTimeMs)
        return advanced.endTimeMs - advanced.startTimeMs >= 12_000 ? advanced : nil
    }

    private func tiCloudStoragePartialExportRange(
        recorded: TiCloudStorageRecordingRange, empty: TiCloudStorageRecordingRange
    ) throws -> TiCloudStorageRecordingRange {
        guard recorded.endTimeMs - recorded.startTimeMs >= 12_000,
            recorded.endTimeMs == empty.startTimeMs,
            empty.startTimeMs < empty.endTimeMs
        else {
            throw NSError(
                domain: "TiCloudStorageExportContract", code: 8,
                userInfo: [NSLocalizedDescriptionKey: "partial export fixture is invalid"])
        }
        return TiCloudStorageRecordingRange(
            startTimeMs: recorded.endTimeMs - 12_000,
            endTimeMs: empty.endTimeMs)
    }

    private func cloudRangeJSON(_ range: TiCloudStorageRecordingRange) -> [String: Any] {
        ["start_time_ms": range.startTimeMs, "end_time_ms": range.endTimeMs]
    }

    private func cloudGapJSON(_ gap: TiCloudStorageRecordingGap) -> [String: Any] {
        [
            "range": cloudRangeJSON(gap.range),
            "tracks": gap.tracks.map {
                ["kind": $0.kind.rawValue, "channel_id": $0.channelId]
            },
            "reasons": gap.reasons.map(\.rawValue),
        ]
    }

    @MainActor
    private func copyCloudExportArtifact(
        _ file: TiCloudStorageRecordingFile, root: String, name: String
    ) throws -> [String: Any] {
        let directory = URL(fileURLWithPath: root, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.copyItem(
                at: URL(fileURLWithPath: file.path), to: destination)
            try validateTiCloudStorageMedia(path: destination.path, kind: "mp4")
            let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
            let bytes = (attributes[.size] as? NSNumber)?.intValue ?? 0
            guard bytes > 8 else {
                throw NSError(
                    domain: "TiCloudStorageExportContract", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "copied export artifact is empty"])
            }
            return ["path": destination.path, "kind": "mp4", "bytes": bytes]
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    @MainActor
    private func runObservedCloudExport(
        storage: TiCloudStorage,
        request: TiCloudStorageExportRequest,
        artifactRoot: String,
        artifactName: String,
        expectComplete: Bool,
        knownGap: TiCloudStorageRecordingGap?
    ) async throws -> ([String: Any], TiCloudStorageRecordingFile) {
        let observations = TiCloudStorageExportObservationBox()
        var task: TiCloudStorageExportTask?
        let exported: TiCloudStorageExportResult = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<TiCloudStorageExportResult, Error>) in
            let started = storage.exportRecording(
                request,
                progress: nil,
                progressDetail: { observations.record(progress: $0) },
                onRecordingGap: { observations.record(gap: $0) }
            ) { result in
                observations.recordTerminal()
                continuation.resume(returning: result)
            }
            guard started.code == TiCloudStorageErrorCode.ok, let startedTask = started.task else {
                continuation.resume(
                    throwing: NSError(
                        domain: "TiCloudStorageExportContract", code: Int(started.code),
                        userInfo: [NSLocalizedDescriptionKey: "range export did not start"]))
                return
            }
            task = startedTask
        }
        do {
            guard task != nil else {
                throw NSError(
                    domain: "TiCloudStorageExportContract", code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "range export task is missing"])
            }
            let barrier = expectation(description: "export callback queue drained")
            var barrierObserved = false
            DispatchQueue.main.async {
                barrierObserved = true
                barrier.fulfill()
            }
            await fulfillment(of: [barrier], timeout: 5)
            guard barrierObserved else {
                throw NSError(
                    domain: "TiCloudStorageExportContract", code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "export callback barrier was not observed"])
            }
            try requireTiCloudStorageOk(exported.code, "Ti Cloud Storage range export")
            let report = try XCTUnwrap(exported.report)
            let file = try XCTUnwrap(exported.file)
            let (progress, gaps, terminalCount, progressCount, progressStreamValid) =
                observations.snapshot()
            guard terminalCount == 1 else {
                throw NSError(
                    domain: "TiCloudStorageExportContract", code: 5,
                    userInfo: [NSLocalizedDescriptionKey: "unexpected terminal callback count"])
            }
            guard progressStreamValid, progressCount >= progress.count else {
                throw NSError(
                    domain: "TiCloudStorageExportContract", code: 9,
                    userInfo: [NSLocalizedDescriptionKey: "export progress stream is invalid"])
            }
            let requestRange = TiCloudStorageRecordingRange(
                startTimeMs: request.startTimeMs, endTimeMs: request.endTimeMs)
            guard
                tiCloudStorageExportObservationValid(
                    request: requestRange,
                    report: report,
                    progress: progress,
                    gaps: gaps,
                    expectComplete: expectComplete,
                    knownGap: knownGap)
            else {
                throw NSError(
                    domain: "TiCloudStorageExportContract", code: 6,
                    userInfo: [NSLocalizedDescriptionKey: "export observations are incomplete"])
            }
            try validateTiCloudStorageMedia(path: file.path, kind: "mp4")
            let artifact = try copyCloudExportArtifact(
                file, root: artifactRoot, name: artifactName)
            var value: [String: Any] = [
                "requested_range": cloudRangeJSON(requestRange),
                "progress_details": progress.map {
                    ["fraction": $0.fraction, "covered_duration_ms": $0.coveredDurationMs]
                },
                "progress_observation_count": progressCount,
                "progress_stream_valid": progressStreamValid,
                "recording_gaps": gaps.map(cloudGapJSON),
                "report": [
                    "requested_range": cloudRangeJSON(report.requestedRange),
                    "covered_duration_ms": report.coveredDurationMs,
                    "segments": report.segments.map {
                        [
                            "source_range": cloudRangeJSON($0.sourceRange),
                            "output_start_ms": $0.outputStartMs,
                            "output_end_ms": $0.outputEndMs,
                        ] as [String: Any]
                    },
                    "gaps": report.gaps.map(cloudGapJSON),
                    "unprocessed_ranges": report.unprocessedRanges.map(cloudRangeJSON),
                    "complete": report.complete,
                    "termination": report.termination.rawValue,
                    "cause": report.cause,
                ] as [String: Any],
                "callback_barrier_observed": barrierObserved,
                "terminal_callback_count": terminalCount,
                "gap_coverage_bilateral": true,
                "artifact": artifact,
            ]
            if let knownGap {
                value["confirmed_empty_range"] = cloudRangeJSON(knownGap.range)
                value["known_gap"] = cloudGapJSON(knownGap)
                value["empty_range_confirmed"] = true
                value["known_gap_covered"] = true
            }
            return (value, file)
        } catch {
            if let file = exported.file { _ = await file.delete() }
            throw error
        }
    }

    private func writeCloudExportResult(
        path: String,
        completeExport: [String: Any],
        partialExport: [String: Any],
        pauseStart: Int64,
        pauseObserved: Int64,
        seekTarget: Int64,
        seekObserved: Int64,
        slowWall: Int64,
        slowMedia: Int64
    ) throws {
        let value: [String: Any] = [
            "schema_version": 1,
            "consumer": "darwin-public-swift-headless",
            "mode": "cloud-integration",
            "architecture": "arm64",
            "process_id": ProcessInfo.processInfo.processIdentifier,
            "status": "passed",
            "result": [
                "status": "passed",
                "query_ok": true,
                "first_audio": true,
                "first_video": true,
                "pause_resume_ok": true,
                "seek_speed_volume_ok": true,
                "snapshot_ok": true,
                "recording_ok": true,
                "export_ok": true,
                "delete_ok": true,
                "natural_terminal": true,
                "log_upload_observed": true,
                "teardown_ok": true,
                "pause_started_time_ms": pauseStart,
                "pause_observed_time_ms": pauseObserved,
                "seek_target_time_ms": seekTarget,
                "seek_observed_time_ms": seekObserved,
                "speed_half_wall_elapsed_ms": slowWall,
                "speed_half_media_elapsed_ms": slowMedia,
                "complete_export": completeExport,
                "partial_export": partialExport,
            ] as [String: Any],
        ]
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        try (data + Data("\n".utf8)).write(
            to: URL(fileURLWithPath: path), options: .atomic)
    }

    private func requireTiCloudStorageOk(_ code: Int32, _ operation: String) throws {
        guard code == TiCloudStorageErrorCode.ok else {
            XCTFail("\(operation) failed: \(code)")
            throw XCTSkip("\(operation) failed: \(code)")
        }
    }

    @MainActor
    private func waitForTiCloudStorageCondition(
        timeoutSeconds: TimeInterval,
        _ predicate: @MainActor @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while !predicate() {
            if Date() >= deadline {
                XCTFail("Ti Cloud Storage SDK condition timed out")
                throw XCTSkip("Ti Cloud Storage SDK condition timed out")
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    @MainActor
    private func validateTiCloudStorageMedia(path: String, kind: String) throws {
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 12) ?? Data()
        XCTAssertGreaterThanOrEqual(data.count, 8)
        if kind == "jpeg" {
            XCTAssertEqual(Array(data.prefix(2)), [0xff, 0xd8])
            let url = URL(fileURLWithPath: path) as CFURL
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(url, nil))
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            XCTAssertGreaterThan(image.width, 0)
            XCTAssertGreaterThan(image.height, 0)
        } else {
            XCTAssertEqual(String(data: data[4..<8], encoding: .ascii), "ftyp")
        }
    }

    @MainActor
    private func deleteAndVerify(_ file: TiCloudStorageRecordingFile) async throws {
        let path = file.path
        try requireTiCloudStorageOk(await file.delete(), "Runtime recording delete")
        try requireTiCloudStorageOk(await file.delete(), "repeat Runtime recording delete")
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    @MainActor
    private func deleteAndVerify(_ file: TiCloudStorageSnapshotFile) async throws {
        let path = file.path
        try requireTiCloudStorageOk(await file.delete(), "Runtime snapshot delete")
        try requireTiCloudStorageOk(await file.delete(), "repeat Runtime snapshot delete")
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    @MainActor
    private func retryTiCloudStorageInUse(_ operation: () -> Int32) -> Int32 {
        let deadline = Date().addingTimeInterval(5)
        while true {
            let code = operation()
            if code != TiCloudStorageErrorCode.inUse || Date() >= deadline { return code }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
    }

    @MainActor
    private func takeTiCloudStorageSnapshotWithCompletion(
        _ output: TiCloudStorageVideoOutput
    ) async throws -> TiCloudStorageSnapshotResult {
        let delivered = expectation(description: "Ti Cloud Storage completion snapshot delivered")
        delivered.assertForOverFulfill = true
        let result = TiCloudStorageSnapshotResultBox()
        output.takeSnapshotForObjectiveC { value in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(result.record(value), 1)
            delivered.fulfill()
        }
        await fulfillment(of: [delivered], timeout: 10)
        XCTAssertEqual(result.count(), 1)
        return try XCTUnwrap(result.value())
    }

    @MainActor
    private func verifyTiCloudStorageConcurrency(
        token: String,
        videoChannel: UInt8,
        statusLog: String
    ) throws {
        try verifyTiCloudStorageTwoThreadDispose(token: token)
        Self.appendStatus(
            statusLog, "ti-cloud-storage-sdk-concurrency-two-thread-dispose-verified")

        try verifyTiCloudStorageUpdateTokenDisposeRace(token: token)
        Self.appendStatus(
            statusLog, "ti-cloud-storage-sdk-concurrency-update-token-dispose-verified")

        try verifyTiCloudStorageReplayControlDisposeRace(token: token)
        Self.appendStatus(
            statusLog, "ti-cloud-storage-sdk-concurrency-replay-control-dispose-verified")

        try verifyTiCloudStorageLazyStoreDisposeRace(token: token)
        Self.appendStatus(
            statusLog, "ti-cloud-storage-sdk-concurrency-lazy-store-dispose-verified")

        try verifyTiCloudStorageLazyReplayDisposeRace(token: token)
        Self.appendStatus(
            statusLog, "ti-cloud-storage-sdk-concurrency-lazy-replay-dispose-verified")

        try verifyTiCloudStorageChildAndAttachmentLifetime(
            token: token, videoChannel: videoChannel, statusLog: statusLog)
    }

    @MainActor
    private func verifyTiCloudStorageTwoThreadDispose(token: String) throws {
        let cloudStorage = TiCloudStorage(token: token)
        try runTiCloudStorageConcurrencyScenario(
            "two-thread dispose",
            operation: {
                try requireTiCloudStorageConcurrency(
                    cloudStorage.updateToken(token) == TiCloudStorageErrorCode.ok,
                    "two-thread dispose store creation failed")
                let results = try runTiCloudStorageConcurrentCalls(
                    cloudStorage.dispose,
                    cloudStorage.dispose
                )
                try requireTiCloudStorageConcurrency(
                    [TiCloudStorageErrorCode.ok, TiCloudStorageErrorCode.inUse].contains(results.0)
                        && [TiCloudStorageErrorCode.ok, TiCloudStorageErrorCode.inUse].contains(
                            results.1)
                        && (results.0 == TiCloudStorageErrorCode.ok
                            || results.1 == TiCloudStorageErrorCode.ok),
                    "unexpected two-thread dispose results: \(results.0), \(results.1)")
                try requireTiCloudStorageConcurrency(
                    retryTiCloudStorageInUse(cloudStorage.dispose) == TiCloudStorageErrorCode.ok,
                    "two-thread dispose did not reach release")
                try requireTiCloudStorageConcurrency(
                    cloudStorage.updateToken("after-two-thread-dispose")
                        == TiCloudStorageErrorCode.notInitialized,
                    "two-thread disposed store remained usable")
            },
            cleanup: {
                [("store dispose", retryTiCloudStorageInUse(cloudStorage.dispose))]
            })
    }

    @MainActor
    private func verifyTiCloudStorageUpdateTokenDisposeRace(token: String) throws {
        let cloudStorage = TiCloudStorage(token: token)
        try runTiCloudStorageConcurrencyScenario(
            "updateToken/dispose race",
            operation: {
                try requireTiCloudStorageConcurrency(
                    cloudStorage.updateToken(token) == TiCloudStorageErrorCode.ok,
                    "updateToken race store creation failed")
                let results = try runTiCloudStorageConcurrentCalls(
                    { cloudStorage.updateToken(token) },
                    cloudStorage.dispose
                )
                try requireTiCloudStorageCallDisposeResults(
                    call: results.0,
                    dispose: results.1,
                    operation: "updateToken/dispose race")
                try requireTiCloudStorageConcurrency(
                    retryTiCloudStorageInUse(cloudStorage.dispose) == TiCloudStorageErrorCode.ok,
                    "updateToken race store did not reach release")
                try requireTiCloudStorageConcurrency(
                    cloudStorage.updateToken("after-update-token-dispose")
                        == TiCloudStorageErrorCode.notInitialized,
                    "updateToken race store remained usable after release")
            },
            cleanup: {
                [("store dispose", retryTiCloudStorageInUse(cloudStorage.dispose))]
            })
    }

    @MainActor
    private func verifyTiCloudStorageReplayControlDisposeRace(token: String) throws {
        let cloudStorage = TiCloudStorage(token: token)
        let replay = cloudStorage.createReplay()
        try runTiCloudStorageConcurrencyScenario(
            "Replay control/dispose race",
            operation: {
                try requireTiCloudStorageConcurrency(
                    cloudStorage.updateToken(token) == TiCloudStorageErrorCode.ok,
                    "Replay race store creation failed")
                try requireTiCloudStorageConcurrency(
                    replay.setSpeed(.x2) == TiCloudStorageErrorCode.ok,
                    "Replay race creation failed")
                let results = try runTiCloudStorageConcurrentCalls(
                    { replay.setSpeed(.x4) },
                    replay.dispose
                )
                try requireTiCloudStorageCallDisposeResults(
                    call: results.0,
                    dispose: results.1,
                    operation: "Replay control/dispose race")
                try requireTiCloudStorageConcurrency(
                    retryTiCloudStorageInUse(replay.dispose) == TiCloudStorageErrorCode.ok,
                    "Replay control race did not reach release")
                try requireTiCloudStorageConcurrency(
                    replay.setSpeed(.x1) == TiCloudStorageErrorCode.notInitialized,
                    "Replay remained usable after control/dispose release")
            },
            cleanup: {
                [
                    ("Replay dispose", retryTiCloudStorageInUse(replay.dispose)),
                    ("store dispose", retryTiCloudStorageInUse(cloudStorage.dispose)),
                ]
            })
    }

    @MainActor
    private func verifyTiCloudStorageLazyStoreDisposeRace(token: String) throws {
        let cloudStorage = TiCloudStorage(token: token)
        try runTiCloudStorageConcurrencyScenario(
            "lazy Store creation/dispose race",
            operation: {
                let results = try runTiCloudStorageConcurrentCalls(
                    { cloudStorage.updateToken(token) },
                    cloudStorage.dispose
                )
                try requireTiCloudStorageCallDisposeResults(
                    call: results.0,
                    dispose: results.1,
                    operation: "lazy Store creation/dispose race")
                try requireTiCloudStorageConcurrency(
                    retryTiCloudStorageInUse(cloudStorage.dispose) == TiCloudStorageErrorCode.ok,
                    "lazy Store race did not reach release")
            },
            cleanup: {
                [("store dispose", retryTiCloudStorageInUse(cloudStorage.dispose))]
            })
    }

    @MainActor
    private func verifyTiCloudStorageLazyReplayDisposeRace(token: String) throws {
        let cloudStorage = TiCloudStorage(token: token)
        let replay = cloudStorage.createReplay()
        try runTiCloudStorageConcurrencyScenario(
            "lazy Replay creation/dispose race",
            operation: {
                try requireTiCloudStorageConcurrency(
                    cloudStorage.updateToken(token) == TiCloudStorageErrorCode.ok,
                    "lazy Replay parent Store creation failed")
                let results = try runTiCloudStorageConcurrentCalls(
                    { replay.setSpeed(.x2) },
                    replay.dispose
                )
                try requireTiCloudStorageCallDisposeResults(
                    call: results.0,
                    dispose: results.1,
                    operation: "lazy Replay creation/dispose race")
                try requireTiCloudStorageConcurrency(
                    retryTiCloudStorageInUse(replay.dispose) == TiCloudStorageErrorCode.ok,
                    "lazy Replay race did not reach release")
            },
            cleanup: {
                [
                    ("Replay dispose", retryTiCloudStorageInUse(replay.dispose)),
                    ("store dispose", retryTiCloudStorageInUse(cloudStorage.dispose)),
                ]
            })
    }

    @MainActor
    private func verifyTiCloudStorageChildAndAttachmentLifetime(
        token: String,
        videoChannel: UInt8,
        statusLog: String
    ) throws {
        let cloudStorage = TiCloudStorage(token: token)
        let replay = cloudStorage.createReplay()
        let videoOutput = TiCloudStorageVideoOutput()
        try runTiCloudStorageConcurrencyScenario(
            "parent/child and attachment lifetime",
            operation: {
                try requireTiCloudStorageConcurrency(
                    cloudStorage.updateToken(token) == TiCloudStorageErrorCode.ok,
                    "parent Store creation failed")
                try requireTiCloudStorageConcurrency(
                    replay.setSpeed(.x2) == TiCloudStorageErrorCode.ok,
                    "child Replay creation failed")
                try requireTiCloudStorageConcurrency(
                    cloudStorage.dispose() == TiCloudStorageErrorCode.inUse,
                    "parent Store dispose did not reject a live Replay child")
                try requireTiCloudStorageConcurrency(
                    cloudStorage.updateToken(token) == TiCloudStorageErrorCode.ok,
                    "parent Store was not reusable after rejected parent dispose")
                try requireTiCloudStorageConcurrency(
                    replay.setSpeed(.x4) == TiCloudStorageErrorCode.ok,
                    "Replay was not reusable after rejected parent dispose")

                try requireTiCloudStorageConcurrency(
                    videoOutput.attach(replay: replay, channelId: videoChannel)
                        == TiCloudStorageErrorCode.ok,
                    "video output attachment failed")
                try requireTiCloudStorageConcurrency(
                    replay.dispose() == TiCloudStorageErrorCode.inUse,
                    "Replay dispose did not reject a live attachment")
                try requireTiCloudStorageConcurrency(
                    replay.setSpeed(.x1) == TiCloudStorageErrorCode.ok,
                    "Replay was not reusable after rejected attached dispose")
                try requireTiCloudStorageConcurrency(
                    videoOutput.dispose() == TiCloudStorageErrorCode.inUse,
                    "video output dispose did not reject a live attachment")
                try requireTiCloudStorageConcurrency(
                    videoOutput.detach() == TiCloudStorageErrorCode.ok,
                    "video output detach failed")
                try requireTiCloudStorageConcurrency(
                    videoOutput.dispose() == TiCloudStorageErrorCode.ok,
                    "video output did not release after detach")
                try requireTiCloudStorageConcurrency(
                    replay.dispose() == TiCloudStorageErrorCode.ok,
                    "Replay did not release after detaching its output")
                try requireTiCloudStorageConcurrency(
                    cloudStorage.updateToken(token) == TiCloudStorageErrorCode.ok,
                    "parent Store was not reusable after child release")
                try requireTiCloudStorageConcurrency(
                    cloudStorage.dispose() == TiCloudStorageErrorCode.ok,
                    "parent Store did not reach final release")
            },
            cleanup: {
                var results: [(String, Int32)] = []
                results.append(("video detach", videoOutput.detach()))
                results.append(
                    ("video dispose", retryTiCloudStorageInUse(videoOutput.dispose)))
                results.append(("Replay dispose", retryTiCloudStorageInUse(replay.dispose)))
                results.append(("store dispose", retryTiCloudStorageInUse(cloudStorage.dispose)))
                return results
            })
        Self.appendStatus(
            statusLog, "ti-cloud-storage-sdk-concurrency-parent-child-reuse-verified")
        Self.appendStatus(
            statusLog, "ti-cloud-storage-sdk-concurrency-attachment-reuse-release-verified")
    }

    @MainActor
    private func runTiCloudStorageConcurrencyScenario(
        _ name: String,
        operation: () throws -> Void,
        cleanup: () -> [(String, Int32)]
    ) throws {
        var operationError: Error?
        do {
            try operation()
        } catch {
            operationError = error
        }

        let cleanupFailures = cleanup().compactMap { operation, code in
            [TiCloudStorageErrorCode.ok, TiCloudStorageErrorCode.notInitialized].contains(code)
                ? nil : "\(operation)=\(code)"
        }
        if !cleanupFailures.isEmpty {
            let message = "\(name) cleanup failed: \(cleanupFailures.joined(separator: ", "))"
            if operationError != nil { XCTFail(message) }
            if operationError == nil {
                throw NSError(
                    domain: "TiCloudStoragePublicSdkConcurrencyCleanup",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: message])
            }
        }
        if let operationError { throw operationError }
    }

    private func requireTiCloudStorageCallDisposeResults(
        call: Int32,
        dispose: Int32,
        operation: String
    ) throws {
        try requireTiCloudStorageConcurrency(
            [
                TiCloudStorageErrorCode.ok,
                TiCloudStorageErrorCode.inUse,
                TiCloudStorageErrorCode.notInitialized,
            ].contains(call),
            "\(operation) returned unexpected call result: \(call)")
        try requireTiCloudStorageConcurrency(
            [TiCloudStorageErrorCode.ok, TiCloudStorageErrorCode.inUse].contains(dispose),
            "\(operation) returned unexpected dispose result: \(dispose)")
        if dispose == TiCloudStorageErrorCode.inUse {
            try requireTiCloudStorageConcurrency(
                call == TiCloudStorageErrorCode.ok,
                "\(operation) returned inUse from dispose without a successful call")
        }
        if call == TiCloudStorageErrorCode.inUse
            || call == TiCloudStorageErrorCode.notInitialized
        {
            try requireTiCloudStorageConcurrency(
                dispose == TiCloudStorageErrorCode.ok,
                "\(operation) rejected the call without completing dispose")
        }
    }

    private func requireTiCloudStorageConcurrency(_ condition: Bool, _ message: String) throws {
        guard condition else {
            throw NSError(
                domain: "TiCloudStoragePublicSdkConcurrency",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private func runTiCloudStorageConcurrentCalls(
        _ left: @escaping () -> Int32,
        _ right: @escaping () -> Int32
    ) throws -> (Int32, Int32) {
        let ready = DispatchSemaphore(value: 0)
        let start = DispatchSemaphore(value: 0)
        let completed = DispatchGroup()
        let results = TiCloudStorageConcurrentResults()
        let actions = [TiCloudStorageConcurrentAction(left), TiCloudStorageConcurrentAction(right)]

        for (index, action) in actions.enumerated() {
            completed.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer { completed.leave() }
                ready.signal()
                guard start.wait(timeout: .now() + .seconds(2)) == .success else { return }
                results.set(action.body(), at: index)
            }
        }
        let bothReady =
            ready.wait(timeout: .now() + .seconds(2)) == .success
            && ready.wait(timeout: .now() + .seconds(2)) == .success
        start.signal()
        start.signal()
        let bothCompleted = completed.wait(timeout: .now() + .seconds(5)) == .success
        guard bothReady, bothCompleted, let values = results.values() else {
            throw NSError(
                domain: "TiCloudStoragePublicSdkConcurrency",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey: "bounded synchronized dispose did not complete"
                ])
        }
        return values
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
                for button in alert.buttons.allElementsBoundByIndex
                where Self.isAllowPermissionLabel(button.label) {
                    button.tap()
                    Self.appendStatusFromEnvironment(
                        "system_permission_allowed title=\(button.label)")
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
            let banner = springBoard.descendants(matching: .any)["NotificationShortLookView"]
                .firstMatch
            guard banner.waitForExistence(timeout: 0.2) else {
                return false
            }
            if banner.isHittable {
                banner.swipeUp()
            } else {
                let start = springBoard.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
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
            let userNotifications = XCUIApplication(
                bundleIdentifier: "com.apple.UserNotificationCenter")
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
        for button in element.buttons.allElementsBoundByIndex
        where Self.isAllowPermissionLabel(button.label) {
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
        scrollIntoView(app, element)
        tapElement(element)
    }

    @MainActor
    private func scrollIntoView(_ app: XCUIApplication, _ element: XCUIElement) {
        #if os(iOS)
            for _ in 0..<6 where element.exists && !element.isHittable {
                let scrollView = app.scrollViews.firstMatch
                let surface = scrollView.exists ? scrollView : app
                if element.frame.midY < app.frame.midY {
                    surface.swipeDown()
                } else {
                    surface.swipeUp()
                }
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            }
        #else
            _ = app
            _ = element
        #endif
    }

    @MainActor
    private func tapCloudSecondaryAction(_ app: XCUIApplication, identifier: String) {
        let target = app.descendants(matching: .any)[identifier].firstMatch
        if !target.exists {
            XCTAssertTrue(
                tapUntilVisible(
                    app,
                    sourceIdentifier: "cloudStorage.more",
                    targetIdentifier: identifier,
                    attempts: 3
                ),
                "cloud secondary action did not become visible: \(identifier)"
            )
        }
        tap(app, identifier)
    }

    @MainActor
    private func tapCloudHeaderAction(_ app: XCUIApplication, identifier: String) {
        let target = app.descendants(matching: .any)[identifier].firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 8.0), "missing cloud header action \(identifier)")
        for _ in 0..<4 {
            handleSystemPermissionDialogs(app, attempts: 1)
            _ = dismissIOSNotificationBanner()
            if app.state != .runningForeground {
                app.activate()
            }
            if target.isHittable {
                target.press(forDuration: 0.1)
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTFail("cloud header action was not hittable: \(identifier)")
    }

    @MainActor
    private func dismissTransientMenu(
        _ app: XCUIApplication,
        anchorIdentifier: String,
        menuItemIdentifier: String
    ) -> Bool {
        let anchor = app.descendants(matching: .any)[anchorIdentifier].firstMatch
        let menuItem = app.descendants(matching: .any)[menuItemIdentifier].firstMatch
        guard anchor.waitForExistence(timeout: 2.0) else { return false }
        anchor.tap()
        return waitForElementToDisappear(menuItem, timeout: 2.0)
    }

    private func waitForElementToDisappear(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter.wait(for: [dismissed], timeout: timeout) == .completed
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
        scrollIntoView(app, element)
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
    private func replaceListValues(
        _ app: XCUIApplication,
        prefix: String,
        values: [String]
    ) throws {
        for (index, value) in values.prefix(3).enumerated() {
            let identifier = "\(prefix).\(index)"
            if !app.descendants(matching: .any)[identifier].exists {
                tap(app, "\(prefix).add")
            }
            try replaceText(app, identifier, value)
        }
    }

    private func csvValues(_ value: String) -> [String] {
        value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter {
                !$0.isEmpty
            }
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
    private func waitForVideoStage(
        _ app: XCUIApplication,
        streamId: String,
        statusLog: String,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if Self.waitForFile(
                statusLog, containing: "video stream_id=\(streamId) ", timeout: 0.05)
            {
                return true
            }
            let stages = app.descendants(matching: .any).matching(identifier: "client.video.stage")
            if stages.allElementsBoundByIndex.contains(where: {
                $0.label.contains("ID \(streamId)")
                    && (($0.value as? String)?.contains("rendering") == true)
            }) {
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
            for pattern in patterns
            where Self.waitForFile(statusLog, containing: pattern, timeout: 0.05) {
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
    private func waitForClientDiagnosticsData(_ app: XCUIApplication, timeout: TimeInterval)
        -> String?
    {
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
            if app.staticTexts.allElementsBoundByIndex.contains(where: {
                $0.label.contains(historyPattern)
            }) {
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
            && text.range(
                of: #"[1-9][0-9]*(\.[0-9]+)?|0\.[0-9]*[1-9]"#, options: .regularExpression)
                != nil
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
        let embedded = try Self.decodeAppEnvironment(
            ExampleUITestHarnessConfig.embeddedEnvironmentJSON)
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

    private static func waitForFile(
        _ path: String, containing pattern: String, timeout: TimeInterval
    )
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

    private static func latestFileLine(_ path: String, containing pattern: String) -> String? {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        return text.split(whereSeparator: \.isNewline).last(where: { $0.contains(pattern) }).map(
            String.init)
    }

    private static func appendStatus(_ path: String, _ message: String) {
        print("[XCUITest] \(message)")
        guard !path.isEmpty, let data = "\(message)\n".data(using: .utf8) else {
            return
        }
        let url = URL(fileURLWithPath: path)
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            _ = try? handle.write(contentsOf: data)
        }
    }

    private static func rawDumpEvidenceMarker(
        event: String, archive: TiRawDumpArchive, code: Int32? = nil, logId: String? = nil
    ) -> String {
        var payload: [String: Any] = [
            "capture_id": archive.captureId,
            "archive_sha256": archive.sha256,
            "archive_path": archive.path,
        ]
        if let code { payload["code"] = code }
        if let logId { payload["log_id"] = logId }
        let data = try! JSONSerialization.data(withJSONObject: payload)
        let encoded = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "raw_dump_evidence_\(event)_b64=\(encoded)"
    }
}
