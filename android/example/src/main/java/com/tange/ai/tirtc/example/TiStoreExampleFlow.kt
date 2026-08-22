package com.tange.ai.tirtc.example

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.view.ViewGroup
import com.tange.ai.tirtc.TiStore
import com.tange.ai.tirtc.TiStoreAudioOutput
import com.tange.ai.tirtc.TiStoreAudioOutputState
import com.tange.ai.tirtc.TiStoreAudioOutputStateListener
import com.tange.ai.tirtc.TiStoreErrorCode
import com.tange.ai.tirtc.TiStoreExportRequest
import com.tange.ai.tirtc.TiStoreExportTask
import com.tange.ai.tirtc.TiStoreOutputErrorListener
import com.tange.ai.tirtc.TiStoreRecordingFile
import com.tange.ai.tirtc.TiStoreRecordingDaysResult
import com.tange.ai.tirtc.TiStoreRecordingRange
import com.tange.ai.tirtc.TiStoreRecordingRangesResult
import com.tange.ai.tirtc.TiStoreRecordingTask
import com.tange.ai.tirtc.TiStoreReplay
import com.tange.ai.tirtc.TiStoreReplayCompletedListener
import com.tange.ai.tirtc.TiStoreReplayErrorListener
import com.tange.ai.tirtc.TiStoreReplaySpeed
import com.tange.ai.tirtc.TiStoreSnapshotFile
import com.tange.ai.tirtc.TiStoreTimeChangedListener
import com.tange.ai.tirtc.TiStoreVideoOutput
import com.tange.ai.tirtc.TiStoreVideoOutputState
import com.tange.ai.tirtc.TiStoreVideoOutputStateListener
import java.io.File
import kotlin.concurrent.thread

internal fun copyPathToGallery(
    context: Context,
    sourcePath: String,
    isVideo: Boolean,
): Int {
    val source = File(sourcePath)
    if (!source.isFile) return TiStoreErrorCode.FILE_WRITE_FAILED
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
            put(MediaStore.MediaColumns.DISPLAY_NAME, source.name)
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
        val uri = resolver.insert(collection, values) ?: return TiStoreErrorCode.FILE_WRITE_FAILED
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
            TiStoreErrorCode.OK
        } catch (_: Throwable) {
            resolver.delete(uri, null, null)
            TiStoreErrorCode.FILE_WRITE_FAILED
        }
    } catch (_: Throwable) {
        TiStoreErrorCode.FILE_WRITE_FAILED
    }
}

/** Public-SDK-only TiStore flow used by the Android Example. */
internal class TiStoreExampleFlow {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var context: Context? = null
    private var initialized = false
    private var store: TiStore? = null
    private var replay: TiStoreReplay? = null
    private var audio: TiStoreAudioOutput? = null
    private var video: TiStoreVideoOutput? = null
    private var recordingTask: TiStoreRecordingTask? = null
    private var exportTask: TiStoreExportTask? = null
    private var latestMedia: OwnedMedia? = null
    private val ownedMedia = mutableListOf<OwnedMedia>()
    private var cleanupError = TiStoreErrorCode.OK
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
    var onVideoStateChanged: ((TiStoreVideoOutputState) -> Unit)? = null
    var onAudioStateChanged: ((TiStoreAudioOutputState) -> Unit)? = null
    var onError: ((Int) -> Unit)? = null

