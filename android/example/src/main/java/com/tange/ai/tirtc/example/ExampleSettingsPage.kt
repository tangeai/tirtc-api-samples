package com.tange.ai.tirtc.example

import android.widget.CheckBox
import androidx.appcompat.app.AppCompatActivity
import com.tange.ai.tirtc.TiRtcOutputBufferStrategy

internal fun AppCompatActivity.showExampleSettingsPage(
    settings: ExampleSettings,
    onBack: () -> Unit,
    onSave: (ExampleSettings) -> Unit,
) {
    val console =
        CheckBox(this).apply {
            text = "Console log"
            isChecked = settings.consoleLogEnabled
            setTextColor(ExampleTheme.textPrimary)
            minHeight = dp(ExampleTheme.minimumTouchTargetDp)
        }
    val decoder = spinner(DecoderPreference.values().map { it.label }, settings.decoderPreference.ordinal)
    val buffer =
        spinner(
            listOf("Automatic", "NoBuffer"),
            if (settings.outputBufferStrategy == TiRtcOutputBufferStrategy.NO_BUFFER) 1 else 0,
        )
    val localAudioCodec = spinner(listOf("G711A", "AAC", "PCM", "OPUS", "AMR"), localAudioCodecIndex(settings.localAudioCodec))
    val localAudioSampleRate =
        spinner(listOf("8 kHz", "16 kHz"), localAudioSampleRateIndex(settings.localAudioSampleRate))
    val localAudioStreamId = editText("localAudio stream id", settings.localAudioStreamId.toString())
    val localAudioAec =
        CheckBox(this).apply {
            text = "AEC"
            isChecked = settings.localAudioAecEnabled
            setTextColor(ExampleTheme.textPrimary)
            minHeight = dp(ExampleTheme.minimumTouchTargetDp)
        }
    val localAudioAgc =
        spinner(
            listOf("Disabled", "Low", "Medium", "High"),
            settings.localAudioAgcLevel.coerceIn(0, 3),
        )
    val localAudioAns =
        spinner(
            listOf("Disabled", "Low", "Medium", "High"),
            settings.localAudioAnsLevel.coerceIn(0, 3),
        )
    setContentView(
        page {
            navigationHeader("偏好设置", onBack)
            addViewWithMargin(
                responsiveFormSections(
                    listOf(
                        formSection("播放") {
                            addViewWithMargin(fieldBlock("Decoder preference", decoder), bottom = 12)
                            addView(fieldBlock("Output buffer policy", buffer))
                        },
                        formSection("本地音频") {
                            addViewWithMargin(fieldBlock("audio codec", localAudioCodec), bottom = 12)
                            addViewWithMargin(fieldBlock("audio sample rate", localAudioSampleRate), bottom = 12)
                            addViewWithMargin(fieldBlock("localAudio stream id", localAudioStreamId), bottom = 12)
                            addView(localAudioAec)
                        },
                        formSection("音频处理") {
                            addViewWithMargin(fieldBlock("AGC", localAudioAgc), bottom = 12)
                            addView(fieldBlock("ANS", localAudioAns))
                        },
                        formSection("日志") { addView(console) },
                    ),
                ),
                bottom = 20,
            )
            addView(
                primaryButton("保存") {
                    onSave(
                        ExampleSettings(
                            decoderPreference = DecoderPreference.values()[decoder.selectedItemPosition],
                            outputBufferStrategy =
                                if (buffer.selectedItemPosition == 1) {
                                    TiRtcOutputBufferStrategy.NO_BUFFER
                                } else {
                                    TiRtcOutputBufferStrategy.AUTOMATIC
                                },
                            localAudioCodec = localAudioCodecFromIndex(localAudioCodec.selectedItemPosition),
                            localAudioSampleRate = localAudioSampleRateFromIndex(localAudioSampleRate.selectedItemPosition),
                            localAudioStreamId = localAudioStreamId.text.toString().toIntOrNull() ?: 14,
                            localAudioAecEnabled = localAudioAec.isChecked,
                            localAudioAgcLevel = localAudioProcessingLevelFromIndex(localAudioAgc.selectedItemPosition),
                            localAudioAnsLevel = localAudioProcessingLevelFromIndex(localAudioAns.selectedItemPosition),
                            consoleLogEnabled = console.isChecked,
                        ),
                    )
                },
            )
        },
    )
}
