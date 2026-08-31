import fs from 'node:fs';
import path from 'node:path';
import type {BrowserWindow, Rectangle} from 'electron';
import {
  TiRtc,
  TiRtcAudioInput,
  TiRtcAudioOutput,
  TiRtcConn,
  TiRtcError,
  TiRtcLogging,
  TiRtcVideoOutput,
  TiVideoView,
} from 'tirtc-electron';
import type {
  TiRtcMediaFile,
  TiRtcRecordingFile,
  TiRtcRecordingTask,
  TiRtcSnapshotFile,
} from 'tirtc-electron';

import type {ExampleConfig, ExampleFailure, ExampleSettings, ExampleState} from './shared/types';
import {OperationBarrier} from './operation_barrier';

export type ExampleSessionConfig = ExampleConfig & Readonly<{token: string}>;

const AUDIO_STREAM_ID = 10;
const VIDEO_STREAM_ID = 11;
const LOCAL_AUDIO_STREAM_ID = 14;

const DEFAULT_SETTINGS: ExampleSettings = {
  videoDecoderPreference: 'auto',
  outputBufferPolicy: 'automatic',
  consoleLogEnabled: false,
  localAudioCodec: 'g711a',
  localAudioSampleRateHz: 16000,
  localAudioStreamId: LOCAL_AUDIO_STREAM_ID,
  localAudioAecEnabled: false,
  localAudioAgcLevel: 'disabled',
  localAudioAnsLevel: 'disabled',
};

