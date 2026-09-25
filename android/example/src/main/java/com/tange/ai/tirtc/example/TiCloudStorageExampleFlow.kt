package com.tange.ai.tirtc.example

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.view.ViewGroup
import android.view.View
import android.view.Gravity
import android.widget.FrameLayout
import android.widget.GridLayout
import android.widget.TextView
import com.tange.ai.tirtc.TiCloudStorage
import com.tange.ai.tirtc.TiCloudStorageAudioOutput
import com.tange.ai.tirtc.TiCloudStorageAudioOutputState
import com.tange.ai.tirtc.TiCloudStorageAudioOutputStateListener
import com.tange.ai.tirtc.TiCloudStorageErrorCode
import com.tange.ai.tirtc.TiCloudStorageExportProgress
import com.tange.ai.tirtc.TiCloudStorageExportReport
import com.tange.ai.tirtc.TiCloudStorageExportRequest
import com.tange.ai.tirtc.TiCloudStorageExportTask
import com.tange.ai.tirtc.TiCloudStorageOutputErrorListener
import com.tange.ai.tirtc.TiCloudStorageRecordingDaysResult
import com.tange.ai.tirtc.TiCloudStorageRecordingFile
import com.tange.ai.tirtc.TiCloudStorageRecordingGap
import com.tange.ai.tirtc.TiCloudStorageRecordingRange
import com.tange.ai.tirtc.TiCloudStorageRecordingRangesResult
import com.tange.ai.tirtc.TiCloudStorageRecordingTask
import com.tange.ai.tirtc.TiCloudStorageReplay
import com.tange.ai.tirtc.TiCloudStorageReplayCompletedListener
import com.tange.ai.tirtc.TiCloudStorageReplayErrorListener
import com.tange.ai.tirtc.TiCloudStorageReplaySpeed
import com.tange.ai.tirtc.TiCloudStorageRawDumpOptions
import com.tange.ai.tirtc.TiRawDumpStartCallback
import com.tange.ai.tirtc.TiCloudStorageSnapshotFile
import com.tange.ai.tirtc.TiCloudStorageTimeChangedListener
import com.tange.ai.tirtc.TiCloudStorageVideoOutput
import com.tange.ai.tirtc.TiCloudStorageVideoOutputState
import com.tange.ai.tirtc.TiCloudStorageVideoOutputStateListener
import java.util.Locale
import java.io.File
import kotlin.concurrent.thread

internal fun copyPathToGallery(
    context: Context,
    sourcePath: String,
    isVideo: Boolean,
    targetId: Int,
): Int {
    val source = File(sourcePath)
    if (!source.isFile) return TiCloudStorageErrorCode.FILE_WRITE_FAILED
    val resolver = context.contentResolver
    val collection =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            if (isVideo) {
                MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            } else {
                MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            }
        } else if (isVideo) {
            MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        } else {
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        }
    val values =
        ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, "${source.nameWithoutExtension}-channel-$targetId.${source.extension}")
            put(MediaStore.MediaColumns.MIME_TYPE, if (isVideo) "video/mp4" else "image/jpeg")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(
                    MediaStore.MediaColumns.RELATIVE_PATH,
                    if (isVideo) Environment.DIRECTORY_MOVIES else Environment.DIRECTORY_PICTURES,
                )
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
        }
    return try {
        val uri = resolver.insert(collection, values) ?: return TiCloudStorageErrorCode.FILE_WRITE_FAILED
        try {
            resolver.openOutputStream(uri)?.use { output -> source.inputStream().use { it.copyTo(output) } }
                ?: throw IllegalStateException("gallery output unavailable")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                resolver.update(
                    uri,
                    ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) },
                    null,
                    null,
                )
            }
            TiCloudStorageErrorCode.OK
        } catch (_: Throwable) {
            resolver.delete(uri, null, null)
            TiCloudStorageErrorCode.FILE_WRITE_FAILED
        }
    } catch (_: Throwable) {
        TiCloudStorageErrorCode.FILE_WRITE_FAILED
    }
}

