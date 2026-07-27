import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tirtc_flutter/tirtc_flutter.dart';

import '../demo_configuration.dart';
import '../demo_downlink_session.dart';
import '../demo_permissions.dart';
import '../demo_test_hooks.dart';

class DemoPlayerLocalAudioController {
  DemoPlayerLocalAudioController({
    required DemoDownlinkSession session,
    required DemoExampleSettings Function() settings,
    required bool Function() isMounted,
    required bool Function() isCommandConnected,
    required DemoAutomationMarkerSink? Function() markerSink,
    required VoidCallback onChanged,
    required void Function(String message) showMessage,
    DemoExamplePermissions permissions = const DemoExamplePermissions(),
  })  : _session = session,
        _settings = settings,
        _isMounted = isMounted,
        _isCommandConnected = isCommandConnected,
        _markerSink = markerSink,
        _onChanged = onChanged,
        _showMessage = showMessage,
        _permissions = permissions;

  static const Duration _connectionWaitTimeout = Duration(seconds: 8);
  static const Duration _connectionWaitPollInterval = Duration(milliseconds: 100);

  final DemoDownlinkSession _session;
  final DemoExampleSettings Function() _settings;
  final bool Function() _isMounted;
  final bool Function() _isCommandConnected;
  final DemoAutomationMarkerSink? Function() _markerSink;
  final VoidCallback _onChanged;
  final void Function(String message) _showMessage;
  final DemoExamplePermissions _permissions;

  bool running = false;
  bool busy = false;
  int? attachedStreamId;
  int startCount = 0;
  int stopCount = 0;

  void toggle() {
    TiRtcLogging.i(
      'flutter_example',
      'local_audio_input_toggle_requested running=$running '
          'busy=$busy command_connected=${_isCommandConnected()}',
    );
    if (running) {
      unawaited(stop(reason: 'manual_stop'));
      return;
    }
    unawaited(start());
  }

  Future<void> start() async {
    if (busy || !_isCommandConnected()) {
      return;
    }
    _setBusy(true);

    TiRtcLogging.i('flutter_example', 'local_audio_input_permission_check_start');
    final bool microphoneReady =
        await _permissions.checkMicrophonePermission() || await _permissions.requestMicrophonePermission();
    TiRtcLogging.i('flutter_example', 'local_audio_input_permission_check_done granted=$microphoneReady');
    if (!_isMounted()) {
      busy = false;
      return;
    }
    if (!microphoneReady) {
      TiRtcLogging.w('flutter_example', 'local_audio_input_permission_denied');
      _markerSink()?.failure(
        failureStage: 'local_audio_permission',
        message: 'microphone permission denied',
      );
      _showMessage('麦克风权限未授权。');
      _setBusy(false);
      return;
    }
    if (!_isCommandConnected() && !await _waitForConnection()) {
      TiRtcLogging.w('flutter_example', 'local_audio_input_connection_unavailable_after_permission');
      _markerSink()?.failure(
        failureStage: 'local_audio_connection',
        message: 'local audio connection unavailable after microphone permission',
      );
      _setBusy(false);
      return;
    }

    final DemoExampleSettings settings = _settings();
    final int streamId = settings.localAudioStreamId;
    final TiRtcAudioInputOptions options = _localAudioOptions(settings);
    TiRtcLogging.i(
      'flutter_example',
      'local_audio_input_start_requested stream_id=$streamId '
          'codec=${settings.localAudioCodec} sample_rate_hz=${settings.localAudioSampleRateHz} '
          'aec=${settings.localAudioAecEnabled} agc=${settings.localAudioAgcLevel} ans=${settings.localAudioAnsLevel}',
    );

    int code = await _session.prepareLocalAudio(audioOptions: options);
    final int? previousStreamId = attachedStreamId;
    if (code == 0 && attachedStreamId != streamId) {
      if (attachedStreamId != null) {
        await _session.stopLocalAudio();
        await _session.detachLocalAudioFromBoundConnection();
        attachedStreamId = null;
      }
      code = await _session.attachLocalAudio(streamId: streamId);
      if (code == 0) {
        _markerSink()?.passed('local_audio_input_attached', payload: <String, Object?>{
          'stream_id': streamId,
          'previous_stream_id': previousStreamId,
        });
        attachedStreamId = streamId;
      }
    }
    final bool reusedBinding = code == 0 && previousStreamId == streamId;
    if (code == 0) {
      code = await _session.startLocalAudio();
    }
    if (code == 0) {
      startCount += 1;
      TiRtcLogging.i(
        'flutter_example',
        'local_audio_input_start_done stream_id=$streamId start_count=$startCount reused_binding=$reusedBinding',
      );
      _markerSink()?.passed('local_audio_input_started', payload: <String, Object?>{
        'stream_id': streamId,
        'start_count': startCount,
        'stop_count': stopCount,
        'reused_binding': reusedBinding,
      });
      running = true;
      busy = false;
      _notifyChanged();
      return;
    }

    TiRtcLogging.w('flutter_example', 'local_audio_input_start_failed code=$code');
    _markerSink()?.failure(
      failureStage: 'local_audio_start',
      message: 'local audio input start failed',
      errorCode: code,
    );
    _showMessage('麦克风启动失败 · ${TiRtc.formatError(code)}');
    running = false;
    busy = false;
    _notifyChanged();
  }

