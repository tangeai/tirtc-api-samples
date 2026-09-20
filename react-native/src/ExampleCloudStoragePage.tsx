import React, {useCallback, useEffect, useMemo, useRef, useState} from 'react';
import {
  Modal,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  useWindowDimensions,
  View,
} from 'react-native';
import Slider from '@react-native-community/slider';
import {useSafeAreaInsets} from 'react-native-safe-area-context';
import {
  TiRtcLogging,
  TiCloudStorage,
  TiCloudStorageAudioOutput,
  TiCloudStorageAudioOutputState,
  TiCloudStorageReplay,
  TiCloudStorageReplaySpeed,
  TiCloudStorageVideoOutput,
  TiCloudStorageVideoOutputState,
  TiCloudStorageVideoOutputView,
  TI_CLOUD_STORAGE_ERROR_NO_FRAME,
  type TiCloudStorageExportTask,
  type TiCloudStorageRecordingFile,
  type TiCloudStorageRecordingDay,
  type TiCloudStorageRecordingRange,
  type TiCloudStorageRecordingRangesResult,
  type TiCloudStorageRecordingTask,
  type TiCloudStorageSnapshotFile,
  type TiRawDump,
} from 'tirtc-react-native';
import {useExampleLogUpload} from './ExampleLogUpload';
import {
  OutlineButton,
  RawDumpStageControl,
  StageControlButton,
  StatusText,
  TopBar,
  VideoStage,
  exampleTheme,
} from './ExampleUi';
import {parseCloudStorageChannelIds, type ExampleConfig, type MediaSelection} from './ExampleTypes';
import {galleryFileName, prepareGalleryWritePermission} from './ExampleSessionShared';
import {PlaybackActionMenu} from './ExamplePlaybackMenu';

const speeds = [TiCloudStorageReplaySpeed.x0_125, TiCloudStorageReplaySpeed.x0_25,
  TiCloudStorageReplaySpeed.x0_5, TiCloudStorageReplaySpeed.x1, TiCloudStorageReplaySpeed.x2,
  TiCloudStorageReplaySpeed.x4, TiCloudStorageReplaySpeed.x8] as const;
const speedLabels: Record<TiCloudStorageReplaySpeed, string> = {
  x0_125: '1/8×', x0_25: '1/4×', x0_5: '1/2×', x1: '1×', x2: '2×', x4: '4×', x8: '8×',
};
const snapshotRetryTimeoutMs = 10_000;
const snapshotRetryIntervalMs = 200;
type TiCloudStorageMediaFile = TiCloudStorageRecordingFile | TiCloudStorageSnapshotFile;

function newestFirstRecordingRanges(
  ranges: readonly TiCloudStorageRecordingRange[],
): TiCloudStorageRecordingRange[] {
  return [...ranges].sort(
    (left, right) => right.startTimeMs - left.startTimeMs || right.endTimeMs - left.endTimeMs,
  );
}

