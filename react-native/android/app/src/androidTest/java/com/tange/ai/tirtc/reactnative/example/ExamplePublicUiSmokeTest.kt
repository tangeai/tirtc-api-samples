package com.tange.ai.tirtc.reactnative.example

import android.content.Intent
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.Rect
import android.os.Bundle
import android.util.Log
import android.view.KeyEvent
import android.view.inputmethod.InputMethodManager
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry
import androidx.test.runner.lifecycle.Stage
import androidx.test.uiautomator.By
import androidx.test.uiautomator.BySelector
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.UiObject2
import androidx.test.uiautomator.UiScrollable
import androidx.test.uiautomator.UiSelector
import androidx.test.uiautomator.Until
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.ByteArrayOutputStream
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import kotlin.math.ceil

@RunWith(AndroidJUnit4::class)
class ExamplePublicUiSmokeTest {
  private val instrumentation = InstrumentationRegistry.getInstrumentation()
  private val device: UiDevice = UiDevice.getInstance(instrumentation)
  private val args: Bundle = InstrumentationRegistry.getArguments()

  @Test
  fun runPublicUiFlow() {
    if (arg("flow", "downlink") == "input-media") {
      launchSdkCase()
      val deadline = System.currentTimeMillis() + 90000
      while (System.currentTimeMillis() < deadline) {
        if (hasAnyText(listOf("Input Media Case Failed"))) {
          dumpFailureArtifacts("input-media-failed")
          throw AssertionError("input media fixture failed")
        }
        if (hasAnyText(listOf("Input Media Case Passed"))) {
          marker("input-media-completed")
          return
        }
        Thread.sleep(250)
      }
      dumpFailureArtifacts("input-media-timeout")
      throw AssertionError("input media fixture timed out")
    }
    if (arg("flow", "downlink") == "ti-cloud-storage-sdk") {
      CloudStorageCallbackLifecycle.verify()
      launchSdkCase()
      runCloudStorageSdkCase()
      CloudStorageModuleLifecycle.verify(ApplicationProvider.getApplicationContext())
      return
    }
    launchExample()
    when (arg("flow", "downlink")) {
      "auxiliary" -> verifyAuxiliaryUiContract()
      "ti-cloud-storage" -> runCloudStorageFlow()
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

  private fun launchSdkCase() {
    collapseSystemOverlays()
    device.pressHome()
    val context = ApplicationProvider.getApplicationContext<android.content.Context>()
    val intent = context.packageManager.getLaunchIntentForPackage(PACKAGE_NAME)
    assertNotNull("missing launch intent for $PACKAGE_NAME", intent)
    intent!!.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TASK or Intent.FLAG_ACTIVITY_NEW_TASK)
    context.startActivity(intent)
    assertTrue(
      "Ti Cloud Storage SDK Case app package did not launch",
      device.wait(Until.hasObject(By.pkg(PACKAGE_NAME).depth(0)), LAUNCH_TIMEOUT_MS),
    )
  }

  private fun runCloudStorageSdkCase() {
    val deadline = System.currentTimeMillis() + STORE_SDK_CASE_TIMEOUT_MS
    while (System.currentTimeMillis() < deadline) {
      if (device.currentPackageName != PACKAGE_NAME) {
        dumpFailureArtifacts("ti-cloud-storage-sdk-case-app-exited")
        throw AssertionError("Ti Cloud Storage SDK Case app exited before a terminal result")
      }
      if (hasAnyText(listOf("Ti Cloud Storage SDK Case Failed"))) {
        dumpFailureArtifacts("ti-cloud-storage-sdk-case-failed")
        throw AssertionError("Ti Cloud Storage public SDK Case reported failure")
      }
      if (hasAnyText(listOf("Ti Cloud Storage SDK Case Passed"))) {
        marker("ti-cloud-storage-sdk-case-completed")
        return
      }
      Thread.sleep(500)
    }
    dumpFailureArtifacts("ti-cloud-storage-sdk-case-timeout")
    throw AssertionError("timed out waiting for Ti Cloud Storage public SDK Case")
  }

  private fun runCloudStorageFlow() {
    val token = fetchOneUseToken(arg("ti-cloud-storage-token-url"))
    val startTimeMs = arg("ti-cloud-storage-start-time-ms").toLongOrNull()
      ?: error("missing Ti Cloud Storage start time")
    try {
      clickText("云录像")
      setConfigField("Ti Cloud Storage Config appId", arg("ti-cloud-storage-app-id"))
      setConfigField("Ti Cloud Storage Config endpoint", arg("ti-cloud-storage-endpoint"))
      setConfigField("Ti Cloud Storage Config token", token.concatToString())
      setConfigField("Ti Cloud Storage Config audioId", arg("ti-cloud-storage-audio-channel-id", "10"))
      val videoChannelIds = csvArg("ti-cloud-storage-video-channel-ids", arg("ti-cloud-storage-video-channel-id", "11"))
      setVideoFields("Ti Cloud Storage Config", videoChannelIds)
      marker("ti-cloud-storage-config-filled")
      tiCloudStorageUiGateCheckpoint("configure")
      clickDesc("Ti Cloud Storage Open")
      waitForDesc("Ti Cloud Storage Recordings Sheet", CONNECT_TIMEOUT_MS)
      verifyVisibleRecordingsState("populated", "录像已加载", CONNECT_TIMEOUT_MS)
      waitForDesc("Ti Cloud Storage Play $startTimeMs", CONNECT_TIMEOUT_MS)
      tiCloudStorageUiGateCheckpoint("sheet", startTimeMs)
      clickDesc("Ti Cloud Storage Play $startTimeMs")
      waitAnyText(listOf("正在播放"), CONNECT_TIMEOUT_MS, "ti-cloud-storage-rendering")
      val videoDeadline = System.currentTimeMillis() + CONNECT_TIMEOUT_MS
      while (System.currentTimeMillis() < videoDeadline && !hasVisibleVideoFrame()) Thread.sleep(750)
      assertTrue("Ti Cloud Storage video frame was not visible", hasVisibleVideoFrame())
      videoChannelIds.forEach { channelId ->
        assertNotNull("missing video Channel $channelId lane", waitForPlaybackLane("Video Channel $channelId", SHORT_TIMEOUT_MS))
      }
      videoChannelIds.lastOrNull()?.let {
        val lane = "Video Channel $it"
        clickPlaybackLane(lane)
        assertNotNull("Ti Cloud Storage playback lane could not be selected: $it", waitForSelectedLane(lane))
      }
      marker("ti-cloud-storage-visible-video-ok")
      tiCloudStorageUiGateCheckpoint("playback")

      clickDesc("Ti Cloud Storage Raw Dump")
      waitAnyText(listOf("正在抓取诊断数据"), SHORT_TIMEOUT_MS, "ti-cloud-storage-raw-dump-start")
      Thread.sleep(10_000L)
      clickDesc("Ti Cloud Storage Raw Dump")
      waitForLogUpload("ti-cloud-storage", "-")
      marker("ti-cloud-storage-raw-dump-upload-ok")

      Thread.sleep(5_000L)
      clickDesc("Ti Cloud Storage Pause Resume")
      waitAnyText(listOf("已暂停"), SHORT_TIMEOUT_MS, "ti-cloud-storage-pause")
      Thread.sleep(3_000L)

      var speedHalf = false
      repeat(7) {
        if (speedHalf) return@repeat
        val speedControl = device.findObject(By.desc("Ti Cloud Storage Speed"))
          ?: device.findObject(By.res(PACKAGE_NAME, automationId("Ti Cloud Storage Speed")))
        assertNotNull("Ti Cloud Storage speed control is missing", speedControl)
        clickControl(speedControl!!)
        Thread.sleep(500L)
        speedHalf = hasAnyText(listOf("播放倍速：1/2×"))
      }
      if (!speedHalf) {
        dumpFailureArtifacts("ti-cloud-storage-speed-x0_5")
      }
      assertTrue("Ti Cloud Storage speed did not reach 1/2×", speedHalf)
      marker("ti-cloud-storage-speed-x0_5-ok")
      Thread.sleep(2_000L)
      val speedControl = device.findObject(By.desc("Ti Cloud Storage Speed"))
        ?: device.findObject(By.res(PACKAGE_NAME, automationId("Ti Cloud Storage Speed")))
      assertNotNull("Ti Cloud Storage speed control is missing", speedControl)
      clickControl(speedControl!!)
      waitForCloudStorageSpeedX1()

      clickDesc("Ti Cloud Storage Pause Resume")
      waitAnyText(listOf("继续播放", "正在播放"), SHORT_TIMEOUT_MS, "ti-cloud-storage-resume")

      clickDesc("Ti Cloud Storage Mute")
      waitAnyText(listOf("已静音"), SHORT_TIMEOUT_MS, "ti-cloud-storage-mute")
      Thread.sleep(2_000L)

      val seek = requireNotNull(findControl("Ti Cloud Storage Seek", "")) { "Ti Cloud Storage seek control missing" }
      val seekBounds = seek.visibleBounds
      var seeked = false
      for (startPercent in listOf(75, 95, 50)) {
        if (seeked) break
        device.swipe(
          seekBounds.left + seekBounds.width() * startPercent / 100,
          seekBounds.centerY(),
          seekBounds.left + seekBounds.width() * 45 / 100,
          seekBounds.centerY(),
          100,
        )
        Thread.sleep(1_500L)
        seeked = hasAnyText(listOf("已跳转"))
      }
      if (!seeked) {
        dumpFailureArtifacts("ti-cloud-storage-seek")
      }
      assertTrue("Ti Cloud Storage seek did not reach 45%", seeked)
      marker("ti-cloud-storage-seek-ok")
      Thread.sleep(3_000L)

      verifyMenuCancellation("Ti Cloud Storage More")
      clickMenuAction("Ti Cloud Storage More", "Ti Cloud Storage Snapshot")
      waitAnyText(listOf("截图完成"), SHORT_TIMEOUT_MS, "ti-cloud-storage-snapshot")
      clickMenuAction("Ti Cloud Storage More", "Ti Cloud Storage Save Gallery")
      waitAnyText(listOf("已保存到系统相册"), SHORT_TIMEOUT_MS, "ti-cloud-storage-snapshot-gallery")

      clickMenuAction("Ti Cloud Storage More", "Ti Cloud Storage Recording")
      waitAnyText(listOf("边播边录已开始"), SHORT_TIMEOUT_MS, "ti-cloud-storage-recording-started")
      Thread.sleep(7_000L)
      clickMenuAction("Ti Cloud Storage More", "Ti Cloud Storage Recording")
      waitAnyText(listOf("边播边录完成"), SHORT_TIMEOUT_MS, "ti-cloud-storage-recording-completed")
      clickMenuAction("Ti Cloud Storage More", "Ti Cloud Storage Save Gallery")
      waitAnyText(listOf("已保存到系统相册"), SHORT_TIMEOUT_MS, "ti-cloud-storage-recording-gallery")

      clickDesc("Ti Cloud Storage Recordings")
      clickDesc("Ti Cloud Storage Export $startTimeMs")
      verifyVisibleRecordingsState("export-busy", "正在下载录像", SHORT_TIMEOUT_MS)
      clickDesc("Ti Cloud Storage Close Recordings")
      waitAnyText(listOf("范围下载完成"), STORE_EXPORT_TIMEOUT_MS, "ti-cloud-storage-export-completed")
      clickMenuAction("Ti Cloud Storage More", "Ti Cloud Storage Save Gallery")
      waitAnyText(listOf("已保存到系统相册"), SHORT_TIMEOUT_MS, "ti-cloud-storage-export-gallery")

      clickDesc("Ti Cloud Storage Recordings")
      clickDesc("Ti Cloud Storage Play $startTimeMs")
      waitAnyText(listOf("正在播放"), CONNECT_TIMEOUT_MS, "ti-cloud-storage-replay-restarted")
      assertNotNull(
        "Ti Cloud Storage mute preference was not retained after replay recreation",
        waitForSelectedLane("Ti Cloud Storage Mute"),
      )
      marker("ti-cloud-storage-replay-muted-preference-ok")
      waitForCloudStorageReplayRendering()
      val replayDeadline = System.currentTimeMillis() + STORE_PLAYBACK_COMPLETION_TIMEOUT_MS
      var outputCompleted = false
      while (System.currentTimeMillis() < replayDeadline) {
        assertTrue("Ti Cloud Storage replay failed", !hasAnyText(listOf("播放失败", "回放失败", "输出失败")))
        if (hasAnyText(listOf("Ti Cloud Storage Status: 播放完成"))) {
          outputCompleted = true
          break
        }
        assertTrue("Ti Cloud Storage replay buffered after rendering", !hasAnyText(listOf("缓冲中")))
        Thread.sleep(1_000L)
      }
      assertTrue("Ti Cloud Storage replay did not reach Output completion", outputCompleted)
      marker("ti-cloud-storage-continuous-playback-ok terminal=output_completed")

      clickDesc("Ti Cloud Storage Mute")
      waitAnyText(listOf("已恢复声音"), SHORT_TIMEOUT_MS, "ti-cloud-storage-unmute")

      clickDesc("Ti Cloud Storage Back")
      assertNotNull(
        "Ti Cloud Storage configure entry is not reachable after back navigation",
        findControl("Ti Cloud Storage Open", "播放云录像"),
      )
      marker("ti-cloud-storage-returned-to-configure")
      tiCloudStorageUiGateCheckpoint("entry")
      marker("ti-cloud-storage-public-ui-done")
    } finally {
      token.fill('\u0000')
    }
  }

  private fun waitForCloudStorageReplayRendering() {
    val deadline = System.currentTimeMillis() + CONNECT_TIMEOUT_MS
    while (System.currentTimeMillis() < deadline) {
      assertTrue("Ti Cloud Storage replay failed", !hasAnyText(listOf("播放失败", "回放失败", "输出失败")))
      if (!hasAnyText(listOf("缓冲中")) && hasVisibleVideoFrame()) {
        marker("ti-cloud-storage-replay-rendering-ok")
        return
      }
      Thread.sleep(500L)
    }
    dumpFailureArtifacts("ti-cloud-storage-replay-rendering")
    throw AssertionError("Ti Cloud Storage replay did not leave its initial buffering state")
  }

  private fun waitForDesc(desc: String, timeoutMs: Long): UiObject2 {
    val deadline = System.currentTimeMillis() + timeoutMs
    while (System.currentTimeMillis() < deadline) {
      ensureExampleWindow()
      device.findObject(By.desc(desc))?.let { return it }
      Thread.sleep(500)
    }
    throw AssertionError("timed out waiting for accessibility label: $desc")
  }

  private fun tiCloudStorageUiGateCheckpoint(name: String, expectedStartMs: Long? = null) {
    val configureEntry = if (name == "configure") {
      findControl("Ti Cloud Storage Open", "播放云录像")
    } else {
      null
    }
    val fileName = "ti-cloud-storage-ui-$name.png"
    val checkpointDir = instrumentation.targetContext.getExternalFilesDir(null)
      ?: instrumentation.targetContext.cacheDir
    val file = File(checkpointDir, fileName)
    assertTrue("Ti Cloud Storage checkpoint screenshot failed: $name", device.takeScreenshot(file))
    when (name) {
      "configure" -> {
        assertNotNull("Ti Cloud Storage configure entry is not visible", configureEntry)
        assertTrue("Ti Cloud Storage configure entry is not visible", configureEntry!!.visibleBounds.height() > 0)
        scrollConfigureToTop()
        val audio = findControl("Ti Cloud Storage Config audioId", arg("ti-cloud-storage-audio-channel-id", "10"))
        assertNotNull("Ti Cloud Storage audio channel field is missing", audio)
        val videoChannelIds = csvArg(
          "ti-cloud-storage-video-channel-ids",
          arg("ti-cloud-storage-video-channel-id", "11"),
        )
        videoChannelIds.forEachIndexed { index, channelId ->
          val video = findControl("Ti Cloud Storage Config videoId ${index + 1}", channelId)
          assertNotNull("Ti Cloud Storage video channel field ${index + 1} is missing", video)
        }
      }
      "sheet" -> {
        val sheet = device.findObject(By.desc("Ti Cloud Storage Recordings Sheet"))
          ?: device.findObject(By.res(PACKAGE_NAME, "ti-cloud-storage-recordings-sheet"))
        assertNotNull("Ti Cloud Storage recordings sheet is missing", sheet)
        val bounds = sheet.visibleBounds
        val heightRatio = bounds.height().toDouble() / device.displayHeight
        val bottomRatio = bounds.bottom.toDouble() / device.displayHeight
        val topRatio = bounds.top.toDouble() / device.displayHeight
        assertTrue("Ti Cloud Storage sheet height out of contract: $heightRatio", heightRatio in 0.84..0.92)
        assertTrue("Ti Cloud Storage sheet is not bottom anchored", bottomRatio >= 0.97 && topRatio <= 0.35)
        val handle = device.findObject(By.desc("Ti Cloud Storage Sheet Handle"))
          ?: device.findObject(By.res(PACKAGE_NAME, "ti-cloud-storage-sheet-handle"))
        assertNotNull("Ti Cloud Storage sheet drag handle is missing", handle)
        assertTrue("Ti Cloud Storage sheet drag handle is not visible", handle.visibleBounds.height() > 0)
        val rows = device.findObjects(By.descContains("Ti Cloud Storage Play "))
        assertTrue("Ti Cloud Storage recording rows are missing", rows.isNotEmpty())
        val topmost = rows.minByOrNull { it.visibleBounds.top }
        assertNotNull("Ti Cloud Storage recording row bounds are missing", topmost)
        assertTrue(
          "Ti Cloud Storage newest recording is not the first visible row",
          topmost!!.contentDescription?.contains("Ti Cloud Storage Play ${expectedStartMs ?: 0}") == true,
        )
      }
      "playback" -> {
        val videoChannelIds = csvArg(
          "ti-cloud-storage-video-channel-ids",
          arg("ti-cloud-storage-video-channel-id", "11"),
        )
        val initialLanes = videoChannelIds.mapNotNull { channelId ->
          findPlaybackLane("Video Channel $channelId")
        }
        assertTrue("Ti Cloud Storage playback lanes are missing", initialLanes.size == videoChannelIds.size)
        verifyMosaicSelection(videoChannelIds.map { "Video Channel $it" })
        val refreshedLanes = videoChannelIds.map { channelId ->
          val lane = waitForPlaybackLane("Video Channel $channelId", SHORT_TIMEOUT_MS)
          assertNotNull("Ti Cloud Storage playback lane is missing after mosaic restore: $channelId", lane)
          lane!!
        }
        val bounds = Rect(
          refreshedLanes.minOf { it.visibleBounds.left },
          refreshedLanes.minOf { it.visibleBounds.top },
          refreshedLanes.maxOf { it.visibleBounds.right },
          refreshedLanes.maxOf { it.visibleBounds.bottom },
        )
        val widthRatio = bounds.width().toDouble() / device.displayWidth
        val heightRatio = bounds.height().toDouble() / device.displayHeight
        assertTrue("Ti Cloud Storage video stage is squeezed horizontally: $widthRatio", widthRatio >= 0.6)
        assertTrue("Ti Cloud Storage video stage is squeezed vertically: $heightRatio", heightRatio >= 0.35)
        assertTrue("Ti Cloud Storage playback controls are not visible", hasControl("Ti Cloud Storage Pause Resume"))
      }
      "entry" -> {
        val entry = device.findObject(By.desc("Ti Cloud Storage Open"))
        assertNotNull("Ti Cloud Storage entry page did not render after back navigation", entry)
        assertTrue("Ti Cloud Storage entry page is not visible", entry.visibleBounds.height() > 0)
      }
    }
    marker("ti-cloud-storage-ui-gate-$name")
    marker("ti-cloud-storage-ui-checkpoint_$name path=$fileName")
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
    clickDesc("TiRTC Player Raw Dump")
    waitAnyText(listOf("正在抓取诊断数据"), SHORT_TIMEOUT_MS, "client-raw-dump-start")
    Thread.sleep(10_000L)
    clickDesc("TiRTC Player Raw Dump")
    marker("client_log_upload_clicked raw_dump=true")
    waitForLogUpload("client")
    marker("client_raw_dump_upload_ok")
    verifyMenuCancellation("TiRTC Player More")
    openMenuWithKeyboardFocus("TiRTC Player More")
    activateWithKeyboard("TiRTC Player Send Command")
    assertMenuDidNotStealFocus("TiRTC Player More", "TiRTC Command Panel Echo Preset")
    device.pressBack()
    waitForInputFocus("TiRTC Player More", "command panel did not restore focus after Android Back")
    openMenuWithKeyboardFocus("TiRTC Player More")
    activateWithKeyboard("TiRTC Player Send Command")
    assertMenuDidNotStealFocus("TiRTC Player More", "TiRTC Command Panel Echo Preset")
    clickDesc("TiRTC Command Panel Echo Preset")
    clickDesc("TiRTC Command Panel Send Command")
    activateWithKeyboard("TiRTC Command Panel Close")
    waitForInputFocus("TiRTC Player More", "command close button did not restore focus to More")
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
      clickStressControl("TiRTC Start Downlink", scrollIfMissing = true)
      marker("stress_loop_${loop}_downlink_clicked package=${device.currentPackageName}")
      waitClientDownlink(captureVideoEvidence = false)
      marker("stress_fabric_output_loop_${loop}_ok")
      Thread.sleep(arg("holdMs", "2000").toLongOrNull() ?: 2_000L)
      clickStressControl("TiRTC Player Stop")
      waitForControlVisible("TiRTC Config appId", SHORT_TIMEOUT_MS)
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
    val token = fetchOneUseToken(arg("tokenUrl"))
    try {
      setConfigField("appId", arg("appId"))
      setConfigField("endpoint", arg("endpoint"))
      setConfigField("remoteId", arg("remoteId"))
      setConfigField("audioId", arg("audioStreamId", "10"))
      setVideoFields("TiRTC Config", csvArg("videoStreamIds", arg("videoStreamId", "11")))
      setConfigField("token", token.concatToString())
      marker("config_filled")
    } finally {
      token.fill('\u0000')
    }
  }

  private fun verifyAuxiliaryUiContract() {
    clickDesc("TiRTC 偏好设置")
    assertNotNull("playback settings section is missing", waitObject(By.text("客户端播放"), SHORT_TIMEOUT_MS))
    assertNotNull("talkback settings section is missing", waitObject(By.text("客户端语音对讲"), SHORT_TIMEOUT_MS))
    assertMinimumTargetDp("TiRTC Settings Back", 48)
    clickDesc("TiRTC Settings Back")

    setConfigField("endpoint", "https://keep-rtc.example")
    setConfigField("appId", "keep-rtc-app")
    setConfigField("remoteId", "KEEPDEVICE")
    setConfigField("audioId", "70")
    clickDesc("TiRTC QR Input")
    replaceAuxiliaryText("TiRTC QR Manual Content", "invalid")
    clickDesc("TiRTC QR Apply Content")
    waitAnyText(listOf("二维码内容无效"), SHORT_TIMEOUT_MS, "rtc-qr-invalid")
    replaceAuxiliaryText("TiRTC QR Manual Content", "{\"app_id\":\"m4-rtc-app\",\"remote_id\":\"M4DEVICE\",\"token\":\"v1.m4-test\",\"endpoint\":\"https://m4-rtc.example\"}")
    clickDesc("TiRTC QR Apply Content")
    waitObject(By.desc("TiRTC Config appId"), SHORT_TIMEOUT_MS)
    waitForFieldValue("TiRTC Config appId", "m4-rtc-app")
    waitForFieldValue("TiRTC Config remoteId", "M4DEVICE")
    waitForFieldValue("TiRTC Config endpoint", "https://m4-rtc.example")
    assertSyntheticTokenValue("TiRTC Config token", "v1.m4-test", "TiRTC Config Show Token", "TiRTC Config Hide Token")
    waitForFieldValue("TiRTC Config audioId", "70")

    clickText("云录像")
    setConfigField("Ti Cloud Storage Config appId", "keep-cloud-app")
    setConfigField("Ti Cloud Storage Config endpoint", "https://keep-cloud.example")
    setConfigField("Ti Cloud Storage Config audioId", "71")
    clickDesc("Ti Cloud Storage QR Input")
    replaceAuxiliaryText("Ti Cloud Storage QR Manual Content", "invalid value")
    clickDesc("Ti Cloud Storage QR Apply Content")
    waitAnyText(listOf("二维码内容无效"), SHORT_TIMEOUT_MS, "cloud-qr-invalid")
    replaceAuxiliaryText("Ti Cloud Storage QR Manual Content", "{\"app_id\":\"m4-cloud-app\",\"token\":\"m4-cloud-token\",\"endpoint\":\"https://m4-cloud.example\"}")
    clickDesc("Ti Cloud Storage QR Apply Content")
    waitObject(By.desc("Ti Cloud Storage Config appId"), SHORT_TIMEOUT_MS)
    waitForFieldValue("Ti Cloud Storage Config appId", "m4-cloud-app")
    waitForFieldValue("Ti Cloud Storage Config endpoint", "https://m4-cloud.example")
    assertSyntheticTokenValue("Ti Cloud Storage Config token", "m4-cloud-token", "Ti Cloud Storage Config Show Token", "Ti Cloud Storage Config Hide Token")
    waitForFieldValue("Ti Cloud Storage Config audioId", "71")
    clickText("RTC")
    marker("auxiliary_ui_contract_ok")
  }

  private fun replaceAuxiliaryText(desc: String, value: String) {
    val field = findControl(desc, desc)
    assertNotNull("missing auxiliary field $desc", field)
    field!!.click()
    field.text = value
    dismissSoftKeyboardIfShown()
    waitForFieldValue(desc, value)
  }

  private fun verifyVisibleRecordingsState(state: String, text: String, timeoutMs: Long) {
    val node = waitObject(By.descContains("Ti Cloud Storage Recordings State $state"), timeoutMs)
    assertNotNull("missing recordings state $state", node)
    assertTrue("recordings state $state has no visible bounds", node!!.visibleBounds.width() > 1 && node.visibleBounds.height() > 1)
    assertTrue("recordings state text $text is not visible", hasAnyText(listOf(text)))
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
    val desc = if (key.startsWith("Ti Cloud Storage ")) key else "TiRTC Config $key"
    assertTrue("missing test value for $desc", value.isNotEmpty())
    val field = findControl(desc, key)
    if (field == null) {
      dumpFailureArtifacts(desc)
    }
    assertNotNull("missing field $desc", field)
    field!!.click()
    field.text = value
    dismissSoftKeyboardIfShown()
    if (desc != "TiRTC Config token" && desc != "Ti Cloud Storage Config token") {
      waitForFieldValue(desc, value)
    }
  }

  private fun csvArg(name: String, fallback: String): List<String> =
    arg(name, fallback).split(',').map(String::trim).filter(String::isNotEmpty).take(3)

  private fun setVideoFields(prefix: String, values: List<String>) {
    values.forEachIndexed { index, value ->
      val label = "$prefix videoId ${index + 1}"
      if (!device.hasObject(By.desc(label))) clickDesc("$prefix add video")
      setConfigField(if (prefix == "TiRTC Config") "videoId ${index + 1}" else label, value)
    }
  }

  private fun clickText(text: String) {
    val item = findControl(text, text)
    assertNotNull("missing control $text", item)
    clickControl(item!!)
    Thread.sleep(300)
  }

  private fun fetchOneUseToken(url: String): CharArray {
    require(url.isNotEmpty()) { "missing one-use token URL" }
    val connection = URL(url).openConnection() as HttpURLConnection
    connection.connectTimeout = SHORT_TIMEOUT_MS.toInt()
    connection.readTimeout = SHORT_TIMEOUT_MS.toInt()
    connection.useCaches = false
    return try {
      check(connection.responseCode == HttpURLConnection.HTTP_OK) { "one-use token handoff failed" }
      val output = ByteArrayOutputStream()
      connection.inputStream.use { input ->
        val buffer = ByteArray(4096)
        while (true) {
          val count = input.read(buffer)
          if (count < 0) break
          check(output.size() + count <= 64 * 1024) { "one-use token handoff is too large" }
          output.write(buffer, 0, count)
        }
        buffer.fill(0)
      }
      val bytes = output.toByteArray()
      check(bytes.isNotEmpty() && bytes.none { it == 0.toByte() || it == 10.toByte() || it == 13.toByte() })
      val value = bytes.toString(Charsets.UTF_8).toCharArray()
      bytes.fill(0)
      value
    } finally {
      connection.disconnect()
    }
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

  private fun assertSyntheticTokenValue(field: String, expected: String, show: String, hide: String) {
    clickDesc(show)
    waitForFieldValue(field, expected)
    clickDesc(hide)
    assertNotNull("token field did not return to hidden state", waitObject(By.desc(show), SHORT_TIMEOUT_MS))
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

  private fun clickStressControl(desc: String, scrollIfMissing: Boolean = false) {
    ensureExampleWindow()
    dismissSoftKeyboardIfShown()
    val text = visibleText(desc)
    var item = findControlNow(desc, text)
    if (item == null && scrollIfMissing) {
      item = scrollToDesc(desc) ?: scrollToText(text) ?: swipeToControl(desc, text)
    }
    if (item == null) {
      dumpFailureArtifacts(desc)
    }
    assertNotNull("missing stress control $desc", item)
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
      ?: swipeToControl(desc, text)
  }

  private fun findControlNow(desc: String, text: String): UiObject2? {
    return device.findObject(By.res(PACKAGE_NAME, automationId(desc)))
      ?: device.findObject(By.desc(desc))
      ?: device.findObject(By.descContains(desc))
      ?: device.findObject(By.text(text))
      ?: device.findObject(By.textContains(text))
  }

  private fun waitAnyText(values: List<String>, timeoutMs: Long, stage: String) {
    val deadline = System.currentTimeMillis() + timeoutMs
    while (System.currentTimeMillis() < deadline) {
      if (hasAnyText(values)) {
        marker("$stage-ok")
        return
      }
      Thread.sleep(250)
    }
    marker("${stage}_timeout")
    dumpFailureArtifacts(stage)
    throw AssertionError("timed out waiting for $stage: ${values.joinToString()}")
  }

  private fun waitForCloudStorageSpeedX1() {
    val deadline = System.currentTimeMillis() + SHORT_TIMEOUT_MS
    while (System.currentTimeMillis() < deadline) {
      if (hasAnyText(listOf("播放倍速：1×"))) {
        marker("ti-cloud-storage-speed-x1-ok")
        return
      }
      if (hasAnyText(listOf("倍速设置失败"))) {
        marker("ti-cloud-storage-speed-x1-rejected")
        dumpFailureArtifacts("ti-cloud-storage-speed-x1-rejected")
        throw AssertionError("Ti Cloud Storage replay rejected the x1 speed change")
      }
      Thread.sleep(250)
    }
    marker("ti-cloud-storage-speed-x1-timeout")
    dumpFailureArtifacts("ti-cloud-storage-speed-x1-timeout")
    throw AssertionError("timed out waiting for ti_cloud_storage_speed_x1")
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
        val videoLanes = csvArg("videoStreamIds", arg("videoStreamId", "11")).map { streamId ->
          val lane = waitForPlaybackLane("Video Stream $streamId", SHORT_TIMEOUT_MS)
          assertNotNull("missing video Stream $streamId lane", lane)
          lane!!
        }
        assertRenderingAccessibilityStatus(videoLanes)
        verifyMosaicSelection(csvArg("videoStreamIds", arg("videoStreamId", "11")).map { "Video Stream $it" })
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
    if (!hasControl("TiRTC Player Diagnostics")) {
      clickDesc("TiRTC Downlink Metrics Expand")
    }
    waitDiagnosticsPanel(
      device = device,
      desc = "TiRTC Player Diagnostics",
      markerName = "client_diagnostics_metrics_ok",
      requireConnMetrics = true,
      ensureExampleWindow = ::ensureExampleWindow,
      marker = ::marker,
      dumpFailureArtifacts = ::dumpFailureArtifacts,
    )
    assertMinimumTargetDp("TiRTC Downlink Metrics Help", 48)
    assertMinimumTargetDp("TiRTC Downlink Metrics Collapse", 48)
  }

  private fun assertMinimumTargetDp(desc: String, minimumDp: Int) {
    val control = waitObject(By.desc(desc), SHORT_TIMEOUT_MS)
    assertNotNull("missing target for bounds check: $desc", control)
    val density = instrumentation.targetContext.resources.displayMetrics.density
    val minimumPx = ceil(minimumDp * density).toInt()
    assertTrue("$desc width is below ${minimumDp}dp (${minimumPx}px)", control!!.visibleBounds.width() >= minimumPx)
    assertTrue("$desc height is below ${minimumDp}dp (${minimumPx}px)", control.visibleBounds.height() >= minimumPx)
  }

  private fun clickMenuAction(menu: String, action: String) {
    clickDesc(menu)
    clickDesc(action)
  }

  private fun verifyMenuCancellation(menu: String) {
    openMenuWithKeyboardFocus(menu)
    device.pressBack()
    waitForInputFocus(menu, "playback menu trigger did not restore keyboard focus")
  }

  private fun openMenuWithKeyboardFocus(desc: String) {
    focusWithKeyboard(desc)
    device.pressEnter()
    assertNotNull("keyboard activation did not open menu: $desc", waitObject(By.desc("$desc Cancel"), SHORT_TIMEOUT_MS))
  }

  private fun activateWithKeyboard(desc: String) {
    focusWithKeyboard(desc)
    device.pressEnter()
  }

  private fun focusWithKeyboard(desc: String) {
    val deadline = System.currentTimeMillis() + SHORT_TIMEOUT_MS
    while (System.currentTimeMillis() < deadline) {
      val trigger = device.findObject(By.desc(desc))
      if (trigger?.isFocused == true) return
      device.pressKeyCode(KeyEvent.KEYCODE_TAB)
      Thread.sleep(100)
    }
    dumpFailureArtifacts("playback_menu_keyboard_focus")
    throw AssertionError("keyboard traversal did not focus control: $desc")
  }

  private fun waitForInputFocus(desc: String, failureMessage: String) {
    val deadline = System.currentTimeMillis() + SHORT_TIMEOUT_MS
    while (System.currentTimeMillis() < deadline) {
      if (device.findObject(By.desc(desc))?.isFocused == true) {
        Thread.sleep(500)
        if (device.findObject(By.desc(desc))?.isFocused == true) return
      }
      Thread.sleep(100)
    }
    dumpFailureArtifacts("playback_menu_focus_restore")
    throw AssertionError(failureMessage)
  }

  private fun assertMenuDidNotStealFocus(menu: String, destination: String) {
    assertNotNull("menu action did not open destination: $destination", waitObject(By.desc(destination), SHORT_TIMEOUT_MS))
    Thread.sleep(250)
    assertFalse("dismissed menu stole focus from action destination: $menu", device.findObject(By.desc(menu))?.isFocused == true)
  }

  private fun verifyMosaicSelection(lanes: List<String>) {
    if (lanes.size < 2) return
    restoreMosaicBaseline(lanes)
    val baseline = waitForPlaybackLane(lanes.first(), SHORT_TIMEOUT_MS)
    assertNotNull("baseline playback lane is missing", baseline)
    if (!baseline!!.isSelected) {
      clickPlaybackLane(lanes.first())
      assertNotNull("baseline playback lane was not selected", waitForSelectedLane(lanes.first()))
    }
    val target = lanes.last()
    if (target != lanes.first()) clickPlaybackLane(target)
    val selected = waitForSelectedLane(target)
      ?: throw AssertionError("selected playback lane state was not exposed")
    if (lanes.size == 3) {
      val primaryArea = selected.visibleBounds.width().toLong() * selected.visibleBounds.height()
      lanes.dropLast(1).forEach { lane ->
        val secondary = waitForPlaybackLane(lane, SHORT_TIMEOUT_MS)
        assertNotNull("secondary playback lane disappeared before maximize: $lane", secondary)
        val secondaryArea = secondary!!.visibleBounds.width().toLong() * secondary.visibleBounds.height()
        assertTrue("selected lane is not the primary visual area", primaryArea > secondaryArea)
      }
    }
    assertNotNull("maximize entry is not exposed", waitObject(By.desc("放大视频"), SHORT_TIMEOUT_MS))
    clickDesc("放大视频")
    val maximized = waitForPlaybackLane(target, SHORT_TIMEOUT_MS)
    assertNotNull("maximized playback lane is missing", maximized)
    waitForLanesAbsent(lanes.dropLast(1))
    assertNotNull("mosaic restore entry is not exposed", waitObject(By.desc("返回宫格"), SHORT_TIMEOUT_MS))
    clickDesc("返回宫格")
    lanes.forEach { lane ->
      assertNotNull("playback lane did not return after restore: $lane", waitForPlaybackLane(lane, SHORT_TIMEOUT_MS))
    }
  }

  private fun waitForSelectedLane(desc: String): UiObject2? {
    val deadline = System.currentTimeMillis() + SHORT_TIMEOUT_MS
    while (System.currentTimeMillis() < deadline) {
      findPlaybackLane(desc)?.let { if (it.isSelected) return it }
      Thread.sleep(100L)
    }
    dumpFailureArtifacts("playback_lane_selected")
    return null
  }

  private fun clickPlaybackLane(desc: String) {
    val lane = waitForPlaybackLane(desc, SHORT_TIMEOUT_MS)
      ?: throw AssertionError("playback lane is missing: $desc")
    val bounds = lane.visibleBounds
    device.click(bounds.centerX(), bounds.top + maxOf(1, bounds.height() / 4))
    Thread.sleep(300L)
  }

  private fun waitForLanesAbsent(lanes: List<String>) {
    val deadline = System.currentTimeMillis() + SHORT_TIMEOUT_MS
    while (System.currentTimeMillis() < deadline) {
      if (lanes.none(::isPlaybackLaneVisuallyPresent)) return
      Thread.sleep(100L)
    }
    dumpFailureArtifacts("playback_lane_maximized")
    throw AssertionError("non-selected lanes remained in maximized layout: ${lanes.joinToString()}")
  }

  private fun restoreMosaicBaseline(lanes: List<String>) {
    val visible = lanes.filter(::isPlaybackLaneVisuallyPresent)
    if (visible.size == lanes.size) return
    assertTrue("mosaic reset found no visible lane", visible.isNotEmpty())
    clickDesc("返回宫格")
    lanes.forEach { lane ->
      assertNotNull("playback lane did not return while resetting layout: $lane", waitForPlaybackLane(lane, SHORT_TIMEOUT_MS))
    }
  }

  private fun waitForLogUpload(role: String, separator: String = "_") {
    val deadline = System.currentTimeMillis() + SHORT_TIMEOUT_MS
    while (System.currentTimeMillis() < deadline) {
      if (hasAnyText(listOf("日志上传失败"))) {
        marker("$role${separator}log${separator}upload${separator}failed")
        dismissLogUploadDialogIfPresent()
        throw AssertionError("log upload failed for $role")
      }
      val logId = visibleLogUploadId()
      if (hasAnyText(listOf("日志上传成功")) && !logId.isNullOrBlank()) {
        marker("$role${separator}log${separator}upload${separator}id logId=$logId")
        marker("$role${separator}log${separator}upload${separator}ok")
        dismissLogUploadDialogIfPresent()
        return
      }
      Thread.sleep(500)
    }
    marker("$role${separator}log${separator}upload${separator}timeout")
    dumpFailureArtifacts("${role}_log_upload")
    throw AssertionError("timed out waiting for log upload result for $role")
  }

  private fun assertRenderingAccessibilityStatus(lanes: List<UiObject2>) {
    lanes.forEach { lane ->
      val accessibleStatus = listOfNotNull(lane.contentDescription, lane.text).joinToString(" ")
      assertTrue(
        "video lane accessibility status is not rendering: $accessibleStatus",
        accessibleStatus.contains("播放中"),
      )
    }
    marker("client_downlink_video_accessibility_rendering_ok")
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
      collapseSystemOverlays()
      device.wait(Until.hasObject(By.pkg(PACKAGE_NAME).depth(0)), 1_000L)
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
      val laneLabels = expectedVideoLaneLabels()
      if (laneLabels.isEmpty()) {
        return false
      }
      val laneBounds = laneLabels.mapNotNull { label ->
        findPlaybackLane(label)?.visibleBounds
      }
      if (laneBounds.size != laneLabels.size) {
        return false
      }
      val visible = laneBounds.all { bounds -> hasVisiblePixels(bitmap, videoContentBand(bounds)) }
      if (visible) {
        saveDownlinkVideoScreenshot()
      }
      return visible
    } finally {
      bitmap.recycle()
      file.delete()
    }
  }

  private fun expectedVideoLaneLabels(): List<String> {
    if (arg("flow", "downlink") == "ti-cloud-storage") {
      return csvArg(
        "ti-cloud-storage-video-channel-ids",
        arg("ti-cloud-storage-video-channel-id", "11"),
      ).map { channelId -> "Video Channel $channelId" }
    }
    return csvArg("videoStreamIds", arg("videoStreamId", "11"))
      .map { streamId -> "Video Stream $streamId" }
  }

  private fun videoContentBand(bounds: Rect): Rect {
    return Rect(
      bounds.left + bounds.width() / 10,
      bounds.top + bounds.height() * 35 / 100,
      bounds.right - bounds.width() / 10,
      bounds.top + bounds.height() * 65 / 100,
    )
  }

  private fun hasVisiblePixels(bitmap: android.graphics.Bitmap, bounds: Rect): Boolean {
    val left = bounds.left.coerceIn(0, bitmap.width)
    val right = bounds.right.coerceIn(left, bitmap.width)
    val top = bounds.top.coerceIn(0, bitmap.height)
    val bottom = bounds.bottom.coerceIn(top, bitmap.height)
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
    return samples > 0 && visibleSamples * 100 / samples >= VIDEO_FRAME_MINIMUM_VISIBLE_PERCENT
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

  private fun findPlaybackLane(desc: String): UiObject2? {
    val testId = when {
      desc.startsWith("Video Stream ") -> "video-stream-${desc.removePrefix("Video Stream ")}"
      desc.startsWith("Video Channel ") -> "video-channel-${desc.removePrefix("Video Channel ")}"
      else -> null
    }
    if (testId != null) {
      device.findObject(By.res(PACKAGE_NAME, testId))?.let { return it }
    }
    return device.findObject(By.desc(desc))
      ?: device.findObjects(By.descContains(desc))
        .filter { it.visibleBounds.width() > 0 && it.visibleBounds.height() > 0 }
        .maxWithOrNull(
          compareBy<UiObject2> { it.isClickable }
            .thenBy { it.visibleBounds.width().toLong() * it.visibleBounds.height() },
        )
  }

  private fun isPlaybackLaneVisuallyPresent(desc: String): Boolean {
    val bounds = findPlaybackLane(desc)?.visibleBounds ?: return false
    val parkedLimitPx = ceil(2 * instrumentation.targetContext.resources.displayMetrics.density).toInt()
    return bounds.width() > parkedLimitPx && bounds.height() > parkedLimitPx
  }

  private fun waitForPlaybackLane(desc: String, timeoutMs: Long): UiObject2? {
    val deadline = System.currentTimeMillis() + timeoutMs
    while (System.currentTimeMillis() < deadline) {
      findPlaybackLane(desc)?.let { return it }
      Thread.sleep(100L)
    }
    return findPlaybackLane(desc)
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
      instrumentation.runOnMainSync {
        val activity = ActivityLifecycleMonitorRegistry.getInstance()
          .getActivitiesInStage(Stage.RESUMED)
          .firstOrNull()
        val focusedView = activity?.currentFocus
        val windowToken = focusedView?.windowToken ?: activity?.window?.decorView?.windowToken
        val inputMethodManager = activity?.getSystemService(android.content.Context.INPUT_METHOD_SERVICE)
          as? InputMethodManager
        if (windowToken != null) {
          inputMethodManager?.hideSoftInputFromWindow(windowToken, 0)
        }
        focusedView?.clearFocus()
      }
      Thread.sleep(250)
      val inputState = device.executeShellCommand("dumpsys input_method")
      val appWindow = device.findObject(By.pkg(PACKAGE_NAME).depth(0))
      val imeVisible = inputState.contains("mInputShown=true") ||
        Regex("mImeWindowVis=(?!0(?:x0)?\\b)(?:0x[0-9a-fA-F]+|\\d+)").containsMatchIn(inputState) ||
        device.hasObject(By.pkg("com.google.android.inputmethod.latin")) ||
        device.hasObject(By.pkg("com.android.inputmethod.latin")) ||
        (appWindow != null && appWindow.visibleBounds.bottom < device.displayHeight * 9 / 10)
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
      device.waitForIdle()
      Thread.sleep(SCROLL_SETTLE_MS)
    } catch (_: Throwable) {
    }
    return device.findObject(By.desc(desc))
  }

  private fun scrollToText(text: String): UiObject2? {
    try {
      UiScrollable(UiSelector().scrollable(true)).scrollIntoView(UiSelector().text(text))
      device.waitForIdle()
      Thread.sleep(SCROLL_SETTLE_MS)
    } catch (_: Throwable) {
    }
    return device.findObject(By.text(text)) ?: device.findObject(By.textContains(text))
  }

  private fun swipeToControl(desc: String, text: String): UiObject2? {
    repeat(6) {
      device.swipe(
        device.displayWidth / 2,
        device.displayHeight * 4 / 5,
        device.displayWidth / 2,
        device.displayHeight / 3,
        24,
      )
      device.waitForIdle()
      Thread.sleep(SCROLL_SETTLE_MS)
      val item = device.findObject(By.res(PACKAGE_NAME, automationId(desc)))
        ?: device.findObject(By.desc(desc))
        ?: device.findObject(By.descContains(desc))
        ?: device.findObject(By.text(text))
        ?: device.findObject(By.textContains(text))
      if (item != null) return item
    }
    return null
  }

  private fun scrollConfigureToTop() {
    repeat(6) {
      device.swipe(
        device.displayWidth / 2,
        device.displayHeight / 3,
        device.displayWidth / 2,
        device.displayHeight * 4 / 5,
        24,
      )
      device.waitForIdle()
      Thread.sleep(SCROLL_SETTLE_MS)
    }
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

  private companion object {
    const val SCROLL_SETTLE_MS = 750L
    const val STORE_EXPORT_TIMEOUT_MS = 240_000L
    const val STORE_PLAYBACK_COMPLETION_TIMEOUT_MS = 210_000L
    const val STORE_SDK_CASE_TIMEOUT_MS = 900_000L
  }
}
