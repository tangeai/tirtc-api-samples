import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:tirtc_flutter/tirtc_flutter.dart';

import 'demo_call_command.dart';
import 'widgets/downlink_metrics_overlay_model.dart';

const int _tiRtcErrorInvalidArgument = 6000;

final class DemoDownlinkSession {
  DemoDownlinkSession({TiRtcConn? connection})
      : _connection = connection ?? TiRtcConn(),
        _audioOutput = TiRtcAudioOutput(),
        _videoOutput = TiRtcVideoOutput(),
        _audioInput = TiRtcAudioInput();

  final TiRtcConn _connection;
  final TiRtcAudioOutput _audioOutput;
  final TiRtcVideoOutput _videoOutput;
  final TiRtcAudioInput _audioInput;
  Future<void>? _releaseInFlight;
  bool _localAudioAttached = false;
  int? _audioSubscribeStreamId;
  int? _videoSubscribeStreamId;
  bool _released = false;
  bool _disposed = false;

  Widget buildVideoView() => _videoOutput.view();

  void setCommandCallback(TiRtcOnConnCommand? onCommand) {
    _connection.onCommand = onCommand;
  }

  void bindCallbacks({
    required TiRtcOnConnStateChanged onConnectionStateChanged,
    required TiRtcOnAudioOutputStateChanged onAudioStateChanged,
    required TiRtcOnAudioOutputError onAudioError,
    required TiRtcOnVideoOutputStateChanged onVideoStateChanged,
    TiRtcOnVideoOutputRenderSizeChanged? onVideoRenderSizeChanged,
    required TiRtcOnVideoOutputError onVideoError,
    TiRtcOnConnCommand? onCommand,
    TiRtcOnInputStateChanged? onAudioInputStateChanged,
    TiRtcOnInputError? onAudioInputError,
    TiRtcOnConnStreamMessage? onStreamMessage,
  }) {
    _connection.onStateChanged = onConnectionStateChanged;
    _connection.onCommand = onCommand;
    _connection.onStreamMessage = onStreamMessage;
    _audioOutput.onStateChanged = onAudioStateChanged;
    _audioOutput.onError = onAudioError;
    _videoOutput.onStateChanged = onVideoStateChanged;
    _videoOutput.onRenderSizeChanged = onVideoRenderSizeChanged;
    _videoOutput.onError = onVideoError;
    _audioInput.onStateChanged = onAudioInputStateChanged;
    _audioInput.onError = onAudioInputError;
  }

  void clearCallbacks() {
    _connection.onStateChanged = null;
    _connection.onCommand = null;
    _connection.onStreamMessage = null;
    _audioOutput.onStateChanged = null;
    _audioOutput.onError = null;
    _videoOutput.onStateChanged = null;
    _videoOutput.onRenderSizeChanged = null;
    _videoOutput.onError = null;
    _audioInput.onStateChanged = null;
    _audioInput.onError = null;
  }

  int connect({required String remoteId, required String token}) {
    final int code = _connection.connect(remoteId: remoteId, token: token);
    if (code == 0) {
      _released = false;
    }
    return code;
  }

  int attachAudio({required int streamId}) {
    return _audioOutput.attach(connection: _connection, streamId: streamId);
  }

  int setAudioOptions({required TiRtcOutputBufferStrategy bufferStrategy}) {
    return _audioOutput.configure(
      TiRtcAudioOutputOptions(bufferStrategy: bufferStrategy),
    );
  }

  int setAudioOutputVolume(int volumePercent) {
    return _audioOutput.setVolume(volumePercent);
  }

  int setVideoOptions({
    required int decoderPreference,
    required TiRtcOutputBufferStrategy bufferStrategy,
  }) {
    return _videoOutput.setOptions(
      TiRtcVideoOutputOptions(
        decoderPreference: _videoDecoderPreferenceFromNativeValue(
          decoderPreference,
        ),
        bufferStrategy: bufferStrategy,
      ),
    );
  }

  int attachVideo({required int streamId}) {
    return _videoOutput.attach(connection: _connection, streamId: streamId);
  }

  int subscribeAudio({required int streamId}) {
    _audioSubscribeStreamId = streamId;
    return _connection.subscribeAudio(streamId: streamId);
  }

  int subscribeVideo({required int streamId}) {
    _videoSubscribeStreamId = streamId;
    return _connection.subscribeVideo(streamId: streamId);
  }

  int sendCallCommand(DemoCallCommand command) {
    if (!command.valid) {
      return _tiRtcErrorInvalidArgument;
    }
    return _connection.sendCommand(
      commandId: demoCallCommandId,
      data: command.encode(),
    );
  }

  int sendCommand({required int commandId, required Uint8List payload}) {
    return _connection.sendCommand(commandId: commandId, data: payload);
  }