export function TiCloudStorageScreen({config, onBack}: {config: ExampleConfig; onBack: () => void}) {
  const insets = useSafeAreaInsets();
  const window = useWindowDimensions();
  const session = useMemo(() => new TiCloudStorageExampleSession(config), [config]);
  const videoChannelIds = session.media.videos;
  const [status, setStatus] = useState('正在初始化 Ti Cloud Storage');
  const [ranges, setRanges] = useState<readonly TiCloudStorageRecordingRange[]>([]);
  const [rangeError, setRangeError] = useState('');
  const [selectedDay, setSelectedDay] = useState(() => shanghaiDate(Date.now()));
  const [visibleMonth, setVisibleMonth] = useState(() => shanghaiDate(Date.now()).slice(0, 7));
  const [recordingDays, setRecordingDays] = useState<ReadonlySet<string>>(() => new Set());
  const [monthLoading, setMonthLoading] = useState(false);
  const [monthError, setMonthError] = useState('');
  const [selected, setSelected] = useState<TiCloudStorageRecordingRange | null>(null);
  const [currentTimeMs, setCurrentTimeMs] = useState<number | null>(null);
  const [videoStates, setVideoStates] = useState<Map<number, TiCloudStorageVideoOutputState>>(
    () => new Map(videoChannelIds.map((channelId) => [channelId, TiCloudStorageVideoOutputState.idle])),
  );
  const [selectedVideoChannelId, setSelectedVideoChannelId] = useState<number | null>(session.selectedVideoChannelId);
  const [maximizedVideoChannelId, setMaximizedVideoChannelId] = useState<number | null>(null);
  const [playbackRevision, setPlaybackRevision] = useState(0);
  const [ready, setReady] = useState(false);
  const [paused, setPaused] = useState(false);
  const [muted, setMuted] = useState(false);
  const [recording, setRecording] = useState(false);
  const [speed, setSpeed] = useState<TiCloudStorageReplaySpeed>(TiCloudStorageReplaySpeed.x1);
  const [busy, setBusy] = useState(false);
  const [rawDumpBusy, setRawDumpBusy] = useState(false);
  const [rawDumpCapturing, setRawDumpCapturing] = useState(false);
  const [rawDumpUploadPending, setRawDumpUploadPending] = useState(false);
  const [exportingRangeStartMs, setExportingRangeStartMs] = useState<number | null>(null);
  const [showRanges, setShowRanges] = useState(true);
  const [latestMedia, setLatestMedia] = useState(false);
  const [seekPreviewRatio, setSeekPreviewRatio] = useState<number | null>(null);
  const mountedRef = useRef(true);
  const dayQueryGenerationRef = useRef(0);
  const monthQueryGenerationRef = useRef(0);
  const renderedClockSecondRef = useRef(-1);
  const playbackStartedRef = useRef(false);
  const {uploadingLogs, uploadLogs} = useExampleLogUpload(() => TiRtcLogging.upload());
  const selectedVideoReady = selectedVideoChannelId !== null &&
    videoStates.get(selectedVideoChannelId) === TiCloudStorageVideoOutputState.rendering;

  const toggleRawDump = async () => {
    if (rawDumpBusy || uploadingLogs) return;
    setRawDumpBusy(true);
    const result = await session.toggleRawDump();
    if (!mountedRef.current) return;
    setRawDumpCapturing(result.capturing);
    setStatus(result.status);
    setRawDumpBusy(false);
    if (result.upload) {
      const success = await uploadLogs();
      session.finishRawDumpUpload(success);
      setRawDumpUploadPending(session.isRawDumpUploadPending());
      setStatus(success ? '诊断数据上传成功' : '诊断数据上传失败 · 点击重试上传');
    }
  };

  const query = useCallback(async (date: string) => {
    const generation = ++dayQueryGenerationRef.current;
    setBusy(true);
    setRangeError('');
    setStatus('正在查询录像…');
    const result = await session.query(...shanghaiDayBounds(date));
    if (!mountedRef.current || generation !== dayQueryGenerationRef.current) return;
    setRanges(newestFirstRecordingRanges(result.recordings));
    setRangeError(result.code === 0 ? '' : `查询失败 ${result.code}`);
    setStatus(
      result.code === 0
        ? result.recordings.length === 0
          ? '当天没有可用录像'
          : `找到 ${result.recordings.length} 段录像`
        : `查询失败 ${result.code}`,
    );
    setBusy(false);
  }, [session]);

  const queryMonth = useCallback(async (month: string) => {
    const generation = ++monthQueryGenerationRef.current;
    setMonthLoading(true);
    setMonthError('');
    setRecordingDays(new Set());
    const result = await session.queryDays(...monthBounds(month), TI_CLOUD_STORAGE_TIME_ZONE);
    if (!mountedRef.current || generation !== monthQueryGenerationRef.current) return;
    setMonthLoading(false);
    if (result.code !== 0) {
      setMonthError(`月份加载失败 ${result.code}`);
      return;
    }
    setRecordingDays(new Set(result.days.filter((day) => day.hasRecording).map((day) => day.date)));
  }, [session]);

  useEffect(() => {
    let mounted = true;
    mountedRef.current = true;
    session.setCallbacks({
      onStatus: (message) => mounted && setStatus(message),
      onTime: (value) => {
        if (!mounted) return;
        const second = Math.floor(value / 1000);
        if (second !== renderedClockSecondRef.current) {
          renderedClockSecondRef.current = second;
          setCurrentTimeMs(value);
        }
      },
      onVideoState: (channelId, value) => {
        if (!mounted) return;
        setVideoStates((current) => new Map(current).set(channelId, value));
      },
    });
    session.start().then((code) => {
      if (!mounted) return;
      if (code === 0) {
        setReady(true);
        const today = shanghaiDate(Date.now());
        void queryMonth(today.slice(0, 7));
        void query(today);
      } else {
        setStatus(`Ti Cloud Storage 初始化失败 ${code}`);
      }
    });
    return () => {
      mounted = false;
      mountedRef.current = false;
      dayQueryGenerationRef.current += 1;
      monthQueryGenerationRef.current += 1;
      void session.close();
    };
  }, [query, queryMonth, session]);

  const leave = () => {
    if (busy) return;
    setBusy(true);
    setReady(false);
    mountedRef.current = false;
    onBack();
  };

  const play = (range: TiCloudStorageRecordingRange) => {
    if (session.media.audio === null && session.media.videos.length === 0) {
      setStatus('请至少选择一路音频或视频后播放');
      return;
    }
    if (!session.hasPlayableOutput) {
      setStatus('所选音视频输出均不可用');
      return;
    }
    const code = session.play(range);
    if (code === 0) {
      if (playbackStartedRef.current) setPlaybackRevision((current) => current + 1);
      playbackStartedRef.current = true;
      setSelected(range);
      setCurrentTimeMs(range.startTimeMs);
      setPaused(false);
      setShowRanges(false);
    }
    setStatus(code === 0 ? '正在播放' : `播放失败 ${code}`);
  };

  const togglePause = () => {
    const code = paused ? session.replay.resume() : session.replay.pause();
    if (code === 0) setPaused(!paused);
    setStatus(code === 0 ? (paused ? '继续播放' : '已暂停') : `控制失败 ${code}`);
  };

  const seek = (ratio: number) => {
    if (selected === null) return;
    const normalized = Math.max(0, Math.min(1, ratio));
    const target = Math.min(
      selected.endTimeMs - 1,
      Math.round(selected.startTimeMs + (selected.endTimeMs - selected.startTimeMs) * normalized),
    );
    const code = session.replay.seek(target);
    if (code === 0) setCurrentTimeMs(target);
    setSeekPreviewRatio(null);
    setStatus(code === 0 ? `已跳转 ${formatClock(target)}` : `定位失败 ${code}`);
  };

  const cycleSpeed = () => {
    const next = speeds[(speeds.indexOf(speed) + 1) % speeds.length] ?? TiCloudStorageReplaySpeed.x1;
    const code = session.setSpeed(next);
    if (code === 0) {
      setSpeed(next);
    }
    setStatus(code === 0 ? `播放倍速：${speedLabels[next]}` : `倍速设置失败 ${code}`);
  };

  const toggleMuted = () => {
    const next = !muted;
    const code = session.setMuted(next);
    if (code === 0) setMuted(next);
    setStatus(code === 0 ? (next ? '已静音' : '已恢复声音') : `音量设置失败 ${code}`);
  };

  const toggleRecording = async () => {
    if (!recording) {
      const code = session.beginRecording();
      setRecording(code === 0);
      setStatus(code === 0 ? '边播边录已开始' : `保存启动失败 ${code}`);
      return;
    }
    setBusy(true);
    const result = await session.finishRecording();
    if (!mountedRef.current) return;
    setRecording(false);
    setBusy(false);
    setLatestMedia(result.file !== null);
    setStatus(result.message);
  };

  const exportRange = async (range: TiCloudStorageRecordingRange) => {
    setBusy(true);
    setExportingRangeStartMs(range.startTimeMs);
    setStatus('下载 0%');
    const result = await session.exportRange(range, (value) => {
      if (mountedRef.current) setStatus(`下载 ${Math.round(value * 100)}%`);
    });
    if (!mountedRef.current) return;
    setBusy(false);
    setExportingRangeStartMs(null);
    setLatestMedia(result.file !== null);
    setStatus(result.message);
  };

  const snapshot = async () => {
    setBusy(true);
    const result = await session.snapshot();
    if (!mountedRef.current) return;
    setLatestMedia(result.file !== null);
    setStatus(result.message);
    setBusy(false);
  };

  const saveLatest = async () => {
    setBusy(true);
    const message = await session.saveLatest();
    if (!mountedRef.current) return;
    setLatestMedia(session.hasLatestMedia);
    setStatus(message);
    setBusy(false);
  };

  const rangeProgress =
    selected === null || currentTimeMs === null
      ? 0
      : Math.max(0, Math.min(1, (currentTimeMs - selected.startTimeMs) / (selected.endTimeMs - selected.startTimeMs)));
  const seekProgress = seekPreviewRatio ?? rangeProgress;
  const seekTimeMs =
    selected === null
      ? 0
      : Math.round(selected.startTimeMs + (selected.endTimeMs - selected.startTimeMs) * seekProgress);
  const compact = window.width < 600;
  const auxiliaryWide = window.width >= 600;
  const recordingsState = exportingRangeStartMs !== null
    ? 'export-busy'
    : busy || monthLoading
      ? 'loading'
      : monthError || rangeError
        ? 'error'
        : ranges.length === 0
          ? 'empty'
          : 'populated';
  const recordingsStateMessage = recordingsState === 'export-busy'
    ? '正在下载录像'
    : recordingsState === 'loading'
      ? '正在加载录像'
      : recordingsState === 'error'
        ? '录像加载失败'
        : recordingsState === 'empty'
          ? '没有录像'
          : '录像已加载';
  const primaryVideoChannelId = videoChannelIds.find((channelId) => channelId === selectedVideoChannelId)
    ?? videoChannelIds[0]
    ?? null;
  const secondaryVideoChannelIds = videoChannelIds.filter((channelId) => channelId !== primaryVideoChannelId);
  const videoLaneLayout = (channelId: number) => {
    if (maximizedVideoChannelId !== null) {
      return channelId === maximizedVideoChannelId ? styles.videoLaneFill : styles.videoLaneParked;
    }
    if (channelId === primaryVideoChannelId) {
      if (secondaryVideoChannelIds.length === 0) return styles.videoLaneFill;
      return compact ? styles.videoLanePrimaryCompact : styles.videoLanePrimaryWide;
    }
    const secondaryIndex = secondaryVideoChannelIds.indexOf(channelId);
    if (compact) {
      if (secondaryVideoChannelIds.length === 1) return styles.videoLaneSecondaryCompactSingle;
      return secondaryIndex === 0
        ? styles.videoLaneSecondaryCompactLeading
        : styles.videoLaneSecondaryCompactTrailing;
    }
    if (secondaryVideoChannelIds.length === 1) return styles.videoLaneSecondaryWideSingle;
    return secondaryIndex === 0
      ? styles.videoLaneSecondaryWideLeading
      : styles.videoLaneSecondaryWideTrailing;
  };
  const renderVideoLane = (channelId: number) => {
    const state = videoStates.get(channelId) ?? TiCloudStorageVideoOutputState.idle;
    const selectedVideo = selectedVideoChannelId === channelId;
    return (
      <View collapsable={false} style={[styles.videoTile, selectedVideo ? styles.videoTileSelected : null]}>
        <Pressable
          accessibilityRole="button"
          accessibilityLabel={`Video Channel ${channelId}`}
          accessibilityState={{selected: selectedVideo}}
          testID={`video-channel-${channelId}`}
          onPress={() => {
            if (selectedVideo) {
              setMaximizedVideoChannelId((current) => current === channelId ? null : channelId);
            } else {
              session.selectVideo(channelId);
              setSelectedVideoChannelId(channelId);
            }
          }}
          onLongPress={() => setMaximizedVideoChannelId((current) => current === channelId ? null : channelId)}
          style={styles.videoTileContent}>
          {ready ? (
            <TiCloudStorageVideoOutputView
              key={`cloud-video-output-${channelId}-${playbackRevision}`}
              output={session.videos.get(channelId)!}
              resizeMode="contain"
              style={styles.video}
            />
          ) : null}
          {selected === null || state !== TiCloudStorageVideoOutputState.rendering ? (
            <View pointerEvents="none" style={styles.videoLaneOverlay}>
              <Text style={styles.videoLaneStatus}>{stageLabel(selected, state, paused)}</Text>
            </View>
          ) : null}
          <Text style={styles.videoLaneLabel}>视频 {videoChannelIds.indexOf(channelId) + 1} · Channel {channelId}</Text>
        </Pressable>
      </View>
    );
  };
  return (
    <View style={styles.root}>
      <View style={styles.videoGrid}>
        {videoChannelIds.length === 0 ? (
          <VideoStage
            label={session.audio === null ? '未配置音视频' : selected === null ? '请选择录像' : paused ? '已暂停' : '仅音频播放'}
            showOverlay
            failed={false}
          />
        ) : (
          <View style={styles.mosaic}>
            {videoChannelIds.map((channelId) => {
              const parked = maximizedVideoChannelId !== null && channelId !== maximizedVideoChannelId;
              return (
                <View
                  key={channelId}
                  collapsable={false}
                  pointerEvents={parked ? 'none' : 'auto'}
                  accessibilityElementsHidden={parked}
                  importantForAccessibility={parked ? 'no-hide-descendants' : 'auto'}
                  style={videoLaneLayout(channelId)}>
                  {renderVideoLane(channelId)}
                </View>
              );
            })}
          </View>
        )}
      </View>
      <View pointerEvents="none" style={styles.bottomScrimSoft} />
      <View pointerEvents="none" style={styles.bottomScrimStrong} />
      <TopBar title="云录像" onBack={leave} backAccessibilityLabel="Ti Cloud Storage Back">
        <View style={styles.barActions}>
          <OutlineButton
            label="选择录像"
            onPress={() => setShowRanges(true)}
            accessibilityLabel="Ti Cloud Storage Recordings"
            compact
            disabled={!ready}
          />
        </View>
      </TopBar>
      <RawDumpStageControl
        capturing={rawDumpCapturing}
        uploadPending={rawDumpUploadPending}
        busy={rawDumpBusy || uploadingLogs}
        accessibilityLabel="Ti Cloud Storage Raw Dump"
        disabled={selected === null}
        onPress={() => void toggleRawDump()}
      />
      {selectedVideoChannelId !== null ? (
        <Pressable
          accessibilityRole="button"
          accessibilityLabel={maximizedVideoChannelId === selectedVideoChannelId ? '返回宫格' : '放大视频'}
          testID={maximizedVideoChannelId === selectedVideoChannelId ? 'cloud-video-grid-restore' : 'cloud-video-maximize'}
          onPress={() => setMaximizedVideoChannelId((current) => current === selectedVideoChannelId ? null : selectedVideoChannelId)}
          style={[styles.maximizeButton, {top: insets.top + 76}]}>
          <Text style={styles.maximizeButtonText}>{maximizedVideoChannelId === selectedVideoChannelId ? '宫格' : '放大'}</Text>
        </Pressable>
      ) : null}
      <View style={[styles.bottomPanel, {paddingBottom: Math.max(insets.bottom, 0) + 24}]}>
        <Text
          style={styles.stageNotice}
          numberOfLines={2}
          accessible
          accessibilityLabel={`Ti Cloud Storage Status: ${status}`}>
          {status}
        </Text>
        <View testID="ti-cloud-storage-control-surface" collapsable={false} style={[styles.playbackConsole, compact ? styles.playbackConsoleCompact : styles.playbackConsoleWide]}>
        {selected !== null ? (
          <View style={styles.seekPanel}>
            <Text style={styles.seekTime}>{formatClock(seekTimeMs)}</Text>
            <Slider
              accessibilityLabel="Ti Cloud Storage Seek"
              minimumValue={0}
              maximumValue={1}
              value={seekProgress}
              minimumTrackTintColor={exampleTheme.primary}
              maximumTrackTintColor="#FFFFFF33"
              thumbTintColor={exampleTheme.primary}
              tapToSeek
              onValueChange={setSeekPreviewRatio}
              onSlidingComplete={seek}
              style={styles.seekSlider}
            />
            <Text style={styles.seekTime}>{formatClock(selected.endTimeMs)}</Text>
          </View>
        ) : null}
        <View style={styles.controls}>
          <StageControlButton
            playbackProfile
            compactPlayback={compact}
            label={compact ? '音' : (muted || speed !== TiCloudStorageReplaySpeed.x1 ? '恢复声音' : '静音')}
            onPress={toggleMuted}
            accessibilityLabel="Ti Cloud Storage Mute"
            tone="surface"
            selected={muted}
            disabled={selected === null || speed !== TiCloudStorageReplaySpeed.x1 || !session.hasAudio}
          />
          <TiCloudStorageSpeedButton
            label={speedLabels[speed]}
            compact={compact}
            onPress={cycleSpeed}
            accessibilityLabel="Ti Cloud Storage Speed"
            disabled={selected === null}
          />
          <StageControlButton
            playbackProfile
            compactPlayback={compact}
            label={compact ? (paused ? '▶' : 'Ⅱ') : (paused ? '继续播放' : '暂停播放')}
            onPress={togglePause}
            accessibilityLabel="Ti Cloud Storage Pause Resume"
            disabled={selected === null}
          />
          <PlaybackActionMenu
            accessibilityLabel="Ti Cloud Storage More"
            actions={[
              ...(videoChannelIds.length > 0 ? [
                {label: recording ? '停止本地保存' : `开始本地保存 · ${selectedVideoChannelId ?? ''}`, accessibilityLabel: 'Ti Cloud Storage Recording', disabled: selected === null || busy || (!recording && !selectedVideoReady), onPress: () => void toggleRecording()},
                {label: `截图 · ${selectedVideoChannelId ?? ''}`, accessibilityLabel: 'Ti Cloud Storage Snapshot', disabled: selected === null || busy || !selectedVideoReady, onPress: () => void snapshot()},
                {label: '保存到系统相册', accessibilityLabel: 'Ti Cloud Storage Save Gallery', disabled: !latestMedia || busy, onPress: () => void saveLatest()},
              ] : []),
              {label: uploadingLogs ? '上传中…' : '上传日志', accessibilityLabel: 'Ti Cloud Storage Upload Logs', disabled: uploadingLogs, onPress: uploadLogs},
            ]}
          />
        </View>
        </View>
      </View>
      <Modal transparent visible={showRanges} animationType="slide" onRequestClose={() => setShowRanges(false)}>
        <View style={styles.modalBackdrop}>
          <Pressable accessibilityRole="button" accessibilityLabel="Ti Cloud Storage Cancel Recordings" onPress={() => setShowRanges(false)} style={styles.modalDismissScrim} />
          <View
            style={[styles.sheet, auxiliaryWide ? styles.sheetWide : styles.sheetCompact]}
            testID="ti-cloud-storage-recordings-sheet"
            accessibilityLabel="Ti Cloud Storage Recordings Sheet"
            accessible>
            <View
              style={styles.sheetHandle}
              testID="ti-cloud-storage-sheet-handle"
              accessibilityLabel="Ti Cloud Storage Sheet Handle"
              accessible
            />
            <View style={styles.sheetHeader}>
              <View style={styles.sheetHeading}>
                <Text style={styles.sheetTitle}>{selectedDay}</Text>
                <Text style={styles.sheetSubtitle}>自然日按 {TI_CLOUD_STORAGE_TIME_ZONE} 查询</Text>
              </View>
              <OutlineButton
                label="刷新"
                onPress={() => {
                  void queryMonth(visibleMonth);
                  void query(selectedDay);
                }}
                accessibilityLabel="Ti Cloud Storage Query"
                compact
                busy={busy}
              />
              <OutlineButton
                label="关闭"
                onPress={() => setShowRanges(false)}
                accessibilityLabel="Ti Cloud Storage Close Recordings"
                compact
              />
            </View>
            <Text
              accessible
              accessibilityLiveRegion="polite"
              accessibilityLabel={`Ti Cloud Storage Recordings State ${recordingsState}: ${recordingsStateMessage}`}
              testID="ti-cloud-storage-recordings-state"
              style={[styles.recordingsStateText, recordingsState === 'error' ? styles.recordingsStateError : null]}>
              {recordingsStateMessage}
            </Text>
            <ScrollView
              testID="ti-cloud-storage-recordings-scroll"
              accessibilityLabel="Ti Cloud Storage Recordings Scroll"
              contentContainerStyle={[styles.recordingsBody, auxiliaryWide ? styles.recordingsBodyWide : null]}
              showsVerticalScrollIndicator>
            <View style={styles.monthPanel}>
              <View style={styles.monthHeader}>
                <OutlineButton
                  label="上个月"
                  onPress={() => {
                    const month = shiftMonth(visibleMonth, -1);
                    setVisibleMonth(month);
                    void queryMonth(month);
                  }}
                  accessibilityLabel="Ti Cloud Storage Previous Month"
                  compact
                />
                <Text style={styles.monthTitle}>{visibleMonth}</Text>
                <OutlineButton
                  label="下个月"
                  onPress={() => {
                    const month = shiftMonth(visibleMonth, 1);
                    setVisibleMonth(month);
                    void queryMonth(month);
                  }}
                  accessibilityLabel="Ti Cloud Storage Next Month"
                  compact
                />
              </View>
              <ScrollView horizontal showsHorizontalScrollIndicator accessibilityLabel="Ti Cloud Storage Calendar Horizontal Scroll">
              <View style={styles.calendarCanvas}>
              <View style={styles.weekHeader}>
                {['日', '一', '二', '三', '四', '五', '六'].map((label) => (
                  <Text key={label} style={styles.weekLabel}>{label}</Text>
                ))}
              </View>
              <View style={styles.calendarGrid}>
                {monthCells(visibleMonth).map((date, index) => date === null ? (
                  <View key={`blank-${index}`} style={styles.dayCell} />
                ) : (
                  <Pressable
                    key={date}
                    accessibilityRole="button"
                    accessibilityLabel={`Ti Cloud Storage Day ${date}`}
                    accessibilityHint={recordingDays.has(date) ? '有录像' : '无录像'}
                    accessibilityState={{selected: selectedDay === date, disabled: !recordingDays.has(date)}}
                    disabled={!recordingDays.has(date)}
                    onPress={() => {
                      setSelectedDay(date);
                      void query(date);
                    }}
                    style={[
                      styles.dayCell,
                      recordingDays.has(date) ? styles.dayAvailable : styles.dayUnavailable,
                      selectedDay === date ? styles.daySelected : null,
                    ]}>
                    <Text style={selectedDay === date ? styles.dayTextSelected : styles.dayText}>
                      {Number(date.slice(-2))}
                    </Text>
                    <View style={[styles.dayStateDot, recordingDays.has(date) ? (selectedDay === date ? styles.dayStateDotSelected : styles.dayStateDotAvailable) : null]} />
                  </Pressable>
                ))}
              </View>
              </View>
              </ScrollView>
              {monthLoading ? <StatusText>正在加载月份…</StatusText> : null}
              {monthError ? (
                <Pressable accessibilityRole="button" onPress={() => void queryMonth(visibleMonth)}>
                  <Text style={styles.monthError}>{monthError}，点此重试</Text>
                </Pressable>
              ) : null}
            </View>
            <View style={styles.rangeList}>
              {ranges.length === 0 ? (
                <View accessibilityLabel={`Ti Cloud Storage Recordings ${recordingsState}`} accessible><StatusText>{status}</StatusText></View>
              ) : (
                ranges.map((range) => (
                  <View key={`${range.startTimeMs}-${range.endTimeMs}`} style={styles.range}>
                    <Pressable
                      accessibilityRole="button"
                      accessibilityLabel={`Ti Cloud Storage Play ${range.startTimeMs}`}
                      onPress={() => play(range)}
                      style={styles.rangeText}
                    >
                      <Text style={styles.rangeTitle}>
                        {formatClock(range.startTimeMs)} — {formatClock(range.endTimeMs)}
                      </Text>
                      <Text style={styles.rangeMeta}>{formatDuration(range.endTimeMs - range.startTimeMs)}</Text>
                    </Pressable>
                    <OutlineButton
                      label={exportingRangeStartMs === range.startTimeMs ? '下载中…' : '下载'}
                      onPress={() => void exportRange(range)}
                      accessibilityLabel={`Ti Cloud Storage Export ${range.startTimeMs}`}
                      compact
                      disabled={busy}
                    />
                  </View>
                ))
              )}
            </View>
            </ScrollView>
          </View>
        </View>
      </Modal>
    </View>
  );
}