/** Public-SDK-only Ti Cloud Storage flow used by the Android Example. */
internal class TiCloudStorageExampleFlow {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var context: Context? = null
    private var initialized = false
    private var cloudStorage: TiCloudStorage? = null
    private var replay: TiCloudStorageReplay? = null
    private var audio: TiCloudStorageAudioOutput? = null
    private val videos = linkedMapOf<Int, TiCloudStorageVideoOutput>()
    private val attachedVideoChannels = mutableSetOf<Int>()
    private val videoLanes = linkedMapOf<Int, FrameLayout>()
    private var selectedVideoChannel: Int? = null
    private var maximizedVideoChannel: Int? = null
    private var recordingTask: TiCloudStorageRecordingTask? = null
    private var recordingTargetChannel: Int? = null
    private var exportTask: TiCloudStorageExportTask? = null
    private var latestMedia: OwnedMedia? = null
    private val ownedMedia = mutableListOf<OwnedMedia>()
    private var replayOutputsCompletionReported = false
    private var cleanupError = TiCloudStorageErrorCode.OK
    private var pendingOperations = 0
    private var closing = false
    private var closeDeadlineMs = 0L
    private val closeCallbacks = mutableListOf<(Int) -> Unit>()

    var paused = false
        private set
    var muted = false
        private set
    var onTimeChanged: ((Long) -> Unit)? = null
    var onReplayCompleted: (() -> Unit)? = null
    var onVideoStateChanged: ((Int, TiCloudStorageVideoOutputState) -> Unit)? = null
    var onAudioStateChanged: ((TiCloudStorageAudioOutputState) -> Unit)? = null
    var onError: ((Int) -> Unit)? = null

    val currentTimeMs: Long?
        get() = replay?.currentTimeMs
    val speed: TiCloudStorageReplaySpeed
        get() = replay?.speed ?: TiCloudStorageReplaySpeed.X1
    val videoState: TiCloudStorageVideoOutputState
        get() = selectedVideoChannel?.let(videos::get)?.state ?: TiCloudStorageVideoOutputState.IDLE
    val selectedVideoChannelId: Int?
        get() = selectedVideoChannel
    val isRecording: Boolean
        get() = recordingTask != null
    val isExporting: Boolean
        get() = exportTask != null
    val hasLatestMedia: Boolean
        get() = latestMedia != null

    fun initialize(
        context: Context,
        appId: String,
        endpoint: String,
        token: String,
        consoleLogEnabled: Boolean,
    ): Int {
        if (closing || initialized) return TiCloudStorageErrorCode.IN_USE
        val code = TiCloudStorage.init(context, appId, endpoint, consoleLogEnabled)
        if (code != TiCloudStorageErrorCode.OK) return code
        this.context = context.applicationContext
        initialized = true
        cloudStorage = TiCloudStorage(token)
        return TiCloudStorageErrorCode.OK
    }

    fun query(
        startMs: Long,
        endMs: Long,
        callback: (TiCloudStorageRecordingRangesResult) -> Unit,
    ): Int {
        val owner = cloudStorage ?: return TiCloudStorageErrorCode.NOT_INITIALIZED
        if (closing) return TiCloudStorageErrorCode.IN_USE
        beginOperation()
        owner.listRecordings(startMs, endMs) { result ->
            callback(result)
            endOperation()
        }
        return TiCloudStorageErrorCode.OK
    }

    fun queryDays(
        startDate: String,
        endDate: String,
        timeZoneId: String = "Asia/Shanghai",
        callback: (TiCloudStorageRecordingDaysResult) -> Unit,
    ): Int {
        val owner = cloudStorage ?: return TiCloudStorageErrorCode.NOT_INITIALIZED
        if (closing) return TiCloudStorageErrorCode.IN_USE
        beginOperation()
        owner.listRecordingDays(startDate, endDate, timeZoneId) { result ->
            callback(result)
            endOperation()
        }
        return TiCloudStorageErrorCode.OK
    }

