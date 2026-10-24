package com.tange.ai.tirtc.reactnative.example

import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice

internal fun waitDiagnosticsPanel(
  device: UiDevice,
  desc: String,
  markerName: String,
  requireConnMetrics: Boolean,
  ensureExampleWindow: () -> Unit,
  marker: (String) -> Unit,
  dumpFailureArtifacts: (String) -> Unit,
) {
  var continuityBeforeReset: Triple<Long, Long, Long>? = null
  val deadline = System.currentTimeMillis() + SHORT_TIMEOUT_MS
  while (System.currentTimeMillis() < deadline) {
    ensureExampleWindow()
    val panelVisible = device.hasObject(By.res(PACKAGE_NAME, automationId(desc))) ||
      device.hasObject(By.desc(desc)) ||
      device.hasObject(By.descContains(desc))
    val metricsReady = !requireConnMetrics || device.hasObject(By.textContains("启动耗时"))
    val continuity = parseAudioContinuityMetrics(
      device.findObject(By.textContains("observed "))?.text.orEmpty(),
    )
    if (panelVisible && metricsReady && continuity != null && continuity.first > 0L) {
      continuityBeforeReset = continuity
      marker(markerName)
      marker(
        "client_audio_continuity_metrics_ok observed=${continuity.first} " +
          "accepted=${continuity.second} missing_ms=${continuity.third}",
      )
      break
    }
    Thread.sleep(750)
  }
  val before = continuityBeforeReset ?: run {
    marker("${markerName}_timeout")
    dumpFailureArtifacts(markerName)
    throw AssertionError("timed out waiting for diagnostics $desc with nonzero audio continuity metrics")
  }

  val reset = device.findObject(By.res(PACKAGE_NAME, automationId("TiRTC Downlink Metrics Reset")))
    ?: device.findObject(By.desc("TiRTC Downlink Metrics Reset"))
  if (reset == null) {
    dumpFailureArtifacts("client_audio_continuity_metrics_reset")
    throw AssertionError("missing metrics reset control")
  }
  reset.click()
  val resetDeadline = System.currentTimeMillis() + SHORT_TIMEOUT_MS
  while (System.currentTimeMillis() < resetDeadline) {
    val resetSucceeded = device.hasObject(By.textContains("区间指标已重置"))
    val after = parseAudioContinuityMetrics(
      device.findObject(By.textContains("observed "))?.text.orEmpty(),
    )
    if (
      resetSucceeded &&
      after != null &&
      after.first >= before.first &&
      after.second >= before.second &&
      after.third >= before.third
    ) {
      marker(
        "client_audio_continuity_metrics_reset_preserved_ok before_observed=${before.first} " +
          "after_observed=${after.first} after_accepted=${after.second} after_missing_ms=${after.third}",
      )
      return
    }
    Thread.sleep(250)
  }
  dumpFailureArtifacts("client_audio_continuity_metrics_reset")
  throw AssertionError("metrics reset cleared or failed to preserve audio continuity metrics")
}

private val AUDIO_CONTINUITY_PATTERN =
  Regex("observed (\\d+) .* accepted (\\d+) .* missing (\\d+) ms")

private fun parseAudioContinuityMetrics(text: String): Triple<Long, Long, Long>? {
  val match = AUDIO_CONTINUITY_PATTERN.find(text) ?: return null
  return Triple(
    match.groupValues[1].toLongOrNull() ?: return null,
    match.groupValues[2].toLongOrNull() ?: return null,
    match.groupValues[3].toLongOrNull() ?: return null,
  )
}
