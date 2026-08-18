export 'demo_token_acquisition.dart'
    show
        DemoScanPayload,
        DemoStoreScanPayload,
        DemoTokenAcquirer,
        normalizeDemoConnectionToken,
        normalizeDemoTokenServerAddress;

final class DemoExampleSettings {
  static const int videoDecoderPreferenceAuto = 0;
  static const int videoDecoderPreferenceSoftware = 1;
  static const int videoDecoderPreferenceHardware = 2;
  static const String outputBufferPolicyAutomatic = 'automatic';
  static const String outputBufferPolicyNoBuffer = 'no_buffer';
  static const String localAudioCodecG711a = 'g711a';
  static const String localAudioCodecAac = 'aac';
  static const String localAudioCodecPcm = 'pcm';
  static const String localAudioCodecOpus = 'opus';
  static const String localAudioCodecAmr = 'amr';
  static const int localAudioSampleRate8k = 8000;
  static const int localAudioSampleRate16k = 16000;
  static const int defaultLocalAudioStreamId = 14;

  static const Set<int> validVideoDecoderPreferences = <int>{
    videoDecoderPreferenceAuto,
    videoDecoderPreferenceSoftware,
    videoDecoderPreferenceHardware,
  };
  static const Set<String> validOutputBufferPolicies = <String>{
    outputBufferPolicyAutomatic,
    outputBufferPolicyNoBuffer,
  };
  static const Set<String> validLocalAudioCodecs = <String>{
    localAudioCodecG711a,
    localAudioCodecAac,
    localAudioCodecPcm,
    localAudioCodecOpus,
    localAudioCodecAmr,
  };
  static const Set<int> validLocalAudioSampleRates = <int>{
    localAudioSampleRate8k,
    localAudioSampleRate16k,
  };
  static const Set<int> validLocalAudioProcessingLevels = <int>{0, 1, 2, 3};

  const DemoExampleSettings({
    this.videoDecoderPreference = videoDecoderPreferenceAuto,
    this.outputBufferPolicy = outputBufferPolicyAutomatic,
    this.consoleLogEnabled = false,
    this.localAudioCodec = localAudioCodecG711a,
    this.localAudioSampleRateHz = localAudioSampleRate16k,
    this.localAudioStreamId = defaultLocalAudioStreamId,
    this.localAudioAecEnabled = false,
    this.localAudioAgcLevel = 0,
    this.localAudioAnsLevel = 0,
  });

  final int videoDecoderPreference;
  final String outputBufferPolicy;
  final bool consoleLogEnabled;
  final String localAudioCodec;
  final int localAudioSampleRateHz;
  final int localAudioStreamId;
  final bool localAudioAecEnabled;
  final int localAudioAgcLevel;
  final int localAudioAnsLevel;

  DemoExampleSettings copyWith({
    int? videoDecoderPreference,
    String? outputBufferPolicy,
    bool? consoleLogEnabled,
    String? localAudioCodec,
    int? localAudioSampleRateHz,
    int? localAudioStreamId,
    bool? localAudioAecEnabled,
    int? localAudioAgcLevel,
    int? localAudioAnsLevel,
  }) {
    return DemoExampleSettings(
      videoDecoderPreference: videoDecoderPreference ?? this.videoDecoderPreference,
      outputBufferPolicy: outputBufferPolicy ?? this.outputBufferPolicy,
      consoleLogEnabled: consoleLogEnabled ?? this.consoleLogEnabled,
      localAudioCodec: localAudioCodec ?? this.localAudioCodec,
      localAudioSampleRateHz: localAudioSampleRateHz ?? this.localAudioSampleRateHz,
      localAudioStreamId: localAudioStreamId ?? this.localAudioStreamId,
      localAudioAecEnabled: localAudioAecEnabled ?? this.localAudioAecEnabled,
      localAudioAgcLevel: localAudioAgcLevel ?? this.localAudioAgcLevel,
      localAudioAnsLevel: localAudioAnsLevel ?? this.localAudioAnsLevel,
    );
  }

  static bool isValidVideoDecoderPreference(int value) {
    return validVideoDecoderPreferences.contains(value);
  }

  static bool isValidOutputBufferPolicy(String value) {
    return validOutputBufferPolicies.contains(value);
  }

  static bool isValidLocalAudioCodec(String value) {
    return validLocalAudioCodecs.contains(value);
  }

  static bool isValidLocalAudioSampleRate(int value) {
    return validLocalAudioSampleRates.contains(value);
  }

  static bool isValidLocalAudioStreamId(int value) {
    return value >= 0 && value <= 15;
  }

  static bool isValidLocalAudioProcessingLevel(int value) {
    return validLocalAudioProcessingLevels.contains(value);
  }

  static String videoDecoderPreferenceLabel(int value) {
    return switch (value) {
      videoDecoderPreferenceHardware => '硬解',
      videoDecoderPreferenceSoftware => '软解',
      _ => '自动',
    };
  }

  static String outputBufferPolicyLabel(String value) {
    return switch (value) {
      outputBufferPolicyNoBuffer => '不缓冲',
      _ => '自动',
    };
  }

  static String localAudioCodecLabel(String value) {
    return switch (value) {
      localAudioCodecAac => 'AAC',
      localAudioCodecPcm => 'PCM',
      localAudioCodecOpus => 'OPUS',
      localAudioCodecAmr => 'AMR',
      _ => 'G711A',
    };
  }

  static String localAudioSampleRateLabel(int value) {
    return switch (value) {
      localAudioSampleRate8k => '8 kHz',
      _ => '16 kHz',
    };
  }

  static String localAudioProcessingLevelLabel(int value) {
    return switch (value) {
      1 => '低',
      2 => '中',
      3 => '高',
      _ => '关闭',
    };
  }
}

final class DemoDownlinkConfiguration {
  static const int defaultAudioStreamId = 10;
  static const int defaultVideoStreamId = 11;

  const DemoDownlinkConfiguration({
    required this.appId,
    required this.endpoint,
    required this.remoteId,
    required this.audioStreamId,
    required this.videoStreamId,
    required this.token,
    required this.settings,
    this.tokenServerAddress = '',
  });

  final String appId;
  final String endpoint;
  final String remoteId;
  final int audioStreamId;
  final int videoStreamId;
  final String token;
  final DemoExampleSettings settings;
  final String tokenServerAddress;

  DemoDownlinkConfiguration withToken(String resolvedToken) {
    return DemoDownlinkConfiguration(
      appId: appId,
      endpoint: endpoint,
      remoteId: remoteId,
      audioStreamId: audioStreamId,
      videoStreamId: videoStreamId,
      token: resolvedToken,
      settings: settings,
      tokenServerAddress: tokenServerAddress,
    );
  }
}

bool demoEndpointValid(String text) => _validEndpoint(text.trim());

bool _validEndpoint(String text) {
  if (text.isEmpty) {
    return true;
  }
  final Uri? uri = Uri.tryParse(text);
  return uri != null && uri.host.isNotEmpty && (uri.scheme == 'http' || uri.scheme == 'https');
}
