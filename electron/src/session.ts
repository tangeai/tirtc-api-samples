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
  TiRawDump,
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
type OperationOwner = 'core' | 'connection' | 'videoOutput' | 'recording' | 'rawDump' | 'file';

export class ExampleSession {
  readonly #window: BrowserWindow;
  readonly #operationDrainTimeoutMs: number;
  #connection: TiRtcConn | null = null;
  #audioInput: TiRtcAudioInput | null = null;
  #audioOutput: TiRtcAudioOutput | null = null;
  #videoOutputs = new Map<number, TiRtcVideoOutput>();
  #unavailableVideoStreamIds = new Set<number>();
  #remoteViews = new Map<number, TiVideoView>();
  #acceptVideoBounds = false;
  #metricsTimer: ReturnType<typeof setInterval> | null = null;
  #recordingTask: TiRtcRecordingTask | null = null;
  #rawDump: TiRawDump | null = null;
  #rawDumpPendingUpload = false;
  #recentRecording: TiRtcRecordingFile | null = null;
  #recentSnapshot: TiRtcSnapshotFile | null = null;
  #recentRecordingTargetId: number | null = null;
  #recentSnapshotTargetId: number | null = null;
  #persistedDestinations = new WeakMap<TiRtcMediaFile, string>();
  #retiredMedia = new Set<TiRtcMediaFile>();
  #acceptedOperations = new OperationBarrier<OperationOwner>();
  #quiescing = true;
  #leavePromise: Promise<void> | null = null;
  #initialized = false;
  #audioStreamId: number | null = AUDIO_STREAM_ID;
  #localAudioStreamId: number | null = null;
  #videoStreamIds: ReadonlyArray<number> = [VIDEO_STREAM_ID];
  #selectedVideoStreamId: number | null = VIDEO_STREAM_ID;
  #recordingTargetId: number | null = null;
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
    rawDumpPhase: 'idle',
    rawDumpCaptureId: null,
    lastError: null,
    metrics: null,
    videoStates: {},
    videoStreamIds: [VIDEO_STREAM_ID],
    selectedVideoStreamId: VIDEO_STREAM_ID,
    hasAudio: true,
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
      const audioStreamId = config.audioStreamId === undefined ? AUDIO_STREAM_ID : config.audioStreamId;
      const videoStreamIds = config.videoStreamIds === undefined ? [VIDEO_STREAM_ID] : [...config.videoStreamIds];
      if ((audioStreamId !== null && (!Number.isSafeInteger(audioStreamId) || audioStreamId < 0 || audioStreamId > 15)) ||
          videoStreamIds.length > 3 || videoStreamIds.some((id) => !Number.isSafeInteger(id) || id < 0 || id > 15) ||
          new Set(videoStreamIds).size !== videoStreamIds.length ||
          (audioStreamId !== null && videoStreamIds.includes(audioStreamId))) {
        throw new TypeError('select optional audio and up to three distinct video Stream IDs from 0 through 15');
      }
      const settings = config.settings ?? DEFAULT_SETTINGS;
      if (!Number.isSafeInteger(settings.localAudioStreamId) || settings.localAudioStreamId < 0 ||
          settings.localAudioStreamId > 15) {
        throw new TypeError('local audio Stream ID must be an integer from 0 through 15');
      }
      this.#audioStreamId = audioStreamId;
      this.#videoStreamIds = videoStreamIds;
      this.#selectedVideoStreamId = videoStreamIds[0] ?? null;
      this.#unavailableVideoStreamIds.clear();
      TiRtc.init({
        appId: config.appId,
        endpoint: config.endpoint,
        consoleLogEnabled: settings.consoleLogEnabled,
      });
      this.#initialized = true;
      const connection = new TiRtcConn();
      const audioInput = new TiRtcAudioInput();
      const audioOutput = audioStreamId === null ? null : new TiRtcAudioOutput();
      this.#connection = connection;
      this.#audioInput = audioInput;
      this.#audioOutput = audioOutput;

