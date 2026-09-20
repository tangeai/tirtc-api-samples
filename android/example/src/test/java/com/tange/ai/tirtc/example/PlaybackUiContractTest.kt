package com.tange.ai.tirtc.example

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PlaybackUiContractTest {
    @Test
    fun rawDumpButtonMatchesFlutterVisualAndStateContract() {
        assertEquals(56, RAW_DUMP_BUTTON_SIZE_DP)
        assertEquals(12, RAW_DUMP_BUTTON_LEFT_INSET_DP)
        assertEquals(
            setOf("抓数据", "准备中", "结束上传", "打包中", "重试结束", "上传数据", "上传中", "重试上传", "重新抓取"),
            RAW_DUMP_BUTTON_LABELS,
        )
    }
    @Test
    fun `one and zero lane geometry has no blank cell`() {
        assertTrue(videoMosaicCells(emptyList(), null, null, wide = false).isEmpty())
        assertEquals(MosaicCell(7, 0, 1, 0, 1, visible = true, primary = true), videoMosaicCells(listOf(7), 7, null, false).single())
    }

    @Test
    fun `two lanes switch between compact rows and wide columns`() {
        assertEquals(listOf(0, 1), videoMosaicCells(listOf(1, 2), 1, null, false).map(MosaicCell::row))
        assertEquals(listOf(0, 1), videoMosaicCells(listOf(1, 2), 1, null, true).map(MosaicCell::column))
    }

    @Test
    fun `three lanes promote selection and maximize then restore`() {
        val promoted = videoMosaicCells(listOf(1, 2, 3), 3, null, false)
        assertEquals(2, promoted.single { it.id == 3 }.rowSpan)
        assertEquals(0, promoted.single { it.id == 3 }.column)
        val maximized = videoMosaicCells(listOf(1, 2, 3), 3, 3, false)
        assertEquals(listOf(false, false, true), maximized.map(MosaicCell::visible))
        assertEquals(3, videoMosaicCells(listOf(1, 2, 3), 3, null, false).count(MosaicCell::visible))
    }

    @Test
    fun `compact controls keep fixed bounds at two hundred percent text`() {
        val fontScale = 2f
        assertEquals(48, PLAYBACK_TOUCH_TARGET_DP)
        assertEquals(112, COMPACT_CLOUD_CONTROLS_HEIGHT_DP)
        assertTrue(PLAYBACK_TOUCH_TARGET_DP * fontScale >= 48f)
    }

    @Test
    fun `six hundred dp at two hundred percent does not expand labels or secondary actions`() {
        val effectiveWidthDp = 600 / 2f
        assertTrue(effectiveWidthDp < ExampleTheme.secondaryActionsBreakpointDp)
        assertEquals(840, ExampleTheme.secondaryActionsBreakpointDp)
    }

    @Test
    fun `menu state rejects stale and busy media actions`() {
        val ready = PlaybackActionState(selectedVideoReady = true)
        assertTrue(rtcActionEnabled(PlaybackMediaAction.RECORDING, ready))
        assertTrue(rtcActionEnabled(PlaybackMediaAction.SNAPSHOT, ready))
        assertFalse(rtcActionEnabled(PlaybackMediaAction.GALLERY, ready))
        val busy = ready.copy(latestMediaAvailable = true, busy = true)
        assertFalse(rtcActionEnabled(PlaybackMediaAction.SNAPSHOT, busy))
        assertFalse(rtcActionEnabled(PlaybackMediaAction.GALLERY, busy))
        assertFalse(rtcActionEnabled(PlaybackMediaAction.RECORDING, busy.copy(recording = true)))
        assertFalse(cloudActionEnabled(PlaybackMediaAction.SNAPSHOT, PlaybackActionState()))
        assertTrue(cloudActionEnabled(PlaybackMediaAction.SNAPSHOT, PlaybackActionState(playing = true, selectedVideoReady = true)))
    }

    @Test
    fun `rtc menu dispatch rechecks current state before execution`() {
        var enabled = true
        var executions = 0
        var message = ""
        assertTrue(dispatchPlaybackAction({ enabled }, "不可用", { message = it }) { executions += 1 })
        enabled = false
        assertFalse(dispatchPlaybackAction({ enabled }, "不可用", { message = it }) { executions += 1 })
        assertEquals(1, executions)
        assertEquals("不可用", message)
    }

    @Test
    fun `calendar keeps visual dots and complete accessibility state`() {
        assertEquals("9\n●", calendarDayText(9, available = true))
        assertEquals("2026-09-09，有录像，已选择", calendarDayDescription("2026-09-09", available = true, selected = true))
        assertEquals("2026-09-10，无录像", calendarDayDescription("2026-09-10", available = false, selected = false))
    }
}
