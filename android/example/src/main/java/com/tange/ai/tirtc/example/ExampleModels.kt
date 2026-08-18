package com.tange.ai.tirtc.example

import com.tange.ai.tirtc.TiRtcAudioCodec
import com.tange.ai.tirtc.TiRtcAudioSampleRate
import com.tange.ai.tirtc.TiRtcOutputBufferStrategy
import com.tange.ai.tirtc.TiRtcVideoDecoderPreference

data class ClientConfiguration(
    val appId: String,
    val endpoint: String,
    val remoteId: String,
    val audioStreamId: Int,
    val videoStreamId: Int,
    val token: String,
    val tokenSource: DemoTokenSource = DemoTokenSource.ONE_TIME,
    val tokenIssuerBaseUrl: String = "",
    val oneTimeToken: String = token,
)

data class StoreConfiguration(
    val appId: String = "",
    val endpoint: String = "",
    val token: String = "",
    val audioChannelId: Int = 10,
    val videoChannelId: Int = 11,
)

enum class ConfigureProduct { RTC, STORE }

data class ExampleSettings(
    val decoderPreference: DecoderPreference = DecoderPreference.AUTO,
    val outputBufferStrategy: TiRtcOutputBufferStrategy = TiRtcOutputBufferStrategy.AUTOMATIC,
    val localAudioCodec: TiRtcAudioCodec = TiRtcAudioCodec.G711A,
    val localAudioSampleRate: TiRtcAudioSampleRate = TiRtcAudioSampleRate.RATE_16K,
    val localAudioStreamId: Int = 14,
    val localAudioAecEnabled: Boolean = false,
    val localAudioAgcLevel: Int = 0,
    val localAudioAnsLevel: Int = 0,
    val consoleLogEnabled: Boolean = true,
)

enum class DecoderPreference(
    val nativeValue: Int,
    val label: String,
) {
    AUTO(0, "Auto"),
    SOFTWARE(1, "Software"),
    HARDWARE(2, "Hardware"),
}

internal fun DecoderPreference.toSdkDecoderPreference(): TiRtcVideoDecoderPreference {
    return when (this) {
        DecoderPreference.AUTO -> TiRtcVideoDecoderPreference.AUTO
        DecoderPreference.SOFTWARE -> TiRtcVideoDecoderPreference.SOFTWARE
        DecoderPreference.HARDWARE -> TiRtcVideoDecoderPreference.HARDWARE
    }
}
