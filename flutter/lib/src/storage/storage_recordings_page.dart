import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tirtc_flutter/tirtc_flutter.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../app_theme.dart';
import '../demo_downlink_support.dart';
import '../demo_permissions.dart';
import '../demo_route_lifecycle.dart';
import '../demo_test_hooks.dart';
import '../demo_widget_keys.dart';
import '../pages/player_log_upload_controller.dart';
import '../widgets/downlink_center_loading.dart';
import '../widgets/notice_dialog.dart';
import '../widgets/player_page_widgets.dart';
import 'storage_recording_calendar.dart';

List<TiCloudStorageRecordingRange> _newestFirstRecordingRanges(Iterable<TiCloudStorageRecordingRange> ranges) {
  final List<TiCloudStorageRecordingRange> sorted = ranges.toList();
  sorted.sort((TiCloudStorageRecordingRange left, TiCloudStorageRecordingRange right) {
    final int startOrder = right.startTimeMs.compareTo(left.startTimeMs);
    return startOrder != 0 ? startOrder : right.endTimeMs.compareTo(left.endTimeMs);
  });
  return sorted;
}

final class DemoCloudStorageRecordingsPage extends StatefulWidget {
  const DemoCloudStorageRecordingsPage({
    super.key,
    required this.appId,
    required this.endpoint,
    required this.token,
    required this.audioChannelId,
    required this.videoChannelId,
  });

  final String appId;
  final String endpoint;
  final String token;
  final int audioChannelId;
  final int videoChannelId;

  @override
  State<DemoCloudStorageRecordingsPage> createState() => _DemoCloudStorageRecordingsPageState();
}

enum _LatestCloudStorageMedia { recording, snapshot }

