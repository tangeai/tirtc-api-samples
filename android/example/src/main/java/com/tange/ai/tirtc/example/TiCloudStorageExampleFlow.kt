package com.tange.ai.tirtc.example

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.view.ViewGroup
import com.tange.ai.tirtc.TiCloudStorage
import com.tange.ai.tirtc.TiCloudStorageAudioOutput
import com.tange.ai.tirtc.TiCloudStorageAudioOutputState
import com.tange.ai.tirtc.TiCloudStorageAudioOutputStateListener
import com.tange.ai.tirtc.TiCloudStorageErrorCode
import com.tange.ai.tirtc.TiCloudStorageExportRequest
import com.tange.ai.tirtc.TiCloudStorageExportTask
import com.tange.ai.tirtc.TiCloudStorageOutputErrorListener
import com.tange.ai.tirtc.TiCloudStorageRecordingFile
import com.tange.ai.tirtc.TiCloudStorageRecordingDaysResult
import com.tange.ai.tirtc.TiCloudStorageRecordingRange
import com.tange.ai.tirtc.TiCloudStorageRecordingRangesResult
import com.tange.ai.tirtc.TiCloudStorageRecordingTask
import com.tange.ai.tirtc.TiCloudStorageReplay
import com.tange.ai.tirtc.TiCloudStorageReplayCompletedListener
import com.tange.ai.tirtc.TiCloudStorageReplayErrorListener
import com.tange.ai.tirtc.TiCloudStorageReplaySpeed
import com.tange.ai.tirtc.TiCloudStorageSnapshotFile
import com.tange.ai.tirtc.TiCloudStorageTimeChangedListener
import com.tange.ai.tirtc.TiCloudStorageVideoOutput
import com.tange.ai.tirtc.TiCloudStorageVideoOutputState
import com.tange.ai.tirtc.TiCloudStorageVideoOutputStateListener
import java.io.File
import kotlin.concurrent.thread

