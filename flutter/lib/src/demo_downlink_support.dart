import 'dart:async';
import 'dart:io';

import 'package:tirtc_flutter/tirtc_flutter.dart';

typedef DemoLogResultDialog = Future<void> Function({
  required String title,
  required String content,
});

final class DemoDownlinkAudioSession {
  bool _retained = false;

  Future<int> retainIfNeeded() async {
    if (!Platform.isIOS || _retained) {
      return 0;
    }

    TiRtcLogging.i('flutter_example', 'downlink_audio_session_retain_requested');
    final int code = await TiRtcHostPlatformApi.instance.retainOutputAudioSession();
    if (code == 0) {
      _retained = true;
      TiRtcLogging.i('flutter_example', 'downlink_audio_session_retain_succeeded');
      return 0;
    }

    TiRtcLogging.w(
      'flutter_example',
      'downlink_audio_session_retain_failed code=$code',
    );
    return code;
  }

  void releaseIfNeeded({required String reason}) {
    if (!Platform.isIOS || !_retained) {
      return;
    }

    _retained = false;
    TiRtcLogging.i(
      'flutter_example',
      'downlink_audio_session_release_requested reason=$reason',
    );
    unawaited(() async {
      final int code = await TiRtcHostPlatformApi.instance.releaseOutputAudioSession();
      if (code == 0) {
        TiRtcLogging.i('flutter_example', 'downlink_audio_session_release_succeeded reason=$reason');
        return;
      }
      TiRtcLogging.w(
        'flutter_example',
        'downlink_audio_session_release_failed reason=$reason code=$code',
      );
    }());
  }
}

final class DemoLogUploader {
  Future<({int code, String? logId})?> upload({
    required String remoteId,
    required bool Function() isActive,
    required DemoLogResultDialog showResult,
  }) async {
    TiRtcLogging.i(
      'flutter_example',
      'log_upload_requested remoteId=$remoteId',
    );

    try {
      final ({int code, String? logId}) result = await TiRtcLogging.upload();
      if (!isActive()) {
        return result;
      }
      if (result.code == 0) {
        final String message =
            (result.logId?.isNotEmpty ?? false) ? '日志 ID: ${result.logId}\n将此编号提供给开发人员排查' : '日志上传成功。';
        TiRtcLogging.i(
          'flutter_example',
          'log_upload_succeeded logId=${result.logId ?? ''}',
        );
        unawaited(showResult(
          title: '日志上传成功',
          content: message,
        ));
        return result;
      }

      TiRtcLogging.i(
        'flutter_example',
        'log_upload_failed code=${result.code}',
      );
      unawaited(showResult(
        title: '日志上传失败',
        content: 'code ${result.code}。',
      ));
      return result;
    } catch (error) {
      TiRtcLogging.w(
        'flutter_example',
        'log_upload_failed unexpected=$error',
      );
      if (!isActive()) {
        return null;
      }
      unawaited(showResult(
        title: '日志上传失败',
        content: '请重试。',
      ));
      return null;
    }
  }
}