    val currentTimeMs: Long?
        get() = replay?.currentTimeMs
    val speed: TiStoreReplaySpeed
        get() = replay?.speed ?: TiStoreReplaySpeed.X1
    val videoState: TiStoreVideoOutputState
        get() = video?.state ?: TiStoreVideoOutputState.IDLE
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
    ): Int {
        if (closing || initialized) return TiStoreErrorCode.IN_USE
        val code = TiStore.init(context, appId, endpoint)
        if (code != TiStoreErrorCode.OK) return code
        this.context = context.applicationContext
        initialized = true
        store = TiStore(token)
        return TiStoreErrorCode.OK
    }

    fun query(
        startMs: Long,
        endMs: Long,
        callback: (TiStoreRecordingRangesResult) -> Unit,
    ): Int {
        val owner = store ?: return TiStoreErrorCode.NOT_INITIALIZED
        if (closing) return TiStoreErrorCode.IN_USE
        beginOperation()
        owner.listRecordings(startMs, endMs) { result ->
            callback(result)
            endOperation()
        }
        return TiStoreErrorCode.OK
    }

    fun queryDays(
        startDate: String,
        endDate: String,
        timeZoneId: String = "Asia/Shanghai",
        callback: (TiStoreRecordingDaysResult) -> Unit,
    ): Int {
        val owner = store ?: return TiStoreErrorCode.NOT_INITIALIZED
        if (closing) return TiStoreErrorCode.IN_USE
        beginOperation()
        owner.listRecordingDays(startDate, endDate, timeZoneId) { result ->
            callback(result)
            endOperation()
        }
        return TiStoreErrorCode.OK
    }

    fun play(
        range: TiStoreRecordingRange,
        stage: ViewGroup,
        videoChannel: Int,
        audioChannel: Int,
    ): Int {
        if (closing) return TiStoreErrorCode.IN_USE
        val owner = store ?: return TiStoreErrorCode.NOT_INITIALIZED
        var activeReplay = replay
        if (activeReplay == null) {
            activeReplay = owner.createReplay()
            val activeVideo = TiStoreVideoOutput()
            val activeAudio = TiStoreAudioOutput()
            activeReplay.onTimeChanged = TiStoreTimeChangedListener { time -> onTimeChanged?.invoke(time) }
            activeReplay.onCompleted = TiStoreReplayCompletedListener { onReplayCompleted?.invoke() }
            activeReplay.onError = TiStoreReplayErrorListener { code -> onError?.invoke(code) }
            activeVideo.onStateChanged = TiStoreVideoOutputStateListener { state -> onVideoStateChanged?.invoke(state) }
            activeVideo.onError = TiStoreOutputErrorListener { code -> onError?.invoke(code) }
            activeAudio.onStateChanged = TiStoreAudioOutputStateListener { state -> onAudioStateChanged?.invoke(state) }
            activeAudio.onError = TiStoreOutputErrorListener { code -> onError?.invoke(code) }
            var code = activeVideo.attachView(stage)
            if (code == TiStoreErrorCode.OK) code = activeVideo.attach(activeReplay, videoChannel)
            if (code == TiStoreErrorCode.OK) code = activeAudio.attach(activeReplay, audioChannel)
            if (code != TiStoreErrorCode.OK) {
                activeAudio.detach()
                activeVideo.detach()
                activeVideo.detachView()
                activeAudio.dispose()
                activeVideo.dispose()
                activeReplay.dispose()
                return code
            }
            replay = activeReplay
            video = activeVideo
            audio = activeAudio
        }
        val code = activeReplay.play(range.startTimeMs, range.endTimeMs)
        if (code == TiStoreErrorCode.OK) paused = false
        return code
    }

    fun pause(): Int {
        val active = replay ?: return TiStoreErrorCode.NOT_STARTED
        return active.pause().also { code ->
            if (code == TiStoreErrorCode.OK) paused = true
        }
    }

    fun resume(): Int {
        val active = replay ?: return TiStoreErrorCode.NOT_STARTED
        return active.resume().also { code ->
            if (code == TiStoreErrorCode.OK) paused = false
        }
    }

    fun seek(timeMs: Long): Int = replay?.seek(timeMs) ?: TiStoreErrorCode.NOT_STARTED

    fun setSpeed(next: TiStoreReplaySpeed): Int = replay?.setSpeed(next) ?: TiStoreErrorCode.NOT_STARTED

    fun toggleMute(): Int {
        val output = audio ?: return TiStoreErrorCode.NOT_STARTED
        val next = !muted
        return output.setVolume(if (next) 0 else 100).also { code ->
            if (code == TiStoreErrorCode.OK) muted = next
        }
    }

    fun takeSnapshot(callback: (Int, String?) -> Unit): Int {
        val output = video ?: return TiStoreErrorCode.NOT_STARTED
        if (closing) return TiStoreErrorCode.IN_USE
        beginOperation()
        output.takeSnapshot { result ->
            val file = result.file
            if (result.code != TiStoreErrorCode.OK || file == null) {
                callback(result.code, null)
                endOperation()
                return@takeSnapshot
            }
            replaceLatest(SnapshotMedia(file)) { code ->
                callback(code, if (code == TiStoreErrorCode.OK) file.path else null)
                endOperation()
            }
        }
        return TiStoreErrorCode.OK
    }

    fun toggleRecording(
        videoChannel: Int,
        audioChannel: Int,
        callback: (started: Boolean, code: Int, path: String?) -> Unit,
    ): Int {
        val active = recordingTask
        if (active == null) {
            val activeReplay = replay ?: return TiStoreErrorCode.NOT_STARTED
            if (closing) return TiStoreErrorCode.IN_USE
            val result = activeReplay.startRecording(videoChannel, audioChannel)
            if (result.code == TiStoreErrorCode.OK) recordingTask = result.task
            callback(result.code == TiStoreErrorCode.OK, result.code, null)
            return result.code
        }
        recordingTask = null
        beginOperation()
        active.stop { result ->
            val file = result.file
            if (result.code != TiStoreErrorCode.OK || file == null) {
                callback(false, result.code, null)
                endOperation()
                return@stop
            }
            if (closing) {
                RecordingMedia(file).delete { code ->
                    callback(false, code, null)
                    endOperation()
                }
            } else {
                replaceLatest(RecordingMedia(file)) { code ->
                    callback(false, code, if (code == TiStoreErrorCode.OK) file.path else null)
                    endOperation()
                }
            }
        }
        return TiStoreErrorCode.OK
    }

    fun export(
        range: TiStoreRecordingRange,
        videoChannel: Int,
        audioChannel: Int,
        onProgress: (Double) -> Unit,
        callback: (Int, String?) -> Unit,
    ): Int {
        val owner = store ?: return TiStoreErrorCode.NOT_INITIALIZED
        if (closing || exportTask != null) return TiStoreErrorCode.IN_USE
        beginOperation()
        val started =
            owner.exportRecording(
                TiStoreExportRequest(range.startTimeMs, range.endTimeMs, videoChannel, audioChannel),
                { progress -> onProgress(progress) },
            ) { result ->
                exportTask = null
                val file = result.file
                if (result.code != TiStoreErrorCode.OK || file == null) {
                    callback(result.code, null)
                    endOperation()
                    return@exportRecording
                }
                if (closing) {
                    RecordingMedia(file).delete { code ->
                        callback(code, null)
                        endOperation()
                    }
                } else {
                    replaceLatest(RecordingMedia(file)) { code ->
                        callback(code, if (code == TiStoreErrorCode.OK) file.path else null)
                        endOperation()
                    }
                }
            }
        exportTask = started.task
        if (started.code != TiStoreErrorCode.OK || started.task == null) {
            exportTask = null
            endOperation()
        }
        return started.code
    }

    fun saveLatestToGallery(callback: (Int) -> Unit): Int {
        val ownerContext = context ?: return TiStoreErrorCode.NOT_INITIALIZED
        val media = latestMedia ?: return TiStoreErrorCode.NOT_STARTED
        if (closing) return TiStoreErrorCode.IN_USE
        beginOperation()
        thread(name = "tistore-example-gallery", isDaemon = true) {
            val copyCode = copyToGallery(ownerContext, media)
            mainHandler.post {
                if (copyCode != TiStoreErrorCode.OK) {
                    callback(copyCode)
                    endOperation()
                    return@post
                }
                media.delete { deleteCode ->
                    if (deleteCode == TiStoreErrorCode.OK) {
                        if (latestMedia === media) latestMedia = null
                        ownedMedia.remove(media)
                    }
                    callback(deleteCode)
                    endOperation()
                }
            }
        }
        return TiStoreErrorCode.OK
    }

    fun close(callback: (Int) -> Unit = {}) {
        closeCallbacks += callback
        if (closing) return
        closing = true
        cleanupError = TiStoreErrorCode.OK
        closeDeadlineMs = android.os.SystemClock.uptimeMillis() + CLOSE_RETRY_MS
        val activeRecording = recordingTask
        if (activeRecording != null) {
            recordingTask = null
            beginOperation()
            activeRecording.stop { result ->
                val media = result.file?.let(::RecordingMedia)
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
            callback(TiStoreErrorCode.OK)
            return
        }
        previous.delete { code ->
            if (code == TiStoreErrorCode.OK) ownedMedia.remove(previous)
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
                if (code != TiStoreErrorCode.OK) captureCleanupError(code)
                endOperation()
            }
            return
        }
        val code = releaseOnce()
        if (code == TiStoreErrorCode.IN_USE && android.os.SystemClock.uptimeMillis() < closeDeadlineMs) {
            mainHandler.post(::continueClose)
            return
        }
        finishClose(if (cleanupError != TiStoreErrorCode.OK) cleanupError else code)
    }

    private fun captureCleanupError(code: Int) {
        if (code != TiStoreErrorCode.OK && cleanupError == TiStoreErrorCode.OK) cleanupError = code
    }

    private fun releaseOnce(): Int {
        var firstError = TiStoreErrorCode.OK

        fun capture(code: Int) {
            if (code == TiStoreErrorCode.OK || code == TiStoreErrorCode.NOT_STARTED || code == TiStoreErrorCode.NOT_BOUND) return
            if (firstError == TiStoreErrorCode.OK || code == TiStoreErrorCode.IN_USE) firstError = code
        }
        capture(replay?.stop() ?: TiStoreErrorCode.OK)
        capture(audio?.detach() ?: TiStoreErrorCode.OK)
        capture(video?.detach() ?: TiStoreErrorCode.OK)
        capture(video?.detachView() ?: TiStoreErrorCode.OK)
        audio?.let { output ->
            val code = output.dispose()
            capture(code)
            if (code == TiStoreErrorCode.OK) audio = null
        }
        video?.let { output ->
            val code = output.dispose()
            capture(code)
            if (code == TiStoreErrorCode.OK) video = null
        }
        replay?.let { active ->
            val code = active.dispose()
            capture(code)
            if (code == TiStoreErrorCode.OK) replay = null
        }
        store?.let { owner ->
            val code = owner.dispose()
            capture(code)
            if (code == TiStoreErrorCode.OK) store = null
        }
        if (store == null && replay == null && audio == null && video == null && initialized) {
            val code = TiStore.shutdown()
            capture(code)
            if (code == TiStoreErrorCode.OK) initialized = false
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
    ): Int = copyPathToGallery(context, media.path, media is RecordingMedia)

    private sealed class OwnedMedia(val path: String) {
        abstract fun delete(callback: (Int) -> Unit)
    }

    private class RecordingMedia(private val file: TiStoreRecordingFile) : OwnedMedia(file.path) {
        override fun delete(callback: (Int) -> Unit) = file.delete { code -> callback(code) }
    }

    private class SnapshotMedia(private val file: TiStoreSnapshotFile) : OwnedMedia(file.path) {
        override fun delete(callback: (Int) -> Unit) = file.delete { code -> callback(code) }
    }

    private companion object {
        private const val CLOSE_RETRY_MS = 1000L
    }
}
