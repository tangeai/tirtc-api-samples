import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:tirtc_flutter/tirtc_flutter.dart';

import 'demo_call_command.dart';
import 'widgets/downlink_metrics_overlay_model.dart';

const int _tiRtcErrorInvalidArgument = 6000;
const int _tiRtcErrorOk = 0;
const int _tiRtcErrorInUse = 6026;

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
  Future<int>? _releaseInFlight;
  bool _localAudioAttached = false;
  int? _audioSubscribeStreamId;
  int? _videoSubscribeStreamId;
  bool _released = false;
  bool _disposed = false;
  TiRtcRecordingTask? _recordingTask;
  Object? _latestMediaFile;
  final List<Object> _ownedMediaFiles = <Object>[];

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

  bool get isRecording => _recordingTask != null;

  Resp<TiRtcRecordingTask> startRecording({
    required int videoStreamId,
    required int audioStreamId,
  }) {
    if (_recordingTask != null) {
      return const Resp<TiRtcRecordingTask>.failure(_tiRtcErrorInUse);
    }
    final Resp<TiRtcRecordingTask> result = _connection.startRecording(
      videoStreamId: videoStreamId,
      audioStreamId: audioStreamId,
    );
    if (result.success) {
      _recordingTask = result.data;
    }
    return result;
  }

  Future<Resp<TiRtcRecordingFile>> stopRecording() async {
    final TiRtcRecordingTask? task = _recordingTask;
    if (task == null) {
      return const Resp<TiRtcRecordingFile>.failure(_tiRtcErrorInUse);
    }
    final Resp<TiRtcRecordingFile> result = await task.stop();
    _recordingTask = null;
    if (result.success && result.data != null) {
      _latestMediaFile = result.data;
      _ownedMediaFiles.add(result.data!);
    }
    return result;
  }

  Future<Resp<TiRtcSnapshotFile>> takeSnapshot() async {
    final Resp<TiRtcSnapshotFile> result = await _videoOutput.takeSnapshot();
    if (result.success && result.data != null) {
      _latestMediaFile = result.data;
      _ownedMediaFiles.add(result.data!);
    }
    return result;
  }

  Future<Resp<TiRtcGalleryAsset>> moveLatestMediaToGallery() {
    final Object? mediaFile = _latestMediaFile;
    if (mediaFile is TiRtcRecordingFile) {
      return _moveToGallery(mediaFile, mediaFile.moveToGallery);
    }
    if (mediaFile is TiRtcSnapshotFile) {
      return _moveToGallery(mediaFile, mediaFile.moveToGallery);
    }
    return Future<Resp<TiRtcGalleryAsset>>.value(
      const Resp<TiRtcGalleryAsset>.failure(_tiRtcErrorInUse),
    );
  }

  Future<Resp<TiRtcGalleryAsset>> _moveToGallery(
    Object mediaFile,
    Future<Resp<TiRtcGalleryAsset>> Function() move,
  ) async {
    final Resp<TiRtcGalleryAsset> result = await move();
    if (result.success) {
      _ownedMediaFiles.remove(mediaFile);
    }
    return result;
  }

  String? get latestMediaPath {
    final Object? mediaFile = _latestMediaFile;
    if (mediaFile is TiRtcRecordingFile) return mediaFile.path;
    if (mediaFile is TiRtcSnapshotFile) return mediaFile.path;
    return null;
  }

  String? get latestMediaType {
    final Object? mediaFile = _latestMediaFile;
    if (mediaFile is TiRtcRecordingFile) return 'video';
    if (mediaFile is TiRtcSnapshotFile) return 'image';
    return null;
  }

  Future<int> release({required String reason}) async {
    final Future<int>? releaseInFlight = _releaseInFlight;
    if (releaseInFlight != null) {
      TiRtcLogging.i('flutter_example', 'downlink_release_joined reason=$reason');
      return releaseInFlight;
    }
    if (_released) {
      TiRtcLogging.i('flutter_example', 'downlink_release_skipped reason=$reason');
      return _tiRtcErrorOk;
    }
    TiRtcLogging.i('flutter_example', 'downlink_release_requested reason=$reason');
    final Future<int> releaseFuture = _performRelease();
    _releaseInFlight = releaseFuture;
    try {
      final int code = await releaseFuture;
      if (code == _tiRtcErrorOk) {
        _released = true;
      }
      return code;
    } finally {
      if (identical(_releaseInFlight, releaseFuture)) {
        _releaseInFlight = null;
      }
    }
  }

  Future<int> _performRelease() async {
    int firstError = _tiRtcErrorOk;
    void recordError(int code) {
      if (code != _tiRtcErrorOk && firstError == _tiRtcErrorOk) {
        firstError = code;
      }
    }

    if (_recordingTask != null) {
      final Resp<TiRtcRecordingFile> result = await stopRecording();
      recordError(result.code ?? _tiRtcErrorOk);
    }

    for (final Object mediaFile in _ownedMediaFiles.toList()) {
      final int code = switch (mediaFile) {
        TiRtcRecordingFile file => await file.delete(),
        TiRtcSnapshotFile file => await file.delete(),
        _ => _tiRtcErrorInvalidArgument,
      };
      recordError(code);
      if (code == _tiRtcErrorOk) {
        _ownedMediaFiles.remove(mediaFile);
      }
    }
    if (_ownedMediaFiles.isEmpty) {
      _latestMediaFile = null;
    }

    final int? videoSubscribeStreamId = _videoSubscribeStreamId;
    if (videoSubscribeStreamId != null) {
      final int code = _connection.unsubscribeVideo(streamId: videoSubscribeStreamId);
      if (code == _tiRtcErrorOk) {
        _videoSubscribeStreamId = null;
      } else {
        recordError(code);
        TiRtcLogging.w(
          'flutter_example',
          'video_unsubscribe_cleanup_failed stream_id=$videoSubscribeStreamId code=$code',
        );
      }
    }

    final int? audioSubscribeStreamId = _audioSubscribeStreamId;
    if (audioSubscribeStreamId != null) {
      final int code = _connection.unsubscribeAudio(streamId: audioSubscribeStreamId);
      if (code == _tiRtcErrorOk) {
        _audioSubscribeStreamId = null;
      } else {
        recordError(code);
        TiRtcLogging.w(
          'flutter_example',
          'audio_unsubscribe_cleanup_failed stream_id=$audioSubscribeStreamId code=$code',
        );
      }
    }

    recordError(_videoOutput.detach());
    recordError(_audioOutput.detach());
    recordError(await _audioInput.stop());
    if (_localAudioAttached) {
      final int detachCode = await _audioInput.detach(connection: _connection);
      if (detachCode == _tiRtcErrorOk) {
        _localAudioAttached = false;
      }
      recordError(detachCode);
    }
    recordError(_connection.disconnect());
    return firstError;
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

  Future<int> disposeAsync() async {
    if (_disposed) {
      return _tiRtcErrorOk;
    }
    int code = await release(reason: 'session_dispose');
    if (code != _tiRtcErrorOk) {
      return code;
    }
    code = await _audioInput.dispose();
    if (code != _tiRtcErrorOk) {
      return code;
    }
    code = await _disposeVideoOutputWithTextureRetry();
    if (code != _tiRtcErrorOk) {
      return code;
    }
    code = _audioOutput.dispose();
    if (code != _tiRtcErrorOk) {
      return code;
    }
    code = _connection.dispose();
    if (code != _tiRtcErrorOk) {
      return code;
    }
    _disposed = true;
    TiRtcLogging.i('flutter_example', 'downlink_dispose_completed');
    return _tiRtcErrorOk;
  }

  Future<int> _disposeVideoOutputWithTextureRetry() async {
    const int maxAttempts = 50;
    for (int attempt = 1; attempt <= maxAttempts; attempt += 1) {
      final int code = _videoOutput.dispose();
      if (code != _tiRtcErrorInUse || attempt == maxAttempts) {
        return code;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return _tiRtcErrorInUse;
  }
}

TiRtcVideoDecoderPreference _videoDecoderPreferenceFromNativeValue(int value) {
  return switch (value) {
    1 => TiRtcVideoDecoderPreference.software,
    2 => TiRtcVideoDecoderPreference.hardware,
    _ => TiRtcVideoDecoderPreference.auto,
  };
}
