import {
  TiCloudStorage,
  TiCloudStorageAudioOutput,
  TiCloudStorageAudioOutputState,
  TiCloudStorageExportTask,
  TiCloudStorageRecordingFile,
  TiCloudStorageRecordingDaysResult,
  TiCloudStorageRecordingRange,
  TiCloudStorageRecordingRangesResult,
  TiCloudStorageRecordingTask,
  TiCloudStorageReplay,
  TiCloudStorageReplaySpeed,
  TiCloudStorageSnapshotFile,
  TiCloudStorageVideoOutput,
  TiCloudStorageVideoOutputState,
  TiRawDump,
  TI_CLOUD_STORAGE_ERROR_IN_USE,
  TI_CLOUD_STORAGE_ERROR_INVALID_ARGUMENT,
  TI_CLOUD_STORAGE_ERROR_OK,
} from 'tirtc/Index';
import type {
  TiCloudStorageExportProgress,
  TiCloudStorageExportReport,
  TiCloudStorageRecordingGap,
} from 'tirtc/Index';

const RAW_DUMP_STOP_RETRY_DELAY_MS = 50;
const RAW_DUMP_STOP_RETRY_LIMIT = 20;

export class TiCloudStorageRawDumpToggleResult {
  readonly capturing: boolean;
  readonly code: number;
  readonly captureId: string;

  constructor(
    capturing: boolean,
    code: number,
    captureId: string = '',
  ) {
    this.capturing = capturing;
    this.code = code;
    this.captureId = captureId;
  }
}

export interface TiCloudStorageExampleFlowListener {
  onReplayState: (state: string) => void;
  onVideoState: (channelId: number, state: string) => void;
  onTimeChanged: (timeMs: number) => void;
  onError: (code: number) => void;
  onExportProgress: (progress: number) => void;
  onExportProgressDetail?: (progress: TiCloudStorageExportProgress) => void;
  onRecordingGap?: (gap: TiCloudStorageRecordingGap) => void;
  onExportReport?: (report: TiCloudStorageExportReport) => void;
  onMediaChanged: (kind: string) => void;
}

export class TiCloudStorageExampleFlow {
  readonly audioOutput: TiCloudStorageAudioOutput = new TiCloudStorageAudioOutput();
  readonly videoOutputs: Array<TiCloudStorageVideoOutput>;
  private readonly cloudStorage: TiCloudStorage;
  private readonly listener: TiCloudStorageExampleFlowListener;
  private playbackGeneration: number = 0;
  private replay?: TiCloudStorageReplay;
  private recordingTask?: TiCloudStorageRecordingTask;
  private rawDump?: TiRawDump;
  private exportTask?: TiCloudStorageExportTask;
  private exportCompletion?: Promise<number>;
  private mediaOperation?: Promise<number>;
  private recentRecording?: TiCloudStorageRecordingFile;
  private recentSnapshot?: TiCloudStorageSnapshotFile;
  private latestKind: string = '';
  private recordingTargetId: number | null = null;
  private latestMediaTargetId: number = -1;
  private readonly recordingQueries: Array<Promise<TiCloudStorageRecordingRangesResult>> = [];
  private readonly dayQueries: Array<Promise<TiCloudStorageRecordingDaysResult>> = [];
  private disposed: boolean = false;
  private readonly videoChannelIds: Array<number>;
  private selectedVideoChannelId: number | null;
  private playbackVideoStates: Array<TiCloudStorageVideoOutputState>;
  private playbackAudioState: TiCloudStorageAudioOutputState = TiCloudStorageAudioOutputState.idle;

  constructor(token: string, videoChannelIds: Array<number>, listener: TiCloudStorageExampleFlowListener) {
    this.cloudStorage = new TiCloudStorage(token);
    this.videoChannelIds = videoChannelIds.slice();
    this.videoOutputs = videoChannelIds.map((): TiCloudStorageVideoOutput => new TiCloudStorageVideoOutput());
    this.playbackVideoStates = videoChannelIds.map((): TiCloudStorageVideoOutputState =>
      TiCloudStorageVideoOutputState.idle);
    this.selectedVideoChannelId = videoChannelIds.length > 0 ? videoChannelIds[0] : null;
    this.listener = listener;
  }

