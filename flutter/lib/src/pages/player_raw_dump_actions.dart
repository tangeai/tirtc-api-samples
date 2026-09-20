part of 'player_page.dart';

extension _DemoPlayerRawDumpActions on _DemoPlayerPageState {
  void _initializeRawDumpController() {
    _rawDumpController = DemoRawDumpController(
      start: () async {
        final Resp<TiRawDump> result = await _session.startRawDump(
          audioStreamId: widget.configuration.audioStreamId,
          videoStreamIds: widget.configuration.videoStreamIds,
          localAudioStreamId: widget.configuration.settings.localAudioStreamId,
        );
        return result.success ? 0 : result.code ?? 6114;
      },
      stop: () async {
        final Resp<TiRawDumpArchive> result = await _session.stopRawDump();
        final TiRawDumpArchive? archive = result.data;
        return DemoRawDumpArchiveResult(
          code: result.success ? 0 : result.code ?? 6114,
          captureId: archive?.captureId,
          archiveSha256: archive?.sha256,
          archivePath: archive?.path,
        );
      },
      upload: _uploadLogsForRawDump,
      onChanged: _notifyRawDumpChanged,
    );
  }

  Future<({int code, String? logId})?> _uploadLogs() async {
    await _rawDumpController.stopBeforeExistingUpload();
    return _logUploadController.upload(remoteId: widget.configuration.remoteId);
  }

  Future<DemoRawDumpUploadResult> _uploadLogsForRawDump() async {
    final ({int code, String? logId})? result = await _logUploadController.upload(
      remoteId: widget.configuration.remoteId,
    );
    return DemoRawDumpUploadResult(code: result?.code ?? 6114, logId: result?.logId);
  }
}
