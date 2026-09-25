import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:tirtc_flutter/tirtc_flutter.dart';

import 'demo_call_command.dart';
import 'demo_downlink_support.dart';
import 'widgets/downlink_metrics_overlay_model.dart';

const int _tiRtcErrorInvalidArgument = 6000;
const int _tiRtcErrorOk = 0;
const int _tiRtcErrorInUse = 6026;

final class DemoDownlinkSession {
  DemoDownlinkSession({TiRtcConn? connection})
    : _connection = connection ?? TiRtcConn(),
      _audioOutput = TiRtcAudioOutput(),
      _audioInput = TiRtcAudioInput();

  final TiRtcConn _connection;
  final TiRtcAudioOutput _audioOutput;
  final LinkedHashMap<int, TiRtcVideoOutput> _videoOutputs = LinkedHashMap<int, TiRtcVideoOutput>();
  final TiRtcAudioInput _audioInput;
  Future<int>? _releaseInFlight;
  bool _localAudioAttached = false;
  bool _audioOutputAttached = false;
  int? _audioSubscribeStreamId;
  final Set<int> _videoSubscribeStreamIds = <int>{};
  bool _released = false;
  bool _disposed = false;
  TiRtcRecordingTask? _recordingTask;
  TiRawDump? _rawDump;
  Object? _latestMediaFile;
  final List<Object> _ownedMediaFiles = <Object>[];
  int _pendingVideoDecoderPreference = 0;
  TiRtcOutputBufferStrategy _pendingVideoBufferStrategy = TiRtcOutputBufferStrategy.automatic;
  void Function(int, TiRtcVideoOutputState)? _onVideoStateChangedForStream;
  void Function(int, Size)? _onVideoRenderSizeChangedForStream;
  void Function(int, int)? _onVideoErrorForStream;

