import 'dart:io';

import 'package:flutter/services.dart';
import 'package:tirtc_flutter/tirtc_flutter.dart';

final class DemoExamplePermissions {
  const DemoExamplePermissions();

  static const MethodChannel _channel = MethodChannel('tirtc_example/permissions');

  Future<bool> checkMicrophonePermission() => _checkPermission('checkMicrophonePermission', 'microphone');

  Future<bool> requestMicrophonePermission() => _requestPermission('requestMicrophonePermission', 'microphone');

  Future<bool> _checkPermission(String method, String name) async {
    if (!_microphonePermissionSupported) {
      return true;
    }
    try {
      return await _channel.invokeMethod<bool>(method) ?? false;
    } on PlatformException catch (error) {
      TiRtcLogging.w(
        'flutter_example',
        '${name}_permission_check_failed code=${error.code} message=${error.message ?? ''}',
      );
      return false;
    }
  }

  Future<bool> _requestPermission(String method, String name) async {
    if (!_microphonePermissionSupported) {
      return true;
    }
    try {
      return await _channel.invokeMethod<bool>(method) ?? false;
    } on PlatformException catch (error) {
      TiRtcLogging.w(
        'flutter_example',
        '${name}_permission_request_failed code=${error.code} message=${error.message ?? ''}',
      );
      return false;
    }
  }

  Future<bool> requestLocalNetworkPermissionIfNeeded() async {
    if (!Platform.isIOS) {
      return true;
    }
    try {
      return await _channel.invokeMethod<bool>('requestLocalNetworkPermission') ?? false;
    } on PlatformException catch (error) {
      TiRtcLogging.w(
        'flutter_example',
        'ios_local_network_permission_request_failed code=${error.code} message=${error.message ?? ''}',
      );
      return false;
    }
  }

  bool get _microphonePermissionSupported =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS || Platform.operatingSystem == 'ohos';
}
