import '../demo_configuration.dart';
import '../settings/example_preferences.dart';

final class DemoCloudStorageConfigurationSnapshot {
  const DemoCloudStorageConfigurationSnapshot({
    this.appId = '',
    this.endpoint = '',
    this.audioChannelId = '',
    this.videoChannelIds = '',
  });

  final String appId;
  final String endpoint;
  final String audioChannelId;
  final String videoChannelIds;
}

final class DemoCloudStorageConfigurationPersistence {
  const DemoCloudStorageConfigurationPersistence({
    DemoExamplePreferences preferences = const MethodChannelDemoExamplePreferences(),
  }) : _preferences = preferences;

  static const String _appIdKey = 'tirtc_example.cloud_storage.app_id';
  static const String _endpointKey = 'tirtc_example.cloud_storage.endpoint';
  static const String _audioChannelIdKey = 'tirtc_example.cloud_storage.audio_channel_id';
  static const String _videoChannelIdsKey = 'tirtc_example.cloud_storage.video_channel_ids';

  final DemoExamplePreferences _preferences;

  Future<DemoCloudStorageConfigurationSnapshot> load() async {
    return DemoCloudStorageConfigurationSnapshot(
      appId: await _preferences.getString(key: _appIdKey, defaultValue: ''),
      endpoint: await _preferences.getString(key: _endpointKey, defaultValue: ''),
      audioChannelId: await _preferences.getString(
        key: _audioChannelIdKey,
        defaultValue: DemoDownlinkConfiguration.defaultAudioStreamId.toString(),
      ),
      videoChannelIds: await _preferences.getString(
        key: _videoChannelIdsKey,
        defaultValue: DemoDownlinkConfiguration.defaultVideoStreamId.toString(),
      ),
    );
  }

  Future<void> save(DemoCloudStorageConfigurationSnapshot snapshot) async {
    await Future.wait(<Future<void>>[
      _preferences.putString(key: _appIdKey, value: snapshot.appId),
      _preferences.putString(key: _endpointKey, value: snapshot.endpoint),
      _preferences.putString(key: _audioChannelIdKey, value: snapshot.audioChannelId),
      _preferences.putString(key: _videoChannelIdsKey, value: snapshot.videoChannelIds),
    ]);
  }
}
