part of 'player_page.dart';

extension _DemoPlayerMediaFileActions on _DemoPlayerPageState {
  Future<void> _toggleRecording() => _mediaOperationBarrier.run(_performToggleRecording);

  Future<void> _performToggleRecording() async {
    _setMediaFileBusy(true);
    if (_session.isRecording) {
      final Resp<TiRtcRecordingFile> result = await _session.stopRecording();
      if (result.success) {
        _latestMediaVideoStreamId = _recordingVideoStreamId;
        widget.smokeMarkerSink?.passed(
          'smoke_recording_stopped',
          payload: <String, Object?>{
            'file_path': result.data!.path,
            'duration_ms': result.data!.duration.inMilliseconds,
            'video_stream_id': _recordingVideoStreamId,
          },
        );
        await _saveLatestMediaToGallery();
      } else {
        _smokeFail(failureStage: 'media_recording_stop', message: 'recording stop failed', errorCode: result.code);
        _showPlayerSnack('停止保存失败 · ${TiRtc.formatError(result.code ?? 0)}');
      }
      _recordingVideoStreamId = null;
    } else {
      final int? targetStreamId = _selectedVideoStreamId;
      if (targetStreamId == null) {
        _showPlayerSnack('请先选择视频流');
        _setMediaFileBusy(false);
        return;
      }
      final Resp<TiRtcRecordingTask> result = _session.startRecording(
        videoStreamId: targetStreamId,
        audioStreamId: widget.configuration.audioStreamId,
      );
      if (result.success) {
        _recordingVideoStreamId = targetStreamId;
        widget.smokeMarkerSink?.passed('smoke_recording_started');
      } else {
        _smokeFail(failureStage: 'media_recording_start', message: 'recording start failed', errorCode: result.code);
      }
      _showPlayerSnack(result.success ? '已开始本地保存' : '开始保存失败 · ${TiRtc.formatError(result.code ?? 0)}');
    }
    _setMediaFileBusy(false);
  }

  Future<void> _takeSnapshot() => _mediaOperationBarrier.run(_performTakeSnapshot);

  Future<void> _performTakeSnapshot() async {
    final int? targetStreamId = _selectedVideoStreamId;
    if (targetStreamId == null) return;
    _setMediaFileBusy(true);
    final Resp<TiRtcSnapshotFile> result = await _session.takeSnapshot(videoStreamId: targetStreamId);
    if (result.success) {
      _latestMediaVideoStreamId = targetStreamId;
      widget.smokeMarkerSink?.passed(
        'smoke_snapshot_saved',
        payload: <String, Object?>{'file_path': result.data!.path, 'video_stream_id': targetStreamId},
      );
      await _saveLatestMediaToGallery();
    } else {
      _smokeFail(failureStage: 'media_snapshot', message: 'snapshot failed', errorCode: result.code);
      _showPlayerSnack('截图失败 · ${TiRtc.formatError(result.code ?? 0)}');
    }
    _setMediaFileBusy(false);
  }

  Future<void> _moveLatestMediaToGallery() => _mediaOperationBarrier.run(_performMoveLatestMediaToGallery);

  Future<void> _performMoveLatestMediaToGallery() async {
    _setMediaFileBusy(true);
    await _saveLatestMediaToGallery();
    _setMediaFileBusy(false);
  }

  Future<bool> _saveLatestMediaToGallery() async {
    if (!await const DemoExamplePermissions().requestGalleryWritePermissionIfNeeded()) {
      _showPlayerSnack('保存失败 · 未获得相册写入权限');
      _smokeFail(failureStage: 'media_gallery_permission', message: 'gallery write permission denied');
      return false;
    }
    final String? sourcePath = _session.latestMediaPath;
    final String? mediaType = _session.latestMediaType;
    final String? fileName = switch (mediaType) {
      'video' => demoGalleryFileName('mp4', targetId: _latestMediaVideoStreamId),
      'image' => demoGalleryFileName('jpg', targetId: _latestMediaVideoStreamId),
      _ => null,
    };
    final Resp<TiRtcGalleryAsset> result = await _session.moveLatestMediaToGallery(fileName: fileName);
    if (result.success) {
      _latestMediaVideoStreamId = null;
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
    return result.success;
  }
}