  int sendStreamMessage({
    required int streamId,
    required Uint8List payload,
    int timestampMs = 0,
  }) {
    return _connection.sendStreamMessage(
      streamId: streamId,
      timestampMs: timestampMs,
      data: payload,
    );
  }

  Future<int> prepareLocalAudio({
    TiRtcAudioInputOptions audioOptions = const TiRtcAudioInputOptions(),
  }) {
    return _audioInput.setOptions(audioOptions);
  }

  Future<int> attachLocalAudio({required int streamId}) async {
    final int code = await _audioInput.attach(
      connection: _connection,
      streamId: streamId,
    );
    if (code == 0) {
      _localAudioAttached = true;
    }
    return code;
  }

  Future<int> startLocalAudio() => _audioInput.start();

  Future<int> stopLocalAudio() => _audioInput.stop();

  Future<void> detachLocalAudioFromBoundConnection() async {
    if (!_localAudioAttached) {
      return;
    }
    _localAudioAttached = false;
    await _audioInput.detach(connection: _connection);
  }

  TiRtcAudioOutputState get audioState => _audioOutput.state;

  TiRtcVideoOutputState get videoState => _videoOutput.state;

  Size? get renderSize => _videoOutput.renderSize;

  void detachAudio() {
    _audioOutput.detach();
  }

  int resetOutputMetricsSession() {
    int code = _audioOutput.resetMetricsSession();
    if (code != 0) {
      return code;
    }
    code = _videoOutput.resetMetricsSession();
    return code;
  }

  void disconnectConnection() {
    _connection.disconnect();
  }

  Future<void> release({required String reason}) async {
    final Future<void>? releaseInFlight = _releaseInFlight;
    if (releaseInFlight != null) {
      TiRtcLogging.i('flutter_example', 'downlink_release_joined reason=$reason');
      await releaseInFlight;
      return;
    }
    if (_released) {
      TiRtcLogging.i('flutter_example', 'downlink_release_skipped reason=$reason');
      return;
    }
    _released = true;
    TiRtcLogging.i('flutter_example', 'downlink_release_requested reason=$reason');
    final Future<void> releaseFuture = _performRelease();
    _releaseInFlight = releaseFuture;
    try {
      await releaseFuture;
    } finally {
      if (identical(_releaseInFlight, releaseFuture)) {
        _releaseInFlight = null;
      }
    }
  }

  Future<void> _performRelease() async {
    final int? videoSubscribeStreamId = _videoSubscribeStreamId;
    _videoSubscribeStreamId = null;
    if (videoSubscribeStreamId != null) {
      final int code = _connection.unsubscribeVideo(streamId: videoSubscribeStreamId);
      if (code != 0) {
        TiRtcLogging.w(
          'flutter_example',
          'video_unsubscribe_cleanup_failed stream_id=$videoSubscribeStreamId code=$code',
        );
      }
    }

    final int? audioSubscribeStreamId = _audioSubscribeStreamId;
    _audioSubscribeStreamId = null;
    if (audioSubscribeStreamId != null) {
      final int code = _connection.unsubscribeAudio(streamId: audioSubscribeStreamId);
      if (code != 0) {
        TiRtcLogging.w(
          'flutter_example',
          'audio_unsubscribe_cleanup_failed stream_id=$audioSubscribeStreamId code=$code',
        );
      }
    }

    _videoOutput.detach();
    _audioOutput.detach();
    await _audioInput.stop();
    await detachLocalAudioFromBoundConnection();
    _connection.disconnect();
  }

