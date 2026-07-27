import 'downlink_metrics_overlay_model.dart';

extension DownlinkMetricsOverlayMarkerPayloads on DownlinkMetricsOverlayModel {
  Map<String, Object?> debugMarkerPayload({required int sessionGeneration}) {
    return <String, Object?>{
      'session_generation': sessionGeneration,
      'requested_decoder_preference': requestedDecoderPreference,
      'video_width': videoWidth,
      'video_height': videoHeight,
      'video_codec': videoCodec,
      'audio_codec': audioCodec,
      'audio_sample_rate_hz': audioSampleRate,
      'audio_channels': audioChannels,
      'resolved_decoder_backend': resolvedDecoderBackend,
      'display_video_size': displayVideoSize,
      'display_video_codec': displayVideoCodec,
      'display_audio_codec': displayAudioCodec,
      'display_video_decoder': displayVideoDecoder,
      'first_video_output_ms': firstVideoOutputMs,
      'first_audio_output_ms': firstAudioOutputMs,
      ..._currentStatsPayload(),
      ..._stutterPayload(),
      ..._latencyPayload(),
      'latency_metrics_ok': latencyMetricsValid,
      'latency_metrics_available': latencyReady,
      'period_summary_available': periodSummaryAvailable,
      'period_summary_required_rows': <String, Object?>{
        'stutter': stutterReady,
        'latency_stats': latencyReady,
      },
      'av_output_health_ok': avOutputHealthOk,
      'runtime_focus_log': 'logs/runtime-focus.log',
    };
  }

  Map<String, Object?> smokeDebugMarkerPayload({
    required int sessionGeneration,
  }) {
    return <String, Object?>{
      'session_generation': sessionGeneration,
      'video_width': videoWidth,
      'video_height': videoHeight,
      'video_codec': videoCodec,
      'audio_codec': audioCodec,
      'resolved_decoder_backend': resolvedDecoderBackend,
      'runtime_focus_log': 'logs/runtime-focus.log',
    };
  }

  Map<String, Object?> smokeRenderWindowMarkerPayload({
    required int sessionGeneration,
  }) {
    return <String, Object?>{
      'session_generation': sessionGeneration,
      ..._currentStatsPayload(),
      ..._stutterPayload(),
      ..._latencyPayload(),
      'latency_metrics_ok': latencyMetricsValid,
      'latency_metrics_available': latencyReady,
      'period_summary_available': periodSummaryAvailable,
      'period_summary_required_rows': <String, Object?>{
        'stutter': stutterReady,
        'latency_stats': latencyReady,
      },
      'av_output_health_ok': avOutputHealthOk,
      'runtime_focus_log': 'logs/runtime-focus.log',
    };
  }

  Map<String, Object?> _currentStatsPayload() {
    return <String, Object?>{
      'audio_input_bitrate_kbps': audioInputBitrateKbps,
      'audio_input_packet_rate': audioInputPacketRate,
      'audio_render_callback_rate': audioRenderCallbackRate,
      'audio_output_continuity_ratio': audioOutputContinuityRatio,
      'audio_stats_refresh_interval_ms': audioStatsRefreshIntervalMs,
      'audio_stats_updated_at_ms': audioStatsUpdatedAtMs,
      'audio_output_health_ok': audioOutputHealthOk,
      'video_input_bitrate_kbps': videoInputBitrateKbps,
      'video_input_fps': videoInputFps,
      'video_decoded_fps': videoDecodedFps,
      'video_render_fps': videoRenderFps,
      'video_render_continuity_ratio': videoRenderContinuityRatio,
      'video_stats_refresh_interval_ms': videoStatsRefreshIntervalMs,
      'video_stats_updated_at_ms': videoStatsUpdatedAtMs,
      'video_output_health_ok': videoOutputHealthOk,
    };
  }

  Map<String, Object?> _stutterPayload() {
    return <String, Object?>{
      'audio_stutter_threshold_ms': audioStutterThresholdMs,
      'audio_output_duration_ms': audioOutputDurationMs,
      'audio_stutter_total_ms': audioStutterTotalMs,
      'audio_stutter_count': audioStutterCount,
      'audio_stutter_peak_ms': audioStutterPeakMs,
      'audio_stutter_average_ms': audioStutterAverageMs,
      'audio_stutter_rate': audioStutterRate,
      'video_stutter_threshold_ms': videoStutterThresholdMs,
      'video_output_duration_ms': videoOutputDurationMs,
      'video_stutter_total_ms': videoStutterTotalMs,
      'video_stutter_count': videoStutterCount,
      'video_stutter_peak_ms': videoStutterPeakMs,
      'video_stutter_average_ms': videoStutterAverageMs,
      'video_stutter_rate': videoStutterRate,
    };
  }

  Map<String, Object?> _latencyPayload() {
    return <String, Object?>{
      'audio_estimated_output_latency_ms': audioEstimatedOutputLatencyMs,
      'video_estimated_output_latency_ms': videoEstimatedOutputLatencyMs,
    };
  }
}
