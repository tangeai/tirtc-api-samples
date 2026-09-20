import UIKit
import XCTest

private let shortTimeout: TimeInterval = 30
private let launchTimeout: TimeInterval = 40
private let connectTimeout: TimeInterval = 180
private let keyboardDismissTimeout: TimeInterval = 3
private let keyboardDismissPollInterval: TimeInterval = 0.2
private let controlledTextInputKeystrokeDelay: TimeInterval = 0.05
private let controlledTextInputChunkSize = 8
private let stressLoopBehaviorBudget: TimeInterval = 60
private let videoFrameMinimumVisiblePercent = 5
private let videoFrameBrightLumaThreshold = 62
private let videoFrameChromaticLumaThreshold = 45
private let videoFrameChromaticSpreadThreshold = 20
private let videoFrameMinimumChangedPercent = 5
private let videoFrameChannelDeltaThreshold = 12
private let backgroundRecoveryWindow: TimeInterval = 10
private let foregroundRecoveryTimeout: TimeInterval = 60

final class ExamplePublicUiSmokeTests: XCTestCase {
  private let cloudStoragePublicSdkLifecycleMarker =
    "ti-cloud-storage-sdk-overlap-inuse-reuse-teardown-v2"
  private let cloudStoragePublicSdkLifecycleFacts = [
    "ti-cloud-storage-sdk-store-async-dispose-inuse-reuse",
    "ti-cloud-storage-sdk-replay-async-control-dispose-inuse-reuse",
    "ti-cloud-storage-sdk-lazy-create-use-dispose-inuse-reuse",
    "ti-cloud-storage-sdk-parent-child-attachment-inuse-reuse",
    "ti-cloud-storage-sdk-final-release-shutdown",
  ]
  private var app: XCUIApplication!

  override func setUpWithError() throws {
    continueAfterFailure = false
    app = XCUIApplication()
    if name.contains("testInputMediaCase") {
      app.resetAuthorizationStatus(for: .camera)
    }
    addUIInterruptionMonitor(withDescription: "System Permission") { alert in
      return self.tapPreferredSystemButton(in: alert)
    }
  }

  func testPublicUiFlow() throws {
    app.launch()
    dismissSystemAlertsIfPresent()
    app.tap()
    dismissSystemAlertsIfPresent()
    waitForControl("TiRTC Config appId", timeout: launchTimeout)

    switch env("TIRTC_RN_FLOW", defaultValue: "downlink") {
    case "ti-cloud-storage":
      try runCloudStorageFlow()
    case "stress":
      fillCommonConfig()
      runStressFlow()
    default:
      verifyAuxiliaryUiContract()
      fillCommonConfig()
      runDownlinkFlow()
    }
  }

  func testTiCloudStoragePublicSdkCase() throws {
    app.launch()
    dismissSystemAlertsIfPresent()
    app.tap()
    dismissSystemAlertsIfPresent()
    let deadline = Date().addingTimeInterval(900)
    while Date() < deadline {
      if app.state != .runningForeground {
        attachScreenshot(name: "ti-cloud-storage-sdk-case-app-exited")
        XCTFail("Ti Cloud Storage SDK Case app exited before a terminal result")
        return
      }
      if labelContains("Ti Cloud Storage SDK Case Failed") {
        attachScreenshot(name: "ti-cloud-storage-sdk-case-failed")
        XCTFail("Ti Cloud Storage public SDK Case reported failure")
        return
      }
      if labelContains("Ti Cloud Storage SDK Case Passed") {
        guard labelContains("marker=\(cloudStoragePublicSdkLifecycleMarker)") else {
          XCTFail("Ti Cloud Storage public SDK Case omitted its lifecycle marker")
          return
        }
        for fact in cloudStoragePublicSdkLifecycleFacts {
          guard labelContains(fact) else {
            XCTFail("Ti Cloud Storage public SDK Case omitted lifecycle fact \(fact)")
            return
          }
          marker(fact)
        }
        marker(cloudStoragePublicSdkLifecycleMarker)
        marker("ti-cloud-storage-sdk-case-completed")
        return
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    }
    attachScreenshot(name: "ti-cloud-storage-sdk-case-timeout")
    XCTFail("timed out waiting for Ti Cloud Storage public SDK Case")
  }

  func testInputMediaCase() throws {
    app.launch()
    let deadline = Date().addingTimeInterval(90)
    while Date() < deadline {
      dismissSystemAlertsIfPresent()
      if labelContains("Input Media Case Failed") {
        attachScreenshot(name: "input-media-failed")
        XCTFail("input media fixture failed")
        return
      }
      if labelContains("Input Media Case Passed") {
        if labelContains("camera unavailable 6110") { marker("input-media-camera-unavailable") }
        marker("input-media-completed")
        return
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.25))
    }
    attachScreenshot(name: "input-media-timeout")
    XCTFail("input media fixture timed out")
  }

