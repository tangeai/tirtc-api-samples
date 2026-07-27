typedef DemoVideoAttachLogger = void Function(String message);
typedef DemoVideoAttachAction = int Function();

final class DemoVideoAttachResult {
  const DemoVideoAttachResult({
    required this.optionsCode,
    required this.attachCode,
  });

  final int optionsCode;
  final int? attachCode;

  bool get optionsApplied => optionsCode == 0;
  bool get attachAttempted => attachCode != null;
}

DemoVideoAttachResult applyVideoDecoderPreferenceThenAttach({
  required int sessionGeneration,
  required int videoStreamId,
  required int requestedPreference,
  required DemoVideoAttachAction applyOptions,
  required DemoVideoAttachAction attachVideo,
  required DemoVideoAttachLogger log,
}) {
  log(
    'event=example_video_decoder_preference_apply_requested '
    'session_generation=$sessionGeneration '
    'video_stream_id=$videoStreamId '
    'requested_preference=$requestedPreference',
  );
  final int optionsCode = applyOptions();
  log(
    'event=example_video_decoder_preference_apply_result '
    'session_generation=$sessionGeneration '
    'video_stream_id=$videoStreamId '
    'requested_preference=$requestedPreference '
    'code=$optionsCode',
  );
  if (optionsCode != 0) {
    return DemoVideoAttachResult(optionsCode: optionsCode, attachCode: null);
  }

  log(
    'event=example_video_attach_requested '
    'session_generation=$sessionGeneration '
    'video_stream_id=$videoStreamId '
    'requested_preference=$requestedPreference',
  );
  final int attachCode = attachVideo();
  log(
    'event=example_video_attach_result '
    'session_generation=$sessionGeneration '
    'video_stream_id=$videoStreamId '
    'requested_preference=$requestedPreference '
    'code=$attachCode',
  );
  return DemoVideoAttachResult(optionsCode: optionsCode, attachCode: attachCode);
}
