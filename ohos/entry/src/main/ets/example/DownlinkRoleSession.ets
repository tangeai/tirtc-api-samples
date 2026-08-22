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
  TiRtcOutputBufferStrategy,
  TiRtcVideoDecoderPreference,
  TiRtcVideoOutput,
  TiRtcVideoOutputState,
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
  audioStreamId: number;
  videoStreamId: number;
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
  onVideoStateChanged?: (state: TiRtcVideoOutputState) => void;
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
  private videoOutput: TiRtcVideoOutput = new TiRtcVideoOutput();
  private localAudioInput: TiRtcAudioInput = new TiRtcAudioInput();
  private callbacks: DownlinkRoleCallbacks = {};
  private activeAudioStreamId: number = 10;
  private activeVideoStreamId: number = 11;
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
  private latestRecordingFile?: TiRtcRecordingFile;
  private latestSnapshotFile?: TiRtcSnapshotFile;
  private readonly ownedMediaFiles: Set<TiRtcRecordingFile | TiRtcSnapshotFile> = new Set();

  videoOutputViewModel(): TiRtcVideoOutput {
    return this.videoOutput;
  }

  async start(options: DownlinkRoleStartOptions, callbacks: DownlinkRoleCallbacks): Promise<number> {
    if (this.running) {
      return 0;
    }
    this.callbacks = callbacks;
    this.callbacks.onConnectingChanged?.(true);
    this.callbacks.onStatusChanged?.('连接中', '正在初始化 TiRTC runtime');
    this.installCallbacks();
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

    this.activeAudioStreamId = options.audioStreamId;
    this.activeVideoStreamId = options.videoStreamId;
    this.selectedDecoderPreference = options.videoDecoderPreference;
    this.resetVideoRenderSize();

    code = this.audioOutput.configure({ bufferStrategy: options.outputBufferStrategy });
    if (code !== 0) {
      return await this.failStart(`音频配置失败 #${code}`, code, code);
    }
    code = this.videoOutput.setOptions({
      decoderPreference: options.videoDecoderPreference,
      bufferStrategy: options.outputBufferStrategy,
    });
    if (code !== 0) {
      return await this.failStart(`视频设置失败 #${code}`, code, code);
    }
    code = this.audioOutput.attach({ connection: this.conn, streamId: options.audioStreamId });
    if (code !== 0) {
      return await this.failStart(`音频输出失败 #${code}`, code, code);
    }
    code = this.videoOutput.attach({ connection: this.conn, streamId: options.videoStreamId });
    if (code !== 0) {
      return await this.failStart(`视频输出失败 #${code}`, code, code);
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
    const audioSubscribeCode = this.conn.subscribeAudio({ streamId: options.audioStreamId });
    const videoSubscribeCode = this.conn.subscribeVideo({ streamId: options.videoStreamId });
    hilog.info(LOG_DOMAIN, LOG_TAG,
      'TIRTC_downlink_subscribe_done audio_code=%{public}d video_code=%{public}d audio_stream_id=%{public}d video_stream_id=%{public}d',
      audioSubscribeCode, videoSubscribeCode, options.audioStreamId, options.videoStreamId);
    if (audioSubscribeCode !== 0 || videoSubscribeCode !== 0) {
      const subscribeCode = audioSubscribeCode !== 0 ? audioSubscribeCode : videoSubscribeCode;
      return await this.failStart(
        `订阅失败：音频 #${audioSubscribeCode}，视频 #${videoSubscribeCode}`,
        subscribeCode,
        subscribeCode,
      );
    }
    const hasRenderSize = await waitVideoRenderSize(this.videoOutput, VIDEO_SIZE_WAIT_TIMEOUT_MS,
      (width: number, height: number): void => {
        this.applyVideoRenderSize(width, height);
      },
      (): boolean => this.videoRenderWidth > 0 && this.videoRenderHeight > 0);
    if (!hasRenderSize) {
      return await this.failStart('视频尺寸未就绪', null, 6001);
    }

    this.running = true;
    this.audioOutputMuted = false;
    this.callbacks.onAudioOutputMutedChanged?.(false);
    this.callbacks.onConnectingChanged?.(false);
    this.callbacks.onPlayingChanged?.(true);
    this.refreshMetrics();
    this.startMetricsRefresh();
    hilog.info(LOG_DOMAIN, LOG_TAG,
      'TIRTC_downlink_start_done remote_id=%{public}s audio_stream_id=%{public}d video_stream_id=%{public}d',
      options.remoteId, options.audioStreamId, options.videoStreamId);
    return 0;
  }

  async stop(reason: string): Promise<void> {
    if (!this.running && this.conn.state === TiRtcConnState.idle) {
      this.stopMetricsRefresh();
      return;
    }
    this.stopMetricsRefresh();
    this.callbacks.onConnectingChanged?.(false);
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
    const videoDetachCode = this.videoOutput.detach();
    this.resetVideoRenderSize();
    const audioDetachCode = this.audioOutput.detach();
    const videoUnsubscribeCode = this.conn.unsubscribeVideo({ streamId: this.activeVideoStreamId });
    const audioUnsubscribeCode = this.conn.unsubscribeAudio({ streamId: this.activeAudioStreamId });
    const disconnectCode = this.conn.disconnect();
    const videoDisposeCode = this.videoOutput.dispose();
    const audioDisposeCode = this.audioOutput.dispose();
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
      return;
    }
    const shutdownCode = TiRtc.shutdown();
    if (shutdownCode !== 0) {
      this.fail(`停止失败 #${shutdownCode}`, shutdownCode);
      return;
    }
    this.resetObjects();
    this.callbacks.onStatusChanged?.(reason === 'manual_stop' ? '已停止' : '加载中', 'Downlink stopped.');
    hilog.info(LOG_DOMAIN, LOG_TAG,
      'TIRTC_downlink_stop_done reason=%{public}s video_detach=%{public}d audio_detach=%{public}d video_unsubscribe=%{public}d audio_unsubscribe=%{public}d disconnect=%{public}d local_audio_dispose=%{public}d video_dispose=%{public}d audio_dispose=%{public}d conn_dispose=%{public}d shutdown=%{public}d',
      reason, videoDetachCode, audioDetachCode, videoUnsubscribeCode, audioUnsubscribeCode, disconnectCode,
      localAudioDisposeCode, videoDisposeCode, audioDisposeCode, connDisposeCode, shutdownCode);
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
      }
      return result.success ? `本地保存完成 · ${result.data?.path ?? ''}` : `本地保存失败 #${result.code ?? 0}`;
    }
    const result = this.conn.startRecording({
      videoStreamId: this.activeVideoStreamId,
      audioStreamId: this.activeAudioStreamId,
    });
    if (!result.success || result.data === null) {
      return `开始本地保存失败 #${result.code ?? 0}`;
    }
    this.recordingTask = result.data;
    return '正在本地保存';
  }

  public isRecording(): boolean {
    return this.recordingTask !== undefined;
  }

  public async takeSnapshot(): Promise<string> {
    const result = await this.videoOutput.takeSnapshot();
    if (result.success && result.data !== null) {
      await this.deleteLatestMediaFiles();
      this.latestSnapshotFile = result.data;
      this.latestRecordingFile = undefined;
      this.ownedMediaFiles.add(result.data);
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
  }

  toggleAudioOutputVolume(): number {
    if (!this.running) {
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
    const streamCode = this.conn.sendStreamMessage({
      streamId: this.activeVideoStreamId,
      timestampMs: 0,
      data: asciiBytes(`${epochSeconds}`),
    });
    hilog.info(LOG_DOMAIN, LOG_TAG,
      'TIRTC_downlink_command_sent command_code=%{public}d stream_code=%{public}d command_id=%{public}d payload_bytes=%{public}d video_stream_id=%{public}d',
      commandCode, streamCode, commandId, payload.byteLength, this.activeVideoStreamId);
    return commandCode !== 0 ? commandCode : streamCode;
  }

  uploadLogs(): void {
    this.callbacks.onLogUploadStatusChanged?.('log_upload=上传中');
    const startedAtMs = Date.now();
    TiRtcLogging.upload()
      .then((result): void => {
        const elapsedMs = Math.max(0, Date.now() - startedAtMs);
        this.callbacks.onLogUploadStatusChanged?.(
          result.code === 0 ? 'log_upload=已上传' : `log_upload=失败 #${result.code}`);
        hilog.info(LOG_DOMAIN, LOG_TAG,
          'TIRTC_downlink_log_upload_done code=%{public}d elapsed_ms=%{public}d log_id_present=%{public}s',
          result.code, elapsedMs, result.logId === undefined || result.logId.length === 0 ? 'false' : 'true');
      })
      .catch((error: Error): void => {
        const elapsedMs = Math.max(0, Date.now() - startedAtMs);
        this.callbacks.onLogUploadStatusChanged?.('log_upload=异常');
        hilog.warn(LOG_DOMAIN, LOG_TAG,
          'TIRTC_downlink_log_upload_failed elapsed_ms=%{public}d message=%{public}s',
          elapsedMs, error.message);
      });
  }

  private installCallbacks(): void {
    this.conn.onStateChanged = (state: TiRtcConnState, errorCode: number) => {
      this.callbacks.onConnStateChanged?.(state);
      hilog.info(LOG_DOMAIN, LOG_TAG, 'TIRTC_connection_state state=%{public}d error=%{public}d',
        state, errorCode);
    };
    this.conn.onCommand = (command: number, payload: Uint8Array) => {
      const matched = command === SAMPLE_COMMAND_ID && bytesEqual(payload, asciiBytes(SAMPLE_COMMAND_PAYLOAD));
      const elapsedMs = this.commandSentAtMs > 0 ? Date.now() - this.commandSentAtMs : 0;
      this.callbacks.onCommandStatusChanged?.(
        matched ? `command=echo_received elapsed_ms=${elapsedMs}` : 'command=mismatch_received');
      hilog.info(LOG_DOMAIN, LOG_TAG,
        'TIRTC_command_echo_received command=%{public}d payload_bytes=%{public}d matched=%{public}s elapsed_ms=%{public}d',
        command, payload.byteLength, matched ? 'true' : 'false', elapsedMs);
    };
    this.conn.onStreamMessage = (streamId: number, timestampMs: number, payload: Uint8Array) => {
      const received = streamId === this.activeVideoStreamId && payload.byteLength > 0;
      const elapsedMs = this.connectedAtMs > 0 ? Date.now() - this.connectedAtMs : 0;
      this.callbacks.onStreamMessageStatusChanged?.(
        received ? `stream_message=收到 ${payload.byteLength}B` : 'stream_message=未匹配');
      hilog.info(LOG_DOMAIN, LOG_TAG,
        'TIRTC_stream_message_received stream_id=%{public}d timestamp_ms=%{public}d payload_bytes=%{public}d payload_text=%{public}s received=%{public}s timeout_ms=%{public}d elapsed_ms=%{public}d',
        streamId, timestampMs, payload.byteLength, asciiPayload(payload), received ? 'true' : 'false',
        STREAM_MESSAGE_TIMEOUT_MS, elapsedMs);
    };
    this.audioOutput.onStateChanged = (state: TiRtcAudioOutputState) => {
      this.callbacks.onAudioStateChanged?.(state);
      hilog.info(LOG_DOMAIN, LOG_TAG, 'TIRTC_audio_state state=%{public}d', state);
    };
    this.videoOutput.onStateChanged = (state: TiRtcVideoOutputState) => {
      this.callbacks.onVideoStateChanged?.(state);
      if (state === TiRtcVideoOutputState.rendering) {
        this.refreshMetrics();
        const debug = this.videoOutput.getDebugSnapshot();
        if (debug.code === 0 && debug.snapshot !== undefined) {
          hilog.info(LOG_DOMAIN, LOG_TAG,
            'TIRTC_video_debug_snapshot codec=%{public}d bitstream=%{public}d width=%{public}d height=%{public}d decoder_preference=%{public}d resolved_decoder_backend=%{public}d',
            debug.snapshot.codec,
            debug.snapshot.bitstreamFormat,
            debug.snapshot.width,
            debug.snapshot.height,
            debug.snapshot.decoderPreference,
            debug.snapshot.resolvedDecoderBackend);
        }
      }
      hilog.info(LOG_DOMAIN, LOG_TAG, 'TIRTC_video_state state=%{public}d', state);
    };
    this.videoOutput.onRenderSizeChanged = (size) => {
      this.applyVideoRenderSize(size.width, size.height);
    };
    this.videoOutput.onError = (code: number) => {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'TIRTC_video_error code=%{public}d', code);
    };
    this.localAudioInput.onStateChanged = (state: TiRtcInputState): void => {
      hilog.info(LOG_DOMAIN, LOG_TAG, 'TIRTC_downlink_local_audio_state state=%{public}d', state);
    };
    this.localAudioInput.onError = (code: number, message?: string): void => {
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
        codec: options.codec,
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
    const videoMetrics = this.videoOutput.getMetricsSnapshot();
    const audioDebug = this.audioOutput.getDebugSnapshot();
    const videoDebug = this.videoOutput.getDebugSnapshot();
    const conn = connMetrics.code === 0 ? connMetrics.snapshot : undefined;
    const audio = audioMetrics.code === 0 ? audioMetrics.snapshot : undefined;
    const video = videoMetrics.code === 0 ? videoMetrics.snapshot : undefined;
    const audioInfo = audioDebug.code === 0 ? audioDebug.snapshot : undefined;
    const videoInfo = videoDebug.code === 0 ? videoDebug.snapshot : undefined;
    const connectDurationMs = conn?.connectDurationMs ?? -1;
    const firstFrameDurationMs = video?.startup.timeToFirstOutputMs ?? -1;
    const lines: string[] = [
      `媒体参数：${this.formatVideoSize(videoInfo?.width, videoInfo?.height)} · ` +
        `${this.formatVideoCodec(videoInfo?.codec)} · ${this.formatAudioCodec(audioInfo?.codec)} · ` +
        `${this.formatVideoDecoder(videoInfo?.resolvedDecoderBackend)}`,
      `视频接收：码率 ${this.formatKbps(video?.videoInputBitrateKbps)} · 接收 ${this.formatRate(video?.videoInputFps, 'fps')}`,
      `音频接收：码率 ${this.formatKbps(audio?.audioInputBitrateKbps)} · PPS ${this.formatRate(audio?.audioInputPacketRate, '/s')}`,
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
    const videoDetachCode = this.videoOutput.detach();
    const audioDetachCode = this.audioOutput.detach();
    const videoUnsubscribeCode = this.conn.unsubscribeVideo({ streamId: this.activeVideoStreamId });
    const audioUnsubscribeCode = this.conn.unsubscribeAudio({ streamId: this.activeAudioStreamId });
    const disconnectCode = this.conn.disconnect();
    const localAudioDisposeCode = await this.localAudioInput.dispose();
    const videoDisposeCode = this.videoOutput.dispose();
    const audioDisposeCode = this.audioOutput.dispose();
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
    this.videoOutput = new TiRtcVideoOutput();
    this.localAudioInput = new TiRtcAudioInput();
    this.commandSentAtMs = 0;
    this.connectedAtMs = 0;
    this.activeAudioStreamId = 10;
    this.activeVideoStreamId = 11;
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
    this.callbacks.onVideoStateChanged?.(TiRtcVideoOutputState.idle);
    this.callbacks.onMetricsChanged?.('');
    this.callbacks.onCommandStatusChanged?.('');
    this.callbacks.onStreamMessageStatusChanged?.('');
    this.callbacks.onLogUploadStatusChanged?.('');
    this.callbacks.onLocalAudioStartedChanged?.(false);
    this.callbacks.onAudioOutputMutedChanged?.(false);
  }
}