internal fun copyPathToGallery(
    context: Context,
    sourcePath: String,
    isVideo: Boolean,
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
    private var video: TiCloudStorageVideoOutput? = null
    private var recordingTask: TiCloudStorageRecordingTask? = null
    private var exportTask: TiCloudStorageExportTask? = null
    private var latestMedia: OwnedMedia? = null
    private val ownedMedia = mutableListOf<OwnedMedia>()
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
    var onVideoStateChanged: ((TiCloudStorageVideoOutputState) -> Unit)? = null
    var onAudioStateChanged: ((TiCloudStorageAudioOutputState) -> Unit)? = null
    var onError: ((Int) -> Unit)? = null

    val currentTimeMs: Long?
        get() = replay?.currentTimeMs
    val speed: TiCloudStorageReplaySpeed
        get() = replay?.speed ?: TiCloudStorageReplaySpeed.X1
    val videoState: TiCloudStorageVideoOutputState
        get() = video?.state ?: TiCloudStorageVideoOutputState.IDLE
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
        if (closing || initialized) return TiCloudStorageErrorCode.IN_USE
        val code = TiCloudStorage.init(context, appId, endpoint)
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
        videoChannel: Int,
        audioChannel: Int,
    ): Int {
        if (closing) return TiCloudStorageErrorCode.IN_USE
        val owner = cloudStorage ?: return TiCloudStorageErrorCode.NOT_INITIALIZED
        var activeReplay = replay
        if (activeReplay == null) {
            activeReplay = owner.createReplay()
            val activeVideo = TiCloudStorageVideoOutput()
            val activeAudio = TiCloudStorageAudioOutput()
            activeReplay.onTimeChanged = TiCloudStorageTimeChangedListener { time -> onTimeChanged?.invoke(time) }
            activeReplay.onCompleted = TiCloudStorageReplayCompletedListener { onReplayCompleted?.invoke() }
            activeReplay.onError = TiCloudStorageReplayErrorListener { code -> onError?.invoke(code) }
            activeVideo.onStateChanged = TiCloudStorageVideoOutputStateListener { state -> onVideoStateChanged?.invoke(state) }
            activeVideo.onError = TiCloudStorageOutputErrorListener { code -> onError?.invoke(code) }
            activeAudio.onStateChanged = TiCloudStorageAudioOutputStateListener { state -> onAudioStateChanged?.invoke(state) }
            activeAudio.onError = TiCloudStorageOutputErrorListener { code -> onError?.invoke(code) }
            var code = activeVideo.attachView(stage)
            if (code == TiCloudStorageErrorCode.OK) code = activeVideo.attach(activeReplay, videoChannel)
            if (code == TiCloudStorageErrorCode.OK) code = activeAudio.attach(activeReplay, audioChannel)
            if (code != TiCloudStorageErrorCode.OK) {
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

    fun toggleMute(): Int {
        val output = audio ?: return TiCloudStorageErrorCode.NOT_STARTED
        val next = !muted
        return output.setVolume(if (next) 0 else 100).also { code ->
            if (code == TiCloudStorageErrorCode.OK) muted = next
        }
    }

    fun takeSnapshot(callback: (Int, String?) -> Unit): Int {
        val output = video ?: return TiCloudStorageErrorCode.NOT_STARTED
        if (closing) return TiCloudStorageErrorCode.IN_USE
        beginOperation()
        output.takeSnapshot { result ->
            val file = result.file
            if (result.code != TiCloudStorageErrorCode.OK || file == null) {
                callback(result.code, null)
                endOperation()
                return@takeSnapshot
            }
            replaceLatest(SnapshotMedia(file)) { code ->
                callback(code, if (code == TiCloudStorageErrorCode.OK) file.path else null)
                endOperation()
            }
        }
        return TiCloudStorageErrorCode.OK
    }

    fun toggleRecording(
        videoChannel: Int,
        audioChannel: Int,
        callback: (started: Boolean, code: Int, path: String?) -> Unit,
    ): Int {
        val active = recordingTask
        if (active == null) {
            val activeReplay = replay ?: return TiCloudStorageErrorCode.NOT_STARTED
            if (closing) return TiCloudStorageErrorCode.IN_USE
            val result = activeReplay.startRecording(videoChannel, audioChannel)
            if (result.code == TiCloudStorageErrorCode.OK) recordingTask = result.task
            callback(result.code == TiCloudStorageErrorCode.OK, result.code, null)
            return result.code
        }
        recordingTask = null
        beginOperation()
        active.stop { result ->
            val file = result.file
            if (result.code != TiCloudStorageErrorCode.OK || file == null) {
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
        audioChannel: Int,
        onProgress: (Double) -> Unit,
        callback: (Int, String?) -> Unit,
    ): Int {
        val owner = cloudStorage ?: return TiCloudStorageErrorCode.NOT_INITIALIZED
        if (closing || exportTask != null) return TiCloudStorageErrorCode.IN_USE
        beginOperation()
        val started =
            owner.exportRecording(
                TiCloudStorageExportRequest(range.startTimeMs, range.endTimeMs, videoChannel, audioChannel),
                { progress -> onProgress(progress) },
            ) { result ->
                exportTask = null
                val file = result.file
                if (result.code != TiCloudStorageErrorCode.OK || file == null) {
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
                        callback(code, if (code == TiCloudStorageErrorCode.OK) file.path else null)
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
        beginOperation()
        thread(name = "ti-cloud-storage-example-gallery", isDaemon = true) {
            val copyCode = copyToGallery(ownerContext, media)
            mainHandler.post {
                if (copyCode != TiCloudStorageErrorCode.OK) {
                    callback(copyCode)
                    endOperation()
                    return@post
                }
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
            if (code == TiCloudStorageErrorCode.OK || code == TiCloudStorageErrorCode.NOT_STARTED || code == TiCloudStorageErrorCode.NOT_BOUND) return
            if (firstError == TiCloudStorageErrorCode.OK || code == TiCloudStorageErrorCode.IN_USE) firstError = code
        }
        capture(replay?.stop() ?: TiCloudStorageErrorCode.OK)
        capture(audio?.detach() ?: TiCloudStorageErrorCode.OK)
        capture(video?.detach() ?: TiCloudStorageErrorCode.OK)
        capture(video?.detachView() ?: TiCloudStorageErrorCode.OK)
        audio?.let { output ->
            val code = output.dispose()
            capture(code)
            if (code == TiCloudStorageErrorCode.OK) audio = null
        }
        video?.let { output ->
            val code = output.dispose()
            capture(code)
            if (code == TiCloudStorageErrorCode.OK) video = null
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
        if (cloudStorage == null && replay == null && audio == null && video == null && initialized) {
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
    ): Int = copyPathToGallery(context, media.path, media is RecordingMedia)

    private sealed class OwnedMedia(val path: String) {
        abstract fun delete(callback: (Int) -> Unit)
    }

    private class RecordingMedia(private val file: TiCloudStorageRecordingFile) : OwnedMedia(file.path) {
        override fun delete(callback: (Int) -> Unit) = file.delete { code -> callback(code) }
    }

    private class SnapshotMedia(private val file: TiCloudStorageSnapshotFile) : OwnedMedia(file.path) {
        override fun delete(callback: (Int) -> Unit) = file.delete { code -> callback(code) }
    }

    private companion object {
        private const val CLOSE_RETRY_MS = 1000L
    }
}
