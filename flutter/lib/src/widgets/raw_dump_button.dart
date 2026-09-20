import 'dart:async';

import 'package:flutter/material.dart';

enum DemoRawDumpUiState {
  idle,
  starting,
  capturing,
  finalizing,
  completed,
  uploading,
  uploadFailed,
  uploaded,
  captureFailed,
}

final class DemoRawDumpArchiveResult {
  const DemoRawDumpArchiveResult({required this.code, this.captureId, this.archiveSha256, this.archivePath});

  final int code;
  final String? captureId;
  final String? archiveSha256;
  final String? archivePath;

  bool get succeeded =>
      code == 0 &&
      (captureId?.isNotEmpty ?? false) &&
      (archiveSha256?.isNotEmpty ?? false) &&
      (archivePath?.isNotEmpty ?? false);
}

final class DemoRawDumpUploadResult {
  const DemoRawDumpUploadResult({required this.code, this.logId});

  final int code;
  final String? logId;

  bool get succeeded => code == 0 && (logId?.isNotEmpty ?? false);
}

typedef DemoRawDumpStarter = Future<int> Function();
typedef DemoRawDumpStopper = Future<DemoRawDumpArchiveResult> Function();
typedef DemoRawDumpUploader = Future<DemoRawDumpUploadResult> Function();

final class DemoRawDumpController {
  DemoRawDumpController({
    required DemoRawDumpStarter start,
    required DemoRawDumpStopper stop,
    required DemoRawDumpUploader upload,
    required VoidCallback onChanged,
  }) : _start = start,
       _stop = stop,
       _upload = upload,
       _onChanged = onChanged;

  final DemoRawDumpStarter _start;
  final DemoRawDumpStopper _stop;
  final DemoRawDumpUploader _upload;
  final VoidCallback _onChanged;
  DemoRawDumpUiState state = DemoRawDumpUiState.idle;
  bool archiveReady = false;
  int? errorCode;
  DemoRawDumpArchiveResult? archiveResult;
  DemoRawDumpUploadResult? uploadResult;
  Future<void>? _inFlight;
  bool _disposed = false;

  String get buttonLabel => switch (state) {
    DemoRawDumpUiState.idle || DemoRawDumpUiState.uploaded => '抓数据',
    DemoRawDumpUiState.starting => '准备中',
    DemoRawDumpUiState.capturing => '结束上传',
    DemoRawDumpUiState.finalizing => '打包中',
    DemoRawDumpUiState.completed => '上传数据',
    DemoRawDumpUiState.uploading => '上传中',
    DemoRawDumpUiState.uploadFailed => '重试上传',
    DemoRawDumpUiState.captureFailed => '重新抓取',
  };

  bool get enabled => switch (state) {
    DemoRawDumpUiState.starting || DemoRawDumpUiState.finalizing || DemoRawDumpUiState.uploading => false,
    _ => true,
  };

  String? get statusLabel {
    if (state == DemoRawDumpUiState.captureFailed && errorCode != null) return '采集失败 · $errorCode';
    if (state == DemoRawDumpUiState.uploadFailed) return '上传失败，数据已保留';
    return null;
  }

  Future<void> tap() => _joinOrRun(() async {
    switch (state) {
      case DemoRawDumpUiState.idle:
      case DemoRawDumpUiState.uploaded:
      case DemoRawDumpUiState.captureFailed:
        await _beginCapture();
        return;
      case DemoRawDumpUiState.capturing:
        await _finalizeCapture();
        if (state == DemoRawDumpUiState.completed) await _uploadArchive();
        return;
      case DemoRawDumpUiState.completed:
      case DemoRawDumpUiState.uploadFailed:
        await _uploadArchive();
        return;
      case DemoRawDumpUiState.starting:
      case DemoRawDumpUiState.finalizing:
      case DemoRawDumpUiState.uploading:
        return;
    }
  });

  Future<void> stopBeforeExistingUpload() async {
    await _inFlight;
    if (state == DemoRawDumpUiState.capturing) await _joinOrRun(_finalizeCapture);
  }

  Future<void> finalizeForLeave() async {
    await _inFlight;
    if (state == DemoRawDumpUiState.capturing) await _joinOrRun(_finalizeCapture);
  }

  void dispose() {
    _disposed = true;
  }

  Future<void> _joinOrRun(Future<void> Function() operation) {
    final Future<void>? existing = _inFlight;
    if (existing != null) return existing;
    final Future<void> future = operation();
    _inFlight = future;
    return future.whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
  }

  Future<void> _beginCapture() async {
    _setState(DemoRawDumpUiState.starting);
    archiveReady = false;
    archiveResult = null;
    uploadResult = null;
    errorCode = null;
    final int code = await _start();
    if (code != 0) {
      errorCode = code;
      _setState(DemoRawDumpUiState.captureFailed);
      return;
    }
    _setState(DemoRawDumpUiState.capturing);
  }

  Future<void> _finalizeCapture() async {
    if (state != DemoRawDumpUiState.capturing) return;
    _setState(DemoRawDumpUiState.finalizing);
    final DemoRawDumpArchiveResult result = await _stop();
    archiveResult = result;
    if (result.succeeded) {
      archiveReady = true;
      _setState(DemoRawDumpUiState.completed);
      return;
    }
    errorCode = result.code;
    _setState(DemoRawDumpUiState.captureFailed);
  }

  Future<void> _uploadArchive() async {
    if (!archiveReady) return;
    _setState(DemoRawDumpUiState.uploading);
    final DemoRawDumpUploadResult result = await _upload();
    uploadResult = result;
    _setState(result.succeeded ? DemoRawDumpUiState.uploaded : DemoRawDumpUiState.uploadFailed);
  }

  void _setState(DemoRawDumpUiState value) {
    state = value;
    _notify();
  }

  void _notify() {
    if (!_disposed) _onChanged();
  }
}

class DemoRawDumpButton extends StatelessWidget {
  const DemoRawDumpButton({super.key, required this.controller});

  final DemoRawDumpController controller;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: controller.buttonLabel,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          width: 56,
          height: 56,
          child: FilledButton(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              shape: const CircleBorder(),
            ),
            onPressed: controller.enabled ? () => unawaited(controller.tap()) : null,
            child: Text(controller.buttonLabel, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11)),
          ),
        ),
        if (controller.statusLabel case final String label) ...<Widget>[
          const SizedBox(height: 6),
          DecoratedBox(
            decoration: BoxDecoration(color: Colors.black.withAlpha(150), borderRadius: BorderRadius.circular(8)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 10)),
            ),
          ),
        ],
      ],
    ),
  );
}
