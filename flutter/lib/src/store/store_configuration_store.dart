import '../settings/example_preferences.dart';

final class DemoStoreConfigurationSnapshot {
  const DemoStoreConfigurationSnapshot({
    this.appId = '',
    this.endpoint = '',
    this.audioChannelId = '',
    this.videoChannelId = '',
  });

  final String appId;
  final String endpoint;
  final String audioChannelId;
  final String videoChannelId;
}

final class DemoStoreConfigurationStore {
  const DemoStoreConfigurationStore({DemoExamplePreferences preferences = const MethodChannelDemoExamplePreferences()})
    : _preferences = preferences;

  static const String _appIdKey = 'tirtc_example.store.app_id';
  static const String _endpointKey = 'tirtc_example.store.endpoint';
  static const String _audioChannelIdKey = 'tirtc_example.store.audio_channel_id';
  static const String _videoChannelIdKey = 'tirtc_example.store.video_channel_id';

  final DemoExamplePreferences _preferences;

  Future<DemoStoreConfigurationSnapshot> load() async {
    return DemoStoreConfigurationSnapshot(
      appId: await _preferences.getString(key: _appIdKey, defaultValue: ''),
      endpoint: await _preferences.getString(key: _endpointKey, defaultValue: ''),
      audioChannelId: await _preferences.getString(key: _audioChannelIdKey, defaultValue: ''),
      videoChannelId: await _preferences.getString(key: _videoChannelIdKey, defaultValue: ''),
    );
  }

  Future<void> save(DemoStoreConfigurationSnapshot snapshot) async {
    await Future.wait(<Future<void>>[
      _preferences.putString(key: _appIdKey, value: snapshot.appId),
      _preferences.putString(key: _endpointKey, value: snapshot.endpoint),
      _preferences.putString(key: _audioChannelIdKey, value: snapshot.audioChannelId),
      _preferences.putString(key: _videoChannelIdKey, value: snapshot.videoChannelId),
    ]);
  }
}
