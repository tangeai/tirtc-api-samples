import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:tirtc_flutter/tirtc_flutter.dart';

import '../app_theme.dart';
import '../demo_configuration.dart';
import '../demo_downlink_session.dart';
import '../demo_downlink_support.dart';
import '../demo_route_lifecycle.dart';
import '../demo_stream_message.dart';
import '../demo_test_hooks.dart';
import '../demo_video_attach_flow.dart';
import '../demo_widget_keys.dart';
import '../widgets/notice_dialog.dart';
import '../widgets/downlink_center_loading.dart';
import '../widgets/downlink_metrics_overlay.dart';
import '../widgets/downlink_metrics_overlay_markers.dart';
import '../widgets/downlink_metrics_overlay_model.dart';
import '../widgets/player_page_widgets.dart';
import '../widgets/stream_message_bubble.dart';
import 'player_command_controller.dart';
import 'player_local_audio_controller.dart';
import 'player_log_upload_controller.dart';

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

  _DownlinkViewState _downlinkState = _DownlinkViewState.idle;
  String _stageStatusLabel = '加载中';
  bool _shouldKeepPlaying = true;
  int _sessionGeneration = 0;
  bool _commandConnected = false;
  bool _audioMuted = false;
  bool _smokeConnectedMarked = false;
  bool _smokeAudioPlayingMarked = false;
  bool _smokeVideoRenderingMarked = false;
  bool _hasRenderedVideoOnce = false;
  bool _smokeDebugStatsMarked = false;
  bool _smokeRenderWindowStarted = false;
  bool _smokeRenderWindowMarked = false;
  int _smokeAudioErrorCount = 0;
  int _smokeVideoErrorCount = 0;
  Timer? _metricsPollTimer;
  DownlinkMetricsOverlayModel? _metricsOverlay;
  DownlinkMetricsOverlayModel? _lastAvStatsOverlay;
  final DemoStreamMessageOverlayController _streamMessageOverlay = DemoStreamMessageOverlayController();

  @override
  void initState() {
    super.initState();
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
      showResult: ({
        required String title,
        required String content,
      }) {
        if (!mounted) {
          return Future<void>.value();
        }
        return context.showNoticeDialog(
          title: title,
          content: content,
        );
      },
    );
  }

  @override
  void dispose() {
    _sessionGeneration += 1;
    _stopMetricsPolling();
    _streamMessageOverlay.dispose();
    _metricsOverlay = null;
    _lastAvStatsOverlay = null;
    _commandConnected = false;
    _localAudioController.resetAfterSessionRelease(notify: false);
    _logUploadController.reset(notify: false);
    _commandController.reset(notify: false);
    _clearSessionCallbacks();
    _session.dispose();
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

    _shouldKeepPlaying = true;
    final int generation = ++_sessionGeneration;

    setState(() {
      _downlinkState = _DownlinkViewState.connecting;
      _stageStatusLabel = '连接中';
      _hasRenderedVideoOnce = false;
    });

    TiRtcLogging.i(
      'flutter_example',
      'downlink_start_requested reason=$reason '
          'remoteId=${widget.configuration.remoteId}',
    );

    final int audioSessionCode = await _audioSession.retainIfNeeded();
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
    final int audioOptionsCode = _session.setAudioOptions(bufferStrategy: outputBufferStrategy);
    if (audioOptionsCode != 0) {
      _clearSessionCallbacks();
      _handleFailure(
        generation: generation,
        label: _downlinkErrorLabel(audioOptionsCode),
        summary: 'Audio output buffer options failed with ${TiRtc.formatError(audioOptionsCode)}.',
      );
      return;
    }

    final int audioAttachCode = _session.attachAudio(streamId: widget.configuration.audioStreamId);
    if (audioAttachCode != 0) {
      _clearSessionCallbacks();
      _handleFailure(
        generation: generation,
        label: _downlinkErrorLabel(audioAttachCode),
        summary: 'Audio attach failed with ${TiRtc.formatError(audioAttachCode)}.',
      );
      return;
    }

    final int videoStreamId = widget.configuration.videoStreamId;
    final int requestedDecoderPreference = widget.configuration.settings.videoDecoderPreference;
    final DemoVideoAttachResult videoAttachResult = applyVideoDecoderPreferenceThenAttach(
      sessionGeneration: generation,
      videoStreamId: videoStreamId,
      requestedPreference: requestedDecoderPreference,
      applyOptions: () => _session.setVideoOptions(
        decoderPreference: requestedDecoderPreference,
        bufferStrategy: outputBufferStrategy,
      ),
      attachVideo: () => _session.attachVideo(streamId: videoStreamId),
      log: (String message) => TiRtcLogging.i('flutter_example', message),
    );
    if (!videoAttachResult.optionsApplied) {
      _clearSessionCallbacks();
      _handleFailure(
        generation: generation,
        label: _downlinkErrorLabel(videoAttachResult.optionsCode),
        summary: 'Video decoder preference apply failed with ${TiRtc.formatError(videoAttachResult.optionsCode)}.',
      );
      return;
    }

    final int videoAttachCode = videoAttachResult.attachCode ?? 0;
    if (videoAttachCode != 0) {
      _clearSessionCallbacks();
      _handleFailure(
        generation: generation,
        label: _downlinkErrorLabel(videoAttachCode),
        summary: 'Video attach failed with ${TiRtc.formatError(videoAttachCode)}.',
      );
      return;
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
        _handleConnectionState(
          generation: generation,
          state: state,
          errorCode: errorCode,
        );
      },
      onAudioStateChanged: (TiRtcAudioOutputState state) {
        _handleAudioState(generation: generation, state: state);
      },
      onAudioError: (int code) {
        _smokeAudioErrorCount += 1;
        _smokeFail(failureStage: 'audio_output', message: 'audio output failed', errorCode: code);
        _handleFailure(
          generation: generation,
          label: _downlinkErrorLabel(code),
          summary: 'Audio output failed with ${TiRtc.formatError(code)}.',
        );
      },
      onVideoStateChanged: (TiRtcVideoOutputState state) {
        _handleVideoState(generation: generation, state: state);
      },
      onVideoError: (int code) {
        _smokeVideoErrorCount += 1;
        _smokeFail(failureStage: 'video_output', message: 'video output failed', errorCode: code);
        _handleFailure(
          generation: generation,
          label: _downlinkErrorLabel(code),
          summary: 'Video output failed with ${TiRtc.formatError(code)}.',
        );
      },
      onCommand: (int commandId, Uint8List data) {
        _handleCommand(
          generation: generation,
          commandId: commandId,
          payload: data,
        );
      },
      onStreamMessage: (int streamId, int timestampMs, Uint8List data) {
        _handleStreamMessage(
          generation: generation,
          streamId: streamId,
          timestampMs: timestampMs,
          payload: data,
        );
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
    _sessionGeneration += 1;
    if (!_smokeRenderWindowMarked) {
      _smokeRenderWindowStarted = false;
    }
    _stopMetricsPolling();
    _streamMessageOverlay.clear();
    _clearMetricsOverlay();
    _clearCommandState();
    _clearSessionCallbacks();
    await _releaseSession(reason: reason);
    _shouldKeepPlaying = !clearIntent;

    if (!mounted) {
      return;
    }
    setState(() {
      _downlinkState = _DownlinkViewState.idle;
      _stageStatusLabel = clearIntent ? '已停止' : '加载中';
      _hasRenderedVideoOnce = false;
    });
  }

  Future<void> _releaseSession({required String reason}) async {
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
    if (!_acceptGeneration(generation) || streamId != widget.configuration.videoStreamId) {
      return;
    }
    final DemoStreamMessageReceiveEvent? event = _streamMessageOverlay.handleIncoming(
      expectedStreamId: widget.configuration.videoStreamId,
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
    widget.smokeMarkerSink?.passed('stream_message_received', payload: <String, Object?>{
      'stream_id': event.streamId,
      'payload_epoch_seconds': event.epochSeconds,
      'payload_bytes': event.payloadBytes,
      'payload_hash': event.payloadHash,
      'received_count': event.count,
    });
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

  String _downlinkErrorLabel(int code) {
    return '播放失败 · ${TiRtc.formatError(code)}';
  }

  String _connectionErrorLabel(int code) {
    return '连接失败 · ${TiRtc.formatError(code)}';
  }

  void _handleConnectionState({
    required int generation,
    required TiRtcConnState state,
    required int errorCode,
  }) {
    if (!_acceptGeneration(generation)) {
      return;
    }

    TiRtcLogging.i(
      'flutter_example',
      'connection_state generation=$generation state=$state errorCode=$errorCode',
    );

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
      final int audioStreamId = widget.configuration.audioStreamId;
      final int audioSubscribeCode = _session.subscribeAudio(streamId: audioStreamId);
      if (audioSubscribeCode != 0) {
        _handleFailure(
          generation: generation,
          label: _connectionErrorLabel(audioSubscribeCode),
          summary: 'Audio subscribe failed for stream $audioStreamId with ${TiRtc.formatError(audioSubscribeCode)}.',
        );
        return;
      }

      final int videoStreamId = widget.configuration.videoStreamId;
      final int videoSubscribeCode = _session.subscribeVideo(streamId: videoStreamId);
      if (videoSubscribeCode != 0) {
        _handleFailure(
          generation: generation,
          label: _connectionErrorLabel(videoSubscribeCode),
          summary: 'Video subscribe failed for stream $videoStreamId with ${TiRtc.formatError(videoSubscribeCode)}.',
        );
        return;
      }

      TiRtcLogging.i(
        'flutter_example',
        'remote_media_subscribed audio_stream_id=$audioStreamId video_stream_id=$videoStreamId',
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
        _downlinkState = _DownlinkViewState.connecting;
        _stageStatusLabel = '加载中';
      });
      _commandController.refreshSheet();
      return;
    }

    if (state == TiRtcConnState.disconnected) {
      _setCommandConnected(false);
      if (errorCode == 0) {
        _handleFailure(
          generation: generation,
          label: '连接断开 #0',
          summary: 'Remote session disconnected.',
        );
      } else {
        _handleFailure(
          generation: generation,
          label: _connectionErrorLabel(errorCode),
          summary: 'Connection disconnected with ${TiRtc.formatError(errorCode)}.',
        );
      }
    }
  }

  void _handleAudioState({
    required int generation,
    required TiRtcAudioOutputState state,
  }) {
    if (!_acceptGeneration(generation)) {
      return;
    }

    if (state == TiRtcAudioOutputState.failed) {
      _smokeAudioErrorCount += 1;
      _smokeFail(failureStage: 'audio_output', message: 'audio output entered failed state');
      _handleFailure(
        generation: generation,
        label: _downlinkErrorLabel(0),
        summary: 'Audio output entered a failed state.',
      );
      return;
    }

    if (state == TiRtcAudioOutputState.playing) {
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

  void _handleLocalAudioInputState({
    required int generation,
    required TiRtcInputState state,
  }) {
    if (!_acceptGeneration(generation)) {
      return;
    }
    _localAudioController.handleInputState(state);
  }

  void _handleLocalAudioInputError({
    required int generation,
    required int code,
    String? message,
  }) {
    if (!_acceptGeneration(generation)) {
      return;
    }
    _localAudioController.handleInputError(code: code, message: message);
  }

  void _handleVideoState({
    required int generation,
    required TiRtcVideoOutputState state,
  }) {
    if (!_acceptGeneration(generation)) {
      return;
    }

    if (state == TiRtcVideoOutputState.failed) {
      _smokeVideoErrorCount += 1;
      _smokeFail(failureStage: 'video_output', message: 'video output entered failed state');
      _handleFailure(
        generation: generation,
        label: _downlinkErrorLabel(0),
        summary: 'Video output entered a failed state.',
      );
      return;
    }

    if (state == TiRtcVideoOutputState.rendering) {
      setState(() {
        if (_downlinkState == _DownlinkViewState.connecting) {
          _downlinkState = _DownlinkViewState.playing;
        }
        _hasRenderedVideoOnce = true;
      });
      _markSmokeVideoRendering(generation: generation);
      _startMetricsPolling(generation: generation);
    }
  }

  void _handleFailure({
    required int generation,
    required String label,
    required String summary,
  }) {
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

  void _smokeFail({
    required String failureStage,
    required String message,
    int? errorCode,
  }) {
    widget.smokeMarkerSink?.failure(
      failureStage: failureStage,
      message: message,
      errorCode: errorCode,
    );
  }

  void _markSmokeVideoRendering({required int generation}) {
    if (_smokeVideoRenderingMarked || widget.smokeMarkerSink == null) {
      return;
    }
    _smokeVideoRenderingMarked = true;
    unawaited(() async {
      final DateTime deadline = DateTime.now().add(const Duration(seconds: 30));
      while (DateTime.now().isBefore(deadline)) {
        if (!_acceptGeneration(generation)) {
          return;
        }
        final TiRtcVideoOutputMetricsResult metrics = _session.videoMetrics();
        final int? firstOutputDurationMs = metrics.snapshot?.startup.timeToFirstOutputMs;
        if (metrics.code == 0 && firstOutputDurationMs != null && firstOutputDurationMs >= 0) {
          widget.smokeMarkerSink?.passed('smoke_video_rendering', payload: <String, Object?>{
            'first_frame_duration_ms': firstOutputDurationMs,
          });
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      _smokeFail(failureStage: 'render_timeout', message: 'first frame metrics timeout');
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
      );
      if (_smokeAudioErrorCount != 0 ||
          _smokeVideoErrorCount != 0 ||
          _session.videoState != TiRtcVideoOutputState.rendering ||
          metrics == null ||
          !metrics.debugStatsReady) {
        _smokeFail(failureStage: 'render_window', message: 'render window ended without healthy output');
        return;
      }
      final DownlinkMetricsOverlayModel markerStats = _lastAvStatsOverlay ?? metrics;
      final Map<String, Object?> markerPayload = markerStats.smokeRenderWindowMarkerPayload(
        sessionGeneration: generation,
      );
      _smokeRenderWindowMarked = true;
      widget.smokeMarkerSink?.passed('smoke_render_window_completed', payload: <String, Object?>{
        ...markerPayload,
        'audio_error_count': _smokeAudioErrorCount,
        'video_error_count': _smokeVideoErrorCount,
        'audio_state': _session.audioState.name,
        'video_state': _session.videoState.name,
      });
    }());
  }

  void _handleCommand({
    required int generation,
    required int commandId,
    required Uint8List payload,
  }) {
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

  Future<void> _showCommandPanel() {
    return _commandController.showPanel(
      context,
      connected: () => _commandConnected,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool connecting = _downlinkState == _DownlinkViewState.connecting;
    final bool playing = _downlinkState == _DownlinkViewState.playing;
    return Scaffold(
      key: DemoWidgetKeys.playerPage,
      backgroundColor: ExampleTheme.background,
      appBar: AppBar(
        title: Text(
          widget.configuration.remoteId,
          style: const TextStyle(
            color: ExampleTheme.primary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: <Widget>[
          PlayerCommandButton(
            key: DemoWidgetKeys.playerCommandButton,
            onOpenCommands: _showCommandPanel,
          ),
          PlayerLogUploadButton(
            key: DemoWidgetKeys.playerLogUploadButton,
            uploadingLogs: _logUploadController.uploading,
            onUploadLogs: () => _logUploadController.upload(remoteId: widget.configuration.remoteId),
          ),
        ],
      ),
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: DownlinkVideoStage(
              videoView: _session.buildVideoView(),
              showStageOverlay: _showStageOverlay,
              stageStatusLabel: _stageStatusLabel,
              indicatorMode: _centerIndicatorMode,
            ),
          ),
          const Positioned.fill(child: DownlinkOverlayGradient()),
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
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Spacer(),
                  if (_streamMessageOverlay.text != null)
                    Align(
                      alignment: Alignment.bottomRight,
                      child: StreamMessageBubble(
                        text: _streamMessageOverlay.text!,
                      ),
                    ),
                  if (_streamMessageOverlay.text != null) const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        AudioOutputVolumeButton(
                          key: DemoWidgetKeys.playerAudioVolumeButton,
                          enabled: _commandConnected,
                          muted: _audioMuted,
                          onPressed: _toggleAudioOutputVolume,
                        ),
                        LocalAudioControlButton(
                          key: DemoWidgetKeys.playerLocalAudioButton,
                          enabled: _commandConnected,
                          busy: _localAudioController.busy,
                          running: _localAudioController.running,
                          onPressed: _localAudioController.toggle,
                        ),
                        DownlinkControlButton(
                          connecting: connecting,
                          playing: playing,
                          onPressed: _toggleDownlink,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _toggleDownlink() {
    if (_downlinkState == _DownlinkViewState.playing) {
      unawaited(
        _stopDownlink(
          reason: 'manual_stop',
          clearIntent: true,
          nextStatusSummary: 'Downlink stopped.',
        ),
      );
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
      _smokeFail(
        failureStage: 'audio_output_volume',
        message: 'audio output volume update failed',
        errorCode: code,
      );
      return;
    }
    setState(() {
      _audioMuted = nextMuted;
    });
    widget.smokeMarkerSink?.passed(
      nextMuted ? 'smoke_audio_output_muted' : 'smoke_audio_output_restored',
      payload: <String, Object?>{
        'volume_percent': volumePercent,
        'audio_state': _session.audioState.name,
      },
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

  bool get _showStageOverlay {
    if (_downlinkState == _DownlinkViewState.playing) {
      return false;
    }
    if (_downlinkState == _DownlinkViewState.failed) {
      return true;
    }
    if (_downlinkState == _DownlinkViewState.idle && !_shouldKeepPlaying) {
      return true;
    }
    return !_hasRenderedVideoOnce;
  }
}
