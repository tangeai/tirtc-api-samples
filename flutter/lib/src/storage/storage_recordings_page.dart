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
import '../widgets/cloud_storage_playback_console.dart';
import '../widgets/notice_dialog.dart';
import '../widgets/player_page_widgets.dart';
import '../widgets/raw_dump_button.dart';
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
    required this.videoChannelIds,
  });

  final String appId;
  final String endpoint;
  final String token;
  final int? audioChannelId;
  final List<int> videoChannelIds;

  @override
  State<DemoCloudStorageRecordingsPage> createState() => _DemoCloudStorageRecordingsPageState();
}

enum _LatestCloudStorageMedia { recording, snapshot }

final class _DemoCloudStorageRecordingsPageState extends State<DemoCloudStorageRecordingsPage>
    with WidgetsBindingObserver, ExampleRouteLifecycleState<DemoCloudStorageRecordingsPage> {
  final DemoDownlinkAudioSession _audioSession = DemoDownlinkAudioSession();
  final FocusNode _recordingsButtonFocusNode = FocusNode(debugLabel: 'cloud-recordings-button');
  TiCloudStorage? _cloudStorage;
  TiCloudStorageReplay? _replay;
  TiRawDump? _rawDump;
  TiCloudStorageAudioOutput? _audioOutput;
  final Map<int, TiCloudStorageVideoOutput> _videoOutputs = <int, TiCloudStorageVideoOutput>{};
  final Map<int, TiCloudStorageVideoOutputState> _videoStates = <int, TiCloudStorageVideoOutputState>{};
  final Set<int> _attachedVideoChannelIds = <int>{};
  final Set<int> _unavailableVideoChannelIds = <int>{};
  TiCloudStorageAudioOutputState _audioState = TiCloudStorageAudioOutputState.idle;
  bool _completionReported = false;
  int? _selectedVideoChannelId;
  int? _maximizedVideoChannelId;
  int? _recordingVideoChannelId;
  int? _exportingVideoChannelId;
  TiCloudStorageRecordingTask? _recordingTask;
  TiCloudStorageExportTask? _exportTask;
  TiCloudStorageRecordingRange? _exportingRange;
  TiCloudStorageRecordingFile? _latestRecording;
  TiCloudStorageSnapshotFile? _latestSnapshot;
  _LatestCloudStorageMedia? _latestMedia;
  int? _latestMediaVideoChannelId;
  List<TiCloudStorageRecordingRange> _recordings = <TiCloudStorageRecordingRange>[];
  List<TiCloudStorageRecordingDay> _recordingDays = <TiCloudStorageRecordingDay>[];
  TiCloudStorageRecordingRange? _selected;
  static const String _timeZoneId = 'Asia/Shanghai';
  late final tz.Location _timeZone;
  late tz.TZDateTime _selectedDate;
  late DateTime _visibleMonth;
  late final DemoPlayerLogUploadController _logUploadController;
  late final DemoRawDumpController _rawDumpController;
  Future<void>? _rawDumpFinalization;
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
    _selectedVideoChannelId = widget.videoChannelIds.firstOrNull;
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
    _rawDumpController = DemoRawDumpController(
      start: _startRawDump,
      stop: _stopRawDump,
      upload: _uploadLogsForRawDump,
      onChanged: () {
        if (_canUpdateUi) setState(() {});
      },
    );
    unawaited(_initialize());
  }

  @override
  void onRouteInactive(String reason) {
    unawaited(() async {
      await _rawDumpController.finalizeForLeave();
      if (!_paused && _replay != null && _selected != null) await _pauseForLifecycle();
    }());
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
    _recordingsButtonFocusNode.dispose();
    _rawDumpFinalization = _rawDumpController.finalizeForLeave();
    _rawDumpController.dispose();
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
            focusNode: _recordingsButtonFocusNode,
            tooltip: '选择录像',
            onPressed: _initCode == 0 ? _showRecordingsSheet : null,
            icon: const Icon(Icons.calendar_month_outlined),
          ),
          PlayerLogUploadButton(
            buttonKey: DemoWidgetKeys.playerLogUploadButton,
            uploadingLogs: _logUploadController.uploading,
            onUploadLogs: _uploadLogs,
          ),
        ],
      ),
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: DownlinkVideoStage(
              lanes: <DownlinkVideoLaneModel>[
                for (final int id in widget.videoChannelIds)
                  DownlinkVideoLaneModel(
                    streamId: id,
                    videoView: _videoOutputs[id]?.view() ?? const SizedBox.shrink(),
                    statusLabel: _videoStatusLabel(id),
                    showStatus: _videoStates[id] != TiCloudStorageVideoOutputState.rendering,
                  ),
              ],
              selectedStreamId: _selectedVideoChannelId,
              maximizedStreamId: _maximizedVideoChannelId,
              stageStatusLabel: _stageStatusLabel,
              indicatorMode: _stageIndicatorMode,
              onSelect: _selectVideoChannel,
            ),
          ),
          const Positioned.fill(child: DownlinkOverlayGradient()),
          Positioned(
            left: 12,
            top: 0,
            bottom: 0,
            child: SafeArea(
              child: Center(
                child: DemoRawDumpButton(key: DemoWidgetKeys.rawDumpButton, controller: _rawDumpController),
              ),
            ),
          ),
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
          CloudStoragePlaybackViewport(console: _buildPlaybackConsole(selected)),
        ],
      ),
    );
  }

  Widget _buildPlaybackConsole(TiCloudStorageRecordingRange? range) {
    final int minimum = range?.startTimeMs ?? 0;
    final int maximum = range == null ? 1 : range.endTimeMs - 1;
    final int current = (_seekPreview?.round() ?? _replay?.currentTimeMs ?? minimum).clamp(minimum, maximum);
    return CloudStoragePlaybackConsole(
      hasRange: range != null,
      rangeStart: minimum.toDouble(),
      rangeEnd: maximum.toDouble(),
      current: current.toDouble(),
      currentLabel: range == null ? '--:--:--' : _formatClock(current),
      endLabel: range == null ? '--:--:--' : _formatClock(range.endTimeMs),
      playing: range != null,
      paused: _paused,
      audioEnabled:
          range != null &&
          _audioOutput != null &&
          _audioState != TiCloudStorageAudioOutputState.failed &&
          _replay?.speed == TiCloudStorageReplaySpeed.x1,
      audioMuted: _audioMuted || _replay?.speed != TiCloudStorageReplaySpeed.x1,
      speed: _replay?.speed ?? TiCloudStorageReplaySpeed.x1,
      selectedVideoChannelId: _selectedVideoChannelId,
      selectedVideoPosition:
          _selectedVideoChannelId == null ? null : widget.videoChannelIds.indexOf(_selectedVideoChannelId!) + 1,
      mediaBusy: _mediaFileBusy,
      recording: _recordingTask != null,
      onSeekPreview: (double value) => setState(() => _seekPreview = value),
      onSeekEnd: _seekTo,
      onTogglePause: _togglePause,
      onToggleVolume: _toggleAudioOutputVolume,
      onSetSpeed: (TiCloudStorageReplaySpeed speed) => unawaited(_setReplaySpeed(speed)),
      onToggleRecording: () => _executeCloudMediaAction(_CloudMediaAction.record),
      onSnapshot: () => _executeCloudMediaAction(_CloudMediaAction.snapshot),
    );
  }

  Future<int> _startRawDump() async {
    final TiCloudStorageReplay? replay = _replay;
    if (replay == null) return kTiCloudStorageErrorNotStarted;
    final Resp<TiRawDump> result = await replay.startRawDump(
      TiCloudStorageRawDumpOptions(
        audioChannelIds: widget.audioChannelId == null ? const <int>[] : <int>[widget.audioChannelId!],
        videoChannelIds: widget.videoChannelIds,
      ),
    );
    if (result.success) _rawDump = result.data;
    return result.success ? 0 : result.code ?? kTiCloudStorageErrorIoFailed;
  }

  Future<DemoRawDumpArchiveResult> _stopRawDump() async {
    final TiRawDump? dump = _rawDump;
    if (dump == null) return const DemoRawDumpArchiveResult(code: kTiCloudStorageErrorInUse);
    final Resp<TiRawDumpArchive> result = await dump.stop();
    if (result.success || result.code != kTiCloudStorageErrorInUse) _rawDump = null;
    final TiRawDumpArchive? archive = result.data;
    return DemoRawDumpArchiveResult(
      code: result.success ? 0 : result.code ?? kTiCloudStorageErrorIoFailed,
      captureId: archive?.captureId,
      archiveSha256: archive?.sha256,
      archivePath: archive?.path,
    );
  }

  Future<({int code, String? logId})?> _uploadLogs() async {
    await _rawDumpController.stopBeforeExistingUpload();
    return _logUploadController.upload(remoteId: 'ti-cloud-storage');
  }

  Future<DemoRawDumpUploadResult> _uploadLogsForRawDump() async {
    final ({int code, String? logId})? result = await _logUploadController.upload(remoteId: 'ti-cloud-storage');
    return DemoRawDumpUploadResult(code: result?.code ?? kTiCloudStorageErrorIoFailed, logId: result?.logId);
  }

  void _seekTo(double value) {
    final int code = _replay?.seek(value.round()) ?? kTiCloudStorageErrorNotStarted;
    setState(() {
      _seekPreview = null;
      _lastCode = code == 0 ? null : code;
    });
    if (code == 0) {
      DemoExampleSmokeHooks.current?.markerSink.passed(
        'ti-cloud-storage-smoke-seek-accepted',
        payload: <String, Object?>{'target_time_ms': value.round()},
      );
    }
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
    if (widget.audioChannelId == null && widget.videoChannelIds.isEmpty) {
      _showMessage('请至少选择一路音频或视频');
      return;
    }

    TiCloudStorageReplay? replay = _replay;
    if (replay == null) {
      final TiCloudStorage? cloudStorage = _cloudStorage;
      if (cloudStorage == null) return;
      if (widget.audioChannelId != null) {
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
      }
      replay = cloudStorage.createReplay();
      final TiCloudStorageAudioOutput? audio = widget.audioChannelId == null ? null : TiCloudStorageAudioOutput();
      final Map<int, TiCloudStorageVideoOutput> videos = <int, TiCloudStorageVideoOutput>{};
      replay.onTimeChanged = (int timeMs) {
        if (_canUpdateUi) {
          setState(() {});
          DemoExampleSmokeHooks.current?.markerSink.passed(
            'ti-cloud-storage-smoke-replay-time',
            payload: <String, Object?>{'time_ms': timeMs},
          );
        }
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
            'ti-cloud-storage-smoke-replay-source-completed',
            payload: <String, Object?>{'time_ms': replay?.currentTimeMs ?? 0},
          );
        }
      };
      for (final int channelId in widget.videoChannelIds) {
        final TiCloudStorageVideoOutput video = TiCloudStorageVideoOutput();
        videos[channelId] = video;
        video.onStateChanged = (TiCloudStorageVideoOutputState state) {
          if (!_canUpdateUi) return;
          setState(() => _videoStates[channelId] = state);
          _publishCompletionIfReady();
          DemoExampleSmokeHooks.current?.markerSink.passed(
            'ti-cloud-storage-smoke-video-state',
            payload: <String, Object?>{'channel_id': channelId, 'state': state.name},
          );
          if (state == TiCloudStorageVideoOutputState.rendering) {
            final Size? size = video.renderSize;
            DemoExampleSmokeHooks.current?.markerSink.passed(
              'ti-cloud-storage-smoke-video-rendering',
              payload: <String, Object?>{
                'channel_id': channelId,
                'width': size?.width.round() ?? 0,
                'height': size?.height.round() ?? 0,
              },
            );
          }
        };
        video.onRenderSizeChanged = (Size size) {
          DemoExampleSmokeHooks.current?.markerSink.passed(
            'ti-cloud-storage-smoke-video-size',
            payload: <String, Object?>{
              'channel_id': channelId,
              'width': size.width.round(),
              'height': size.height.round(),
            },
          );
        };
        video.onError = (int code) {
          if (!_canUpdateUi) return;
          _unavailableVideoChannelIds.add(channelId);
          setState(() => _videoStates[channelId] = TiCloudStorageVideoOutputState.failed);
        };
      }
      audio?.onStateChanged = (TiCloudStorageAudioOutputState state) {
        if (!_canUpdateUi) return;
        setState(() => _audioState = state);
        _publishCompletionIfReady();
        DemoExampleSmokeHooks.current?.markerSink.passed(
          'ti-cloud-storage-smoke-audio-state',
          payload: <String, Object?>{'state': state.name},
        );
      };
      audio?.onError = (int code) {
        if (_canUpdateUi) {
          setState(() {
            _audioState = TiCloudStorageAudioOutputState.failed;
            _lastCode = code;
          });
        }
      };
      int firstAttachError = kTiCloudStorageErrorOk;
      for (final MapEntry<int, TiCloudStorageVideoOutput> entry in videos.entries) {
        final int laneCode = entry.value.attach(replay: replay, channelId: entry.key);
        if (laneCode == kTiCloudStorageErrorOk) {
          _attachedVideoChannelIds.add(entry.key);
        } else {
          if (firstAttachError == kTiCloudStorageErrorOk) firstAttachError = laneCode;
          _unavailableVideoChannelIds.add(entry.key);
          _videoStates[entry.key] = TiCloudStorageVideoOutputState.failed;
        }
      }
      bool audioAttached = false;
      if (audio != null) {
        final int audioCode = audio.attach(replay: replay, channelId: widget.audioChannelId!);
        audioAttached = audioCode == kTiCloudStorageErrorOk;
        if (!audioAttached) {
          if (firstAttachError == kTiCloudStorageErrorOk) firstAttachError = audioCode;
          _audioState = TiCloudStorageAudioOutputState.failed;
          await _disposeAfterDeferredCallbacks(audio.dispose);
        }
      }
      if (_attachedVideoChannelIds.isEmpty && !audioAttached) {
        for (final TiCloudStorageVideoOutput video in videos.values) {
          await _disposeAfterDeferredCallbacks(video.dispose);
        }
        await _disposeAfterDeferredCallbacks(replay.dispose);
        _audioSession.releaseIfNeeded(reason: 'cloud_storage_output_attach_failed');
        if (_canUpdateUi) {
          setState(() => _lastCode = firstAttachError);
          _reportSmokeFailure('ti-cloud-storage-play-attach', firstAttachError);
        }
        return;
      }
      _replay = replay;
      _audioOutput = audioAttached ? audio : null;
      _videoOutputs.addAll(videos);
    }

    _completionReported = false;
    _audioState =
        _audioOutput == null
            ? (widget.audioChannelId == null
                ? TiCloudStorageAudioOutputState.completed
                : TiCloudStorageAudioOutputState.failed)
            : TiCloudStorageAudioOutputState.idle;
    for (final int channelId in widget.videoChannelIds) {
      _videoStates[channelId] =
          _unavailableVideoChannelIds.contains(channelId)
              ? TiCloudStorageVideoOutputState.failed
              : TiCloudStorageVideoOutputState.idle;
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
    final int? targetChannelId = _selectedVideoChannelId;
    if (targetChannelId == null) return;
    final Resp<TiCloudStorageRecordingTask>? result = _replay?.startRecording(
      videoChannelId: targetChannelId,
      audioChannelId: widget.audioChannelId,
    );
    if (!_canUpdateUi) return;
    setState(() {
      _recordingTask = result?.data;
      _recordingVideoChannelId = result?.success == true ? targetChannelId : null;
      _lastCode = result?.code;
    });
    if (result?.success == true) {
      DemoExampleSmokeHooks.current?.markerSink.passed('ti-cloud-storage-smoke-recording-started');
    } else {
      _reportSmokeFailure('ti-cloud-storage-recording-start', result?.code);
    }
  }

  Future<void> _executeCloudMediaAction(_CloudMediaAction action) async {
    if (!_canUpdateUi || _selected == null || _replay == null || _selectedVideoChannelId == null || _mediaFileBusy) {
      return;
    }
    switch (action) {
      case _CloudMediaAction.record:
        await _toggleRecording();
        return;
      case _CloudMediaAction.snapshot:
        await _snapshot();
        return;
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
    if (file != null) await _replaceLatestRecording(file, _recordingVideoChannelId);
    if (!_canUpdateUi) return result.code ?? kTiCloudStorageErrorOk;
    setState(() => _lastCode = result.code);
    if (result.success && file != null) {
      DemoExampleSmokeHooks.current?.markerSink.passed(
        'ti-cloud-storage-smoke-recording-completed',
        payload: <String, Object?>{
          'video_channel_id': _recordingVideoChannelId,
          'duration_ms': file.duration.inMilliseconds,
        },
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
    final List<TiCloudStorageRecordingGap> observedGaps = <TiCloudStorageRecordingGap>[];
    final int? targetChannelId = _selectedVideoChannelId;
    if (targetChannelId == null) {
      setState(() => _exportingRange = null);
      return;
    }
    _exportingVideoChannelId = targetChannelId;
    final Resp<TiCloudStorageExportTask> started = cloudStorage.exportRecording(
      startTimeMs: range.startTimeMs,
      endTimeMs: range.endTimeMs,
      videoChannelId: targetChannelId,
      audioChannelId: widget.audioChannelId,
      onProgress: (_) {
        if (_canUpdateUi) {
          setState(() {});
          _refreshSheet();
        }
      },
      onProgressDetail: (_) {
        if (_canUpdateUi) {
          setState(() {});
          _refreshSheet();
        }
      },
      onRecordingGap: observedGaps.add,
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
    final TiCloudStorageExportOutcome? outcome = await started.data?.completion;
    if (outcome == null) {
      if (_canUpdateUi) {
        setState(() {
          _exportTask = null;
          _exportingRange = null;
        });
        _refreshSheet();
      }
      return;
    }
    final TiCloudStorageRecordingFile? file = outcome.file;
    if (!_canUpdateUi) {
      await file?.delete();
      return;
    }
    setState(() {
      _exportTask = null;
      _exportingRange = null;
      _lastCode = outcome.code;
    });
    _refreshSheet();
    if (file != null) await _replaceLatestRecording(file, _exportingVideoChannelId);
    if (outcome.code == kTiCloudStorageErrorOk && file != null && outcome.report != null) {
      DemoExampleSmokeHooks.current?.markerSink.passed(
        'ti-cloud-storage-smoke-export-completed',
        payload: <String, Object?>{
          'duration_ms': file.duration.inMilliseconds,
          'video_channel_id': _exportingVideoChannelId,
          'covered_duration_ms': outcome.report!.coveredDuration.inMilliseconds,
          'gap_count': outcome.report!.gaps.length,
          'observed_gap_count': observedGaps.length,
          'complete': outcome.report!.complete,
        },
      );
      await _saveLatestMediaToGallery();
    } else {
      _reportSmokeFailure('ti-cloud-storage-export', outcome.code);
    }
  }

  Future<void> _snapshot() async {
    final int? targetChannelId = _selectedVideoChannelId;
    if (targetChannelId == null) return;
    setState(() => _mediaFileBusy = true);
    DemoExampleSmokeHooks.current?.markerSink.passed('ti-cloud-storage-smoke-snapshot-started');
    final Resp<TiCloudStorageSnapshotFile>? result = await _videoOutputs[targetChannelId]?.takeSnapshot();
    if (!_canUpdateUi || result == null) {
      await result?.data?.delete();
      if (_canUpdateUi) setState(() => _mediaFileBusy = false);
      return;
    }
    if (result.data != null) await _replaceLatestSnapshot(result.data!, targetChannelId);
    if (!_canUpdateUi) return;
    setState(() => _lastCode = result.code);
    if (result.success && result.data != null) {
      DemoExampleSmokeHooks.current?.markerSink.passed(
        'ti-cloud-storage-smoke-snapshot-completed',
        payload: <String, Object?>{'video_channel_id': targetChannelId},
      );
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
    final String fileName = demoGalleryFileName(
      kind == _LatestCloudStorageMedia.recording ? 'mp4' : 'jpg',
      targetId: _latestMediaVideoChannelId,
      targetKind: 'channel',
    );
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
        _latestMediaVideoChannelId = null;
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

  Future<void> _replaceLatestRecording(TiCloudStorageRecordingFile file, int? targetChannelId) async {
    final TiCloudStorageRecordingFile? previous = _latestRecording;
    final TiCloudStorageSnapshotFile? other = _latestSnapshot;
    _latestRecording = file;
    _latestSnapshot = null;
    _latestMedia = _LatestCloudStorageMedia.recording;
    _latestMediaVideoChannelId = targetChannelId;
    if (previous != null && previous.path != file.path) await previous.delete();
    await other?.delete();
  }

  Future<void> _replaceLatestSnapshot(TiCloudStorageSnapshotFile file, int targetChannelId) async {
    final TiCloudStorageSnapshotFile? previous = _latestSnapshot;
    final TiCloudStorageRecordingFile? other = _latestRecording;
    _latestSnapshot = file;
    _latestRecording = null;
    _latestMedia = _LatestCloudStorageMedia.snapshot;
    _latestMediaVideoChannelId = targetChannelId;
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
    if (_canUpdateUi && _recordingsButtonFocusNode.canRequestFocus) {
      _recordingsButtonFocusNode.requestFocus();
    }
  }

  Widget _buildRecordingSheet(BuildContext sheetContext) {
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * 0.88,
            child: Column(
              children: <Widget>[
                Expanded(
                  child: ListView(
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(child: _buildRecordingSheetBody(sheetContext)),
              ],
            ),
          ),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ExampleTheme.radiusSmall)),
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
    await _rawDumpFinalization;
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
    _latestMediaVideoChannelId = null;
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
    await _rawDumpController.finalizeForLeave();
    final TiCloudStorageReplay? replay = _replay;
    final TiCloudStorageAudioOutput? audio = _audioOutput;
    final Map<int, TiCloudStorageVideoOutput> videos = Map<int, TiCloudStorageVideoOutput>.of(_videoOutputs);
    final Set<int> attachedVideoChannelIds = Set<int>.of(_attachedVideoChannelIds);
    void clearPlayback() {
      _selected = null;
      _audioOutput = null;
      _videoOutputs.clear();
      _videoStates.clear();
      _attachedVideoChannelIds.clear();
      _unavailableVideoChannelIds.clear();
      _audioState = TiCloudStorageAudioOutputState.idle;
      _completionReported = false;
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
    for (final MapEntry<int, TiCloudStorageVideoOutput> entry in videos.entries) {
      if (attachedVideoChannelIds.contains(entry.key)) {
        cleanupCode = _firstError(cleanupCode, entry.value.detach());
      }
    }
    cleanupCode = _firstError(cleanupCode, await _disposeAfterDeferredCallbacks(audio?.dispose));
    for (final TiCloudStorageVideoOutput video in videos.values) {
      final int videoCode = await _disposeAfterDeferredCallbacks(video.dispose);
      if (videoCode != 0 && _canUpdateUi) setState(() => _lastCode = videoCode);
      cleanupCode = _firstError(cleanupCode, videoCode);
    }
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

  String get _stageStatusLabel {
    if (_selected == null) return _initCode == null ? '加载中' : '请选择录像';
    if (widget.videoChannelIds.isEmpty) {
      return widget.audioChannelId == null ? '未配置音视频' : _audioStatusLabel;
    }
    switch (_videoStates[_selectedVideoChannelId]) {
      case TiCloudStorageVideoOutputState.buffering:
        return '缓冲中';
      case TiCloudStorageVideoOutputState.paused:
        return '已暂停';
      case TiCloudStorageVideoOutputState.completed:
        return _outputsCompleted ? '播放完成' : '其他输出播放中';
      case TiCloudStorageVideoOutputState.failed:
        return '播放失败';
      case TiCloudStorageVideoOutputState.idle:
      case TiCloudStorageVideoOutputState.rendering:
      case null:
        return '加载中';
    }
  }

  DownlinkCenterIndicatorMode get _stageIndicatorMode {
    if (widget.videoChannelIds.isEmpty && widget.audioChannelId != null) {
      if (_audioState == TiCloudStorageAudioOutputState.failed) return DownlinkCenterIndicatorMode.error;
      if (_audioState == TiCloudStorageAudioOutputState.idle ||
          _audioState == TiCloudStorageAudioOutputState.buffering) {
        return DownlinkCenterIndicatorMode.loading;
      }
      return DownlinkCenterIndicatorMode.running;
    }
    final TiCloudStorageVideoOutputState? state = _videoStates[_selectedVideoChannelId];
    if (state == TiCloudStorageVideoOutputState.failed || (_initCode != null && _initCode != 0)) {
      return DownlinkCenterIndicatorMode.error;
    }
    return state == TiCloudStorageVideoOutputState.buffering || (_initCode == null && _selected == null)
        ? DownlinkCenterIndicatorMode.loading
        : DownlinkCenterIndicatorMode.running;
  }

  String _videoStatusLabel(int channelId) {
    return switch (_videoStates[channelId]) {
      TiCloudStorageVideoOutputState.buffering => '缓冲中',
      TiCloudStorageVideoOutputState.paused => '已暂停',
      TiCloudStorageVideoOutputState.completed => '播放完成',
      TiCloudStorageVideoOutputState.failed => '播放失败',
      TiCloudStorageVideoOutputState.rendering => '播放中',
      TiCloudStorageVideoOutputState.idle || null => '等待视频',
    };
  }

  bool get _outputsCompleted {
    final bool audioCompleted =
        widget.audioChannelId == null || _audioState == TiCloudStorageAudioOutputState.completed;
    return audioCompleted &&
        widget.videoChannelIds.every(
          (int channelId) => _videoStates[channelId] == TiCloudStorageVideoOutputState.completed,
        );
  }

  String get _audioStatusLabel => switch (_audioState) {
    TiCloudStorageAudioOutputState.idle || TiCloudStorageAudioOutputState.buffering => '等待音频',
    TiCloudStorageAudioOutputState.playing => '音频播放中',
    TiCloudStorageAudioOutputState.paused => '已暂停',
    TiCloudStorageAudioOutputState.completed => '播放完成',
    TiCloudStorageAudioOutputState.failed => '播放失败',
  };

  void _publishCompletionIfReady() {
    if (_completionReported || !_outputsCompleted) return;
    _completionReported = true;
    DemoExampleSmokeHooks.current?.markerSink.passed(
      'ti-cloud-storage-smoke-outputs-completed',
      payload: <String, Object?>{
        'audio_channel_id': widget.audioChannelId,
        'video_channel_ids': widget.videoChannelIds,
      },
    );
  }

  void _selectVideoChannel(int channelId) {
    setState(() {
      if (_selectedVideoChannelId == channelId) {
        _maximizedVideoChannelId = _maximizedVideoChannelId == channelId ? null : channelId;
      } else {
        _selectedVideoChannelId = channelId;
        _maximizedVideoChannelId = null;
      }
    });
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

enum _CloudMediaAction { record, snapshot }

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