    fun play(
        range: TiCloudStorageRecordingRange,
        stage: ViewGroup,
        videoChannels: List<Int>,
        audioChannel: Int?,
    ): Int {
        if (closing) return TiCloudStorageErrorCode.IN_USE
        val owner = cloudStorage ?: return TiCloudStorageErrorCode.NOT_INITIALIZED
        var activeReplay = replay
        if (activeReplay == null) {
            activeReplay = owner.createReplay()
            val activeVideos = videoChannels.associateWithTo(linkedMapOf()) { TiCloudStorageVideoOutput() }
            val activeAudio = audioChannel?.let { TiCloudStorageAudioOutput() }
            fun notifyIfOutputsCompleted() {
                if (replayOutputsCompletionReported) return
                val videosCompleted = activeVideos.values.all { it.state == TiCloudStorageVideoOutputState.COMPLETED }
                val audioCompleted = activeAudio == null || activeAudio.state == TiCloudStorageAudioOutputState.COMPLETED
                if (videosCompleted && audioCompleted) {
                    replayOutputsCompletionReported = true
                    onReplayCompleted?.invoke()
                }
            }
            activeReplay.onTimeChanged = TiCloudStorageTimeChangedListener { time -> onTimeChanged?.invoke(time) }
            activeReplay.onCompleted = TiCloudStorageReplayCompletedListener { }
            activeReplay.onError = TiCloudStorageReplayErrorListener { code -> onError?.invoke(code) }
            activeAudio?.onStateChanged = TiCloudStorageAudioOutputStateListener { state ->
                onAudioStateChanged?.invoke(state)
                notifyIfOutputsCompleted()
            }
            activeAudio?.onError = TiCloudStorageOutputErrorListener {
                onAudioStateChanged?.invoke(TiCloudStorageAudioOutputState.FAILED)
            }
            stage.removeAllViews()
            val grid = GridLayout(stage.context).apply {
                columnCount = 1
                rowCount = 1
            }
            stage.addView(grid, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
            var code = TiCloudStorageErrorCode.OK
            var firstVideoError = TiCloudStorageErrorCode.OK
            val attached = mutableListOf<TiCloudStorageVideoOutput>()
            activeVideos.forEach { (channelId, activeVideo) ->
                val lane = FrameLayout(stage.context).apply {
                    contentDescription = "cloud_storage_video_lane_$channelId state=idle"
                    setBackgroundColor(0xFF101817.toInt())
                    setOnClickListener {
                        maximizedVideoChannel =
                            if (selectedVideoChannel == channelId && maximizedVideoChannel == null) channelId else null
                        selectedVideoChannel = channelId
                        layoutVideoMosaic(
                            grid,
                            videoChannels,
                            videoLanes,
                            selectedVideoChannel,
                            maximizedVideoChannel,
                            stage.resources.configuration.screenWidthDp >= ExampleTheme.compactBreakpointDp,
                        )
                    }
                }
                val index = videoChannels.indexOf(channelId)
                grid.addView(
                    lane,
                    GridLayout.LayoutParams().apply { width = 0; height = 0 },
                )
                videoLanes[channelId] = lane
                val stateLabel = TextView(stage.context).apply {
                    text = "视频 ${index + 1} · Channel $channelId\n等待视频"
                    setTextColor(0xFFFFFFFF.toInt())
                    setBackgroundColor(0x99000000.toInt())
                    setPadding(12, 8, 12, 8)
                }
                activeVideo.onStateChanged =
                    TiCloudStorageVideoOutputStateListener { state ->
                        stateLabel.text = "视频 ${index + 1} · Channel $channelId\n${state.name.lowercase(Locale.ROOT)}"
                        lane.contentDescription =
                            "cloud_storage_video_lane_$channelId state=${state.name.lowercase(Locale.ROOT)}"
                        onVideoStateChanged?.invoke(channelId, state)
                        notifyIfOutputsCompleted()
                    }
                activeVideo.onError = TiCloudStorageOutputErrorListener { error ->
                    stateLabel.text = "视频 ${index + 1} · Channel $channelId\n播放失败 · $error"
                    lane.contentDescription = "cloud_storage_video_lane_$channelId state=failed"
                    onVideoStateChanged?.invoke(channelId, TiCloudStorageVideoOutputState.FAILED)
                }
                val viewCode = activeVideo.attachView(lane)
                var laneCode = viewCode
                if (laneCode == TiCloudStorageErrorCode.OK) laneCode = activeVideo.attach(activeReplay, channelId)
                if (laneCode == TiCloudStorageErrorCode.OK) {
                    attached += activeVideo
                    attachedVideoChannels += channelId
                } else {
                    if (firstVideoError == TiCloudStorageErrorCode.OK) firstVideoError = laneCode
                    stateLabel.text = "视频 ${index + 1} · Channel $channelId\n播放失败"
                    lane.contentDescription = "cloud_storage_video_lane_$channelId state=failed"
                    onVideoStateChanged?.invoke(channelId, TiCloudStorageVideoOutputState.FAILED)
                }
                if (viewCode == TiCloudStorageErrorCode.OK && laneCode != TiCloudStorageErrorCode.OK) {
                    activeVideo.detachView()
                }
                lane.addView(
                    stateLabel,
                    FrameLayout.LayoutParams(
                        FrameLayout.LayoutParams.WRAP_CONTENT,
                        FrameLayout.LayoutParams.WRAP_CONTENT,
                        Gravity.TOP or Gravity.START,
                    ),
                )
            }
            var audioAttached = false
            if (activeAudio != null) {
                code = activeAudio.attach(activeReplay, audioChannel!!)
                audioAttached = code == TiCloudStorageErrorCode.OK
                if (!audioAttached) onAudioStateChanged?.invoke(TiCloudStorageAudioOutputState.FAILED)
            }
            if (attached.isNotEmpty()) code = TiCloudStorageErrorCode.OK
            if (attached.isEmpty() && !audioAttached) {
                code = when {
                    code != TiCloudStorageErrorCode.OK -> code
                    firstVideoError != TiCloudStorageErrorCode.OK -> firstVideoError
                    else -> TiCloudStorageErrorCode.INVALID_ARGUMENT
                }
            }
            if (code != TiCloudStorageErrorCode.OK) {
                if (audioAttached) activeAudio?.detach()
                attached.forEach {
                    it.detach()
                    it.detachView()
                }
                attachedVideoChannels.clear()
                activeAudio?.dispose()
                activeVideos.values.forEach(TiCloudStorageVideoOutput::dispose)
                activeReplay.dispose()
                return code
            }
            if (!audioAttached) activeAudio?.dispose()
            replay = activeReplay
            videos.putAll(activeVideos)
            selectedVideoChannel = videoChannels.firstOrNull()
            layoutVideoMosaic(
                grid,
                videoChannels,
                videoLanes,
                selectedVideoChannel,
                maximizedVideoChannel,
                stage.resources.configuration.screenWidthDp >= ExampleTheme.compactBreakpointDp,
            )
            audio = if (audioAttached) activeAudio else null
        }
        replayOutputsCompletionReported = false
        val code = activeReplay.play(range.startTimeMs, range.endTimeMs)
        if (code == TiCloudStorageErrorCode.OK) paused = false
        return code
    }

    fun pause(): Int {
        val active = replay ?: return TiCloudStorageErrorCode.NOT_STARTED
        return active.pause().also { code ->
            if (code == TiCloudStorageErrorCode.OK) paused = true
        }
    }

    fun resume(): Int {
        val active = replay ?: return TiCloudStorageErrorCode.NOT_STARTED
        return active.resume().also { code ->
            if (code == TiCloudStorageErrorCode.OK) paused = false
        }
    }

    fun seek(timeMs: Long): Int = replay?.seek(timeMs) ?: TiCloudStorageErrorCode.NOT_STARTED

    fun setSpeed(next: TiCloudStorageReplaySpeed): Int = replay?.setSpeed(next) ?: TiCloudStorageErrorCode.NOT_STARTED

    fun startRawDump(
        audioChannelId: Int?,
        videoChannelIds: List<Int>,
        callback: TiRawDumpStartCallback,
    ): Boolean {
        val activeReplay = replay ?: return false
        activeReplay.startRawDump(
            TiCloudStorageRawDumpOptions(
                audioChannelIds = audioChannelId?.let { intArrayOf(it) } ?: intArrayOf(),
                videoChannelIds = videoChannelIds.toIntArray(),
            ),
            callback,
        )
        return true
    }

    fun toggleMute(): Int {
        val output = audio ?: return TiCloudStorageErrorCode.NOT_STARTED
        val next = !muted
        return output.setVolume(if (next) 0 else 100).also { code ->
            if (code == TiCloudStorageErrorCode.OK) muted = next
        }
    }

    fun takeSnapshot(videoChannel: Int, callback: (Int, String?) -> Unit): Int {
        val output = videos[videoChannel] ?: return TiCloudStorageErrorCode.NOT_STARTED
        if (closing) return TiCloudStorageErrorCode.IN_USE
        beginOperation()
        output.takeSnapshot { result ->
            val file = result.file
            if (result.code != TiCloudStorageErrorCode.OK || file == null) {
                callback(result.code, null)
                endOperation()
                return@takeSnapshot
            }
            replaceLatest(SnapshotMedia(file, videoChannel)) { code ->
                callback(code, if (code == TiCloudStorageErrorCode.OK) file.path else null)
                endOperation()
            }
        }
        return TiCloudStorageErrorCode.OK
    }

    fun toggleRecording(
        videoChannel: Int,
        audioChannel: Int?,
        callback: (started: Boolean, code: Int, path: String?) -> Unit,
    ): Int {
        val active = recordingTask
        if (active == null) {
            val activeReplay = replay ?: return TiCloudStorageErrorCode.NOT_STARTED
            if (closing) return TiCloudStorageErrorCode.IN_USE
            val result = activeReplay.startRecording(videoChannel, audioChannel)
            if (result.code == TiCloudStorageErrorCode.OK) {
                recordingTask = result.task
                recordingTargetChannel = videoChannel
            }
            callback(result.code == TiCloudStorageErrorCode.OK, result.code, null)
            return result.code
        }
        recordingTask = null
        val recordingTarget = recordingTargetChannel ?: videoChannel
        recordingTargetChannel = null
        beginOperation()
        active.stop { result ->
            val file = result.file
            if (result.code != TiCloudStorageErrorCode.OK || file == null) {
                callback(false, result.code, null)
                endOperation()
                return@stop
            }
            if (closing) {
                RecordingMedia(file, recordingTarget).delete { code ->
                    callback(false, code, null)
                    endOperation()
                }
            } else {
                replaceLatest(RecordingMedia(file, recordingTarget)) { code ->
                    callback(false, code, if (code == TiCloudStorageErrorCode.OK) file.path else null)
                    endOperation()
                }
            }
        }
        return TiCloudStorageErrorCode.OK
    }

    fun export(
        range: TiCloudStorageRecordingRange,
        videoChannel: Int,
        audioChannel: Int?,
        onProgress: (Double) -> Unit,
        onProgressDetail: (TiCloudStorageExportProgress) -> Unit,
        onRecordingGap: (TiCloudStorageRecordingGap) -> Unit,
        callback: (Int, String?, TiCloudStorageExportReport?) -> Unit,
    ): Int {
        val owner = cloudStorage ?: return TiCloudStorageErrorCode.NOT_INITIALIZED
        if (closing || exportTask != null) return TiCloudStorageErrorCode.IN_USE
        beginOperation()
        val started =
            owner.exportRecording(
                TiCloudStorageExportRequest(range.startTimeMs, range.endTimeMs, videoChannel, audioChannel),
                { progress -> onProgress(progress) },
                { progress -> onProgressDetail(progress) },
                { gap -> onRecordingGap(gap) },
            ) { result ->
                exportTask = null
                val file = result.file
                if (result.code != TiCloudStorageErrorCode.OK || file == null) {
                    callback(result.code, null, result.report)
                    endOperation()
                    return@exportRecording
                }
                if (closing) {
                    RecordingMedia(file, videoChannel).delete { code ->
                        callback(code, null, result.report)
                        endOperation()
                    }
                } else {
                    replaceLatest(RecordingMedia(file, videoChannel)) { code ->
                        callback(code, if (code == TiCloudStorageErrorCode.OK) file.path else null, result.report)
                        endOperation()
                    }
                }
            }
        exportTask = started.task
        if (started.code != TiCloudStorageErrorCode.OK || started.task == null) {
            exportTask = null
            endOperation()
        }
        return started.code
    }

    fun saveLatestToGallery(callback: (Int) -> Unit): Int {
        val ownerContext = context ?: return TiCloudStorageErrorCode.NOT_INITIALIZED
        val media = latestMedia ?: return TiCloudStorageErrorCode.NOT_STARTED
        if (closing) return TiCloudStorageErrorCode.IN_USE
        val publishRequired = shouldPublishToGallery(media.galleryPublishState)
        beginOperation()
        thread(name = "ti-cloud-storage-example-gallery", isDaemon = true) {
            val copyCode = if (publishRequired) copyToGallery(ownerContext, media) else TiCloudStorageErrorCode.OK
            mainHandler.post {
                if (copyCode != TiCloudStorageErrorCode.OK) {
                    callback(copyCode)
                    endOperation()
                    return@post
                }
                media.galleryPublishState = GalleryPublishState.PUBLISHED_PENDING_DELETE
                media.delete { deleteCode ->
                    if (deleteCode == TiCloudStorageErrorCode.OK) {
                        if (latestMedia === media) latestMedia = null
                        ownedMedia.remove(media)
                    }
                    callback(deleteCode)
                    endOperation()
                }
            }
        }
        return TiCloudStorageErrorCode.OK
    }

    fun close(callback: (Int) -> Unit = {}) {
        closeCallbacks += callback
        if (closing) return
        closing = true
        cleanupError = TiCloudStorageErrorCode.OK
        closeDeadlineMs = android.os.SystemClock.uptimeMillis() + CLOSE_RETRY_MS
        val activeRecording = recordingTask
        if (activeRecording != null) {
            recordingTask = null
            val recordingTarget = recordingTargetChannel ?: 0
            recordingTargetChannel = null
            beginOperation()
            activeRecording.stop { result ->
                val media = result.file?.let { file -> RecordingMedia(file, recordingTarget) }
                if (media == null) {
                    endOperation()
                } else {
                    media.delete { code ->
                        captureCleanupError(code)
                        endOperation()
                    }
                }
            }
        }
        exportTask?.stop()
        continueClose()
    }

    private fun beginOperation() {
        pendingOperations += 1
    }

    private fun endOperation() {
        pendingOperations = (pendingOperations - 1).coerceAtLeast(0)
        if (closing) continueClose()
    }

    private fun replaceLatest(
        next: OwnedMedia,
        callback: (Int) -> Unit,
    ) {
        val previous = latestMedia
        latestMedia = next
        if (ownedMedia.none { it.path == next.path }) ownedMedia += next
        if (previous == null || previous.path == next.path) {
            callback(TiCloudStorageErrorCode.OK)
            return
        }
        previous.delete { code ->
            if (code == TiCloudStorageErrorCode.OK) ownedMedia.remove(previous)
            callback(code)
        }
    }

    private fun continueClose() {
        if (!closing || pendingOperations != 0) return
        val media = ownedMedia.firstOrNull()
        if (media != null) {
            if (latestMedia === media) latestMedia = null
            beginOperation()
            media.delete { code ->
                ownedMedia.remove(media)
                if (code != TiCloudStorageErrorCode.OK) captureCleanupError(code)
                endOperation()
            }
            return
        }
        val code = releaseOnce()
        if (code == TiCloudStorageErrorCode.IN_USE && android.os.SystemClock.uptimeMillis() < closeDeadlineMs) {
            mainHandler.post(::continueClose)
            return
        }
        finishClose(if (cleanupError != TiCloudStorageErrorCode.OK) cleanupError else code)
    }

    private fun captureCleanupError(code: Int) {
        if (code != TiCloudStorageErrorCode.OK && cleanupError == TiCloudStorageErrorCode.OK) cleanupError = code
    }

    private fun releaseOnce(): Int {
        var firstError = TiCloudStorageErrorCode.OK

        fun capture(code: Int) {
            if (code == TiCloudStorageErrorCode.OK ||
                code == TiCloudStorageErrorCode.NOT_STARTED ||
                code == TiCloudStorageErrorCode.NOT_BOUND
            ) {
                return
            }
            if (firstError == TiCloudStorageErrorCode.OK || code == TiCloudStorageErrorCode.IN_USE) firstError = code
        }
        capture(replay?.stop() ?: TiCloudStorageErrorCode.OK)
        capture(audio?.detach() ?: TiCloudStorageErrorCode.OK)
        videos.forEach { (channelId, output) ->
            if (attachedVideoChannels.contains(channelId)) {
                capture(output.detach())
                capture(output.detachView())
            }
        }
        audio?.let { output ->
            val code = output.dispose()
            capture(code)
            if (code == TiCloudStorageErrorCode.OK) audio = null
        }
        videos.entries.toList().forEach { (channelId, output) ->
            val code = output.dispose()
            capture(code)
            if (code == TiCloudStorageErrorCode.OK) {
                videos.remove(channelId)
                attachedVideoChannels.remove(channelId)
            }
        }
        if (videos.isEmpty()) {
            videoLanes.clear()
            selectedVideoChannel = null
            maximizedVideoChannel = null
        }
        replay?.let { active ->
            val code = active.dispose()
            capture(code)
            if (code == TiCloudStorageErrorCode.OK) replay = null
        }
        cloudStorage?.let { owner ->
            val code = owner.dispose()
            capture(code)
            if (code == TiCloudStorageErrorCode.OK) cloudStorage = null
        }
        if (cloudStorage == null && replay == null && audio == null && videos.isEmpty() && initialized) {
            val code = TiCloudStorage.shutdown()
            capture(code)
            if (code == TiCloudStorageErrorCode.OK) initialized = false
        }
        return firstError
    }

    private fun finishClose(code: Int) {
        closing = false
        onTimeChanged = null
        onReplayCompleted = null
        onVideoStateChanged = null
        onAudioStateChanged = null
        onError = null
        val callbacks = closeCallbacks.toList()
        closeCallbacks.clear()
        callbacks.forEach { it(code) }
    }

    private fun copyToGallery(
        context: Context,
        media: OwnedMedia,
    ): Int = copyPathToGallery(context, media.path, media is RecordingMedia, media.targetId)

    private sealed class OwnedMedia(val path: String, val targetId: Int) {
        var galleryPublishState = GalleryPublishState.NEEDS_PUBLISH
        abstract fun delete(callback: (Int) -> Unit)
    }

    private class RecordingMedia(private val file: TiCloudStorageRecordingFile, targetId: Int) :
        OwnedMedia(file.path, targetId) {
        override fun delete(callback: (Int) -> Unit) = file.delete { code -> callback(code) }
    }

    private class SnapshotMedia(private val file: TiCloudStorageSnapshotFile, targetId: Int) :
        OwnedMedia(file.path, targetId) {
        override fun delete(callback: (Int) -> Unit) = file.delete { code -> callback(code) }
    }

    private companion object {
        private const val CLOSE_RETRY_MS = 1000L
    }
}
