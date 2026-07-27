import 'package:flutter/services.dart';

abstract interface class DemoExamplePreferences {
  Future<int> getInt({required String key, required int defaultValue});

  Future<void> putInt({required String key, required int value});

  Future<String> getString({required String key, required String defaultValue});

  Future<void> putString({required String key, required String value});
}

final class MethodChannelDemoExamplePreferences implements DemoExamplePreferences {
  const MethodChannelDemoExamplePreferences();

  static const MethodChannel _channel = MethodChannel('tirtc_example/preferences');

  @override
  Future<int> getInt({required String key, required int defaultValue}) async {
    final int? value = await _channel.invokeMethod<int>(
      'getPreferencesInt',
      <String, Object?>{
        'key': key,
        'defaultValue': defaultValue,
      },
    );
    return value ?? defaultValue;
  }

  @override
  Future<void> putInt({required String key, required int value}) async {
    await _channel.invokeMethod<void>(
      'putPreferencesInt',
      <String, Object?>{
        'key': key,
        'value': value,
      },
    );
  }

  @override
  Future<String> getString({required String key, required String defaultValue}) async {
    final String? value = await _channel.invokeMethod<String>(
      'getPreferencesString',
      <String, Object?>{
        'key': key,
        'defaultValue': defaultValue,
      },
    );
    return value ?? defaultValue;
  }

  @override
  Future<void> putString({required String key, required String value}) async {
    await _channel.invokeMethod<void>(
      'putPreferencesString',
      <String, Object?>{
        'key': key,
        'value': value,
      },
    );
  }
}
