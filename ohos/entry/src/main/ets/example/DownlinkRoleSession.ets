import type { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  TiRtc,
  TiRtcAudioAecMode,
  TiRtcAudioAgcLevel,
  TiRtcAudioAnsLevel,
  TiRtcAudioChannelCount,
  TiRtcAudioCodec,
  TiRtcAudioInput,
  TiRtcAudioOutput,
  TiRtcAudioOutputState,
  TiRtcAudioSampleRate,
  TiRtcConn,
  TiRtcConnState,
  TiRtcInputState,
  TiRtcLogging,
  TiRtcRecordingTask,
  TiRtcRecordingFile,
  TiRtcSnapshotFile,
  TiRawDump,
  TiRtcOutputBufferStrategy,
  TiRtcVideoDecoderPreference,
  TiRtcVideoOutput,
  TiRtcVideoOutputState,
  TI_CLOUD_STORAGE_ERROR_IN_USE,
} from 'tirtc/Index';
import {
  asciiBytes,
  asciiPayload,
  bytesEqual,
  CONNECT_WAIT_TIMEOUT_MS,
  LOCAL_AUDIO_CONNECT_WAIT_TIMEOUT_MS,
  LOG_DOMAIN,
  LOG_TAG,
  SAMPLE_COMMAND_ID,
  SAMPLE_COMMAND_PAYLOAD,
  STREAM_MESSAGE_TIMEOUT_MS,
  VIDEO_SIZE_WAIT_TIMEOUT_MS,
} from './ExampleConfig';
import {
  waitConnected,
  waitVideoRenderSize,
} from './DownlinkAsync';

const MEDIA_CODEC_AUDIO_G711A = 1;
const RAW_DUMP_STOP_RETRY_DELAY_MS = 50;
const RAW_DUMP_STOP_RETRY_LIMIT = 20;
const MEDIA_CODEC_AUDIO_AAC = 2;
const MEDIA_CODEC_AUDIO_PCM = 3;
const MEDIA_CODEC_AUDIO_OPUS = 4;
const MEDIA_CODEC_AUDIO_AMR = 5;
const MEDIA_CODEC_VIDEO_H264 = 65;
const MEDIA_CODEC_VIDEO_H265 = 66;
const MEDIA_CODEC_VIDEO_MJPEG = 67;
const VIDEO_DECODER_BACKEND_SOFTWARE = 1;
const VIDEO_DECODER_BACKEND_HARDWARE = 2;
const METRICS_REFRESH_INTERVAL_MS = 1000;

export interface DownlinkRoleStartOptions {
  context: common.UIAbilityContext;
  endpoint: string;
  appId: string;
  remoteId: string;
  token: string;
  audioStreamId: number | null;
  videoStreamIds: Array<number>;
  videoDecoderPreference: TiRtcVideoDecoderPreference;
  outputBufferStrategy: TiRtcOutputBufferStrategy;
  consoleLogEnabled: boolean;
}

export interface DownlinkRoleCallbacks {
  onConnectingChanged?: (connecting: boolean) => void;
  onPlayingChanged?: (playing: boolean) => void;
  onStatusChanged?: (status: string, detail: string) => void;
  onLastErrorChanged?: (error: string) => void;
  onConnStateChanged?: (state: TiRtcConnState) => void;
  onAudioStateChanged?: (state: TiRtcAudioOutputState) => void;
  onVideoStateChanged?: (streamId: number, state: TiRtcVideoOutputState) => void;
  onMetricsChanged?: (value: string) => void;
  onRenderSizeChanged?: (width: number, height: number) => void;
  onCommandStatusChanged?: (value: string) => void;
  onStreamMessageStatusChanged?: (value: string) => void;
  onLogUploadStatusChanged?: (value: string) => void;
  onLocalAudioStartedChanged?: (started: boolean) => void;
  onAudioOutputMutedChanged?: (muted: boolean) => void;
}

export interface DownlinkLocalAudioOptions {
  streamId: number;
  codec: TiRtcAudioCodec;
  sampleRate: TiRtcAudioSampleRate;
  channels: TiRtcAudioChannelCount;
  aecMode: TiRtcAudioAecMode;
  agcLevel: TiRtcAudioAgcLevel;
  ansLevel: TiRtcAudioAnsLevel;
}

export class DownlinkRoleSession {
  private conn: TiRtcConn = new TiRtcConn();
  private audioOutput: TiRtcAudioOutput = new TiRtcAudioOutput();
  private videoOutputs: Array<TiRtcVideoOutput> = [];
  private localAudioInput: TiRtcAudioInput = new TiRtcAudioInput();
  private callbacks: DownlinkRoleCallbacks = {};
  private activeAudioStreamId: number | null = 10;
  private activeVideoStreamIds: Array<number> = [11];
  private selectedVideoStreamId: number | null = 11;
  private audioOutputAvailable: boolean = false;
  private audioOutputAttached: boolean = false;
  private audioOutputSubscribed: boolean = false;
  private readonly unavailableVideoStreamIds: Set<number> = new Set();
  private readonly attachedVideoStreamIds: Set<number> = new Set();
  private readonly subscribedVideoStreamIds: Set<number> = new Set();
  private sessionGeneration: number = 0;
  private localAudioStreamId: number = -1;
  private commandSentAtMs: number = 0;
  private connectedAtMs: number = 0;
  private videoRenderWidth: number = 0;
  private videoRenderHeight: number = 0;
  private selectedDecoderPreference: TiRtcVideoDecoderPreference = TiRtcVideoDecoderPreference.auto;
  private running: boolean = false;
  private localAudioAttached: boolean = false;
  private localAudioStarted: boolean = false;
  private audioOutputMuted: boolean = false;
  private audioOutputMuteStartedAtMs: number = 0;
  private audioOutputMuteStartDurationMs: number = -1;
  private metricsRefreshTimer: number = -1;
  private recordingTask?: TiRtcRecordingTask;
  private rawDump?: TiRawDump;
  private rawDumpUploadPending: boolean = false;
  private latestRecordingFile?: TiRtcRecordingFile;
  private latestSnapshotFile?: TiRtcSnapshotFile;
  private recordingTargetId: number | null = null;
  private latestMediaTargetId: number = -1;
  private readonly ownedMediaFiles: Set<TiRtcRecordingFile | TiRtcSnapshotFile> = new Set();

