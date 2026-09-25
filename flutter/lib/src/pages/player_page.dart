import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:tirtc_flutter/tirtc_flutter.dart';

import '../app_theme.dart';
import '../demo_configuration.dart';
import '../demo_downlink_session.dart';
import '../demo_downlink_support.dart';
import '../demo_media_operation_barrier.dart';
import '../demo_permissions.dart';
import '../demo_route_lifecycle.dart';
import '../demo_stream_message.dart';
import '../demo_test_hooks.dart';
import '../demo_widget_keys.dart';
import '../widgets/notice_dialog.dart';
import '../widgets/downlink_center_loading.dart';
import '../widgets/downlink_metrics_overlay.dart';
import '../widgets/downlink_metrics_overlay_markers.dart';
import '../widgets/downlink_metrics_overlay_model.dart';
import '../widgets/player_page_widgets.dart';
import '../widgets/raw_dump_button.dart';
import '../widgets/stream_message_bubble.dart';
import 'player_command_controller.dart';
import 'player_local_audio_controller.dart';
import 'player_log_upload_controller.dart';

part 'player_media_file_actions.dart';
part 'player_raw_dump_actions.dart';

enum _DownlinkViewState { idle, connecting, playing, failed }

class DemoPlayerPage extends StatefulWidget {
  const DemoPlayerPage({
    super.key,
    required this.configuration,
    this.smokeMarkerSink,
    this.smokeRenderWindowSeconds = 30,
  });

  final DemoDownlinkConfiguration configuration;
  final DemoAutomationMarkerSink? smokeMarkerSink;
  final int smokeRenderWindowSeconds;

  @override
  State<DemoPlayerPage> createState() => _DemoPlayerPageState();
}

