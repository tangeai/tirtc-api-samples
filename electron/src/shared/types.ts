import type {Rectangle} from 'electron';
import type {
  TiCloudStorageRecordingDay,
  TiCloudStorageRecordingRange,
  TiCloudStorageReplaySpeed,
  TiRtcErrorCode,
} from 'tirtc-electron';

export type ExampleFailure = Readonly<{
  code: TiRtcErrorCode | 'invalid-input';
  message: string;
}>;

export type ExampleSettings = Readonly<{
  videoDecoderPreference: 'auto' | 'software' | 'hardware';
  outputBufferPolicy: 'automatic' | 'noBuffer';
  consoleLogEnabled: boolean;
  localAudioCodec: 'g711a' | 'aac' | 'pcm' | 'opus' | 'amr';
  localAudioSampleRateHz: 8000 | 16000;
  localAudioStreamId: number;
  localAudioAecEnabled: boolean;
  localAudioAgcLevel: 'disabled' | 'low' | 'medium' | 'high';
  localAudioAnsLevel: 'disabled' | 'low' | 'medium' | 'high';
}>;

export type ExampleConfig = Readonly<{
  appId: string;
  endpoint: string;
  remoteId: string;
  tokenServerAddress?: string;
  audioStreamId?: number;
  videoStreamId?: number;
  settings?: ExampleSettings;
}>;

export type ExampleState = Readonly<{
  phase: 'configuration' | 'connecting' | 'playing' | 'failed';
  message: string;
  messageDirection: 'sent' | 'received' | null;
  messageCommandId: number | null;
  connectionState: string;
  audioState: string;
  audioMuted: boolean;
  localAudioRunning: boolean;
  recording: boolean;
  recentRecording: boolean;
  recentSnapshot: boolean;
  lastSavedFile: string | null;
  uploadingLogs: boolean;
  lastError: ExampleFailure | null;
  metrics: unknown | null;
}>;

export type ExampleApi = Readonly<{
  configure(config: ExampleConfig): Promise<void>;
  setVideoBounds(bounds: Rectangle): Promise<void>;
  sendMessage(message: string): Promise<void>;
  sendCommand(commandId: number, message: string): Promise<void>;
  startRecording(): Promise<void>;
  stopRecording(): Promise<void>;
  takeSnapshot(): Promise<void>;
  saveRecent(kind: 'recording' | 'snapshot'): Promise<void>;
  revealRecent(kind: 'recording' | 'snapshot'): Promise<void>;
  setAudioMuted(muted: boolean): Promise<void>;
  setLocalAudioRunning(running: boolean): Promise<void>;
  uploadLogs(): Promise<void>;
  leave(): Promise<void>;
  onState(listener: (state: ExampleState) => void): () => void;
  tiCloudStorageConfigure(config: TiCloudStorageExampleConfig): Promise<void>;
  tiCloudStorageQuery(startTimeMs: number, endTimeMs: number): Promise<void>;
  tiCloudStorageQueryDays(startDate: string, endDate: string, timeZoneId: string): Promise<ReadonlyArray<TiCloudStorageRecordingDay>>;
  tiCloudStoragePlayRange(index: number): Promise<void>;
  tiCloudStorageSetVideoBounds(bounds: Rectangle): Promise<void>;
  tiCloudStoragePause(): Promise<void>;
  tiCloudStorageResume(): Promise<void>;
  tiCloudStorageSeek(timeMs: number): Promise<void>;
  tiCloudStorageSetSpeed(speed: TiCloudStorageReplaySpeed): Promise<void>;
  tiCloudStorageSetMuted(muted: boolean): Promise<void>;
  tiCloudStorageStartRecording(): Promise<void>;
  tiCloudStorageStopRecording(): Promise<void>;
  tiCloudStorageTakeSnapshot(): Promise<void>;
  tiCloudStorageStartExport(index: number): Promise<void>;
  tiCloudStorageSaveRecent(kind: 'recording' | 'snapshot'): Promise<void>;
  tiCloudStorageUploadLogs(): Promise<void>;
  tiCloudStorageLeave(): Promise<void>;
  tiCloudStorageOnState(listener: (state: TiCloudStorageExampleState) => void): () => void;
}>;

export type TiCloudStorageExampleConfig = Readonly<{
  appId: string;
  endpoint: string;
  videoChannelId: number;
  audioChannelId: number;
}>;

export type TiCloudStorageExampleState = Readonly<{
  phase: 'configuration' | 'selection' | 'playing' | 'failed';
  querying: boolean;
  ranges: ReadonlyArray<TiCloudStorageRecordingRange>;
  selectedIndex: number | null;
  currentTimeMs: number | null;
  speed: TiCloudStorageReplaySpeed;
  replayState: string;
  recording: boolean;
  exportProgress: number | null;
  recentRecording: boolean;
  recentSnapshot: boolean;
  lastSavedFile: string | null;
  message: string;
  uploadingLogs: boolean;
  mediaBusy: boolean;
  lastError: ExampleFailure | null;
}>;
