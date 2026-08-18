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
    private val avParameters = metricLine("媒体参数")
    private val videoReceive = metricLine("视频接收")
    private val audioReceive = metricLine("音频接收")
    private val latency = metricLine("估算延迟")
    private val startup = metricLine("启动耗时")
    private val stutter = metricLine("卡顿统计")
    private val rows = listOf(avParameters, videoReceive, audioReceive, latency, startup, stutter)

    init {
        orientation = VERTICAL
        setPadding(context.dp(12), context.dp(8), context.dp(12), context.dp(8))
        background = rounded(Color.WHITE, context.dp(20))
        elevation = context.dp(8).toFloat()
        addView(
            LinearLayout(context).apply {
                orientation = HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                addView(
                    TextView(context).apply {
                        text = "即时统计"
                        setTextColor(Color.rgb(17, 17, 17))
                        textSize = 11f
                        typeface = Typeface.DEFAULT_BOLD
                    },
                    LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f),
                )
                addView(
                    TextView(context).apply {
                        text = "?"
                        gravity = Gravity.CENTER
                        setTextColor(ExampleTheme.primary)
                        textSize = 15f
                        setOnClickListener { onShowExplanation() }
                    },
                    LayoutParams(context.dp(22), context.dp(22)),
                )
                addView(
                    TextView(context).apply {
                        text = "⌃ 收起"
                        gravity = Gravity.CENTER
                        setTextColor(Color.WHITE)
                        textSize = 10f
                        typeface = Typeface.DEFAULT_BOLD
                        background = rounded(Color.rgb(79, 134, 217), context.dp(12))
                        setPadding(context.dp(8), 0, context.dp(8), 0)
                        setOnClickListener {
                            val show = rows.first().root.visibility != View.VISIBLE
                            rows.forEach { it.root.visibility = if (show) View.VISIBLE else View.GONE }
                            text = if (show) "⌃ 收起" else "▮ 即时统计"
                        }
                    },
                    LayoutParams(LayoutParams.WRAP_CONTENT, context.dp(20)).apply { leftMargin = context.dp(6) },
                )
            },
        )
        rows.forEach(::addMetric)
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
            "${displayVideoSize(videoDebug)} · ${displayVideoCodec(videoDebug?.codec)} · " +
            "${displayAudioCodec(audioDebug?.codec)} · ${displayVideoDecoder(videoDebug)}"
        videoReceive.value.text =
            "码率 ${formatKbps(videoMetrics?.videoInputBitrateKbps)} · " +
            "接收 ${formatRate(videoMetrics?.videoInputFps, "FPS")}"
        audioReceive.value.text =
            "码率 ${formatKbps(audioMetrics?.audioInputBitrateKbps)} · " +
            "PPS ${formatRate(audioMetrics?.audioInputPacketRate, "/s")}"
        latency.value.text =
            "视频 ${formatDuration(videoMetrics?.estimatedOutputLatencyMs)} · " +
            "音频 ${formatDuration(audioMetrics?.estimatedOutputLatencyMs)}"
        startup.value.text =
            "连接 ${formatDuration(connMetrics?.connectDurationMs)} · " +
            "首帧 ${formatDuration(videoMetrics?.startup?.timeToFirstOutputMs)}"
        stutter.value.text =
            "视频 ${formatCount(videoMetrics?.stutter?.stutterCount)} / " +
            "最长 ${formatDuration(videoMetrics?.stutter?.stutterPeakMs)} · " +
            "音频 ${formatCount(audioMetrics?.stutter?.stutterCount)} / " +
            "最长 ${formatDuration(audioMetrics?.stutter?.stutterPeakMs)}"
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
                setTextColor(Color.rgb(17, 17, 17))
                textSize = 10f
                this.maxLines = maxLines
            }
        val root =
            LinearLayout(context).apply {
                orientation = HORIZONTAL
                setPadding(0, 0, 0, context.dp(4))
                addView(
                    TextView(context).apply {
                        text = "$label："
                        setTextColor(ExampleTheme.primary)
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

    private fun formatOutputLatency(valueMs: Long?): String = if (nonNegative(valueMs)) "估算输出延迟 $valueMs ms" else "--"

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
