import 'dart:async';
import 'dart:typed_data';

import 'demo_echo_command.dart';

abstract interface class DemoAutomationMarkerSink {
  void passed(String marker, {Map<String, Object?> payload = const <String, Object?>{}});

  void failure({
    required String failureStage,
    required String message,
    int? errorCode,
  });
}

abstract interface class DemoPerformanceMarkerSink {
  void passed(String marker, {Map<String, Object?> payload = const <String, Object?>{}});

  void failure({
    required String errorStage,
    required String errorCode,
    required String errorMessage,
  });
}

final class DemoExampleSmokeHooks {
  const DemoExampleSmokeHooks({
    required this.markerSink,
    required this.renderWindowSeconds,
  });

  static DemoExampleSmokeHooks? current;

  final DemoAutomationMarkerSink markerSink;
  final int renderWindowSeconds;
}

const int automationCommandEchoId = demoEchoCommandId;
const String automationCommandEchoPayload = demoEchoCommandPayloadText;
const Duration automationCommandEchoTimeout = Duration(seconds: 15);
const int automationCommandSendRetryLimit = 120;
const Duration automationCommandSendRetryInterval = Duration(milliseconds: 100);

typedef AutomationCommandSend = int Function({
  required int commandId,
  required Uint8List payload,
});

final class AutomationCommandProbeResult {
  const AutomationCommandProbeResult._({
    required this.ok,
    required this.commandId,
    required this.payloadText,
    required this.payloadBytes,
    this.errorCode,
    this.timedOut = false,
  });

  factory AutomationCommandProbeResult.passed({
    required int commandId,
    required String payloadText,
    required int payloadBytes,
  }) {
    return AutomationCommandProbeResult._(
      ok: true,
      commandId: commandId,
      payloadText: payloadText,
      payloadBytes: payloadBytes,
    );
  }

  factory AutomationCommandProbeResult.failed({
    required int commandId,
    required String payloadText,
    required int payloadBytes,
    int? errorCode,
    bool timedOut = false,
  }) {
    return AutomationCommandProbeResult._(
      ok: false,
      commandId: commandId,
      payloadText: payloadText,
      payloadBytes: payloadBytes,
      errorCode: errorCode,
      timedOut: timedOut,
    );
  }

  final bool ok;
  final int commandId;
  final String payloadText;
  final int payloadBytes;
  final int? errorCode;
  final bool timedOut;
}

final class AutomationCommandProbe {
  AutomationCommandProbe()
      : payloadText = automationCommandEchoPayload,
        _payload = demoEchoCommandPayload();

  final String payloadText;
  final Uint8List _payload;
  final Completer<void> _echo = Completer<void>();

  void handleCommand(int commandId, Uint8List payload) {
    if (_echo.isCompleted || commandId != automationCommandEchoId) {
      return;
    }
    if (!_sameBytes(payload, _payload)) {
      return;
    }
    _echo.complete();
  }

  Future<AutomationCommandProbeResult> run({
    required AutomationCommandSend sendCommand,
    Duration timeout = automationCommandEchoTimeout,
  }) async {
    int sendCode = -1;
    for (int attempt = 0; attempt < automationCommandSendRetryLimit; attempt += 1) {
      sendCode = sendCommand(
        commandId: automationCommandEchoId,
        payload: Uint8List.fromList(_payload),
      );
      if (sendCode == 0) {
        break;
      }
      await Future<void>.delayed(automationCommandSendRetryInterval);
    }
    if (sendCode != 0) {
      return AutomationCommandProbeResult.failed(
        commandId: automationCommandEchoId,
        payloadText: payloadText,
        payloadBytes: _payload.length,
        errorCode: sendCode,
      );
    }
    final bool echoed = await Future.any<bool>(<Future<bool>>[
      _echo.future.then<bool>((_) => true),
      Future<void>.delayed(timeout).then<bool>((_) => false),
    ]);
    if (!echoed) {
      return AutomationCommandProbeResult.failed(
        commandId: automationCommandEchoId,
        payloadText: payloadText,
        payloadBytes: _payload.length,
        timedOut: true,
      );
    }
    return AutomationCommandProbeResult.passed(
      commandId: automationCommandEchoId,
      payloadText: payloadText,
      payloadBytes: _payload.length,
    );
  }
}

bool _sameBytes(Uint8List left, Uint8List right) {
  if (left.length != right.length) {
    return false;
  }
  for (int index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}
