package com.tange.ai.tirtc.example

import android.util.Log
import com.tange.ai.tirtc.TiRtcAudioAecMode
import com.tange.ai.tirtc.TiRtcAudioAgcLevel
import com.tange.ai.tirtc.TiRtcAudioAnsLevel
import com.tange.ai.tirtc.TiRtcAudioChannelCount
import com.tange.ai.tirtc.TiRtcAudioCodec
import com.tange.ai.tirtc.TiRtcAudioInput
import com.tange.ai.tirtc.TiRtcAudioInputMode
import com.tange.ai.tirtc.TiRtcAudioInputOptions
import com.tange.ai.tirtc.TiRtcAudioSampleRate
import com.tange.ai.tirtc.TiRtcPcmCaptureListener

internal fun ExampleSettings.localAudioOptions(): TiRtcAudioInputOptions {
    return TiRtcAudioInputOptions(
        sampleRate = localAudioSampleRate,
        channels = TiRtcAudioChannelCount.MONO,
        aecMode = if (localAudioAecEnabled) TiRtcAudioAecMode.ENABLED else TiRtcAudioAecMode.DISABLED,
        agcLevel = localAudioAgcLevel.toAudioAgcLevel(),
        ansLevel = localAudioAnsLevel.toAudioAnsLevel(),
    ).apply {
        mode = if (localAudioRobotVoiceEnabled) TiRtcAudioInputMode.CUSTOM else TiRtcAudioInputMode.BUILT_IN
        captureEnabled = true
        media =
            when (localAudioCodec) {
                TiRtcAudioCodec.PCM -> 1
                TiRtcAudioCodec.G711A -> 2
                TiRtcAudioCodec.AAC -> 3
                TiRtcAudioCodec.OPUS -> 4
                TiRtcAudioCodec.AMR -> 5
            }
    }
}

internal fun localAudioCodecFromIndex(position: Int): TiRtcAudioCodec {
    return when (position) {
        1 -> TiRtcAudioCodec.AAC
        2 -> TiRtcAudioCodec.PCM
        3 -> TiRtcAudioCodec.OPUS
        4 -> TiRtcAudioCodec.AMR
        else -> TiRtcAudioCodec.G711A
    }
}

internal fun localAudioCodecIndex(codec: TiRtcAudioCodec): Int {
    return when (codec) {
        TiRtcAudioCodec.AAC -> 1
        TiRtcAudioCodec.PCM -> 2
        TiRtcAudioCodec.OPUS -> 3
        TiRtcAudioCodec.AMR -> 4
        TiRtcAudioCodec.G711A -> 0
        else -> 0
    }
}

internal fun localAudioSampleRateFromIndex(position: Int): TiRtcAudioSampleRate {
    return if (position == 0) TiRtcAudioSampleRate.RATE_8K else TiRtcAudioSampleRate.RATE_16K
}

internal fun localAudioSampleRateIndex(sampleRate: TiRtcAudioSampleRate): Int {
    return if (sampleRate == TiRtcAudioSampleRate.RATE_8K) 0 else 1
}

internal fun localAudioSampleRateHz(sampleRate: TiRtcAudioSampleRate): Int {
    return if (sampleRate == TiRtcAudioSampleRate.RATE_8K) 8000 else 16000
}

internal fun localAudioProcessingLevelFromIndex(position: Int): Int {
    return position.coerceIn(0, 3)
}

internal class ExampleLocalAudioController {
    private val lock = Any()
    private var input: TiRtcAudioInput? = null
    private var effect: ExampleRobotVoiceEffect? = null
    private var generation = 0L
    private var active = false
    private var capturedBlocks = 0L
    private var submittedBlocks = 0L
    private var firstSubmitError: Int? = null

    fun configure(
        input: TiRtcAudioInput,
        settings: ExampleSettings,
    ): Int {
        deactivate(input)
        complete("reconfigure")
        val optionsCode = input.setOptions(settings.localAudioOptions())
        if (optionsCode != 0 || !settings.localAudioRobotVoiceEnabled) return optionsCode

        val sampleRateHz = localAudioSampleRateHz(settings.localAudioSampleRate)
        val callbackGeneration =
            synchronized(lock) {
                this.input = input
                effect = ExampleRobotVoiceEffect(sampleRateHz).also { it.reset() }
                capturedBlocks = 0
                submittedBlocks = 0
                firstSubmitError = null
                generation += 1
                generation
            }
        input.onPcmCaptured =
            TiRtcPcmCaptureListener { pcm ->
                processCapturedPcm(input, callbackGeneration, pcm)
            }
        Log.i(TAG, "robot_voice configured sample_rate=$sampleRateHz frequency_hz=80")
        return 0
    }

    fun beginStart(input: TiRtcAudioInput) {
        synchronized(lock) {
            if (this.input === input && effect != null) active = true
        }
    }

    fun deactivate(input: TiRtcAudioInput) {
        synchronized(lock) {
            active = false
            generation += 1
        }
        input.onPcmCaptured = null
    }

    fun complete(reason: String) {
        val summary =
            synchronized(lock) {
                val hadEffect = effect != null
                effect?.reset()
                val message =
                    if (hadEffect) {
                        "robot_voice stopped reason=$reason captured_blocks=$capturedBlocks " +
                            "submitted_blocks=$submittedBlocks first_error=${firstSubmitError ?: 0}"
                    } else {
                        null
                    }
                input = null
                effect = null
                active = false
                capturedBlocks = 0
                submittedBlocks = 0
                firstSubmitError = null
                message
            }
        summary?.let { Log.i(TAG, it) }
    }

    private fun processCapturedPcm(
        source: TiRtcAudioInput,
        callbackGeneration: Long,
        pcm: ByteArray,
    ) {
        val processor =
            synchronized(lock) {
                if (!active || input !== source || generation != callbackGeneration) return
                capturedBlocks += 1
                effect ?: return
            }
        val processed = processor.process(pcm)
        synchronized(lock) {
            if (!active || input !== source || generation != callbackGeneration) return
        }
        val code = source.submitPcm(processed)
        var firstSubmit = false
        var firstError = false
        synchronized(lock) {
            if (input !== source) return
            if (code == 0) {
                submittedBlocks += 1
                firstSubmit = submittedBlocks == 1L
            } else if (firstSubmitError == null) {
                firstSubmitError = code
                firstError = true
            }
        }
        if (firstSubmit) Log.i(TAG, "robot_voice first_submit bytes=${processed.size}")
        if (firstError) Log.w(TAG, "robot_voice first_submit_error code=$code")
    }

    private companion object {
        const val TAG = "TiRtcExample"
    }
}

private fun Int.toAudioAgcLevel(): TiRtcAudioAgcLevel {
    return when (this) {
        1 -> TiRtcAudioAgcLevel.LOW
        2 -> TiRtcAudioAgcLevel.MEDIUM
        3 -> TiRtcAudioAgcLevel.HIGH
        else -> TiRtcAudioAgcLevel.DISABLED
    }
}

private fun Int.toAudioAnsLevel(): TiRtcAudioAnsLevel {
    return when (this) {
        1 -> TiRtcAudioAnsLevel.LOW
        2 -> TiRtcAudioAnsLevel.MEDIUM
        3 -> TiRtcAudioAnsLevel.HIGH
        else -> TiRtcAudioAnsLevel.DISABLED
    }
}
