import 'dart:convert';
import 'dart:typed_data';

const int demoEchoCommandId = 0xffffffff;
const String demoEchoCommandPayloadText = 'echo';

typedef DemoEchoCommandSender = int Function(int commandId, Uint8List payload);

Uint8List demoEchoCommandPayload() {
  return Uint8List.fromList(utf8.encode(demoEchoCommandPayloadText));
}

bool isDemoEchoCommand({
  required int commandId,
  required Uint8List payload,
}) {
  return commandId == demoEchoCommandId && _sameBytes(payload, demoEchoCommandPayload());
}

int? echoDemoCommandIfNeeded({
  required int commandId,
  required Uint8List payload,
  required DemoEchoCommandSender sendCommand,
}) {
  if (!isDemoEchoCommand(commandId: commandId, payload: payload)) {
    return null;
  }
  return sendCommand(commandId, Uint8List.fromList(payload));
}

final class DemoEchoCommandResponder {
  int _pendingLocalEchoReplies = 0;

  void trackLocalSend({
    required int commandId,
    required Uint8List payload,
    required int resultCode,
  }) {
    if (resultCode == 0 && isDemoEchoCommand(commandId: commandId, payload: payload)) {
      _pendingLocalEchoReplies += 1;
    }
  }

  int? handleReceived({
    required int commandId,
    required Uint8List payload,
    required DemoEchoCommandSender sendCommand,
  }) {
    if (!isDemoEchoCommand(commandId: commandId, payload: payload)) {
      return null;
    }
    if (_pendingLocalEchoReplies > 0) {
      _pendingLocalEchoReplies -= 1;
      return null;
    }
    final int code = sendCommand(commandId, Uint8List.fromList(payload));
    trackLocalSend(commandId: commandId, payload: payload, resultCode: code);
    return code;
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