  public selectVideoChannel(channelId: number): void {
    if (this.videoChannelIds.indexOf(channelId) >= 0) this.selectedVideoChannelId = channelId;
  }

  public async query(startTimeMs: number, endTimeMs: number): Promise<TiCloudStorageRecordingRangesResult> {
    if (this.disposed) return { code: TI_CLOUD_STORAGE_ERROR_INVALID_ARGUMENT, recordings: [] };
    const operation = this.cloudStorage.listRecordings(startTimeMs, endTimeMs);
    this.recordingQueries.push(operation);
    const result = await operation.finally((): void => {
      const index = this.recordingQueries.indexOf(operation);
      if (index >= 0) this.recordingQueries.splice(index, 1);
    });
    if (result.code !== TI_CLOUD_STORAGE_ERROR_OK) {
      this.listener.onError(result.code);
    }
    return result;
  }

  public async queryDays(
    startDate: string,
    endDate: string,
    timeZoneId: string,
  ): Promise<TiCloudStorageRecordingDaysResult> {
    if (this.disposed) return { code: TI_CLOUD_STORAGE_ERROR_INVALID_ARGUMENT, days: [] };
    const operation = this.cloudStorage.listRecordingDays(startDate, endDate, timeZoneId);
    this.dayQueries.push(operation);
    const result = await operation.finally((): void => {
      const index = this.dayQueries.indexOf(operation);
      if (index >= 0) this.dayQueries.splice(index, 1);
    });
    if (result.code !== TI_CLOUD_STORAGE_ERROR_OK) this.listener.onError(result.code);
    return result;
  }

  public play(range: TiCloudStorageRecordingRange, audioChannelId: number | null): number {
    if (this.disposed || range.endTimeMs <= range.startTimeMs) {
      return TI_CLOUD_STORAGE_ERROR_INVALID_ARGUMENT;
    }
    this.playbackGeneration += 1;
    const generation = this.playbackGeneration;
    const released = this.releasePlayback();
    if (released !== TI_CLOUD_STORAGE_ERROR_OK) {
      return released;
    }
    this.playbackVideoStates = this.videoChannelIds.map((): TiCloudStorageVideoOutputState =>
      TiCloudStorageVideoOutputState.idle);
    this.playbackAudioState = TiCloudStorageAudioOutputState.idle;
    for (let index = 0; index < this.videoOutputs.length; index += 1) {
      const output = this.videoOutputs[index];
      const channelId = this.videoChannelIds[index];
      output.onStateChanged = (state: TiCloudStorageVideoOutputState): void => {
        if (!this.isPlaybackCurrent(generation)) return;
        this.playbackVideoStates[index] = state;
        const label = this.videoStateLabel(state);
        this.listener.onVideoState(channelId, label);
        if (this.outputsCompleted(audioChannelId !== null)) {
          this.listener.onReplayState('completed');
        } else if (channelId === this.selectedVideoChannelId && state !== TiCloudStorageVideoOutputState.completed) {
          this.listener.onReplayState(label);
        }
      };
      output.onError = (code: number): void => {
        if (this.isPlaybackCurrent(generation)) {
          this.playbackVideoStates[index] = TiCloudStorageVideoOutputState.failed;
          this.listener.onVideoState(channelId, 'failed');
        }
      };
    }
    if (audioChannelId !== null) {
      this.audioOutput.onStateChanged = (state: TiCloudStorageAudioOutputState): void => {
        if (!this.isPlaybackCurrent(generation)) return;
        this.playbackAudioState = state;
        if (this.outputsCompleted(true)) {
          this.listener.onReplayState('completed');
        } else if (this.videoOutputs.length === 0) {
          this.listener.onReplayState(this.audioStateLabel(state));
        }
      };
      this.audioOutput.onError = (code: number): void => {
        if (!this.isPlaybackCurrent(generation)) return;
        this.playbackAudioState = TiCloudStorageAudioOutputState.failed;
        this.listener.onReplayState('audio failed');
      };
    }
    const replay = this.cloudStorage.createReplay();
    replay.onTimeChanged = (timeMs: number): void => {
      if (this.isPlaybackCurrent(generation)) this.listener.onTimeChanged(timeMs);
    };
    replay.onError = (code: number): void => {
      if (this.isPlaybackCurrent(generation)) this.listener.onError(code);
    };
    replay.onRecordingGap = (gap: TiCloudStorageRecordingGap): void => {
      if (this.isPlaybackCurrent(generation)) this.listener.onRecordingGap?.(gap);
    };
    this.replay = replay;
    let code = TI_CLOUD_STORAGE_ERROR_OK;
    let attachedVideoCount = 0;
    let firstVideoError = TI_CLOUD_STORAGE_ERROR_OK;
    for (let index = 0; index < this.videoOutputs.length; index += 1) {
      const laneCode = this.videoOutputs[index].attach(replay, this.videoChannelIds[index]);
      if (laneCode === TI_CLOUD_STORAGE_ERROR_OK) {
        attachedVideoCount += 1;
      } else {
        if (firstVideoError === TI_CLOUD_STORAGE_ERROR_OK) firstVideoError = laneCode;
        this.playbackVideoStates[index] = TiCloudStorageVideoOutputState.failed;
        this.listener.onVideoState(this.videoChannelIds[index], 'failed');
      }
    }
    let audioAttached = false;
    if (audioChannelId !== null) {
      code = this.audioOutput.attach(replay, audioChannelId);
      audioAttached = code === TI_CLOUD_STORAGE_ERROR_OK;
      if (!audioAttached) {
        this.playbackAudioState = TiCloudStorageAudioOutputState.failed;
        this.listener.onReplayState('audio failed');
      }
    }
    if (attachedVideoCount > 0 || audioAttached) {
      code = replay.play(range.startTimeMs, range.endTimeMs);
    } else if (audioChannelId === null && this.videoOutputs.length > 0) {
      code = firstVideoError;
    } else if (audioChannelId === null) {
      code = TI_CLOUD_STORAGE_ERROR_INVALID_ARGUMENT;
    }
    if (code !== TI_CLOUD_STORAGE_ERROR_OK) {
      this.releasePlayback();
      this.listener.onError(code);
    }
    return code;
  }