  videoOutputCount(): number {
    return this.videoOutputs.length;
  }

  videoOutputAt(index: number): TiRtcVideoOutput {
    return this.videoOutputs[index];
  }

  public selectVideoStream(streamId: number): void {
    if (this.activeVideoStreamIds.indexOf(streamId) >= 0) {
      this.selectedVideoStreamId = streamId;
      this.refreshMetrics();
    }
  }

  async start(options: DownlinkRoleStartOptions, callbacks: DownlinkRoleCallbacks): Promise<number> {
    if (this.running) {
      return 0;
    }
    this.callbacks = callbacks;
    const generation = ++this.sessionGeneration;
    this.activeAudioStreamId = options.audioStreamId;
    this.activeVideoStreamIds = options.videoStreamIds.slice();
    this.selectedVideoStreamId = this.activeVideoStreamIds.length > 0 ? this.activeVideoStreamIds[0] : null;
    this.videoOutputs = this.activeVideoStreamIds.map((): TiRtcVideoOutput => new TiRtcVideoOutput());
    this.audioOutputAvailable = options.audioStreamId !== null;
    this.audioOutputAttached = false;
    this.audioOutputSubscribed = false;
    this.unavailableVideoStreamIds.clear();
    this.attachedVideoStreamIds.clear();
    this.subscribedVideoStreamIds.clear();
    this.callbacks.onConnectingChanged?.(true);
    this.callbacks.onStatusChanged?.('连接中', '正在初始化 TiRTC runtime');
    this.installCallbacks(generation);
    hilog.info(LOG_DOMAIN, LOG_TAG,
      'TIRTC_downlink_start_requested remote_id=%{public}s token_length=%{public}d token_prefix=%{public}s',
      options.remoteId,
      options.token.length,
      options.token.startsWith('v1.') ? 'v1' : 'other');

    let code = await TiRtc.init({
      context: options.context,
      appId: options.appId,
      endpoint: options.endpoint,
      consoleLogEnabled: options.consoleLogEnabled,
    });
    if (code !== 0) {
      this.fail(`初始化失败 #${code}`, code);
      return code;
    }

    this.selectedDecoderPreference = options.videoDecoderPreference;
    this.resetVideoRenderSize();

    if (options.audioStreamId !== null) {
      code = this.audioOutput.configure({ bufferStrategy: options.outputBufferStrategy });
      if (code !== 0) {
        this.markAudioOutputUnavailable('configure', code);
      } else {
        code = this.audioOutput.attach({ connection: this.conn, streamId: options.audioStreamId });
        if (code === 0) {
          this.audioOutputAttached = true;
        } else {
          this.markAudioOutputUnavailable('attach', code);
        }
      }
    }
    for (let index = 0; index < this.videoOutputs.length; index += 1) {
      const output = this.videoOutputs[index];
      const streamId = this.activeVideoStreamIds[index];
      code = output.setOptions({
        decoderPreference: options.videoDecoderPreference,
        bufferStrategy: options.outputBufferStrategy,
      });
      if (code === 0) code = output.attach({ connection: this.conn, streamId });
      if (code !== 0) {
        this.unavailableVideoStreamIds.add(streamId);
        this.callbacks.onVideoStateChanged?.(streamId, TiRtcVideoOutputState.failed);
        hilog.warn(LOG_DOMAIN, LOG_TAG,
          'TIRTC_downlink_video_lane_attach_failed stream_id=%{public}d code=%{public}d', streamId, code);
      } else {
        this.attachedVideoStreamIds.add(streamId);
      }
    }
    code = this.conn.connect({
      remoteId: options.remoteId,
      token: options.token,
    });
    if (code !== 0) {
      return await this.failStart(`连接失败 #${code}`, code, code);
    }
    const connected = await waitConnected(this.conn, CONNECT_WAIT_TIMEOUT_MS);
    if (!connected) {
      return await this.failStart('连接超时', null, 6001);
    }
    this.connectedAtMs = Date.now();
    const audioSubscribeCode = options.audioStreamId === null || !this.audioOutputAvailable ? 0 :
      this.conn.subscribeAudio({ streamId: options.audioStreamId });
    if (audioSubscribeCode !== 0) {
      this.markAudioOutputUnavailable('subscribe', audioSubscribeCode);
    } else if (options.audioStreamId !== null && this.audioOutputAvailable) {
      this.audioOutputSubscribed = true;
    }
    for (const streamId of this.activeVideoStreamIds) {
      if (this.unavailableVideoStreamIds.has(streamId)) continue;
      const videoSubscribeCode = this.conn.subscribeVideo({ streamId });
      if (videoSubscribeCode !== 0) {
        this.unavailableVideoStreamIds.add(streamId);
        this.callbacks.onVideoStateChanged?.(streamId, TiRtcVideoOutputState.failed);
        hilog.warn(LOG_DOMAIN, LOG_TAG,
          'TIRTC_downlink_video_lane_subscribe_failed stream_id=%{public}d code=%{public}d',
          streamId, videoSubscribeCode);
      } else {
        this.subscribedVideoStreamIds.add(streamId);
      }
    }
    const selectedOutput = this.selectedVideoOutput();
    if (selectedOutput !== undefined) {
      const hasRenderSize = await waitVideoRenderSize(selectedOutput, VIDEO_SIZE_WAIT_TIMEOUT_MS,
        (width: number, height: number): void => {
          this.applyVideoRenderSize(width, height);
        },
        (): boolean => this.videoRenderWidth > 0 && this.videoRenderHeight > 0);
      if (!hasRenderSize) {
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'TIRTC_downlink_selected_video_size_not_ready');
      }
    }

