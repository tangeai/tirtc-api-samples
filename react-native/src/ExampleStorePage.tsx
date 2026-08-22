import React, {useCallback, useEffect, useMemo, useRef, useState} from 'react';
import {
  Modal,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import Slider from '@react-native-community/slider';
import {useSafeAreaInsets} from 'react-native-safe-area-context';
import {
  TiRtcLogging,
  TiStore,
  TiStoreAudioOutput,
  TiStoreReplay,
  TiStoreReplaySpeed,
  TiStoreVideoOutput,
  TiStoreVideoOutputState,
  TiStoreVideoOutputView,
  type TiStoreExportTask,
  type TiStoreRecordingFile,
  type TiStoreRecordingDay,
  type TiStoreRecordingRange,
  type TiStoreRecordingRangesResult,
  type TiStoreRecordingTask,
  type TiStoreSnapshotFile,
} from 'tirtc-react-native';
import {useExampleLogUpload} from './ExampleLogUpload';
import {
  OutlineButton,
  StageControlButton,
  StatusText,
  TopBar,
  VideoStage,
  exampleTheme,
} from './ExampleUi';
import type {ExampleConfig} from './ExampleTypes';
import {galleryFileName, prepareGalleryWritePermission} from './ExampleSessionShared';

const speeds = [TiStoreReplaySpeed.x1, TiStoreReplaySpeed.x2, TiStoreReplaySpeed.x4, TiStoreReplaySpeed.x8] as const;
type StoreMediaFile = TiStoreRecordingFile | TiStoreSnapshotFile;

function newestFirstRecordingRanges(
  ranges: readonly TiStoreRecordingRange[],
): TiStoreRecordingRange[] {
  return [...ranges].sort(
    (left, right) => right.startTimeMs - left.startTimeMs || right.endTimeMs - left.endTimeMs,
  );
}

export function StoreScreen({config, onBack}: {config: ExampleConfig; onBack: () => void}) {
  const insets = useSafeAreaInsets();
  const session = useMemo(() => new StoreExampleSession(config), [config]);
  const [status, setStatus] = useState('正在初始化 TiStore');
  const [ranges, setRanges] = useState<readonly TiStoreRecordingRange[]>([]);
  const [selectedDay, setSelectedDay] = useState(() => shanghaiDate(Date.now()));
  const [visibleMonth, setVisibleMonth] = useState(() => shanghaiDate(Date.now()).slice(0, 7));
  const [recordingDays, setRecordingDays] = useState<ReadonlySet<string>>(() => new Set());
  const [monthLoading, setMonthLoading] = useState(false);
  const [monthError, setMonthError] = useState('');
  const [selected, setSelected] = useState<TiStoreRecordingRange | null>(null);
  const [currentTimeMs, setCurrentTimeMs] = useState<number | null>(null);
  const [videoState, setVideoState] = useState<TiStoreVideoOutputState>(TiStoreVideoOutputState.idle);
  const [ready, setReady] = useState(false);
  const [paused, setPaused] = useState(false);
  const [muted, setMuted] = useState(false);
  const [recording, setRecording] = useState(false);
  const [speed, setSpeed] = useState<TiStoreReplaySpeed>(TiStoreReplaySpeed.x1);
  const [busy, setBusy] = useState(false);
  const [showRanges, setShowRanges] = useState(true);
  const [latestMedia, setLatestMedia] = useState(false);
  const [seekPreviewRatio, setSeekPreviewRatio] = useState<number | null>(null);
  const mountedRef = useRef(true);
  const dayQueryGenerationRef = useRef(0);
  const monthQueryGenerationRef = useRef(0);
  const renderedClockSecondRef = useRef(-1);
  const {uploadingLogs, uploadLogs} = useExampleLogUpload(() => TiRtcLogging.upload());

  const query = useCallback(async (date: string) => {
    const generation = ++dayQueryGenerationRef.current;
    setBusy(true);
    setStatus('正在查询录像…');
    const result = await session.query(...shanghaiDayBounds(date));
    if (!mountedRef.current || generation !== dayQueryGenerationRef.current) return;
    setRanges(newestFirstRecordingRanges(result.recordings));
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
    const result = await session.queryDays(...monthBounds(month), STORE_TIME_ZONE);
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
      onVideoState: (value) => mounted && setVideoState(value),
    });
    session.start().then((code) => {
      if (!mounted) return;
      if (code === 0) {
        setReady(true);
        const today = shanghaiDate(Date.now());
        void queryMonth(today.slice(0, 7));
        void query(today);
      } else {
        setStatus(`TiStore 初始化失败 ${code}`);
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

  const leave = async () => {
    if (busy) return;
    setBusy(true);
    setReady(false);
    mountedRef.current = false;
    await new Promise<void>((resolve) => requestAnimationFrame(() => resolve()));
    await session.close();
    onBack();
  };

  const play = (range: TiStoreRecordingRange) => {
    const code = session.play(range);
    if (code === 0) {
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
    const next = speeds[(speeds.indexOf(speed) + 1) % speeds.length] ?? TiStoreReplaySpeed.x1;
    const code = session.replay.setSpeed(next);
    if (code === 0) {
      setSpeed(next);
    }
    setStatus(code === 0 ? `播放倍速：${next}` : `倍速设置失败 ${code}`);
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

  const exportRange = async (range: TiStoreRecordingRange) => {
    setBusy(true);
    setStatus('下载 0%');
    const result = await session.exportRange(range, (value) => {
      if (mountedRef.current) setStatus(`下载 ${Math.round(value * 100)}%`);
    });
    if (!mountedRef.current) return;
    setBusy(false);
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
  const showOverlay = selected === null || videoState !== TiStoreVideoOutputState.rendering;

  return (
    <View style={styles.root}>
      <VideoStage label={stageLabel(selected, videoState, paused)} showOverlay={showOverlay}>
        {ready ? <TiStoreVideoOutputView output={session.video} resizeMode="contain" style={styles.video} /> : null}
      </VideoStage>
      <View pointerEvents="none" style={styles.bottomScrimSoft} />
      <View pointerEvents="none" style={styles.bottomScrimStrong} />
      <TopBar title="云录像" onBack={() => void leave()} backAccessibilityLabel="TiStore Back">
        <View style={styles.barActions}>
          <OutlineButton
            label="选择录像"
            onPress={() => setShowRanges(true)}
            accessibilityLabel="TiStore Recordings"
            compact
            disabled={!ready}
          />
          <OutlineButton
            label={uploadingLogs ? '上传中…' : '上传日志'}
            onPress={uploadLogs}
            accessibilityLabel="TiStore Upload Logs"
            compact
            busy={uploadingLogs}
          />
        </View>
      </TopBar>
      <View style={[styles.bottomPanel, {paddingBottom: Math.max(insets.bottom, 0) + 24}]}>
        <Text style={styles.stageNotice} numberOfLines={2}>
          {status}
        </Text>
        {selected !== null ? (
          <View style={styles.seekPanel}>
            <Text style={styles.seekTime}>{formatClock(seekTimeMs)}</Text>
            <Slider
              accessibilityLabel="TiStore Seek"
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
          <StoreRoundButton
            symbol={recording ? '■' : '●'}
            label={recording ? '停止本地保存' : '开始本地保存'}
            onPress={() => void toggleRecording()}
            accessibilityLabel="TiStore Recording"
            disabled={selected === null || busy}
            active={recording}
          />
          <StoreRoundButton
            symbol="▣"
            label="截图"
            onPress={() => void snapshot()}
            accessibilityLabel="TiStore Snapshot"
            disabled={selected === null || busy}
          />
          <StoreRoundButton
            symbol="▧"
            label="保存到系统相册"
            onPress={() => void saveLatest()}
            accessibilityLabel="TiStore Save Gallery"
            disabled={!latestMedia || busy}
          />
          <StageControlButton
            label={muted || speed !== TiStoreReplaySpeed.x1 ? '恢复声音' : '静音'}
            onPress={toggleMuted}
            accessibilityLabel="TiStore Mute"
            tone="surface"
            disabled={selected === null || speed !== TiStoreReplaySpeed.x1}
          />
          <StoreSpeedButton
            label={speed}
            onPress={cycleSpeed}
            accessibilityLabel="TiStore Speed"
            disabled={selected === null}
          />
          <StageControlButton
            label={paused ? '继续播放' : '暂停播放'}
            onPress={togglePause}
            accessibilityLabel="TiStore Pause Resume"
            disabled={selected === null}
          />
        </View>
      </View>
      <Modal transparent visible={showRanges} animationType="slide" onRequestClose={() => setShowRanges(false)}>
        <View style={styles.modalBackdrop}>
          <View
            style={styles.sheet}
            testID="store-recordings-sheet"
            accessibilityLabel="TiStore Recordings Sheet"
            accessible>
            <View
              style={styles.sheetHandle}
              testID="store-sheet-handle"
              accessibilityLabel="TiStore Sheet Handle"
              accessible
            />
            <View style={styles.sheetHeader}>
              <View>
                <Text style={styles.sheetTitle}>{selectedDay}</Text>
                <Text style={styles.sheetSubtitle}>自然日按 {STORE_TIME_ZONE} 查询</Text>
              </View>
              <OutlineButton
                label="刷新"
                onPress={() => {
                  void queryMonth(visibleMonth);
                  void query(selectedDay);
                }}
                accessibilityLabel="TiStore Query"
                compact
                busy={busy}
              />
              <OutlineButton
                label="关闭"
                onPress={() => setShowRanges(false)}
                accessibilityLabel="TiStore Close Recordings"
                compact
              />
            </View>
            <View style={styles.monthPanel}>
              <View style={styles.monthHeader}>
                <OutlineButton
                  label="上个月"
                  onPress={() => {
                    const month = shiftMonth(visibleMonth, -1);
                    setVisibleMonth(month);
                    void queryMonth(month);
                  }}
                  accessibilityLabel="TiStore Previous Month"
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
                  accessibilityLabel="TiStore Next Month"
                  compact
                />
              </View>
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
                    accessibilityLabel={`TiStore Day ${date}`}
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
                    <Text style={selectedDay === date ? styles.dayStateTextSelected : styles.dayStateText}>
                      {recordingDays.has(date) ? '有录像' : '无录像'}
                    </Text>
                  </Pressable>
                ))}
              </View>
              {monthLoading ? <StatusText>正在加载月份…</StatusText> : null}
              {monthError ? (
                <Pressable accessibilityRole="button" onPress={() => void queryMonth(visibleMonth)}>
                  <Text style={styles.monthError}>{monthError}，点此重试</Text>
                </Pressable>
              ) : null}
            </View>
            <ScrollView contentContainerStyle={styles.rangeList}>
              {ranges.length === 0 ? (
                <StatusText>{status}</StatusText>
              ) : (
                ranges.map((range) => (
                  <View key={`${range.startTimeMs}-${range.endTimeMs}`} style={styles.range}>
                    <Pressable
                      accessibilityRole="button"
                      accessibilityLabel={`TiStore Play ${range.startTimeMs}`}
                      onPress={() => play(range)}
                      style={styles.rangeText}
                    >
                      <Text style={styles.rangeTitle}>
                        {formatClock(range.startTimeMs)} — {formatClock(range.endTimeMs)}
                      </Text>
                      <Text style={styles.rangeMeta}>{formatDuration(range.endTimeMs - range.startTimeMs)}</Text>
                    </Pressable>
                    <OutlineButton
                      label="下载"
                      onPress={() => void exportRange(range)}
                      accessibilityLabel={`TiStore Export ${range.startTimeMs}`}
                      compact
                      disabled={busy}
                    />
                  </View>
                ))
              )}
            </ScrollView>
          </View>
        </View>
      </Modal>
    </View>
  );
}

function StoreRoundButton({
  symbol,
  label,
  accessibilityLabel,
  onPress,
  disabled,
  active = false,
}: {
  symbol: string;
  label: string;
  accessibilityLabel: string;
  onPress: () => void;
  disabled?: boolean;
  active?: boolean;
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
      style={[styles.roundControl, active ? styles.roundControlActive : null, disabled ? styles.controlDisabled : null]}
    >
      <Text accessibilityElementsHidden style={styles.roundControlSymbol}>
        {symbol}
      </Text>
      <Text accessibilityElementsHidden style={styles.controlTooltip}>
        {label}
      </Text>
    </Pressable>
  );
}

function StoreSpeedButton({
  label,
  accessibilityLabel,
  onPress,
  disabled,
}: {
  label: string;
  accessibilityLabel: string;
  onPress: () => void;
  disabled?: boolean;
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
      style={[styles.speedControl, disabled ? styles.controlDisabled : null]}
    >
      <Text style={styles.speedControlText}>{label}</Text>
    </Pressable>
  );
}

type StoreCallbacks = {
  onStatus: (message: string) => void;
  onTime: (value: number) => void;
  onVideoState: (value: TiStoreVideoOutputState) => void;
};

class StoreExampleSession {
  readonly store: TiStore;
  readonly replay: TiStoreReplay;
  readonly audio = new TiStoreAudioOutput();
  readonly video = new TiStoreVideoOutput();
  private callbacks: StoreCallbacks = {
    onStatus: () => {},
    onTime: () => {},
    onVideoState: () => {},
  };
  private task: TiStoreRecordingTask | null = null;
  private exportTask: TiStoreExportTask | null = null;
  private latestMedia: StoreMediaFile | null = null;
  private snapshotPromise: Promise<StoreFileResult> | null = null;
  private readonly pendingQueries = new Set<Promise<unknown>>();
  private closed = false;
  private startPromise: Promise<number> | null = null;
  private closePromise: Promise<void> | null = null;

  constructor(private readonly config: ExampleConfig) {
    this.store = new TiStore(config.storeToken);
    this.replay = this.store.createReplay();
  }

  get hasLatestMedia(): boolean {
    return this.latestMedia !== null;
  }

  setCallbacks(callbacks: StoreCallbacks): void {
    this.callbacks = callbacks;
  }

  start(): Promise<number> {
    return (this.startPromise ??= this.startOnce());
  }

  private async startOnce(): Promise<number> {
    const code = await TiStore.init({
      appId: this.config.appId,
      endpoint: this.config.endpoint,
      consoleLogEnabled: this.config.consoleLogEnabled,
    });
    if (code !== 0) return code;
    if (this.closed) return 6001;
    this.store.onTokenExpired = () => this.callbacks.onStatus('Token 已过期');
    this.replay.onTimeChanged = (value) => this.callbacks.onTime(value);
    this.replay.onError = (value) => this.callbacks.onStatus(`回放失败 ${value}`);
    this.replay.onCompleted = () => this.callbacks.onVideoState(TiStoreVideoOutputState.completed);
    this.video.onStateChanged = (value) => this.callbacks.onVideoState(value);
    this.video.onError = (value) => this.callbacks.onStatus(`视频输出失败 ${value}`);
    this.audio.onError = (value) => this.callbacks.onStatus(`音频输出失败 ${value}`);
    const audioCode = this.audio.attach(this.replay, Number.parseInt(this.config.audioStreamId, 10) || 10);
    if (audioCode !== 0) return audioCode;
    return this.video.attach(this.replay, Number.parseInt(this.config.videoStreamId, 10) || 11);
  }

  query(startTimeMs: number, endTimeMs: number): Promise<TiStoreRecordingRangesResult> {
    if (this.closed) return Promise.resolve({code: 6001, recordings: []});
    const operation = this.store.listRecordings(startTimeMs, endTimeMs);
    this.pendingQueries.add(operation);
    void operation.finally(() => this.pendingQueries.delete(operation));
    return operation;
  }

  queryDays(startDate: string, endDate: string, timeZoneId: string): Promise<{code: number; days: readonly TiStoreRecordingDay[]}> {
    if (this.closed) return Promise.resolve({code: 6001, days: []});
    const operation = this.store.listRecordingDays(startDate, endDate, timeZoneId);
    this.pendingQueries.add(operation);
    void operation.finally(() => this.pendingQueries.delete(operation));
    return operation;
  }

  play(range: TiStoreRecordingRange): number {
    return this.replay.play(range.startTimeMs, range.endTimeMs);
  }
  setMuted(value: boolean): number {
    return this.audio.setVolume(value ? 0 : 100);
  }

  beginRecording(): number {
    const result = this.replay.startRecording({
      videoChannelId: Number.parseInt(this.config.videoStreamId, 10) || 11,
      audioChannelId: Number.parseInt(this.config.audioStreamId, 10) || 10,
    });
    if (result.success && result.data !== null) this.task = result.data;
    return result.success ? 0 : (result.code ?? 6123);
  }

  async finishRecording(): Promise<StoreFileResult> {
    const task = this.task;
    this.task = null;
    if (task === null) return {message: '没有活动保存任务', file: null};
    const result = await task.stop();
    if (!result.success || result.data === null) return {message: `录像保存失败 ${result.code}`, file: null};
    await this.replaceLatest(result.data);
    return {message: '边播边录完成', file: result.data};
  }

  async exportRange(range: TiStoreRecordingRange, onProgress: (value: number) => void): Promise<StoreFileResult> {
    const started = this.store.exportRecording(
      {
        startTimeMs: range.startTimeMs,
        endTimeMs: range.endTimeMs,
        videoChannelId: Number.parseInt(this.config.videoStreamId, 10) || 11,
        audioChannelId: Number.parseInt(this.config.audioStreamId, 10) || 10,
      },
      onProgress,
    );
    if (!started.success || started.data === null) return {message: `下载启动失败 ${started.code}`, file: null};
    this.exportTask = started.data;
    try {
      const result = await started.data.result;
      if (!result.success || result.data === null) return {message: `下载失败 ${result.code}`, file: null};
      await this.replaceLatest(result.data);
      return {message: '范围下载完成', file: result.data};
    } finally {
      if (this.exportTask === started.data) this.exportTask = null;
    }
  }

  async snapshot(): Promise<StoreFileResult> {
    const operation = (async (): Promise<StoreFileResult> => {
      const result = await this.video.takeSnapshot();
      if (!result.success || result.data === null) return {message: `截图失败 ${result.code}`, file: null};
      await this.replaceLatest(result.data);
      return {message: '截图完成', file: result.data};
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
      galleryFileName('durationMs' in file ? 'mp4' : 'jpg'),
    );
    if (!result.success) return `保存失败 ${result.code}`;
    if (this.latestMedia === file) this.latestMedia = null;
    return '已保存到系统相册';
  }

  close(): Promise<void> {
    return (this.closePromise ??= this.closeOnce());
  }

  private async replaceLatest(file: StoreMediaFile): Promise<void> {
    const previous = this.latestMedia;
    this.latestMedia = file;
    if (previous !== null && previous !== file) await previous.delete();
  }

  private async closeOnce(): Promise<void> {
    this.closed = true;
    if (this.startPromise !== null) await this.startPromise;
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
    this.audio.detach();
    this.video.detach();
    this.audio.dispose();
    this.video.dispose();
    this.replay.dispose();
    this.store.dispose();
    TiStore.shutdown();
  }
}

type StoreFileResult = {message: string; file: StoreMediaFile | null};

const STORE_TIME_ZONE = 'Asia/Shanghai';

function shanghaiDate(value: number): string {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: STORE_TIME_ZONE, year: 'numeric', month: '2-digit', day: '2-digit',
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
  return [
    ...Array<string | null>(firstWeekday).fill(null),
    ...Array.from({length: last}, (_, index) => `${month}-${String(index + 1).padStart(2, '0')}`),
  ];
}

function stageLabel(range: TiStoreRecordingRange | null, state: TiStoreVideoOutputState, paused: boolean): string {
  if (range === null) return '请选择录像';
  if (paused || state === TiStoreVideoOutputState.paused) return '已暂停';
  if (state === TiStoreVideoOutputState.buffering) return '缓冲中';
  if (state === TiStoreVideoOutputState.completed) return '播放完成';
  if (state === TiStoreVideoOutputState.failed) return '播放失败';
  return '录像播放中';
}

function formatClock(value: number): string {
  return new Intl.DateTimeFormat('zh-CN', {
    timeZone: STORE_TIME_ZONE, hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false,
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
    width: '100%',
    maxWidth: 620,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    borderRadius: 18,
    padding: 12,
    backgroundColor: 'rgba(37,37,37,0.92)',
  },
  seekTime: {color: '#FFFFFFB3', fontSize: 12},
  seekSlider: {
    flex: 1,
    height: 32,
  },
  controls: {
    width: '100%',
    maxWidth: 620,
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 12,
    justifyContent: 'flex-end',
    alignItems: 'center',
  },
  roundControl: {
    width: 48,
    height: 48,
    borderRadius: 24,
    backgroundColor: '#D9E5E2',
    alignItems: 'center',
    justifyContent: 'center',
  },
  roundControlActive: {
    backgroundColor: '#E68A35',
  },
  roundControlSymbol: {
    color: exampleTheme.primary,
    fontSize: 18,
    fontWeight: '700',
  },
  controlTooltip: {
    position: 'absolute',
    width: 1,
    height: 1,
    opacity: 0,
  },
  speedControl: {
    minWidth: 62,
    minHeight: 52,
    borderRadius: 18,
    backgroundColor: 'rgba(37,37,37,0.92)',
    paddingHorizontal: 14,
    alignItems: 'center',
    justifyContent: 'center',
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
  sheet: {
    height: '88%',
    borderTopLeftRadius: 28,
    borderTopRightRadius: 28,
    backgroundColor: exampleTheme.background,
    paddingTop: 8,
  },
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
  sheetTitle: {
    color: exampleTheme.textPrimary,
    fontSize: 16,
    fontWeight: '700',
  },
  sheetSubtitle: {color: exampleTheme.textSecondary, fontSize: 12},
  monthPanel: {gap: 8, paddingHorizontal: 18, paddingVertical: 12},
  monthHeader: {flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between'},
  monthTitle: {color: exampleTheme.textPrimary, fontSize: 15, fontWeight: '700'},
  weekHeader: {flexDirection: 'row'},
  weekLabel: {width: `${100 / 7}%`, textAlign: 'center', color: exampleTheme.textSecondary, fontSize: 11},
  calendarGrid: {flexDirection: 'row', flexWrap: 'wrap'},
  dayCell: {width: `${100 / 7}%`, height: 46, alignItems: 'center', justifyContent: 'center', borderRadius: 12},
  dayAvailable: {backgroundColor: 'rgba(101,146,135,0.14)'},
  dayUnavailable: {opacity: 0.34},
  daySelected: {backgroundColor: exampleTheme.primary},
  dayText: {color: exampleTheme.textPrimary, fontSize: 12},
  dayTextSelected: {color: exampleTheme.foreground, fontSize: 12, fontWeight: '700'},
  dayStateText: {color: exampleTheme.textSecondary, fontSize: 8},
  dayStateTextSelected: {color: exampleTheme.foreground, fontSize: 8},
  monthError: {color: exampleTheme.failure, textAlign: 'center', fontSize: 12},
  rangeList: {padding: 16, gap: 8},
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
