import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:tirtc_flutter/tirtc_flutter.dart';

const Duration demoStreamMessagePeriod = Duration(seconds: 10);
const Duration demoStreamMessageBubbleDuration = Duration(seconds: 4);
final BigInt _fnv1a64OffsetBasis = BigInt.parse('cbf29ce484222325', radix: 16);
final BigInt _fnv1a64Prime = BigInt.parse('100000001b3', radix: 16);
final BigInt _uint64Mask = (BigInt.one << 64) - BigInt.one;

Uint8List encodeDemoStreamMessagePayload({DateTime? now}) {
  final int epochSeconds = ((now ?? DateTime.now()).millisecondsSinceEpoch / 1000).floor();
  return Uint8List.fromList(utf8.encode(epochSeconds.toString()));
}

int? decodeDemoStreamMessageEpochSeconds(Uint8List payload) {
  final String text;
  try {
    text = utf8.decode(payload, allowMalformed: false);
  } on FormatException {
    return null;
  }
  final int? epochSeconds = int.tryParse(text);
  if (epochSeconds == null || epochSeconds <= 0) {
    return null;
  }
  return epochSeconds;
}

String demoStreamMessagePayloadHash(Uint8List payload) {
  BigInt hash = _fnv1a64OffsetBasis;
  for (final int byte in payload) {
    hash ^= BigInt.from(byte);
    hash = (hash * _fnv1a64Prime) & _uint64Mask;
  }
  return 'fnv1a64:${hash.toRadixString(16).padLeft(16, '0')}';
}

final class DemoStreamMessageSendEvent {
  const DemoStreamMessageSendEvent({
    required this.sessionIndex,
    required this.streamId,
    required this.epochSeconds,
    required this.payloadBytes,
    required this.payloadHash,
    required this.resultCode,
    required this.sentCount,
    required this.periodicSendOk,
  });

  final int sessionIndex;
  final int streamId;
  final int epochSeconds;
  final int payloadBytes;
  final String payloadHash;
  final int resultCode;
  final int sentCount;
  final bool periodicSendOk;
}

final class DemoStreamMessageSender {
  DemoStreamMessageSender({
    required this.streamId,
    this.period = demoStreamMessagePeriod,
    this.onSent,
  });

  final int streamId;
  final Duration period;
  final void Function(DemoStreamMessageSendEvent event)? onSent;
  final Map<TiRtcConn, Timer> _timers = <TiRtcConn, Timer>{};
  final Map<TiRtcConn, int> _sessionIndexes = <TiRtcConn, int>{};
  final Map<TiRtcConn, int> _sentCounts = <TiRtcConn, int>{};

  void start(TiRtcConn connection, {required int sessionIndex}) {
    stop(connection);
    _sessionIndexes[connection] = sessionIndex;
    _sentCounts[connection] = 0;
    _send(connection);
    _timers[connection] = Timer.periodic(period, (_) {
      _send(connection);
    });
  }

  void stop(TiRtcConn connection) {
    _timers.remove(connection)?.cancel();
    _sessionIndexes.remove(connection);
    _sentCounts.remove(connection);
  }

  void stopAll() {
    for (final Timer timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _sessionIndexes.clear();
    _sentCounts.clear();
  }

  void _send(TiRtcConn connection) {
    final Uint8List payload = encodeDemoStreamMessagePayload();
    final int? epochSeconds = decodeDemoStreamMessageEpochSeconds(payload);
    final int resultCode = connection.sendStreamMessage(streamId: streamId, timestampMs: 0, data: payload);
    final int sentCount = (_sentCounts[connection] ?? 0) + (resultCode == 0 ? 1 : 0);
    _sentCounts[connection] = sentCount;
    final DemoStreamMessageSendEvent event = DemoStreamMessageSendEvent(
      sessionIndex: _sessionIndexes[connection] ?? 0,
      streamId: streamId,
      epochSeconds: epochSeconds ?? 0,
      payloadBytes: payload.length,
      payloadHash: demoStreamMessagePayloadHash(payload),
      resultCode: resultCode,
      sentCount: sentCount,
      periodicSendOk: sentCount >= 2,
    );
    onSent?.call(event);
    TiRtcLogging.i(
      'flutter_example',
      'stream_message_sent stream_id=$streamId payload_epoch_seconds=${event.epochSeconds} code=$resultCode',
    );
  }
}

final class DemoStreamMessageReceiveEvent {
  const DemoStreamMessageReceiveEvent({
    required this.streamId,
    required this.timestampMs,
    required this.epochSeconds,
    required this.payloadBytes,
    required this.payloadHash,
    required this.count,
  });

  final int streamId;
  final int timestampMs;
  final int epochSeconds;
  final int payloadBytes;
  final String payloadHash;
  final int count;
}

final class DemoStreamMessageOverlayController {
  DemoStreamMessageOverlayController({
    this.bubbleDuration = demoStreamMessageBubbleDuration,
  });

  final Duration bubbleDuration;
  Timer? _hideTimer;
  String? _text;
  int _receivedCount = 0;

  String? get text => _text;

  int get receivedCount => _receivedCount;

  DemoStreamMessageReceiveEvent? handleIncoming({
    required int expectedStreamId,
    required int streamId,
    required int timestampMs,
    required Uint8List payload,
    required bool Function() isActive,
    required VoidCallback onChanged,
  }) {
    if (!isActive() || streamId != expectedStreamId) {
      return null;
    }
    final int? epochSeconds = decodeDemoStreamMessageEpochSeconds(payload);
    if (epochSeconds == null) {
      return null;
    }

    _receivedCount += 1;
    _text = epochSeconds.toString();
    _hideTimer?.cancel();
    _hideTimer = Timer(bubbleDuration, () {
      if (!isActive()) {
        return;
      }
      _text = null;
      onChanged();
    });
    onChanged();

    return DemoStreamMessageReceiveEvent(
      streamId: streamId,
      timestampMs: timestampMs,
      epochSeconds: epochSeconds,
      payloadBytes: payload.length,
      payloadHash: demoStreamMessagePayloadHash(payload),
      count: _receivedCount,
    );
  }

  void clear({VoidCallback? onChanged}) {
    _hideTimer?.cancel();
    _hideTimer = null;
    final bool changed = _text != null;
    _text = null;
    if (changed) {
      onChanged?.call();
    }
  }

  void dispose() {
    clear();
  }
}
