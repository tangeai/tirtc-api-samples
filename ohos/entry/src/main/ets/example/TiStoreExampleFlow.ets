import {
  TiStore,
  TiStoreAudioOutput,
  TiStoreExportTask,
  TiStoreRecordingFile,
  TiStoreRecordingDaysResult,
  TiStoreRecordingRange,
  TiStoreRecordingRangesResult,
  TiStoreRecordingTask,
  TiStoreReplay,
  TiStoreReplaySpeed,
  TiStoreSnapshotFile,
  TiStoreVideoOutput,
  TiStoreVideoOutputState,
  TISTORE_ERROR_IN_USE,
  TISTORE_ERROR_INVALID_ARGUMENT,
  TISTORE_ERROR_OK,
} from 'tirtc/Index';

export interface TiStoreExampleFlowListener {
  onReplayState: (state: string) => void;
  onTimeChanged: (timeMs: number) => void;
  onCompleted: () => void;
  onError: (code: number) => void;
  onExportProgress: (progress: number) => void;
  onMediaChanged: (kind: string) => void;
}

export class TiStoreExampleFlow {
  readonly audioOutput: TiStoreAudioOutput = new TiStoreAudioOutput();
  readonly videoOutput: TiStoreVideoOutput = new TiStoreVideoOutput();
  private readonly store: TiStore;
  private readonly listener: TiStoreExampleFlowListener;
  private replay?: TiStoreReplay;
  private recordingTask?: TiStoreRecordingTask;
  private exportTask?: TiStoreExportTask;
  private exportCompletion?: Promise<number>;
  private mediaOperation?: Promise<number>;
  private recentRecording?: TiStoreRecordingFile;
  private recentSnapshot?: TiStoreSnapshotFile;
  private latestKind: string = '';
  private readonly recordingQueries: Array<Promise<TiStoreRecordingRangesResult>> = [];
  private readonly dayQueries: Array<Promise<TiStoreRecordingDaysResult>> = [];
  private disposed: boolean = false;

  constructor(token: string, listener: TiStoreExampleFlowListener) {
    this.store = new TiStore(token);
    this.listener = listener;
    this.store.onTokenExpired = (): void => this.listener.onError(6014);
    this.videoOutput.onStateChanged = (state: TiStoreVideoOutputState): void => {
      this.listener.onReplayState(this.videoStateLabel(state));
    };
    this.videoOutput.onError = (code: number): void => this.listener.onError(code);
    this.audioOutput.onError = (code: number): void => this.listener.onError(code);
  }

  public async query(startTimeMs: number, endTimeMs: number): Promise<TiStoreRecordingRangesResult> {
    if (this.disposed) return { code: TISTORE_ERROR_INVALID_ARGUMENT, recordings: [] };
    const operation = this.store.listRecordings(startTimeMs, endTimeMs);
    this.recordingQueries.push(operation);
    const result = await operation.finally((): void => {
      const index = this.recordingQueries.indexOf(operation);
      if (index >= 0) this.recordingQueries.splice(index, 1);
    });
    if (result.code !== TISTORE_ERROR_OK) {
      this.listener.onError(result.code);
    }
    return result;
  }

  public async queryDays(
    startDate: string,
    endDate: string,
    timeZoneId: string,
  ): Promise<TiStoreRecordingDaysResult> {
    if (this.disposed) return { code: TISTORE_ERROR_INVALID_ARGUMENT, days: [] };
    const operation = this.store.listRecordingDays(startDate, endDate, timeZoneId);
    this.dayQueries.push(operation);
    const result = await operation.finally((): void => {
      const index = this.dayQueries.indexOf(operation);
      if (index >= 0) this.dayQueries.splice(index, 1);
    });
    if (result.code !== TISTORE_ERROR_OK) this.listener.onError(result.code);
    return result;
  }

  public play(range: TiStoreRecordingRange, videoChannelId: number, audioChannelId: number): number {
    if (this.disposed || range.endTimeMs <= range.startTimeMs) {
      return TISTORE_ERROR_INVALID_ARGUMENT;
    }
    const released = this.releasePlayback();
    if (released !== TISTORE_ERROR_OK) {
      return released;
    }
    const replay = this.store.createReplay();
    replay.onTimeChanged = (timeMs: number): void => this.listener.onTimeChanged(timeMs);
    replay.onCompleted = (): void => this.listener.onCompleted();
    replay.onError = (code: number): void => this.listener.onError(code);
    this.replay = replay;
    let code = this.videoOutput.attach(replay, videoChannelId);
    if (code === TISTORE_ERROR_OK) {
      code = this.audioOutput.attach(replay, audioChannelId);
    }
    if (code === TISTORE_ERROR_OK) {
      code = replay.play(range.startTimeMs, range.endTimeMs);
    }
    if (code !== TISTORE_ERROR_OK) {
      this.releasePlayback();
      this.listener.onError(code);
    }
    return code;
  }

  public pause(): number {
    return this.replay?.pause() ?? TISTORE_ERROR_INVALID_ARGUMENT;
  }

  public resume(): number {
    return this.replay?.resume() ?? TISTORE_ERROR_INVALID_ARGUMENT;
  }

  public seek(timeMs: number): number {
    return this.replay?.seek(timeMs) ?? TISTORE_ERROR_INVALID_ARGUMENT;
  }

