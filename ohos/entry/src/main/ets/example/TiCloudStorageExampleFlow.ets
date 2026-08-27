import {
  TiCloudStorage,
  TiCloudStorageAudioOutput,
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
  TI_CLOUD_STORAGE_ERROR_IN_USE,
  TI_CLOUD_STORAGE_ERROR_INVALID_ARGUMENT,
  TI_CLOUD_STORAGE_ERROR_OK,
} from 'tirtc/Index';

export interface TiCloudStorageExampleFlowListener {
  onReplayState: (state: string) => void;
  onTimeChanged: (timeMs: number) => void;
  onCompleted: () => void;
  onError: (code: number) => void;
  onExportProgress: (progress: number) => void;
  onMediaChanged: (kind: string) => void;
}

export class TiCloudStorageExampleFlow {
  readonly audioOutput: TiCloudStorageAudioOutput = new TiCloudStorageAudioOutput();
  readonly videoOutput: TiCloudStorageVideoOutput = new TiCloudStorageVideoOutput();
  private readonly cloudStorage: TiCloudStorage;
  private readonly listener: TiCloudStorageExampleFlowListener;
  private replay?: TiCloudStorageReplay;
  private recordingTask?: TiCloudStorageRecordingTask;
  private exportTask?: TiCloudStorageExportTask;
  private exportCompletion?: Promise<number>;
  private mediaOperation?: Promise<number>;
  private recentRecording?: TiCloudStorageRecordingFile;
  private recentSnapshot?: TiCloudStorageSnapshotFile;
  private latestKind: string = '';
  private readonly recordingQueries: Array<Promise<TiCloudStorageRecordingRangesResult>> = [];
  private readonly dayQueries: Array<Promise<TiCloudStorageRecordingDaysResult>> = [];
  private disposed: boolean = false;

  constructor(token: string, listener: TiCloudStorageExampleFlowListener) {
    this.cloudStorage = new TiCloudStorage(token);
    this.listener = listener;
    this.videoOutput.onStateChanged = (state: TiCloudStorageVideoOutputState): void => {
      this.listener.onReplayState(this.videoStateLabel(state));
    };
    this.videoOutput.onError = (code: number): void => this.listener.onError(code);
    this.audioOutput.onError = (code: number): void => this.listener.onError(code);
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

  public play(range: TiCloudStorageRecordingRange, videoChannelId: number, audioChannelId: number): number {
    if (this.disposed || range.endTimeMs <= range.startTimeMs) {
      return TI_CLOUD_STORAGE_ERROR_INVALID_ARGUMENT;
    }
    const released = this.releasePlayback();
    if (released !== TI_CLOUD_STORAGE_ERROR_OK) {
      return released;
    }
    const replay = this.cloudStorage.createReplay();
    replay.onTimeChanged = (timeMs: number): void => this.listener.onTimeChanged(timeMs);
    replay.onCompleted = (): void => this.listener.onCompleted();
    replay.onError = (code: number): void => this.listener.onError(code);
    this.replay = replay;
    let code = this.videoOutput.attach(replay, videoChannelId);
    if (code === TI_CLOUD_STORAGE_ERROR_OK) {
      code = this.audioOutput.attach(replay, audioChannelId);
    }
    if (code === TI_CLOUD_STORAGE_ERROR_OK) {
      code = replay.play(range.startTimeMs, range.endTimeMs);
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

  public startRecording(videoChannelId: number, audioChannelId: number): number {
    if (this.replay === undefined || this.recordingTask !== undefined || this.mediaOperation !== undefined) {
      return TI_CLOUD_STORAGE_ERROR_IN_USE;
    }
    const result = this.replay.startRecording({ videoChannelId, audioChannelId });
    if (!result.success || result.data === null) {
      return result.code ?? TI_CLOUD_STORAGE_ERROR_INVALID_ARGUMENT;
    }
    this.recordingTask = result.data;
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
      return this.replaceRecording(result.data);
    });
  }

  public takeSnapshot(): Promise<number> {
    if (this.replay === undefined) {
      return Promise.resolve(TI_CLOUD_STORAGE_ERROR_INVALID_ARGUMENT);
    }
    return this.runMediaOperation(async (): Promise<number> => {
      const result = await this.videoOutput.takeSnapshot();
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
      this.listener.onMediaChanged(this.latestKind);
      return TI_CLOUD_STORAGE_ERROR_OK;
    });
  }

  public exportRecording(
    range: TiCloudStorageRecordingRange,
    videoChannelId: number,
    audioChannelId: number,
  ): Promise<number> {
    if (this.exportTask !== undefined || this.exportCompletion !== undefined) {
      return Promise.resolve(TI_CLOUD_STORAGE_ERROR_IN_USE);
    }
    const started = this.cloudStorage.exportRecording({
      startTimeMs: range.startTimeMs,
      endTimeMs: range.endTimeMs,
      videoChannelId,
      audioChannelId,
    }, (progress: number): void => this.listener.onExportProgress(progress));
    if (!started.success || started.data === null) {
      return Promise.resolve(started.code ?? TI_CLOUD_STORAGE_ERROR_INVALID_ARGUMENT);
    }
    this.exportTask = started.data;
    const completion = started.data.result.then(async (result): Promise<number> => {
      this.exportTask = undefined;
      if (!result.success || result.data === null) {
        return result.code ?? TI_CLOUD_STORAGE_ERROR_INVALID_ARGUMENT;
      }
      return this.replaceRecording(result.data);
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
      this.listener.onMediaChanged('');
    }
    return code;
  }

  public async dispose(): Promise<number> {
    if (this.disposed) {
      return TI_CLOUD_STORAGE_ERROR_OK;
    }
    this.disposed = true;
    let first = TI_CLOUD_STORAGE_ERROR_OK;
    const note = (code: number): void => {
      if (first === TI_CLOUD_STORAGE_ERROR_OK && code !== TI_CLOUD_STORAGE_ERROR_OK) {
        first = code;
      }
    };
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
    note(this.videoOutput.dispose());
    if (this.recentRecording !== undefined) {
      note(await this.recentRecording.delete());
    }
    if (this.recentSnapshot !== undefined) {
      note(await this.recentSnapshot.delete());
    }
    this.recentRecording = undefined;
    this.recentSnapshot = undefined;
    this.latestKind = '';
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
    note(this.videoOutput.detach());
    if (this.replay !== undefined) {
      note(this.replay.dispose());
    }
    this.replay = undefined;
    return first;
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

  private async replaceRecording(file: TiCloudStorageRecordingFile): Promise<number> {
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
}
