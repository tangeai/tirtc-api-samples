import 'dart:convert';
import 'dart:typed_data';

import '../demo_echo_command.dart';

const int demoCommandPanelEventLimit = 20;
const int _maxCommandId = 0xffffffff;
const int demoCommandEchoPresetId = demoEchoCommandId;
const String demoCommandEchoPresetPayload = demoEchoCommandPayloadText;

enum DemoCommandPayloadMode {
  hex,
  text,
}

enum DemoCommandEventDirection {
  sent,
  received,
}

final class DemoCommandParseResult<T> {
  const DemoCommandParseResult._({
    required this.value,
    required this.error,
  });

  const DemoCommandParseResult.success(T value) : this._(value: value, error: null);

  const DemoCommandParseResult.failure(String error) : this._(value: null, error: error);

  final T? value;
  final String? error;

  bool get valid => error == null;
}

final class DemoCommandPanelEvent {
  DemoCommandPanelEvent({
    required this.direction,
    required this.commandId,
    required Uint8List payload,
    required this.createdAt,
    this.resultCode,
  }) : payload = Uint8List.fromList(payload);

  final DemoCommandEventDirection direction;
  final int commandId;
  final Uint8List payload;
  final int? resultCode;
  final DateTime createdAt;

  String get commandIdLabel => formatDemoCommandId(commandId);

  String get payloadHex => formatDemoCommandPayloadHex(payload);
}

final class DemoCommandPreset {
  const DemoCommandPreset({
    required this.label,
    required this.commandId,
    required this.payloadMode,
    required this.payloadText,
  });

  final String label;
  final int commandId;
  final DemoCommandPayloadMode payloadMode;
  final String payloadText;

  String get commandIdLabel => formatDemoCommandId(commandId);
}

const List<DemoCommandPreset> demoCommonCommandPresets = <DemoCommandPreset>[
  DemoCommandPreset(
    label: 'Echo',
    commandId: demoCommandEchoPresetId,
    payloadMode: DemoCommandPayloadMode.text,
    payloadText: demoCommandEchoPresetPayload,
  ),
];

DemoCommandParseResult<int> parseDemoCommandId(String input) {
  final String value = input.trim();
  if (value.isEmpty) {
    return const DemoCommandParseResult<int>.failure('请输入命令 ID');
  }

  final bool hex = value.startsWith('0x') || value.startsWith('0X');
  final String digits = hex ? value.substring(2) : value;
  if (digits.isEmpty) {
    return const DemoCommandParseResult<int>.failure('请输入命令 ID');
  }

  final int? commandId = int.tryParse(digits, radix: hex ? 16 : 10);
  if (commandId == null || commandId < 0 || commandId > _maxCommandId) {
    return const DemoCommandParseResult<int>.failure('命令 ID 必须是 32 位无符号整数');
  }
  return DemoCommandParseResult<int>.success(commandId);
}

DemoCommandParseResult<Uint8List> parseDemoCommandPayload({
  required String input,
  required DemoCommandPayloadMode mode,
}) {
  switch (mode) {
    case DemoCommandPayloadMode.hex:
      return _parseHexPayload(input);
    case DemoCommandPayloadMode.text:
      return DemoCommandParseResult<Uint8List>.success(Uint8List.fromList(utf8.encode(input)));
  }
}

DemoCommandParseResult<Uint8List> _parseHexPayload(String input) {
  final String normalized = input.replaceAll(RegExp(r'[\s,]+'), '');
  if (normalized.isEmpty) {
    return DemoCommandParseResult<Uint8List>.success(Uint8List(0));
  }
  if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(normalized)) {
    return const DemoCommandParseResult<Uint8List>.failure('HEX 内容包含无效字符');
  }
  if (normalized.length.isOdd) {
    return const DemoCommandParseResult<Uint8List>.failure('HEX 内容必须是偶数位');
  }

  final Uint8List bytes = Uint8List(normalized.length ~/ 2);
  for (int offset = 0; offset < normalized.length; offset += 2) {
    bytes[offset ~/ 2] = int.parse(normalized.substring(offset, offset + 2), radix: 16);
  }
  return DemoCommandParseResult<Uint8List>.success(bytes);
}

String formatDemoCommandId(int commandId) {
  final int normalized = commandId & _maxCommandId;
  return '0x${normalized.toRadixString(16).toUpperCase().padLeft(8, '0')}';
}

String formatDemoCommandPayloadHex(Uint8List payload) {
  return payload.map((int byte) => byte.toRadixString(16).toUpperCase().padLeft(2, '0')).join(' ');
}

List<DemoCommandPanelEvent> trimDemoCommandEvents(Iterable<DemoCommandPanelEvent> events) {
  final List<DemoCommandPanelEvent> values = List<DemoCommandPanelEvent>.of(events);
  if (values.length <= demoCommandPanelEventLimit) {
    return values;
  }
  return values.sublist(values.length - demoCommandPanelEventLimit);
}
