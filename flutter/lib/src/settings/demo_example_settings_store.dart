import 'package:tirtc_flutter/tirtc_flutter.dart';

import '../demo_configuration.dart';
import 'example_preferences.dart';

final class DemoExampleSettingsStore {
  const DemoExampleSettingsStore({
    this.preferences = const MethodChannelDemoExamplePreferences(),
  });

  static const String videoDecoderPreferenceKey = 'tirtc_example.settings.video_decoder_preference';
  static const String outputBufferPolicyKey = 'tirtc_example.settings.output_buffer_policy';
  static const String consoleLogEnabledKey = 'tirtc_example.settings.console_log_enabled';
  static const String localAudioCodecKey = 'tirtc_example.settings.local_audio_codec';
  static const String localAudioSampleRateKey = 'tirtc_example.settings.local_audio_sample_rate_hz';
  static const String localAudioStreamIdKey = 'tirtc_example.settings.local_audio_stream_id';
  static const String localAudioAecEnabledKey = 'tirtc_example.settings.local_audio_aec_enabled';
  static const String localAudioAgcLevelKey = 'tirtc_example.settings.local_audio_agc_level';
  static const String localAudioAnsLevelKey = 'tirtc_example.settings.local_audio_ans_level';

  final DemoExamplePreferences preferences;

  Future<DemoExampleSettings> load({
    int? testVideoDecoderPreference,
    String? testOutputBufferPolicy,
  }) async {
    final DemoExampleSettings manualSettings = await _loadManualSettings();
    if (testVideoDecoderPreference == null && testOutputBufferPolicy == null) {
      return manualSettings;
    }

    return DemoExampleSettings(
      videoDecoderPreference: _validVideoDecoderPreferenceOrDefault(
        testVideoDecoderPreference ?? manualSettings.videoDecoderPreference,
      ),
      outputBufferPolicy:
          _validOutputBufferPolicyOrDefault(testOutputBufferPolicy ?? manualSettings.outputBufferPolicy),
      consoleLogEnabled: true,
      localAudioCodec: manualSettings.localAudioCodec,
      localAudioSampleRateHz: manualSettings.localAudioSampleRateHz,
      localAudioStreamId: manualSettings.localAudioStreamId,
      localAudioAecEnabled: manualSettings.localAudioAecEnabled,
      localAudioAgcLevel: manualSettings.localAudioAgcLevel,
      localAudioAnsLevel: manualSettings.localAudioAnsLevel,
    );
  }

  Future<void> save(DemoExampleSettings settings) async {
    await preferences.putInt(
      key: videoDecoderPreferenceKey,
      value: _validVideoDecoderPreferenceOrDefault(settings.videoDecoderPreference),
    );
    await preferences.putString(
      key: outputBufferPolicyKey,
      value: _validOutputBufferPolicyOrDefault(settings.outputBufferPolicy),
    );
    await preferences.putInt(
      key: consoleLogEnabledKey,
      value: settings.consoleLogEnabled ? 1 : 0,
    );
    await preferences.putString(
      key: localAudioCodecKey,
      value: _validLocalAudioCodecOrDefault(settings.localAudioCodec),
    );
    await preferences.putInt(
      key: localAudioSampleRateKey,
      value: _validLocalAudioSampleRateOrDefault(settings.localAudioSampleRateHz),
    );
    await preferences.putInt(
      key: localAudioStreamIdKey,
      value: _validLocalAudioStreamIdOrDefault(settings.localAudioStreamId),
    );
    await preferences.putInt(
      key: localAudioAecEnabledKey,
      value: settings.localAudioAecEnabled ? 1 : 0,
    );
    await preferences.putInt(
      key: localAudioAgcLevelKey,
      value: _validLocalAudioProcessingLevelOrDefault(settings.localAudioAgcLevel),
    );
    await preferences.putInt(
      key: localAudioAnsLevelKey,
      value: _validLocalAudioProcessingLevelOrDefault(settings.localAudioAnsLevel),
    );
  }