function TiCloudStorageSpeedButton({
  label,
  accessibilityLabel,
  onPress,
  disabled,
  compact,
}: {
  label: string;
  accessibilityLabel: string;
  onPress: () => void;
  disabled?: boolean;
  compact?: boolean;
}) {
  return (
    <Pressable
      accessible
      accessibilityRole="button"
      accessibilityLabel={accessibilityLabel}
      importantForAccessibility="yes"
      collapsable={false}
      disabled={disabled}
      onPress={onPress}
      style={[styles.speedControl, compact ? styles.compactSpeedControl : null, disabled ? styles.controlDisabled : null]}
    >
      <Text numberOfLines={1} maxFontSizeMultiplier={1.25} style={styles.speedControlText}>{label}</Text>
    </Pressable>
  );
}

type TiCloudStorageCallbacks = {
  onStatus: (message: string) => void;
  onTime: (value: number) => void;
  onVideoState: (channelId: number, value: TiCloudStorageVideoOutputState) => void;
};

export class TiCloudStorageExampleSession {
  readonly tiCloudStorage: TiCloudStorage;
  replay: TiCloudStorageReplay;
  audio: TiCloudStorageAudioOutput | null;
  readonly videos = new Map<number, TiCloudStorageVideoOutput>();
  readonly media: MediaSelection;
  selectedVideoChannelId: number | null;
  private callbacks: TiCloudStorageCallbacks = {
    onStatus: () => {},
    onTime: () => {},
    onVideoState: () => {},
  };
  private readonly videoStates = new Map<number, TiCloudStorageVideoOutputState>();
  private audioState: TiCloudStorageAudioOutputState = TiCloudStorageAudioOutputState.idle;
  private readonly unavailableVideoChannels = new Set<number>();
  private audioAvailable: boolean;
  private playbackStarted = false;
  private preferredSpeed: TiCloudStorageReplaySpeed = TiCloudStorageReplaySpeed.x1;
  private muted = false;
  private completionReported = false;
  private task: TiCloudStorageRecordingTask | null = null;
  private rawDump: TiRawDump | null = null;
  private rawDumpUploadPending = false;
  private exportTask: TiCloudStorageExportTask | null = null;
  private latestMedia: TiCloudStorageMediaFile | null = null;
  private latestMediaTargetId: number | null = null;
  private recordingTargetId: number | null = null;
  private snapshotPromise: Promise<TiCloudStorageFileResult> | null = null;
  private readonly pendingQueries = new Set<Promise<unknown>>();
  private closed = false;
  private startPromise: Promise<number> | null = null;
  private closePromise: Promise<void> | null = null;