  public pause(): number {
    return this.replay?.pause() ?? TI_CLOUD_STORAGE_ERROR_INVALID_ARGUMENT;
  }

  public resume(): number {
    return this.replay?.resume() ?? TI_CLOUD_STORAGE_ERROR_INVALID_ARGUMENT;
  }

  public seek(timeMs: number): number {
    return this.replay?.seek(timeMs) ?? TI_CLOUD_STORAGE_ERROR_INVALID_ARGUMENT;
  }

  public setSpeed(speed: TiCloudStorageReplaySpeed): number {
    return this.replay?.setSpeed(speed) ?? TI_CLOUD_STORAGE_ERROR_INVALID_ARGUMENT;
  }

  public setMuted(muted: boolean): number {
    return this.replay === undefined ? TI_CLOUD_STORAGE_ERROR_INVALID_ARGUMENT : this.audioOutput.setVolume(muted ? 0 : 100);
  }

  public async toggleRawDump(audioChannelId: number | null): Promise<TiCloudStorageRawDumpToggleResult> {
    if (this.rawDump !== undefined) {
      const result = await this.rawDump.stop();
      if (!result.success || result.data === null) {
        return new TiCloudStorageRawDumpToggleResult(true, result.code ?? TI_CLOUD_STORAGE_ERROR_INVALID_ARGUMENT);
      }
      this.rawDump = undefined;
      return new TiCloudStorageRawDumpToggleResult(false, TI_CLOUD_STORAGE_ERROR_OK, result.data.captureId);
    }
    if (this.replay === undefined) {
      return new TiCloudStorageRawDumpToggleResult(false, TI_CLOUD_STORAGE_ERROR_INVALID_ARGUMENT);
    }
    const result = await this.replay.startRawDump({
      audioChannelIds: audioChannelId === null ? [] : [audioChannelId],
      videoChannelIds: this.videoChannelIds,
    });
    if (!result.success || result.data === null) {
      return new TiCloudStorageRawDumpToggleResult(false, result.code ?? TI_CLOUD_STORAGE_ERROR_INVALID_ARGUMENT);
    }
    this.rawDump = result.data;
    return new TiCloudStorageRawDumpToggleResult(true, TI_CLOUD_STORAGE_ERROR_OK);
  }

