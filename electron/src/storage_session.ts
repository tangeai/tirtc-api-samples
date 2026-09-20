import fs from 'node:fs';
import path from 'node:path';
import type {BrowserWindow, Rectangle} from 'electron';
import {
  TiCloudStorage,
  TiCloudStorageAudioOutput,
  TiCloudStorageVideoOutput,
  TiRtcError,
  TiRtcLogging,
  TiVideoView,
} from 'tirtc-electron';
import type {
  TiCloudStorageExportTask,
  TiCloudStorageRecordingDay,
  TiCloudStorageRecordingFile,
  TiCloudStorageRecordingTask,
  TiCloudStorageReplay,
  TiCloudStorageReplaySpeed,
  TiCloudStorageSnapshotFile,
  TiRtcMediaFile,
  TiRawDump,
} from 'tirtc-electron';

import type {
  ExampleFailure,
  TiCloudStorageExampleConfig,
  TiCloudStorageExampleState,
} from './shared/types';
import {OperationBarrier, settlesWithin} from './operation_barrier';

export type TiCloudStorageExampleSessionConfig =
  TiCloudStorageExampleConfig & Readonly<{token: string}>;

function failureOf(reason: unknown): ExampleFailure {
  if (reason instanceof TiRtcError) return {code: reason.code, message: reason.message};
  return {code: 'invalid-input', message: reason instanceof Error ? reason.message : String(reason)};
}

