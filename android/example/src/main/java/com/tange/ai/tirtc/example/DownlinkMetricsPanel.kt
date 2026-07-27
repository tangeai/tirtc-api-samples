package com.tange.ai.tirtc.example

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import android.widget.TextView
import com.tange.ai.tirtc.TiRtcAudioOutput
import com.tange.ai.tirtc.TiRtcAudioOutputMetricsSnapshot
import com.tange.ai.tirtc.TiRtcConn
import com.tange.ai.tirtc.TiRtcConnMetricsSnapshot
import com.tange.ai.tirtc.TiRtcVideoOutput
import com.tange.ai.tirtc.TiRtcVideoOutputDebugSnapshot
import com.tange.ai.tirtc.TiRtcVideoOutputMetricsSnapshot
import java.util.Locale

internal class DownlinkMetricsPanel(
    context: Context,
    private val requestedDecoderPreference: Int,
    onShowExplanation: () -> Unit,
) : LinearLayout(context) {
    private val avParameters = metricLine("音视频参数", maxLines = 2)
    private val videoReceive = metricLine("视频接收")
    private val audioReceive = metricLine("音频接收")
    private val audioStutter = metricLine("音频卡顿", maxLines = 2)
    private val videoLatency = metricLine("视频输出延迟", maxLines = 2)
    private val audioLatency = metricLine("音频输出延迟", maxLines = 2)
    private val connectDuration = metricLine("连接耗时")
    private val firstFrameDuration = metricLine("首帧耗时")
    private val sessionStutterRatio = metricLine("本次播放卡顿占比")
    private val sessionStutterCount = metricLine("本次播放卡顿次数")
    private val sessionStutterPeak = metricLine("本次播放最长卡顿")

    init {
        orientation = VERTICAL
        setPadding(context.dp(12), context.dp(10), context.dp(12), context.dp(10))
        background = rounded(Color.argb(204, 0, 0, 0), context.dp(8))
        elevation = context.dp(4).toFloat()
        addView(
            TextView(context).apply {
                text = "播放调试信息"
                setTextColor(Color.WHITE)
                textSize = 10f
                typeface = Typeface.DEFAULT_BOLD
                paint.isUnderlineText = true
                setPadding(0, 0, 0, context.dp(10))
            },
        )
        addMetric(avParameters)
        addMetric(videoReceive)
        addMetric(audioReceive)
        addMetric(audioStutter)
        addMetric(videoLatency)
        addMetric(audioLatency)
        addMetric(connectDuration)
        addMetric(firstFrameDuration)
        addMetric(sessionStutterRatio)
        addMetric(sessionStutterCount)
        addMetric(sessionStutterPeak)
        addView(
            TextView(context).apply {
                text = "?"
                gravity = Gravity.CENTER
                textSize = 14f
                typeface = Typeface.DEFAULT_BOLD
                setTextColor(Color.WHITE)
                setPadding(context.dp(6), context.dp(2), context.dp(6), context.dp(2))
                setOnClickListener { onShowExplanation() }
            },
            LayoutParams(context.dp(28), context.dp(28)).apply {
                gravity = Gravity.END
                topMargin = context.dp(2)
            },
        )
    }

    fun render(
        connection: TiRtcConn?,
        audio: TiRtcAudioOutput?,
        video: TiRtcVideoOutput?,
    ) {
        val connMetrics: TiRtcConnMetricsSnapshot? = connection?.getMetricsSnapshot()?.snapshot
        val audioMetrics: TiRtcAudioOutputMetricsSnapshot? = audio?.getMetricsSnapshot()?.snapshot
        val videoMetrics: TiRtcVideoOutputMetricsSnapshot? = video?.getMetricsSnapshot()?.snapshot
        val audioDebug = audio?.getDebugSnapshot()?.snapshot
        val videoDebug: TiRtcVideoOutputDebugSnapshot? = video?.getDebugSnapshot()?.snapshot

        avParameters.value.text =
            "分辨率 ${displayVideoSize(videoDebug)} / 视频 ${displayVideoCodec(videoDebug?.codec)} / " +
            "音频 ${displayAudioCodec(audioDebug?.codec)} / ${displayVideoDecoder(videoDebug)}"
        videoReceive.value.text =
            "码率 ${formatKbps(videoMetrics?.videoInputBitrateKbps)} / " +
            "接收 ${formatRate(videoMetrics?.videoInputFps, "帧/秒")} / " +
            "渲染 ${formatRate(videoMetrics?.videoRenderFps, "帧/秒")}"
        audioReceive.value.text =
            "码率 ${formatKbps(audioMetrics?.audioInputBitrateKbps)} / " +
            "音频包 ${formatRate(audioMetrics?.audioInputPacketRate, "个/秒")}"
        audioStutter.value.text =
            "次数 ${formatCount(audioMetrics?.stutter?.stutterCount)} / " +
            "累计 ${formatDuration(audioMetrics?.stutter?.stutterTotalMs)} / " +
            "最长 ${formatDuration(audioMetrics?.stutter?.stutterPeakMs)} / " +
            (if (audioOutputHealthOk(audioMetrics)) "稳定" else "断续风险")
        videoLatency.value.text = formatOutputLatency(videoMetrics?.estimatedOutputLatencyMs)
        audioLatency.value.text = formatOutputLatency(audioMetrics?.estimatedOutputLatencyMs)
        connectDuration.value.text = formatDuration(connMetrics?.connectDurationMs)
        firstFrameDuration.value.text = formatDuration(videoMetrics?.startup?.timeToFirstOutputMs)
        sessionStutterRatio.value.text = formatPercent(videoMetrics?.stutter?.stutterRate)
        sessionStutterCount.value.text = formatCount(videoMetrics?.stutter?.stutterCount)
        sessionStutterPeak.value.text = formatDuration(videoMetrics?.stutter?.stutterPeakMs)
    }

    private fun addMetric(metric: MetricLine) {
        addView(metric.root)
    }

    private fun metricLine(
        label: String,
        maxLines: Int = 1,
    ): MetricLine {
        val value =
            TextView(context).apply {
                text = "--"
                setTextColor(Color.WHITE)
                textSize = 10f
                this.maxLines = maxLines
            }
        val root =
            LinearLayout(context).apply {
                orientation = HORIZONTAL
                setPadding(0, 0, 0, context.dp(6))
                addView(
                    TextView(context).apply {
                        text = "[$label] "
                        setTextColor(Color.WHITE)
                        textSize = 10f
                        typeface = Typeface.DEFAULT_BOLD
                    },
                )
                addView(value, LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f))
            }
        return MetricLine(root, value)
    }

    private fun displayVideoSize(snapshot: TiRtcVideoOutputDebugSnapshot?): String {
        val width = snapshot?.width ?: 0
        val height = snapshot?.height ?: 0
        return if (width > 0 && height > 0) "${width}x$height" else "--"
    }

    private fun displayVideoCodec(codec: Int?): String =
        when (codec) {
            VIDEO_CODEC_H264 -> "H264"
            VIDEO_CODEC_H265 -> "H265"
            VIDEO_CODEC_MJPEG -> "MJPEG"
            else -> "--"
        }

    private fun displayAudioCodec(codec: Int?): String =
        when (codec) {
            AUDIO_CODEC_G711A -> "G711A"
            AUDIO_CODEC_AAC -> "AAC"
            else -> "--"
        }

    private fun displayVideoDecoder(snapshot: TiRtcVideoOutputDebugSnapshot?): String {
        val suffix = if (requestedDecoderPreference == DECODER_PREFERENCE_AUTO) "（自动）" else ""
        return when (snapshot?.resolvedDecoderBackend) {
            VIDEO_DECODER_BACKEND_HARDWARE -> "硬解$suffix"
            VIDEO_DECODER_BACKEND_SOFTWARE -> "软解$suffix"
            else -> "未确定"
        }
    }

    private fun audioOutputHealthOk(metrics: TiRtcAudioOutputMetricsSnapshot?): Boolean {
        return audioOutputMetricsReady(metrics) && (metrics?.stutter?.stutterCount ?: 0L) == 0L
    }

    private fun audioOutputMetricsReady(metrics: TiRtcAudioOutputMetricsSnapshot?): Boolean {
        return positive(metrics?.audioInputBitrateKbps) &&
            positive(metrics?.audioInputPacketRate) &&
            positive(metrics?.audioRenderCallbackRate) &&
            nonNegative(metrics?.estimatedOutputLatencyMs)
    }

    private fun formatOutputLatency(valueMs: Long?): String =
        if (nonNegative(valueMs)) "估算输出延迟 $valueMs ms" else "--"

    private fun formatDuration(durationMs: Long?): String {
        if (durationMs == null || durationMs < 0) {
            return "--"
        }
        return "$durationMs ms"
    }

    private fun formatPercent(value: Double?): String {
        if (value == null || value.isNaN() || value.isInfinite() || value < 0) {
            return "--"
        }
        return "${value.toStringWithPrecision(1)}%"
    }

    private fun formatKbps(value: Double?): String {
        if (!positive(value)) {
            return "--"
        }
        return "${value!!.toStringWithPrecision(if (value >= 100.0) 0 else 1)} Kbps"
    }

    private fun formatRate(
        value: Double?,
        suffix: String,
    ): String {
        if (!positive(value)) {
            return "--"
        }
        return "${value!!.toStringWithPrecision(1)} $suffix"
    }

    private fun formatCount(count: Long?): String {
        if (count == null || count < 0) {
            return "--"
        }
        return "$count 次"
    }

    private fun Double.toStringWithPrecision(digits: Int): String {
        return "%.${digits}f".format(Locale.US, this)
    }

    private fun positive(value: Number?): Boolean = value != null && value.toDouble() > 0.0

    private fun nonNegative(value: Number?): Boolean = value != null && value.toDouble() >= 0.0

    private data class MetricLine(
        val root: View,
        val value: TextView,
    )

    private companion object {
        private const val AUDIO_CODEC_G711A = 1
        private const val AUDIO_CODEC_AAC = 2
        private const val VIDEO_CODEC_H264 = 65
        private const val VIDEO_CODEC_H265 = 66
        private const val VIDEO_CODEC_MJPEG = 67
        private const val DECODER_PREFERENCE_AUTO = 0
        private const val VIDEO_DECODER_BACKEND_SOFTWARE = 1
        private const val VIDEO_DECODER_BACKEND_HARDWARE = 2
    }
}

private fun rounded(
    color: Int,
    radius: Int,
): GradientDrawable {
    return GradientDrawable().apply {
        setColor(color)
        cornerRadius = radius.toFloat()
    }
}