  public startRecording(videoChannelId: number, audioChannelId: number | null): number {
    if (this.replay === undefined || this.recordingTask !== undefined || this.mediaOperation !== undefined) {
      return TI_CLOUD_STORAGE_ERROR_IN_USE;
    }
    const result = audioChannelId === null ? this.replay.startRecording({ videoChannelId }) :
      this.replay.startRecording({ videoChannelId, audioChannelId });
    if (!result.success || result.data === null) {
      return result.code ?? TI_CLOUD_STORAGE_ERROR_INVALID_ARGUMENT;
    }
    this.recordingTask = result.data;
    this.recordingTargetId = videoChannelId;
    return TI_CLOUD_STORAGE_ERROR_OK;
  }

  public stopRecording(): Promise<number> {
    const task = this.recordingTask;
    if (task === undefined) {
      return Promise.resolve(TI_CLOUD_STORAGE_ERROR_INVALID_ARGUMENT);
    }
    if (this.mediaOperation !== undefined) {
      return Promise.resolve(TI_CLOUD_STORAGE_ERROR_IN_USE);
    }
    this.recordingTask = undefined;
    return this.runMediaOperation(async (): Promise<number> => {
      const result = await task.stop();
      if (!result.success || result.data === null) {
        return result.code ?? TI_CLOUD_STORAGE_ERROR_INVALID_ARGUMENT;
      }
      const targetId = this.recordingTargetId ?? -1;
      this.recordingTargetId = null;
      return this.replaceRecording(result.data, targetId);
    });
  }

  public takeSnapshot(): Promise<number> {
    if (this.replay === undefined) {
      return Promise.resolve(TI_CLOUD_STORAGE_ERROR_INVALID_ARGUMENT);
    }
    return this.runMediaOperation(async (): Promise<number> => {
      const output = this.selectedVideoOutput();
      if (output === undefined) return TI_CLOUD_STORAGE_ERROR_INVALID_ARGUMENT;
      const targetId = this.selectedVideoChannelId ?? -1;
      const result = await output.takeSnapshot();
      if (!result.success || result.data === null) {
        return result.code ?? TI_CLOUD_STORAGE_ERROR_INVALID_ARGUMENT;
      }
      const previous = this.recentSnapshot;
      if (previous !== undefined) {
        const deleted = await previous.delete();
        if (deleted !== TI_CLOUD_STORAGE_ERROR_OK) {
          await result.data.delete();
          return deleted;
        }
      }
      this.recentSnapshot = result.data;
      this.latestKind = 'snapshot';
      this.latestMediaTargetId = targetId;
      this.listener.onMediaChanged(this.latestKind);
      return TI_CLOUD_STORAGE_ERROR_OK;
    });
  }

  public exportRecording(
    range: TiCloudStorageRecordingRange,
    videoChannelId: number,
    audioChannelId: number | null,
  ): Promise<number> {
    if (this.exportTask !== undefined || this.exportCompletion !== undefined) {
      return Promise.resolve(TI_CLOUD_STORAGE_ERROR_IN_USE);
    }
    const started = this.cloudStorage.exportRecording(audioChannelId === null ? {
      startTimeMs: range.startTimeMs,
      endTimeMs: range.endTimeMs,
      videoChannelId,
    } : {
      startTimeMs: range.startTimeMs,
      endTimeMs: range.endTimeMs,
      videoChannelId,
      audioChannelId,
    }, (progress: number): void => this.listener.onExportProgress(progress), {
      onProgressDetail: (progress: TiCloudStorageExportProgress): void =>
        this.listener.onExportProgressDetail?.(progress),
      onRecordingGap: (gap: TiCloudStorageRecordingGap): void =>
        this.listener.onRecordingGap?.(gap),
    });
    if (!started.success || started.data === null) {
      return Promise.resolve(started.code ?? TI_CLOUD_STORAGE_ERROR_INVALID_ARGUMENT);
    }
    this.exportTask = started.data;
    const targetId = videoChannelId;
    const completion = started.data.detailedResult.then(async (result): Promise<number> => {
      this.exportTask = undefined;
      if (!result.success || result.data === null) {
        return result.code ?? TI_CLOUD_STORAGE_ERROR_INVALID_ARGUMENT;
      }
      this.listener.onExportReport?.(result.data.report);
      return this.replaceRecording(result.data.file, targetId);
    });
    this.exportCompletion = completion;
    return completion.then((code: number): number => {
      if (this.exportCompletion === completion) {
        this.exportCompletion = undefined;
      }
      return code;
    });
  }

