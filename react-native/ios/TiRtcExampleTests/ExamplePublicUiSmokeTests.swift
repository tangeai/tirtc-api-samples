import XCTest

private let shortTimeout: TimeInterval = 30
private let launchTimeout: TimeInterval = 40
private let connectTimeout: TimeInterval = 180
private let keyboardDismissTimeout: TimeInterval = 3
private let keyboardDismissPollInterval: TimeInterval = 0.2
private let videoFrameMinimumVisiblePercent = 5
private let videoFrameBrightLumaThreshold = 62
private let videoFrameChromaticLumaThreshold = 45
private let videoFrameChromaticSpreadThreshold = 20
private let backgroundRecoveryWindow: TimeInterval = 10
private let foregroundRecoveryTimeout: TimeInterval = 60

final class ExamplePublicUiSmokeTests: XCTestCase {
  private var app: XCUIApplication!

  override func setUpWithError() throws {
    continueAfterFailure = false
    app = XCUIApplication()
    addUIInterruptionMonitor(withDescription: "System Permission") { alert in
      self.tapPreferredSystemButton(in: alert)
    }
  }

  func testPublicUiFlow() throws {
    app.launch()
    dismissSystemAlertsIfPresent()
    app.tap()
    dismissSystemAlertsIfPresent()
    waitForControl("TiRTC Config appId", timeout: launchTimeout)

    switch env("TIRTC_RN_FLOW", defaultValue: "downlink") {
    case "stress":
      fillCommonConfig()
      runStressFlow()
    default:
      fillCommonConfig()
      runDownlinkFlow()
    }
  }

  private func runDownlinkFlow() {
    tapStartDownlink()
    marker("client_connect_clicked")
    waitPlayerOpened()
    waitClientDownlink()
    waitPlayerDiagnostics()
    runAudioOutputVolumeProbe()
    runTalkbackProbe()
    waitStreamMessageBubble()
    if isIntegrationLayer() {
      runBackgroundForegroundProbe(role: "client", expectedControl: "TiRTC Player Stop")
      waitClientDownlink(captureEvidence: false)
    }
    tapControl("TiRTC Player Send Command")
    tapControl("TiRTC Command Panel Echo Preset")
    tapControl("TiRTC Command Panel Send Command")
    tapControl("TiRTC Command Panel Close")
    tapControl("TiRTC Player Upload Logs")
    marker("client_log_upload_clicked")
    waitForLogUpload(role: "client")
    marker("client_public_actions_clicked")
    hold()
    tapControl("TiRTC Player Stop")
    waitForControl("TiRTC Config appId", timeout: shortTimeout)
    if isIntegrationLayer() {
      marker("teardown_mount_unmount_client_ok")
    }
    marker("client_downlink_done")
  }

  private func runStressFlow() {
    let loops = max(1, Int(env("TIRTC_RN_LOOPS", defaultValue: "20")) ?? 20)
    let loopOffset = max(0, Int(env("TIRTC_RN_LOOP_OFFSET", defaultValue: "0")) ?? 0)
    for localLoop in 1...loops {
      let loop = loopOffset + localLoop
      marker("stress_loop_\(loop)_start")
      tapStartDownlink()
      marker("stress_loop_\(loop)_downlink_clicked")
      waitPlayerOpened(captureEvidence: false)
      waitClientDownlink(captureEvidence: false)
      marker("stress_fabric_output_loop_\(loop)_ok")
      hold()
      tapControl("TiRTC Player Stop")
      waitForControl("TiRTC Config appId", timeout: shortTimeout)
      marker("stress_loop_\(loop)_done")
      if localLoop < loops {
        sleep(20)
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
      "TiRTC Config audioStreamId", value: env("TIRTC_RN_AUDIO_STREAM_ID", defaultValue: "10"))
    setField(
      "TiRTC Config videoStreamId", value: env("TIRTC_RN_VIDEO_STREAM_ID", defaultValue: "11"))
    setField("TiRTC Config token", value: env("TIRTC_RN_TOKEN"))
    marker("config_filled")
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
    tapControl("TiRTC Player Mute Audio")
    waitForControl("TiRTC Player Restore Audio", timeout: shortTimeout)
    let muteStartedAt = Date()
    RunLoop.current.run(until: muteStartedAt.addingTimeInterval(5.5))
    guard isPlayerScreenVisible(), hasVisibleVideoFrame() else {
      attachScreenshot(name: "audio-output-muted-continuity-failed")
      XCTFail("downlink did not remain active while audio output was muted")
      return
    }
    tapControl("TiRTC Player Restore Audio")
    waitForControl("TiRTC Player Mute Audio", timeout: shortTimeout)
    waitClientDownlink(captureEvidence: false)
    marker("audio_output_volume_cycle_ok")
    marker(
      "audio_output_volume_cycle_details mute_hold_ms=\(Int(Date().timeIntervalSince(muteStartedAt) * 1000))"
    )
  }

  private func isIntegrationLayer() -> Bool {
    env("TIRTC_RN_LAYER", defaultValue: "") == "integration"
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
    let deadline = Date().addingTimeInterval(connectTimeout)
    while Date() < deadline {
      if isPlayerScreenVisible() && hasVisibleVideoFrame() {
        if captureEvidence {
          attachScreenshot(name: "downlink-video")
        }
        marker("client_downlink_video_frame_ok")
        return
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.75))
    }
    attachScreenshot(name: "client-downlink-timeout")
    XCTFail("timed out waiting for client downlink")
  }