  private func runCloudStorageFlow() throws {
    let startTimeMs = env("TI_CLOUD_STORAGE_START_TIME_MS")
    guard !startTimeMs.isEmpty else {
      XCTFail("missing Ti Cloud Storage start time")
      return
    }
    tapControl("云录像")
    setField("Ti Cloud Storage Config appId", value: env("TI_CLOUD_STORAGE_APP_ID"))
    setField("Ti Cloud Storage Config endpoint", value: env("TI_CLOUD_STORAGE_ENDPOINT"))
    setField(
      "Ti Cloud Storage Config token",
      value: env("TI_CLOUD_STORAGE_TOKEN_URL"))
    assertSensitiveFieldValue(
      field: "Ti Cloud Storage Config token",
      expected: env("TI_CLOUD_STORAGE_TOKEN_URL"),
      show: "Ti Cloud Storage Config Show Token",
      hide: "Ti Cloud Storage Config Hide Token")
    setField(
      "Ti Cloud Storage Config audioId",
      value: env("TI_CLOUD_STORAGE_AUDIO_CHANNEL_ID", defaultValue: "10"))
    let videoChannelIds = csvValues(
      env(
        "TI_CLOUD_STORAGE_VIDEO_CHANNEL_IDS",
        defaultValue:
          env("TI_CLOUD_STORAGE_VIDEO_CHANNEL_ID", defaultValue: "11")))
    setVideoFields(prefix: "Ti Cloud Storage Config", values: videoChannelIds)
    marker("ti-cloud-storage-config-filled")
    verifyCloudStorageUiGate("configure", startTimeMs: startTimeMs, videoChannelIds: videoChannelIds)
    tapControl("Ti Cloud Storage Open")
    verifyVisibleRecordingsState(state: "populated", text: "录像已加载", timeout: connectTimeout)
    verifyCloudStorageUiGate("sheet", startTimeMs: startTimeMs, videoChannelIds: videoChannelIds)
    tapControl("Ti Cloud Storage Play \(startTimeMs)")
    waitForText("正在播放", timeout: connectTimeout)
    marker("ti-cloud-storage-rendering-ok")
    let videoDeadline = Date().addingTimeInterval(connectTimeout)
    while Date() < videoDeadline && !hasVisibleVideoFrame() {
      RunLoop.current.run(until: Date().addingTimeInterval(0.75))
    }
    XCTAssertTrue(hasVisibleVideoFrame(), "Ti Cloud Storage video frame was not visible")
    for channelId in videoChannelIds {
      _ = waitForControl("Video Channel \(channelId)", timeout: shortTimeout)
    }
    verifyMosaicSelection(videoChannelIds.map { "Video Channel \($0)" })
    attachScreenshot(name: "ti-cloud-storage-visible-video")
    marker("ti-cloud-storage-visible-video-ok")
    verifyCloudStorageUiGate("playback", startTimeMs: startTimeMs, videoChannelIds: videoChannelIds)

    tapControl("Ti Cloud Storage Raw Dump")
    waitForText("正在抓取诊断数据", timeout: shortTimeout)
    RunLoop.current.run(until: Date().addingTimeInterval(10))
    tapControl("Ti Cloud Storage Raw Dump")
    waitForLogUpload(role: "ti-cloud-storage")
    marker("ti-cloud-storage-raw-dump-upload-ok")

    RunLoop.current.run(until: Date().addingTimeInterval(5))
    tapControl("Ti Cloud Storage Pause Resume")
    waitForText("已暂停", timeout: shortTimeout)
    marker("ti-cloud-storage-pause-ok")
    RunLoop.current.run(until: Date().addingTimeInterval(3))
    tapControl("Ti Cloud Storage Pause Resume")
    waitForText("继续播放", timeout: shortTimeout)
    marker("ti-cloud-storage-resume-ok")

    tapControl("Ti Cloud Storage Mute")
    waitForText("已静音", timeout: shortTimeout)
    marker("ti-cloud-storage-mute-ok")
    RunLoop.current.run(until: Date().addingTimeInterval(2))
    tapControl("Ti Cloud Storage Mute")
    waitForText("已恢复声音", timeout: shortTimeout)
    marker("ti-cloud-storage-unmute-ok")

    for _ in 0..<6 { tapControl("Ti Cloud Storage Speed") }
    waitForText("播放倍速：1/2×", timeout: shortTimeout)
    marker("ti-cloud-storage-speed-x0_5-ok")
    RunLoop.current.run(until: Date().addingTimeInterval(3))
    tapControl("Ti Cloud Storage Speed")
    waitForText("播放倍速：1×", timeout: shortTimeout)
    marker("ti-cloud-storage-speed-x1-ok")

    let seek = waitForControl("Ti Cloud Storage Seek", timeout: shortTimeout)
    seek.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.5)).tap()
    waitForText("已跳转", timeout: shortTimeout)
    marker("ti-cloud-storage-seek-ok")
    RunLoop.current.run(until: Date().addingTimeInterval(3))

    verifyMenuCancellation("Ti Cloud Storage More")
    tapMenuAction(menu: "Ti Cloud Storage More", action: "Ti Cloud Storage Snapshot")
    waitForText("截图完成", timeout: shortTimeout)
    marker("ti-cloud-storage-snapshot-ok")
    tapMenuAction(menu: "Ti Cloud Storage More", action: "Ti Cloud Storage Save Gallery", dismissSystemAlertsAfterTap: false)
    dismissSystemAlertsIfPresent()
    waitForText("已保存到系统相册", timeout: shortTimeout)
    marker("ti-cloud-storage-snapshot-gallery-ok")

    tapMenuAction(menu: "Ti Cloud Storage More", action: "Ti Cloud Storage Recording")
    waitForText("边播边录已开始", timeout: shortTimeout)
    marker("ti-cloud-storage-recording-started-ok")
    RunLoop.current.run(until: Date().addingTimeInterval(7))
    tapMenuAction(menu: "Ti Cloud Storage More", action: "Ti Cloud Storage Recording")
    waitForText("边播边录完成", timeout: shortTimeout)
    marker("ti-cloud-storage-recording-completed-ok")
    tapMenuAction(menu: "Ti Cloud Storage More", action: "Ti Cloud Storage Save Gallery")
    waitForText("已保存到系统相册", timeout: shortTimeout)
    marker("ti-cloud-storage-recording-gallery-ok")

    tapControl("Ti Cloud Storage Recordings")
    tapControl("Ti Cloud Storage Export \(startTimeMs)")
    verifyVisibleRecordingsState(state: "export-busy", text: "正在下载录像", timeout: shortTimeout)
    tapControl("Ti Cloud Storage Close Recordings")
    waitForText("范围下载完成", timeout: 240)
    marker("ti-cloud-storage-export-completed-ok")
    tapMenuAction(menu: "Ti Cloud Storage More", action: "Ti Cloud Storage Save Gallery")
    waitForText("已保存到系统相册", timeout: shortTimeout)
    marker("ti-cloud-storage-export-gallery-ok")

    tapControl("Ti Cloud Storage Recordings")
    tapControl("Ti Cloud Storage Play \(startTimeMs)")
    waitForText("正在播放", timeout: connectTimeout)
    let replayDeadline = Date().addingTimeInterval(210)
    var outputCompleted = false
    while Date() < replayDeadline {
      XCTAssertFalse(labelContains("播放失败") || labelContains("回放失败") || labelContains("输出失败"))
      if labelContains("Ti Cloud Storage Status: 播放完成") {
        outputCompleted = true
        break
      }
      XCTAssertFalse(labelContains("缓冲中"), "Ti Cloud Storage replay buffered after rendering")
      RunLoop.current.run(until: Date().addingTimeInterval(1))
    }
    XCTAssertTrue(outputCompleted, "Ti Cloud Storage replay did not reach Output completion")
    marker("ti-cloud-storage-continuous-playback-ok terminal=output_completed")

    tapControl("Ti Cloud Storage Back")
    waitForControl("Ti Cloud Storage Open", timeout: shortTimeout)
    marker("ti-cloud-storage-returned-to-configure")
    verifyCloudStorageUiGate("entry", startTimeMs: startTimeMs, videoChannelIds: videoChannelIds)
    marker("ti-cloud-storage-public-ui-done")
  }

  private func runDownlinkFlow() {
    tapStartDownlink()
    marker("client_connect_clicked")
    waitPlayerOpened()
    waitClientDownlink()
    waitPlayerDiagnostics()
    runAudioOutputVolumeProbe()
    if !isSimulatorDownlinkOnly() {
      runTalkbackProbe()
      waitStreamMessageBubble()
      if isIntegrationLayer() {
        runBackgroundForegroundProbe(role: "client", expectedControl: "TiRTC Player Stop")
        waitClientDownlink(captureEvidence: false)
      }
      tapControl("TiRTC Player Raw Dump")
      waitForText("正在抓取诊断数据", timeout: shortTimeout)
      RunLoop.current.run(until: Date().addingTimeInterval(10))
      tapControl("TiRTC Player Raw Dump")
      marker("client_log_upload_clicked raw_dump=true")
      waitForLogUpload(role: "client")
      marker("client_raw_dump_upload_ok")
      verifyMenuCancellation("TiRTC Player More")
      tapMenuAction(menu: "TiRTC Player More", action: "TiRTC Player Send Command")
      tapControl("TiRTC Command Panel Cancel")
      XCTAssertTrue(waitForControl("TiRTC Player More", timeout: shortTimeout).hasFocus, "command cancel did not restore focus to More")
      tapMenuAction(menu: "TiRTC Player More", action: "TiRTC Player Send Command")
      tapControl("TiRTC Command Panel Echo Preset")
      tapControl("TiRTC Command Panel Send Command")
      tapControl("TiRTC Command Panel Close")
      XCTAssertTrue(waitForControl("TiRTC Player More", timeout: shortTimeout).hasFocus, "command close did not restore focus to More")
      marker("client_public_actions_clicked")
    }
    hold()
    tapControl("TiRTC Player Stop")
    waitForControl("TiRTC Config appId", timeout: shortTimeout)
    if isIntegrationLayer() {
      marker("teardown_mount_unmount_client_ok")
    }
    marker("client_downlink_done")
  }

  private func runStressFlow() {
    let loops = max(1, Int(env("TIRTC_RN_LOOPS", defaultValue: "2")) ?? 2)
    let loopOffset = max(0, Int(env("TIRTC_RN_LOOP_OFFSET", defaultValue: "0")) ?? 0)
    for localLoop in 1...loops {
      let loop = loopOffset + localLoop
      let behaviorStartedAt = Date()
      marker("stress_loop_\(loop)_start")
      tapStartDownlink()
      marker("stress_loop_\(loop)_downlink_clicked")
      waitPlayerOpened(captureEvidence: false)
      waitClientDownlink(captureEvidence: false)
      marker("stress_fabric_output_loop_\(loop)_ok")
      hold()
      tapControl("TiRTC Player Stop")
      waitForControl("TiRTC Config appId", timeout: shortTimeout)
      let behaviorDurationMs = Int(Date().timeIntervalSince(behaviorStartedAt) * 1000)
      if behaviorDurationMs > Int(stressLoopBehaviorBudget * 1000) {
        XCTFail("stress loop \(loop) exceeded the 60 second behavior budget")
        return
      }
      marker("stress_loop_\(loop)_behavior_ms=\(behaviorDurationMs)")
      marker("stress_loop_\(loop)_done")
      if localLoop < loops {
        sleep(2)
        marker("stress_loop_\(loop)_cooldown_done")
      }
    }
    marker("stress_loops_done")
    marker("stress_fabric_output_loops_done")
    marker("stress_loops_done_details count=\(loops) offset=\(loopOffset)")
  }

  private func fillCommonConfig() {
    setField("TiRTC Config appId", value: env("TIRTC_RN_APP_ID"))
    setField("TiRTC Config endpoint", value: env("TIRTC_RN_ENDPOINT"))
    setField("TiRTC Config remoteId", value: env("TIRTC_RN_REMOTE_ID"))
    setField(
      "TiRTC Config audioId", value: env("TIRTC_RN_AUDIO_STREAM_ID", defaultValue: "10"))
    setVideoFields(
      prefix: "TiRTC Config",
      values: csvValues(
        env(
          "TIRTC_RN_VIDEO_STREAM_IDS",
          defaultValue:
            env("TIRTC_RN_VIDEO_STREAM_ID", defaultValue: "11"))))
    setField("TiRTC Config token", value: env("TIRTC_RN_TOKEN"))
    assertSensitiveFieldValue(
      field: "TiRTC Config token",
      expected: env("TIRTC_RN_TOKEN"),
      show: "TiRTC Config Show Token",
      hide: "TiRTC Config Hide Token")
    marker("config_filled")
  }

  private func verifyAuxiliaryUiContract() {
    tapControl("TiRTC 偏好设置")
    _ = waitForControl("TiRTC Settings Video Decoder Preference", timeout: shortTimeout)
    _ = waitForControl("TiRTC Settings Local Audio Codec", timeout: shortTimeout)
    assertMinimumTarget("TiRTC Settings Back", minimum: 44)
    tapControl("TiRTC Settings Back")

    setField("TiRTC Config endpoint", value: "https://keep-rtc.example")
    setField("TiRTC Config appId", value: "keep-rtc-app")
    setField("TiRTC Config remoteId", value: "KEEPDEVICE")
    setField("TiRTC Config audioId", value: "70")
    tapControl("TiRTC QR Input")
    setField("TiRTC QR Manual Content", value: "invalid")
    tapControl("TiRTC QR Apply Content")
    waitForText("二维码内容无效", timeout: shortTimeout)
    setField("TiRTC QR Manual Content", value: #"{"app_id":"m4-rtc-app","remote_id":"M4DEVICE","token":"v1.m4-test","endpoint":"https://m4-rtc.example"}"#, verifyValue: false)
    tapControl("TiRTC QR Apply Content")
    _ = waitForControl("TiRTC Config appId", timeout: shortTimeout)
    XCTAssertTrue(waitForFieldValue("TiRTC Config appId", expected: "m4-rtc-app", sensitive: false))
    XCTAssertTrue(waitForFieldValue("TiRTC Config remoteId", expected: "M4DEVICE", sensitive: false))
    XCTAssertTrue(waitForFieldValue("TiRTC Config endpoint", expected: "https://m4-rtc.example", sensitive: false))
    assertSyntheticTokenValue(field: "TiRTC Config token", expected: "v1.m4-test", show: "TiRTC Config Show Token", hide: "TiRTC Config Hide Token")
    XCTAssertTrue(waitForFieldValue("TiRTC Config audioId", expected: "70", sensitive: false))

    tapControl("云录像")
    setField("Ti Cloud Storage Config appId", value: "keep-cloud-app")
    setField("Ti Cloud Storage Config endpoint", value: "https://keep-cloud.example")
    setField("Ti Cloud Storage Config audioId", value: "71")
    tapControl("Ti Cloud Storage QR Input")
    setField("Ti Cloud Storage QR Manual Content", value: "invalid value")
    tapControl("Ti Cloud Storage QR Apply Content")
    waitForText("二维码内容无效", timeout: shortTimeout)
    setField("Ti Cloud Storage QR Manual Content", value: #"{"app_id":"m4-cloud-app","token":"m4-cloud-token","endpoint":"https://m4-cloud.example"}"#, verifyValue: false)
    tapControl("Ti Cloud Storage QR Apply Content")
    _ = waitForControl("Ti Cloud Storage Config appId", timeout: shortTimeout)
    XCTAssertTrue(waitForFieldValue("Ti Cloud Storage Config appId", expected: "m4-cloud-app", sensitive: false))
    XCTAssertTrue(waitForFieldValue("Ti Cloud Storage Config endpoint", expected: "https://m4-cloud.example", sensitive: false))
    assertSyntheticTokenValue(field: "Ti Cloud Storage Config token", expected: "m4-cloud-token", show: "Ti Cloud Storage Config Show Token", hide: "Ti Cloud Storage Config Hide Token")
    XCTAssertTrue(waitForFieldValue("Ti Cloud Storage Config audioId", expected: "71", sensitive: false))
    tapControl("RTC")
    marker("auxiliary_ui_contract_ok")
  }

  private func verifyVisibleRecordingsState(state: String, text: String, timeout: TimeInterval) {
    let node = waitForControl("Ti Cloud Storage Recordings State \(state): \(text)", timeout: timeout)
    XCTAssertFalse(node.frame.isEmpty, "recordings state \(state) has no visible bounds")
    waitForText(text, timeout: timeout)
  }

  private func verifyCloudStorageUiGate(
    _ name: String, startTimeMs: String, videoChannelIds: [String]
  ) {
    switch name {
    case "configure":
      XCTAssertFalse(
        waitForControl("Ti Cloud Storage Open", timeout: shortTimeout).frame.isEmpty,
        "Ti Cloud Storage configure entry is not visible")
      _ = waitForControl("Ti Cloud Storage Config audioId", timeout: shortTimeout)
      for index in videoChannelIds.indices {
        _ = waitForControl("Ti Cloud Storage Config videoId \(index + 1)", timeout: shortTimeout)
      }
    case "sheet":
      XCTAssertFalse(
        waitForControl("Ti Cloud Storage Recordings Sheet", timeout: shortTimeout).frame.isEmpty,
        "Ti Cloud Storage recordings sheet is not visible")
      XCTAssertFalse(
        waitForControl("Ti Cloud Storage Sheet Handle", timeout: shortTimeout).frame.isEmpty,
        "Ti Cloud Storage sheet handle is not visible")
      XCTAssertFalse(
        waitForControl("Ti Cloud Storage Play \(startTimeMs)", timeout: shortTimeout).frame.isEmpty,
        "Ti Cloud Storage newest recording is not visible")
    case "playback":
      let lanes = videoChannelIds.map {
        waitForControl("Video Channel \($0)", timeout: shortTimeout)
      }
      XCTAssertEqual(lanes.count, videoChannelIds.count, "Ti Cloud Storage playback lanes are missing")
      let stage = lanes.dropFirst().reduce(lanes[0].frame) { $0.union($1.frame) }
      let appFrame = app.frame
      XCTAssertGreaterThanOrEqual(
        stage.width / appFrame.width, 0.6,
        "Ti Cloud Storage video stage is squeezed horizontally")
      XCTAssertGreaterThanOrEqual(
        stage.height / appFrame.height, 0.35,
        "Ti Cloud Storage video stage is squeezed vertically")
      XCTAssertFalse(
        waitForControl("Ti Cloud Storage Pause Resume", timeout: shortTimeout).frame.isEmpty,
        "Ti Cloud Storage playback controls are not visible")
    case "entry":
      XCTAssertFalse(
        waitForControl("Ti Cloud Storage Open", timeout: shortTimeout).frame.isEmpty,
        "Ti Cloud Storage entry page is not visible after back navigation")
    default:
      XCTFail("unknown Ti Cloud Storage UI gate \(name)")
      return
    }
    attachScreenshot(name: "ti-cloud-storage-ui-\(name)")
    marker("ti-cloud-storage-ui-gate-\(name)")
  }

  private func runTalkbackProbe() {
    tapControl("TiRTC Player Start Talkback", dismissSystemAlertsAfterTap: false)
    waitAndAllowSystemPermission(stage: "talkback")
    waitForTalkbackPermissionReturn()
    marker("talkback_permission_returned")
    tapControl("TiRTC Player Start Talkback")
    waitForTalkbackRunning()
    marker("talkback_start_ok")
    tapControl("TiRTC Player Stop Talkback")
    waitForTalkbackStopped()
    marker("talkback_stop_ok")
    tapControl("TiRTC Player Start Talkback")
    waitForTalkbackRunning()
    tapControl("TiRTC Player Stop Talkback")
    waitForTalkbackStopped()
    marker("talkback_restart_ok")
  }

  private func runAudioOutputVolumeProbe() {
    tapControl("TiRTC Downlink Metrics Collapse")
    let videoTiles = currentVideoTiles()
    guard let beforeMute = videoFrameSignatures(in: videoTiles) else {
      attachScreenshot(name: "audio-output-before-mute-frame-missing")
      XCTFail("downlink video was not visible before muting audio output")
      return
    }
    tapControl("TiRTC Player Mute Audio")
    waitForControl("TiRTC Player Restore Audio", timeout: shortTimeout)
    let muteStartedAt = Date()
    RunLoop.current.run(until: muteStartedAt.addingTimeInterval(5.5))
    guard
      isPlayerScreenVisible(),
      let afterMute = videoFrameSignatures(in: videoTiles),
      videoFramesAdvanced(from: beforeMute, to: afterMute)
    else {
      attachScreenshot(name: "audio-output-muted-continuity-failed")
      XCTFail("each downlink video did not advance while audio output was muted")
      return
    }
    attachScreenshot(name: "audio-output-muted-continuity")
    tapControl("TiRTC Player Restore Audio")
    waitForControl("TiRTC Player Mute Audio", timeout: shortTimeout)
    tapControl("TiRTC Downlink Metrics Expand")
    waitClientDownlink(captureEvidence: false)
    marker("audio_output_volume_cycle_ok")
    marker(
      "audio_output_volume_cycle_details mute_hold_ms=\(Int(Date().timeIntervalSince(muteStartedAt) * 1000))"
    )
  }

  private func isIntegrationLayer() -> Bool {
    env("TIRTC_RN_LAYER", defaultValue: "") == "integration"
  }

  private func isSimulatorDownlinkOnly() -> Bool {
    env("TIRTC_RN_DOWNLINK_ONLY", defaultValue: "0") == "1"
  }

  private func runBackgroundForegroundProbe(role: String, expectedControl: String) {
    marker("background_foreground_\(role)_start")
    XCUIDevice.shared.press(.home)
    RunLoop.current.run(until: Date().addingTimeInterval(backgroundRecoveryWindow))
    app.activate()
    dismissSystemAlertsIfPresent()
    app.tap()
    waitForControl(expectedControl, timeout: foregroundRecoveryTimeout)
    marker("background_foreground_\(role)_ok")
  }

  private func waitClientDownlink(captureEvidence: Bool = true) {
    if failForVisibleClientStartupError(captureEvidence: captureEvidence) {
      return
    }
    let streamIds = csvValues(
      env(
        "TIRTC_RN_VIDEO_STREAM_IDS",
        defaultValue:
          env("TIRTC_RN_VIDEO_STREAM_ID", defaultValue: "11")))
    let videoTiles = streamIds.map {
      waitForControl("Video Stream \($0)", timeout: shortTimeout)
    }
    verifyMosaicSelection(streamIds.map { "Video Stream \($0)" })
    if app.buttons["TiRTC Downlink Metrics Collapse"].exists {
      tapControl("TiRTC Downlink Metrics Collapse")
    }
    let deadline = Date().addingTimeInterval(connectTimeout)
    var previousSignatures: [[UInt8]]?
    while Date() < deadline {
      if failForVisibleClientStartupError(captureEvidence: captureEvidence) {
        return
      }
      if failForVisibleVideoPlaybackError(in: videoTiles, captureEvidence: captureEvidence) {
        return
      }
      if isPlayerScreenVisible(), let signatures = videoFrameSignatures(in: videoTiles) {
        if let previousSignatures,
          videoFramesAdvanced(from: previousSignatures, to: signatures)
        {
          let renderedTiles = currentVideoTiles()
          XCTAssertEqual(renderedTiles.count, streamIds.count)
          XCTAssertTrue(
            renderedTiles.allSatisfy { ($0.value as? String)?.contains("播放中") == true },
            "video lane accessibility status must report rendering after frames advance"
          )
          marker("client_downlink_video_accessibility_rendering_ok")
          if captureEvidence {
            attachScreenshot(name: "downlink-video")
          }
          marker("client_downlink_video_progress_ok")
          marker("client_downlink_video_frame_ok")
          tapControl("TiRTC Downlink Metrics Expand")
          return
        }
        previousSignatures = signatures
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.75))
    }
    attachScreenshot(name: "client-downlink-timeout")
    XCTFail("timed out waiting for client downlink")
  }

  private func waitPlayerOpened(captureEvidence: Bool = true) {
    let deadline = Date().addingTimeInterval(shortTimeout)
    while Date() < deadline {
      if failForVisibleClientStartupError(captureEvidence: captureEvidence) {
        return
      }
      if isPlayerScreenVisible() {
        marker("client_player_opened")
        return
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    }
    if captureEvidence {
      attachScreenshot(name: "client-player-not-opened")
    }
    XCTFail("client player did not open")
  }

  @discardableResult
  private func failForVisibleClientStartupError(captureEvidence: Bool) -> Bool {
    let failureTexts = ["Token 校验失败", "播放准备失败", "播放启动失败", "连接失败", "订阅失败"]
    let status = app.staticTexts["tirtc-player-status"]
    guard status.exists,
      let detail = status.value as? String,
      failureTexts.contains(where: { detail.contains($0) })
    else {
      return false
    }
    if captureEvidence {
      attachScreenshot(name: "client-player-open-failed")
    }
    XCTFail("client player open failed: \(detail)")
    return true
  }

  @discardableResult
  private func failForVisibleVideoPlaybackError(
    in videoTiles: [XCUIElement], captureEvidence: Bool
  ) -> Bool {
    let detail = videoTiles.compactMap { $0.value as? String }
      .first(where: { $0.contains("播放失败 · error") })
    guard let detail else {
      return false
    }
    if captureEvidence {
      attachScreenshot(name: "client-video-playback-failed")
    }
    XCTFail("client video playback failed: \(detail)")
    return true
  }

  private func tapStartDownlink() {
    tapControl("TiRTC Start Downlink")
    let deadline = Date().addingTimeInterval(shortTimeout)
    while Date() < deadline {
      dismissLogBoxIfPresent()
      dismissSystemAlertsIfPresent()
      if !isConfigureScreenVisible() || labelContains("Token 校验中") || labelContains("初始化中")
        || labelContains("Token 校验失败") || labelContains("播放启动失败")
      {
        return
      }
      let startButton = app.buttons["TiRTC Start Downlink"]
      if startButton.exists {
        startButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
      } else {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.70)).tap()
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.75))
    }
    attachScreenshot(name: "start-downlink-not-accepted")
    XCTFail("start downlink tap was not accepted")
  }

  private func isPlayerScreenVisible() -> Bool {
    return app.buttons["TiRTC Player Stop"].exists
      || app.buttons["TiRTC Player Upload Logs"].exists
      || app.staticTexts["tirtc-player-status"].exists
  }

  private func isConfigureScreenVisible() -> Bool {
    app.textFields["TiRTC Config endpoint"].isHittable
      || app.textFields["TiRTC Config appId"].isHittable
      || app.buttons["TiRTC Start Downlink"].isHittable
  }

  private func waitStreamMessageBubble() {
    let deadline = Date().addingTimeInterval(shortTimeout)
    while Date() < deadline {
      if hasStreamMessageBubble() {
        marker("client_stream_message_bubble_ok")
        return
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.75))
    }
    attachScreenshot(name: "stream-message-timeout")
    XCTFail("timed out waiting for stream message bubble")
  }

  private func waitForTalkbackRunning() {
    let deadline = Date().addingTimeInterval(shortTimeout)
    while Date() < deadline {
      if app.buttons["TiRTC Player Stop Talkback"].exists {
        return
      }
      if labelContains("麦克风配置失败") || labelContains("麦克风绑定失败") || labelContains("麦克风启动失败") {
        attachScreenshot(name: "talkback-start-failed")
        XCTFail("talkback failed to start")
        return
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    }
    attachScreenshot(name: "talkback-start-timeout")
    XCTFail("timed out waiting for talkback start")
  }

  private func waitForTalkbackPermissionReturn() {
    let startButton = app.buttons["TiRTC Player Start Talkback"]
    let stopButton = app.buttons["TiRTC Player Stop Talkback"]
    let deadline = Date().addingTimeInterval(shortTimeout)
    while Date() < deadline {
      if startButton.exists && startButton.isHittable && startButton.isEnabled && !stopButton.exists
      {
        return
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.25))
    }
    attachScreenshot(name: "talkback-permission-return-timeout")
    XCTFail("talkback did not return to the start state after permission grant")
  }

  private func waitForTalkbackStopped() {
    let deadline = Date().addingTimeInterval(shortTimeout)
    while Date() < deadline {
      if app.buttons["TiRTC Player Start Talkback"].exists {
        return
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    }
    attachScreenshot(name: "talkback-stop-timeout")
    XCTFail("timed out waiting for talkback stop")
  }

  private func waitPlayerDiagnostics() {
    if !app.descendants(matching: .any)["TiRTC Player Diagnostics"].exists {
      tapControl("TiRTC Downlink Metrics Expand")
    }
    waitDiagnostics(
      label: "TiRTC Player Diagnostics",
      markerName: "client_diagnostics_metrics_ok",
      requireConnMetrics: true
    )
    assertMinimumTarget("TiRTC Downlink Metrics Help", minimum: 44)
    assertMinimumTarget("TiRTC Downlink Metrics Collapse", minimum: 44)
  }

  private func assertMinimumTarget(_ label: String, minimum: CGFloat) {
    let control = waitForControl(label, timeout: shortTimeout)
    XCTAssertGreaterThanOrEqual(control.frame.width, minimum, "\(label) width is below \(minimum)")
    XCTAssertGreaterThanOrEqual(control.frame.height, minimum, "\(label) height is below \(minimum)")
  }

  private func waitDiagnostics(label: String, markerName: String, requireConnMetrics: Bool) {
    let deadline = Date().addingTimeInterval(shortTimeout)
    while Date() < deadline {
      let panelVisible =
        app.descendants(matching: .any)[automationId(label)].exists
        || app.descendants(matching: .any)[label].exists || labelContains(label)
      let metricsReady = !requireConnMetrics || labelContains("启动耗时")
      if panelVisible && metricsReady {
        marker(markerName)
        return
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.75))
    }
    marker("\(markerName)_timeout")
    attachScreenshot(name: "\(automationId(label))-timeout")
    XCTFail("timed out waiting for diagnostics \(label)")
  }

  private func waitForLogUpload(role: String) {
    let deadline = Date().addingTimeInterval(shortTimeout)
    while Date() < deadline {
      if labelContains("日志上传失败") {
        marker("\(role)_log_upload_failed")
        dismissLogUploadDialogIfPresent()
        XCTFail("log upload failed for \(role)")
        return
      }
      if labelContains("日志上传成功") {
        guard let logId = visibleLogUploadId(), !logId.isEmpty else {
          marker("\(role)_log_upload_missing_id")
          dismissLogUploadDialogIfPresent()
          XCTFail("log upload did not return a non-empty log id for \(role)")
          return
        }
        marker("\(role)_log_upload_id logId=\(logId)")
        marker("\(role)_log_upload_ok")
        dismissLogUploadDialogIfPresent()
        return
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.75))
    }
    marker("\(role)_log_upload_timeout")
    XCTFail("timed out waiting for log upload result for \(role)")
  }

  private func visibleLogUploadId() -> String? {
    for element in app.staticTexts.allElementsBoundByIndex {
      let combined = "\(element.label)\n\(element.value as? String ?? "")"
      if let id = parseLogUploadId(from: combined) {
        return id
      }
    }
    return nil
  }

  private func parseLogUploadId(from text: String) -> String? {
    guard let range = text.range(of: "日志 ID:") else {
      return nil
    }
    let suffix = text[range.upperBound...]
    let value =
      suffix.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).first.map(String.init) ?? ""
    return value.isEmpty ? nil : value
  }

  private func waitForText(_ text: String, timeout: TimeInterval) {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if labelContains(text) {
        return
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.25))
    }
    attachScreenshot(name: "missing-text-\(automationId(text))")
    XCTFail("missing text \(text)")
  }

  private func setField(_ label: String, value: String, verifyValue: Bool = true) {
    guard !value.isEmpty else {
      XCTFail("empty runner value for \(label)")
      return
    }
    dismissSystemAlertsIfPresent()
    let element = waitForControl(label, timeout: shortTimeout)
    let sensitive = isSensitiveField(label)
    if !sensitive && fieldValue(element) == value {
      return
    }
    element.tap()
    dismissSystemAlertsIfPresent()
    let currentValue = fieldValue(element)
    if !isPlaceholderValue(currentValue) {
      clearTextReliably(currentValue, from: element)
    }
    typeTextReliably(value, into: element)
    dismissSystemAlertsIfPresent()
    if verifyValue {
      var fieldWasSet = waitForFieldValue(label, expected: value, sensitive: sensitive)
      if !fieldWasSet && !sensitive {
        let retryElement = waitForControl(label, timeout: shortTimeout)
        retryElement.tap()
        let retryValue = fieldValue(retryElement)
        if !isPlaceholderValue(retryValue) {
          clearTextReliably(retryValue, from: retryElement)
        }
        typeTextCharacterByCharacter(value, into: retryElement)
        fieldWasSet = waitForFieldValue(label, expected: value, sensitive: false)
      }
      if !fieldWasSet {
        attachScreenshot(name: "field-not-set-\(automationId(label))")
        XCTFail("failed to set field \(label)")
      }
    }
    if !dismissKeyboardIfPresent() {
      attachScreenshot(name: "keyboard-not-dismissed-\(automationId(label))")
    }
  }

  private func csvValues(_ raw: String) -> [String] {
    Array(
      raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }.prefix(3))
  }

  private func setVideoFields(prefix: String, values: [String]) {
    for (index, value) in values.enumerated() {
      let label = "\(prefix) videoId \(index + 1)"
      if !app.descendants(matching: .any)[automationId(label)].exists {
        tapControl("\(prefix) add video")
      }
      setField(label, value: value)
    }
  }

  private func tapControl(_ label: String, dismissSystemAlertsAfterTap: Bool = true) {
    dismissSystemAlertsIfPresent()
    dismissLogBoxIfPresent()
    if !dismissKeyboardIfPresent() {
      attachScreenshot(name: "keyboard-not-dismissed-before-\(automationId(label))")
    }
    var element = waitForControl(label, timeout: shortTimeout)
    if !element.isHittable && dismissLogBoxIfPresent() {
      element = waitForControl(label, timeout: shortTimeout)
    }
    element.tap()
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    dismissLogBoxIfPresent()
    if dismissSystemAlertsAfterTap {
      dismissSystemAlertsIfPresent()
    }
  }

  private func tapMenuAction(
    menu: String,
    action: String,
    dismissSystemAlertsAfterTap: Bool = true
  ) {
    tapControl(menu)
    tapControl(action, dismissSystemAlertsAfterTap: dismissSystemAlertsAfterTap)
  }

  private func verifyMenuCancellation(_ menu: String) {
    tapControl(menu)
    tapControl("\(menu) Cancel")
    let trigger = waitForControl(menu, timeout: shortTimeout)
    XCTAssertTrue(trigger.isHittable, "playback menu trigger did not return after cancellation")
  }

  private func verifyMosaicSelection(_ lanes: [String]) {
    guard lanes.count > 1, let target = lanes.last else { return }
    restoreMosaicBaseline(lanes)
    let baseline = waitForControl(lanes[0], timeout: shortTimeout)
    if !baseline.isSelected {
      baseline.tap()
      XCTAssertTrue(waitForControl(lanes[0], timeout: shortTimeout).isSelected, "baseline playback lane was not selected")
    }
    if target != lanes[0] { tapControl(target) }
    let selected = waitForControl(target, timeout: shortTimeout)
    XCTAssertTrue(selected.isSelected, "selected playback lane state was not exposed")
    if lanes.count == 3 {
      for lane in lanes.dropLast() {
        let secondary = waitForControl(lane, timeout: shortTimeout)
        XCTAssertGreaterThan(selected.frame.width * selected.frame.height, secondary.frame.width * secondary.frame.height, "selected lane is not the primary visual area")
      }
    }
    tapControl(target)
    let maximized = waitForControl(target, timeout: shortTimeout)
    XCTAssertTrue(maximized.exists, "maximized playback lane is missing")
    for lane in lanes.dropLast() {
      XCTAssertFalse(app.descendants(matching: .any)[lane].exists, "non-selected lane remained in maximized layout")
    }
    tapControl(target)
    for lane in lanes {
      _ = waitForControl(lane, timeout: shortTimeout)
    }
  }

  private func restoreMosaicBaseline(_ lanes: [String]) {
    let visible = lanes.compactMap { lane -> XCUIElement? in
      let element = app.descendants(matching: .any)[lane]
      return element.exists ? element : nil
    }
    if visible.count == lanes.count { return }
    XCTAssertFalse(visible.isEmpty, "mosaic reset found no visible lane")
    visible[0].tap()
    for lane in lanes {
      _ = waitForControl(lane, timeout: shortTimeout)
    }
  }

  @discardableResult
  private func waitForControl(_ label: String, timeout: TimeInterval) -> XCUIElement {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      let id = automationId(label)
      let candidates = [
        app.buttons[id].firstMatch,
        app.textFields[id].firstMatch,
        app.textViews[id].firstMatch,
        app.secureTextFields[id].firstMatch,
        app.otherElements[id].firstMatch,
        app.staticTexts[id].firstMatch,
        app.descendants(matching: .any)[id].firstMatch,
        app.buttons[label].firstMatch,
        app.textFields[label].firstMatch,
        app.textViews[label].firstMatch,
        app.secureTextFields[label].firstMatch,
        app.otherElements[label].firstMatch,
        app.staticTexts[label].firstMatch,
        app.descendants(matching: .any)[label].firstMatch,
      ]
      if let element = candidates.first(where: { $0.exists && $0.isHittable }) {
        return element
      }
      if let element = candidates.first(where: { $0.exists }) {
        return element
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.25))
    }
    attachScreenshot(name: "missing-\(automationId(label))")
    XCTFail("missing control \(label)")
    return app.descendants(matching: .any).firstMatch
  }

  private func hasStreamMessageBubble() -> Bool {
    app.descendants(matching: .any)["TiRTC_Stream_Message_Bubble"].exists || labelContains("流消息")
  }

  private func waitForFieldValue(_ label: String, expected: String, sensitive: Bool) -> Bool {
    let deadline = Date().addingTimeInterval(5)
    while Date() < deadline {
      let element = waitForControl(label, timeout: 1)
      let current = fieldValue(element)
      if sensitive {
        if !isPlaceholderValue(current) {
          return true
        }
      } else if current == expected {
        return true
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.25))
    }
    return false
  }

  private func assertSyntheticTokenValue(field: String, expected: String, show: String, hide: String) {
    assertSensitiveFieldValue(field: field, expected: expected, show: show, hide: hide)
  }

  private func assertSensitiveFieldValue(field: String, expected: String, show: String, hide: String) {
    tapControl(show)
    var fieldWasSet = waitForFieldValue(field, expected: expected, sensitive: false)
    if !fieldWasSet {
      let element = waitForControl(field, timeout: shortTimeout)
      element.tap()
      let currentValue = fieldValue(element)
      if !isPlaceholderValue(currentValue) {
        clearTextReliably(currentValue, from: element)
      }
      typeTextCharacterByCharacter(expected, into: element)
      fieldWasSet = waitForFieldValue(field, expected: expected, sensitive: false)
    }
    tapControl(hide)
    XCTAssertTrue(fieldWasSet, "sensitive field did not match expected value")
    XCTAssertTrue(waitForControl(show, timeout: shortTimeout).exists, "token field did not return to hidden state")
  }

  private func fieldValue(_ element: XCUIElement) -> String {
    (element.value as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func typeTextReliably(_ value: String, into element: XCUIElement) {
    var chunkStart = value.startIndex
    while chunkStart < value.endIndex {
      let remaining = value.distance(from: chunkStart, to: value.endIndex)
      let chunkEnd = value.index(
        chunkStart,
        offsetBy: min(controlledTextInputChunkSize, remaining))
      element.typeText(String(value[chunkStart..<chunkEnd]))
      RunLoop.current.run(
        until: Date().addingTimeInterval(controlledTextInputKeystrokeDelay))
      chunkStart = chunkEnd
    }
  }

  private func typeTextCharacterByCharacter(_ value: String, into element: XCUIElement) {
    for character in value {
      element.typeText(String(character))
      RunLoop.current.run(
        until: Date().addingTimeInterval(controlledTextInputKeystrokeDelay))
    }
  }

  private func clearTextReliably(_ value: String, from element: XCUIElement) {
    if element.elementType != .textView {
      element.typeText(
        String(repeating: XCUIKeyboardKey.delete.rawValue, count: max(1, value.count)))
      return
    }
    element.typeKey("a", modifierFlags: .command)
    element.typeKey(.delete, modifierFlags: [])
    RunLoop.current.run(
      until: Date().addingTimeInterval(controlledTextInputKeystrokeDelay))
  }

  private func isSensitiveField(_ label: String) -> Bool {
    label.localizedCaseInsensitiveContains("token")
      || label.localizedCaseInsensitiveContains("secret")
  }

  private func isPlaceholderValue(_ value: String) -> Bool {
    if value.isEmpty {
      return true
    }
    let placeholderMarkers = [
      "TiRTC",
      "接入",
      "待连接",
      "音频流",
      "视频流",
      "粘贴",
      "例如",
    ]
    return placeholderMarkers.contains { value.contains($0) }
  }

  private func labelContains(_ text: String) -> Bool {
    let predicate = NSPredicate(format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@", text, text)
    return app.descendants(matching: .any).containing(predicate).firstMatch.exists
  }

  @discardableResult
  private func dismissLogBoxIfPresent() -> Bool {
    let predicate = NSPredicate(
      format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@",
      "Open debugger to view warnings",
      "Open debugger to view warnings"
    )
    let warning = app.descendants(matching: .any).containing(predicate).firstMatch
    guard warning.exists else {
      return false
    }
    let closeLabels = ["Close", "Dismiss", "关闭", "×"]
    for label in closeLabels {
      let button = app.buttons[label]
      if button.exists && button.isHittable {
        button.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        return true
      }
    }
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.89)).tap()
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    return true
  }

  @discardableResult
  private func dismissLogUploadDialogIfPresent() -> Bool {
    let alert = app.alerts.firstMatch
    if alert.exists {
      for title in ["确定", "OK"] where alert.buttons[title].exists {
        alert.buttons[title].tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        return true
      }
    }
    for title in ["确定", "OK"] where app.buttons[title].exists {
      app.buttons[title].tap()
      RunLoop.current.run(until: Date().addingTimeInterval(0.2))
      return true
    }
    return false
  }

  private func hasVisibleVideoFrame() -> Bool {
    return hasVisibleVideoFrames(in: currentVideoTiles())
  }

  private func currentVideoTiles() -> [XCUIElement] {
    var videoTiles =
      app.buttons.matching(
        NSPredicate(format: "label BEGINSWITH[c] %@", "Video Stream ")
      ).allElementsBoundByIndex
    if videoTiles.isEmpty {
      videoTiles =
        app.buttons.matching(
          NSPredicate(format: "label BEGINSWITH[c] %@", "Video Channel ")
        ).allElementsBoundByIndex
    }
    return videoTiles
  }

  private func hasVisibleVideoFrames(in videoTiles: [XCUIElement]) -> Bool {
    return videoFrameSignatures(in: videoTiles) != nil
  }

  private func videoFrameSignatures(in videoTiles: [XCUIElement]) -> [[UInt8]]? {
    guard !videoTiles.isEmpty else {
      return nil
    }
    let image = app.screenshot().image
    guard
      let pngData = image.pngData(),
      let cgImage = UIImage(data: pngData)?.cgImage
    else {
      return nil
    }
    let width = cgImage.width
    let height = cgImage.height
    let bytesPerRow = width * 4
    var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
    let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
      guard
        let context = CGContext(
          data: buffer.baseAddress,
          width: width,
          height: height,
          bitsPerComponent: 8,
          bytesPerRow: bytesPerRow,
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else {
        return false
      }
      context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    guard rendered else {
      return nil
    }
    let appFrame = app.frame
    guard appFrame.width > 0, appFrame.height > 0 else {
      return nil
    }
    let scaleX = CGFloat(width) / appFrame.width
    let scaleY = CGFloat(height) / appFrame.height
    var signatures: [[UInt8]] = []
    for tile in videoTiles {
      let frame = tile.frame
      let left = max(0, Int((frame.minX - appFrame.minX) * scaleX))
      let right = min(width, Int((frame.maxX - appFrame.minX) * scaleX))
      let tileTop = max(0, Int((frame.minY - appFrame.minY) * scaleY))
      let tileBottom = min(height, Int((frame.maxY - appFrame.minY) * scaleY))
      guard right > left, tileBottom > tileTop else {
        return nil
      }
      let top = tileTop + (tileBottom - tileTop) * 35 / 100
      let bottom = tileTop + (tileBottom - tileTop) * 65 / 100
      guard
        let signature = videoFrameSignature(
          pixels,
          bytesPerRow: bytesPerRow,
          left: left,
          right: right,
          top: top,
          bottom: bottom)
      else {
        return nil
      }
      signatures.append(signature)
    }
    return signatures
  }

  private func videoFrameSignature(
    _ pixels: [UInt8],
    bytesPerRow: Int,
    left: Int,
    right: Int,
    top: Int,
    bottom: Int
  ) -> [UInt8]? {
    let stepX = max(1, (right - left) / 32)
    let stepY = max(1, (bottom - top) / 18)
    var samples = 0
    var visibleSamples = 0
    var signature: [UInt8] = []
    var y = top
    while y < bottom {
      var x = left
      while x < right {
        let offset = y * bytesPerRow + x * 4
        let r = Int(pixels[offset])
        let g = Int(pixels[offset + 1])
        let b = Int(pixels[offset + 2])
        let maxChannel = max(r, max(g, b))
        let minChannel = min(r, min(g, b))
        let luma = (r * 299 + g * 587 + b * 114) / 1000
        let chromaSpread = maxChannel - minChannel
        signature.append(UInt8(r))
        signature.append(UInt8(g))
        signature.append(UInt8(b))
        if luma >= videoFrameBrightLumaThreshold
          || (luma >= videoFrameChromaticLumaThreshold
            && chromaSpread >= videoFrameChromaticSpreadThreshold)
        {
          visibleSamples += 1
        }
        samples += 1
        x += stepX
      }
      y += stepY
    }
    guard
      samples > 0,
      visibleSamples * 100 / samples >= videoFrameMinimumVisiblePercent
    else {
      return nil
    }
    return signature
  }

  private func videoFramesAdvanced(from before: [[UInt8]], to after: [[UInt8]]) -> Bool {
    guard before.count == after.count, !before.isEmpty else {
      return false
    }
    return zip(before, after).allSatisfy { beforeLane, afterLane in
      guard beforeLane.count == afterLane.count, beforeLane.count >= 3 else {
        return false
      }
      var changedSamples = 0
      var offset = 0
      while offset + 2 < beforeLane.count {
        let redDelta = abs(Int(beforeLane[offset]) - Int(afterLane[offset]))
        let greenDelta = abs(Int(beforeLane[offset + 1]) - Int(afterLane[offset + 1]))
        let blueDelta = abs(Int(beforeLane[offset + 2]) - Int(afterLane[offset + 2]))
        if max(redDelta, max(greenDelta, blueDelta)) >= videoFrameChannelDeltaThreshold {
          changedSamples += 1
        }
        offset += 3
      }
      let sampleCount = beforeLane.count / 3
      return changedSamples * 100 / sampleCount >= videoFrameMinimumChangedPercent
    }
  }

  private func hold() {
    let milliseconds = Int(env("TIRTC_RN_HOLD_MS", defaultValue: "2000")) ?? 2000
    RunLoop.current.run(until: Date().addingTimeInterval(Double(milliseconds) / 1000.0))
  }

  private func attachScreenshot(name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  @discardableResult
  private func dismissSystemAlertsIfPresent() -> Bool {
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let alert = springboard.alerts.firstMatch
    if alert.waitForExistence(timeout: 0.2), tapPreferredSystemButton(in: alert) {
      return true
    }
    return dismissPasswordSaveSheetIfPresent(springboard: springboard)
  }

  private func dismissPasswordSaveSheetIfPresent(springboard: XCUIApplication) -> Bool {
    let dismissTitles = ["以后", "稍后", "取消", "Not Now", "Later", "Cancel"]
    guard let applicationUnderTest = app else {
      return false
    }
    for application in [applicationUnderTest, springboard] {
      for title in dismissTitles {
        let button = application.buttons[title].firstMatch
        if button.exists && button.isHittable {
          button.tap()
          RunLoop.current.run(until: Date().addingTimeInterval(0.2))
          return true
        }
      }
    }
    return false
  }

  private func waitAndAllowSystemPermission(stage: String) {
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let alert = springboard.alerts.firstMatch
    guard alert.waitForExistence(timeout: shortTimeout) else {
      attachScreenshot(name: "\(stage)-permission-dialog-timeout")
      XCTFail("timed out waiting for the \(stage) system permission dialog")
      return
    }
    marker("\(stage)_permission_dialog_seen")
    guard tapSystemPermissionAllowButton(in: alert) else {
      attachScreenshot(name: "\(stage)-permission-allow-missing")
      XCTFail("missing allow button in the \(stage) system permission dialog")
      return
    }
    let deadline = Date().addingTimeInterval(shortTimeout)
    while Date() < deadline {
      if !alert.exists {
        marker("\(stage)_permission_allowed")
        return
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.25))
    }
    attachScreenshot(name: "\(stage)-permission-dialog-not-dismissed")
    XCTFail("the \(stage) system permission dialog did not close")
  }

  private func tapSystemPermissionAllowButton(in alert: XCUIElement) -> Bool {
    let titles = [
      "Allow", "Allow Once", "Allow While Using App", "OK", "Continue",
      "允许", "允许一次", "使用 App 时允许", "好", "继续",
    ]
    for title in titles where alert.buttons[title].exists {
      alert.buttons[title].tap()
      return true
    }
    return false
  }

  @discardableResult
  private func dismissKeyboardIfPresent() -> Bool {
    let keyboard = app.keyboards.firstMatch
    guard keyboard.exists else {
      return true
    }
    let safeTop = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
    let deadline = Date().addingTimeInterval(keyboardDismissTimeout)
    while Date() < deadline {
      safeTop.tap()
      RunLoop.current.run(until: Date().addingTimeInterval(keyboardDismissPollInterval))
      if !keyboard.exists {
        return true
      }
      app.swipeDown()
      RunLoop.current.run(until: Date().addingTimeInterval(keyboardDismissPollInterval))
      if !keyboard.exists {
        return true
      }
    }
    return !keyboard.exists
  }

  private func tapPreferredSystemButton(in alert: XCUIElement) -> Bool {
    let preferredButtons = [
      "允许",
      "无线局域网与蜂窝网络",
      "好",
      "继续",
      "Allow",
      "Wi-Fi & Cellular Data",
      "WLAN & Cellular Data",
      "OK",
      "Continue",
      "Join",
      "Allow While Using App",
    ]
    for title in preferredButtons where alert.buttons[title].exists {
      alert.buttons[title].tap()
      return true
    }
    let buttonCount = alert.buttons.count
    if buttonCount > 0 {
      alert.buttons.element(boundBy: buttonCount - 1).tap()
      return true
    }
    return false
  }

  private func marker(_ value: String) {
    print("TiRtcRnSmoke marker=\(value)")
  }

  private func env(_ key: String, defaultValue: String = "") -> String {
    ProcessInfo.processInfo.environment[key] ?? defaultValue
  }

  private func automationId(_ label: String) -> String {
    label.replacingOccurrences(of: "[^A-Za-z0-9_]+", with: "_", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
  }
}