  public isRecording(): boolean {
    return this.recordingTask !== undefined;
  }

  public isMediaBusy(): boolean {
    return this.mediaOperation !== undefined;
  }

  public latestMediaPath(): string {
    if (this.latestKind === 'snapshot') {
      return this.recentSnapshot?.path ?? '';
    }
    if (this.latestKind === 'recording') {
      return this.recentRecording?.path ?? '';
    }
    return '';
  }

  public latestMediaKind(): string {
    return this.latestKind;
  }

  public latestMediaTarget(): number {
    return this.latestMediaTargetId;
  }

  public async deleteLatestMedia(): Promise<number> {
    const latestKind = this.latestKind;
    const file = latestKind === 'snapshot' ? this.recentSnapshot : this.recentRecording;
    if (file === undefined) {
      return TI_CLOUD_STORAGE_ERROR_INVALID_ARGUMENT;
    }
    const code = await file.delete();
    if (code === TI_CLOUD_STORAGE_ERROR_OK) {
      if (latestKind === 'snapshot') {
        this.recentSnapshot = undefined;
      } else {
        this.recentRecording = undefined;
      }
      this.latestKind = '';
      this.latestMediaTargetId = -1;
      this.listener.onMediaChanged('');
    }
    return code;
  }

  public async dispose(): Promise<number> {
    if (this.disposed) {
      return TI_CLOUD_STORAGE_ERROR_OK;
    }
    let first = TI_CLOUD_STORAGE_ERROR_OK;
    const note = (code: number): void => {
      if (first === TI_CLOUD_STORAGE_ERROR_OK && code !== TI_CLOUD_STORAGE_ERROR_OK) {
        first = code;
      }
    };
    if (this.rawDump !== undefined) {
      const rawDump = this.rawDump;
      let rawDumpResult = await rawDump.stop();
      for (let attempt = 0;
        !rawDumpResult.success && rawDumpResult.code === TI_CLOUD_STORAGE_ERROR_IN_USE &&
          attempt < RAW_DUMP_STOP_RETRY_LIMIT;
        attempt += 1) {
        await new Promise<void>((resolve): void => {
          setTimeout(resolve, RAW_DUMP_STOP_RETRY_DELAY_MS);
        });
        rawDumpResult = await rawDump.stop();
      }
      if (!rawDumpResult.success && rawDumpResult.code === TI_CLOUD_STORAGE_ERROR_IN_USE) {
        return TI_CLOUD_STORAGE_ERROR_IN_USE;
      }
      note(rawDumpResult.success ? TI_CLOUD_STORAGE_ERROR_OK :
        (rawDumpResult.code ?? TI_CLOUD_STORAGE_ERROR_INVALID_ARGUMENT));
      this.rawDump = undefined;
    }
    this.disposed = true;
    this.playbackGeneration += 1;
    if (this.mediaOperation !== undefined) {
      note(await this.mediaOperation);
    }
    try {
      await Promise.all(this.recordingQueries.slice());
      await Promise.all(this.dayQueries.slice());
    } catch (_) {
      note(TI_CLOUD_STORAGE_ERROR_INVALID_ARGUMENT);
    }
    if (this.exportTask !== undefined) {
      const stopped = await this.exportTask.stop();
      note(stopped.success ? TI_CLOUD_STORAGE_ERROR_OK : stopped.code ?? TI_CLOUD_STORAGE_ERROR_INVALID_ARGUMENT);
    }
    if (this.exportCompletion !== undefined) {
      note(await this.exportCompletion);
    }
    if (this.recordingTask !== undefined) {
      note(await this.stopRecording());
    }
    note(this.releasePlayback());
    note(this.audioOutput.dispose());
    for (const output of this.videoOutputs) note(output.dispose());
    if (this.recentRecording !== undefined) {
      note(await this.recentRecording.delete());
    }
    if (this.recentSnapshot !== undefined) {
      note(await this.recentSnapshot.delete());
    }
    this.recentRecording = undefined;
    this.recentSnapshot = undefined;
    this.latestKind = '';
    this.latestMediaTargetId = -1;
    note(this.cloudStorage.dispose());
    return first;
  }