  public setSpeed(speed: TiStoreReplaySpeed): number {
    return this.replay?.setSpeed(speed) ?? TISTORE_ERROR_INVALID_ARGUMENT;
  }

  public setMuted(muted: boolean): number {
    return this.replay === undefined ? TISTORE_ERROR_INVALID_ARGUMENT : this.audioOutput.setVolume(muted ? 0 : 100);
  }

  public startRecording(videoChannelId: number, audioChannelId: number): number {
    if (this.replay === undefined || this.recordingTask !== undefined || this.mediaOperation !== undefined) {
      return TISTORE_ERROR_IN_USE;
    }
    const result = this.replay.startRecording({ videoChannelId, audioChannelId });
    if (!result.success || result.data === null) {
      return result.code ?? TISTORE_ERROR_INVALID_ARGUMENT;
    }
    this.recordingTask = result.data;
    return TISTORE_ERROR_OK;
  }

  public stopRecording(): Promise<number> {
    const task = this.recordingTask;
    if (task === undefined) {
      return Promise.resolve(TISTORE_ERROR_INVALID_ARGUMENT);
    }
    if (this.mediaOperation !== undefined) {
      return Promise.resolve(TISTORE_ERROR_IN_USE);
    }
    this.recordingTask = undefined;
    return this.runMediaOperation(async (): Promise<number> => {
      const result = await task.stop();
      if (!result.success || result.data === null) {
        return result.code ?? TISTORE_ERROR_INVALID_ARGUMENT;
      }
      return this.replaceRecording(result.data);
    });
  }

  public takeSnapshot(): Promise<number> {
    if (this.replay === undefined) {
      return Promise.resolve(TISTORE_ERROR_INVALID_ARGUMENT);
    }
    return this.runMediaOperation(async (): Promise<number> => {
      const result = await this.videoOutput.takeSnapshot();
      if (!result.success || result.data === null) {
        return result.code ?? TISTORE_ERROR_INVALID_ARGUMENT;
      }
      const previous = this.recentSnapshot;
      if (previous !== undefined) {
        const deleted = await previous.delete();
        if (deleted !== TISTORE_ERROR_OK) {
          await result.data.delete();
          return deleted;
        }
      }
      this.recentSnapshot = result.data;
      this.latestKind = 'snapshot';
      this.listener.onMediaChanged(this.latestKind);
      return TISTORE_ERROR_OK;
    });
  }

  public exportRecording(
    range: TiStoreRecordingRange,
    videoChannelId: number,
    audioChannelId: number,
  ): Promise<number> {
    if (this.exportTask !== undefined || this.exportCompletion !== undefined) {
      return Promise.resolve(TISTORE_ERROR_IN_USE);
    }
    const started = this.store.exportRecording({
      startTimeMs: range.startTimeMs,
      endTimeMs: range.endTimeMs,
      videoChannelId,
      audioChannelId,
    }, (progress: number): void => this.listener.onExportProgress(progress));
    if (!started.success || started.data === null) {
      return Promise.resolve(started.code ?? TISTORE_ERROR_INVALID_ARGUMENT);
    }
    this.exportTask = started.data;
    const completion = started.data.result.then(async (result): Promise<number> => {
      this.exportTask = undefined;
      if (!result.success || result.data === null) {
        return result.code ?? TISTORE_ERROR_INVALID_ARGUMENT;
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
      return TISTORE_ERROR_INVALID_ARGUMENT;
    }
    const code = await file.delete();
    if (code === TISTORE_ERROR_OK) {
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
      return TISTORE_ERROR_OK;
    }
    this.disposed = true;
    let first = TISTORE_ERROR_OK;
    const note = (code: number): void => {
      if (first === TISTORE_ERROR_OK && code !== TISTORE_ERROR_OK) {
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
      note(TISTORE_ERROR_INVALID_ARGUMENT);
    }
    if (this.exportTask !== undefined) {
      const stopped = await this.exportTask.stop();
      note(stopped.success ? TISTORE_ERROR_OK : stopped.code ?? TISTORE_ERROR_INVALID_ARGUMENT);
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
    note(this.store.dispose());
    return first;
  }

  private releasePlayback(): number {
    let first = TISTORE_ERROR_OK;
    const note = (code: number): void => {
      if (first === TISTORE_ERROR_OK && code !== TISTORE_ERROR_OK) {
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
      return Promise.resolve(TISTORE_ERROR_IN_USE);
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

  private async replaceRecording(file: TiStoreRecordingFile): Promise<number> {
    const previous = this.recentRecording;
    if (previous !== undefined) {
      const deleted = await previous.delete();
      if (deleted !== TISTORE_ERROR_OK) {
        await file.delete();
        return deleted;
      }
    }
    this.recentRecording = file;
    this.latestKind = 'recording';
    this.listener.onMediaChanged(this.latestKind);
    return TISTORE_ERROR_OK;
  }

  private videoStateLabel(state: TiStoreVideoOutputState): string {
    if (state === TiStoreVideoOutputState.buffering) return 'buffering';
    if (state === TiStoreVideoOutputState.rendering) return 'rendering';
    if (state === TiStoreVideoOutputState.paused) return 'paused';
    if (state === TiStoreVideoOutputState.completed) return 'completed';
    if (state === TiStoreVideoOutputState.failed) return 'failed';
    return 'idle';
  }
}
