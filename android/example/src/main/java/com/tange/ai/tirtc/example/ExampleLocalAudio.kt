package com.tange.ai.tirtc.example

import com.tange.ai.tirtc.TiRtcAudioAecMode
import com.tange.ai.tirtc.TiRtcAudioAgcLevel
import com.tange.ai.tirtc.TiRtcAudioAnsLevel
import com.tange.ai.tirtc.TiRtcAudioChannelCount
import com.tange.ai.tirtc.TiRtcAudioCodec
import com.tange.ai.tirtc.TiRtcAudioInputOptions
import com.tange.ai.tirtc.TiRtcAudioSampleRate

internal fun ExampleSettings.localAudioOptions(): TiRtcAudioInputOptions {
    return TiRtcAudioInputOptions(
        codec = localAudioCodec,
        sampleRate = localAudioSampleRate,
        channels = TiRtcAudioChannelCount.MONO,
        aecMode = if (localAudioAecEnabled) TiRtcAudioAecMode.ENABLED else TiRtcAudioAecMode.DISABLED,
        agcLevel = localAudioAgcLevel.toAudioAgcLevel(),
        ansLevel = localAudioAnsLevel.toAudioAnsLevel(),
    )
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

internal fun localAudioProcessingLevelFromIndex(position: Int): Int {
    return position.coerceIn(0, 3)
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