class _DemoPlayerPageState extends State<DemoPlayerPage>
    with WidgetsBindingObserver, ExampleRouteLifecycleState<DemoPlayerPage> {
  static const Duration _metricsPollInterval = Duration(seconds: 1);

  final DemoDownlinkAudioSession _audioSession = DemoDownlinkAudioSession();
  late final DemoDownlinkSession _session;
  late final DemoPlayerCommandController _commandController;
  late final DemoPlayerLocalAudioController _localAudioController;
  late final DemoPlayerLogUploadController _logUploadController;
  late final DemoRawDumpController _rawDumpController;

  _DownlinkViewState _downlinkState = _DownlinkViewState.idle;
  String _stageStatusLabel = '加载中';
  bool _shouldKeepPlaying = true;
  int _sessionGeneration = 0;
  bool _commandConnected = false;
  bool _audioMuted = false;
  bool _audioOutputAvailable = false;
  bool _mediaFileBusy = false;
  final DemoMediaOperationBarrier _mediaOperationBarrier = DemoMediaOperationBarrier();
  bool _smokeConnectedMarked = false;
  bool _smokeAudioPlayingMarked = false;
  bool _smokeVideoRenderingMarked = false;
  bool _smokeMultiVideoRenderingMarked = false;
  final Set<int> _smokePendingVideoStreamIds = <int>{};
  final Set<int> _smokeRenderedVideoStreamIds = <int>{};
  final Map<int, TiRtcVideoOutputState> _videoStates = <int, TiRtcVideoOutputState>{};
  final Map<int, String> _videoStatusLabels = <int, String>{};
  int? _selectedVideoStreamId;
  int? _maximizedVideoStreamId;
  int? _recordingVideoStreamId;
  int? _latestMediaVideoStreamId;

  void _setMediaFileBusy(bool value) {
    if (mounted) setState(() => _mediaFileBusy = value);
  }

  bool _smokeDebugStatsMarked = false;
  bool _smokeRenderWindowStarted = false;
  bool _smokeRenderWindowMarked = false;
  int _smokeAudioErrorCount = 0;
  int _smokeVideoErrorCount = 0;
  Timer? _metricsPollTimer;
  DownlinkMetricsOverlayModel? _metricsOverlay;
  DownlinkMetricsOverlayModel? _lastAvStatsOverlay;
  final DemoStreamMessageOverlayController _streamMessageOverlay = DemoStreamMessageOverlayController();
  final FocusNode _commandButtonFocusNode = FocusNode(debugLabel: 'player-command-button');

  void _notifyRawDumpChanged() => setState(() {});

  @override
  void initState() {
    super.initState();
    _selectedVideoStreamId = widget.configuration.videoStreamIds.firstOrNull;
    _session = DemoDownlinkSession();
    _commandController = DemoPlayerCommandController(
      session: _session,
      onChanged: () {
        if (mounted) {
          setState(() {});
        }
      },
    );
    _localAudioController = DemoPlayerLocalAudioController(
      session: _session,
      settings: () => widget.configuration.settings,
      isMounted: () => mounted,
      isCommandConnected: () => _commandConnected,
      markerSink: () => widget.smokeMarkerSink,
      onChanged: () {
        if (mounted) {
          setState(() {});
        }
      },
      showMessage: _showPlayerSnack,
    );
    _logUploadController = DemoPlayerLogUploadController(
      isMounted: () => mounted,
      markerSink: () => widget.smokeMarkerSink,
      onChanged: () {
        if (mounted) {
          setState(() {});
        }
      },
      showResult: ({required String title, required String content}) {
        if (!mounted) {
          return Future<void>.value();
        }
        return context.showNoticeDialog(title: title, content: content);
      },
    );
    _initializeRawDumpController();
  }

  @override
  void dispose() {
    _sessionGeneration += 1;
    _mediaOperationBarrier.beginClosing();
    _stopMetricsPolling();
    _streamMessageOverlay.dispose();
    _commandButtonFocusNode.dispose();
    _metricsOverlay = null;
    _lastAvStatsOverlay = null;
    _commandConnected = false;
    _localAudioController.resetAfterSessionRelease(notify: false);
    final Future<void> rawDumpFinalized = _rawDumpController.finalizeForLeave();
    final Future<void> mediaFinalized = _mediaOperationBarrier.drain();
    _rawDumpController.dispose();
    _logUploadController.reset(notify: false);
    _commandController.reset(notify: false);
    _clearSessionCallbacks();
    final DemoAutomationMarkerSink? markerSink = widget.smokeMarkerSink;
    unawaited(
      Future.wait(<Future<void>>[rawDumpFinalized, mediaFinalized]).then((_) => _session.disposeAsync()).then((
        int code,
      ) {
        if (code == 0) {
          markerSink?.passed(
            'smoke_dispose_completed',
            payload: <String, Object?>{'dispose_result_observed': true, 'code': code},
          );
          return;
        }
        TiRtcLogging.e('flutter_example', 'downlink_dispose_failed code=$code');
      }),
    );
    super.dispose();
  }

  @override
  void onRouteActive(String reason) {
    if (_shouldKeepPlaying) {
      unawaited(_startDownlink(reason: reason));
    }
  }

  @override
  void onRouteInactive(String reason) {
    unawaited(
      _stopDownlink(
        reason: reason,
        clearIntent: false,
        nextStatusSummary: 'Downlink paused while the page is inactive.',
      ),
    );
  }

  Future<void> _startDownlink({required String reason}) async {
    if (_downlinkState == _DownlinkViewState.connecting || _downlinkState == _DownlinkViewState.playing) {
      return;
    }

    _mediaOperationBarrier.reopen();
    _shouldKeepPlaying = true;
    final int generation = ++_sessionGeneration;

    setState(() {
      _downlinkState = _DownlinkViewState.connecting;
      _stageStatusLabel = '连接中';
    });

    TiRtcLogging.i(
      'flutter_example',
      'downlink_start_requested reason=$reason '
          'remoteId=${widget.configuration.remoteId}',
    );

    final int? audioStreamId = widget.configuration.audioStreamId;
    final int audioSessionCode = audioStreamId == null ? 0 : await _audioSession.retainIfNeeded();
    if (!_acceptGeneration(generation)) {
      _audioSession.releaseIfNeeded(reason: 'stale_audio_session_retain');
      return;
    }
    if (audioSessionCode != 0) {
      _handleFailure(
        generation: generation,
        label: '播放准备失败 · ${TiRtc.formatError(audioSessionCode)}',
        summary: 'Downlink audio session setup failed with ${TiRtc.formatError(audioSessionCode)}.',
      );
      return;
    }

    _bindSessionCallbacks(generation: generation);

    final TiRtcOutputBufferStrategy outputBufferStrategy = _outputBufferStrategy(widget.configuration.settings);
    if (audioStreamId != null) {
      final int audioOptionsCode = _session.setAudioOptions(bufferStrategy: outputBufferStrategy);
      if (audioOptionsCode != 0) {
        _handleAudioOutputFailure(
          generation: generation,
          code: audioOptionsCode,
          summary: 'Audio output buffer options failed.',
        );
      } else {
        final int audioAttachCode = _session.attachAudio(streamId: audioStreamId);
        if (audioAttachCode != 0) {
          _handleAudioOutputFailure(generation: generation, code: audioAttachCode, summary: 'Audio attach failed.');
        } else {
          _audioOutputAvailable = true;
        }
      }
    }

    final int requestedDecoderPreference = widget.configuration.settings.videoDecoderPreference;
    for (final int videoStreamId in widget.configuration.videoStreamIds) {
      final int videoAttachCode = _session.attachVideo(
        streamId: videoStreamId,
        decoderPreference: requestedDecoderPreference,
        bufferStrategy: outputBufferStrategy,
        onStateChanged: (int streamId, TiRtcVideoOutputState state) {
          _handleVideoState(generation: generation, streamId: streamId, state: state);
        },
        onError: (int streamId, int code) {
          _handleVideoError(generation: generation, streamId: streamId, code: code);
        },
      );
      if (videoAttachCode != 0) {
        _handleVideoError(generation: generation, streamId: videoStreamId, code: videoAttachCode);
        _smokeFail(
          failureStage: 'video_output_attach',
          message: 'video output attach failed for stream $videoStreamId',
          errorCode: videoAttachCode,
        );
      }
    }

    if (!_acceptGeneration(generation)) {
      _clearSessionCallbacks();
      await _releaseSession(reason: 'stale_start');
      return;
    }

    final int connectCode = _session.connect(
      remoteId: widget.configuration.remoteId,
      token: widget.configuration.token,
    );
    if (connectCode != 0) {
      _clearSessionCallbacks();
      _handleFailure(
        generation: generation,
        label: _connectionErrorLabel(connectCode),
        summary: 'Connection setup failed with ${TiRtc.formatError(connectCode)}.',
      );
      return;
    }

    if (mounted) {
      setState(() {
        _stageStatusLabel = '连接中';
      });
    }
  }

  TiRtcOutputBufferStrategy _outputBufferStrategy(DemoExampleSettings settings) {
    return settings.outputBufferPolicy == DemoExampleSettings.outputBufferPolicyNoBuffer
        ? TiRtcOutputBufferStrategy.noBuffer
        : TiRtcOutputBufferStrategy.automatic;
  }

  void _bindSessionCallbacks({required int generation}) {
    _session.bindCallbacks(
      onConnectionStateChanged: (TiRtcConnState state, int errorCode) {
        _handleConnectionState(generation: generation, state: state, errorCode: errorCode);
      },
      onAudioStateChanged: (TiRtcAudioOutputState state) {
        _handleAudioState(generation: generation, state: state);
      },
      onAudioError: (int code) {
        _handleAudioOutputFailure(generation: generation, code: code, summary: 'Audio output failed.');
      },
      onVideoStateChanged: (_) {},
      onVideoStateChangedForStream: (int streamId, TiRtcVideoOutputState state) {
        _handleVideoState(generation: generation, streamId: streamId, state: state);
      },
      onVideoError: (_) {},
      onVideoErrorForStream: (int streamId, int code) {
        _handleVideoError(generation: generation, streamId: streamId, code: code);
      },
      onCommand: (int commandId, Uint8List data) {
        _handleCommand(generation: generation, commandId: commandId, payload: data);
      },
      onStreamMessage: (int streamId, int timestampMs, Uint8List data) {
        _handleStreamMessage(generation: generation, streamId: streamId, timestampMs: timestampMs, payload: data);
      },
      onAudioInputStateChanged: (TiRtcInputState state) {
        _handleLocalAudioInputState(generation: generation, state: state);
      },
      onAudioInputError: (int code, String? message) {
        _handleLocalAudioInputError(generation: generation, code: code, message: message);
      },
    );
  }

  void _clearSessionCallbacks() {
    _session.clearCallbacks();
  }

  Future<void> _stopDownlink({
    required String reason,
    required bool clearIntent,
    required String nextStatusSummary,
  }) async {
    _mediaOperationBarrier.beginClosing();
    _sessionGeneration += 1;
    if (!_smokeRenderWindowMarked) {
      _smokeRenderWindowStarted = false;
    }
    _stopMetricsPolling();
    _streamMessageOverlay.clear();
    _clearMetricsOverlay();
    _clearCommandState();
    _clearSessionCallbacks();
    await _rawDumpController.finalizeForLeave();
    await _releaseSession(reason: reason);
    _shouldKeepPlaying = !clearIntent;

    if (!mounted) {
      return;
    }
    setState(() {
      _downlinkState = _DownlinkViewState.idle;
      _stageStatusLabel = clearIntent ? '已停止' : '加载中';
      _audioOutputAvailable = false;
    });
  }

  Future<void> _releaseSession({required String reason}) async {
    await _mediaOperationBarrier.drain();
    await _session.release(reason: reason);
    _audioSession.releaseIfNeeded(reason: reason);
    _localAudioController.resetAfterSessionRelease(notify: false);
  }

  void _clearMetricsOverlay() {
    if (!mounted) {
      _metricsOverlay = null;
      _lastAvStatsOverlay = null;
      return;
    }
    setState(() {
      _metricsOverlay = null;
      _lastAvStatsOverlay = null;
      _streamMessageOverlay.clear();
    });
  }

  void _clearCommandState() {
    if (!mounted) {
      _commandConnected = false;
      _commandController.reset(notify: false);
      return;
    }
    setState(() {
      _commandConnected = false;
    });
    _commandController.reset(notify: false);
    _commandController.refreshSheet();
  }

  void _handleStreamMessage({
    required int generation,
    required int streamId,
    required int timestampMs,
    required Uint8List payload,
  }) {
    if (!_acceptGeneration(generation) || !widget.configuration.videoStreamIds.contains(streamId)) {
      return;
    }
    final DemoStreamMessageReceiveEvent? event = _streamMessageOverlay.handleIncoming(
      expectedStreamId: streamId,
      streamId: streamId,
      timestampMs: timestampMs,
      payload: payload,
      isActive: () => _acceptGeneration(generation),
      onChanged: () {
        if (mounted) {
          setState(() {});
        }
      },
    );
    if (event == null) {
      return;
    }
    TiRtcLogging.i(
      'flutter_example',
      'stream_message_received stream_id=${event.streamId} timestamp_ms=${event.timestampMs} '
          'payload_epoch_seconds=${event.epochSeconds} count=${event.count}',
    );
    widget.smokeMarkerSink?.passed(
      'stream_message_received',
      payload: <String, Object?>{
        'stream_id': event.streamId,
        'payload_epoch_seconds': event.epochSeconds,
        'payload_bytes': event.payloadBytes,
        'payload_hash': event.payloadHash,
        'received_count': event.count,
      },
    );
  }

  void _startMetricsPolling({required int generation}) {
    _stopMetricsPolling();
    _pollDownlinkMetrics(generation: generation);
    _metricsPollTimer = Timer.periodic(_metricsPollInterval, (_) {
      _pollDownlinkMetrics(generation: generation);
    });
  }

  void _stopMetricsPolling() {
    _metricsPollTimer?.cancel();
    _metricsPollTimer = null;
  }

  void _pollDownlinkMetrics({required int generation}) {
    if (!_acceptGeneration(generation) || _downlinkState != _DownlinkViewState.playing) {
      return;
    }

    final DownlinkMetricsOverlayModel? nextMetrics = _session.readMetricsOverlay(
      requestedDecoderPreference: widget.configuration.settings.videoDecoderPreference,
      videoStreamId: _selectedVideoStreamId,
    );
    if (nextMetrics == null) {
      return;
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _metricsOverlay = nextMetrics;
    });
    if (nextMetrics.avStatsReady) {
      _lastAvStatsOverlay = nextMetrics;
    }
    if (nextMetrics.debugStatsReady) {
      _smokePassOnce(
        marker: 'smoke_debug_stats_ready',
        marked: _smokeDebugStatsMarked,
        setMarked: () {
          _smokeDebugStatsMarked = true;
        },
        payload: nextMetrics.smokeDebugMarkerPayload(sessionGeneration: generation),
      );
      _startSmokeRenderWindow(generation: generation);
    }
  }

  bool _acceptGeneration(int generation) {
    return mounted && generation == _sessionGeneration;
  }

  String _connectionErrorLabel(int code) {
    return '连接失败 · ${TiRtc.formatError(code)}';
  }

  void _handleConnectionState({required int generation, required TiRtcConnState state, required int errorCode}) {
    if (!_acceptGeneration(generation)) {
      return;
    }

    TiRtcLogging.i('flutter_example', 'connection_state generation=$generation state=$state errorCode=$errorCode');

    if (state == TiRtcConnState.connecting) {
      if (_downlinkState == _DownlinkViewState.playing) {
        return;
      }
      setState(() {
        _downlinkState = _DownlinkViewState.connecting;
        _stageStatusLabel = '连接中';
      });
      return;
    }

    if (state == TiRtcConnState.connected) {
      final int? audioStreamId = widget.configuration.audioStreamId;
      if (audioStreamId != null && _audioOutputAvailable) {
        final int audioSubscribeCode = _session.subscribeAudio(streamId: audioStreamId);
        if (audioSubscribeCode != 0) {
          _handleAudioOutputFailure(
            generation: generation,
            code: audioSubscribeCode,
            summary: 'Audio subscribe failed for stream $audioStreamId.',
          );
        }
      }

      for (final int videoStreamId in widget.configuration.videoStreamIds) {
        if (_videoStates[videoStreamId] == TiRtcVideoOutputState.failed) continue;
        final int videoSubscribeCode = _session.subscribeVideo(streamId: videoStreamId);
        if (videoSubscribeCode != 0) {
          _handleVideoError(generation: generation, streamId: videoStreamId, code: videoSubscribeCode);
          _smokeFail(
            failureStage: 'video_output_subscribe',
            message: 'video subscribe failed for stream $videoStreamId',
            errorCode: videoSubscribeCode,
          );
        }
      }

      TiRtcLogging.i(
        'flutter_example',
        'remote_media_subscribed audio_stream_id=$audioStreamId video_stream_ids=${widget.configuration.videoStreamIds}',
      );
      _smokePassOnce(
        marker: 'smoke_connected',
        marked: _smokeConnectedMarked,
        setMarked: () {
          _smokeConnectedMarked = true;
        },
        payload: <String, Object?>{'remote_id': widget.configuration.remoteId},
      );
      if (_downlinkState == _DownlinkViewState.playing) {
        _setCommandConnected(true);
        return;
      }
      setState(() {
        _commandConnected = true;
        final bool waitingForVideo = widget.configuration.videoStreamIds.any(
          (int streamId) => _videoStates[streamId] != TiRtcVideoOutputState.failed,
        );
        _downlinkState = waitingForVideo ? _DownlinkViewState.connecting : _DownlinkViewState.playing;
        _stageStatusLabel =
            _audioOutputAvailable
                ? '音频播放中'
                : widget.configuration.audioStreamId == null && widget.configuration.videoStreamIds.isEmpty
                ? '未配置音视频'
                : waitingForVideo
                ? '等待视频'
                : '音视频输出不可用';
      });
      _commandController.refreshSheet();
      return;
    }

    if (state == TiRtcConnState.disconnected) {
      _setCommandConnected(false);
      if (errorCode == 0) {
        _handleFailure(generation: generation, label: '连接断开 #0', summary: 'Remote session disconnected.');
      } else {
        _handleFailure(
          generation: generation,
          label: _connectionErrorLabel(errorCode),
          summary: 'Connection disconnected with ${TiRtc.formatError(errorCode)}.',
        );
      }
    }
  }

  void _handleAudioState({required int generation, required TiRtcAudioOutputState state}) {
    if (!_acceptGeneration(generation)) {
      return;
    }

    if (state == TiRtcAudioOutputState.failed) {
      _handleAudioOutputFailure(generation: generation, code: 0, summary: 'Audio output entered a failed state.');
      return;
    }

    if (state == TiRtcAudioOutputState.playing) {
      if (!_audioOutputAvailable) setState(() => _audioOutputAvailable = true);
      _smokePassOnce(
        marker: 'smoke_audio_playing',
        marked: _smokeAudioPlayingMarked,
        setMarked: () {
          _smokeAudioPlayingMarked = true;
        },
        payload: <String, Object?>{'audio_error_count': _smokeAudioErrorCount},
      );
    }
  }

  void _handleLocalAudioInputState({required int generation, required TiRtcInputState state}) {
    if (!_acceptGeneration(generation)) {
      return;
    }
    _localAudioController.handleInputState(state);
  }

  void _handleLocalAudioInputError({required int generation, required int code, String? message}) {
    if (!_acceptGeneration(generation)) {
      return;
    }
    _localAudioController.handleInputError(code: code, message: message);
  }

  void _handleVideoState({required int generation, required int streamId, required TiRtcVideoOutputState state}) {
    if (!_acceptGeneration(generation)) {
      return;
    }

    if (state == TiRtcVideoOutputState.failed) {
      _smokeVideoErrorCount += 1;
      setState(() {
        _videoStates[streamId] = state;
        _videoStatusLabels[streamId] = '播放失败';
        _settleAfterAllVideoOutputsFail();
      });
      TiRtcLogging.w('flutter_example', 'video_output_failed stream_id=$streamId');
      return;
    }

    setState(() {
      _videoStates[streamId] = state;
      _videoStatusLabels[streamId] = state == TiRtcVideoOutputState.rendering ? '播放中' : '等待视频';
    });
    if (state == TiRtcVideoOutputState.rendering) {
      setState(() {
        if (_downlinkState == _DownlinkViewState.connecting) {
          _downlinkState = _DownlinkViewState.playing;
        }
      });
      _markSmokeVideoRendering(generation: generation, streamId: streamId);
      _startMetricsPolling(generation: generation);
    }
  }

  void _handleVideoError({required int generation, required int streamId, required int code}) {
    if (!_acceptGeneration(generation)) return;
    _smokeVideoErrorCount += 1;
    setState(() {
      _videoStates[streamId] = TiRtcVideoOutputState.failed;
      _videoStatusLabels[streamId] = '播放失败 · ${TiRtc.formatError(code)}';
      _settleAfterAllVideoOutputsFail();
    });
    TiRtcLogging.w('flutter_example', 'video_output_error stream_id=$streamId code=$code');
  }

  void _handleAudioOutputFailure({required int generation, required int code, required String summary}) {
    if (!_acceptGeneration(generation)) return;
    _smokeAudioErrorCount += 1;
    _audioOutputAvailable = false;
    _smokeFail(failureStage: 'audio_output', message: summary, errorCode: code == 0 ? null : code);
    setState(() {
      if (widget.configuration.videoStreamIds.isEmpty) {
        _stageStatusLabel = code == 0 ? '音频播放失败' : '音频播放失败 · ${TiRtc.formatError(code)}';
      }
    });
    TiRtcLogging.w('flutter_example', 'audio_output_error code=$code summary=$summary');
  }

  void _settleAfterAllVideoOutputsFail() {
    if (!_commandConnected ||
        !widget.configuration.videoStreamIds.every((int id) => _videoStates[id] == TiRtcVideoOutputState.failed)) {
      return;
    }
    _downlinkState = _DownlinkViewState.playing;
    _stageStatusLabel = _audioOutputAvailable ? '音频播放中' : '音视频输出不可用';
  }

  void _handleFailure({required int generation, required String label, required String summary}) {
    if (!_acceptGeneration(generation)) {
      return;
    }

    _sessionGeneration += 1;
    _stopMetricsPolling();
    _clearSessionCallbacks();
    unawaited(_releaseSession(reason: 'failure'));
    setState(() {
      _downlinkState = _DownlinkViewState.failed;
      _stageStatusLabel = label;
      _metricsOverlay = null;
      _commandConnected = false;
      _audioOutputAvailable = false;
    });
    TiRtcLogging.w('flutter_example', 'downlink_failed summary=$summary');
    _commandController.refreshSheet();
    _smokeFail(failureStage: 'downlink', message: summary);
  }

  void _smokePassOnce({
    required String marker,
    required bool marked,
    required VoidCallback setMarked,
    required Map<String, Object?> payload,
  }) {
    if (marked) {
      return;
    }
    setMarked();
    widget.smokeMarkerSink?.passed(marker, payload: payload);
  }

  void _smokeFail({required String failureStage, required String message, int? errorCode}) {
    widget.smokeMarkerSink?.failure(failureStage: failureStage, message: message, errorCode: errorCode);
  }

  void _markSmokeVideoRendering({required int generation, required int streamId}) {
    if (widget.smokeMarkerSink == null ||
        _smokeRenderedVideoStreamIds.contains(streamId) ||
        !_smokePendingVideoStreamIds.add(streamId)) {
      return;
    }
    unawaited(() async {
      try {
        final DateTime deadline = DateTime.now().add(const Duration(seconds: 30));
        while (DateTime.now().isBefore(deadline)) {
          if (!_acceptGeneration(generation)) {
            return;
          }
          final TiRtcVideoOutputMetricsResult metrics = _session.videoMetrics(streamId);
          final int? firstOutputDurationMs = metrics.snapshot?.startup.timeToFirstOutputMs;
          if (metrics.code == 0 && firstOutputDurationMs != null && firstOutputDurationMs >= 0) {
            _smokeRenderedVideoStreamIds.add(streamId);
            if (!_smokeVideoRenderingMarked) {
              _smokeVideoRenderingMarked = true;
              widget.smokeMarkerSink?.passed(
                'smoke_video_rendering',
                payload: <String, Object?>{'stream_id': streamId, 'first_frame_duration_ms': firstOutputDurationMs},
              );
            }
            if (_smokeRenderedVideoStreamIds.containsAll(widget.configuration.videoStreamIds) &&
                widget.configuration.videoStreamIds.length > 1 &&
                !_smokeMultiVideoRenderingMarked) {
              _smokeMultiVideoRenderingMarked = true;
              widget.smokeMarkerSink?.passed(
                'smoke_multi_video_rendering',
                payload: <String, Object?>{'video_stream_ids': widget.configuration.videoStreamIds},
              );
            }
            return;
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        _smokeFail(failureStage: 'render_timeout', message: 'first frame metrics timeout');
      } finally {
        _smokePendingVideoStreamIds.remove(streamId);
      }
    }());
  }

  void _startSmokeRenderWindow({required int generation}) {
    if (_smokeRenderWindowStarted || widget.smokeMarkerSink == null) {
      return;
    }
    _smokeRenderWindowStarted = true;
    unawaited(() async {
      await Future<void>.delayed(Duration(seconds: widget.smokeRenderWindowSeconds));
      if (!_acceptGeneration(generation) || _smokeRenderWindowMarked) {
        return;
      }
      final DownlinkMetricsOverlayModel? metrics = _session.readMetricsOverlay(
        requestedDecoderPreference: widget.configuration.settings.videoDecoderPreference,
        videoStreamId: _selectedVideoStreamId,
      );
      if (_smokeAudioErrorCount != 0 || _smokeVideoErrorCount != 0 || metrics == null || !metrics.debugStatsReady) {
        _smokeFail(failureStage: 'render_window', message: 'render window ended without healthy output');
        return;
      }
      final DownlinkMetricsOverlayModel markerStats = _lastAvStatsOverlay ?? metrics;
      final Map<String, Object?> markerPayload = markerStats.smokeRenderWindowMarkerPayload(
        sessionGeneration: generation,
      );
      _smokeRenderWindowMarked = true;
      widget.smokeMarkerSink?.passed(
        'smoke_render_window_completed',
        payload: <String, Object?>{
          ...markerPayload,
          'audio_error_count': _smokeAudioErrorCount,
          'video_error_count': _smokeVideoErrorCount,
          'audio_state': _session.audioState.name,
          'video_states': <String, String>{
            for (final int id in widget.configuration.videoStreamIds)
              '$id': (_session.videoStateFor(id)?.name ?? 'missing'),
          },
        },
      );
    }());
  }

  void _handleCommand({required int generation, required int commandId, required Uint8List payload}) {
    if (!_acceptGeneration(generation)) {
      return;
    }
    _commandController.handleReceived(commandId: commandId, payload: payload);
  }

  void _setCommandConnected(bool connected) {
    if (_commandConnected == connected) {
      return;
    }
    if (!mounted) {
      _commandConnected = connected;
      return;
    }
    setState(() {
      _commandConnected = connected;
    });
    _commandController.refreshSheet();
  }

  Future<void> _showMetricsExplanationDialog() {
    return context.showNoticeDialog(
      title: '指标说明',
      content: downlinkMetricsExplanationContent,
      contentMaxWidth: 520,
      contentMaxHeightFactor: 0.68,
      contentFontSize: 15,
    );
  }

  Future<void> _showCommandPanel() async {
    await _commandController.showPanel(context, connected: () => _commandConnected);
    if (mounted) _commandButtonFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final bool connecting = _downlinkState == _DownlinkViewState.connecting;
    final bool playing = _downlinkState == _DownlinkViewState.playing;
    final bool appleProfile = ExampleTheme.isAppleProfile(context);
    return Scaffold(
      key: DemoWidgetKeys.playerPage,
      backgroundColor: ExampleTheme.background,
      appBar: AppBar(
        title: Text(
          widget.configuration.remoteId,
          style: const TextStyle(color: ExampleTheme.primary, fontSize: 14, fontWeight: FontWeight.w600),
        ),
        actions: <Widget>[
          PlayerCommandButton(
            key: DemoWidgetKeys.playerCommandButton,
            focusNode: _commandButtonFocusNode,
            onOpenCommands: _showCommandPanel,
          ),
          PlayerLogUploadButton(
            buttonKey: DemoWidgetKeys.playerLogUploadButton,
            uploadingLogs: _logUploadController.uploading,
            onUploadLogs: _uploadLogs,
          ),
        ],
      ),
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: DownlinkVideoStage(
              lanes: <DownlinkVideoLaneModel>[
                for (final int id in widget.configuration.videoStreamIds)
                  DownlinkVideoLaneModel(
                    streamId: id,
                    videoView: _session.buildVideoView(id),
                    statusLabel: _videoStatusLabels[id] ?? '等待视频',
                    showStatus: _videoStates[id] != TiRtcVideoOutputState.rendering,
                  ),
              ],
              selectedStreamId: _selectedVideoStreamId,
              maximizedStreamId: _maximizedVideoStreamId,
              stageStatusLabel: _stageStatusLabel,
              indicatorMode: _centerIndicatorMode,
              onSelect: _selectVideoStream,
            ),
          ),
          const Positioned.fill(child: DownlinkOverlayGradient()),
          Positioned(
            left: 12,
            top: 0,
            bottom: 0,
            child: SafeArea(
              child: Center(
                child: DemoRawDumpButton(key: DemoWidgetKeys.rawDumpButton, controller: _rawDumpController),
              ),
            ),
          ),
          if (_metricsOverlay != null)
            Positioned(
              top: 18,
              left: 18,
              right: 18,
              child: SafeArea(
                bottom: false,
                child: DownlinkMetricsOverlay(
                  metrics: _metricsOverlay!,
                  onShowExplanation: _showMetricsExplanationDialog,
                ),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, appleProfile ? 0 : 16, 20, appleProfile ? 0 : 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Spacer(),
                  if (_streamMessageOverlay.text != null)
                    Align(
                      alignment: Alignment.bottomRight,
                      child: StreamMessageBubble(text: _streamMessageOverlay.text!),
                    ),
                  if (_streamMessageOverlay.text != null) const SizedBox(height: 12),
                  PlayerControlPanel(
                    connecting: connecting,
                    playing: playing,
                    audioOutputEnabled: _commandConnected && _audioOutputAvailable,
                    audioMuted: _audioMuted,
                    localAudioControl: LocalAudioControlButton(
                      key: DemoWidgetKeys.playerLocalAudioButton,
                      enabled: _commandConnected,
                      busy: _localAudioController.busy,
                      running: _localAudioController.running,
                      onPressed: _localAudioController.toggle,
                    ),
                    selectedVideoPosition:
                        _selectedVideoStreamId == null
                            ? null
                            : widget.configuration.videoStreamIds.indexOf(_selectedVideoStreamId!) + 1,
                    selectedVideoStreamId: _selectedVideoStreamId,
                    mediaBusy: _mediaFileBusy,
                    recording: _session.isRecording,
                    galleryRetryAvailable: _session.hasPendingGalleryMedia,
                    canExecuteMedia:
                        () =>
                            _downlinkState == _DownlinkViewState.playing &&
                            _selectedVideoStreamId != null &&
                            !_mediaFileBusy &&
                            _mediaOperationBarrier.accepting,
                    onToggleDownlink: _toggleDownlink,
                    onToggleAudioOutput: _toggleAudioOutputVolume,
                    onToggleRecording: _toggleRecording,
                    onSnapshot: _takeSnapshot,
                    onGallery: _moveLatestMediaToGallery,
                    onMediaUnavailable: () => _showPlayerSnack('播放状态已变化，请恢复播放后重试。'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _selectVideoStream(int streamId) {
    setState(() {
      if (_selectedVideoStreamId == streamId) {
        _maximizedVideoStreamId = _maximizedVideoStreamId == streamId ? null : streamId;
      } else {
        _selectedVideoStreamId = streamId;
        _maximizedVideoStreamId = null;
      }
    });
  }

  void _toggleDownlink() {
    if (_downlinkState == _DownlinkViewState.playing) {
      unawaited(_stopDownlink(reason: 'manual_stop', clearIntent: true, nextStatusSummary: 'Downlink stopped.'));
      return;
    }

    unawaited(_startDownlink(reason: 'manual_start'));
  }

  void _toggleAudioOutputVolume() {
    final bool nextMuted = !_audioMuted;
    final int volumePercent = nextMuted ? 0 : 100;
    final int code = _session.setAudioOutputVolume(volumePercent);
    if (code != 0) {
      _showPlayerSnack('音量设置失败 · ${TiRtc.formatError(code)}');
      _smokeFail(failureStage: 'audio_output_volume', message: 'audio output volume update failed', errorCode: code);
      return;
    }
    setState(() {
      _audioMuted = nextMuted;
    });
    widget.smokeMarkerSink?.passed(
      nextMuted ? 'smoke_audio_output_muted' : 'smoke_audio_output_restored',
      payload: <String, Object?>{'volume_percent': volumePercent, 'audio_state': _session.audioState.name},
    );
  }

  void _showPlayerSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  DownlinkCenterIndicatorMode get _centerIndicatorMode {
    if (_downlinkState == _DownlinkViewState.connecting) {
      return DownlinkCenterIndicatorMode.loading;
    }

    if (_downlinkState == _DownlinkViewState.failed) {
      return DownlinkCenterIndicatorMode.error;
    }

    if (_downlinkState == _DownlinkViewState.idle && !_shouldKeepPlaying) {
      return DownlinkCenterIndicatorMode.error;
    }

    return DownlinkCenterIndicatorMode.loading;
  }
}
