import 'package:flutter/foundation.dart';

import '../demo_widget_keys.dart';

const int _mediaCodecAudioG711A = 1;
const int _mediaCodecAudioAac = 2;
const int _mediaCodecAudioPcm = 3;
const int _mediaCodecAudioOpus = 4;
const int _mediaCodecAudioAmr = 5;
const int _mediaCodecVideoH264 = 65;
const int _mediaCodecVideoH265 = 66;
const int _mediaCodecVideoMjpeg = 67;
const int _videoDecoderBackendSoftware = 1;
const int _videoDecoderBackendHardware = 2;
const double _minimumVideoRenderContinuityRatio = 0.8;

class DownlinkMetricsOverlayModel {
  const DownlinkMetricsOverlayModel({
    required this.connectDurationMs,
    required this.firstVideoOutputMs,
    required this.firstAudioOutputMs,
    required this.videoWidth,
    required this.videoHeight,
    required this.videoCodec,
    required this.audioCodec,
    required this.audioSampleRate,
    required this.audioChannels,
    required this.requestedDecoderPreference,
    required this.resolvedDecoderBackend,
    required this.audioInputBitrateKbps,
    required this.audioInputPacketRate,
    required this.audioRenderCallbackRate,
    required this.audioStatsRefreshIntervalMs,
    required this.audioStatsUpdatedAtMs,
    required this.audioStutterThresholdMs,
    required this.audioOutputDurationMs,
    required this.audioStutterTotalMs,
    required this.audioStutterCount,
    required this.audioStutterPeakMs,
    required this.audioStutterAverageMs,
    required this.audioStutterRate,
    required this.audioEstimatedOutputLatencyMs,
    required this.videoInputBitrateKbps,
    required this.videoInputFps,
    required this.videoDecodedFps,
    required this.videoRenderFps,
    required this.videoStatsRefreshIntervalMs,
    required this.videoStatsUpdatedAtMs,
    required this.videoStutterThresholdMs,
    required this.videoOutputDurationMs,
    required this.videoStutterTotalMs,
    required this.videoStutterCount,
    required this.videoStutterPeakMs,
    required this.videoStutterAverageMs,
    required this.videoStutterRate,
    required this.videoEstimatedOutputLatencyMs,
  });

  final int? connectDurationMs;
  final int? firstVideoOutputMs;
  final int? firstAudioOutputMs;
  final int? videoWidth;
  final int? videoHeight;
  final int? videoCodec;
  final int? audioCodec;
  final int? audioSampleRate;
  final int? audioChannels;
  final int requestedDecoderPreference;
  final int? resolvedDecoderBackend;
  final double? audioInputBitrateKbps;
  final double? audioInputPacketRate;
  final double? audioRenderCallbackRate;
  final int? audioStatsRefreshIntervalMs;
  final int? audioStatsUpdatedAtMs;
  final int? audioStutterThresholdMs;
  final int? audioOutputDurationMs;
  final int? audioStutterTotalMs;
  final int? audioStutterCount;
  final int? audioStutterPeakMs;
  final int? audioStutterAverageMs;
  final double? audioStutterRate;
  final int? audioEstimatedOutputLatencyMs;
  final double? videoInputBitrateKbps;
  final double? videoInputFps;
  final double? videoDecodedFps;
  final double? videoRenderFps;
  final int? videoStatsRefreshIntervalMs;
  final int? videoStatsUpdatedAtMs;
  final int? videoStutterThresholdMs;
  final int? videoOutputDurationMs;
  final int? videoStutterTotalMs;
  final int? videoStutterCount;
  final int? videoStutterPeakMs;
  final int? videoStutterAverageMs;
  final double? videoStutterRate;
  final int? videoEstimatedOutputLatencyMs;

  String get displayVideoSize {
    final int? width = videoWidth;
    final int? height = videoHeight;
    if (width == null || height == null || width <= 0 || height <= 0) {
      return '--';
    }
    return '${width}x$height';
  }

  String get displayVideoCodec {
    return switch (videoCodec) {
      _mediaCodecVideoH264 => 'H264',
      _mediaCodecVideoH265 => 'H265',
      _mediaCodecVideoMjpeg => 'MJPEG',
      _ => '--',
    };
  }

  String get displayAudioCodec {
    return switch (audioCodec) {
      _mediaCodecAudioG711A => 'G711A',
      _mediaCodecAudioAac => 'AAC',
      _mediaCodecAudioPcm => 'PCM',
      _mediaCodecAudioOpus => 'OPUS',
      _mediaCodecAudioAmr => 'AMR',
      _ => '--',
    };
  }

  String get displayVideoDecoder {
    return switch (resolvedDecoderBackend) {
      _videoDecoderBackendHardware => '硬解',
      _videoDecoderBackendSoftware => '软解',
      _ => '未确定',
    };
  }