  DownlinkMetricsOverlayModel? readMetricsOverlay({
    required int requestedDecoderPreference,
  }) {
    final TiRtcConnMetricsResult connResult = _connection.getMetricsSnapshot();
    final TiRtcVideoOutputMetricsResult videoResult = _videoOutput.getMetricsSnapshot();
    final TiRtcAudioOutputMetricsResult audioResult = _audioOutput.getMetricsSnapshot();
    if (connResult.code != 0 || videoResult.code != 0 || audioResult.code != 0) {
      return null;
    }

    final TiRtcConnMetricsSnapshot? connSnapshot = connResult.snapshot;
    final TiRtcVideoOutputMetricsSnapshot? videoSnapshot = videoResult.snapshot;
    final TiRtcAudioOutputMetricsSnapshot? audioSnapshot = audioResult.snapshot;
    if (connSnapshot == null || videoSnapshot == null || audioSnapshot == null) {
      return null;
    }

    final TiRtcAudioOutputDebugSnapshotResult audioDebugResult = _audioOutput.getDebugSnapshot();
    final TiRtcVideoOutputDebugSnapshotResult videoDebugResult = _videoOutput.getDebugSnapshot();
    final TiRtcAudioOutputDebugSnapshot? audioDebugSnapshot =
        audioDebugResult.code == 0 ? audioDebugResult.snapshot : null;
    final TiRtcVideoOutputDebugSnapshot? videoDebugSnapshot =
        videoDebugResult.code == 0 ? videoDebugResult.snapshot : null;
    final int videoWidth = videoSnapshot.videoWidth;
    final int videoHeight = videoSnapshot.videoHeight;
    final int videoCodec = videoSnapshot.videoCodec;
    final int audioCodec = audioSnapshot.audioCodec;
    final int audioSampleRate = audioSnapshot.audioSampleRateHz;
    final int audioChannels = audioSnapshot.audioChannels;
    final int decoderBackend = videoSnapshot.decoderBackend;

    return DownlinkMetricsOverlayModel(
      connectDurationMs: connSnapshot.connectDurationMs,
      firstVideoOutputMs: videoSnapshot.startup.timeToFirstOutputMs,
      firstAudioOutputMs: audioSnapshot.startup.timeToFirstOutputMs,
      videoWidth: videoWidth > 0 ? videoWidth : videoDebugSnapshot?.width,
      videoHeight: videoHeight > 0 ? videoHeight : videoDebugSnapshot?.height,
      videoCodec: videoCodec != 0 ? videoCodec : videoDebugSnapshot?.codec,
      audioCodec: audioCodec != 0 ? audioCodec : audioDebugSnapshot?.codec,
      audioSampleRate: audioSampleRate > 0 ? audioSampleRate : audioDebugSnapshot?.sampleRate,
      audioChannels: audioChannels > 0 ? audioChannels : audioDebugSnapshot?.channels,
      requestedDecoderPreference: requestedDecoderPreference,
      resolvedDecoderBackend: decoderBackend != 0 ? decoderBackend : videoDebugSnapshot?.resolvedDecoderBackend,
      audioInputBitrateKbps: audioSnapshot.audioInputBitrateKbps,
      audioInputPacketRate: audioSnapshot.audioInputPacketRate,
      audioRenderCallbackRate: audioSnapshot.audioRenderCallbackRate,
      audioStatsRefreshIntervalMs: audioSnapshot.statsRefreshIntervalMs,
      audioStatsUpdatedAtMs: audioSnapshot.statsUpdatedAtMs,
      audioStutterThresholdMs: audioSnapshot.stutter.stutterThresholdMs,
      audioOutputDurationMs: audioSnapshot.stutter.outputDurationMs,
      audioStutterTotalMs: audioSnapshot.stutter.stutterTotalMs,
      audioStutterCount: audioSnapshot.stutter.stutterCount,
      audioStutterPeakMs: audioSnapshot.stutter.stutterPeakMs,
      audioStutterAverageMs: audioSnapshot.stutter.stutterAverageMs,
      audioStutterRate: audioSnapshot.stutter.stutterRate,
      audioEstimatedOutputLatencyMs: audioSnapshot.estimatedOutputLatencyMs,
      videoInputBitrateKbps: videoSnapshot.videoInputBitrateKbps,
      videoInputFps: videoSnapshot.videoInputFps,
      videoDecodedFps: videoSnapshot.videoDecodedFps,
      videoRenderFps: videoSnapshot.videoRenderFps,
      videoStatsRefreshIntervalMs: videoSnapshot.statsRefreshIntervalMs,
      videoStatsUpdatedAtMs: videoSnapshot.statsUpdatedAtMs,
      videoStutterThresholdMs: videoSnapshot.stutter.stutterThresholdMs,
      videoOutputDurationMs: videoSnapshot.stutter.outputDurationMs,
      videoStutterTotalMs: videoSnapshot.stutter.stutterTotalMs,
      videoStutterCount: videoSnapshot.stutter.stutterCount,
      videoStutterPeakMs: videoSnapshot.stutter.stutterPeakMs,
      videoStutterAverageMs: videoSnapshot.stutter.stutterAverageMs,
      videoStutterRate: videoSnapshot.stutter.stutterRate,
      videoEstimatedOutputLatencyMs: videoSnapshot.estimatedOutputLatencyMs,
    );
  }

  TiRtcVideoOutputMetricsResult videoMetrics() {
    return _videoOutput.getMetricsSnapshot();
  }

  TiRtcAudioOutputMetricsResult audioMetrics() {
    return _audioOutput.getMetricsSnapshot();
  }

  void dispose() {
    unawaited(disposeAsync());
  }

  Future<void> disposeAsync() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await release(reason: 'session_dispose');
    await _audioInput.dispose();
    _videoOutput.dispose();
    _audioOutput.dispose();
    _connection.dispose();
  }
}

TiRtcVideoDecoderPreference _videoDecoderPreferenceFromNativeValue(int value) {
  return switch (value) {
    1 => TiRtcVideoDecoderPreference.software,
    2 => TiRtcVideoDecoderPreference.hardware,
    _ => TiRtcVideoDecoderPreference.auto,
  };
}