  private func waitPlayerOpened(captureEvidence: Bool = true) {
    let deadline = Date().addingTimeInterval(shortTimeout)
    while Date() < deadline {
      if isPlayerScreenVisible() {
        marker("client_player_opened")
        return
      }
      if labelContains("Token 校验失败") || labelContains("启动失败") || labelContains("订阅失败") {
        if captureEvidence {
          attachScreenshot(name: "client-player-open-failed")
        }
        XCTFail("client player open failed")
        return
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    }
    if captureEvidence {
      attachScreenshot(name: "client-player-not-opened")
    }
    XCTFail("client player did not open")
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
    if isConfigureScreenVisible() {
      return false
    }
    return app.buttons["TiRTC Player Stop"].isHittable
      || app.buttons["TiRTC Player Upload Logs"].isHittable
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
      if startButton.exists && startButton.isHittable && startButton.isEnabled && !stopButton.exists {
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
    waitDiagnostics(
      label: "TiRTC Player Diagnostics",
      markerName: "client_diagnostics_metrics_ok",
      requireConnMetrics: true
    )
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

  private func setField(_ label: String, value: String) {
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
    if !isPlaceholderValue(fieldValue(element)) {
      element.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 256))
    }
    element.typeText(value)
    dismissSystemAlertsIfPresent()
    if !waitForFieldValue(label, expected: value, sensitive: sensitive) {
      attachScreenshot(name: "field-not-set-\(automationId(label))")
      XCTFail("failed to set field \(label)")
    }
    if !dismissKeyboardIfPresent() {
      attachScreenshot(name: "keyboard-not-dismissed-\(automationId(label))")
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

  @discardableResult
  private func waitForControl(_ label: String, timeout: TimeInterval) -> XCUIElement {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      let id = automationId(label)
      let candidates = [
        app.buttons[id],
        app.textFields[id],
        app.textViews[id],
        app.secureTextFields[id],
        app.otherElements[id],
        app.staticTexts[id],
        app.descendants(matching: .any)[id],
        app.buttons[label],
        app.textFields[label],
        app.textViews[label],
        app.secureTextFields[label],
        app.otherElements[label],
        app.staticTexts[label],
        app.descendants(matching: .any)[label],
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

  private func fieldValue(_ element: XCUIElement) -> String {
    (element.value as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
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
    let image = app.screenshot().image
    guard let cgImage = image.cgImage else {
      return false
    }
    guard let provider = cgImage.dataProvider, let data = provider.data else {
      return false
    }
    let bytes = CFDataGetBytePtr(data)
    let bytesPerRow = cgImage.bytesPerRow
    let bitsPerPixel = cgImage.bitsPerPixel
    guard bitsPerPixel >= 32, let pixels = bytes else {
      return false
    }
    let width = cgImage.width
    let height = cgImage.height
    let left = width / 10
    let right = width * 9 / 10
    let top = height * 42 / 100
    let bottom = height * 68 / 100
    let stepX = max(1, (right - left) / 32)
    let stepY = max(1, (bottom - top) / 18)
    var samples = 0
    var visibleSamples = 0
    var y = top
    while y < bottom {
      var x = left
      while x < right {
        let offset = y * bytesPerRow + x * 4
        let b = Int(pixels[offset])
        let g = Int(pixels[offset + 1])
        let r = Int(pixels[offset + 2])
        let maxChannel = max(r, max(g, b))
        let minChannel = min(r, min(g, b))
        let luma = (r * 299 + g * 587 + b * 114) / 1000
        let chromaSpread = maxChannel - minChannel
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
    return samples > 0 && visibleSamples * 100 / samples >= videoFrameMinimumVisiblePercent
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
    guard alert.waitForExistence(timeout: 0.2) else {
      return false
    }
    return tapPreferredSystemButton(in: alert)
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
      "好",
      "继续",
      "Allow",
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