  bool get debugStatsReady {
    final int? width = videoWidth;
    final int? height = videoHeight;
    return width != null &&
        width > 0 &&
        height != null &&
        height > 0 &&
        _isKnownVideoCodec(videoCodec) &&
        _isKnownAudioCodec(audioCodec) &&
        _isKnownAudioSampleRate(audioSampleRate) &&
        _isKnownAudioChannels(audioChannels) &&
        _isResolvedDecoderBackend(resolvedDecoderBackend);
  }

  bool get avStatsReady {
    return audioOutputMetricsReady && videoOutputMetricsReady;
  }

  bool get audioOutputMetricsReady {
    return _positive(audioInputBitrateKbps) &&
        _positive(audioInputPacketRate) &&
        _positive(audioRenderCallbackRate) &&
        _positive(audioStatsRefreshIntervalMs);
  }

  double? get audioOutputContinuityRatio {
    return _rateRatio(audioRenderCallbackRate, audioInputPacketRate);
  }

  bool get audioOutputHealthOk {
    return audioOutputMetricsReady && (audioStutterCount ?? 0) == 0;
  }

  bool get videoOutputMetricsReady {
    return _positive(videoInputBitrateKbps) &&
        _positive(videoInputFps) &&
        _positive(videoDecodedFps) &&
        _positive(videoRenderFps) &&
        _positive(videoStatsRefreshIntervalMs);
  }

  double? get videoRenderContinuityRatio {
    return _rateRatio(videoRenderFps, videoInputFps);
  }

  bool get videoOutputHealthOk {
    final double? ratio = videoRenderContinuityRatio;
    return videoOutputMetricsReady &&
        ratio != null &&
        ratio >= _minimumVideoRenderContinuityRatio &&
        (videoStutterCount ?? 0) == 0;
  }

  bool get avOutputHealthOk {
    return audioOutputHealthOk && videoOutputHealthOk;
  }

  bool get latencyReady {
    return _nonNegative(audioEstimatedOutputLatencyMs) && _nonNegative(videoEstimatedOutputLatencyMs);
  }

  bool get latencyMetricsValid {
    return _validOutputLatency(audioEstimatedOutputLatencyMs) && _validOutputLatency(videoEstimatedOutputLatencyMs);
  }

  bool get stutterReady {
    return _nonNegative(audioOutputDurationMs) &&
        _nonNegative(videoOutputDurationMs) &&
        _nonNegative(audioStutterTotalMs) &&
        _nonNegative(videoStutterTotalMs) &&
        _nonNegative(audioStutterRate) &&
        _nonNegative(videoStutterRate);
  }

  bool get periodSummaryAvailable {
    return latencyReady && stutterReady;
  }

  List<DownlinkMetricsOverlayRow> get overlayRows {
    return <DownlinkMetricsOverlayRow>[
      DownlinkMetricsOverlayRow(
        rowKey: 'media_params',
        widgetKey: DemoWidgetKeys.downlinkMetricsMediaParamsText,
        label: '媒体参数',
        value: '$displayVideoSize · $displayVideoCodec · $displayAudioCodec · $displayVideoDecoder',
      ),
      DownlinkMetricsOverlayRow(
        rowKey: 'video_receive',
        widgetKey: DemoWidgetKeys.downlinkMetricsVideoReceiveText,
        label: '视频接收',
        value: '码率 ${_formatKbps(videoInputBitrateKbps)} · '
            '接收 ${_formatFps(videoInputFps)}',
      ),
      DownlinkMetricsOverlayRow(
        rowKey: 'audio_receive',
        widgetKey: DemoWidgetKeys.downlinkMetricsAudioReceiveText,
        label: '音频接收',
        value: '码率 ${_formatKbps(audioInputBitrateKbps)} · '
            'PPS ${_formatPerSecond(audioInputPacketRate)}',
      ),
      DownlinkMetricsOverlayRow(
        rowKey: 'latency_stats',
        widgetKey: DemoWidgetKeys.downlinkMetricsLatencyStatsText,
        label: '估算延迟',
        value:
            '视频 ${_formatDuration(videoEstimatedOutputLatencyMs)} · 音频 ${_formatDuration(audioEstimatedOutputLatencyMs)}',
        periodTextPresent: true,
        periodAvailable: latencyReady,
        unavailableReason: latencyReady ? null : 'latency_metrics_unavailable',
      ),
      DownlinkMetricsOverlayRow(
        rowKey: 'startup',
        widgetKey: DemoWidgetKeys.downlinkMetricsStartupText,
        label: '启动耗时',
        value: _formatStartup(connectDurationMs, firstVideoOutputMs),
      ),
      DownlinkMetricsOverlayRow(
        rowKey: 'stutter',
        widgetKey: DemoWidgetKeys.downlinkMetricsStutterText,
        label: '卡顿统计',
        value: '视频 ${_formatCount(videoStutterCount)} / 最长 ${_formatDuration(videoStutterPeakMs)} · '
            '音频 ${_formatCount(audioStutterCount)} / 最长 ${_formatDuration(audioStutterPeakMs)}',
        periodTextPresent: true,
        periodAvailable: stutterReady,
        unavailableReason: stutterReady ? null : 'stutter_metrics_unavailable',
      ),
    ];
  }

