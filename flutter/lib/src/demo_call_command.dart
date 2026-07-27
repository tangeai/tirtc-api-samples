import 'dart:convert';
import 'dart:typed_data';

const int demoCallCommandId = 0x54524343;

enum DemoCallCommandAction {
  startCall('start_call'),
  callReady('call_ready'),
  callReject('call_reject');

  const DemoCallCommandAction(this.wireName);

  final String wireName;

  static DemoCallCommandAction? fromWireName(String value) {
    for (final DemoCallCommandAction action in values) {
      if (action.wireName == value) {
        return action;
      }
    }
    return null;
  }
}

enum DemoCallRole { initiator, responder }

final class DemoCallStreamIds {
  static const int defaultInitiatorAudio = 10;
  static const int defaultInitiatorVideo = 11;
  static const int defaultResponderAudio = 20;
  static const int defaultResponderVideo = 21;

  const DemoCallStreamIds({
    this.initiatorAudio = defaultInitiatorAudio,
    this.initiatorVideo = defaultInitiatorVideo,
    this.responderAudio = defaultResponderAudio,
    this.responderVideo = defaultResponderVideo,
  });

  final int initiatorAudio;
  final int initiatorVideo;
  final int responderAudio;
  final int responderVideo;

  int localAudio(DemoCallRole role) {
    return role == DemoCallRole.initiator ? initiatorAudio : responderAudio;
  }

  int localVideo(DemoCallRole role) {
    return role == DemoCallRole.initiator ? initiatorVideo : responderVideo;
  }

  int remoteAudio(DemoCallRole role) {
    return role == DemoCallRole.initiator ? responderAudio : initiatorAudio;
  }

  int remoteVideo(DemoCallRole role) {
    return role == DemoCallRole.initiator ? responderVideo : initiatorVideo;
  }

  bool isValid({required bool audioEnabled, required bool videoEnabled}) {
    final List<int> enabled = <int>[
      if (audioEnabled) initiatorAudio,
      if (videoEnabled) initiatorVideo,
      if (audioEnabled) responderAudio,
      if (videoEnabled) responderVideo,
    ];
    if (enabled.any((int value) => value < 0 || value > 255)) {
      return false;
    }
    return enabled.toSet().length == enabled.length;
  }

  Map<String, Object?> toJson({
    required bool audioEnabled,
    required bool videoEnabled,
  }) {
    return <String, Object?>{
      if (audioEnabled) 'initiator_audio_stream_id': initiatorAudio,
      if (videoEnabled) 'initiator_video_stream_id': initiatorVideo,
      if (audioEnabled) 'responder_audio_stream_id': responderAudio,
      if (videoEnabled) 'responder_video_stream_id': responderVideo,
    };
  }
}

final class DemoCallCommand {
  const DemoCallCommand({
    required this.action,
    required this.requestId,
    this.audioEnabled = true,
    this.videoEnabled = true,
    this.streamIds = const DemoCallStreamIds(),
    this.reason,
  });

  final DemoCallCommandAction action;
  final String requestId;
  final bool audioEnabled;
  final bool videoEnabled;
  final DemoCallStreamIds streamIds;
  final String? reason;

  bool get valid {
    if (requestId.isEmpty) {
      return false;
    }
    if (action == DemoCallCommandAction.callReject) {
      return true;
    }
    return streamIds.isValid(audioEnabled: audioEnabled, videoEnabled: videoEnabled);
  }

  DemoCallCommand readyResponse() {
    return DemoCallCommand(
      action: DemoCallCommandAction.callReady,
      requestId: requestId,
      audioEnabled: audioEnabled,
      videoEnabled: videoEnabled,
      streamIds: streamIds,
    );
  }

  Uint8List encode() {
    final Map<String, Object?> payload = <String, Object?>{
      'schema_version': 1,
      'action': action.wireName,
      'request_id': requestId,
      if (action != DemoCallCommandAction.callReject) ...<String, Object?>{
        'audio_enabled': audioEnabled,
        'video_enabled': videoEnabled,
        ...streamIds.toJson(audioEnabled: audioEnabled, videoEnabled: videoEnabled),
      },
      if (action == DemoCallCommandAction.callReject && reason != null) 'reason': reason,
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(payload)));
  }

  static DemoCallCommand? tryDecode({
    required int commandId,
    required Uint8List data,
  }) {
    if (commandId != demoCallCommandId) {
      return null;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(data));
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, Object?>) {
      return null;
    }
    if (decoded['schema_version'] != 1) {
      return null;
    }
    final Object? rawAction = decoded['action'];
    final Object? rawRequestId = decoded['request_id'];
    if (rawAction is! String || rawRequestId is! String || rawRequestId.isEmpty) {
      return null;
    }
    final DemoCallCommandAction? action = DemoCallCommandAction.fromWireName(rawAction);
    if (action == null) {
      return null;
    }
    if (action == DemoCallCommandAction.callReject) {
      final Object? reason = decoded['reason'];
      return DemoCallCommand(
        action: action,
        requestId: rawRequestId,
        reason: reason is String ? reason : null,
      );
    }
    final Object? rawAudioEnabled = decoded['audio_enabled'];
    final Object? rawVideoEnabled = decoded['video_enabled'];
    if (rawAudioEnabled is! bool || rawVideoEnabled is! bool) {
      return null;
    }
    final DemoCallStreamIds? streamIds = _decodeStreamIds(
      decoded,
      audioEnabled: rawAudioEnabled,
      videoEnabled: rawVideoEnabled,
    );
    if (streamIds == null) {
      return null;
    }
    final DemoCallCommand result = DemoCallCommand(
      action: action,
      requestId: rawRequestId,
      audioEnabled: rawAudioEnabled,
      videoEnabled: rawVideoEnabled,
      streamIds: streamIds,
    );
    return result.valid ? result : null;
  }

  static DemoCallStreamIds? _decodeStreamIds(
    Map<String, Object?> payload, {
    required bool audioEnabled,
    required bool videoEnabled,
  }) {
    final int initiatorAudio = audioEnabled ? _intValue(payload['initiator_audio_stream_id']) : 0;
    final int initiatorVideo = videoEnabled ? _intValue(payload['initiator_video_stream_id']) : 0;
    final int responderAudio = audioEnabled ? _intValue(payload['responder_audio_stream_id']) : 0;
    final int responderVideo = videoEnabled ? _intValue(payload['responder_video_stream_id']) : 0;
    if ((audioEnabled && (initiatorAudio < 0 || responderAudio < 0)) ||
        (videoEnabled && (initiatorVideo < 0 || responderVideo < 0))) {
      return null;
    }
    return DemoCallStreamIds(
      initiatorAudio: initiatorAudio,
      initiatorVideo: initiatorVideo,
      responderAudio: responderAudio,
      responderVideo: responderVideo,
    );
  }

  static int _intValue(Object? value) {
    return value is int && value >= 0 && value <= 255 ? value : -1;
  }
}