  constructor(private readonly config: ExampleConfig) {
    this.media = parseCloudStorageChannelIds(config);
    this.audio = this.media.audio === null ? null : new TiCloudStorageAudioOutput();
    this.audioAvailable = this.audio !== null;
    for (const channelId of this.media.videos) {
      this.videos.set(channelId, new TiCloudStorageVideoOutput());
      this.videoStates.set(channelId, TiCloudStorageVideoOutputState.idle);
    }
    this.selectedVideoChannelId = this.media.videos[0] ?? null;
    this.tiCloudStorage = new TiCloudStorage(config.tiCloudStorageToken);
    this.replay = this.tiCloudStorage.createReplay();
  }

  get hasLatestMedia(): boolean {
    return this.latestMedia !== null;
  }

  get hasAudio(): boolean {
    return this.audioAvailable;
  }

  get hasPlayableOutput(): boolean {
    return this.audioAvailable || this.media.videos.some(
      (channelId) => !this.unavailableVideoChannels.has(channelId),
    );
  }

  setCallbacks(callbacks: TiCloudStorageCallbacks): void {
    this.callbacks = callbacks;
  }

  start(): Promise<number> {
    return (this.startPromise ??= this.startOnce());
  }

  private async startOnce(): Promise<number> {
    const code = await TiCloudStorage.init({
      appId: this.config.appId,
      endpoint: this.config.endpoint,
      consoleLogEnabled: this.config.consoleLogEnabled,
    });
    if (code !== 0) return code;
    if (this.closed) return 6001;
    return this.attachPlaybackGraph(false);
  }