  List<Map<String, Object?>> snapshotRowsPayload() {
    return overlayRows
        .map(
          (DownlinkMetricsOverlayRow row) => <String, Object?>{
            'key': row.rowKey,
            'text': row.text,
            'present': true,
            'period_text_present': row.periodTextPresent,
          },
        )
        .toList(growable: false);
  }

  Map<String, Object?> periodSummaryPayload() {
    final List<DownlinkMetricsOverlayRow> periodRows =
        overlayRows.where((DownlinkMetricsOverlayRow row) => row.periodTextPresent).toList(growable: false);
    return <String, Object?>{
      'available': periodSummaryAvailable,
      'source': 'ui_text_period_summary',
      'rows': periodRows
          .map(
            (DownlinkMetricsOverlayRow row) => <String, Object?>{
              'key': row.rowKey,
              'text': row.text,
              'available': row.periodAvailable,
              'unavailable_reason': row.periodAvailable ? null : row.unavailableReason,
            },
          )
          .toList(growable: false),
    };
  }

  static bool _isKnownVideoCodec(int? codec) {
    return codec == _mediaCodecVideoH264 || codec == _mediaCodecVideoH265 || codec == _mediaCodecVideoMjpeg;
  }

  static bool _isKnownAudioCodec(int? codec) {
    return codec == _mediaCodecAudioG711A ||
        codec == _mediaCodecAudioAac ||
        codec == _mediaCodecAudioPcm ||
        codec == _mediaCodecAudioOpus ||
        codec == _mediaCodecAudioAmr;
  }

  static bool _isKnownAudioSampleRate(int? sampleRate) {
    return sampleRate == 8000 || sampleRate == 16000;
  }

  static bool _isKnownAudioChannels(int? channels) {
    return channels == 1 || channels == 2;
  }

  static bool _isResolvedDecoderBackend(int? backend) {
    return backend == _videoDecoderBackendHardware || backend == _videoDecoderBackendSoftware;
  }

  static bool _positive(num? value) {
    return value != null && value > 0;
  }

  static bool _nonNegative(num? value) {
    return value != null && value >= 0;
  }

  static bool _validOutputLatency(int? value) {
    return value != null && (value >= 0 || value == -1);
  }

  static double? _rateRatio(double? numerator, double? denominator) {
    if (!_positive(numerator) || !_positive(denominator)) {
      return null;
    }
    return numerator! / denominator!;
  }
}

final class DownlinkMetricsOverlayRow {
  const DownlinkMetricsOverlayRow({
    required this.rowKey,
    required this.widgetKey,
    required this.label,
    required this.value,
    this.periodTextPresent = false,
    this.periodAvailable = false,
    this.unavailableReason,
  });

  final String rowKey;
  final ValueKey<String> widgetKey;
  final String label;
  final String value;
  final bool periodTextPresent;
  final bool periodAvailable;
  final String? unavailableReason;

  String get text => '$label：$value';
}

String _formatDuration(int? durationMs) {
  if (durationMs == null || durationMs < 0) {
    return '--';
  }
  return '$durationMs ms';
}

String _formatKbps(double? value) {
  if (value == null || value.isNaN || value.isInfinite || value <= 0) {
    return '--';
  }
  return '${value.toStringAsFixed(value >= 100 ? 0 : 1)} kbps';
}

String _formatFps(double? value) {
  if (value == null || value.isNaN || value.isInfinite || value <= 0) {
    return '--';
  }
  return '${value.toStringAsFixed(1)} fps';
}

String _formatPerSecond(double? value) {
  if (value == null || value.isNaN || value.isInfinite || value <= 0) {
    return '--';
  }
  return '${value.toStringAsFixed(1)}/s';
}

String _formatCount(int? count) {
  if (count == null || count < 0) {
    return '--';
  }
  return '$count 次';
}

String _formatStartup(int? connectDurationMs, int? firstOutputMs) {
  final String connectText = '连接 ${_formatDuration(connectDurationMs)}';
  if (connectDurationMs != null &&
      firstOutputMs != null &&
      connectDurationMs >= 0 &&
      firstOutputMs >= connectDurationMs) {
    return '$connectText · 首帧等待 ${_formatDuration(firstOutputMs - connectDurationMs)}';
  }
  return '$connectText · 首帧总耗时 ${_formatDuration(firstOutputMs)}';
}
