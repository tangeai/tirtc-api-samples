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
  val deadline = System.currentTimeMillis() + SHORT_TIMEOUT_MS
  while (System.currentTimeMillis() < deadline) {
    ensureExampleWindow()
    val panelVisible = device.hasObject(By.res(PACKAGE_NAME, automationId(desc))) ||
      device.hasObject(By.desc(desc)) ||
      device.hasObject(By.descContains(desc))
    val metricsReady = !requireConnMetrics || device.hasObject(By.textContains("启动耗时"))
    if (panelVisible && metricsReady) {
      marker(markerName)
      return
    }
    Thread.sleep(750)
  }
  marker("${markerName}_timeout")
  dumpFailureArtifacts(markerName)
  throw AssertionError("timed out waiting for diagnostics $desc")
}