  private attachPlaybackGraph(requireAllOutputs: boolean): number {
    this.replay.onTimeChanged = (value) => {
      if (!this.closed) this.callbacks.onTime(value);
    };
    this.replay.onError = (value) => {
      if (!this.closed) this.callbacks.onStatus(`回放失败 ${value}`);
    };
    this.replay.onRecordingGap = (gap) => {
      if (!this.closed) this.callbacks.onStatus(`回放缺口 ${gap.range.startTimeMs}-${gap.range.endTimeMs}`);
    };
    let firstAttachError = 0;
    for (const [channelId, output] of this.videos) {
      output.onStateChanged = (value) => {
        if (this.closed) return;
        this.videoStates.set(channelId, value);
        if (value === TiCloudStorageVideoOutputState.failed) this.unavailableVideoChannels.add(channelId);
        this.callbacks.onVideoState(channelId, value);
        this.publishCompletionIfReady();
      };
      output.onError = (value) => {
        if (this.closed) return;
        this.videoStates.set(channelId, TiCloudStorageVideoOutputState.failed);
        this.unavailableVideoChannels.add(channelId);
        this.callbacks.onVideoState(channelId, TiCloudStorageVideoOutputState.failed);
        this.callbacks.onStatus(`视频 Channel ${channelId} 输出失败 ${value}`);
        this.publishCompletionIfReady();
      };
      const videoCode = output.attach(this.replay, channelId);
      if (videoCode !== 0) {
        if (firstAttachError === 0) firstAttachError = videoCode;
        this.videoStates.set(channelId, TiCloudStorageVideoOutputState.failed);
        this.unavailableVideoChannels.add(channelId);
        this.callbacks.onVideoState(channelId, TiCloudStorageVideoOutputState.failed);
      }
    }
    let audioCode = 0;
    if (this.audio !== null && this.media.audio !== null) {
      this.audio.onStateChanged = (value) => {
        if (this.closed) return;
        this.audioState = value;
        if (value === TiCloudStorageAudioOutputState.failed) this.audioAvailable = false;
        this.publishCompletionIfReady();
      };
      this.audio.onError = (value) => {
        if (this.closed) return;
        this.audioState = TiCloudStorageAudioOutputState.failed;
        this.audioAvailable = false;
        this.callbacks.onStatus(`音频输出失败 ${value}`);
        this.publishCompletionIfReady();
      };
      audioCode = this.audio.attach(this.replay, this.media.audio);
      if (audioCode !== 0) {
        if (firstAttachError === 0) firstAttachError = audioCode;
        this.audioState = TiCloudStorageAudioOutputState.failed;
        this.audioAvailable = false;
        this.callbacks.onStatus(`音频输出绑定失败 ${audioCode}`);
      }
    }
    return requireAllOutputs ? firstAttachError : 0;
  }

  query(startTimeMs: number, endTimeMs: number): Promise<TiCloudStorageRecordingRangesResult> {
    if (this.closed) return Promise.resolve({code: 6001, recordings: []});
    const operation = this.tiCloudStorage.listRecordings(startTimeMs, endTimeMs);
    this.pendingQueries.add(operation);
    void operation.finally(() => this.pendingQueries.delete(operation));
    return operation;
  }

  queryDays(startDate: string, endDate: string, timeZoneId: string): Promise<{code: number; days: readonly TiCloudStorageRecordingDay[]}> {
    if (this.closed) return Promise.resolve({code: 6001, days: []});
    const operation = this.tiCloudStorage.listRecordingDays(startDate, endDate, timeZoneId);
    this.pendingQueries.add(operation);
    void operation.finally(() => this.pendingQueries.delete(operation));
    return operation;
  }