async function retryWhileInUse(operation: () => void): Promise<void> {
  for (let attempt = 0; attempt < 250; attempt += 1) {
    try {
      operation();
      return;
    } catch (reason) {
      if (!(reason instanceof TiRtcError) || reason.code !== 'in-use') throw reason;
    }
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  throw new Error('resource remained in use during teardown');
}

function newestFirstRecordingRanges<T extends Readonly<{startTimeMs: number; endTimeMs: number}>>(
  ranges: ReadonlyArray<T>,
): ReadonlyArray<T> {
  return [...ranges].sort((left, right) =>
    right.startTimeMs - left.startTimeMs || right.endTimeMs - left.endTimeMs);
}

const OPERATION_DRAIN_TIMEOUT_MS = 5_000;
type OperationOwner =
  'core' | 'cloudStorage' | 'replay' | 'videoOutput' | 'recording' | 'rawDump' | 'export' | 'file';

export class TiCloudStorageExampleSession {
  readonly #window: BrowserWindow;
  readonly #operationDrainTimeoutMs: number;
  #cloudStorage: TiCloudStorage | null = null;
  #replay: TiCloudStorageReplay | null = null;
  #audioOutput: TiCloudStorageAudioOutput | null = null;
  #videoOutputs = new Map<number, TiCloudStorageVideoOutput>();
  #audioAttached = false;
  #attachedVideoChannelIds = new Set<number>();
  #views = new Map<number, TiVideoView>();
  #recordingTask: TiCloudStorageRecordingTask | null = null;
  #rawDump: TiRawDump | null = null;
  #rawDumpPendingUpload = false;
  #exportTask: TiCloudStorageExportTask | null = null;
  #exportCompletion: Promise<void> | null = null;
  #recentRecording: TiCloudStorageRecordingFile | null = null;
  #recentSnapshot: TiCloudStorageSnapshotFile | null = null;
  #persistedDestinations = new WeakMap<TiRtcMediaFile, string>();
  #retiredMedia = new Set<TiRtcMediaFile>();
  #acceptedOperations = new OperationBarrier<OperationOwner>();
  #quiescing = true;
  #leavePromise: Promise<void> | null = null;
  #initialized = false;
  #videoChannelIds: ReadonlyArray<number> = [11];
  #audioChannelId: number | null = 10;
  #selectedVideoChannelId: number | null = 11;
  #recordingTargetId: number | null = null;
  #exportTargetId: number | null = null;
  #recentRecordingTargetId: number | null = null;
  #recentSnapshotTargetId: number | null = null;
  #queryGeneration = 0;
  #state: TiCloudStorageExampleState = {
    phase: 'configuration',
    querying: false,
    ranges: [],
    selectedIndex: null,
    currentTimeMs: null,
    speed: 1,
    replayState: 'idle',
    recording: false,
    exportProgress: null,
    recentRecording: false,
    recentSnapshot: false,
    lastSavedFile: null,
    message: '',
    uploadingLogs: false,
    rawDumpPhase: 'idle',
    rawDumpCaptureId: null,
    mediaBusy: false,
    lastError: null,
    videoStates: {}, videoChannelIds: [11], selectedVideoChannelId: 11, hasAudio: true,
  };

  constructor(window: BrowserWindow, operationDrainTimeoutMs = OPERATION_DRAIN_TIMEOUT_MS) {
    this.#window = window;
    this.#operationDrainTimeoutMs = operationDrainTimeoutMs;
  }
  get state(): TiCloudStorageExampleState { return this.#state; }

  async configure(config: TiCloudStorageExampleSessionConfig): Promise<void> {
    await this.leave();
    this.#quiescing = false;
    try {
      TiCloudStorage.init({appId: config.appId, endpoint: config.endpoint});
      this.#initialized = true;
      const videoChannelIds = config.videoChannelIds === undefined ? [11] : [...config.videoChannelIds];
      if ((config.audioChannelId !== null && (!Number.isSafeInteger(config.audioChannelId) || config.audioChannelId < 0 || config.audioChannelId > 255)) ||
          videoChannelIds.length > 3 || videoChannelIds.some((id) => !Number.isSafeInteger(id) || id < 0 || id > 255) ||
          new Set(videoChannelIds).size !== videoChannelIds.length) {
        throw new TypeError('select optional audio and up to three distinct video Channel IDs from 0 through 255');
      }
      this.#videoChannelIds = videoChannelIds;
      this.#audioChannelId = config.audioChannelId;
      this.#selectedVideoChannelId = this.#videoChannelIds[0] ?? null;
      this.#cloudStorage = new TiCloudStorage(config.token);
      this.#replay = this.#cloudStorage.createReplay();
      this.#audioOutput = this.#audioChannelId === null ? null : new TiCloudStorageAudioOutput();
      this.#replay.onTimeChanged = (timeMs) => this.update({currentTimeMs: timeMs});
      this.#replay.onCompleted = () => this.update({message: '录像源读取完成'});
      this.#replay.onError = (error) => this.captureFailure(error);
      this.#replay.onRecordingGap = (gap) => {
        this.update({message: `Replay gap ${gap.range.startTimeMs}-${gap.range.endTimeMs}`});
      };
      if (this.#audioOutput !== null) {
        this.#audioOutput.onStateChanged = (state) => {
          if (this.replayOutputsCompleted()) this.update({replayState: 'completed'});
          else if (this.#videoChannelIds.length === 0 && (state === 'playing' || state === 'paused')) {
            this.update({replayState: state});
          }
        };
        this.#audioOutput.onError = (error) => {
          const failure = failureOf(error);
          this.update({
            message: `音频播放失败：${failure.message}`,
            hasAudio: false,
          });
        };
      }
      const videoStates: Record<string, string> = {};
      for (const channelId of this.#videoChannelIds) {
        const output = new TiCloudStorageVideoOutput();
        this.#videoOutputs.set(channelId, output);
        videoStates[String(channelId)] = 'idle';
        output.onStateChanged = (state) => {
          const next: Record<string, string> = {...this.#state.videoStates, [channelId]: state};
          if (this.replayOutputsCompleted(next)) {
            this.update({videoStates: next, replayState: 'completed'});
          } else if (state === 'rendering' || state === 'paused') {
            this.update({videoStates: next, replayState: state});
          } else {
            this.update({videoStates: next});
          }
        };
        output.onError = (error) => {
          const failure = failureOf(error);
          const next: Record<string, string> = {...this.#state.videoStates, [channelId]: 'failed'};
          this.update({
            videoStates: next,
            message: `视频 Channel ${channelId} 播放失败：${failure.message}`,
          });
        };
      }
      this.update({phase: 'selection', lastError: null, message: '', videoStates,
        videoChannelIds: this.#videoChannelIds,
        selectedVideoChannelId: this.#selectedVideoChannelId, hasAudio: this.#audioChannelId !== null});
    } catch (reason) {
      let failure = reason;
      try { await this.leave(); } catch (cleanupError) { failure = cleanupError; }
      this.captureFailure(failure);
      throw failure;
    }
  }

  query(startTimeMs: number, endTimeMs: number): Promise<void> {
    this.ensureAccepting();
    return this.track(this.queryOwned(startTimeMs, endTimeMs), 'cloudStorage', 'core');
  }

  private async queryOwned(startTimeMs: number, endTimeMs: number): Promise<void> {
    if (this.#cloudStorage === null) throw new Error('Ti Cloud Storage is unavailable');
    const generation = ++this.#queryGeneration;
    const cloudStorage = this.#cloudStorage;
    this.update({querying: true, lastError: null});
    try {
      const ranges = await cloudStorage.listRecordings({startTimeMs, endTimeMs});
      if (generation !== this.#queryGeneration || cloudStorage !== this.#cloudStorage) return;
      this.update({
        querying: false,
        ranges: newestFirstRecordingRanges(ranges),
        selectedIndex: null,
        message: ranges.length === 0 ? '没有可用录像' : '',
      });
    } catch (reason) {
      if (generation === this.#queryGeneration) this.captureFailure(reason, {querying: false});
      throw reason;
    }
  }

  queryDays(
    startDate: string,
    endDate: string,
    timeZoneId: string,
  ): Promise<ReadonlyArray<TiCloudStorageRecordingDay>> {
    this.ensureAccepting();
    if (this.#cloudStorage === null) throw new Error('Ti Cloud Storage is unavailable');
    return this.track(
      this.#cloudStorage.listRecordingDays({startDate, endDate, timeZoneId}),
      'cloudStorage', 'core',
    );
  }

  play(index: number): void {
    this.ensureAccepting();
    if (this.#replay === null || (this.#audioOutput === null && this.#videoOutputs.size === 0)) {
      throw new Error('replay is unavailable');
    }
    const range = this.#state.ranges[index];
    if (range === undefined) throw new TypeError('recording index is invalid');
    let firstAttachError: unknown = null;
    if (this.#audioOutput !== null && this.#audioChannelId !== null && !this.#audioAttached) {
      try {
        this.#audioOutput.attach(this.#replay, this.#audioChannelId);
        this.#audioAttached = true;
        this.update({hasAudio: true});
      } catch (reason) {
        firstAttachError = reason;
        this.update({hasAudio: false, message: `音频输出绑定失败：${failureOf(reason).message}`});
      }
    }
    const videoStates: Record<string, string> = {...this.#state.videoStates};
    for (const [channelId, output] of this.#videoOutputs) {
      if (!this.#attachedVideoChannelIds.has(channelId)) {
        try {
          output.attach(this.#replay, channelId);
          this.#attachedVideoChannelIds.add(channelId);
        } catch (reason) {
          firstAttachError ??= reason;
          videoStates[String(channelId)] = 'failed';
          this.update({message: `视频 Channel ${channelId} 绑定失败：${failureOf(reason).message}`});
        }
      }
      if (this.#attachedVideoChannelIds.has(channelId)) videoStates[String(channelId)] = 'idle';
    }
    if (!this.#audioAttached && this.#attachedVideoChannelIds.size === 0) {
      throw firstAttachError ?? new Error('no replay output could be attached');
    }
    this.#replay.play({startTimeMs: range.startTimeMs, endTimeMs: range.endTimeMs});
    this.update({
      phase: 'playing',
      selectedIndex: index,
      currentTimeMs: range.startTimeMs,
      replayState: 'buffering',
      lastError: null,
      videoStates,
    });
  }

  setVideoBounds(channelId: number, bounds: Rectangle): void {
    if (this.#quiescing) return;
    const output = this.#videoOutputs.get(channelId);
    if (output === undefined) return;
    const existing = this.#views.get(channelId);
    if (existing === undefined) {
      const view = new TiVideoView(this.#window, bounds);
      output.mount(view);
      this.#views.set(channelId, view);
    } else {
      existing.setBounds(bounds);
    }
  }

  selectVideo(channelId: number): void {
    this.ensureAccepting();
    if (!this.#videoOutputs.has(channelId)) throw new TypeError('video Channel ID is not configured');
    this.#selectedVideoChannelId = channelId;
    this.update({selectedVideoChannelId: channelId});
  }

  pause(): void { this.ensureAccepting(); this.requireReplay().pause(); this.update({replayState: 'paused'}); }
  resume(): void { this.ensureAccepting(); this.requireReplay().resume(); this.update({replayState: 'buffering'}); }
  seek(timeMs: number): void { this.ensureAccepting(); this.requireReplay().seek(timeMs); }
  setSpeed(speed: TiCloudStorageReplaySpeed): void {
    this.ensureAccepting();
    this.requireReplay().setSpeed(speed);
    this.update({speed});
  }

  setMuted(muted: boolean): void {
    this.ensureAccepting();
    if (this.#audioOutput === null) throw new Error('audio output is unavailable');
    this.#audioOutput.setVolume(muted ? 0 : 100);
  }

  startRecording(): void {
    this.ensureAccepting();
    if (this.#recordingTask !== null) throw new Error('recording is already active');
    this.#recordingTask = this.requireReplay().startRecording({
      videoChannelId: this.requireSelectedVideoChannelId(),
      audioChannelId: this.#audioChannelId ?? undefined,
    });
    this.#recordingTargetId = this.#selectedVideoChannelId;
    this.update({recording: true, mediaBusy: false});
  }

  stopRecording(): Promise<void> {
    this.ensureAccepting();
    return this.track(this.stopRecordingOwned(), 'recording', 'replay', 'core');
  }

  private async stopRecordingOwned(): Promise<void> {
    if (this.#recordingTask === null) throw new Error('recording has not started');
    const task = this.#recordingTask;
    this.#recordingTask = null;
    this.update({mediaBusy: true});
    let stopped = false;
    try {
      const file = await task.stop();
      stopped = true;
      await this.replaceRecent('recording', file, this.#recordingTargetId);
      this.#recordingTargetId = null;
      this.update({recording: false, mediaBusy: false});
    } catch (reason) {
      if (!stopped && this.#recordingTask === null) this.#recordingTask = task;
      this.captureFailure(reason, {recording: !stopped, mediaBusy: false});
      throw reason;
    }
  }

  takeSnapshot(): Promise<void> {
    this.ensureAccepting();
    return this.track(this.takeSnapshotOwned(), 'videoOutput', 'replay', 'core');
  }

  private async takeSnapshotOwned(): Promise<void> {
    const output = this.selectedVideoOutput();
    if (output === null) throw new Error('video output is unavailable');
    this.update({mediaBusy: true});
    try {
      const targetId = this.#selectedVideoChannelId;
      await this.replaceRecent('snapshot', await output.takeSnapshot(), targetId);
      this.update({mediaBusy: false});
    } catch (reason) {
      this.captureFailure(reason, {mediaBusy: false});
      throw reason;
    }
  }

  startExport(index: number): void {
    this.ensureAccepting();
    if (this.#cloudStorage === null || this.#exportTask !== null) throw new Error('export is unavailable');
    const range = this.#state.ranges[index];
    if (range === undefined) throw new TypeError('recording index is invalid');
    const task = this.#cloudStorage.exportRecording({
      startTimeMs: range.startTimeMs,
      endTimeMs: range.endTimeMs,
      videoChannelId: this.requireSelectedVideoChannelId(),
      audioChannelId: this.#audioChannelId ?? undefined,
    }, {
      onProgressDetail: (progress) => this.update({exportProgress: progress.fraction}),
      onRecordingGap: (gap) => {
        this.update({message: `Export gap ${gap.range.startTimeMs}-${gap.range.endTimeMs}`});
      },
    });
    this.#exportTask = task;
    this.#exportTargetId = this.#selectedVideoChannelId;
    this.update({exportProgress: 0, mediaBusy: true});
    void task.result.catch(() => undefined);
    const completion = this.track(task.completion.then(async (outcome) => {
      if (this.#exportTask !== task) return;
      if (outcome.code !== 0 || outcome.file === null || outcome.report === null) {
        await task.result;
        return;
      }
      await this.replaceRecent('recording', outcome.file, this.#exportTargetId);
      this.update({
        exportProgress: null,
        mediaBusy: false,
        message: `Covered ${outcome.report.coveredDurationMs}ms; gaps ${outcome.report.gaps.length}; ` +
          `unprocessed ${outcome.report.unprocessedRanges.length}; ${outcome.report.termination}`,
      });
    }).catch((reason) => {
      if (this.#exportTask !== task) return;
      if (reason instanceof TiRtcError && reason.code === 'cancelled') {
        this.update({exportProgress: null, mediaBusy: false});
      } else {
        this.captureFailure(reason, {exportProgress: null, mediaBusy: false});
      }
    }).finally(() => {
      if (this.#exportTask === task) this.#exportTask = null;
      if (this.#exportCompletion === completion) this.#exportCompletion = null;
    }), 'export', 'cloudStorage', 'core');
    this.#exportCompletion = completion;
  }

  saveRecent(kind: 'recording' | 'snapshot', destinationPath: string): Promise<void> {
    this.ensureAccepting();
    return this.track(this.saveRecentOwned(kind, destinationPath), 'file', 'core');
  }

  private async saveRecentOwned(kind: 'recording' | 'snapshot', destinationPath: string): Promise<void> {
    const file = kind === 'recording' ? this.#recentRecording : this.#recentSnapshot;
    if (file === null) throw new Error('there is no recent media file');
    if (!path.isAbsolute(destinationPath) || path.resolve(destinationPath) === path.resolve(file.path)) {
      throw new TypeError('destinationPath must be a different absolute path');
    }
    let persisted = this.#persistedDestinations.get(file);
    if (persisted === undefined) {
      await fs.promises.copyFile(file.path, destinationPath, fs.constants.COPYFILE_EXCL);
      persisted = destinationPath;
      this.#persistedDestinations.set(file, persisted);
    }
    await this.deleteRecent(file);
    if (kind === 'recording') {
      this.#recentRecording = null;
      this.update({recentRecording: false, lastSavedFile: path.basename(persisted)});
    } else {
      this.#recentSnapshot = null;
      this.update({recentSnapshot: false, lastSavedFile: path.basename(persisted)});
    }
  }

  recentPath(kind: 'recording' | 'snapshot'): string | null {
    const file = kind === 'recording' ? this.#recentRecording : this.#recentSnapshot;
    return file === null ? null : this.#persistedDestinations.get(file) ?? file.path;
  }

  recentTargetId(kind: 'recording' | 'snapshot'): number | null {
    return kind === 'recording' ? this.#recentRecordingTargetId : this.#recentSnapshotTargetId;
  }

  uploadLogs(): Promise<void> {
    this.ensureAccepting();
    return this.track(this.uploadLogsOwned(), 'core');
  }

  private async uploadLogsOwned(): Promise<void> {
    if (this.#rawDump !== null) await this.stopRawDumpOwned(false);
    await this.uploadCompletedDiagnostics();
  }

  toggleRawDump(): Promise<void> {
    this.ensureAccepting();
    return this.track(this.toggleRawDumpOwned(), 'rawDump', 'replay', 'core');
  }

  private async toggleRawDumpOwned(): Promise<void> {
    if (this.#rawDump !== null) {
      await this.stopRawDumpOwned(true);
      return;
    }
    if (this.#rawDumpPendingUpload) {
      await this.uploadCompletedDiagnostics();
      return;
    }
    if (this.#state.selectedIndex === null) throw new Error('raw dump requires an active replay');
    this.#rawDump = await this.requireReplay().startRawDump({
      audioChannelIds: this.#audioChannelId === null ? [] : [this.#audioChannelId],
      videoChannelIds: this.#videoChannelIds,
    });
    this.update({
      rawDumpPhase: 'capturing',
      rawDumpCaptureId: null, lastError: null,
    });
  }

  private async stopRawDumpOwned(upload: boolean): Promise<void> {
    const dump = this.#rawDump;
    if (dump === null) return;
    this.update({rawDumpPhase: 'finalizing'});
    const archive = await dump.stop();
    this.#rawDump = null;
    this.#rawDumpPendingUpload = true;
    this.update({
      rawDumpPhase: upload ? 'uploading' : 'completed',
      rawDumpCaptureId: archive.captureId,
    });
    if (upload) await this.uploadCompletedDiagnostics();
  }

  private async uploadCompletedDiagnostics(): Promise<void> {
    this.update({uploadingLogs: true});
    if (this.#rawDumpPendingUpload) this.update({rawDumpPhase: 'uploading'});
    try {
      const logId = await TiRtcLogging.upload();
      this.#rawDumpPendingUpload = false;
      this.update({uploadingLogs: false, message: `Log ID: ${logId}`, lastError: null,
        rawDumpPhase: this.#state.rawDumpCaptureId === null ? 'idle' : 'completed'});
    } catch (reason) {
      this.captureFailure(reason, {uploadingLogs: false,
        rawDumpPhase: this.#rawDumpPendingUpload ? 'failed' : this.#state.rawDumpPhase});
      throw reason;
    }
  }

  leave(): Promise<void> {
    if (this.#leavePromise === null) {
      const operation = this.leaveOwned();
      this.#leavePromise = operation.finally(() => { this.#leavePromise = null; });
    }
    return this.#leavePromise;
  }

  private async leaveOwned(): Promise<void> {
    this.#quiescing = true;
    this.#queryGeneration += 1;
    let firstError: unknown = null;
    const attempt = async (operation: () => void | Promise<void>): Promise<boolean> => {
      try {
        await operation();
        return true;
      } catch (reason) {
        firstError ??= reason;
        return false;
      }
    };
    if (this.#exportTask !== null) {
      const task = this.#exportTask;
      task.cancel();
      const completion = this.#exportCompletion;
      const completed = completion === null
        ? this.#exportTask !== task
        : await settlesWithin(completion, this.#operationDrainTimeoutMs);
      if (!completed) firstError ??= new Error('export cancellation did not settle during teardown');
    }
    if (!await this.drainAcceptedOperations()) {
      firstError ??= new Error('Ti Cloud Storage accepted operations did not settle during teardown');
    }
    if (this.#recordingTask !== null && !this.ownerBusy('recording')) {
      await attempt(() => this.track(this.stopRecordingOwned(), 'recording', 'replay', 'core'));
    }
    if (this.#rawDump !== null && !this.ownerBusy('rawDump')) {
      await attempt(() => this.track(this.stopRawDumpOwned(false), 'rawDump', 'replay', 'core'));
    }
    if (!await this.drainAcceptedOperations()) {
      firstError ??= new Error('Ti Cloud Storage teardown operations did not settle');
    }
    if (!this.ownerBusy('file') && this.#recentRecording !== null &&
        await attempt(() => this.deleteRecent(this.#recentRecording))) {
      this.#recentRecording = null;
    }
    if (!this.ownerBusy('file') && this.#recentSnapshot !== null &&
        await attempt(() => this.deleteRecent(this.#recentSnapshot))) {
      this.#recentSnapshot = null;
    }
    if (!this.ownerBusy('file')) {
      for (const file of [...this.#retiredMedia]) await attempt(() => this.deleteRecent(file));
    }
    if (!this.ownerBusy('videoOutput')) {
      for (const [channelId, output] of this.#videoOutputs) {
        if (this.#attachedVideoChannelIds.has(channelId)) {
          if (await attempt(() => retryWhileInUse(() => output.detach()))) {
            this.#attachedVideoChannelIds.delete(channelId);
          }
        }
        await attempt(() => retryWhileInUse(() => output.unmount()));
        const view = this.#views.get(channelId);
        if (view !== undefined && await attempt(() => retryWhileInUse(() => view.dispose()))) {
          this.#views.delete(channelId);
        }
        if (await attempt(() => retryWhileInUse(() => output.dispose()))) {
          this.#videoOutputs.delete(channelId);
          this.#attachedVideoChannelIds.delete(channelId);
        }
      }
      for (const [channelId, view] of this.#views) {
        if (this.#videoOutputs.has(channelId)) continue;
        if (await attempt(() => retryWhileInUse(() => view.dispose()))) this.#views.delete(channelId);
      }
    }
    if (this.#audioOutput !== null) {
      if (this.#audioAttached) await attempt(() => retryWhileInUse(() => this.#audioOutput!.detach()));
      if (await attempt(() => retryWhileInUse(() => this.#audioOutput!.dispose()))) {
        this.#audioOutput = null;
        this.#audioAttached = false;
      }
    }
    if (this.#replay !== null && !this.ownerBusy('replay') && this.#audioOutput === null &&
        this.#videoOutputs.size === 0 && this.#recordingTask === null && this.#rawDump === null) {
      await attempt(() => retryWhileInUse(() => this.#replay!.stop()));
      if (await attempt(() => retryWhileInUse(() => this.#replay!.dispose()))) this.#replay = null;
    }
    if (this.#cloudStorage !== null && !this.ownerBusy('cloudStorage') && this.#replay === null &&
        this.#exportTask === null &&
        await attempt(() => retryWhileInUse(() => this.#cloudStorage!.dispose()))) this.#cloudStorage = null;
    if (this.#initialized && this.#cloudStorage === null && this.#replay === null &&
        this.#audioOutput === null && this.#videoOutputs.size === 0 && this.#views.size === 0 &&
        this.#recordingTask === null && this.#rawDump === null && this.#exportTask === null &&
        this.#recentRecording === null &&
        this.#recentSnapshot === null && this.#retiredMedia.size === 0 && !this.ownerBusy('core')) {
      if (await attempt(() => retryWhileInUse(() => TiCloudStorage.shutdown()))) this.#initialized = false;
    }
    if (this.#initialized && firstError === null) {
      firstError = new Error('Ti Cloud Storage session teardown did not reach shutdown');
    }
    if (firstError instanceof TiRtcError && firstError.code === 'cancelled') firstError = null;
    this.#state = {
      phase: firstError === null ? 'configuration' : 'failed',
      querying: false, ranges: [], selectedIndex: null,
      currentTimeMs: null, speed: 1, replayState: 'idle', recording: false,
      exportProgress: null,
      recentRecording: this.#recentRecording !== null,
      recentSnapshot: this.#recentSnapshot !== null,
      lastSavedFile: null,
      message: firstError === null ? '' : failureOf(firstError).message,
      uploadingLogs: false, mediaBusy: false,
      rawDumpPhase: 'idle',
      rawDumpCaptureId: null,
      lastError: firstError === null ? null : failureOf(firstError),
      videoStates: {}, videoChannelIds: [], selectedVideoChannelId: null, hasAudio: false,
    };
    this.#rawDumpPendingUpload = false;
    this.publish();
    if (firstError !== null) throw firstError;
  }

  private requireReplay(): TiCloudStorageReplay {
    if (this.#replay === null) throw new Error('replay is unavailable');
    return this.#replay;
  }

  private async replaceRecent(kind: 'recording' | 'snapshot', file: TiRtcMediaFile, targetId: number | null): Promise<void> {
    if (kind === 'recording') {
      const previous = this.#recentRecording;
      this.#recentRecording = file as TiCloudStorageRecordingFile;
      this.#recentRecordingTargetId = targetId;
      this.update({recentRecording: true, lastSavedFile: null});
      if (previous !== null) {
        try { await this.deleteRecent(previous); } catch (reason) {
          this.#retiredMedia.add(previous);
          throw reason;
        }
      }
    } else {
      const previous = this.#recentSnapshot;
      this.#recentSnapshot = file as TiCloudStorageSnapshotFile;
      this.#recentSnapshotTargetId = targetId;
      this.update({recentSnapshot: true, lastSavedFile: null});
      if (previous !== null) {
        try { await this.deleteRecent(previous); } catch (reason) {
          this.#retiredMedia.add(previous);
          throw reason;
        }
      }
    }
  }

  private async deleteRecent(file: TiRtcMediaFile | null): Promise<void> {
    if (file !== null) {
      await file.delete();
      this.#retiredMedia.delete(file);
    }
  }

  private ensureAccepting(): void {
    if (this.#quiescing) throw new Error('Ti Cloud Storage session is leaving');
  }

  private selectedVideoOutput(): TiCloudStorageVideoOutput | null {
    return this.#selectedVideoChannelId === null ? null : this.#videoOutputs.get(this.#selectedVideoChannelId) ?? null;
  }

  private requireSelectedVideoChannelId(): number {
    if (this.#selectedVideoChannelId === null) throw new Error('video output is unavailable');
    return this.#selectedVideoChannelId;
  }

  private replayOutputsCompleted(videoStates: Readonly<Record<string, string>> = this.#state.videoStates): boolean {
    const audioCompleted = this.#audioChannelId === null ||
      (this.#audioAttached && this.#audioOutput?.state === 'completed');
    return audioCompleted && this.#videoChannelIds.every((id) =>
      this.#attachedVideoChannelIds.has(id) && videoStates[String(id)] === 'completed');
  }

  private track<T>(operation: Promise<T>, ...owners: OperationOwner[]): Promise<T> {
    return this.#acceptedOperations.track(operation, ...owners);
  }

  private async drainAcceptedOperations(): Promise<boolean> {
    return this.#acceptedOperations.drain(this.#operationDrainTimeoutMs);
  }

  private ownerBusy(owner: OperationOwner): boolean {
    return this.#acceptedOperations.busy(owner);
  }

  private captureFailure(reason: unknown, patch: Partial<TiCloudStorageExampleState> = {}): void {
    const failure = failureOf(reason);
    this.update({phase: 'failed', message: failure.message, lastError: failure, ...patch});
  }

  private update(patch: Partial<TiCloudStorageExampleState>): void {
    this.#state = {...this.#state, ...patch};
    this.publish();
  }

  private publish(): void {
    if (!this.#window.isDestroyed()) {
      this.#window.webContents.send('tirtc-example:ti-cloud-storage-state', this.#state);
    }
  }
}