  Future<DemoExampleSettings> _loadManualSettings() async {
    final int videoDecoderPreference = await _readInt(
      key: videoDecoderPreferenceKey,
      defaultValue: DemoExampleSettings.videoDecoderPreferenceAuto,
    );
    final int consoleLogEnabled = await _readInt(
      key: consoleLogEnabledKey,
      defaultValue: 0,
    );
    final String outputBufferPolicy = await _readString(
      key: outputBufferPolicyKey,
      defaultValue: DemoExampleSettings.outputBufferPolicyAutomatic,
    );
    final String localAudioCodec = await _readString(
      key: localAudioCodecKey,
      defaultValue: DemoExampleSettings.localAudioCodecG711a,
    );
    final int localAudioSampleRateHz = await _readInt(
      key: localAudioSampleRateKey,
      defaultValue: DemoExampleSettings.localAudioSampleRate16k,
    );
    final int localAudioStreamId = await _readInt(
      key: localAudioStreamIdKey,
      defaultValue: DemoExampleSettings.defaultLocalAudioStreamId,
    );
    final int localAudioAecEnabled = await _readInt(
      key: localAudioAecEnabledKey,
      defaultValue: 0,
    );
    final int localAudioAgcLevel = await _readInt(
      key: localAudioAgcLevelKey,
      defaultValue: 0,
    );
    final int localAudioAnsLevel = await _readInt(
      key: localAudioAnsLevelKey,
      defaultValue: 0,
    );

    return DemoExampleSettings(
      videoDecoderPreference: _validVideoDecoderPreferenceOrDefault(videoDecoderPreference),
      outputBufferPolicy: _validOutputBufferPolicyOrDefault(outputBufferPolicy),
      consoleLogEnabled: consoleLogEnabled == 1,
      localAudioCodec: _validLocalAudioCodecOrDefault(localAudioCodec),
      localAudioSampleRateHz: _validLocalAudioSampleRateOrDefault(localAudioSampleRateHz),
      localAudioStreamId: _validLocalAudioStreamIdOrDefault(localAudioStreamId),
      localAudioAecEnabled: localAudioAecEnabled == 1,
      localAudioAgcLevel: _validLocalAudioProcessingLevelOrDefault(localAudioAgcLevel),
      localAudioAnsLevel: _validLocalAudioProcessingLevelOrDefault(localAudioAnsLevel),
    );
  }

  Future<int> _readInt({
    required String key,
    required int defaultValue,
  }) async {
    try {
      return await preferences.getInt(key: key, defaultValue: defaultValue);
    } on Object catch (error) {
      TiRtcLogging.w(
        'flutter_example',
        'example_settings_read_failed key=$key error=$error',
      );
      return defaultValue;
    }
  }

  Future<String> _readString({
    required String key,
    required String defaultValue,
  }) async {
    try {
      return await preferences.getString(key: key, defaultValue: defaultValue);
    } on Object catch (error) {
      TiRtcLogging.w(
        'flutter_example',
        'example_settings_read_failed key=$key error=$error',
      );
      return defaultValue;
    }
  }

  static int _validVideoDecoderPreferenceOrDefault(int value) {
    if (DemoExampleSettings.isValidVideoDecoderPreference(value)) {
      return value;
    }
    return DemoExampleSettings.videoDecoderPreferenceAuto;
  }

  static String _validOutputBufferPolicyOrDefault(String value) {
    if (DemoExampleSettings.isValidOutputBufferPolicy(value)) {
      return value;
    }
    return DemoExampleSettings.outputBufferPolicyAutomatic;
  }

  static String _validLocalAudioCodecOrDefault(String value) {
    if (DemoExampleSettings.isValidLocalAudioCodec(value)) {
      return value;
    }
    return DemoExampleSettings.localAudioCodecG711a;
  }

  static int _validLocalAudioSampleRateOrDefault(int value) {
    if (DemoExampleSettings.isValidLocalAudioSampleRate(value)) {
      return value;
    }
    return DemoExampleSettings.localAudioSampleRate16k;
  }

  static int _validLocalAudioStreamIdOrDefault(int value) {
    if (DemoExampleSettings.isValidLocalAudioStreamId(value)) {
      return value;
    }
    return DemoExampleSettings.defaultLocalAudioStreamId;
  }

  static int _validLocalAudioProcessingLevelOrDefault(int value) {
    if (DemoExampleSettings.isValidLocalAudioProcessingLevel(value)) {
      return value;
    }
    return 0;
  }
}