  play(range: TiCloudStorageRecordingRange): number {
    if (this.playbackStarted) {
      const stopCode = this.replay.stop();
      if (stopCode !== 0) return stopCode;
      const recreateCode = this.recreatePlaybackGraph();
      if (recreateCode !== 0) return recreateCode;
    }
    this.completionReported = false;
    this.audioState = this.audioAvailable ? TiCloudStorageAudioOutputState.idle : TiCloudStorageAudioOutputState.failed;
    for (const channelId of this.media.videos) {
      this.videoStates.set(
        channelId,
        this.unavailableVideoChannels.has(channelId)
          ? TiCloudStorageVideoOutputState.failed
          : TiCloudStorageVideoOutputState.idle,
      );
    }
    const code = this.replay.play(range.startTimeMs, range.endTimeMs);
    if (code === 0) this.playbackStarted = true;
    return code;
  }

  private recreatePlaybackGraph(): number {
    const audioDetachCode = this.audio?.detach() ?? 0;
    if (audioDetachCode !== 0) return audioDetachCode;
    for (const output of this.videos.values()) {
      const detachCode = output.detach();
      if (detachCode !== 0) return detachCode;
    }
    const audioDisposeCode = this.audio?.dispose() ?? 0;
    if (audioDisposeCode !== 0) return audioDisposeCode;
    for (const output of this.videos.values()) {
      const disposeCode = output.dispose();
      if (disposeCode !== 0) return disposeCode;
    }
    const replayDisposeCode = this.replay.dispose();
    if (replayDisposeCode !== 0) return replayDisposeCode;

    this.replay = this.tiCloudStorage.createReplay();
    this.audio = this.media.audio === null ? null : new TiCloudStorageAudioOutput();
    this.videos.clear();
    for (const channelId of this.media.videos) {
      this.videos.set(channelId, new TiCloudStorageVideoOutput());
      this.videoStates.set(channelId, TiCloudStorageVideoOutputState.idle);
    }
    this.unavailableVideoChannels.clear();
    this.audioAvailable = this.audio !== null;
    const attachCode = this.attachPlaybackGraph(true);
    if (attachCode !== 0) return attachCode;
    const speedCode = this.replay.setSpeed(this.preferredSpeed);
    if (speedCode !== 0) return speedCode;
    return this.audio?.setVolume(this.muted ? 0 : 100) ?? 0;
  }
  setSpeed(value: TiCloudStorageReplaySpeed): number {
    const code = this.replay.setSpeed(value);
    if (code === 0) this.preferredSpeed = value;
    return code;
  }

  setMuted(value: boolean): number {
    const code = this.audio?.setVolume(value ? 0 : 100) ?? 6001;
    if (code === 0) this.muted = value;
    return code;
  }

  async toggleRawDump(): Promise<{capturing: boolean; status: string; upload: boolean}> {
    if (this.rawDumpUploadPending) {
      return {capturing: false, status: '诊断数据已保留 · 正在重试上传', upload: true};
    }
    if (this.rawDump !== null) {
      const result = await this.rawDump.stop();
      if (!result.success || result.data === null) {
        return {capturing: true, status: `诊断抓取停止失败 · #${result.code ?? 0}`, upload: false};
      }
      this.rawDump = null;
      this.rawDumpUploadPending = true;
      return {capturing: false, status: `诊断抓取完成 · ${result.data.captureId}`, upload: true};
    }
    if (!this.playbackStarted) {
      return {capturing: false, status: '诊断抓取失败 · 回放未就绪', upload: false};
    }
    const result = await this.replay.startRawDump({
      audioChannelIds: this.media.audio === null ? [] : [this.media.audio],
      videoChannelIds: this.media.videos,
    });
    if (!result.success || result.data === null) {
      return {capturing: false, status: `诊断抓取失败 · #${result.code ?? 0}`, upload: false};
    }
    this.rawDump = result.data;
    return {capturing: true, status: '正在抓取诊断数据 · 再次点击结束并上传日志', upload: false};
  }

  finishRawDumpUpload(success: boolean): void {
    if (success) this.rawDumpUploadPending = false;
  }

  isRawDumpUploadPending(): boolean { return this.rawDumpUploadPending; }

  selectVideo(channelId: number): void {
    if (this.videos.has(channelId)) this.selectedVideoChannelId = channelId;
  }

  private publishCompletionIfReady(): void {
    if (this.completionReported) return;
    const audioCompleted = this.audio === null || this.audioState === TiCloudStorageAudioOutputState.completed;
    const videosCompleted = this.media.videos.every((channelId) =>
      this.videoStates.get(channelId) === TiCloudStorageVideoOutputState.completed);
    if (!audioCompleted || !videosCompleted) return;
    this.completionReported = true;
    this.callbacks.onStatus('播放完成');
  }

  beginRecording(): number {
    const channelId = this.selectedVideoChannelId;
    if (channelId === null) return 6001;
    const result = this.replay.startRecording({
      videoChannelId: channelId,
      audioChannelId: this.media.audio ?? undefined,
    });
    if (result.success && result.data !== null) {
      this.task = result.data;
      this.recordingTargetId = channelId;
    }
    return result.success ? 0 : (result.code ?? 6123);
  }

  async finishRecording(): Promise<TiCloudStorageFileResult> {
    const task = this.task;
    this.task = null;
    if (task === null) return {message: '没有活动保存任务', file: null};
    const result = await task.stop();
    if (!result.success || result.data === null) return {message: `录像保存失败 ${result.code}`, file: null};
    await this.replaceLatest(result.data);
    this.latestMediaTargetId = this.recordingTargetId;
    this.recordingTargetId = null;
    return {message: '边播边录完成', file: result.data};
  }

  async exportRange(range: TiCloudStorageRecordingRange, onProgress: (value: number) => void): Promise<TiCloudStorageFileResult> {
    const channelId = this.selectedVideoChannelId;
    if (channelId === null) return {message: '请先选择视频', file: null};
    const observedGaps: Array<{range: TiCloudStorageRecordingRange}> = [];
    const started = this.tiCloudStorage.exportRecording(
      {
        startTimeMs: range.startTimeMs,
        endTimeMs: range.endTimeMs,
        videoChannelId: channelId,
        audioChannelId: this.media.audio ?? undefined,
      },
      {
        onProgress,
        onProgressDetail: (progress) => onProgress(progress.fraction),
        onRecordingGap: (gap) => observedGaps.push(gap),
      },
    );
    if (!started.success || started.data === null) return {message: `下载启动失败 ${started.code}`, file: null};
    this.exportTask = started.data;
    try {
      const outcome = await started.data.completion;
      if (outcome.code !== 0 || outcome.file === null || outcome.report === null)
        return {message: `下载失败 ${outcome.code}`, file: null};
      await this.replaceLatest(outcome.file);
      this.latestMediaTargetId = channelId;
      return {
        message: `范围下载完成 · 覆盖 ${outcome.report.coveredDurationMs}ms · 缺口 ${observedGaps.length}`,
        file: outcome.file,
      };
    } finally {
      if (this.exportTask === started.data) this.exportTask = null;
    }
  }