    this.running = true;
    this.audioOutputMuted = false;
    this.callbacks.onAudioOutputMutedChanged?.(false);
    this.callbacks.onConnectingChanged?.(false);
    this.callbacks.onPlayingChanged?.(true);
    this.refreshMetrics();
    this.startMetricsRefresh();
    hilog.info(LOG_DOMAIN, LOG_TAG,
      'TIRTC_downlink_start_done remote_id=%{public}s audio_enabled=%{public}s video_count=%{public}d',
      options.remoteId, options.audioStreamId === null ? 'false' : 'true', options.videoStreamIds.length);
    return 0;
  }

  async stop(reason: string): Promise<boolean> {
    if (!this.running && this.conn.state === TiRtcConnState.idle) {
      this.stopMetricsRefresh();
      return true;
    }
    this.sessionGeneration += 1;
    this.callbacks.onConnectingChanged?.(false);
    if (this.rawDump !== undefined) {
      const rawDump = this.rawDump;
      let result = await rawDump.stop();
      for (let attempt = 0;
        !result.success && result.code === TI_CLOUD_STORAGE_ERROR_IN_USE && attempt < RAW_DUMP_STOP_RETRY_LIMIT;
        attempt += 1) {
        await new Promise<void>((resolve): void => {
          setTimeout(resolve, RAW_DUMP_STOP_RETRY_DELAY_MS);
        });
        result = await rawDump.stop();
      }
      if (!result.success && result.code === TI_CLOUD_STORAGE_ERROR_IN_USE) return false;
      if (result.success) this.rawDumpUploadPending = true;
      this.rawDump = undefined;
    }
    this.stopMetricsRefresh();
    this.callbacks.onPlayingChanged?.(false);
    if (this.recordingTask !== undefined) {
      const recordingResult = await this.recordingTask.stop();
      if (recordingResult.success && recordingResult.data !== null) {
        this.ownedMediaFiles.add(recordingResult.data);
      }
      this.recordingTask = undefined;
    }
    await this.deleteLatestMediaFiles();
    const localAudioDisposeCode = await this.releaseLocalAudioInput();
    let videoDetachCode = 0;
    for (let index = 0; index < this.videoOutputs.length; index += 1) {
      if (!this.attachedVideoStreamIds.has(this.activeVideoStreamIds[index])) continue;
      const laneCode = this.videoOutputs[index].detach();
      if (videoDetachCode === 0 && laneCode !== 0) videoDetachCode = laneCode;
    }
    this.resetVideoRenderSize();
    const audioDetachCode = !this.audioOutputAttached ? 0 : this.audioOutput.detach();
    let videoUnsubscribeCode = 0;
    for (const streamId of this.subscribedVideoStreamIds) {
      const laneCode = this.conn.unsubscribeVideo({ streamId });
      if (videoUnsubscribeCode === 0 && laneCode !== 0) videoUnsubscribeCode = laneCode;
    }
    const audioUnsubscribeCode = !this.audioOutputSubscribed || this.activeAudioStreamId === null ? 0 :
      this.conn.unsubscribeAudio({ streamId: this.activeAudioStreamId });
    const disconnectCode = this.conn.disconnect();
    let videoDisposeCode = 0;
    for (const output of this.videoOutputs) {
      const laneCode = output.dispose();
      if (videoDisposeCode === 0 && laneCode !== 0) videoDisposeCode = laneCode;
    }
    const audioDisposeCode = this.activeAudioStreamId === null ? 0 : this.audioOutput.dispose();
    const connDisposeCode = this.conn.dispose();
    if (localAudioDisposeCode !== 0 || videoDisposeCode !== 0 || audioDisposeCode !== 0 ||
      connDisposeCode !== 0) {
      const disposeCode = localAudioDisposeCode !== 0 ? localAudioDisposeCode :
        (videoDisposeCode !== 0 ? videoDisposeCode :
          (audioDisposeCode !== 0 ? audioDisposeCode : connDisposeCode));
      this.fail(`停止失败 #${disposeCode}`, disposeCode);
      hilog.error(LOG_DOMAIN, LOG_TAG,
        'TIRTC_downlink_dispose_failed reason=%{public}s local_audio=%{public}d video=%{public}d audio=%{public}d conn=%{public}d',
        reason, localAudioDisposeCode, videoDisposeCode, audioDisposeCode, connDisposeCode);
      return true;
    }
    const shutdownCode = TiRtc.shutdown();
    if (shutdownCode !== 0) {
      this.fail(`停止失败 #${shutdownCode}`, shutdownCode);
      return true;
    }
    this.resetObjects();
    this.callbacks.onStatusChanged?.(reason === 'manual_stop' ? '已停止' : '加载中', 'Downlink stopped.');
    hilog.info(LOG_DOMAIN, LOG_TAG,
      'TIRTC_downlink_stop_done reason=%{public}s video_detach=%{public}d audio_detach=%{public}d video_unsubscribe=%{public}d audio_unsubscribe=%{public}d disconnect=%{public}d local_audio_dispose=%{public}d video_dispose=%{public}d audio_dispose=%{public}d conn_dispose=%{public}d shutdown=%{public}d',
      reason, videoDetachCode, audioDetachCode, videoUnsubscribeCode, audioUnsubscribeCode, disconnectCode,
      localAudioDisposeCode, videoDisposeCode, audioDisposeCode, connDisposeCode, shutdownCode);
    return true;
  }

  public async toggleRecording(): Promise<string> {
    if (this.recordingTask !== undefined) {
      const result = await this.recordingTask.stop();
      this.recordingTask = undefined;
      if (result.success && result.data !== null) {
        await this.deleteLatestMediaFiles();
        this.latestRecordingFile = result.data;
        this.latestSnapshotFile = undefined;
        this.ownedMediaFiles.add(result.data);
        this.latestMediaTargetId = this.recordingTargetId ?? -1;
      }
      this.recordingTargetId = null;
      return result.success ? `本地保存完成 · ${result.data?.path ?? ''}` : `本地保存失败 #${result.code ?? 0}`;
    }
    const streamId = this.selectedVideoStreamId;
    if (streamId === null) return '未选择视频流';
    const result = this.activeAudioStreamId === null || !this.audioOutputAvailable ?
      this.conn.startRecording({ videoStreamId: streamId }) :
      this.conn.startRecording({ videoStreamId: streamId, audioStreamId: this.activeAudioStreamId });
    if (!result.success || result.data === null) {
      return `开始本地保存失败 #${result.code ?? 0}`;
    }
    this.recordingTask = result.data;
    this.recordingTargetId = streamId;
    return `正在本地保存 · Stream ${streamId}`;
  }

  public isRecording(): boolean {
    return this.recordingTask !== undefined;
  }

  public async toggleRawDump(uplinkAudioStreamId: number): Promise<string> {
    if (this.rawDumpUploadPending) {
      const uploaded = await this.uploadLogs();
      return uploaded ? '诊断数据上传成功' : '诊断数据上传失败 · 点击重试上传';
    }
    if (this.rawDump !== undefined) {
      const result = await this.rawDump.stop();
      if (!result.success || result.data === null) return `诊断抓取停止失败 #${result.code ?? 0}`;
      this.rawDump = undefined;
      this.rawDumpUploadPending = true;
      const uploaded = await this.uploadLogs();
      return uploaded ? `诊断数据上传成功 · ${result.data.captureId}` :
        `诊断数据上传失败 · ${result.data.captureId} · 点击重试上传`;
    }
    const result = await this.conn.startRawDump({
      audioStreamIds: this.activeAudioStreamId === null ? [] : [this.activeAudioStreamId],
      videoStreamIds: this.activeVideoStreamIds,
      uplinkAudioStreamIds: [uplinkAudioStreamId],
    });
    if (!result.success || result.data === null) return `诊断抓取失败 #${result.code ?? 0}`;
    this.rawDump = result.data;
    return '正在抓取诊断数据 · 再次点击结束并上传日志';
  }

  public isRawDumpCapturing(): boolean {
    return this.rawDump !== undefined;
  }

  public isRawDumpUploadPending(): boolean { return this.rawDumpUploadPending; }

  public async takeSnapshot(): Promise<string> {
    const output = this.selectedVideoOutput();
    if (output === undefined) return '';
    const targetId = this.selectedVideoStreamId ?? -1;
    const result = await output.takeSnapshot();
    if (result.success && result.data !== null) {
      await this.deleteLatestMediaFiles();
      this.latestSnapshotFile = result.data;
      this.latestRecordingFile = undefined;
      this.ownedMediaFiles.add(result.data);
      this.latestMediaTargetId = targetId;
      return result.data.path;
    }
    return '';
  }

  public latestMediaPath(): string {
    return this.latestSnapshotFile?.path ?? this.latestRecordingFile?.path ?? '';
  }

  public latestMediaKind(): string {
    if (this.latestSnapshotFile !== undefined) return 'snapshot';
    if (this.latestRecordingFile !== undefined) return 'recording';
    return '';
  }

  public latestMediaTarget(): number {
    return this.latestMediaTargetId;
  }

  private async deleteLatestMediaFiles(): Promise<void> {
    for (const file of this.ownedMediaFiles) {
      if (await file.delete() === 0) this.ownedMediaFiles.delete(file);
    }
    if (this.latestRecordingFile !== undefined && !this.ownedMediaFiles.has(this.latestRecordingFile)) {
      this.latestRecordingFile = undefined;
    }
    if (this.latestSnapshotFile !== undefined && !this.ownedMediaFiles.has(this.latestSnapshotFile)) {
      this.latestSnapshotFile = undefined;
    }
    if (this.latestRecordingFile === undefined && this.latestSnapshotFile === undefined) this.latestMediaTargetId = -1;
  }

  toggleAudioOutputVolume(): number {
    if (!this.running || this.activeAudioStreamId === null || !this.audioOutputAvailable) {
      return 6026;
    }
    const targetVolume = this.audioOutputMuted ? 100 : 0;
    const before = this.audioOutput.getMetricsSnapshot().snapshot;
    const code = this.audioOutput.setVolume(targetVolume);
    if (code !== 0) {
      hilog.warn(LOG_DOMAIN, LOG_TAG,
        'TIRTC_audio_output_volume_toggle target=%{public}d code=%{public}d',
        targetVolume, code);
      return code;
    }
    this.audioOutputMuted = targetVolume === 0;
    this.callbacks.onAudioOutputMutedChanged?.(this.audioOutputMuted);
    const after = this.audioOutput.getMetricsSnapshot().snapshot;
    hilog.info(LOG_DOMAIN, LOG_TAG,
      'TIRTC_audio_output_volume_toggle target=%{public}d code=%{public}d state=%{public}d system_volume_write=false output_duration_ms_before=%{public}d output_duration_ms_after=%{public}d render_callback_rate=%{public}f',
      targetVolume,
      code,
      this.audioOutput.state,
      before?.stutter.outputDurationMs ?? -1,
      after?.stutter.outputDurationMs ?? -1,
      after?.audioRenderCallbackRate ?? -1);
    if (targetVolume === 0) {
      this.audioOutputMuteStartedAtMs = Date.now();
      this.audioOutputMuteStartDurationMs = after?.stutter.outputDurationMs ?? -1;
      return code;
    }
    const elapsedMs = Math.max(0, Date.now() - this.audioOutputMuteStartedAtMs);
    const durationProgressMs =
      (before?.stutter.outputDurationMs ?? -1) - this.audioOutputMuteStartDurationMs;
    const passed = elapsedMs >= 4800 &&
      durationProgressMs >= 4500 &&
      (before?.audioRenderCallbackRate ?? 0) > 0;
    hilog.info(LOG_DOMAIN, LOG_TAG,
      'TIRTC_audio_output_volume_cycle_completed status=%{public}s mute_hold_ms=%{public}d duration_progress_ms=%{public}d render_callback_rate=%{public}f system_volume_write=false',
      passed ? 'passed' : 'failed',
      elapsedMs,
      durationProgressMs,
      before?.audioRenderCallbackRate ?? -1);
    this.audioOutputMuteStartedAtMs = 0;
    this.audioOutputMuteStartDurationMs = -1;
    return passed ? code : 6001;
  }

  async toggleLocalAudio(options: DownlinkLocalAudioOptions): Promise<number> {
    if (!this.running) {
      return 6028;
    }
    if (this.localAudioStarted) {
      return await this.stopLocalAudio(false);
    }
    return await this.startLocalAudio(options);
  }

  sendControlMessage(commandId: number, payload: Uint8Array): number {
    if (!this.running) {
      return 6028;
    }
    this.callbacks.onCommandStatusChanged?.('command=发送中');
    this.callbacks.onStreamMessageStatusChanged?.('stream_message=发送中');
    this.commandSentAtMs = Date.now();
    const commandCode = this.conn.sendCommand({ commandId, data: payload });
    const epochSeconds = Math.floor(Date.now() / 1000);
    const targetStreamId = this.activeVideoStreamIds.length > 0 ?
      this.activeVideoStreamIds[0] : this.activeAudioStreamId;
    if (targetStreamId === null) return commandCode;
    const streamCode = this.conn.sendStreamMessage({
      streamId: targetStreamId,
      timestampMs: 0,
      data: asciiBytes(`${epochSeconds}`),
    });
    hilog.info(LOG_DOMAIN, LOG_TAG,
      'TIRTC_downlink_command_sent command_code=%{public}d stream_code=%{public}d command_id=%{public}d payload_bytes=%{public}d video_stream_id=%{public}d',
      commandCode, streamCode, commandId, payload.byteLength, targetStreamId);
    return commandCode !== 0 ? commandCode : streamCode;
  }

  async uploadLogs(): Promise<boolean> {
    this.callbacks.onLogUploadStatusChanged?.('log_upload=上传中');
    const startedAtMs = Date.now();
    try {
      const result = await TiRtcLogging.upload();
      const elapsedMs = Math.max(0, Date.now() - startedAtMs);
      this.callbacks.onLogUploadStatusChanged?.(
        result.code === 0 ? 'log_upload=已上传' : `log_upload=失败 #${result.code}`);
      hilog.info(LOG_DOMAIN, LOG_TAG,
        'TIRTC_downlink_log_upload_done code=%{public}d elapsed_ms=%{public}d log_id_present=%{public}s',
        result.code, elapsedMs, result.logId === undefined || result.logId.length === 0 ? 'false' : 'true');
      if (result.code === 0) this.rawDumpUploadPending = false;
      return result.code === 0;
    } catch (error) {
      const elapsedMs = Math.max(0, Date.now() - startedAtMs);
      this.callbacks.onLogUploadStatusChanged?.('log_upload=异常');
      hilog.warn(LOG_DOMAIN, LOG_TAG,
        'TIRTC_downlink_log_upload_failed elapsed_ms=%{public}d message=%{public}s',
        elapsedMs, `${error}`);
      return false;
    }
  }

  private installCallbacks(generation: number): void {
    this.conn.onStateChanged = (state: TiRtcConnState, errorCode: number) => {
      if (generation !== this.sessionGeneration) return;
      this.callbacks.onConnStateChanged?.(state);
      hilog.info(LOG_DOMAIN, LOG_TAG, 'TIRTC_connection_state state=%{public}d error=%{public}d',
        state, errorCode);
    };
    this.conn.onCommand = (command: number, payload: Uint8Array) => {
      if (generation !== this.sessionGeneration) return;
      const matched = command === SAMPLE_COMMAND_ID && bytesEqual(payload, asciiBytes(SAMPLE_COMMAND_PAYLOAD));
      const elapsedMs = this.commandSentAtMs > 0 ? Date.now() - this.commandSentAtMs : 0;
      this.callbacks.onCommandStatusChanged?.(
        matched ? `command=echo_received elapsed_ms=${elapsedMs}` : 'command=mismatch_received');
      hilog.info(LOG_DOMAIN, LOG_TAG,
        'TIRTC_command_echo_received command=%{public}d payload_bytes=%{public}d matched=%{public}s elapsed_ms=%{public}d',
        command, payload.byteLength, matched ? 'true' : 'false', elapsedMs);
    };
    this.conn.onStreamMessage = (streamId: number, timestampMs: number, payload: Uint8Array) => {
      if (generation !== this.sessionGeneration) return;
      const received = (this.activeVideoStreamIds.indexOf(streamId) >= 0 || streamId === this.activeAudioStreamId) &&
        payload.byteLength > 0;
      const elapsedMs = this.connectedAtMs > 0 ? Date.now() - this.connectedAtMs : 0;
      this.callbacks.onStreamMessageStatusChanged?.(
        received ? `stream_message=收到 ${payload.byteLength}B` : 'stream_message=未匹配');
      hilog.info(LOG_DOMAIN, LOG_TAG,
        'TIRTC_stream_message_received stream_id=%{public}d timestamp_ms=%{public}d payload_bytes=%{public}d payload_text=%{public}s received=%{public}s timeout_ms=%{public}d elapsed_ms=%{public}d',
        streamId, timestampMs, payload.byteLength, asciiPayload(payload), received ? 'true' : 'false',
        STREAM_MESSAGE_TIMEOUT_MS, elapsedMs);
    };
    if (this.activeAudioStreamId !== null) {
      this.audioOutput.onStateChanged = (state: TiRtcAudioOutputState) => {
        if (generation !== this.sessionGeneration) return;
        if (state === TiRtcAudioOutputState.failed) this.markAudioOutputUnavailable('runtime-state', -1);
        this.callbacks.onAudioStateChanged?.(state);
        hilog.info(LOG_DOMAIN, LOG_TAG, 'TIRTC_audio_state state=%{public}d', state);
      };
      this.audioOutput.onError = (code: number) => {
        if (generation !== this.sessionGeneration) return;
        this.markAudioOutputUnavailable('runtime', code);
      };
    }
    for (let index = 0; index < this.videoOutputs.length; index += 1) {
      const output = this.videoOutputs[index];
      const streamId = this.activeVideoStreamIds[index];
      output.onStateChanged = (state: TiRtcVideoOutputState) => {
        if (generation !== this.sessionGeneration || this.videoOutputs[index] !== output) return;
        if (state === TiRtcVideoOutputState.failed) this.unavailableVideoStreamIds.add(streamId);
        this.callbacks.onVideoStateChanged?.(streamId, state);
        if (state === TiRtcVideoOutputState.rendering && streamId === this.selectedVideoStreamId) {
          this.refreshMetrics();
          const debug = output.getDebugSnapshot();
          if (debug.code === 0 && debug.snapshot !== undefined) {
            hilog.info(LOG_DOMAIN, LOG_TAG,
              'TIRTC_video_debug_snapshot stream_id=%{public}d codec=%{public}d bitstream=%{public}d width=%{public}d height=%{public}d decoder_preference=%{public}d resolved_decoder_backend=%{public}d',
              streamId, debug.snapshot.codec, debug.snapshot.bitstreamFormat,
              debug.snapshot.width, debug.snapshot.height, debug.snapshot.decoderPreference,
              debug.snapshot.resolvedDecoderBackend);
          }
        }
        hilog.info(LOG_DOMAIN, LOG_TAG, 'TIRTC_video_state stream_id=%{public}d state=%{public}d', streamId, state);
      };
      output.onRenderSizeChanged = (size) => {
        if (generation !== this.sessionGeneration || this.videoOutputs[index] !== output) return;
        if (streamId === this.selectedVideoStreamId) this.applyVideoRenderSize(size.width, size.height);
      };
      output.onError = (code: number) => {
        if (generation !== this.sessionGeneration || this.videoOutputs[index] !== output) return;
        this.unavailableVideoStreamIds.add(streamId);
        this.callbacks.onVideoStateChanged?.(streamId, TiRtcVideoOutputState.failed);
        hilog.error(LOG_DOMAIN, LOG_TAG, 'TIRTC_video_error stream_id=%{public}d code=%{public}d', streamId, code);
      };
    }
    this.localAudioInput.onStateChanged = (state: TiRtcInputState): void => {
      if (generation !== this.sessionGeneration) return;
      hilog.info(LOG_DOMAIN, LOG_TAG, 'TIRTC_downlink_local_audio_state state=%{public}d', state);
    };
    this.localAudioInput.onError = (code: number, message?: string): void => {
      if (generation !== this.sessionGeneration) return;
      hilog.warn(LOG_DOMAIN, LOG_TAG,
        'TIRTC_downlink_local_audio_error code=%{public}d message=%{public}s',
        code, message ?? '');
    };
  }

  private async startLocalAudio(options: DownlinkLocalAudioOptions): Promise<number> {
    const connected = await waitConnected(this.conn, LOCAL_AUDIO_CONNECT_WAIT_TIMEOUT_MS);
    if (!connected) {
      return 6028;
    }
    if (this.localAudioAttached && this.localAudioStreamId !== options.streamId) {
      const detachCode = await this.localAudioInput.detach({ connection: this.conn });
      if (detachCode !== 0) {
        return detachCode;
      }
      this.localAudioAttached = false;
      this.localAudioStreamId = -1;
    }
    if (!this.localAudioAttached) {
      const optionsCode = await this.localAudioInput.setOptions({
        media: options.codec === TiRtcAudioCodec.pcm ? 1 :
          options.codec === TiRtcAudioCodec.g711a ? 2 :
          options.codec === TiRtcAudioCodec.aac ? 3 :
          options.codec === TiRtcAudioCodec.opus ? 4 : 5,
        sampleRate: options.sampleRate,
        channels: options.channels,
        aecMode: options.aecMode,
        agcLevel: options.agcLevel,
        ansLevel: options.ansLevel,
      });
      if (optionsCode !== 0) {
        return optionsCode;
      }
      const attachCode = await this.localAudioInput.attach({ connection: this.conn, streamId: options.streamId });
      if (attachCode !== 0) {
        return attachCode;
      }
      this.localAudioAttached = true;
      this.localAudioStreamId = options.streamId;
      hilog.info(LOG_DOMAIN, LOG_TAG,
        'TIRTC_downlink_local_audio_input_attached stream_id=%{public}d codec=%{public}d sample_rate=%{public}d aec=%{public}d agc=%{public}d ans=%{public}d',
        options.streamId, options.codec, options.sampleRate, options.aecMode, options.agcLevel, options.ansLevel);
    }
    const startCode = await this.localAudioInput.start();
    if (startCode !== 0) {
      return startCode;
    }
    this.localAudioStarted = true;
    this.callbacks.onLocalAudioStartedChanged?.(true);
    hilog.info(LOG_DOMAIN, LOG_TAG,
      'TIRTC_downlink_local_audio_input_started stream_id=%{public}d',
      options.streamId);
    return 0;
  }

  private async stopLocalAudio(releaseBinding: boolean): Promise<number> {
    const stopCode = await this.localAudioInput.stop();
    if (stopCode !== 0) {
      return stopCode;
    }
    this.localAudioStarted = false;
    this.callbacks.onLocalAudioStartedChanged?.(false);
    hilog.info(LOG_DOMAIN, LOG_TAG,
      'TIRTC_downlink_local_audio_input_stopped stream_id=%{public}d release_binding=%{public}s',
      this.localAudioStreamId, releaseBinding ? 'true' : 'false');
    if (releaseBinding && this.localAudioAttached) {
      const detachCode = await this.localAudioInput.detach({ connection: this.conn });
      if (detachCode !== 0) {
        return detachCode;
      }
      this.localAudioAttached = false;
      this.localAudioStreamId = -1;
    }
    return 0;
  }

  private async releaseLocalAudioInput(): Promise<number> {
    if (this.localAudioStarted) {
      const stopCode = await this.stopLocalAudio(true);
      if (stopCode !== 0) {
        return stopCode;
      }
    } else if (this.localAudioAttached) {
      const detachCode = await this.localAudioInput.detach({ connection: this.conn });
      if (detachCode !== 0) {
        return detachCode;
      }
      this.localAudioAttached = false;
      this.localAudioStreamId = -1;
      this.callbacks.onLocalAudioStartedChanged?.(false);
    }
    return this.localAudioInput.dispose();
  }

  private refreshMetrics(): void {
    const connMetrics = this.conn.getMetricsSnapshot();
    const audioMetrics = this.audioOutput.getMetricsSnapshot();
    const selectedVideo = this.selectedVideoOutput();
    const videoMetrics = selectedVideo?.getMetricsSnapshot();
    const audioDebug = this.audioOutput.getDebugSnapshot();
    const videoDebug = selectedVideo?.getDebugSnapshot();
    const conn = connMetrics.code === 0 ? connMetrics.snapshot : undefined;
    const audio = this.audioOutputAvailable && audioMetrics.code === 0 ? audioMetrics.snapshot : undefined;
    const video = videoMetrics !== undefined && videoMetrics.code === 0 ? videoMetrics.snapshot : undefined;
    const audioInfo = this.audioOutputAvailable && audioDebug.code === 0 ? audioDebug.snapshot : undefined;
    const videoInfo = videoDebug !== undefined && videoDebug.code === 0 ? videoDebug.snapshot : undefined;
    const connectDurationMs = conn?.connectDurationMs ?? -1;
    const firstFrameDurationMs = video?.startup.timeToFirstOutputMs ?? -1;
    const lines: string[] = [
      `媒体参数：${this.formatVideoSize(videoInfo?.width, videoInfo?.height)} · ` +
        `${this.formatVideoCodec(videoInfo?.codec)} · ${this.formatAudioCodec(audioInfo?.codec)} · ` +
        `${this.formatVideoDecoder(videoInfo?.resolvedDecoderBackend)}`,
      `视频接收：码率 ${this.formatKbps(video?.videoInputBitrateKbps)} · 接收 ${this.formatRate(video?.videoInputFps, 'fps')}`,
      `音频接收：码率 ${this.formatKbps(audio?.audioInputBitrateKbps)} · ` +
        `PPS ${this.formatRate(audio?.audioInputPacketRate, '/s')} · ` +
        `输出 ${this.formatDuration(audio?.stutter.outputDurationMs)}`,
      `估算延迟：视频 ${this.formatDuration(video?.estimatedOutputLatencyMs)} · ` +
        `音频 ${this.formatDuration(audio?.estimatedOutputLatencyMs)}`,
      `启动耗时：${this.formatStartup(connectDurationMs, firstFrameDurationMs)}`,
      `卡顿统计：视频 ${this.formatCount(video?.stutter.stutterCount)} / ` +
        `最长 ${this.formatDuration(video?.stutter.stutterPeakMs)} · 音频 ` +
        `${this.formatCount(audio?.stutter.stutterCount)} / ` +
        `最长 ${this.formatDuration(audio?.stutter.stutterPeakMs)}`,
    ];
    this.callbacks.onMetricsChanged?.(lines.join('\n'));
  }

  private startMetricsRefresh(): void {
    this.stopMetricsRefresh();
    this.metricsRefreshTimer = setInterval((): void => {
      if (this.running) {
        this.refreshMetrics();
      }
    }, METRICS_REFRESH_INTERVAL_MS);
  }

  private stopMetricsRefresh(): void {
    if (this.metricsRefreshTimer < 0) {
      return;
    }
    clearInterval(this.metricsRefreshTimer);
    this.metricsRefreshTimer = -1;
  }

  private formatVideoSize(width: number | undefined, height: number | undefined): string {
    if (width === undefined || height === undefined || width <= 0 || height <= 0) {
      return '--';
    }
    return `${width}x${height}`;
  }

  private formatVideoCodec(codec: number | undefined): string {
    if (codec === MEDIA_CODEC_VIDEO_H264) {
      return 'H264';
    }
    if (codec === MEDIA_CODEC_VIDEO_H265) {
      return 'H265';
    }
    if (codec === MEDIA_CODEC_VIDEO_MJPEG) {
      return 'MJPEG';
    }
    return '--';
  }

  private formatAudioCodec(codec: number | undefined): string {
    if (codec === MEDIA_CODEC_AUDIO_G711A) {
      return 'G711A';
    }
    if (codec === MEDIA_CODEC_AUDIO_AAC) {
      return 'AAC';
    }
    if (codec === MEDIA_CODEC_AUDIO_PCM) {
      return 'PCM';
    }
    if (codec === MEDIA_CODEC_AUDIO_OPUS) {
      return 'OPUS';
    }
    if (codec === MEDIA_CODEC_AUDIO_AMR) {
      return 'AMR';
    }
    return '--';
  }

  private formatVideoDecoder(resolvedBackend: number | undefined): string {
    const suffix = this.selectedDecoderPreference === TiRtcVideoDecoderPreference.auto ? '（自动）' : '';
    if (resolvedBackend === VIDEO_DECODER_BACKEND_HARDWARE) {
      return `硬解${suffix}`;
    }
    if (resolvedBackend === VIDEO_DECODER_BACKEND_SOFTWARE) {
      return `软解${suffix}`;
    }
    return '未确定';
  }

  private formatDuration(durationMs: number | undefined): string {
    if (durationMs === undefined || durationMs < 0) {
      return '--';
    }
    return `${Math.round(durationMs)} ms`;
  }

  private formatRatio(ratio: number | undefined): string {
    if (ratio === undefined || !Number.isFinite(ratio)) {
      return '--';
    }
    return `${(ratio * 100).toFixed(1)}%`;
  }

  private formatKbps(value: number | undefined): string {
    if (value === undefined || !Number.isFinite(value) || value <= 0) {
      return '--';
    }
    return `${value >= 100 ? value.toFixed(0) : value.toFixed(1)} kbps`;
  }

  private formatRate(value: number | undefined, suffix: string): string {
    if (value === undefined || !Number.isFinite(value) || value <= 0) {
      return '--';
    }
    return `${value.toFixed(1)} ${suffix}`;
  }

  private formatCount(count: number | undefined): string {
    if (count === undefined || count < 0) {
      return '--';
    }
    return `${Math.round(count)} 次`;
  }

  private formatStartup(connectDurationMs: number, firstFrameDurationMs: number): string {
    const connect = this.formatDuration(connectDurationMs);
    if (firstFrameDurationMs < 0) {
      return `连接 ${connect} · 首帧总耗时 --`;
    }
    return `连接 ${connect} · 首帧总耗时 ${this.formatDuration(firstFrameDurationMs)}`;
  }

  private fail(message: string, code: number | null): void {
    this.stopMetricsRefresh();
    this.callbacks.onConnectingChanged?.(false);
    this.callbacks.onPlayingChanged?.(false);
    this.callbacks.onStatusChanged?.(message, '请检查 token、remote_id、source 或设备日志。');
    this.callbacks.onLastErrorChanged?.(message);
    hilog.error(LOG_DOMAIN, LOG_TAG, 'TIRTC_downlink_failed message=%{public}s code=%{public}d',
      message, code ?? 0);
  }

  private async failStart(message: string, code: number | null, resultCode: number): Promise<number> {
    await this.releaseFailedStart();
    this.fail(message, code);
    return resultCode;
  }

  private async releaseFailedStart(): Promise<void> {
    this.sessionGeneration += 1;
    let videoDetachCode = 0;
    for (let index = 0; index < this.videoOutputs.length; index += 1) {
      if (!this.attachedVideoStreamIds.has(this.activeVideoStreamIds[index])) continue;
      const laneCode = this.videoOutputs[index].detach();
      if (videoDetachCode === 0 && laneCode !== 0) videoDetachCode = laneCode;
    }
    const audioDetachCode = !this.audioOutputAttached ? 0 : this.audioOutput.detach();
    let videoUnsubscribeCode = 0;
    for (const streamId of this.subscribedVideoStreamIds) {
      const laneCode = this.conn.unsubscribeVideo({ streamId });
      if (videoUnsubscribeCode === 0 && laneCode !== 0) videoUnsubscribeCode = laneCode;
    }
    const audioUnsubscribeCode = !this.audioOutputSubscribed || this.activeAudioStreamId === null ? 0 :
      this.conn.unsubscribeAudio({ streamId: this.activeAudioStreamId });
    const disconnectCode = this.conn.disconnect();
    const localAudioDisposeCode = await this.localAudioInput.dispose();
    let videoDisposeCode = 0;
    for (const output of this.videoOutputs) {
      const laneCode = output.dispose();
      if (videoDisposeCode === 0 && laneCode !== 0) videoDisposeCode = laneCode;
    }
    const audioDisposeCode = this.activeAudioStreamId === null ? 0 : this.audioOutput.dispose();
    const connDisposeCode = this.conn.dispose();
    const shutdownCode = TiRtc.shutdown();
    const released = localAudioDisposeCode === 0 && videoDisposeCode === 0 &&
      audioDisposeCode === 0 && connDisposeCode === 0 && shutdownCode === 0;
    if (released) {
      this.resetObjects();
      hilog.info(LOG_DOMAIN, LOG_TAG,
        'TIRTC_downlink_start_cleanup_done video_detach=%{public}d audio_detach=%{public}d video_unsubscribe=%{public}d audio_unsubscribe=%{public}d disconnect=%{public}d',
        videoDetachCode, audioDetachCode, videoUnsubscribeCode, audioUnsubscribeCode, disconnectCode);
      return;
    }
    hilog.error(LOG_DOMAIN, LOG_TAG,
      'TIRTC_downlink_start_cleanup_failed video_detach=%{public}d audio_detach=%{public}d video_unsubscribe=%{public}d audio_unsubscribe=%{public}d disconnect=%{public}d local_audio=%{public}d video=%{public}d audio=%{public}d conn=%{public}d shutdown=%{public}d',
      videoDetachCode, audioDetachCode, videoUnsubscribeCode, audioUnsubscribeCode, disconnectCode,
      localAudioDisposeCode, videoDisposeCode, audioDisposeCode, connDisposeCode, shutdownCode);
  }

  private applyVideoRenderSize(width: number, height: number): void {
    if (width <= 0 || height <= 0) {
      return;
    }
    if (this.videoRenderWidth === width && this.videoRenderHeight === height) {
      return;
    }
    this.videoRenderWidth = width;
    this.videoRenderHeight = height;
    hilog.info(LOG_DOMAIN, LOG_TAG, 'TIRTC_video_render_size width=%{public}d height=%{public}d',
      width, height);
    this.callbacks.onRenderSizeChanged?.(width, height);
  }

  private resetVideoRenderSize(): void {
    if (this.videoRenderWidth === 0 && this.videoRenderHeight === 0) {
      return;
    }
    this.videoRenderWidth = 0;
    this.videoRenderHeight = 0;
    this.callbacks.onRenderSizeChanged?.(0, 0);
  }

  private resetObjects(): void {
    this.stopMetricsRefresh();
    this.conn = new TiRtcConn();
    this.audioOutput = new TiRtcAudioOutput();
    this.videoOutputs = [];
    this.localAudioInput = new TiRtcAudioInput();
    this.commandSentAtMs = 0;
    this.connectedAtMs = 0;
    this.activeAudioStreamId = null;
    this.activeVideoStreamIds = [];
    this.selectedVideoStreamId = null;
    this.audioOutputAvailable = false;
    this.audioOutputAttached = false;
    this.audioOutputSubscribed = false;
    this.unavailableVideoStreamIds.clear();
    this.attachedVideoStreamIds.clear();
    this.subscribedVideoStreamIds.clear();
    this.running = false;
    this.localAudioAttached = false;
    this.localAudioStarted = false;
    this.localAudioStreamId = -1;
    this.audioOutputMuted = false;
    this.audioOutputMuteStartedAtMs = 0;
    this.audioOutputMuteStartDurationMs = -1;
    this.resetVideoRenderSize();
    this.callbacks.onConnStateChanged?.(TiRtcConnState.idle);
    this.callbacks.onAudioStateChanged?.(TiRtcAudioOutputState.idle);
    for (const streamId of this.activeVideoStreamIds) {
      this.callbacks.onVideoStateChanged?.(streamId, TiRtcVideoOutputState.idle);
    }
    this.callbacks.onMetricsChanged?.('');
    this.callbacks.onCommandStatusChanged?.('');
    this.callbacks.onStreamMessageStatusChanged?.('');
    this.callbacks.onLogUploadStatusChanged?.('');
    this.callbacks.onLocalAudioStartedChanged?.(false);
    this.callbacks.onAudioOutputMutedChanged?.(false);
  }

  private selectedVideoOutput(): TiRtcVideoOutput | undefined {
    if (this.selectedVideoStreamId === null ||
      this.unavailableVideoStreamIds.has(this.selectedVideoStreamId)) return undefined;
    const index = this.activeVideoStreamIds.indexOf(this.selectedVideoStreamId);
    return index < 0 ? undefined : this.videoOutputs[index];
  }

  private markAudioOutputUnavailable(phase: string, code: number): void {
    this.audioOutputAvailable = false;
    this.callbacks.onAudioStateChanged?.(TiRtcAudioOutputState.failed);
    hilog.warn(LOG_DOMAIN, LOG_TAG,
      'TIRTC_downlink_audio_output_failed phase=%{public}s code=%{public}d', phase, code);
  }
}
