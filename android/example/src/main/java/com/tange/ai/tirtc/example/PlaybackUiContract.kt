package com.tange.ai.tirtc.example

internal data class MosaicCell(
    val id: Int,
    val row: Int,
    val rowSpan: Int,
    val column: Int,
    val columnSpan: Int,
    val visible: Boolean,
    val primary: Boolean,
)

internal fun videoMosaicCells(
    orderedIds: List<Int>,
    selectedId: Int?,
    maximizedId: Int?,
    wide: Boolean,
): List<MosaicCell> {
    val primaryId = selectedId?.takeIf(orderedIds::contains) ?: orderedIds.firstOrNull()
    val secondaryIds = orderedIds.filter { it != primaryId }
    return orderedIds.map { id ->
        val visible = maximizedId == null || id == maximizedId
        when {
            maximizedId != null || orderedIds.size <= 1 -> MosaicCell(id, 0, 1, 0, 1, visible, id == primaryId)
            orderedIds.size == 2 && !wide -> MosaicCell(id, orderedIds.indexOf(id), 1, 0, 1, true, id == primaryId)
            orderedIds.size == 2 -> MosaicCell(id, 0, 1, orderedIds.indexOf(id), 1, true, id == primaryId)
            id == primaryId -> MosaicCell(id, 0, 2, 0, 1, true, true)
            else -> MosaicCell(id, secondaryIds.indexOf(id), 1, 1, 1, true, false)
        }
    }
}

internal data class PlaybackActionState(
    val selectedVideoReady: Boolean = false,
    val recording: Boolean = false,
    val latestMediaAvailable: Boolean = false,
    val busy: Boolean = false,
    val playing: Boolean = false,
)

internal enum class PlaybackMediaAction { RECORDING, SNAPSHOT, GALLERY }

internal fun rtcActionEnabled(action: PlaybackMediaAction, state: PlaybackActionState): Boolean =
    when (action) {
        PlaybackMediaAction.RECORDING -> !state.busy && (state.recording || state.selectedVideoReady)
        PlaybackMediaAction.SNAPSHOT -> state.selectedVideoReady && !state.busy
        PlaybackMediaAction.GALLERY -> state.latestMediaAvailable && !state.busy
    }

internal fun cloudActionEnabled(action: PlaybackMediaAction, state: PlaybackActionState): Boolean =
    when (action) {
        PlaybackMediaAction.RECORDING -> !state.busy && (state.recording || state.playing && state.selectedVideoReady)
        PlaybackMediaAction.SNAPSHOT -> state.playing && state.selectedVideoReady && !state.busy
        PlaybackMediaAction.GALLERY -> state.latestMediaAvailable && !state.busy
    }

internal const val COMPACT_CLOUD_CONTROLS_HEIGHT_DP = 112
internal const val PLAYBACK_TOUCH_TARGET_DP = 48
internal const val RAW_DUMP_BUTTON_SIZE_DP = 56
internal const val RAW_DUMP_BUTTON_LEFT_INSET_DP = 12
internal val RAW_DUMP_BUTTON_LABELS =
    setOf("抓数据", "准备中", "结束上传", "打包中", "重试结束", "上传数据", "上传中", "重试上传", "重新抓取")

internal fun calendarDayText(day: Int, available: Boolean): String = "$day\n${if (available) "●" else "○"}"

internal fun calendarDayDescription(
    date: String,
    available: Boolean,
    selected: Boolean,
): String = "$date，${if (available) "有录像" else "无录像"}${if (selected) "，已选择" else ""}"

internal fun dispatchPlaybackAction(
    enabled: () -> Boolean,
    unavailableMessage: String,
    showUnavailable: (String) -> Unit,
    dispatch: () -> Unit,
): Boolean {
    if (!enabled()) {
        showUnavailable(unavailableMessage)
        return false
    }
    dispatch()
    return true
}