final class _DemoCloudStorageRecordingsPageState extends State<DemoCloudStorageRecordingsPage>
    with WidgetsBindingObserver, ExampleRouteLifecycleState<DemoCloudStorageRecordingsPage> {
  final DemoDownlinkAudioSession _audioSession = DemoDownlinkAudioSession();
  TiCloudStorage? _cloudStorage;
  TiCloudStorageReplay? _replay;
  TiCloudStorageAudioOutput? _audioOutput;
  TiCloudStorageVideoOutput? _videoOutput;
  TiCloudStorageRecordingTask? _recordingTask;
  TiCloudStorageExportTask? _exportTask;
  TiCloudStorageRecordingRange? _exportingRange;
  TiCloudStorageRecordingFile? _latestRecording;
  TiCloudStorageSnapshotFile? _latestSnapshot;
  _LatestCloudStorageMedia? _latestMedia;
  List<TiCloudStorageRecordingRange> _recordings = <TiCloudStorageRecordingRange>[];
  List<TiCloudStorageRecordingDay> _recordingDays = <TiCloudStorageRecordingDay>[];
  TiCloudStorageRecordingRange? _selected;
  static const String _timeZoneId = 'Asia/Shanghai';
  late final tz.Location _timeZone;
  late tz.TZDateTime _selectedDate;
  late DateTime _visibleMonth;
  late final DemoPlayerLogUploadController _logUploadController;
  StateSetter? _sheetSetState;
  Future<void>? _queryFuture;
  Future<void>? _calendarQueryFuture;
  double? _seekPreview;
  int? _initCode;
  int? _lastCode;
  int? _queryCode;
  int? _calendarCode;
  int _calendarGeneration = 0;
  int _queryGeneration = 0;
  bool _querying = false;
  bool _queryQueued = false;
  bool _calendarQuerying = false;
  bool _sheetOpen = false;
  bool _paused = false;
  bool _pausedByLifecycle = false;
  bool _audioMuted = false;
  bool _mediaFileBusy = false;
  bool _cleaning = false;
  bool _uiActive = true;

  bool get _canUpdateUi => _uiActive && mounted;

  @override
  void initState() {
    super.initState();
    tz_data.initializeTimeZones();
    _timeZone = tz.getLocation(_timeZoneId);
    _selectedDate = tz.TZDateTime.now(_timeZone);
    _visibleMonth = DateTime.utc(_selectedDate.year, _selectedDate.month);
    _logUploadController = DemoPlayerLogUploadController(
      isMounted: () => _canUpdateUi,
      markerSink: () => DemoExampleSmokeHooks.current?.markerSink,
      onChanged: () {
        if (_canUpdateUi) setState(() {});
      },
      showResult: ({required String title, required String content}) {
        if (!_canUpdateUi) return Future<void>.value();
        return context.showNoticeDialog(title: title, content: content);
      },
    );
    unawaited(_initialize());
  }

  @override
  void onRouteInactive(String reason) {
    if (_paused || _replay == null || _selected == null) {
      return;
    }
    unawaited(_pauseForLifecycle());
  }

  @override
  void onRouteActive(String reason) {
    if (!_pausedByLifecycle || _replay == null) {
      return;
    }
    unawaited(_resumeFromLifecycle());
  }

  @override
  void dispose() {
    _uiActive = false;
    _logUploadController.reset(notify: false);
    unawaited(_cleanup());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TiCloudStorageRecordingRange? selected = _selected;
    return Scaffold(
      key: DemoWidgetKeys.cloudStorageRecordingsPage,
      backgroundColor: ExampleTheme.background,
      appBar: AppBar(
        title: const Text(
          '云录像',
          style: TextStyle(color: ExampleTheme.primary, fontSize: 14, fontWeight: FontWeight.w600),
        ),
        actions: <Widget>[
          IconButton(
            key: DemoWidgetKeys.cloudStorageCalendarButton,
            tooltip: '选择录像',
            onPressed: _initCode == 0 ? _showRecordingsSheet : null,
            icon: const Icon(Icons.calendar_month_outlined),
          ),
          PlayerLogUploadButton(
            buttonKey: DemoWidgetKeys.playerLogUploadButton,
            uploadingLogs: _logUploadController.uploading,
            onUploadLogs: () => _logUploadController.upload(remoteId: 'ti-cloud-storage'),
          ),
        ],
      ),
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: DownlinkVideoStage(
              videoView: _videoOutput?.view() ?? const SizedBox.shrink(),
              showStageOverlay: _showStageOverlay,
              stageStatusLabel: _stageStatusLabel,
              indicatorMode: _stageIndicatorMode,
            ),
          ),
          const Positioned.fill(child: DownlinkOverlayGradient()),
          if (_visibleErrorCode != null)
            Positioned(
              top: 12,
              left: 16,
              right: 16,
              child: SafeArea(
                bottom: false,
                child: _ErrorBanner(label: _initCode != 0 ? '初始化失败' : '操作失败', code: _visibleErrorCode!),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  const Spacer(),
                  if (selected != null) _buildSeekPanel(selected),
                  if (selected != null) const SizedBox(height: 12),
                  _buildControls(selected != null),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeekPanel(TiCloudStorageRecordingRange range) {
    final int maximum = range.endTimeMs - 1;
    final int current = (_seekPreview?.round() ?? _replay?.currentTimeMs ?? range.startTimeMs).clamp(
      range.startTimeMs,
      maximum,
    );
    return Container(
      constraints: const BoxConstraints(maxWidth: 620),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      decoration: ExampleTheme.videoPanelDecoration,
      child: Row(
        children: <Widget>[
          Text(_formatClock(current), style: const TextStyle(color: Colors.white70, fontSize: 12)),
          Expanded(
            child: Slider(
              key: DemoWidgetKeys.cloudStorageSeekSlider,
              min: range.startTimeMs.toDouble(),
              max: maximum.toDouble(),
              value: current.toDouble(),
              onChanged: (double value) => setState(() => _seekPreview = value),
              onChangeEnd: (double value) {
                final int code = _replay?.seek(value.round()) ?? kTiCloudStorageErrorNotStarted;
                setState(() {
                  _seekPreview = null;
                  _lastCode = code == 0 ? null : code;
                });
                if (code == 0) {
                  DemoExampleSmokeHooks.current?.markerSink.passed(
                    'ti-cloud-storage-smoke-seek-completed',
                    payload: <String, Object?>{'time_ms': value.round()},
                  );
                }
              },
            ),
          ),
          Text(_formatClock(range.endTimeMs), style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildControls(bool playing) {
    return Align(
      alignment: Alignment.bottomRight,
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          _CloudStorageMediaActionButton(
            buttonKey: DemoWidgetKeys.cloudStorageRecordingButton,
            enabled: playing && !_mediaFileBusy,
            active: _recordingTask != null,
            icon: _recordingTask == null ? Icons.fiber_manual_record : Icons.stop_circle_outlined,
            label: _recordingTask == null ? '录屏' : '结束录屏',
            onPressed: _toggleRecording,
          ),
          _CloudStorageMediaActionButton(
            buttonKey: DemoWidgetKeys.cloudStorageSnapshotButton,
            enabled: playing && !_mediaFileBusy,
            icon: Icons.camera_alt_outlined,
            label: '截图',
            onPressed: _snapshot,
          ),
          AudioOutputVolumeButton(
            key: DemoWidgetKeys.cloudStorageAudioVolumeButton,
            enabled: playing && _replay?.speed == TiCloudStorageReplaySpeed.x1,
            muted: _audioMuted || _replay?.speed != TiCloudStorageReplaySpeed.x1,
            onPressed: _toggleAudioOutputVolume,
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: ExampleTheme.videoPanelDecoration,
            child: DropdownButtonHideUnderline(
              child: DropdownButton<TiCloudStorageReplaySpeed>(
                key: DemoWidgetKeys.cloudStorageSpeedSelector,
                value: _replay?.speed ?? TiCloudStorageReplaySpeed.x1,
                dropdownColor: ExampleTheme.videoBackground,
                iconEnabledColor: Colors.white,
                style: const TextStyle(color: Colors.white),
                items:
                    TiCloudStorageReplaySpeed.values
                        .map(
                          (TiCloudStorageReplaySpeed speed) => DropdownMenuItem<TiCloudStorageReplaySpeed>(
                            value: speed,
                            child: Text(_replaySpeedLabel(speed)),
                          ),
                        )
                        .toList(),
                onChanged:
                    !playing
                        ? null
                        : (TiCloudStorageReplaySpeed? speed) {
                          if (speed == null) return;
                          unawaited(_setReplaySpeed(speed));
                        },
              ),
            ),
          ),
          FilledButton.icon(
            key: DemoWidgetKeys.cloudStoragePauseButton,
            onPressed: playing ? _togglePause : null,
            icon: Icon(_paused ? Icons.play_circle_fill_rounded : Icons.pause_circle_filled_rounded),
            label: Text(_paused ? '继续播放' : '暂停播放'),
          ),
        ],
      ),
    );
  }

  Future<void> _initialize() async {
    final int code = await TiCloudStorage.init(appId: widget.appId, endpoint: widget.endpoint);
    if (!_canUpdateUi) {
      if (code == 0) TiCloudStorage.shutdown();
      return;
    }
    setState(() {
      _initCode = code;
      if (code == 0) _cloudStorage = TiCloudStorage(token: widget.token);
    });
    if (code == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_canUpdateUi) unawaited(_showRecordingsSheet(query: true));
      });
    }
  }

  Future<void> _queryMonth() {
    final Future<void>? active = _calendarQueryFuture;
    if (active != null) return active;
    final Future<void> started = _runMonthQuery();
    _calendarQueryFuture = started;
    return started.whenComplete(() {
      if (identical(_calendarQueryFuture, started)) _calendarQueryFuture = null;
    });
  }

  Future<void> _runMonthQuery() async {
    final TiCloudStorage? cloudStorage = _cloudStorage;
    if (cloudStorage == null) return;
    final int generation = ++_calendarGeneration;
    final int lastDay = DateTime.utc(_visibleMonth.year, _visibleMonth.month + 1, 0).day;
    final String startDate = _dateText(_visibleMonth.year, _visibleMonth.month, 1);
    final String endDate = _dateText(_visibleMonth.year, _visibleMonth.month, lastDay);
    setState(() {
      _calendarQuerying = true;
      _calendarCode = null;
      _recordingDays = <TiCloudStorageRecordingDay>[];
    });
    _refreshSheet();
    final Resp<List<TiCloudStorageRecordingDay>> result = await cloudStorage.listRecordingDays(
      startDate: startDate,
      endDate: endDate,
      timeZoneId: _timeZoneId,
    );
    if (!_canUpdateUi || generation != _calendarGeneration) return;
    setState(() {
      _calendarQuerying = false;
      _calendarCode = result.code;
      _recordingDays = result.data ?? <TiCloudStorageRecordingDay>[];
    });
    _refreshSheet();
    DemoExampleSmokeHooks.current?.markerSink.passed(
      'ti-cloud-storage-smoke-recording-days-completed',
      payload: <String, Object?>{
        'code': result.success ? kTiCloudStorageErrorOk : result.code ?? kTiCloudStorageErrorIoFailed,
        'month': _monthText(_visibleMonth),
        'available_day_count': _recordingDays.where((TiCloudStorageRecordingDay day) => day.hasRecording).length,
      },
    );
  }

  Future<void> _queryMonthAndSelectedDay() async {
    await Future.wait<void>(<Future<void>>[_queryMonth(), _query()]);
  }

  Future<void> _query() {
    _queryGeneration += 1;
    _queryQueued = true;
    final Future<void>? active = _queryFuture;
    if (active != null) return active;
    final Future<void> started = _drainQueries();
    _queryFuture = started;
    return started.whenComplete(() {
      if (identical(_queryFuture, started)) _queryFuture = null;
    });
  }

  Future<void> _drainQueries() async {
    while (_queryQueued) {
      _queryQueued = false;
      await _runQuery(_queryGeneration);
    }
  }

  Future<void> _runQuery(int generation) async {
    final TiCloudStorage? cloudStorage = _cloudStorage;
    if (cloudStorage == null) return;
    final ({int start, int end}) bounds = _selectedDayBounds;
    setState(() {
      _querying = true;
      _queryCode = null;
      _recordings = <TiCloudStorageRecordingRange>[];
    });
    _refreshSheet();
    final Resp<List<TiCloudStorageRecordingRange>> result = await cloudStorage.listRecordings(
      startTimeMs: bounds.start,
      endTimeMs: bounds.end,
    );
    if (!_canUpdateUi || generation != _queryGeneration) return;
    setState(() {
      _querying = false;
      _recordings = _newestFirstRecordingRanges(result.data ?? <TiCloudStorageRecordingRange>[]);
      _queryCode = result.code;
    });
    _refreshSheet();
    DemoExampleSmokeHooks.current?.markerSink.passed(
      'ti-cloud-storage-smoke-query-completed',
      payload: <String, Object?>{
        'code': result.success ? kTiCloudStorageErrorOk : result.code ?? kTiCloudStorageErrorIoFailed,
        'recording_count': result.data?.length ?? 0,
        'start_time_ms': bounds.start,
        'end_time_ms': bounds.end,
      },
    );
  }

  Future<void> _play(TiCloudStorageRecordingRange range) async {
    await _stopActiveRecording(keepFile: true);
    if (!_canUpdateUi) return;

    TiCloudStorageReplay? replay = _replay;
    if (replay == null) {
      final TiCloudStorage? cloudStorage = _cloudStorage;
      if (cloudStorage == null) return;
      final int audioSessionCode = await _audioSession.retainIfNeeded();
      if (!_canUpdateUi) {
        _audioSession.releaseIfNeeded(reason: 'cloud_storage_page_unmounted');
        return;
      }
      if (audioSessionCode != kTiCloudStorageErrorOk) {
        setState(() => _lastCode = audioSessionCode);
        _reportSmokeFailure('ti-cloud-storage-audio-session', audioSessionCode);
        return;
      }
      replay = cloudStorage.createReplay();
      final TiCloudStorageAudioOutput audio = TiCloudStorageAudioOutput();
      final TiCloudStorageVideoOutput video = TiCloudStorageVideoOutput();
      replay.onTimeChanged = (_) {
        if (_canUpdateUi) setState(() {});
      };
      replay.onError = (int code) {
        if (!_canUpdateUi) return;
        setState(() => _lastCode = code);
        _reportSmokeFailure('ti-cloud-storage-replay', code);
      };
      replay.onCompleted = () {
        if (_canUpdateUi) {
          setState(() {});
          DemoExampleSmokeHooks.current?.markerSink.passed(
            'ti-cloud-storage-smoke-replay-completed',
            payload: <String, Object?>{'time_ms': replay?.currentTimeMs ?? 0},
          );
        }
      };
      video.onStateChanged = (TiCloudStorageVideoOutputState state) {
        if (!_canUpdateUi) return;
        setState(() {});
        DemoExampleSmokeHooks.current?.markerSink.passed(
          'ti-cloud-storage-smoke-video-state',
          payload: <String, Object?>{'state': state.name},
        );
        if (video.state == TiCloudStorageVideoOutputState.rendering) {
          final Size? size = video.renderSize;
          DemoExampleSmokeHooks.current?.markerSink.passed(
            'ti-cloud-storage-smoke-video-rendering',
            payload: <String, Object?>{'width': size?.width.round() ?? 0, 'height': size?.height.round() ?? 0},
          );
        }
      };
      video.onRenderSizeChanged = (Size size) {
        DemoExampleSmokeHooks.current?.markerSink.passed(
          'ti-cloud-storage-smoke-video-size',
          payload: <String, Object?>{'width': size.width.round(), 'height': size.height.round()},
        );
      };
      audio.onError = (int code) {
        if (_canUpdateUi) setState(() => _lastCode = code);
      };
      video.onError = (int code) {
        if (_canUpdateUi) setState(() => _lastCode = code);
      };
      int code = video.attach(replay: replay, channelId: widget.videoChannelId);
      final bool videoAttached = code == 0;
      if (code == 0) code = audio.attach(replay: replay, channelId: widget.audioChannelId);
      final bool audioAttached = code == 0;
      if (code != 0) {
        if (audioAttached) audio.detach();
        if (videoAttached) video.detach();
        audio.dispose();
        video.dispose();
        replay.dispose();
        _audioSession.releaseIfNeeded(reason: 'cloud_storage_output_attach_failed');
        setState(() => _lastCode = code);
        _reportSmokeFailure('ti-cloud-storage-play-attach', code);
        return;
      }
      _replay = replay;
      _audioOutput = audio;
      _videoOutput = video;
    }

    final int code = replay.play(startTimeMs: range.startTimeMs, endTimeMs: range.endTimeMs);
    if (!_canUpdateUi) return;
    setState(() {
      if (code == 0) {
        _selected = range;
        _paused = false;
        _pausedByLifecycle = false;
        _seekPreview = null;
      }
      _lastCode = code == 0 ? null : code;
    });
    if (code == 0) {
      DemoExampleSmokeHooks.current?.markerSink.passed(
        'ti-cloud-storage-smoke-play-started',
        payload: <String, Object?>{'start_time_ms': range.startTimeMs, 'end_time_ms': range.endTimeMs},
      );
    } else {
      _reportSmokeFailure('ti-cloud-storage-play', code);
    }
  }

  Future<void> _toggleRecording() async {
    if (_recordingTask != null) {
      setState(() => _mediaFileBusy = true);
      await _stopActiveRecording(keepFile: true);
      if (_canUpdateUi) setState(() => _mediaFileBusy = false);
      return;
    }
    final Resp<TiCloudStorageRecordingTask>? result = _replay?.startRecording(
      videoChannelId: widget.videoChannelId,
      audioChannelId: widget.audioChannelId,
    );
    if (!_canUpdateUi) return;
    setState(() {
      _recordingTask = result?.data;
      _lastCode = result?.code;
    });
    if (result?.success == true) {
      DemoExampleSmokeHooks.current?.markerSink.passed('ti-cloud-storage-smoke-recording-started');
    } else {
      _reportSmokeFailure('ti-cloud-storage-recording-start', result?.code);
    }
  }

  Future<int> _stopActiveRecording({required bool keepFile}) async {
    final TiCloudStorageRecordingTask? task = _recordingTask;
    if (task == null) return kTiCloudStorageErrorOk;
    _recordingTask = null;
    if (_canUpdateUi) setState(() {});
    final Resp<TiCloudStorageRecordingFile> result = await task.stop();
    final TiCloudStorageRecordingFile? file = result.data;
    if (!keepFile || !_canUpdateUi) {
      final int deleteCode = await file?.delete() ?? kTiCloudStorageErrorOk;
      return _firstError(result.code ?? kTiCloudStorageErrorOk, deleteCode);
    }
    if (file != null) await _replaceLatestRecording(file);
    if (!_canUpdateUi) return result.code ?? kTiCloudStorageErrorOk;
    setState(() => _lastCode = result.code);
    if (result.success && file != null) {
      DemoExampleSmokeHooks.current?.markerSink.passed(
        'ti-cloud-storage-smoke-recording-completed',
        payload: <String, Object?>{'duration_ms': file.duration.inMilliseconds},
      );
      await _saveLatestMediaToGallery();
    } else {
      _reportSmokeFailure('ti-cloud-storage-recording-stop', result.code);
    }
    return result.code ?? kTiCloudStorageErrorOk;
  }

  Future<void> _export(TiCloudStorageRecordingRange range) async {
    final TiCloudStorage? cloudStorage = _cloudStorage;
    if (cloudStorage == null || _exportTask != null || _exportingRange != null) return;
    setState(() => _exportingRange = range);
    _refreshSheet();
    final Resp<TiCloudStorageExportTask> started = cloudStorage.exportRecording(
      startTimeMs: range.startTimeMs,
      endTimeMs: range.endTimeMs,
      videoChannelId: widget.videoChannelId,
      audioChannelId: widget.audioChannelId,
      onProgress: (_) {
        if (_canUpdateUi) {
          setState(() {});
          _refreshSheet();
        }
      },
    );
    if (!_canUpdateUi) {
      await started.data?.stop();
      return;
    }
    setState(() {
      _exportTask = started.data;
      _exportingRange = started.success ? range : null;
      _lastCode = started.code;
    });
    if (started.success) {
      DemoExampleSmokeHooks.current?.markerSink.passed('ti-cloud-storage-smoke-export-started');
    } else {
      _reportSmokeFailure('ti-cloud-storage-export-start', started.code);
    }
    _refreshSheet();
    final Resp<TiCloudStorageRecordingFile>? result = await started.data?.result;
    if (result == null) {
      if (_canUpdateUi) {
        setState(() {
          _exportTask = null;
          _exportingRange = null;
        });
        _refreshSheet();
      }
      return;
    }
    final TiCloudStorageRecordingFile? file = result.data;
    if (!_canUpdateUi) {
      await file?.delete();
      return;
    }
    setState(() {
      _exportTask = null;
      _exportingRange = null;
      _lastCode = result.code;
    });
    _refreshSheet();
    if (file != null) await _replaceLatestRecording(file);
    if (result.success && file != null) {
      DemoExampleSmokeHooks.current?.markerSink.passed(
        'ti-cloud-storage-smoke-export-completed',
        payload: <String, Object?>{'duration_ms': file.duration.inMilliseconds},
      );
      await _saveLatestMediaToGallery();
    } else {
      _reportSmokeFailure('ti-cloud-storage-export', result.code);
    }
  }

  Future<void> _snapshot() async {
    setState(() => _mediaFileBusy = true);
    DemoExampleSmokeHooks.current?.markerSink.passed('ti-cloud-storage-smoke-snapshot-started');
    final Resp<TiCloudStorageSnapshotFile>? result = await _videoOutput?.takeSnapshot();
    if (!_canUpdateUi || result == null) {
      await result?.data?.delete();
      if (_canUpdateUi) setState(() => _mediaFileBusy = false);
      return;
    }
    if (result.data != null) await _replaceLatestSnapshot(result.data!);
    if (!_canUpdateUi) return;
    setState(() => _lastCode = result.code);
    if (result.success && result.data != null) {
      DemoExampleSmokeHooks.current?.markerSink.passed('ti-cloud-storage-smoke-snapshot-completed');
      await _saveLatestMediaToGallery();
    } else {
      _reportSmokeFailure('ti-cloud-storage-snapshot', result.code);
    }
    if (_canUpdateUi) setState(() => _mediaFileBusy = false);
  }

  Future<void> _saveLatestMediaToGallery() async {
    if (_latestMedia == null) return;
    if (!await const DemoExamplePermissions().requestGalleryWritePermissionIfNeeded()) {
      if (_canUpdateUi) {
        _showMessage('保存失败 · 未获得相册写入权限');
      }
      _reportSmokeFailure('ti-cloud-storage-gallery-permission', kTiCloudStorageErrorPermissionDenied);
      return;
    }
    final _LatestCloudStorageMedia kind = _latestMedia!;
    final String sourcePath =
        kind == _LatestCloudStorageMedia.recording ? _latestRecording!.path : _latestSnapshot!.path;
    final String fileName = demoGalleryFileName(kind == _LatestCloudStorageMedia.recording ? 'mp4' : 'jpg');
    final Resp<TiCloudStorageGalleryAsset> result =
        kind == _LatestCloudStorageMedia.recording
            ? await _latestRecording!.moveToGallery(fileName: fileName)
            : await _latestSnapshot!.moveToGallery(fileName: fileName);
    if (!_canUpdateUi) return;
    setState(() {
      _lastCode = result.code;
      if (result.success) {
        if (kind == _LatestCloudStorageMedia.recording) {
          _latestRecording = null;
        } else {
          _latestSnapshot = null;
        }
        _latestMedia = null;
      }
    });
    if (result.success && result.data != null) {
      DemoExampleSmokeHooks.current?.markerSink.passed(
        'ti-cloud-storage-smoke-gallery-saved',
        payload: <String, Object?>{
          'uri': result.data!.uri.toString(),
          'file_name': fileName,
          'source_deleted': !File(sourcePath).existsSync(),
        },
      );
    } else {
      _reportSmokeFailure('ti-cloud-storage-gallery', result.code);
    }
    _showMessage(result.success ? '已保存到系统相册' : '保存失败 · ${TiCloudStorage.errorToString(result.code ?? 0)}');
  }

  Future<void> _replaceLatestRecording(TiCloudStorageRecordingFile file) async {
    final TiCloudStorageRecordingFile? previous = _latestRecording;
    final TiCloudStorageSnapshotFile? other = _latestSnapshot;
    _latestRecording = file;
    _latestSnapshot = null;
    _latestMedia = _LatestCloudStorageMedia.recording;
    if (previous != null && previous.path != file.path) await previous.delete();
    await other?.delete();
  }

  Future<void> _replaceLatestSnapshot(TiCloudStorageSnapshotFile file) async {
    final TiCloudStorageSnapshotFile? previous = _latestSnapshot;
    final TiCloudStorageRecordingFile? other = _latestRecording;
    _latestSnapshot = file;
    _latestRecording = null;
    _latestMedia = _LatestCloudStorageMedia.snapshot;
    if (previous != null && previous.path != file.path) await previous.delete();
    await other?.delete();
  }

  Future<int> _retryReplayAction(int Function() action) async {
    final Stopwatch deadline = Stopwatch()..start();
    int code = action();
    while (code == kTiCloudStorageErrorInUse && deadline.elapsed < const Duration(seconds: 2)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      code = action();
    }
    return code;
  }

  Future<void> _pauseForLifecycle() async {
    final int code = await _retryReplayAction(() => _replay?.pause() ?? kTiCloudStorageErrorNotStarted);
    if (!_canUpdateUi) return;
    setState(() {
      if (code == 0) {
        _paused = true;
        _pausedByLifecycle = true;
        _lastCode = null;
      } else {
        _lastCode = code;
      }
    });
  }

  Future<void> _resumeFromLifecycle() async {
    final int code = await _retryReplayAction(() => _replay?.resume() ?? kTiCloudStorageErrorNotStarted);
    if (!_canUpdateUi) return;
    setState(() {
      _pausedByLifecycle = false;
      if (code == 0) {
        _paused = false;
        _lastCode = null;
      } else {
        _lastCode = code;
      }
    });
  }

  Future<void> _setReplaySpeed(TiCloudStorageReplaySpeed speed) async {
    final int code = _replay?.setSpeed(speed) ?? kTiCloudStorageErrorNotStarted;
    if (!_canUpdateUi) return;
    setState(() {
      _lastCode = code == 0 ? null : code;
    });
    if (code == 0) {
      DemoExampleSmokeHooks.current?.markerSink.passed(
        'ti-cloud-storage-smoke-speed-changed',
        payload: <String, Object?>{'speed': speed.name},
      );
    }
  }

  String _replaySpeedLabel(TiCloudStorageReplaySpeed speed) => switch (speed) {
    TiCloudStorageReplaySpeed.x0_125 => '1/8×',
    TiCloudStorageReplaySpeed.x0_25 => '1/4×',
    TiCloudStorageReplaySpeed.x0_5 => '1/2×',
    TiCloudStorageReplaySpeed.x1 => '1×',
    TiCloudStorageReplaySpeed.x2 => '2×',
    TiCloudStorageReplaySpeed.x4 => '4×',
    TiCloudStorageReplaySpeed.x8 => '8×',
  };

  void _togglePause() {
    unawaited(_togglePauseAsync());
  }

  Future<void> _togglePauseAsync() async {
    final bool resume = _paused;
    final int code = await _retryReplayAction(
      () =>
          resume
              ? _replay?.resume() ?? kTiCloudStorageErrorNotStarted
              : _replay?.pause() ?? kTiCloudStorageErrorNotStarted,
    );
    if (!_canUpdateUi) return;
    setState(() {
      if (code == 0) {
        _paused = !resume;
        _pausedByLifecycle = false;
      }
      _lastCode = code == 0 ? null : code;
    });
    if (code == 0) {
      DemoExampleSmokeHooks.current?.markerSink.passed(
        'ti-cloud-storage-smoke-pause-changed',
        payload: <String, Object?>{'paused': _paused},
      );
    }
  }

  void _toggleAudioOutputVolume() {
    final bool nextMuted = !_audioMuted;
    final int code = _audioOutput?.setVolume(nextMuted ? 0 : 100) ?? kTiCloudStorageErrorNotStarted;
    setState(() {
      if (code == 0) _audioMuted = nextMuted;
      _lastCode = code == 0 ? null : code;
    });
    if (code == 0) {
      DemoExampleSmokeHooks.current?.markerSink.passed(
        'ti-cloud-storage-smoke-audio-volume-changed',
        payload: <String, Object?>{'muted': nextMuted},
      );
    }
  }

  Future<void> _showRecordingsSheet({bool query = false}) async {
    if (_sheetOpen || !_canUpdateUi) return;
    _sheetOpen = true;
    final Future<void> sheet = showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder:
          (BuildContext sheetContext) => StatefulBuilder(
            builder: (BuildContext context, StateSetter setSheetState) {
              _sheetSetState = setSheetState;
              return _buildRecordingSheet(sheetContext);
            },
          ),
    );
    if (query) unawaited(_queryMonthAndSelectedDay());
    await sheet;
    _sheetSetState = null;
    _sheetOpen = false;
  }

  Widget _buildRecordingSheet(BuildContext sheetContext) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * 0.88,
        child: Column(
          children: <Widget>[
            ListTile(
              key: DemoWidgetKeys.cloudStorageDatePickerButton,
              leading: const Icon(Icons.calendar_today_outlined),
              title: const Text('选择录像日期'),
              subtitle: Text('自然日按 $_timeZoneId 计算 · ${_formatDate(_selectedDate)}'),
              trailing: IconButton(
                key: DemoWidgetKeys.cloudStorageQueryButton,
                tooltip: '刷新月份和当天录像',
                onPressed: _querying || _calendarQuerying ? null : _queryMonthAndSelectedDay,
                icon: const Icon(Icons.refresh),
              ),
            ),
            const Divider(height: 1),
            _buildCalendar(),
            const Divider(height: 1),
            Expanded(child: _buildRecordingSheetBody(sheetContext)),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendar() {
    final tz.TZDateTime today = tz.TZDateTime.now(_timeZone);
    return DemoCloudStorageRecordingCalendar(
      visibleMonth: _visibleMonth,
      selectedDate: _selectedDate,
      today: today,
      days: _recordingDays,
      loading: _calendarQuerying,
      errorCode: _calendarCode,
      onPreviousMonth: () => _changeMonth(-1),
      onNextMonth: () => _changeMonth(1),
      onRetry: _queryMonth,
      onSelectDay: _selectDate,
    );
  }

  Widget _buildRecordingSheetBody(BuildContext sheetContext) {
    if (_selectedDate.year != _visibleMonth.year || _selectedDate.month != _visibleMonth.month) {
      return const Center(child: Text('请选择有录像的日期'));
    }
    if (_querying) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_queryCode != null && _queryCode != 0) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('查询失败 · ${TiCloudStorage.errorToString(_queryCode!)} ($_queryCode)'),
            const SizedBox(height: 12),
            FilledButton(key: DemoWidgetKeys.cloudStorageQueryRetryButton, onPressed: _query, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_recordings.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text('当天没有可用录像'),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _query, child: const Text('重新查询')),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: _recordings.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (BuildContext context, int index) {
        final TiCloudStorageRecordingRange range = _recordings[index];
        return ListTile(
          key: ValueKey<String>('ti-cloud-storage-recording-${range.startTimeMs}-${range.endTimeMs}'),
          title: Text('${_formatClock(range.startTimeMs)} — ${_formatClock(range.endTimeMs)}'),
          subtitle: Text(_formatDuration(range.endTimeMs - range.startTimeMs)),
          onTap: () {
            Navigator.pop(sheetContext);
            unawaited(_play(range));
          },
          trailing: _exportAction(range),
        );
      },
    );
  }

  Widget _exportAction(TiCloudStorageRecordingRange range) {
    final bool exportingThis =
        _exportingRange != null &&
        _exportingRange!.startTimeMs == range.startTimeMs &&
        _exportingRange!.endTimeMs == range.endTimeMs;
    return OutlinedButton(
      key: ValueKey<String>('ti-cloud-storage-export-${range.startTimeMs}-${range.endTimeMs}'),
      onPressed: _exportingRange != null ? null : () => unawaited(_export(range)),
      style: OutlinedButton.styleFrom(
        foregroundColor: ExampleTheme.primary,
        side: BorderSide(color: ExampleTheme.primary.withAlpha(150)),
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      child:
          exportingThis
              ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, value: _exportTask?.progress),
              )
              : const Text('下载'),
    );
  }

  void _changeMonth(int amount) {
    setState(() {
      _visibleMonth = DateTime.utc(_visibleMonth.year, _visibleMonth.month + amount);
      _recordings = <TiCloudStorageRecordingRange>[];
      _queryCode = null;
    });
    _refreshSheet();
    unawaited(_queryMonth());
  }

  void _selectDate(int day) {
    setState(() {
      _selectedDate = tz.TZDateTime(_timeZone, _visibleMonth.year, _visibleMonth.month, day);
      _recordings = <TiCloudStorageRecordingRange>[];
      _queryCode = null;
    });
    _refreshSheet();
    unawaited(_query());
  }

  Future<void> _cleanup() async {
    if (_cleaning) return;
    _cleaning = true;
    int cleanupCode = await _stopActiveRecording(keepFile: false);
    final Resp<TiCloudStorageRecordingFile>? exportResult = await _exportTask?.stop();
    cleanupCode = _firstError(cleanupCode, exportResult?.code ?? kTiCloudStorageErrorOk);
    cleanupCode = _firstError(cleanupCode, await exportResult?.data?.delete() ?? kTiCloudStorageErrorOk);
    _exportTask = null;
    _exportingRange = null;
    await _queryFuture;
    await _calendarQueryFuture;
    cleanupCode = _firstError(cleanupCode, await _releasePlayback());
    cleanupCode = _firstError(cleanupCode, await _latestRecording?.delete() ?? kTiCloudStorageErrorOk);
    cleanupCode = _firstError(cleanupCode, await _latestSnapshot?.delete() ?? kTiCloudStorageErrorOk);
    _latestRecording = null;
    _latestSnapshot = null;
    _latestMedia = null;
    cleanupCode = _firstError(cleanupCode, await _disposeAfterDeferredCallbacks(_cloudStorage?.dispose));
    _cloudStorage = null;
    if (_initCode == 0) cleanupCode = _firstError(cleanupCode, TiCloudStorage.shutdown());
    final DemoAutomationMarkerSink? markerSink = DemoExampleSmokeHooks.current?.markerSink;
    if (cleanupCode == kTiCloudStorageErrorOk) {
      markerSink?.passed('ti-cloud-storage-smoke-cleanup-completed');
    } else {
      markerSink?.failure(
        failureStage: 'ti-cloud-storage-cleanup',
        message: TiCloudStorage.errorToString(cleanupCode),
        errorCode: cleanupCode,
      );
    }
  }

  Future<int> _releasePlayback() async {
    final TiCloudStorageReplay? replay = _replay;
    final TiCloudStorageAudioOutput? audio = _audioOutput;
    final TiCloudStorageVideoOutput? video = _videoOutput;
    void clearPlayback() {
      _selected = null;
      _audioOutput = null;
      _videoOutput = null;
      _replay = null;
      _paused = false;
      _pausedByLifecycle = false;
    }

    if (_canUpdateUi) {
      setState(clearPlayback);
      await WidgetsBinding.instance.endOfFrame;
    } else {
      clearPlayback();
      await Future<void>.delayed(Duration.zero);
    }
    int cleanupCode = replay?.stop() ?? kTiCloudStorageErrorOk;
    cleanupCode = _firstError(cleanupCode, audio?.detach() ?? kTiCloudStorageErrorOk);
    cleanupCode = _firstError(cleanupCode, video?.detach() ?? kTiCloudStorageErrorOk);
    cleanupCode = _firstError(cleanupCode, await _disposeAfterDeferredCallbacks(audio?.dispose));
    final int videoCode = await _disposeAfterDeferredCallbacks(video?.dispose);
    if (videoCode != 0 && _canUpdateUi) setState(() => _lastCode = videoCode);
    cleanupCode = _firstError(cleanupCode, videoCode);
    cleanupCode = _firstError(cleanupCode, await _disposeAfterDeferredCallbacks(replay?.dispose));
    _audioSession.releaseIfNeeded(reason: 'cloud_storage_playback_released');
    return cleanupCode;
  }

  Future<int> _disposeAfterDeferredCallbacks(int Function()? dispose) async {
    if (dispose == null) return kTiCloudStorageErrorOk;
    final Stopwatch deadline = Stopwatch()..start();
    int code = dispose();
    while (code == kTiCloudStorageErrorInUse && deadline.elapsed < const Duration(seconds: 5)) {
      // Runtime callback tasks arrive through NativeCallable.listener. A timer turn lets the Dart
      // event queue complete each accepted task before the next checked destruction attempt.
      await Future<void>.delayed(const Duration(milliseconds: 10));
      code = dispose();
    }
    return code;
  }

  void _refreshSheet() {
    final StateSetter? setSheetState = _sheetSetState;
    if (setSheetState != null) setSheetState(() {});
  }

  void _showMessage(String message) {
    if (!_canUpdateUi) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _reportSmokeFailure(String stage, int? code) {
    final int errorCode = code ?? kTiCloudStorageErrorIoFailed;
    DemoExampleSmokeHooks.current?.markerSink.failure(
      failureStage: stage,
      message: TiCloudStorage.errorToString(errorCode),
      errorCode: errorCode,
    );
  }

  ({int start, int end}) get _selectedDayBounds {
    final tz.TZDateTime start = tz.TZDateTime(_timeZone, _selectedDate.year, _selectedDate.month, _selectedDate.day);
    final tz.TZDateTime end = tz.TZDateTime(_timeZone, _selectedDate.year, _selectedDate.month, _selectedDate.day + 1);
    return (start: start.millisecondsSinceEpoch, end: end.millisecondsSinceEpoch);
  }

  int? get _visibleErrorCode {
    if (_initCode != null && _initCode != 0) return _initCode;
    if (_lastCode != null && _lastCode != 0) return _lastCode;
    return null;
  }

  bool get _showStageOverlay {
    final TiCloudStorageVideoOutputState? state = _videoOutput?.state;
    return _selected == null ||
        state == TiCloudStorageVideoOutputState.idle ||
        state == TiCloudStorageVideoOutputState.buffering ||
        state == TiCloudStorageVideoOutputState.paused ||
        state == TiCloudStorageVideoOutputState.completed ||
        state == TiCloudStorageVideoOutputState.failed;
  }

  String get _stageStatusLabel {
    if (_selected == null) return _initCode == null ? '加载中' : '请选择录像';
    switch (_videoOutput?.state) {
      case TiCloudStorageVideoOutputState.buffering:
        return '缓冲中';
      case TiCloudStorageVideoOutputState.paused:
        return '已暂停';
      case TiCloudStorageVideoOutputState.completed:
        return '播放完成';
      case TiCloudStorageVideoOutputState.failed:
        return '播放失败';
      case TiCloudStorageVideoOutputState.idle:
      case TiCloudStorageVideoOutputState.rendering:
      case null:
        return '加载中';
    }
  }

  DownlinkCenterIndicatorMode get _stageIndicatorMode {
    final TiCloudStorageVideoOutputState? state = _videoOutput?.state;
    if (state == TiCloudStorageVideoOutputState.failed || (_initCode != null && _initCode != 0)) {
      return DownlinkCenterIndicatorMode.error;
    }
    return state == TiCloudStorageVideoOutputState.buffering || (_initCode == null && _selected == null)
        ? DownlinkCenterIndicatorMode.loading
        : DownlinkCenterIndicatorMode.running;
  }

  static String _formatDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  static String _dateText(int year, int month, int day) =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

  static String _monthText(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}';

  String _formatClock(int milliseconds) {
    final tz.TZDateTime value = tz.TZDateTime.fromMillisecondsSinceEpoch(_timeZone, milliseconds);
    return '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}:${value.second.toString().padLeft(2, '0')}';
  }

  static String _formatDuration(int milliseconds) {
    final Duration value = Duration(milliseconds: milliseconds);
    final int minutes = value.inMinutes;
    final int seconds = value.inSeconds.remainder(60);
    return '时长 ${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  static int _firstError(int current, int next) => current == kTiCloudStorageErrorOk ? next : current;
}

final class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.label, required this.code});

  final String label;
  final int code;

  @override
  Widget build(BuildContext context) => MaterialBanner(
    backgroundColor: ExampleTheme.surface.withAlpha(235),
    content: Text('$label：${TiCloudStorage.errorToString(code)} ($code)'),
    actions: const <Widget>[SizedBox.shrink()],
  );
}

final class _CloudStorageMediaActionButton extends StatelessWidget {
  const _CloudStorageMediaActionButton({
    required this.buttonKey,
    required this.enabled,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.active = false,
  });

  final Key buttonKey;
  final bool enabled;
  final bool active;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      key: buttonKey,
      onPressed: enabled ? onPressed : null,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        backgroundColor: active ? Colors.orangeAccent.shade700 : ExampleTheme.surface,
        foregroundColor: active ? Colors.white : ExampleTheme.primary,
      ),
      icon: Icon(icon),
      label: Text(label),
    );
  }
}