  private releasePlayback(): number {
    let first = TI_CLOUD_STORAGE_ERROR_OK;
    const note = (code: number): void => {
      if (first === TI_CLOUD_STORAGE_ERROR_OK && code !== TI_CLOUD_STORAGE_ERROR_OK) {
        first = code;
      }
    };
    if (this.replay !== undefined) {
      note(this.replay.stop());
    }
    note(this.audioOutput.detach());
    for (const output of this.videoOutputs) note(output.detach());
    if (this.replay !== undefined) {
      note(this.replay.dispose());
    }
    this.replay = undefined;
    return first;
  }

  private isPlaybackCurrent(generation: number): boolean {
    return !this.disposed && generation === this.playbackGeneration;
  }

  private runMediaOperation(operation: () => Promise<number>): Promise<number> {
    if (this.mediaOperation !== undefined) {
      return Promise.resolve(TI_CLOUD_STORAGE_ERROR_IN_USE);
    }
    const started = operation();
    this.mediaOperation = started;
    return started.then((code: number): number => {
      if (this.mediaOperation === started) {
        this.mediaOperation = undefined;
      }
      return code;
    });
  }

  private async replaceRecording(file: TiCloudStorageRecordingFile, targetId: number): Promise<number> {
    const previous = this.recentRecording;
    if (previous !== undefined) {
      const deleted = await previous.delete();
      if (deleted !== TI_CLOUD_STORAGE_ERROR_OK) {
        await file.delete();
        return deleted;
      }
    }
    this.recentRecording = file;
    this.latestKind = 'recording';
    this.latestMediaTargetId = targetId;
    this.listener.onMediaChanged(this.latestKind);
    return TI_CLOUD_STORAGE_ERROR_OK;
  }

  private videoStateLabel(state: TiCloudStorageVideoOutputState): string {
    if (state === TiCloudStorageVideoOutputState.buffering) return 'buffering';
    if (state === TiCloudStorageVideoOutputState.rendering) return 'rendering';
    if (state === TiCloudStorageVideoOutputState.paused) return 'paused';
    if (state === TiCloudStorageVideoOutputState.completed) return 'completed';
    if (state === TiCloudStorageVideoOutputState.failed) return 'failed';
    return 'idle';
  }

  private audioStateLabel(state: TiCloudStorageAudioOutputState): string {
    if (state === TiCloudStorageAudioOutputState.buffering) return 'buffering';
    if (state === TiCloudStorageAudioOutputState.playing) return 'rendering';
    if (state === TiCloudStorageAudioOutputState.paused) return 'paused';
    if (state === TiCloudStorageAudioOutputState.completed) return 'completed';
    if (state === TiCloudStorageAudioOutputState.failed) return 'failed';
    return 'idle';
  }

  private outputsCompleted(expectsAudio: boolean): boolean {
    const audioCompleted = !expectsAudio || this.playbackAudioState === TiCloudStorageAudioOutputState.completed;
    return audioCompleted && this.playbackVideoStates.every((state: TiCloudStorageVideoOutputState): boolean =>
      state === TiCloudStorageVideoOutputState.completed);
  }

  private selectedVideoOutput(): TiCloudStorageVideoOutput | undefined {
    if (this.selectedVideoChannelId === null) return undefined;
    const index = this.videoChannelIds.indexOf(this.selectedVideoChannelId);
    return index < 0 || this.playbackVideoStates[index] === TiCloudStorageVideoOutputState.failed ?
      undefined : this.videoOutputs[index];
  }
}
