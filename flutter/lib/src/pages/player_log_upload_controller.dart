import 'package:flutter/foundation.dart';

import '../demo_downlink_support.dart';
import '../demo_test_hooks.dart';

class DemoPlayerLogUploadController {
  DemoPlayerLogUploadController({
    required bool Function() isMounted,
    required DemoAutomationMarkerSink? Function() markerSink,
    required VoidCallback onChanged,
    required DemoLogResultDialog showResult,
    DemoLogUploader? uploader,
  })  : _isMounted = isMounted,
        _markerSink = markerSink,
        _onChanged = onChanged,
        _showResult = showResult,
        _uploader = uploader ?? DemoLogUploader();

  final bool Function() _isMounted;
  final DemoAutomationMarkerSink? Function() _markerSink;
  final VoidCallback _onChanged;
  final DemoLogResultDialog _showResult;
  final DemoLogUploader _uploader;

  bool uploading = false;

  Future<void> upload({required String remoteId}) async {
    if (uploading) {
      return;
    }
    uploading = true;
    _notifyChanged();

    try {
      final ({int code, String? logId})? result = await _uploader.upload(
        remoteId: remoteId,
        isActive: _isMounted,
        showResult: _showResult,
      );
      if (result != null && result.code == 0 && (result.logId?.isNotEmpty ?? false)) {
        _markerSink()?.passed('smoke_log_upload_completed', payload: <String, Object?>{
          'log_id': result.logId,
          'code': result.code,
        });
      } else if (_markerSink() != null) {
        _markerSink()?.failure(
          failureStage: 'log_upload',
          message: 'log upload failed',
          errorCode: result?.code,
        );
      }
    } finally {
      uploading = false;
      _notifyChanged();
    }
  }

  void reset({bool notify = true}) {
    final bool changed = uploading;
    uploading = false;
    if (changed && notify) {
      _notifyChanged();
    }
  }

  void _notifyChanged() {
    if (_isMounted()) {
      _onChanged();
    }
  }
}