  Future<void> stop({required String reason}) async {
    if (busy) {
      return;
    }
    _setBusy(true);
    TiRtcLogging.i('flutter_example', 'local_audio_input_stop_requested reason=$reason');
    final int code = await _session.stopLocalAudio();
    if (code == 0) {
      stopCount += 1;
      TiRtcLogging.i('flutter_example', 'local_audio_input_stop_done stop_count=$stopCount');
      _markerSink()?.passed('local_audio_input_stopped', payload: <String, Object?>{
        'stream_id': attachedStreamId,
        'start_count': startCount,
        'stop_count': stopCount,
      });
      running = false;
      busy = false;
      _notifyChanged();
      return;
    }
    TiRtcLogging.w('flutter_example', 'local_audio_input_stop_failed code=$code');
    _showMessage('麦克风停止失败 · ${TiRtc.formatError(code)}');
    _setBusy(false);
  }

  void handleInputState(TiRtcInputState state) {
    TiRtcLogging.i('flutter_example', 'local_audio_input_state state=${state.name}');
    if (state == TiRtcInputState.running && !running) {
      running = true;
      _notifyChanged();
    } else if (state != TiRtcInputState.running && running) {
      running = false;
      _notifyChanged();
    }
  }

  void handleInputError({
    required int code,
    String? message,
  }) {
    TiRtcLogging.w('flutter_example', 'local_audio_input_error code=$code message=${message ?? ''}');
    _markerSink()?.failure(
      failureStage: 'local_audio_input',
      message: 'local audio input failed',
      errorCode: code,
    );
    running = false;
    busy = false;
    _notifyChanged();
  }

  void resetAfterSessionRelease({bool notify = true}) {
    final bool changed = attachedStreamId != null || running || busy;
    attachedStreamId = null;
    running = false;
    busy = false;
    if (changed && notify) {
      _notifyChanged();
    }
  }

  Future<bool> _waitForConnection() async {
    final Stopwatch stopwatch = Stopwatch()..start();
    TiRtcLogging.i('flutter_example', 'local_audio_input_wait_for_connection_start');
    while (_isMounted() && !_isCommandConnected() && stopwatch.elapsed < _connectionWaitTimeout) {
      await Future<void>.delayed(_connectionWaitPollInterval);
    }
    final bool ready = _isMounted() && _isCommandConnected();
    TiRtcLogging.i(
      'flutter_example',
      'local_audio_input_wait_for_connection_done ready=$ready elapsed_ms=${stopwatch.elapsedMilliseconds}',
    );
    return ready;
  }

  TiRtcAudioInputOptions _localAudioOptions(DemoExampleSettings settings) {
    return TiRtcAudioInputOptions(
      codec: switch (settings.localAudioCodec) {
        DemoExampleSettings.localAudioCodecAac => TiRtcAudioCodec.aac,
        DemoExampleSettings.localAudioCodecPcm => TiRtcAudioCodec.pcm,
        DemoExampleSettings.localAudioCodecOpus => TiRtcAudioCodec.opus,
        DemoExampleSettings.localAudioCodecAmr => TiRtcAudioCodec.amr,
        _ => TiRtcAudioCodec.g711a,
      },
      sampleRate: settings.localAudioSampleRateHz == DemoExampleSettings.localAudioSampleRate8k
          ? TiRtcAudioSampleRate.rate8k
          : TiRtcAudioSampleRate.rate16k,
      channels: TiRtcAudioChannelCount.mono,
      aecMode: settings.localAudioAecEnabled ? TiRtcAudioAecMode.enabled : TiRtcAudioAecMode.disabled,
      agcLevel: _localAudioAgcLevel(settings.localAudioAgcLevel),
      ansLevel: _localAudioAnsLevel(settings.localAudioAnsLevel),
    );
  }

  TiRtcAudioAgcLevel _localAudioAgcLevel(int value) {
    return switch (value) {
      1 => TiRtcAudioAgcLevel.low,
      2 => TiRtcAudioAgcLevel.medium,
      3 => TiRtcAudioAgcLevel.high,
      _ => TiRtcAudioAgcLevel.disabled,
    };
  }

  TiRtcAudioAnsLevel _localAudioAnsLevel(int value) {
    return switch (value) {
      1 => TiRtcAudioAnsLevel.low,
      2 => TiRtcAudioAnsLevel.medium,
      3 => TiRtcAudioAnsLevel.high,
      _ => TiRtcAudioAnsLevel.disabled,
    };
  }

  void _setBusy(bool nextBusy) {
    if (busy == nextBusy) {
      return;
    }
    busy = nextBusy;
    _notifyChanged();
  }

  void _notifyChanged() {
    if (_isMounted()) {
      _onChanged();
    }
  }
}
