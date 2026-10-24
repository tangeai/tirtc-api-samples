import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tirtc_flutter/tirtc_flutter.dart';

import '../audio/robot_voice_effect.dart';
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
  }) : _session = session,
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
  bool robotVoiceEnabled = false;
  int? attachedStreamId;
  int startCount = 0;
  int stopCount = 0;
  bool? _preparedRobotVoiceEnabled;
  int _pcmGeneration = 0;
  DemoRobotVoiceEffect? _robotVoiceEffect;
  final Set<Future<void>> _pendingPcmSubmissions = <Future<void>>{};
  int _capturedPcmBlocks = 0;
  int _submittedPcmBlocks = 0;
  bool _submitFailureReported = false;
  bool _cycleRobotVoiceEnabled = false;
  bool _postStopActivityReported = false;

  void setRobotVoiceEnabled(bool enabled) {
    if (busy || running || robotVoiceEnabled == enabled) {
      return;
    }
    robotVoiceEnabled = enabled;
    TiRtcLogging.i('flutter_example', 'robot_voice_selection_changed enabled=$enabled');
    _notifyChanged();
  }

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
      _markerSink()?.failure(failureStage: 'local_audio_permission', message: 'microphone permission denied');
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
    final bool useRobotVoice = robotVoiceEnabled;
    final TiRtcAudioInputOptions options = _localAudioOptions(settings, useRobotVoice: useRobotVoice);
    final int pcmGeneration = _beginPcmCycle(settings, enabled: useRobotVoice);
    TiRtcLogging.i(
      'flutter_example',
      'local_audio_input_start_requested stream_id=$streamId '
          'codec=${settings.localAudioCodec} sample_rate_hz=${settings.localAudioSampleRateHz} '
          'aec=${settings.localAudioAecEnabled} agc=${settings.localAudioAgcLevel} '
          'ans=${settings.localAudioAnsLevel} robot_voice=$useRobotVoice',
    );

    int code = 0;
    if (_preparedRobotVoiceEnabled != null && _preparedRobotVoiceEnabled != useRobotVoice && attachedStreamId != null) {
      await _session.stopLocalAudio();
      await _session.detachLocalAudioFromBoundConnection();
      attachedStreamId = null;
    }
    code = await _session.prepareLocalAudio(audioOptions: options);
    if (code == 0) {
      _preparedRobotVoiceEnabled = useRobotVoice;
    }
    final int? previousStreamId = attachedStreamId;
    if (code == 0 && attachedStreamId != streamId) {
      if (attachedStreamId != null) {
        await _session.stopLocalAudio();
        await _session.detachLocalAudioFromBoundConnection();
        attachedStreamId = null;
      }
      code = await _session.attachLocalAudio(streamId: streamId);
      if (code == 0) {
        _markerSink()?.passed(
          'local_audio_input_attached',
          payload: <String, Object?>{'stream_id': streamId, 'previous_stream_id': previousStreamId},
        );
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
      _markerSink()?.passed(
        'local_audio_input_started',
        payload: <String, Object?>{
          'stream_id': streamId,
          'start_count': startCount,
          'stop_count': stopCount,
          'reused_binding': reusedBinding,
          'robot_voice': useRobotVoice,
        },
      );
      running = true;
      busy = false;
      _notifyChanged();
      return;
    }

    TiRtcLogging.w('flutter_example', 'local_audio_input_start_failed code=$code');
    await _endPcmCycle(pcmGeneration);
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
    final int pcmGeneration = _pcmGeneration;
    await _endPcmCycle(pcmGeneration);
    final int code = await _session.stopLocalAudio();
    if (code == 0) {
      stopCount += 1;
      TiRtcLogging.i('flutter_example', 'local_audio_input_stop_done stop_count=$stopCount');
      _markerSink()?.passed(
        'local_audio_input_stopped',
        payload: <String, Object?>{'stream_id': attachedStreamId, 'start_count': startCount, 'stop_count': stopCount},
      );
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

  void handleInputError({required int code, String? message}) {
    TiRtcLogging.w('flutter_example', 'local_audio_input_error code=$code message=${message ?? ''}');
    _markerSink()?.failure(failureStage: 'local_audio_input', message: 'local audio input failed', errorCode: code);
    running = false;
    busy = false;
    unawaited(_endPcmCycle(_pcmGeneration));
    _notifyChanged();
  }

  void resetAfterSessionRelease({bool notify = true}) {
    final bool changed = attachedStreamId != null || running || busy;
    _pcmGeneration += 1;
    _session.setLocalAudioPcmCallback(null);
    _robotVoiceEffect?.reset();
    _robotVoiceEffect = null;
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

  TiRtcAudioInputOptions _localAudioOptions(DemoExampleSettings settings, {required bool useRobotVoice}) {
    return TiRtcAudioInputOptions(
      media: switch (settings.localAudioCodec) {
        DemoExampleSettings.localAudioCodecAac => 3,
        DemoExampleSettings.localAudioCodecPcm => 1,
        DemoExampleSettings.localAudioCodecOpus => 4,
        DemoExampleSettings.localAudioCodecAmr => 5,
        _ => 2,
      },
      sampleRate:
          settings.localAudioSampleRateHz == DemoExampleSettings.localAudioSampleRate8k
              ? TiRtcAudioSampleRate.rate8k
              : TiRtcAudioSampleRate.rate16k,
      channels: TiRtcAudioChannelCount.mono,
      aecMode: settings.localAudioAecEnabled ? TiRtcAudioAecMode.enabled : TiRtcAudioAecMode.disabled,
      agcLevel: _localAudioAgcLevel(settings.localAudioAgcLevel),
      ansLevel: _localAudioAnsLevel(settings.localAudioAnsLevel),
      mode: useRobotVoice ? TiRtcAudioInputMode.custom : TiRtcAudioInputMode.builtIn,
      captureEnabled: true,
    );
  }

  int _beginPcmCycle(DemoExampleSettings settings, {required bool enabled}) {
    final int generation = ++_pcmGeneration;
    _capturedPcmBlocks = 0;
    _submittedPcmBlocks = 0;
    _submitFailureReported = false;
    _cycleRobotVoiceEnabled = enabled;
    _postStopActivityReported = false;
    _robotVoiceEffect?.reset();
    _robotVoiceEffect = null;
    _session.setLocalAudioPcmCallback(null);
    if (!enabled) {
      return generation;
    }
    final DemoRobotVoiceEffect effect = DemoRobotVoiceEffect(sampleRate: settings.localAudioSampleRateHz);
    _robotVoiceEffect = effect;
    _session.setLocalAudioPcmCallback((Uint8List pcm) {
      if (generation != _pcmGeneration || !identical(_robotVoiceEffect, effect)) {
        if (!_postStopActivityReported) {
          _postStopActivityReported = true;
          _markerSink()?.passed(
            'local_audio_pcm_activity_after_stop',
            payload: <String, Object?>{'generation': generation, 'current_generation': _pcmGeneration},
          );
        }
        return;
      }
      _capturedPcmBlocks += 1;
      final Uint8List processed = effect.process(pcm);
      _submitRobotPcm(generation, processed);
    });
    return generation;
  }

  void _submitRobotPcm(int generation, Uint8List pcm) {
    late final Future<void> operation;
    operation = _session
        .submitLocalAudioPcm(pcm)
        .then((int code) {
          if (generation != _pcmGeneration) {
            return;
          }
          if (code == 0) {
            _submittedPcmBlocks += 1;
            return;
          }
          TiRtcLogging.w(
            'flutter_example',
            'robot_voice_submit_failed code=$code captured_blocks=$_capturedPcmBlocks '
                'submitted_blocks=$_submittedPcmBlocks',
          );
          if (!_submitFailureReported) {
            _submitFailureReported = true;
            _showMessage('机器人变声提交失败 · ${TiRtc.formatError(code)}');
          }
        })
        .whenComplete(() {
          _pendingPcmSubmissions.remove(operation);
        });
    _pendingPcmSubmissions.add(operation);
  }

  Future<void> _endPcmCycle(int generation) async {
    if (generation != _pcmGeneration) {
      return;
    }
    _session.setLocalAudioPcmCallback(null);
    final DemoRobotVoiceEffect? effect = _robotVoiceEffect;
    _robotVoiceEffect = null;
    final List<Future<void>> pending = _pendingPcmSubmissions.toList(growable: false);
    if (pending.isNotEmpty) {
      await Future.wait<void>(pending);
    }
    effect?.reset();
    if (generation != _pcmGeneration) {
      return;
    }
    _pcmGeneration += 1;
    TiRtcLogging.i(
      'flutter_example',
      'robot_voice_cycle_done enabled=$robotVoiceEnabled captured_blocks=$_capturedPcmBlocks '
          'submitted_blocks=$_submittedPcmBlocks',
    );
    _markerSink()?.passed(
      'local_audio_pcm_cycle_completed',
      payload: <String, Object?>{
        'generation': generation,
        'mode': _cycleRobotVoiceEnabled ? 'custom' : 'built_in',
        'capture_enabled': true,
        'robot_voice': _cycleRobotVoiceEnabled,
        'callback_registered': _cycleRobotVoiceEnabled,
        'captured_blocks': _capturedPcmBlocks,
        'submitted_blocks': _submittedPcmBlocks,
        'submit_failure': _submitFailureReported,
        'pending_submissions': _pendingPcmSubmissions.length,
      },
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