  async snapshot(): Promise<TiCloudStorageFileResult> {
    const channelId = this.selectedVideoChannelId;
    const video = channelId === null ? null : this.videos.get(channelId) ?? null;
    if (video === null) return {message: '请先选择视频', file: null};
    const operation = (async (): Promise<TiCloudStorageFileResult> => {
      const deadline = Date.now() + snapshotRetryTimeoutMs;
      while (true) {
        const result = await video.takeSnapshot();
        if (result.success && result.data !== null) {
          await this.replaceLatest(result.data);
          this.latestMediaTargetId = channelId;
          return {message: '截图完成', file: result.data};
        }
        if (result.code !== TI_CLOUD_STORAGE_ERROR_NO_FRAME || Date.now() >= deadline) {
          return {message: `截图失败 ${result.code}`, file: null};
        }
        await new Promise<void>((resolve) => setTimeout(resolve, snapshotRetryIntervalMs));
      }
    })();
    this.snapshotPromise = operation;
    try {
      return await operation;
    } finally {
      if (this.snapshotPromise === operation) this.snapshotPromise = null;
    }
  }

  async saveLatest(): Promise<string> {
    const file = this.latestMedia;
    if (file === null) return '没有可保存的文件';
    if (!await prepareGalleryWritePermission()) return '保存失败 6024';
    const result = await file.moveToGallery(
      galleryFileName('durationMs' in file ? 'mp4' : 'jpg', this.latestMediaTargetId ?? undefined),
    );
    if (!result.success) return `保存失败 ${result.code}`;
    if (this.latestMedia === file) this.latestMedia = null;
    return '已保存到系统相册';
  }

  close(): Promise<void> {
    return (this.closePromise ??= this.closeOnce());
  }

  private async replaceLatest(file: TiCloudStorageMediaFile): Promise<void> {
    const previous = this.latestMedia;
    this.latestMedia = file;
    if (previous !== null && previous !== file) await previous.delete();
  }

  private async closeOnce(): Promise<void> {
    this.closed = true;
    if (this.startPromise !== null) await this.startPromise;
    if (this.rawDump !== null) {
      await this.rawDump.stop();
      this.rawDump = null;
    }
    this.rawDumpUploadPending = false;
    if (this.task !== null) {
      const task = this.task;
      this.task = null;
      const result = await task.stop();
      if (result.data !== null) await result.data.delete();
    }
    if (this.exportTask !== null) {
      const result = await this.exportTask.stop();
      if (result.data !== null) await result.data.delete();
    }
    if (this.snapshotPromise !== null) await this.snapshotPromise;
    if (this.pendingQueries.size > 0) await Promise.allSettled([...this.pendingQueries]);
    if (this.latestMedia !== null) await this.latestMedia.delete();
    this.latestMedia = null;
    this.replay.stop();
    this.audio?.detach();
    for (const output of this.videos.values()) output.detach();
    this.audio?.dispose();
    for (const output of this.videos.values()) output.dispose();
    this.replay.dispose();
    this.tiCloudStorage.dispose();
    TiCloudStorage.shutdown();
  }
}

type TiCloudStorageFileResult = {message: string; file: TiCloudStorageMediaFile | null};

const TI_CLOUD_STORAGE_TIME_ZONE = 'Asia/Shanghai';

function shanghaiDate(value: number): string {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: TI_CLOUD_STORAGE_TIME_ZONE, year: 'numeric', month: '2-digit', day: '2-digit',
  }).format(value);
}

function shanghaiDayBounds(date: string): [number, number] {
  const start = Date.parse(`${date}T00:00:00+08:00`);
  return [start, start + 24 * 60 * 60 * 1000];
}

function monthBounds(month: string): [string, string] {
  const [year, monthNumber] = month.split('-').map(Number);
  const last = new Date(Date.UTC(year, monthNumber, 0)).getUTCDate();
  return [`${month}-01`, `${month}-${String(last).padStart(2, '0')}`];
}

function shiftMonth(month: string, delta: number): string {
  const [year, monthNumber] = month.split('-').map(Number);
  const value = new Date(Date.UTC(year, monthNumber - 1 + delta, 1));
  return `${value.getUTCFullYear()}-${String(value.getUTCMonth() + 1).padStart(2, '0')}`;
}

function monthCells(month: string): readonly (string | null)[] {
  const [year, monthNumber] = month.split('-').map(Number);
  const firstWeekday = new Date(Date.UTC(year, monthNumber - 1, 1)).getUTCDay();
  const last = new Date(Date.UTC(year, monthNumber, 0)).getUTCDate();
  const cells = [
    ...Array<string | null>(firstWeekday).fill(null),
    ...Array.from({length: last}, (_, index) => `${month}-${String(index + 1).padStart(2, '0')}`),
  ];
  return [...cells, ...Array<string | null>(42 - cells.length).fill(null)];
}

function stageLabel(range: TiCloudStorageRecordingRange | null, state: TiCloudStorageVideoOutputState, paused: boolean): string {
  if (range === null) return '请选择录像';
  if (paused || state === TiCloudStorageVideoOutputState.paused) return '已暂停';
  if (state === TiCloudStorageVideoOutputState.buffering) return '缓冲中';
  if (state === TiCloudStorageVideoOutputState.completed) return '播放完成';
  if (state === TiCloudStorageVideoOutputState.failed) return '播放失败';
  return '录像播放中';
}

function formatClock(value: number): string {
  return new Intl.DateTimeFormat('zh-CN', {
    timeZone: TI_CLOUD_STORAGE_TIME_ZONE, hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false,
  }).format(value);
}

function formatDuration(value: number): string {
  const seconds = Math.floor(value / 1000);
  return `时长 ${String(Math.floor(seconds / 60)).padStart(2, '0')}:${String(seconds % 60).padStart(2, '0')}`;
}

