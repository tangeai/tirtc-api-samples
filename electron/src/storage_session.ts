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
  'core' | 'cloudStorage' | 'replay' | 'videoOutput' | 'recording' | 'export' | 'file';

export class TiCloudStorageExampleSession {
  readonly #window: BrowserWindow;
  readonly #operationDrainTimeoutMs: number;
  #cloudStorage: TiCloudStorage | null = null;
  #replay: TiCloudStorageReplay | null = null;
  #audioOutput: TiCloudStorageAudioOutput | null = null;
  #videoOutput: TiCloudStorageVideoOutput | null = null;
  #view: TiVideoView | null = null;
  #recordingTask: TiCloudStorageRecordingTask | null = null;
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
  #videoChannelId = 11;
  #audioChannelId = 10;
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
    mediaBusy: false,
    lastError: null,
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
      this.#videoChannelId = config.videoChannelId;
      this.#audioChannelId = config.audioChannelId;
      this.#cloudStorage = new TiCloudStorage(config.token);
      this.#replay = this.#cloudStorage.createReplay();
      this.#audioOutput = new TiCloudStorageAudioOutput();
      this.#videoOutput = new TiCloudStorageVideoOutput();
      this.#replay.onTimeChanged = (timeMs) => this.update({currentTimeMs: timeMs});
      this.#replay.onCompleted = () => this.update({replayState: 'completed'});
      this.#replay.onError = (error) => this.captureFailure(error);
      this.#audioOutput.onStateChanged = (state) => {
        if (state === 'paused' || state === 'completed' || state === 'failed') this.update({replayState: state});
      };
      this.#audioOutput.onError = (error) => this.captureFailure(error);
      this.#videoOutput.onStateChanged = (state) => this.update({replayState: state});
      this.#videoOutput.onError = (error) => this.captureFailure(error);
      this.update({phase: 'selection', lastError: null, message: ''});
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
    if (this.#replay === null || this.#audioOutput === null || this.#videoOutput === null) {
      throw new Error('replay is unavailable');
    }
    const range = this.#state.ranges[index];
    if (range === undefined) throw new TypeError('recording index is invalid');
    this.#audioOutput.attach(this.#replay, this.#audioChannelId);
    this.#videoOutput.attach(this.#replay, this.#videoChannelId);
    this.#replay.play({startTimeMs: range.startTimeMs, endTimeMs: range.endTimeMs});
    this.update({
      phase: 'playing',
      selectedIndex: index,
      currentTimeMs: range.startTimeMs,
      replayState: 'buffering',
      lastError: null,
    });
  }

  setVideoBounds(bounds: Rectangle): void {
    this.ensureAccepting();
    if (this.#videoOutput === null) return;
    if (this.#view === null) {
      this.#view = new TiVideoView(this.#window, bounds);
      this.#videoOutput.mount(this.#view);
    } else {
      this.#view.setBounds(bounds);
    }
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
      videoChannelId: this.#videoChannelId,
      audioChannelId: this.#audioChannelId,
    });
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
      await this.replaceRecent('recording', file);
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
    if (this.#videoOutput === null) throw new Error('video output is unavailable');
    this.update({mediaBusy: true});
    try {
      await this.replaceRecent('snapshot', await this.#videoOutput.takeSnapshot());
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
      videoChannelId: this.#videoChannelId,
      audioChannelId: this.#audioChannelId,
    }, (progress) => this.update({exportProgress: progress}));
    this.#exportTask = task;
    this.update({exportProgress: 0, mediaBusy: true});
    const completion = this.track(task.result.then(async (file) => {
      if (this.#exportTask !== task) return;
      await this.replaceRecent('recording', file);
      this.update({exportProgress: null, mediaBusy: false});
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

  uploadLogs(): Promise<void> {
    this.ensureAccepting();
    return this.track(this.uploadLogsOwned(), 'core');
  }

  private async uploadLogsOwned(): Promise<void> {
    this.update({uploadingLogs: true});
    try {
      const logId = await TiRtcLogging.upload();
      this.update({uploadingLogs: false, message: `Log ID: ${logId}`, lastError: null});
    } catch (reason) {
      this.captureFailure(reason, {uploadingLogs: false});
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
    if (this.#videoOutput !== null && !this.ownerBusy('videoOutput')) {
      await attempt(() => retryWhileInUse(() => this.#videoOutput!.detach()));
      await attempt(() => retryWhileInUse(() => this.#videoOutput!.unmount()));
    }
    if (!this.ownerBusy('videoOutput') && this.#view !== null &&
        await attempt(() => retryWhileInUse(() => this.#view!.dispose()))) this.#view = null;
    if (!this.ownerBusy('videoOutput') && this.#videoOutput !== null &&
        await attempt(() => retryWhileInUse(() => this.#videoOutput!.dispose()))) this.#videoOutput = null;
    if (this.#audioOutput !== null) {
      await attempt(() => retryWhileInUse(() => this.#audioOutput!.detach()));
      if (await attempt(() => retryWhileInUse(() => this.#audioOutput!.dispose()))) this.#audioOutput = null;
    }
    if (this.#replay !== null && !this.ownerBusy('replay') && this.#audioOutput === null &&
        this.#videoOutput === null && this.#recordingTask === null) {
      await attempt(() => retryWhileInUse(() => this.#replay!.stop()));
      if (await attempt(() => retryWhileInUse(() => this.#replay!.dispose()))) this.#replay = null;
    }
    if (this.#cloudStorage !== null && !this.ownerBusy('cloudStorage') && this.#replay === null &&
        this.#exportTask === null &&
        await attempt(() => retryWhileInUse(() => this.#cloudStorage!.dispose()))) this.#cloudStorage = null;
    if (this.#initialized && this.#cloudStorage === null && this.#replay === null &&
        this.#audioOutput === null && this.#videoOutput === null && this.#view === null &&
        this.#recordingTask === null && this.#exportTask === null && this.#recentRecording === null &&
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
      lastError: firstError === null ? null : failureOf(firstError),
    };
    this.publish();
    if (firstError !== null) throw firstError;
  }

  private requireReplay(): TiCloudStorageReplay {
    if (this.#replay === null) throw new Error('replay is unavailable');
    return this.#replay;
  }

  private async replaceRecent(kind: 'recording' | 'snapshot', file: TiRtcMediaFile): Promise<void> {
    if (kind === 'recording') {
      const previous = this.#recentRecording;
      this.#recentRecording = file as TiCloudStorageRecordingFile;
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