function failureOf(reason: unknown): ExampleFailure {
  if (reason instanceof TiRtcError) return {code: reason.code, message: reason.message};
  return {
    code: 'invalid-input',
    message: reason instanceof Error ? reason.message : String(reason),
  };
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

const OPERATION_DRAIN_TIMEOUT_MS = 5_000;
type OperationOwner = 'core' | 'connection' | 'videoOutput' | 'recording' | 'file';

export class ExampleSession {
  readonly #window: BrowserWindow;
  readonly #operationDrainTimeoutMs: number;
  #connection: TiRtcConn | null = null;
  #audioInput: TiRtcAudioInput | null = null;
  #audioOutput: TiRtcAudioOutput | null = null;
  #videoOutput: TiRtcVideoOutput | null = null;
  #remoteView: TiVideoView | null = null;
  #acceptVideoBounds = false;
  #metricsTimer: ReturnType<typeof setInterval> | null = null;
  #recordingTask: TiRtcRecordingTask | null = null;
  #recentRecording: TiRtcRecordingFile | null = null;
  #recentSnapshot: TiRtcSnapshotFile | null = null;
  #persistedDestinations = new WeakMap<TiRtcMediaFile, string>();
  #retiredMedia = new Set<TiRtcMediaFile>();
  #acceptedOperations = new OperationBarrier<OperationOwner>();
  #quiescing = true;
  #leavePromise: Promise<void> | null = null;
  #initialized = false;
  #audioStreamId = AUDIO_STREAM_ID;
  #videoStreamId = VIDEO_STREAM_ID;
  #state: ExampleState = {
    phase: 'configuration',
    message: '',
    messageDirection: null,
    messageCommandId: null,
    connectionState: 'idle',
    recording: false,
    audioState: 'idle',
    audioMuted: false,
    localAudioRunning: false,
    recentRecording: false,
    recentSnapshot: false,
    lastSavedFile: null,
    uploadingLogs: false,
    lastError: null,
    metrics: null,
  };

  constructor(window: BrowserWindow, operationDrainTimeoutMs = OPERATION_DRAIN_TIMEOUT_MS) {
    this.#window = window;
    this.#operationDrainTimeoutMs = operationDrainTimeoutMs;
  }
  get state(): ExampleState { return this.#state; }

  async configure(config: ExampleSessionConfig): Promise<void> {
    await this.leave();
    this.#quiescing = false;
    try {
      const audioStreamId = config.audioStreamId ?? AUDIO_STREAM_ID;
      const videoStreamId = config.videoStreamId ?? VIDEO_STREAM_ID;
      if (!Number.isSafeInteger(audioStreamId) || !Number.isSafeInteger(videoStreamId) ||
          audioStreamId < 0 || audioStreamId > 15 || videoStreamId < 0 || videoStreamId > 15 ||
          audioStreamId === videoStreamId) {
        throw new TypeError('audio and video Stream IDs must be different integers from 0 through 15');
      }
      const settings = config.settings ?? DEFAULT_SETTINGS;
      if (!Number.isSafeInteger(settings.localAudioStreamId) || settings.localAudioStreamId < 0 ||
          settings.localAudioStreamId > 15) {
        throw new TypeError('local audio Stream ID must be an integer from 0 through 15');
      }
      this.#audioStreamId = audioStreamId;
      this.#videoStreamId = videoStreamId;
      TiRtc.init({
        appId: config.appId,
        endpoint: config.endpoint,
        consoleLogEnabled: settings.consoleLogEnabled,
      });
      this.#initialized = true;
      this.#connection = new TiRtcConn();
      this.#audioInput = new TiRtcAudioInput();
      this.#audioOutput = new TiRtcAudioOutput();
      this.#videoOutput = new TiRtcVideoOutput();

      this.#connection.onStateChanged = (state, error) => {
        this.update({
          connectionState: state,
          phase: state === 'connected' ? 'playing' : this.#state.phase,
        });
        if (state === 'connected') {
          try {
            this.#connection!.subscribeAudio(this.#audioStreamId);
            this.#connection!.subscribeVideo(this.#videoStreamId);
          } catch (reason) {
            this.captureFailure(reason);
          }
        }
        if (error !== null) this.captureFailure(error);
      };
      this.#connection.onStreamMessage = (_streamId, _timestampMs, data) => {
        this.update({message: new TextDecoder().decode(data), messageDirection: 'received', messageCommandId: null});
      };
      this.#connection.onCommand = (commandId, data) => {
        this.update({message: new TextDecoder().decode(data), messageDirection: 'received', messageCommandId: commandId});
      };
      this.#audioOutput.onStateChanged = (state) => this.update({audioState: state});
      this.#audioInput.onStateChanged = (state) => this.update({localAudioRunning: state === 'running'});
      this.#audioInput.onError = (error) => this.captureFailure(error);
      this.#audioOutput.onError = (error) => this.captureFailure(error);
      this.#videoOutput.onError = (error) => this.captureFailure(error);
      this.#videoOutput.onStateChanged = () => this.publish();
      this.#videoOutput.onRenderSizeChanged = () => this.publish();

      this.#audioInput.setOptions({
        codec: settings.localAudioCodec,
        sampleRateHz: settings.localAudioCodec === 'amr' ? 8000 : settings.localAudioSampleRateHz,
        channels: 1,
        aecMode: settings.localAudioAecEnabled ? 'enabled' : 'disabled',
        agcLevel: settings.localAudioAgcLevel,
        ansLevel: settings.localAudioAnsLevel,
      });
      this.#audioOutput.setOptions({bufferStrategy: settings.outputBufferPolicy});
      this.#videoOutput.setOptions({
        decoderPreference: settings.videoDecoderPreference,
        bufferStrategy: settings.outputBufferPolicy,
      });
      this.#audioInput.attach(this.#connection, settings.localAudioStreamId);
      this.#audioOutput.attach(this.#connection, this.#audioStreamId);
      this.#videoOutput.attach(this.#connection, this.#videoStreamId);
      this.#acceptVideoBounds = true;
      this.#metricsTimer = setInterval(() => this.publishMetrics(), 1000);
      this.update({phase: 'connecting', lastError: null, message: '', messageDirection: null, messageCommandId: null});
      this.#connection.connect({remoteId: config.remoteId, token: config.token});
    } catch (reason) {
      let failure = reason;
      try { await this.leave(); } catch (cleanupError) { failure = cleanupError; }
      this.captureFailure(failure);
      throw failure;
    }
  }

  setVideoBounds(bounds: Rectangle): void {
    this.ensureAccepting();
    if (!this.#acceptVideoBounds || this.#videoOutput === null) return;
    if (this.#remoteView === null) {
      this.#remoteView = new TiVideoView(this.#window, bounds);
      this.#videoOutput.mount(this.#remoteView);
    } else {
      this.#remoteView.setBounds(bounds);
    }
  }

  sendMessage(message: string): void {
    this.ensureAccepting();
    if (this.#connection === null) throw new Error('RTC connection is unavailable');
    this.#connection.sendStreamMessage({
      streamId: 0,
      timestampMs: Date.now() >>> 0,
      data: new TextEncoder().encode(message),
    });
  }

  sendCommand(commandId: number, message: string): void {
    this.ensureAccepting();
    if (this.#connection === null) throw new Error('RTC connection is unavailable');
    this.#connection.sendCommand(commandId, new TextEncoder().encode(message));
    this.update({message, messageDirection: 'sent', messageCommandId: commandId});
  }

  startRecording(): void {
    this.ensureAccepting();
    if (this.#connection === null || this.#recordingTask !== null) {
      throw new Error('recording is unavailable');
    }
    this.#recordingTask = this.#connection.startRecording({
      videoStreamId: this.#videoStreamId,
      audioStreamId: this.#audioStreamId,
    });
    this.update({recording: true});
  }

  stopRecording(): Promise<void> {
    this.ensureAccepting();
    return this.track(this.stopRecordingOwned(), 'recording', 'connection', 'core');
  }

  private async stopRecordingOwned(): Promise<void> {
    if (this.#recordingTask === null) throw new Error('recording has not started');
    const task = this.#recordingTask;
    this.#recordingTask = null;
    let stopped = false;
    try {
      const file = await task.stop();
      stopped = true;
      await this.replaceRecent('recording', file);
      this.update({recording: false});
    } catch (reason) {
      if (!stopped && this.#recordingTask === null) this.#recordingTask = task;
      this.update({recording: !stopped});
      this.captureFailure(reason);
      throw reason;
    }
  }

  takeSnapshot(): Promise<void> {
    this.ensureAccepting();
    return this.track(this.takeSnapshotOwned(), 'videoOutput', 'connection', 'core');
  }

  private async takeSnapshotOwned(): Promise<void> {
    if (this.#videoOutput === null) throw new Error('video output is unavailable');
    try {
      await this.replaceRecent('snapshot', await this.#videoOutput.takeSnapshot());
    } catch (reason) {
      this.captureFailure(reason);
      throw reason;
    }
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

  setAudioMuted(muted: boolean): void {
    this.ensureAccepting();
    if (this.#audioOutput === null) throw new Error('audio output is unavailable');
    this.#audioOutput.setVolume(muted ? 0 : 100);
    this.update({audioMuted: muted});
  }

  setLocalAudioRunning(running: boolean): void {
    this.ensureAccepting();
    if (this.#audioInput === null) throw new Error('audio input is unavailable');
    if (running) this.#audioInput.start();
    else this.#audioInput.stop();
    this.update({localAudioRunning: running});
  }

  uploadLogs(): Promise<void> {
    this.ensureAccepting();
    return this.track(this.uploadLogsOwned(), 'core');
  }

  private async uploadLogsOwned(): Promise<void> {
    this.update({uploadingLogs: true});
    try {
      const logId = await TiRtcLogging.upload();
      this.update({uploadingLogs: false, message: `Log ID: ${logId}`,
        messageDirection: null, messageCommandId: null, lastError: null});
    } catch (reason) {
      this.update({uploadingLogs: false});
      this.captureFailure(reason);
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
    this.#acceptVideoBounds = false;
    if (this.#metricsTimer !== null) {
      clearInterval(this.#metricsTimer);
      this.#metricsTimer = null;
    }
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

    if (!await this.drainAcceptedOperations()) {
      firstError ??= new Error('RTC accepted operations did not settle during teardown');
    }
    if (this.#recordingTask !== null && !this.ownerBusy('recording')) {
      await attempt(() => this.track(
        this.stopRecordingOwned(), 'recording', 'connection', 'core',
      ));
    }
    if (!await this.drainAcceptedOperations()) {
      firstError ??= new Error('RTC teardown operations did not settle');
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

    if (this.#audioInput !== null) {
      if (this.#audioInput.state !== 'idle' && this.#audioInput.state !== 'stopped') {
        await attempt(() => retryWhileInUse(() => this.#audioInput!.stop()));
      }
      await attempt(() => retryWhileInUse(() => this.#audioInput!.detach()));
      if (await attempt(() => retryWhileInUse(() => this.#audioInput!.dispose()))) this.#audioInput = null;
    }
    if (this.#audioOutput !== null) {
      await attempt(() => retryWhileInUse(() => this.#audioOutput!.detach()));
      if (await attempt(() => retryWhileInUse(() => this.#audioOutput!.dispose()))) this.#audioOutput = null;
    }
    if (this.#videoOutput !== null && !this.ownerBusy('videoOutput')) {
      await attempt(() => retryWhileInUse(() => this.#videoOutput!.detach()));
      await attempt(() => retryWhileInUse(() => this.#videoOutput!.unmount()));
    }
    if (!this.ownerBusy('videoOutput') && this.#remoteView !== null &&
        await attempt(() => retryWhileInUse(() => this.#remoteView!.dispose()))) this.#remoteView = null;
    if (!this.ownerBusy('videoOutput') && this.#videoOutput !== null &&
        await attempt(() => retryWhileInUse(() => this.#videoOutput!.dispose()))) this.#videoOutput = null;
    if (this.#connection !== null && !this.ownerBusy('connection') && this.#audioInput === null &&
        this.#audioOutput === null && this.#videoOutput === null && this.#recordingTask === null) {
      await attempt(() => retryWhileInUse(() => this.#connection!.disconnect()));
      if (await attempt(() => retryWhileInUse(() => this.#connection!.dispose()))) this.#connection = null;
    }
    if (this.#initialized && this.#connection === null && this.#audioInput === null &&
        this.#audioOutput === null && this.#videoOutput === null && this.#remoteView === null &&
        this.#recordingTask === null && this.#recentRecording === null && this.#recentSnapshot === null &&
        this.#retiredMedia.size === 0 && !this.ownerBusy('core')) {
      if (await attempt(() => retryWhileInUse(() => TiRtc.shutdown()))) this.#initialized = false;
    }
    if (this.#initialized && firstError === null) {
      firstError = new Error('RTC session teardown did not reach shutdown');
    }
    this.#state = {
      phase: firstError === null ? 'configuration' : 'failed',
      message: firstError === null ? '' : failureOf(firstError).message,
      messageDirection: null, messageCommandId: null,
      connectionState: 'idle', recording: false,
      audioState: 'idle', audioMuted: false, localAudioRunning: false,
      recentRecording: this.#recentRecording !== null,
      recentSnapshot: this.#recentSnapshot !== null,
      lastSavedFile: null,
      uploadingLogs: false,
      lastError: firstError === null ? null : failureOf(firstError), metrics: null,
    };
    this.publish();
    if (firstError !== null) throw firstError;
  }

  private async replaceRecent(kind: 'recording' | 'snapshot', file: TiRtcMediaFile): Promise<void> {
    if (kind === 'recording') {
      const previous = this.#recentRecording;
      this.#recentRecording = file as TiRtcRecordingFile;
      this.update({recentRecording: true, lastSavedFile: null});
      if (previous !== null) {
        try { await this.deleteRecent(previous); } catch (reason) {
          this.#retiredMedia.add(previous);
          throw reason;
        }
      }
    } else {
      const previous = this.#recentSnapshot;
      this.#recentSnapshot = file as TiRtcSnapshotFile;
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
    if (this.#quiescing) throw new Error('RTC session is leaving');
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

  private publishMetrics(): void {
    if (this.#connection === null || this.#audioOutput === null || this.#videoOutput === null) return;
    try {
      this.update({metrics: {
        connection: this.#connection.getMetricsSnapshot(),
        audio: this.#audioOutput.getMetricsSnapshot(),
        video: this.#videoOutput.getMetricsSnapshot(),
      }});
    } catch {}
  }

  private captureFailure(reason: unknown): void {
    const failure = failureOf(reason);
    this.update({phase: 'failed', message: failure.message, lastError: failure});
  }

  private update(patch: Partial<ExampleState>): void {
    this.#state = {...this.#state, ...patch};
    this.publish();
  }

  private publish(): void {
    if (!this.#window.isDestroyed()) this.#window.webContents.send('tirtc-example:state', this.#state);
  }
}
