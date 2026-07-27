package com.tange.ai.tirtc.reactnative.example

import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice

internal const val PACKAGE_NAME = "com.tange.ai.tirtc.reactnative.example"
internal const val MARKER_TAG = "TiRtcRnSmoke"
internal const val LAUNCH_TIMEOUT_MS = 20_000L
internal const val SHORT_TIMEOUT_MS = 30_000L
internal const val CONNECT_TIMEOUT_MS = 180_000L
internal const val FOREGROUND_RECOVERY_TIMEOUT_MS = 60_000L
internal const val BACKGROUND_RECOVERY_WINDOW_MS = 10_000L
internal const val FAILURE_HIERARCHY_PATH = "/sdcard/window_dump.xml"
internal const val FAILURE_SCREENSHOT_PATH = "/sdcard/tirtc_rn_smoke_failure.png"
internal const val DOWNLINK_VIDEO_SCREENSHOT_PATH = "/sdcard/tirtc_rn_smoke_downlink_video.png"
internal const val VIDEO_FRAME_MINIMUM_VISIBLE_PERCENT = 5
internal const val VIDEO_FRAME_BRIGHT_LUMA_THRESHOLD = 62
internal const val VIDEO_FRAME_CHROMATIC_LUMA_THRESHOLD = 45
internal const val VIDEO_FRAME_CHROMATIC_SPREAD_THRESHOLD = 20
internal const val DEFAULT_STRESS_LOOPS = 20
internal const val STRESS_RECONNECT_COOLDOWN_MS = 20_000L
internal val DOWNLINK_TEXT_MARKERS = listOf("video rendering", "播放中")

internal fun visibleText(desc: String): String {
  return when (desc) {
    "TiRTC Scan Token QR" -> "扫码"
    "TiRTC Start Downlink" -> "开始连接、拉流播放"
    "TiRTC Player Send Command" -> "发送命令"
    "TiRTC Player Upload Logs" -> "上传日志"
    "TiRTC Player Stop" -> "停止播放"
    "TiRTC Player Mute Audio" -> "静音"
    "TiRTC Player Restore Audio" -> "恢复声音"
    "TiRTC Player Start Talkback" -> "启动麦克风"
    "TiRTC Player Stop Talkback" -> "语音对讲中"
    "TiRTC Command Panel Send Command" -> "发送命令"
    "TiRTC Command Panel Send Stream Message" -> "发送流消息"
    "TiRTC Command Panel Request Key Frame" -> "请求关键帧"
    "TiRTC Command Panel Close" -> "×"
    "TiRTC Back" -> "‹"
    else ->
      desc
        .removePrefix("TiRTC Example ")
        .removePrefix("TiRTC Client ")
        .removePrefix("TiRTC Diagnostics ")
        .removePrefix("TiRTC Config ")
  }
}

internal fun automationId(label: String): String =
  label.replace(Regex("[^A-Za-z0-9_]+"), "_").trim('_')

internal fun hasStreamMessageBubble(device: UiDevice): Boolean {
  return device.hasObject(By.res(PACKAGE_NAME, automationId("TiRTC Stream Message Bubble"))) ||
    device.hasObject(By.desc("TiRTC Stream Message Bubble")) ||
    device.hasObject(By.descContains("TiRTC Stream Message Bubble")) ||
    device.hasObject(By.textContains("流消息"))
}