  Widget buildVideoView([int? streamId]) =>
      _videoOutputs[streamId ?? _videoOutputs.keys.firstOrNull]?.view() ?? const SizedBox.shrink();

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
    void Function(int streamId, TiRtcVideoOutputState state)? onVideoStateChangedForStream,
    void Function(int streamId, Size size)? onVideoRenderSizeChangedForStream,
    void Function(int streamId, int code)? onVideoErrorForStream,
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
    _onVideoStateChangedForStream =
        onVideoStateChangedForStream ?? (_, TiRtcVideoOutputState state) => onVideoStateChanged(state);
    _onVideoRenderSizeChangedForStream =
        onVideoRenderSizeChangedForStream ??
        (onVideoRenderSizeChanged == null ? null : (_, Size size) => onVideoRenderSizeChanged(size));
    _onVideoErrorForStream = onVideoErrorForStream ?? (_, int code) => onVideoError(code);
    for (final MapEntry<int, TiRtcVideoOutput> entry in _videoOutputs.entries) {
      _bindVideoCallbacks(
        streamId: entry.key,
        output: entry.value,
        onVideoStateChanged: _onVideoStateChangedForStream!,
        onVideoRenderSizeChanged: _onVideoRenderSizeChangedForStream,
        onVideoError: _onVideoErrorForStream!,
      );
    }
    _audioInput.onStateChanged = onAudioInputStateChanged;
    _audioInput.onError = onAudioInputError;
  }

  void clearCallbacks() {
    _connection.onStateChanged = null;
    _connection.onCommand = null;
    _connection.onStreamMessage = null;
    _audioOutput.onStateChanged = null;
    _audioOutput.onError = null;
    for (final TiRtcVideoOutput output in _videoOutputs.values) {
      output.onStateChanged = null;
      output.onRenderSizeChanged = null;
      output.onError = null;
    }
    _onVideoStateChangedForStream = null;
    _onVideoRenderSizeChangedForStream = null;
    _onVideoErrorForStream = null;
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
    final int code = _audioOutput.attach(connection: _connection, streamId: streamId);
    if (code == _tiRtcErrorOk) {
      _audioOutputAttached = true;
      _released = false;
    }
    return code;
  }

  int setAudioOptions({required TiRtcOutputBufferStrategy bufferStrategy}) {
    return _audioOutput.configure(TiRtcAudioOutputOptions(bufferStrategy: bufferStrategy));
  }

  int setAudioOutputVolume(int volumePercent) {
    return _audioOutput.setVolume(volumePercent);
  }

  int setVideoOptions({required int decoderPreference, required TiRtcOutputBufferStrategy bufferStrategy}) {
    _pendingVideoDecoderPreference = decoderPreference;
    _pendingVideoBufferStrategy = bufferStrategy;
    return _tiRtcErrorOk;
  }

  int attachVideo({
    required int streamId,
    int? decoderPreference,
    TiRtcOutputBufferStrategy? bufferStrategy,
    void Function(int streamId, TiRtcVideoOutputState state)? onStateChanged,
    void Function(int streamId, Size size)? onRenderSizeChanged,
    void Function(int streamId, int code)? onError,
  }) {
    final TiRtcVideoOutput output = _videoOutputs[streamId] ?? TiRtcVideoOutput();
    int code = output.setOptions(
      TiRtcVideoOutputOptions(
        decoderPreference: _videoDecoderPreferenceFromNativeValue(decoderPreference ?? _pendingVideoDecoderPreference),
        bufferStrategy: bufferStrategy ?? _pendingVideoBufferStrategy,
      ),
    );
    if (code != _tiRtcErrorOk) {
      if (!_videoOutputs.containsKey(streamId)) output.dispose();
      return code;
    }
    _bindVideoCallbacks(
      streamId: streamId,
      output: output,
      onVideoStateChanged: onStateChanged ?? _onVideoStateChangedForStream ?? (_, __) {},
      onVideoRenderSizeChanged: onRenderSizeChanged ?? _onVideoRenderSizeChangedForStream,
      onVideoError: onError ?? _onVideoErrorForStream ?? (_, __) {},
    );
    code = output.attach(connection: _connection, streamId: streamId);
    if (code != _tiRtcErrorOk) {
      if (!_videoOutputs.containsKey(streamId)) output.dispose();
      return code;
    }
    _videoOutputs[streamId] = output;
    _released = false;
    return _tiRtcErrorOk;
  }

  void _bindVideoCallbacks({
    required int streamId,
    required TiRtcVideoOutput output,
    required void Function(int streamId, TiRtcVideoOutputState state) onVideoStateChanged,
    void Function(int streamId, Size size)? onVideoRenderSizeChanged,
    required void Function(int streamId, int code) onVideoError,
  }) {
    output.onStateChanged = (TiRtcVideoOutputState state) => onVideoStateChanged(streamId, state);
    output.onRenderSizeChanged =
        onVideoRenderSizeChanged == null ? null : (Size size) => onVideoRenderSizeChanged(streamId, size);
    output.onError = (int code) => onVideoError(streamId, code);
  }

  int subscribeAudio({required int streamId}) {
    final int code = _connection.subscribeAudio(streamId: streamId);
    if (code == _tiRtcErrorOk) _audioSubscribeStreamId = streamId;
    return code;
  }

  int subscribeVideo({required int streamId}) {
    final int code = _connection.subscribeVideo(streamId: streamId);
    if (code == _tiRtcErrorOk) _videoSubscribeStreamIds.add(streamId);
    return code;
  }

  int sendCallCommand(DemoCallCommand command) {
    if (!command.valid) {
      return _tiRtcErrorInvalidArgument;
    }
    return _connection.sendCommand(commandId: demoCallCommandId, data: command.encode());
  }

  int sendCommand({required int commandId, required Uint8List payload}) {
    return _connection.sendCommand(commandId: commandId, data: payload);
  }

  int sendStreamMessage({required int streamId, required Uint8List payload, int timestampMs = 0}) {
    return _connection.sendStreamMessage(streamId: streamId, timestampMs: timestampMs, data: payload);
  }

  Future<int> prepareLocalAudio({TiRtcAudioInputOptions audioOptions = const TiRtcAudioInputOptions()}) {
    return _audioInput.setOptions(audioOptions);
  }

  Future<int> attachLocalAudio({required int streamId}) async {
    final int code = await _audioInput.attach(connection: _connection, streamId: streamId);
    if (code == 0) {
      _localAudioAttached = true;
      _released = false;
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

  TiRtcVideoOutputState get videoState => _videoOutputs.values.firstOrNull?.state ?? TiRtcVideoOutputState.idle;

  TiRtcVideoOutputState? videoStateFor(int streamId) => _videoOutputs[streamId]?.state;

  Size? get renderSize => _videoOutputs.values.firstOrNull?.renderSize;

  Size? renderSizeFor(int streamId) => _videoOutputs[streamId]?.renderSize;

  void detachAudio() {
    if (!_audioOutputAttached) return;
    if (_audioOutput.detach() == _tiRtcErrorOk) {
      _audioOutputAttached = false;
    }
  }

  int resetOutputMetricsSession() {
    int code = _audioOutput.resetMetricsSession();
    if (code != 0) {
      return code;
    }
    for (final TiRtcVideoOutput output in _videoOutputs.values) {
      code = output.resetMetricsSession();
      if (code != 0) return code;
    }
    return _tiRtcErrorOk;
  }

  void disconnectConnection() {
    _connection.disconnect();
  }

  bool get isRecording => _recordingTask != null;

  Future<Resp<TiRawDump>> startRawDump({
    int? audioStreamId,
    required List<int> videoStreamIds,
    required int localAudioStreamId,
  }) async {
    final TiRawDump? active = _rawDump;
    if (active != null) return const Resp<TiRawDump>.failure(_tiRtcErrorInUse);
    final Resp<TiRawDump> result = await _connection.startRawDump(
      TiRtcRawDumpOptions(
        audioStreamIds: audioStreamId == null ? const <int>[] : <int>[audioStreamId],
        videoStreamIds: videoStreamIds,
        uplinkAudioStreamIds: <int>[localAudioStreamId],
      ),
    );
    if (result.success) _rawDump = result.data;
    return result;
  }

  Future<Resp<TiRawDumpArchive>> stopRawDump() async {
    final TiRawDump? dump = _rawDump;
    if (dump == null) return const Resp<TiRawDumpArchive>.failure(_tiRtcErrorInUse);
    final Resp<TiRawDumpArchive> result = await dump.stop();
    if (result.success || result.code != _tiRtcErrorInUse) _rawDump = null;
    return result;
  }

  Resp<TiRtcRecordingTask> startRecording({required int videoStreamId, int? audioStreamId}) {
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

  Future<Resp<TiRtcSnapshotFile>> takeSnapshot({required int videoStreamId}) async {
    final TiRtcVideoOutput? output = _videoOutputs[videoStreamId];
    if (output == null) return const Resp<TiRtcSnapshotFile>.failure(_tiRtcErrorInvalidArgument);
    final Resp<TiRtcSnapshotFile> result = await output.takeSnapshot();
    if (result.success && result.data != null) {
      _latestMediaFile = result.data;
      _ownedMediaFiles.add(result.data!);
    }
    return result;
  }

  Future<Resp<TiRtcGalleryAsset>> moveLatestMediaToGallery({String? fileName}) {
    final Object? mediaFile = _latestMediaFile;
    if (mediaFile is TiRtcRecordingFile) {
      return _moveToGallery(mediaFile, () => mediaFile.moveToGallery(fileName: fileName ?? demoGalleryFileName('mp4')));
    }
    if (mediaFile is TiRtcSnapshotFile) {
      return _moveToGallery(mediaFile, () => mediaFile.moveToGallery(fileName: fileName ?? demoGalleryFileName('jpg')));
    }
    return Future<Resp<TiRtcGalleryAsset>>.value(const Resp<TiRtcGalleryAsset>.failure(_tiRtcErrorInUse));
  }

  Future<Resp<TiRtcGalleryAsset>> _moveToGallery(
    Object mediaFile,
    Future<Resp<TiRtcGalleryAsset>> Function() move,
  ) async {
    final Resp<TiRtcGalleryAsset> result = await move();
    if (result.success) {
      _ownedMediaFiles.remove(mediaFile);
      if (identical(_latestMediaFile, mediaFile)) {
        _latestMediaFile = null;
      }
    }
    return result;
  }

  bool get hasPendingGalleryMedia => _latestMediaFile != null;

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

    if (_rawDump != null) {
      final Resp<TiRawDumpArchive> result = await stopRawDump();
      recordError(result.code ?? _tiRtcErrorOk);
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

    for (final int videoSubscribeStreamId in _videoSubscribeStreamIds.toList()) {
      final int code = _connection.unsubscribeVideo(streamId: videoSubscribeStreamId);
      if (code == _tiRtcErrorOk) {
        _videoSubscribeStreamIds.remove(videoSubscribeStreamId);
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

    for (final TiRtcVideoOutput output in _videoOutputs.values) {
      recordError(output.detach());
    }
    if (_audioOutputAttached) {
      final int code = _audioOutput.detach();
      if (code == _tiRtcErrorOk) {
        _audioOutputAttached = false;
      }
      recordError(code);
    }
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

  DownlinkMetricsOverlayModel? readMetricsOverlay({required int requestedDecoderPreference, int? videoStreamId}) {
    final TiRtcConnMetricsResult connResult = _connection.getMetricsSnapshot();
    final TiRtcVideoOutput? videoOutput = videoStreamId == null ? null : _videoOutputs[videoStreamId];
    final TiRtcVideoOutputMetricsResult? videoResult = videoOutput?.getMetricsSnapshot();
    final TiRtcAudioOutputMetricsResult? audioResult = _audioOutputAttached ? _audioOutput.getMetricsSnapshot() : null;
    if (connResult.code != 0 || (videoResult != null && videoResult.code != 0)) {
      return null;
    }

    final TiRtcConnMetricsSnapshot? connSnapshot = connResult.snapshot;
    final TiRtcVideoOutputMetricsSnapshot? videoSnapshot = videoResult?.snapshot;
    final TiRtcAudioOutputMetricsSnapshot? audioSnapshot =
        audioResult?.code == _tiRtcErrorOk ? audioResult?.snapshot : null;
    if (connSnapshot == null || (videoOutput != null && videoSnapshot == null)) {
      return null;
    }

    final TiRtcAudioOutputDebugSnapshotResult? audioDebugResult =
        _audioOutputAttached ? _audioOutput.getDebugSnapshot() : null;
    final TiRtcVideoOutputDebugSnapshotResult? videoDebugResult = videoOutput?.getDebugSnapshot();
    final TiRtcAudioOutputDebugSnapshot? audioDebugSnapshot =
        audioDebugResult?.code == 0 ? audioDebugResult?.snapshot : null;
    final TiRtcVideoOutputDebugSnapshot? videoDebugSnapshot =
        videoDebugResult?.code == 0 ? videoDebugResult?.snapshot : null;
    final int videoWidth = videoSnapshot?.videoWidth ?? 0;
    final int videoHeight = videoSnapshot?.videoHeight ?? 0;
    final int videoCodec = videoSnapshot?.videoCodec ?? 0;
    final int audioCodec = audioSnapshot?.audioCodec ?? 0;
    final int audioSampleRate = audioSnapshot?.audioSampleRateHz ?? 0;
    final int audioChannels = audioSnapshot?.audioChannels ?? 0;
    final int decoderBackend = videoSnapshot?.decoderBackend ?? 0;

    return DownlinkMetricsOverlayModel(
      connectDurationMs: connSnapshot.connectDurationMs,
      firstVideoOutputMs: videoSnapshot?.startup.timeToFirstOutputMs,
      firstAudioOutputMs: audioSnapshot?.startup.timeToFirstOutputMs,
      videoWidth: videoWidth > 0 ? videoWidth : videoDebugSnapshot?.width,
      videoHeight: videoHeight > 0 ? videoHeight : videoDebugSnapshot?.height,
      videoCodec: videoCodec != 0 ? videoCodec : videoDebugSnapshot?.codec,
      audioCodec: audioCodec != 0 ? audioCodec : audioDebugSnapshot?.codec,
      audioSampleRate: audioSampleRate > 0 ? audioSampleRate : audioDebugSnapshot?.sampleRate,
      audioChannels: audioChannels > 0 ? audioChannels : audioDebugSnapshot?.channels,
      requestedDecoderPreference: requestedDecoderPreference,
      resolvedDecoderBackend: decoderBackend != 0 ? decoderBackend : videoDebugSnapshot?.resolvedDecoderBackend,
      audioInputBitrateKbps: audioSnapshot?.audioInputBitrateKbps,
      audioInputPacketRate: audioSnapshot?.audioInputPacketRate,
      audioRenderCallbackRate: audioSnapshot?.audioRenderCallbackRate,
      audioStatsRefreshIntervalMs: audioSnapshot?.statsRefreshIntervalMs,
      audioStatsUpdatedAtMs: audioSnapshot?.statsUpdatedAtMs,
      audioStutterThresholdMs: audioSnapshot?.stutter.stutterThresholdMs,
      audioOutputDurationMs: audioSnapshot?.stutter.outputDurationMs,
      audioStutterTotalMs: audioSnapshot?.stutter.stutterTotalMs,
      audioStutterCount: audioSnapshot?.stutter.stutterCount,
      audioStutterPeakMs: audioSnapshot?.stutter.stutterPeakMs,
      audioStutterAverageMs: audioSnapshot?.stutter.stutterAverageMs,
      audioStutterRate: audioSnapshot?.stutter.stutterRate,
      audioEstimatedOutputLatencyMs: audioSnapshot?.estimatedOutputLatencyMs,
      videoInputBitrateKbps: videoSnapshot?.videoInputBitrateKbps,
      videoInputFps: videoSnapshot?.videoInputFps,
      videoDecodedFps: videoSnapshot?.videoDecodedFps,
      videoRenderFps: videoSnapshot?.videoRenderFps,
      videoStatsRefreshIntervalMs: videoSnapshot?.statsRefreshIntervalMs,
      videoStatsUpdatedAtMs: videoSnapshot?.statsUpdatedAtMs,
      videoStutterThresholdMs: videoSnapshot?.stutter.stutterThresholdMs,
      videoOutputDurationMs: videoSnapshot?.stutter.outputDurationMs,
      videoStutterTotalMs: videoSnapshot?.stutter.stutterTotalMs,
      videoStutterCount: videoSnapshot?.stutter.stutterCount,
      videoStutterPeakMs: videoSnapshot?.stutter.stutterPeakMs,
      videoStutterAverageMs: videoSnapshot?.stutter.stutterAverageMs,
      videoStutterRate: videoSnapshot?.stutter.stutterRate,
      videoEstimatedOutputLatencyMs: videoSnapshot?.estimatedOutputLatencyMs,
    );
  }

  TiRtcVideoOutputMetricsResult videoMetrics([int? streamId]) {
    final TiRtcVideoOutput? output = _videoOutputs[streamId ?? _videoOutputs.keys.firstOrNull];
    return output?.getMetricsSnapshot() ?? (code: _tiRtcErrorInUse, snapshot: null);
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
    for (final TiRtcVideoOutput output in _videoOutputs.values) {
      code = await _disposeVideoOutputWithTextureRetry(output);
      if (code != _tiRtcErrorOk) return code;
    }
    _videoOutputs.clear();
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

  Future<int> _disposeVideoOutputWithTextureRetry(TiRtcVideoOutput output) async {
    const int maxAttempts = 50;
    for (int attempt = 1; attempt <= maxAttempts; attempt += 1) {
      final int code = output.dispose();
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