      connection.onStateChanged = (state, error) => {
        if (this.#quiescing || this.#connection !== connection) return;
        this.update({
          connectionState: state,
          phase: state === 'connected' ? 'playing' : this.#state.phase,
        });
        if (state === 'connected') {
          if (this.#audioStreamId !== null && this.#audioOutput !== null) {
            try { connection.subscribeAudio(this.#audioStreamId); } catch (reason) {
              this.retireAudioOutput(this.#audioOutput, reason, '订阅');
            }
          }
          for (const streamId of this.#videoStreamIds) {
            if (this.#unavailableVideoStreamIds.has(streamId)) continue;
            try { connection.subscribeVideo(streamId); } catch (reason) {
              this.markVideoUnavailable(streamId, reason, '订阅');
            }
          }
        }
        if (error !== null) this.captureFailure(error);
      };
      connection.onStreamMessage = (_streamId, _timestampMs, data) => {
        if (this.#quiescing || this.#connection !== connection) return;
        this.update({message: new TextDecoder().decode(data), messageDirection: 'received', messageCommandId: null});
      };
      connection.onCommand = (commandId, data) => {
        if (this.#quiescing || this.#connection !== connection) return;
        this.update({message: new TextDecoder().decode(data), messageDirection: 'received', messageCommandId: commandId});
      };
      if (audioOutput !== null) {
        audioOutput.onStateChanged = (state) => {
          if (this.#quiescing || this.#audioOutput !== audioOutput) return;
          this.update({audioState: state});
          if (state === 'failed') this.retireAudioOutput(audioOutput, new Error('audio output failed'), '播放');
        };
        audioOutput.onError = (error) => {
          if (!this.#quiescing && this.#audioOutput === audioOutput) {
            this.retireAudioOutput(audioOutput, error, '播放');
          }
        };
      }
      audioInput.onStateChanged = (state) => {
        if (!this.#quiescing && this.#audioInput === audioInput) {
          this.update({localAudioRunning: state === 'running'});
        }
      };
      audioInput.onError = (error) => {
        if (!this.#quiescing && this.#audioInput === audioInput) {
          this.update({localAudioRunning: false, message: `麦克风失败：${failureOf(error).message}`});
        }
      };

      try {
        audioInput.setOptions({
          media: {pcm: 1, g711a: 2, aac: 3, opus: 4, amr: 5}[settings.localAudioCodec],
          sampleRateHz: settings.localAudioCodec === 'amr' ? 8000 : settings.localAudioSampleRateHz,
          channels: 1,
          aecMode: settings.localAudioAecEnabled ? 'enabled' : 'disabled',
          agcLevel: settings.localAudioAgcLevel,
          ansLevel: settings.localAudioAnsLevel,
        });
        audioInput.attach(connection, settings.localAudioStreamId);
        this.#localAudioStreamId = settings.localAudioStreamId;
      } catch (reason) {
        try { audioInput.dispose(); } catch {}
        if (this.#audioInput === audioInput) this.#audioInput = null;
        this.update({localAudioRunning: false, message: `麦克风准备失败：${failureOf(reason).message}`});
      }
      if (audioOutput !== null && this.#audioStreamId !== null) {
        try {
          audioOutput.setOptions({bufferStrategy: settings.outputBufferPolicy});
          audioOutput.attach(connection, this.#audioStreamId);
        } catch (reason) {
          this.retireAudioOutput(audioOutput, reason, '准备');
        }
      }
      const videoStates: Record<string, string> = {};
      for (const streamId of this.#videoStreamIds) {
        const output = new TiRtcVideoOutput();
        this.#videoOutputs.set(streamId, output);
        videoStates[String(streamId)] = 'idle';
        output.onError = (error) => {
          if (!this.#quiescing && this.#videoOutputs.get(streamId) === output) {
            this.markVideoUnavailable(streamId, error, '播放');
          }
        };
        output.onStateChanged = (state) => {
          if (this.#quiescing || this.#videoOutputs.get(streamId) !== output) return;
          this.update({videoStates: {...this.#state.videoStates, [streamId]: state}});
          if (state === 'failed') this.#unavailableVideoStreamIds.add(streamId);
        };
        output.onRenderSizeChanged = () => {
          if (!this.#quiescing && this.#videoOutputs.get(streamId) === output) this.publish();
        };
        try {
          output.setOptions({decoderPreference: settings.videoDecoderPreference, bufferStrategy: settings.outputBufferPolicy});
          output.attach(connection, streamId);
        } catch (reason) {
          videoStates[String(streamId)] = 'failed';
          this.#unavailableVideoStreamIds.add(streamId);
          this.update({message: `视频 Stream ${streamId} 准备失败：${failureOf(reason).message}`});
        }
      }
      this.#acceptVideoBounds = true;
      this.#metricsTimer = setInterval(() => this.publishMetrics(), 1000);
      this.update({phase: 'connecting', lastError: null, message: this.#state.message,
        messageDirection: null, messageCommandId: null, videoStates,
        videoStreamIds: this.#videoStreamIds,
        selectedVideoStreamId: this.#selectedVideoStreamId, hasAudio: this.#audioOutput !== null});
      connection.connect({remoteId: config.remoteId, token: config.token});
    } catch (reason) {
      let failure = reason;
      try { await this.leave(); } catch (cleanupError) { failure = cleanupError; }
      this.captureFailure(failure);
      throw failure;
    }
  }

  setVideoBounds(streamId: number, bounds: Rectangle): void {
    if (this.#quiescing) return;
    const output = this.#videoOutputs.get(streamId);
    if (!this.#acceptVideoBounds || output === undefined) return;
    const existing = this.#remoteViews.get(streamId);
    if (existing === undefined) {
      const view = new TiVideoView(this.#window, bounds);
      output.mount(view);
      this.#remoteViews.set(streamId, view);
    } else {
      existing.setBounds(bounds);
    }
  }

  selectVideoStream(streamId: number): void {
    this.ensureAccepting();
    if (!this.#videoOutputs.has(streamId)) throw new TypeError('video Stream ID is not configured');
    this.#selectedVideoStreamId = streamId;
    this.update({selectedVideoStreamId: streamId});
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
      videoStreamId: this.requireSelectedVideoStreamId(),
      audioStreamId: this.#audioStreamId ?? undefined,
    });
    this.#recordingTargetId = this.#selectedVideoStreamId;
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
      await this.replaceRecent('recording', file, this.#recordingTargetId);
      this.#recordingTargetId = null;
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
    const output = this.selectedVideoOutput();
    if (output === null) throw new Error('video output is unavailable');
    try {
      const targetId = this.#selectedVideoStreamId;
      await this.replaceRecent('snapshot', await output.takeSnapshot(), targetId);
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

  recentTargetId(kind: 'recording' | 'snapshot'): number | null {
    return kind === 'recording' ? this.#recentRecordingTargetId : this.#recentSnapshotTargetId;
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
    if (this.#rawDump !== null) await this.stopRawDumpOwned(false);
    await this.uploadCompletedDiagnostics();
  }

  toggleRawDump(): Promise<void> {
    this.ensureAccepting();
    return this.track(this.toggleRawDumpOwned(), 'rawDump', 'connection', 'core');
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
    if (this.#connection === null || this.#state.connectionState !== 'connected') {
      throw new Error('raw dump requires a connected RTC session');
    }
    this.#rawDump = await this.#connection.startRawDump({
      audioStreamIds: this.#audioStreamId === null ? [] : [this.#audioStreamId],
      videoStreamIds: this.#videoStreamIds,
      uplinkAudioStreamIds: this.#localAudioStreamId === null ? [] : [this.#localAudioStreamId],
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
      this.update({uploadingLogs: false, message: `Log ID: ${logId}`,
        messageDirection: null, messageCommandId: null, lastError: null,
        rawDumpPhase: this.#state.rawDumpCaptureId === null ? 'idle' : 'completed'});
    } catch (reason) {
      this.update({uploadingLogs: false,
        rawDumpPhase: this.#rawDumpPendingUpload ? 'failed' : this.#state.rawDumpPhase});
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
    if (this.#rawDump !== null && !this.ownerBusy('rawDump')) {
      await attempt(() => this.track(this.stopRawDumpOwned(false), 'rawDump', 'connection', 'core'));
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
    if (!this.ownerBusy('videoOutput')) {
      for (const [streamId, output] of this.#videoOutputs) {
        await attempt(() => retryWhileInUse(() => output.detach()));
        await attempt(() => retryWhileInUse(() => output.unmount()));
        const view = this.#remoteViews.get(streamId);
        if (view !== undefined && await attempt(() => retryWhileInUse(() => view.dispose()))) {
          this.#remoteViews.delete(streamId);
        }
        if (await attempt(() => retryWhileInUse(() => output.dispose()))) {
          this.#videoOutputs.delete(streamId);
          this.#unavailableVideoStreamIds.delete(streamId);
        }
      }
      for (const [streamId, view] of this.#remoteViews) {
        if (this.#videoOutputs.has(streamId)) continue;
        if (await attempt(() => retryWhileInUse(() => view.dispose()))) this.#remoteViews.delete(streamId);
      }
    }
    if (this.#connection !== null && !this.ownerBusy('connection') && this.#audioInput === null &&
        this.#audioOutput === null && this.#videoOutputs.size === 0 && this.#recordingTask === null &&
        this.#rawDump === null) {
      await attempt(() => retryWhileInUse(() => this.#connection!.disconnect()));
      if (await attempt(() => retryWhileInUse(() => this.#connection!.dispose()))) this.#connection = null;
    }
    if (this.#initialized && this.#connection === null && this.#audioInput === null &&
        this.#audioOutput === null && this.#videoOutputs.size === 0 && this.#remoteViews.size === 0 &&
        this.#recordingTask === null && this.#rawDump === null && this.#recentRecording === null &&
        this.#recentSnapshot === null &&
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
      rawDumpPhase: 'idle',
      rawDumpCaptureId: null,
      lastError: firstError === null ? null : failureOf(firstError), metrics: null,
      videoStates: {}, videoStreamIds: [], selectedVideoStreamId: null, hasAudio: false,
    };
    this.#rawDumpPendingUpload = false;
    this.#localAudioStreamId = null;
    this.publish();
    if (firstError !== null) throw firstError;
  }

  private async replaceRecent(kind: 'recording' | 'snapshot', file: TiRtcMediaFile, targetId: number | null): Promise<void> {
    if (kind === 'recording') {
      const previous = this.#recentRecording;
      this.#recentRecording = file as TiRtcRecordingFile;
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
      this.#recentSnapshot = file as TiRtcSnapshotFile;
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
    if (this.#connection === null) return;
    const videoOutput = this.selectedVideoOutput();
    try {
      this.update({metrics: {
        connection: this.#connection.getMetricsSnapshot(),
        audio: this.#audioOutput?.getMetricsSnapshot() ?? null,
        video: videoOutput?.getMetricsSnapshot() ?? null,
      }});
    } catch {}
  }

  private selectedVideoOutput(): TiRtcVideoOutput | null {
    return this.#selectedVideoStreamId === null || this.#unavailableVideoStreamIds.has(this.#selectedVideoStreamId)
      ? null : this.#videoOutputs.get(this.#selectedVideoStreamId) ?? null;
  }

  private retireAudioOutput(output: TiRtcAudioOutput, reason: unknown, phase: string): void {
    if (this.#audioOutput !== output) return;
    if (this.#connection !== null && this.#audioStreamId !== null) {
      try { this.#connection.unsubscribeAudio(this.#audioStreamId); } catch {}
    }
    try { output.detach(); } catch {}
    try { output.dispose(); } catch {}
    this.#audioOutput = null;
    this.update({audioState: 'failed', hasAudio: false,
      message: `音频${phase}失败：${failureOf(reason).message}`});
  }

  private markVideoUnavailable(streamId: number, reason: unknown, phase: string): void {
    this.#unavailableVideoStreamIds.add(streamId);
    this.update({
      videoStates: {...this.#state.videoStates, [streamId]: 'failed'},
      message: `视频 Stream ${streamId} ${phase}失败：${failureOf(reason).message}`,
    });
  }

  private requireSelectedVideoStreamId(): number {
    if (this.#selectedVideoStreamId === null ||
        this.#unavailableVideoStreamIds.has(this.#selectedVideoStreamId) ||
        this.#state.videoStates[String(this.#selectedVideoStreamId)] !== 'rendering') {
      throw new Error('video output is unavailable');
    }
    return this.#selectedVideoStreamId;
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
