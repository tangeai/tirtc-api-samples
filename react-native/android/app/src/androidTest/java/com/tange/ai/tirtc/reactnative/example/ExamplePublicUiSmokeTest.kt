package com.tange.ai.tirtc.reactnative.example

import android.content.Intent
import android.graphics.BitmapFactory
import android.graphics.Color
import android.os.Bundle
import android.util.Log
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.BySelector
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.UiObject2
import androidx.test.uiautomator.UiScrollable
import androidx.test.uiautomator.UiSelector
import androidx.test.uiautomator.Until
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class ExamplePublicUiSmokeTest {
  private val instrumentation = InstrumentationRegistry.getInstrumentation()
  private val device: UiDevice = UiDevice.getInstance(instrumentation)
  private val args: Bundle = InstrumentationRegistry.getArguments()

  @Test
  fun runPublicUiFlow() {
    launchExample()
    when (arg("flow", "downlink")) {
      "stress" -> {
        fillCommonConfig()
        runStressFlow()
      }
      else -> {
        fillCommonConfig()
        runDownlinkFlow()
      }
    }
  }

  private fun runDownlinkFlow() {
    clickDesc("TiRTC Start Downlink")
    marker("client_connect_clicked")
    waitPlayerOpened()
    waitClientDownlink()
    waitPlayerDiagnostics()
    runAudioOutputVolumeProbe()
    runTalkbackProbe()
    waitStreamMessageBubble()
    if (isIntegrationLayer()) {
      runBackgroundForegroundProbe("client", "TiRTC Player Stop")
      waitClientDownlink(captureVideoEvidence = false)
    }
    clickDesc("TiRTC Player Send Command")
    clickDesc("TiRTC Command Panel Echo Preset")
    clickDesc("TiRTC Command Panel Send Command")
    clickDesc("TiRTC Command Panel Close")
    clickDesc("TiRTC Player Upload Logs")
    marker("client_log_upload_clicked")
    waitForLogUpload("client")
    marker("client_public_actions_clicked")
    Thread.sleep(arg("holdMs", "2000").toLongOrNull() ?: 2_000L)
    clickDesc("TiRTC Player Stop")
    waitObject(By.desc("TiRTC Config appId"), SHORT_TIMEOUT_MS)
    if (isIntegrationLayer()) {
      marker("teardown_mount_unmount_client_ok")
    }
    marker("client_downlink_done")
  }

  private fun runStressFlow() {
    val loops = arg("loops", DEFAULT_STRESS_LOOPS.toString()).toIntOrNull()?.coerceAtLeast(1) ?: DEFAULT_STRESS_LOOPS
    val loopOffset = arg("loopOffset", "0").toIntOrNull()?.coerceAtLeast(0) ?: 0
    repeat(loops) { index ->
      val localLoop = index + 1
      val loop = loopOffset + localLoop
      marker("stress_loop_${loop}_start")
      clickDesc("TiRTC Start Downlink")
      marker("stress_loop_${loop}_downlink_clicked package=${device.currentPackageName}")
      waitClientDownlink(captureVideoEvidence = false)
      marker("stress_fabric_output_loop_${loop}_ok")
      Thread.sleep(arg("holdMs", "2000").toLongOrNull() ?: 2_000L)
      clickDesc("TiRTC Player Stop")
      waitObject(By.desc("TiRTC Config appId"), SHORT_TIMEOUT_MS)
      marker("stress_loop_${loop}_done")
      if (localLoop < loops) {
        Thread.sleep(STRESS_RECONNECT_COOLDOWN_MS)
        marker("stress_loop_${loop}_cooldown_done")
      }
    }
    marker("stress_loops_done")
    marker("stress_fabric_output_loops_done")
    marker("stress_loops_done_details count=$loops offset=$loopOffset")
  }

  private fun fillCommonConfig() {
    waitObject(By.desc("TiRTC Config appId"), LAUNCH_TIMEOUT_MS)
    setConfigField("appId", arg("appId"))
    setConfigField("endpoint", arg("endpoint"))
    setConfigField("remoteId", arg("remoteId"))
    setConfigField("audioStreamId", arg("audioStreamId", "10"))
    setConfigField("videoStreamId", arg("videoStreamId", "11"))
    setConfigField("token", arg("token"))
    marker("config_filled")
  }

  private fun launchExample() {
    collapseSystemOverlays()
    device.pressHome()
    val context = ApplicationProvider.getApplicationContext<android.content.Context>()
    val intent = context.packageManager.getLaunchIntentForPackage(PACKAGE_NAME)
    assertNotNull("missing launch intent for $PACKAGE_NAME", intent)
    intent!!.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TASK or Intent.FLAG_ACTIVITY_NEW_TASK)
    context.startActivity(intent)
    assertTrue("app package did not launch", device.wait(Until.hasObject(By.pkg(PACKAGE_NAME).depth(0)), LAUNCH_TIMEOUT_MS))
    val configField = waitObject(By.desc("TiRTC Config appId"), LAUNCH_TIMEOUT_MS)
    if (configField == null) {
      dumpFailureArtifacts("launch_config")
    }
    assertNotNull("missing launch config field TiRTC Config appId", configField)
  }

  private fun activateExample() {
    collapseSystemOverlays()
    val context = ApplicationProvider.getApplicationContext<android.content.Context>()
    val intent = context.packageManager.getLaunchIntentForPackage(PACKAGE_NAME)
    assertNotNull("missing launch intent for $PACKAGE_NAME", intent)
    intent!!.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    context.startActivity(intent)
    assertTrue("app package did not return to foreground", device.wait(Until.hasObject(By.pkg(PACKAGE_NAME).depth(0)), LAUNCH_TIMEOUT_MS))
  }

  private fun runBackgroundForegroundProbe(role: String, expectedControl: String) {
    marker("background_foreground_${role}_start")
    device.pressHome()
    Thread.sleep(BACKGROUND_RECOVERY_WINDOW_MS)
    activateExample()
    waitForControlVisible(expectedControl, FOREGROUND_RECOVERY_TIMEOUT_MS)
    marker("background_foreground_${role}_ok")
  }

  private fun setConfigField(key: String, value: String) {
    val desc = "TiRTC Config $key"
    assertTrue("missing test value for $desc", value.isNotEmpty())
    val field = findControl(desc, key)
    if (field == null) {
      dumpFailureArtifacts(desc)
    }
    assertNotNull("missing field $desc", field)
    field!!.click()
    field.text = value
    dismissSoftKeyboardIfShown()
    waitForFieldValue(desc, value)
  }

  private fun waitForFieldValue(desc: String, expected: String) {
    val deadline = System.currentTimeMillis() + SHORT_TIMEOUT_MS
    while (System.currentTimeMillis() < deadline) {
      val field =
        device.findObject(By.res(PACKAGE_NAME, automationId(desc)))
          ?: device.findObject(By.desc(desc))
      if (field?.text == expected) {
        return
      }
      Thread.sleep(100)
    }
    dumpFailureArtifacts(desc)
    throw AssertionError("field $desc did not retain the provided value")
  }

  private fun collapseSystemOverlays() {
    try {
      device.executeShellCommand("cmd statusbar collapse")
    } catch (_: Throwable) {
    }
  }

  private fun clickDesc(desc: String) {
    ensureExampleWindow()
    dismissSoftKeyboardIfShown()
    val item = findControl(desc, visibleText(desc))
    if (item == null) {
      dumpFailureArtifacts(desc)
    }
    assertNotNull("missing control $desc", item)
    clickControl(item!!)
    Thread.sleep(300)
  }

  private fun clickControl(item: UiObject2) {
    var target: UiObject2? = item
    repeat(4) {
      val current = target ?: return@repeat
      if (current.isClickable) {
        current.click()
        return
      }
      target = current.parent
    }
    val bounds = item.visibleBounds
    device.click(bounds.centerX(), bounds.centerY())
  }

  private fun findControl(desc: String, text: String): UiObject2? {
    return waitObject(By.res(PACKAGE_NAME, automationId(desc)), 3_000L)
      ?: waitObject(By.desc(desc), 3_000L)
      ?: waitObject(By.descContains(desc), 3_000L)
      ?: waitObject(By.text(text), 3_000L)
      ?: waitObject(By.textContains(text), 3_000L)
      ?: scrollToDesc(desc)
      ?: scrollToText(text)
  }

  private fun waitAnyText(values: List<String>, timeoutMs: Long, stage: String) {
    val deadline = System.currentTimeMillis() + timeoutMs
    while (System.currentTimeMillis() < deadline) {
      if (hasAnyText(values)) {
        marker("${stage}_ok")
        return
      }
      Thread.sleep(250)
    }
    marker("${stage}_timeout")
    dumpFailureArtifacts(stage)
    throw AssertionError("timed out waiting for $stage: ${values.joinToString()}")
  }

  private fun waitPlayerOpened() {
    val deadline = System.currentTimeMillis() + SHORT_TIMEOUT_MS
    while (System.currentTimeMillis() < deadline) {
      if (hasPlayerControls()) {
        marker("client_player_opened")
        return
      }
      if (hasAnyText(listOf("Token 校验失败", "启动失败", "订阅失败"))) {
        dumpFailureArtifacts("client_player_open_failed")
        throw AssertionError("client player open failed")
      }
      Thread.sleep(500)
    }
    dumpFailureArtifacts("client_player_not_opened")
    throw AssertionError("client player did not open")
  }

  private fun waitClientDownlink(captureVideoEvidence: Boolean = true) {
    val deadline = System.currentTimeMillis() + CONNECT_TIMEOUT_MS
    var textSeen = false
    var streamSeen = false
    while (System.currentTimeMillis() < deadline) {
      if (!textSeen && hasAnyText(DOWNLINK_TEXT_MARKERS)) {
        marker("client_downlink_text_ok")
        textSeen = true
      }
      if (!streamSeen && hasStreamMessageBubble(device)) {
        marker("client_downlink_stream_message_ok")
        streamSeen = true
      }
      if (hasPlayerControls() && hasVisibleVideoFrame()) {
        if (captureVideoEvidence) {
          saveDownlinkVideoScreenshot()
        }
        marker("client_downlink_video_frame_ok")
        return
      }
      Thread.sleep(750)
    }
    marker("client_downlink_timeout")
    dumpFailureArtifacts("client_downlink")
    throw AssertionError("timed out waiting for client_downlink: ${DOWNLINK_TEXT_MARKERS.joinToString()}")
  }

  private fun waitStreamMessageBubble() {
    val deadline = System.currentTimeMillis() + SHORT_TIMEOUT_MS
    while (System.currentTimeMillis() < deadline) {
      if (hasStreamMessageBubble(device)) {
        marker("client_stream_message_bubble_ok")
        return
      }
      Thread.sleep(750)
    }
    marker("client_stream_message_bubble_timeout")
    dumpFailureArtifacts("client_stream_message_bubble")
    throw AssertionError("timed out waiting for stream message bubble")
  }

  private fun runTalkbackProbe() {
    clickDesc("TiRTC Player Start Talkback")
    waitAndAllowRuntimePermission("talkback")
    waitForTalkbackPermissionReturn()
    marker("talkback_permission_returned")
    clickDesc("TiRTC Player Start Talkback")
    waitForTalkbackRunning()
    marker("talkback_start_ok")
    clickDesc("TiRTC Player Stop Talkback")
    waitForTalkbackStopped()
    marker("talkback_stop_ok")
    clickDesc("TiRTC Player Start Talkback")
    waitForTalkbackRunning()
    clickDesc("TiRTC Player Stop Talkback")
    waitForTalkbackStopped()
    marker("talkback_restart_ok")
  }

  private fun runAudioOutputVolumeProbe() {
    clickDesc("TiRTC Player Mute Audio")
    waitObject(By.desc("TiRTC Player Restore Audio"), SHORT_TIMEOUT_MS)
    marker("audio_output_muted_ok")
    Thread.sleep(5_000L)
    clickDesc("TiRTC Player Restore Audio")
    waitObject(By.desc("TiRTC Player Mute Audio"), SHORT_TIMEOUT_MS)
    marker("audio_output_volume_cycle_ok")
  }

  private fun waitForTalkbackRunning() {
    val deadline = System.currentTimeMillis() + SHORT_TIMEOUT_MS
    while (System.currentTimeMillis() < deadline) {
      if (hasControl("TiRTC Player Stop Talkback")) {
        return
      }
      if (hasAnyText(listOf("麦克风配置失败", "麦克风绑定失败", "麦克风启动失败"))) {
        dumpFailureArtifacts("talkback_start")
        throw AssertionError("talkback failed to start")
      }
      Thread.sleep(500)
    }
    dumpFailureArtifacts("talkback_start")
    throw AssertionError("timed out waiting for talkback start")
  }

  private fun waitForTalkbackPermissionReturn() {
    val deadline = System.currentTimeMillis() + SHORT_TIMEOUT_MS
    while (System.currentTimeMillis() < deadline) {
      val startButton =
        device.findObject(By.res(PACKAGE_NAME, automationId("TiRTC Player Start Talkback")))
          ?: device.findObject(By.desc("TiRTC Player Start Talkback"))
      if (
        device.currentPackageName == PACKAGE_NAME &&
        startButton?.isEnabled == true &&
        !hasControl("TiRTC Player Stop Talkback")
      ) {
        return
      }
      Thread.sleep(250)
    }
    dumpFailureArtifacts("talkback_permission_return")
    throw AssertionError("talkback did not return to the start state after permission grant")
  }

  private fun waitForTalkbackStopped() {
    val deadline = System.currentTimeMillis() + SHORT_TIMEOUT_MS
    while (System.currentTimeMillis() < deadline) {
      if (hasControl("TiRTC Player Start Talkback")) {
        return
      }
      Thread.sleep(500)
    }
    dumpFailureArtifacts("talkback_stop")
    throw AssertionError("timed out waiting for talkback stop")
  }

  private fun waitPlayerDiagnostics() {
    waitDiagnosticsPanel(
      device = device,
      desc = "TiRTC Player Diagnostics",
      markerName = "client_diagnostics_metrics_ok",
      requireConnMetrics = true,
      ensureExampleWindow = ::ensureExampleWindow,
      marker = ::marker,
      dumpFailureArtifacts = ::dumpFailureArtifacts,
    )
  }

  private fun waitForLogUpload(role: String) {
    val deadline = System.currentTimeMillis() + SHORT_TIMEOUT_MS
    while (System.currentTimeMillis() < deadline) {
      if (hasAnyText(listOf("日志上传失败"))) {
        marker("${role}_log_upload_failed")
        dismissLogUploadDialogIfPresent()
        throw AssertionError("log upload failed for $role")
      }
      val logId = visibleLogUploadId()
      if (hasAnyText(listOf("日志上传成功")) && !logId.isNullOrBlank()) {
        marker("${role}_log_upload_id logId=$logId")
        marker("${role}_log_upload_ok")
        dismissLogUploadDialogIfPresent()
        return
      }
      Thread.sleep(500)
    }
    marker("${role}_log_upload_timeout")
    dumpFailureArtifacts("${role}_log_upload")
    throw AssertionError("timed out waiting for log upload result for $role")
  }

  private fun visibleLogUploadId(): String? {
    val candidates = listOfNotNull(
      device.findObject(By.textContains("日志 ID:"))?.text,
      device.findObject(By.descContains("日志 ID:"))?.contentDescription,
    )
    return candidates.firstNotNullOfOrNull(::parseLogUploadId)
  }

  private fun parseLogUploadId(text: String): String? {
    val marker = "日志 ID:"
    val index = text.indexOf(marker)
    if (index < 0) {
      return null
    }
    val value = text
      .substring(index + marker.length)
      .trim()
      .split(Regex("\\s+"))
      .firstOrNull()
      ?.trim()
      .orEmpty()
    return value.ifBlank { null }
  }

  private fun dismissLogUploadDialogIfPresent() {
    for (text in listOf("确定", "OK")) {
      val button = device.findObject(By.text(text)) ?: device.findObject(By.desc(text))
      if (button != null) {
        button.click()
        Thread.sleep(250)
        return
      }
    }
  }

  private fun hasAnyText(values: List<String>): Boolean {
    return values.any { value ->
      device.hasObject(By.textContains(value)) || device.hasObject(By.descContains(value))
    }
  }

  private fun hasPlayerControls(): Boolean {
    return device.hasObject(By.desc("TiRTC Player Stop")) ||
      device.hasObject(By.text("停止播放")) ||
      device.hasObject(By.textContains("停止播放"))
  }

  private fun hasControl(desc: String): Boolean {
    val text = visibleText(desc)
    return device.hasObject(By.res(PACKAGE_NAME, automationId(desc))) ||
      device.hasObject(By.desc(desc)) ||
      device.hasObject(By.descContains(desc)) ||
      device.hasObject(By.text(text)) ||
      device.hasObject(By.textContains(text))
  }

  private fun waitForControlVisible(desc: String, timeoutMs: Long) {
    val deadline = System.currentTimeMillis() + timeoutMs
    while (System.currentTimeMillis() < deadline) {
      ensureExampleWindow()
      if (hasControl(desc)) {
        return
      }
      Thread.sleep(250)
    }
    dumpFailureArtifacts(desc)
    throw AssertionError("timed out waiting for foreground control $desc")
  }

  private fun hasVisibleVideoFrame(): Boolean {
    if (device.currentPackageName != PACKAGE_NAME) {
      ensureExampleWindow()
      if (device.currentPackageName != PACKAGE_NAME) {
        return false
      }
    }
    val file = File(instrumentation.targetContext.cacheDir, "tirtc-rn-smoke-video-probe.png")
    if (!device.takeScreenshot(file)) {
      return false
    }
    val bitmap =
      BitmapFactory.decodeFile(file.absolutePath)
        ?: run {
          file.delete()
          return false
        }
    try {
      val left = bitmap.width / 10
      val right = bitmap.width * 9 / 10
      val top = bitmap.height * 42 / 100
      val bottom = bitmap.height * 68 / 100
      val stepX = ((right - left) / 32).coerceAtLeast(1)
      val stepY = ((bottom - top) / 18).coerceAtLeast(1)
      var samples = 0
      var visibleSamples = 0
      var y = top
      while (y < bottom) {
        var x = left
        while (x < right) {
          val pixel = bitmap.getPixel(x, y)
          val red = Color.red(pixel)
          val green = Color.green(pixel)
          val blue = Color.blue(pixel)
          val maxChannel = maxOf(red, green, blue)
          val minChannel = minOf(red, green, blue)
          val luma = (red * 299 + green * 587 + blue * 114) / 1000
          val chromaSpread = maxChannel - minChannel
          if (luma >= VIDEO_FRAME_BRIGHT_LUMA_THRESHOLD ||
            (luma >= VIDEO_FRAME_CHROMATIC_LUMA_THRESHOLD &&
              chromaSpread >= VIDEO_FRAME_CHROMATIC_SPREAD_THRESHOLD)
          ) {
            visibleSamples += 1
          }
          samples += 1
          x += stepX
        }
        y += stepY
      }
      val visible =
        samples > 0 && visibleSamples * 100 / samples >= VIDEO_FRAME_MINIMUM_VISIBLE_PERCENT
      if (visible) {
        saveDownlinkVideoScreenshot()
      }
      return visible
    } finally {
      bitmap.recycle()
      file.delete()
    }
  }

  private fun saveDownlinkVideoScreenshot() {
    try {
      device.executeShellCommand("screencap -p $DOWNLINK_VIDEO_SCREENSHOT_PATH")
    } catch (error: Throwable) {
      Log.w(MARKER_TAG, "failed_to_capture_downlink_video reason=${error.message}")
    }
  }

  private fun waitObject(selector: BySelector, timeoutMs: Long): UiObject2? {
    device.wait(Until.hasObject(selector), timeoutMs)
    return device.findObject(selector)
  }

  private fun ensureExampleWindow() {
    collapseSystemOverlays()
    val currentPackage = device.currentPackageName
    if (!currentPackage.isNullOrEmpty() && currentPackage != PACKAGE_NAME) {
      device.pressBack()
      Thread.sleep(250)
    }
  }

  private fun dismissSoftKeyboardIfShown() {
    try {
      val inputState = device.executeShellCommand("dumpsys input_method")
      val imeVisible = inputState.contains("mInputShown=true") ||
        Regex("mImeWindowVis=(?!0\\b)\\d+").containsMatchIn(inputState)
      if (imeVisible) {
        device.pressBack()
        Thread.sleep(500)
      }
    } catch (_: Throwable) {
    }
  }

  private fun waitAndAllowRuntimePermission(stage: String) {
    val deadline = System.currentTimeMillis() + SHORT_TIMEOUT_MS
    while (System.currentTimeMillis() < deadline) {
      val button = permissionAllowButton()
      if (button != null) {
        marker("${stage}_permission_dialog_seen")
        button.click()
        waitForPermissionDialogToClose(stage)
        marker("${stage}_permission_allowed")
        return
      }
      Thread.sleep(250)
    }
    dumpSystemDialogFailureArtifacts("${stage}_permission_dialog")
    throw AssertionError("timed out waiting for the $stage runtime permission dialog")
  }

  private fun permissionAllowButton(): UiObject2? {
    val controllerPackages =
      listOf(
        "com.google.android.permissioncontroller",
        "com.android.permissioncontroller",
        "com.android.packageinstaller",
      )
    val resourceNames =
      listOf(
        "permission_allow_foreground_only_button",
        "permission_allow_button",
        "permission_allow_one_time_button",
      )
    for (controllerPackage in controllerPackages) {
      for (resourceName in resourceNames) {
        val button = device.findObject(By.res(controllerPackage, resourceName))
        if (button != null) {
          return button
        }
      }
    }
    for (label in listOf("使用应用时允许", "仅在使用该应用时允许", "仅此一次", "允许", "While using the app", "Only this time", "Allow")) {
      val button = device.findObject(By.text(label))
      if (button != null) {
        return button
      }
    }
    return null
  }

  private fun waitForPermissionDialogToClose(stage: String) {
    val deadline = System.currentTimeMillis() + SHORT_TIMEOUT_MS
    while (System.currentTimeMillis() < deadline) {
      if (permissionAllowButton() == null && device.currentPackageName == PACKAGE_NAME) {
        return
      }
      Thread.sleep(250)
    }
    dumpSystemDialogFailureArtifacts("${stage}_permission_return")
    throw AssertionError("$stage runtime permission dialog did not return to the Example")
  }

  private fun dumpSystemDialogFailureArtifacts(desc: String) {
    try {
      device.executeShellCommand("uiautomator dump $FAILURE_HIERARCHY_PATH")
      device.executeShellCommand("screencap -p $FAILURE_SCREENSHOT_PATH")
      Log.i(MARKER_TAG, "failure_artifacts=$desc hierarchy=$FAILURE_HIERARCHY_PATH screenshot=$FAILURE_SCREENSHOT_PATH")
    } catch (error: Throwable) {
      Log.w(MARKER_TAG, "failed_to_dump_failure_artifacts=$desc reason=${error.message}")
    }
  }

  private fun scrollToDesc(desc: String): UiObject2? {
    try {
      UiScrollable(UiSelector().scrollable(true)).scrollIntoView(UiSelector().description(desc))
    } catch (_: Throwable) {
    }
    return device.findObject(By.desc(desc))
  }

  private fun scrollToText(text: String): UiObject2? {
    try {
      UiScrollable(UiSelector().scrollable(true)).scrollIntoView(UiSelector().text(text))
    } catch (_: Throwable) {
    }
    return device.findObject(By.text(text)) ?: device.findObject(By.textContains(text))
  }

  private fun marker(name: String) {
    Log.i(MARKER_TAG, "marker=$name")
  }

  private fun dumpFailureArtifacts(desc: String) {
    try {
      ensureExampleWindow()
      device.executeShellCommand("uiautomator dump $FAILURE_HIERARCHY_PATH")
      device.executeShellCommand("screencap -p $FAILURE_SCREENSHOT_PATH")
      Log.i(MARKER_TAG, "failure_artifacts=$desc hierarchy=$FAILURE_HIERARCHY_PATH screenshot=$FAILURE_SCREENSHOT_PATH")
    } catch (error: Throwable) {
      Log.w(MARKER_TAG, "failed_to_dump_failure_artifacts=$desc reason=${error.message}")
    }
  }

  private fun isIntegrationLayer(): Boolean = arg("layer") == "integration"

  private fun arg(name: String, default: String = ""): String = args.getString(name) ?: default
}