const styles = StyleSheet.create({
  root: {
    flex: 1,
    backgroundColor: exampleTheme.videoBackground,
  },
  barActions: {flexDirection: 'row', alignItems: 'center', gap: 8},
  video: {width: '100%', height: '100%'},
  videoGrid: {flex: 1, backgroundColor: exampleTheme.videoBackground},
  mosaic: {flex: 1, position: 'relative'},
  videoLaneFill: {position: 'absolute', left: 0, right: 0, top: 0, bottom: 0},
  videoLanePrimaryCompact: {position: 'absolute', left: 0, right: 0, top: 0, bottom: '33.333%'},
  videoLanePrimaryWide: {position: 'absolute', left: 0, right: '33.333%', top: 0, bottom: 0},
  videoLaneSecondaryCompactSingle: {position: 'absolute', left: 0, right: 0, top: '66.667%', bottom: 0},
  videoLaneSecondaryCompactLeading: {position: 'absolute', left: 0, width: '50%', top: '66.667%', bottom: 0},
  videoLaneSecondaryCompactTrailing: {position: 'absolute', left: '50%', right: 0, top: '66.667%', bottom: 0},
  videoLaneSecondaryWideSingle: {position: 'absolute', left: '66.667%', right: 0, top: 0, bottom: 0},
  videoLaneSecondaryWideLeading: {position: 'absolute', left: '66.667%', right: 0, top: 0, height: '50%'},
  videoLaneSecondaryWideTrailing: {position: 'absolute', left: '66.667%', right: 0, top: '50%', bottom: 0},
  videoLaneParked: {position: 'absolute', left: -2, top: -2, width: 1, height: 1, opacity: 0},
  videoTile: {flex: 1, position: 'relative', overflow: 'hidden', backgroundColor: '#252525', borderWidth: 2, borderColor: 'transparent'},
  videoTileContent: {flex: 1, position: 'relative'},
  videoTileSelected: {borderColor: '#659287'},
  videoLaneOverlay: {position: 'absolute', left: 0, right: 0, top: 0, bottom: 0, alignItems: 'center', justifyContent: 'center', backgroundColor: '#252525'},
  videoLaneStatus: {color: '#CCFFFFFF', fontSize: 13},
  videoLaneLabel: {position: 'absolute', left: 8, top: 8, zIndex: 1, elevation: 1, color: '#FFFFFF', backgroundColor: '#75000000', borderRadius: 10, paddingHorizontal: 8, paddingVertical: 4, fontSize: 11},
  maximizeButton: {position: 'absolute', right: 8, zIndex: 11, elevation: 11, minWidth: Platform.OS === 'ios' ? 44 : 48, minHeight: Platform.OS === 'ios' ? 44 : 48, alignItems: 'center', justifyContent: 'center', backgroundColor: '#75000000', borderRadius: 10, paddingHorizontal: 8, paddingVertical: 4},
  maximizeButtonText: {color: '#FFFFFF', fontSize: 11},
  bottomScrimSoft: {
    position: 'absolute',
    left: 0,
    right: 0,
    bottom: 150,
    height: 150,
    backgroundColor: 'rgba(0,0,0,0.18)',
  },
  bottomScrimStrong: {
    position: 'absolute',
    left: 0,
    right: 0,
    bottom: 0,
    height: 170,
    backgroundColor: 'rgba(0,0,0,0.42)',
  },
  bottomPanel: {
    position: 'absolute',
    left: 20,
    right: 20,
    bottom: 0,
    zIndex: 10,
    elevation: 10,
    gap: 12,
    alignItems: 'flex-end',
  },
  stageNotice: {
    maxWidth: 620,
    alignSelf: 'flex-start',
    borderRadius: 18,
    overflow: 'hidden',
    backgroundColor: 'rgba(0,0,0,0.46)',
    paddingHorizontal: 14,
    paddingVertical: 9,
    color: exampleTheme.foreground,
    fontSize: 13,
    fontWeight: '600',
  },
  seekPanel: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    paddingHorizontal: 8,
  },
  seekTime: {color: '#FFFFFFB3', fontSize: 12},
  seekSlider: {
    flex: 1,
    height: 32,
  },
  controls: {
    flexDirection: 'row',
    gap: 8,
    justifyContent: 'flex-end',
    alignItems: 'center',
  },
  playbackConsole: {
    width: '100%',
    maxWidth: 860,
    alignSelf: 'center',
    borderRadius: Platform.OS === 'ios' ? 12 : 20,
    backgroundColor: Platform.OS === 'ios' ? 'rgba(37,37,37,0.72)' : 'rgba(37,37,37,0.92)',
    padding: Platform.OS === 'ios' ? 4 : 8,
    gap: Platform.OS === 'ios' ? 6 : 8,
  },
  playbackConsoleCompact: {flexDirection: 'column'},
  playbackConsoleWide: {flexDirection: 'row', alignItems: 'center'},
  speedControl: {
    minWidth: 62,
    height: Platform.OS === 'ios' ? 44 : 48,
    minHeight: Platform.OS === 'ios' ? 44 : 48,
    borderRadius: Platform.OS === 'ios' ? 10 : 24,
    backgroundColor: 'rgba(37,37,37,0.92)',
    paddingHorizontal: 14,
    alignItems: 'center',
    justifyContent: 'center',
  },
  compactSpeedControl: {
    flex: 1,
    minWidth: 0,
    paddingHorizontal: 4,
  },
  speedControlText: {
    color: exampleTheme.foreground,
    fontSize: 14,
    fontWeight: '600',
  },
  controlDisabled: {
    opacity: 0.46,
  },
  modalBackdrop: {
    flex: 1,
    justifyContent: 'flex-end',
    backgroundColor: '#00000066',
  },
  modalDismissScrim: {position: 'absolute', left: 0, right: 0, top: 0, bottom: 0},
  sheet: {
    backgroundColor: exampleTheme.background,
    paddingTop: 8,
  },
  sheetCompact: {height: '88%', borderTopLeftRadius: 28, borderTopRightRadius: 28},
  sheetWide: {width: 900, maxWidth: '94%', height: '82%', alignSelf: 'center', marginBottom: 24, borderRadius: 28},
  sheetHandle: {
    alignSelf: 'center',
    width: 36,
    height: 4,
    borderRadius: 2,
    backgroundColor: '#D0C9BC',
    marginBottom: 10,
  },
  sheetHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    paddingHorizontal: 18,
    paddingBottom: 14,
    borderBottomWidth: 1,
    borderBottomColor: exampleTheme.inputBorder,
  },
  sheetHeading: {flex: 1, minWidth: 0},
  sheetTitle: {
    color: exampleTheme.textPrimary,
    fontSize: 16,
    fontWeight: '700',
  },
  sheetSubtitle: {color: exampleTheme.textSecondary, fontSize: 12},
  recordingsBody: {flexGrow: 1},
  recordingsBodyWide: {flexDirection: 'row', alignItems: 'flex-start'},
  recordingsStateText: {
    marginHorizontal: 18,
    marginTop: 10,
    borderRadius: 12,
    backgroundColor: 'rgba(101,146,135,0.14)',
    color: exampleTheme.textPrimary,
    fontSize: 13,
    fontWeight: '600',
    paddingHorizontal: 12,
    paddingVertical: 10,
  },
  recordingsStateError: {backgroundColor: 'rgba(176,64,64,0.14)', color: exampleTheme.failure},
  monthPanel: {flex: 1, minWidth: 0, gap: 8, paddingHorizontal: 18, paddingVertical: 12},
  monthHeader: {flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between'},
  monthTitle: {color: exampleTheme.textPrimary, fontSize: 15, fontWeight: '700'},
  weekHeader: {flexDirection: 'row'},
  weekLabel: {width: `${100 / 7}%`, textAlign: 'center', color: exampleTheme.textSecondary, fontSize: 11},
  calendarGrid: {flexDirection: 'row', flexWrap: 'wrap'},
  calendarCanvas: {minWidth: (Platform.OS === 'ios' ? 44 : 48) * 7},
  dayCell: {width: `${100 / 7}%`, minHeight: Platform.OS === 'ios' ? 44 : 48, paddingVertical: 4, alignItems: 'center', justifyContent: 'center', borderRadius: 12},
  dayAvailable: {backgroundColor: 'rgba(101,146,135,0.14)'},
  dayUnavailable: {opacity: 0.34},
  daySelected: {backgroundColor: exampleTheme.primary},
  dayText: {color: exampleTheme.textPrimary, fontSize: 12},
  dayTextSelected: {color: exampleTheme.foreground, fontSize: 12, fontWeight: '700'},
  dayStateDot: {width: 5, height: 5, marginTop: 3, borderRadius: 3, backgroundColor: 'transparent'},
  dayStateDotAvailable: {backgroundColor: exampleTheme.primary},
  dayStateDotSelected: {backgroundColor: exampleTheme.foreground},
  monthError: {color: exampleTheme.failure, textAlign: 'center', fontSize: 12},
  rangeList: {flexGrow: 1, padding: 16, gap: 8},
  range: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    borderRadius: 18,
    backgroundColor: exampleTheme.surface,
    borderWidth: 1,
    borderColor: exampleTheme.inputBorder,
    padding: 14,
  },
  rangeText: {flex: 1, gap: 4},
  rangeTitle: {
    color: exampleTheme.textPrimary,
    fontSize: 13,
    fontWeight: '600',
  },
  rangeMeta: {color: exampleTheme.textSecondary, fontSize: 12},
});
