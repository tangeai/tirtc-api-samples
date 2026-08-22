part of 'player_page.dart';

extension _DemoPlayerMediaFileActions on _DemoPlayerPageState {
  Future<void> _toggleRecording() async {
    _setMediaFileBusy(true);
    if (_session.isRecording) {
      final Resp<TiRtcRecordingFile> result = await _session.stopRecording();
      if (result.success) {
        widget.smokeMarkerSink?.passed(
          'smoke_recording_stopped',
          payload: <String, Object?>{
            'file_path': result.data!.path,
            'duration_ms': result.data!.duration.inMilliseconds,
          },
        );
      } else {
        _smokeFail(failureStage: 'media_recording_stop', message: 'recording stop failed', errorCode: result.code);
      }
      _showPlayerSnack(
        result.success ? '录像已保存 · ${result.data!.path}' : '停止保存失败 · ${TiRtc.formatError(result.code ?? 0)}',
      );
    } else {
      final Resp<TiRtcRecordingTask> result = _session.startRecording(
        videoStreamId: widget.configuration.videoStreamId,
        audioStreamId: widget.configuration.audioStreamId,
      );
      if (result.success) {
        widget.smokeMarkerSink?.passed('smoke_recording_started');
      } else {
        _smokeFail(failureStage: 'media_recording_start', message: 'recording start failed', errorCode: result.code);
      }
      _showPlayerSnack(result.success ? '已开始本地保存' : '开始保存失败 · ${TiRtc.formatError(result.code ?? 0)}');
    }
    _setMediaFileBusy(false);
  }

  Future<void> _takeSnapshot() async {
    _setMediaFileBusy(true);
    final Resp<TiRtcSnapshotFile> result = await _session.takeSnapshot();
    if (result.success) {
      widget.smokeMarkerSink?.passed(
        'smoke_snapshot_saved',
        payload: <String, Object?>{'file_path': result.data!.path},
      );
    } else {
      _smokeFail(failureStage: 'media_snapshot', message: 'snapshot failed', errorCode: result.code);
    }
    _showPlayerSnack(result.success ? '截图已保存 · ${result.data?.path}' : '截图失败 · ${TiRtc.formatError(result.code ?? 0)}');
    _setMediaFileBusy(false);
  }

  Future<void> _moveLatestMediaToGallery() async {
    _setMediaFileBusy(true);
    if (!await const DemoExamplePermissions().requestGalleryWritePermissionIfNeeded()) {
      _showPlayerSnack('保存失败 · 未获得相册写入权限');
      _setMediaFileBusy(false);
      return;
    }
    final String? sourcePath = _session.latestMediaPath;
    final String? mediaType = _session.latestMediaType;
    final String? fileName = switch (mediaType) {
      'video' => demoGalleryFileName('mp4'),
      'image' => demoGalleryFileName('jpg'),
      _ => null,
    };
    final Resp<TiRtcGalleryAsset> result = await _session.moveLatestMediaToGallery(fileName: fileName);
    if (result.success) {
      final String marker = mediaType == 'video' ? 'smoke_recording_gallery_saved' : 'smoke_snapshot_gallery_saved';
      widget.smokeMarkerSink?.passed(
        marker,
        payload: <String, Object?>{
          'uri': result.data!.uri.toString(),
          'source_path': sourcePath,
          'media_type': mediaType,
          'file_name': fileName,
        },
      );
    } else {
      _smokeFail(failureStage: 'media_gallery', message: 'media gallery move failed', errorCode: result.code);
    }
    _showPlayerSnack(result.success ? '已保存到系统相册' : '保存失败 · ${TiRtc.formatError(result.code ?? 0)}');
    _setMediaFileBusy(false);
  }
}
