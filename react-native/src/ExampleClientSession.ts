import {
  TiRtc,
  TiRtcAudioInput,
  TiRtcAudioOutput,
  TiRtcAudioOutputState,
  TiRtcConn,
  TiRtcConnState,
  TiRtcInputState,
  TiRtcLogging,
  type TiRtcLoggingUploadResult,
  type TiRtcSize,
  TiRtcVideoOutput,
  TiRtcVideoOutputState,
  type TiRtcRecordingTask,
  type TiRtcRecordingFile,
  type TiRtcSnapshotFile,
  type TiRawDump,
} from 'tirtc-react-native';
import {
  clonePayload,
  commandInvalidStateCode,
  formatCommandId,
  isDemoEchoCommand,
  trimCommandEvents,
  type CommandPanelEvent,
} from './ExampleCommandPanelModel';
import {formatDuration, formatFps, formatRate, formatSize, videoDebugSize} from './ExampleDiagnostics';
import {
  createDownlinkMetricsOverlayModel,
  type DownlinkMetricsOverlayModel,
} from './ExampleDownlinkMetricsOverlayModel';
import {DemoStreamMessageOverlayController, DemoStreamMessageSender} from './ExampleStreamMessage';
import {
  localAudioInputOptionsFromConfig,
  galleryFileName,
  outputBufferStrategyFromConfig,
  prepareGalleryWritePermission,
  validSize,
  videoDecoderPreferenceFromConfig,
} from './ExampleSessionShared';
import {parseLocalAudioStreamId, type ExampleConfig, type MediaSelection} from './ExampleTypes';

export class ClientSession {
  conn: TiRtcConn | null = null;
  audioOutput: TiRtcAudioOutput | null = null;
  readonly videoOutputs = new Map<number, TiRtcVideoOutput>();
  readonly renderSizes = new Map<number, TiRtcSize>();
  readonly videoStates = new Map<number, TiRtcVideoOutputState>();
  readonly videoErrors = new Map<number, number>();
  selectedVideoStreamId: number | null = null;
  talkback: TiRtcAudioInput | null = null;
  audioOutputMuted = false;
  onTalkbackStateChanged: ((running: boolean) => void) | null = null;
  recordingTask: TiRtcRecordingTask | null = null;
  rawDump: TiRawDump | null = null;
  private rawDumpUploadPending = false;
  private recordingTargetId: number | null = null;
  private latestMediaFile: TiRtcRecordingFile | TiRtcSnapshotFile | null = null;
  private latestMediaTargetId: number | null = null;
  private readonly ownedMediaFiles = new Set<TiRtcRecordingFile | TiRtcSnapshotFile>();
  private connState: TiRtcConnState = TiRtcConnState.idle;
  private audioState: TiRtcAudioOutputState = TiRtcAudioOutputState.idle;
  private talkbackState: TiRtcInputState = TiRtcInputState.idle;
  private firstVideoRendered = false;
  private renderPoll: ReturnType<typeof setInterval> | null = null;
  private downlinkStreams: MediaSelection | null = null;
  private localAudioStreamId = 14;
  private downlinkSubscribed = false;
  private readonly streamMessageOverlay = new DemoStreamMessageOverlayController();
  private pendingLocalEchoReplies = 0;
  private generation = 0;
  commandEvents: CommandPanelEvent[] = [];

  constructor(private readonly setStatus: (status: string) => void) {}

  get videoOutput(): TiRtcVideoOutput | null {
    return this.selectedVideoStreamId === null ? null : this.videoOutputs.get(this.selectedVideoStreamId) ?? null;
  }

  get renderSize(): TiRtcSize | null {
    return this.selectedVideoStreamId === null ? null : this.renderSizes.get(this.selectedVideoStreamId) ?? null;
  }

  get hasLatestMedia(): boolean {
    return this.latestMediaFile !== null;
  }

  async start(config: ExampleConfig, streams: MediaSelection) {
    await this.stop();
    const generation = ++this.generation;
    this.stopRenderPoll();
    this.renderSizes.clear();
    this.videoStates.clear();
    this.selectedVideoStreamId = null;
    this.audioOutputMuted = false;
    this.localAudioStreamId = parseLocalAudioStreamId(config);
    TiRtcLogging.i(
      'TiRtcRnExample',
      `client_start_begin app_id_present=${config.appId.length > 0} endpoint_present=${config.endpoint.length > 0} remote_id_present=${config.remoteId.length > 0}`,
    );
    const initCode = await TiRtc.init({
      appId: config.appId,
      endpoint: config.endpoint,
      consoleLogEnabled: config.consoleLogEnabled,
    });
    TiRtcLogging.i('TiRtcRnExample', `client_init_done code=${initCode}`);
    if (initCode !== 0) {
      this.setStatus(`播放准备失败 · ${TiRtc.formatError(initCode)}`);
      return;
    }

    const connection = new TiRtcConn();
    this.conn = connection;
    this.downlinkStreams = {...streams};
    connection.onStateChanged = (state, code) => {
      if (generation !== this.generation || this.conn !== connection) return;
      this.connState = state;
      if (state === TiRtcConnState.connected) {
        this.subscribeDownlinkIfReady();
        this.setStatus('client connected');
        return;
      }
      if (state === TiRtcConnState.disconnected && code !== 0) {
        this.setStatus(`连接失败 · ${TiRtc.formatError(code)}`);
        return;
      }
      this.setStatus(`conn ${state} code=${code}`);
    };
    connection.onCommand = (commandId, data) => {
      if (generation !== this.generation || this.conn !== connection) return;
      this.handleReceivedCommand(commandId, data);
    };
    connection.onStreamMessage = (streamId, _timestampMs, data) => {
      if (generation !== this.generation || this.conn !== connection) return;
      this.handleStreamMessage(streams.videos.includes(streamId) ? streamId : (streams.videos[0] ?? streams.audio ?? 0), streamId, data);
    };

    const outputBufferStrategy = outputBufferStrategyFromConfig(config.outputBufferPolicy);
    if (streams.audio !== null) {
      const audioOutput = new TiRtcAudioOutput();
      this.audioOutput = audioOutput;
      audioOutput.onStateChanged = (state) => {
        if (generation !== this.generation || this.audioOutput !== audioOutput) return;
        this.audioState = state;
        if (state === TiRtcAudioOutputState.playing) this.setStatus('audio playing');
        if (state === TiRtcAudioOutputState.failed) {
          this.retireAudioOutput(audioOutput);
          this.setStatus('音频播放失败');
        }
      };
      audioOutput.onError = (code) => {
        if (generation !== this.generation || this.audioOutput !== audioOutput) return;
        this.audioState = TiRtcAudioOutputState.failed;
        this.retireAudioOutput(audioOutput);
        this.setStatus(`音频播放失败 · ${TiRtc.formatError(code)}`);
      };
      const audioOptionsCode = audioOutput.configure({bufferStrategy: outputBufferStrategy});
      if (audioOptionsCode !== 0) {
        this.audioState = TiRtcAudioOutputState.failed;
        this.audioOutput = null;
        audioOutput.dispose();
        this.setStatus(`音频播放配置失败 · ${TiRtc.formatError(audioOptionsCode)}`);
      } else {
        const audioAttachCode = audioOutput.attach(connection, streams.audio);
        if (audioAttachCode !== 0) {
          this.audioState = TiRtcAudioOutputState.failed;
          this.audioOutput = null;
          audioOutput.dispose();
          this.setStatus(`音频播放启动失败 · ${TiRtc.formatError(audioAttachCode)}`);
        }
      }
    }
    for (const streamId of streams.videos) {
      const output = new TiRtcVideoOutput();
      this.videoOutputs.set(streamId, output);
      this.videoStates.set(streamId, TiRtcVideoOutputState.idle);
      output.onStateChanged = (state) => {
        if (generation !== this.generation || this.videoOutputs.get(streamId) !== output) return;
        this.videoStates.set(streamId, state);
        if (state === TiRtcVideoOutputState.rendering) {
          this.videoErrors.delete(streamId);
          this.markVideoRendering(streamId, output.renderSize);
        }
      };
      output.onError = (code) => {
        if (generation !== this.generation || this.videoOutputs.get(streamId) !== output) return;
        this.videoStates.set(streamId, TiRtcVideoOutputState.failed);
        this.videoErrors.set(streamId, code);
        this.setStatus(`视频 ${streamId} 播放失败 · ${TiRtc.formatError(code)}`);
      };
      output.onRenderSizeChanged = (size) => {
        if (generation !== this.generation || this.videoOutputs.get(streamId) !== output) return;
        this.markVideoRendering(streamId, size);
      };
      const optionsCode = output.setOptions({
        decoderPreference: videoDecoderPreferenceFromConfig(config.videoDecoderPreference),
        bufferStrategy: outputBufferStrategy,
      });
      if (optionsCode !== 0) {
        this.videoStates.set(streamId, TiRtcVideoOutputState.failed);
        this.videoErrors.set(streamId, optionsCode);
        this.setStatus(`视频 ${streamId} 配置失败 · ${TiRtc.formatError(optionsCode)}`);
        continue;
      }
      const attachCode = output.attach(connection, streamId);
      if (attachCode !== 0) {
        this.videoStates.set(streamId, TiRtcVideoOutputState.failed);
        this.videoErrors.set(streamId, attachCode);
        this.setStatus(`视频 ${streamId} 启动失败 · ${TiRtc.formatError(attachCode)}`);
      }
    }
    this.selectedVideoStreamId = streams.videos[0] ?? null;
    const connectCode = connection.connect(config.remoteId, config.token);
    TiRtcLogging.i('TiRtcRnExample', `client_connect_done code=${connectCode}`);
    if (connectCode !== 0) {
      await this.failStartup(`连接失败 · ${TiRtc.formatError(connectCode)}`);
      return;
    }
    this.subscribeDownlinkIfReady();
    const hasUsableVideo = streams.videos.some(
      (streamId) => this.videoStates.get(streamId) !== TiRtcVideoOutputState.failed,
    );
    this.setStatus(
      !this.downlinkSubscribed
        ? '等待连接'
        : hasUsableVideo
          ? '等待首帧'
          : this.audioOutput !== null
            ? '等待音频'
            : 'client connected',
    );
    this.startRenderPoll();
  }

  sendCommand(commandId: number, payload: Uint8Array): number {
    const code = this.conn?.sendCommand(commandId, payload) ?? commandInvalidStateCode;
    if (code === 0 && isDemoEchoCommand(commandId, payload)) {
      this.pendingLocalEchoReplies += 1;
    }
    this.appendCommandEvent({
      direction: 'sent',
      commandId,
      payload: clonePayload(payload),
      resultCode: code,
      createdAt: Date.now(),
    });
    this.setStatus(`command sent ${formatCommandId(commandId)} bytes=${payload.length} code=${code}`);
    return code;
  }

  sendStreamMessage(streamId: number): number {
    const sender = new DemoStreamMessageSender();
    const code = sender.send(this.conn, streamId);
    this.setStatus(`stream message sent ${streamId} code=${code}`);
    return code;
  }

  requestKeyFrame(streamId: number) {
    this.conn?.requestKeyFrame(streamId);
  }

  setAudioOutputMuted(muted: boolean): number {
    const volumePercent = muted ? 0 : 100;
    const code = this.audioOutput?.setVolume(volumePercent) ?? commandInvalidStateCode;
    TiRtcLogging.i(
      'TiRtcRnExample',
      `client_audio_output_volume_done code=${code} volume_percent=${volumePercent}`,
    );
    if (code === 0) {
      this.audioOutputMuted = muted;
      this.setStatus(muted ? '播放已静音' : '播放声音已恢复');
    } else {
      this.setStatus(`音量设置失败 · ${TiRtc.formatError(code)}`);
    }
    return code;
  }

  async startTalkback(config: ExampleConfig) {
    if (!this.conn) {
      return;
    }
    await this.stopTalkback();
    const streamId = this.localAudioStreamId;
    this.talkback = new TiRtcAudioInput();
    this.talkback.onStateChanged = (state) => {
      this.setTalkbackState(state);
    };
    this.talkback.onError = (code) => {
      this.setTalkbackState(TiRtcInputState.failed);
      this.setStatus(`麦克风异常 · ${TiRtc.formatError(code)}`);
    };
    let code = await this.talkback.setOptions(localAudioInputOptionsFromConfig(config));
    if (code !== 0) {
      await this.talkback.dispose();
      this.talkback = null;
      this.setTalkbackState(TiRtcInputState.idle);
      this.setStatus(`麦克风配置失败 · ${TiRtc.formatError(code)}`);
      return;
    }
    code = await this.talkback.attach(this.conn, streamId);
    if (code !== 0) {
      await this.talkback.dispose();
      this.talkback = null;
      this.setTalkbackState(TiRtcInputState.idle);
      this.setStatus(`麦克风绑定失败 · ${TiRtc.formatError(code)}`);
      return;
    }
    code = await this.talkback.start();
    if (code !== 0) {
      await this.talkback.dispose();
      this.talkback = null;
      this.setTalkbackState(TiRtcInputState.idle);
      this.setStatus(`麦克风启动失败 · ${TiRtc.formatError(code)}`);
      return;
    }
    this.setTalkbackState(TiRtcInputState.running);
    this.setStatus(this.firstVideoRendered ? 'video rendering' : 'client connected');
  }

  async stopTalkback() {
    const talkback = this.talkback;
    if (!talkback) {
      this.setTalkbackState(TiRtcInputState.idle);
      return;
    }
    this.talkback = null;
    await talkback.stop();
    await talkback.dispose();
    this.setTalkbackState(TiRtcInputState.stopped);
  }

  async uploadLogs(): Promise<TiRtcLoggingUploadResult> {
    TiRtcLogging.i('TiRtcRnExample', 'client_log_upload_start');
    const upload = await TiRtcLogging.upload();
    TiRtcLogging.i('TiRtcRnExample', `client_log_upload_done code=${upload.code} logId=${upload.logId ?? '-'}`);
    return upload;
  }

  async toggleRawDump(): Promise<{capturing: boolean; status: string; upload: boolean}> {
    if (this.rawDumpUploadPending) {
      return {capturing: false, status: '诊断数据已保留 · 正在重试上传', upload: true};
    }
    if (this.rawDump !== null) {
      const result = await this.rawDump.stop();
      if (!result.success || result.data === null) {
        return {capturing: true, status: `诊断抓取停止失败 · #${result.code ?? 0}`, upload: false};
      }
      this.rawDump = null;
      this.rawDumpUploadPending = true;
      return {capturing: false, status: `诊断抓取完成 · ${result.data.captureId}`, upload: true};
    }
    if (this.conn === null || this.downlinkStreams === null) {
      return {capturing: false, status: '诊断抓取失败 · 播放未就绪', upload: false};
    }
    const result = await this.conn.startRawDump({
      audioStreamIds: this.downlinkStreams.audio === null ? [] : [this.downlinkStreams.audio],
      videoStreamIds: this.downlinkStreams.videos,
      uplinkAudioStreamIds: [this.localAudioStreamId],
    });
    if (!result.success || result.data === null) {
      return {capturing: false, status: `诊断抓取失败 · #${result.code ?? 0}`, upload: false};
    }
    this.rawDump = result.data;
    return {capturing: true, status: '正在抓取诊断数据 · 再次点击结束并上传日志', upload: false};
  }

  finishRawDumpUpload(success: boolean): void {
    if (success) this.rawDumpUploadPending = false;
  }

  isRawDumpUploadPending(): boolean { return this.rawDumpUploadPending; }

  diagnostics(): string[] {
    const connMetrics = this.conn?.getMetricsSnapshot().snapshot ?? null;
    const audioMetrics = this.audioOutput?.getMetricsSnapshot().snapshot ?? null;
    const videoMetrics = this.videoOutput?.getMetricsSnapshot().snapshot ?? null;
    const audioDebug = this.audioOutput?.getDebugSnapshot().snapshot ?? null;
    const videoDebug = this.videoOutput?.getDebugSnapshot().snapshot ?? null;
    const output = this.videoOutput;
    const renderSize = validSize(this.renderSize) ?? (output ? this.debugRenderSize(output) : null);
    return [
      `conn ${this.connState} · ready ${connMetrics?.isReady ? 'yes' : '-'}`,
      `metrics conn ${connMetrics ? 'yes' : '-'} · ${formatDuration(connMetrics?.connectDurationMs)}`,
      `audio ${this.audioState} · ${formatRate(audioMetrics?.audioInputBitrateKbps)}`,
      `video ${this.selectedVideoStreamId === null ? '未配置' : this.videoStates.get(this.selectedVideoStreamId) ?? TiRtcVideoOutputState.idle} · ${formatFps(videoMetrics?.videoRenderFps)}`,
      `render ${formatSize(renderSize)} · first ${this.firstVideoRendered ? 'yes' : 'no'}`,
      `debug a:${audioDebug?.codec ?? '-'} v:${videoDebug?.codec ?? '-'} ${formatSize(videoDebugSize(videoDebug))}`,
    ];
  }

  readMetricsOverlay(
    requestedDecoderPreference: ExampleConfig['videoDecoderPreference'],
  ): DownlinkMetricsOverlayModel | null {
    const connection = this.conn;
    const videoOutput = this.videoOutput;
    const audioOutput = this.audioOutput;
    if (connection === null || videoOutput === null || audioOutput === null) {
      return null;
    }
    const connResult = connection.getMetricsSnapshot();
    const videoResult = videoOutput.getMetricsSnapshot();
    const audioResult = audioOutput.getMetricsSnapshot();
    if (connResult.code !== 0 || videoResult.code !== 0 || audioResult.code !== 0) {
      return null;
    }
    const connSnapshot = connResult.snapshot;
    const videoSnapshot = videoResult.snapshot;
    const audioSnapshot = audioResult.snapshot;
    if (connSnapshot === null || videoSnapshot === null || audioSnapshot === null) {
      return null;
    }
    const audioDebugResult = audioOutput.getDebugSnapshot();
    const videoDebugResult = videoOutput.getDebugSnapshot();
    return createDownlinkMetricsOverlayModel({
      connSnapshot,
      videoSnapshot,
      audioSnapshot,
      videoDebugSnapshot: videoDebugResult.code === 0 ? videoDebugResult.snapshot : null,
      audioDebugSnapshot: audioDebugResult.code === 0 ? audioDebugResult.snapshot : null,
      requestedDecoderPreference,
    });
  }

  async stop() {
    this.generation += 1;
    if (this.rawDump !== null) {
      await this.rawDump.stop();
      this.rawDump = null;
    }
    this.rawDumpUploadPending = false;
    if (this.recordingTask !== null) {
      const result = await this.recordingTask.stop();
      if (result.success && result.data !== null) {
        this.ownedMediaFiles.add(result.data);
      }
      this.recordingTask = null;
      this.recordingTargetId = null;
    }
    for (const file of this.ownedMediaFiles) {
      if (await file.delete() === 0) {
        this.ownedMediaFiles.delete(file);
      }
    }
    if (this.ownedMediaFiles.size === 0) this.latestMediaFile = null;
    this.latestMediaTargetId = null;
    this.stopRenderPoll();
    this.streamMessageOverlay.clear();
    await this.stopTalkback();
    this.unsubscribeDownlink();
    this.audioOutput?.detach();
    for (const output of this.videoOutputs.values()) output.detach();
    this.conn?.disconnect();
    this.audioOutput?.dispose();
    for (const output of this.videoOutputs.values()) output.dispose();
    this.conn?.dispose();
    this.audioOutput = null;
    this.audioOutputMuted = false;
    this.videoOutputs.clear();
    this.conn = null;
    this.downlinkStreams = null;
    this.downlinkSubscribed = false;
    this.renderSizes.clear();
    this.videoErrors.clear();
    this.connState = TiRtcConnState.idle;
    this.audioState = TiRtcAudioOutputState.idle;
    this.videoStates.clear();
    this.selectedVideoStreamId = null;
    this.setTalkbackState(TiRtcInputState.idle);
    this.firstVideoRendered = false;
    this.pendingLocalEchoReplies = 0;
    this.commandEvents = [];
    TiRtc.shutdown();
  }

  async toggleRecording(): Promise<string> {
    if (this.recordingTask !== null) {
      const result = await this.recordingTask.stop();
      this.recordingTask = null;
      if (result.success && result.data !== null) {
        this.latestMediaFile = result.data;
        this.latestMediaTargetId = this.recordingTargetId;
        this.ownedMediaFiles.add(result.data);
      }
      this.recordingTargetId = null;
      return result.success ? `本地保存完成 · ${result.data?.path ?? ''}` : `本地保存失败 · #${result.code ?? 0}`;
    }
    const connection = this.conn;
    if (connection === null) {
      return '开始本地保存失败 · 播放未就绪';
    }
    const streams = this.downlinkStreams;
    if (streams === null) {
      return '开始本地保存失败 · 流未就绪';
    }
    const streamId = this.selectedVideoStreamId;
    if (streamId === null) return '开始本地保存失败 · 未选择视频';
    if (this.videoStateFor(streamId) !== TiRtcVideoOutputState.rendering) {
      return '开始本地保存失败 · 视频未就绪';
    }
    const result = connection.startRecording({
      videoStreamId: streamId,
      audioStreamId: streams.audio ?? undefined,
    });
    if (!result.success || result.data === null) {
      return `开始本地保存失败 · #${result.code ?? 0}`;
    }
    this.recordingTask = result.data;
    this.recordingTargetId = streamId;
    return '正在本地保存';
  }

  async takeSnapshot(): Promise<string> {
    const streamId = this.selectedVideoStreamId;
    if (streamId === null || this.videoStateFor(streamId) !== TiRtcVideoOutputState.rendering) return '';
    const output = this.videoOutputs.get(streamId);
    const result = await output?.takeSnapshot();
    if (result?.success === true && result.data !== null) {
      this.latestMediaFile = result.data;
      this.latestMediaTargetId = streamId;
      this.ownedMediaFiles.add(result.data);
      return result.data.path;
    }
    return '';
  }

  selectVideoStream(streamId: number): void {
    if (this.videoOutputs.has(streamId)) this.selectedVideoStreamId = streamId;
  }

  videoStateFor(streamId: number): TiRtcVideoOutputState {
    return this.videoStates.get(streamId) ?? TiRtcVideoOutputState.idle;
  }

  videoFailureFor(streamId: number): string {
    const code = this.videoErrors.get(streamId);
    return code === undefined ? '播放失败' : `播放失败 · ${TiRtc.formatError(code)}`;
  }

  renderSizeFor(streamId: number): TiRtcSize | null {
    return this.renderSizes.get(streamId) ?? null;
  }

  async moveLatestMediaToGallery(): Promise<boolean> {
    if (this.latestMediaFile === null) return false;
    if (!await prepareGalleryWritePermission()) return false;
    const file = this.latestMediaFile;
    const result = await file.moveToGallery(
      galleryFileName('durationMs' in file ? 'mp4' : 'jpg', this.latestMediaTargetId ?? undefined),
    );
    if (result.success) this.ownedMediaFiles.delete(file);
    return result.success;
  }

  get commandConnected(): boolean {
    return this.connState === TiRtcConnState.connected;
  }

  get talkbackRunning(): boolean {
    return this.talkbackState === TiRtcInputState.running;
  }

  get streamMessageText(): string | null {
    return this.streamMessageOverlay.text;
  }

  private startRenderPoll() {
    this.stopRenderPoll();
    this.renderPoll = setInterval(() => {
      if (this.videoOutputs.size === 0) {
        this.stopRenderPoll();
        return;
      }
      for (const [streamId, output] of this.videoOutputs) {
        const size = validSize(output.renderSize) ?? this.debugRenderSize(output);
        if (output.state === TiRtcVideoOutputState.rendering || this.hasVideoRendered(output) || size !== null) {
          this.markVideoRendering(streamId, size);
        }
      }
    }, 500);
  }

  private stopRenderPoll() {
    if (this.renderPoll !== null) {
      clearInterval(this.renderPoll);
      this.renderPoll = null;
    }
  }

  private async failStartup(status: string) {
    TiRtcLogging.e('TiRtcRnExample', `client_start_failed status=${status}`);
    await this.stop();
    this.setStatus(status);
  }

  private subscribeDownlinkIfReady(): number {
    if (this.downlinkSubscribed) {
      return 0;
    }
    if (this.connState !== TiRtcConnState.connected || this.conn === null || this.downlinkStreams === null) {
      return 0;
    }
    if (this.downlinkStreams.audio !== null && this.audioOutput !== null) {
      const audioCode = this.conn.subscribeAudio(this.downlinkStreams.audio);
      if (audioCode !== 0) {
        const audioOutput = this.audioOutput;
        this.audioOutput = null;
        this.audioState = TiRtcAudioOutputState.failed;
        audioOutput.detach();
        audioOutput.dispose();
        this.setStatus(`音频订阅失败 · ${TiRtc.formatError(audioCode)}`);
      }
    }
    for (const streamId of this.downlinkStreams.videos) {
      if (this.videoStates.get(streamId) === TiRtcVideoOutputState.failed) continue;
      const videoCode = this.conn.subscribeVideo(streamId);
      if (videoCode !== 0) {
        this.videoStates.set(streamId, TiRtcVideoOutputState.failed);
        this.setStatus(`视频 ${streamId} 订阅失败 · ${TiRtc.formatError(videoCode)}`);
        continue;
      }
      const keyFrameCode = this.conn.requestKeyFrame(streamId);
      if (keyFrameCode !== 0) {
        this.setStatus(`视频 ${streamId} 关键帧请求失败 · ${TiRtc.formatError(keyFrameCode)}`);
      }
    }
    this.downlinkSubscribed = true;
    return 0;
  }

  private unsubscribeDownlink() {
    if (this.conn === null || this.downlinkStreams === null) {
      return;
    }
    for (const streamId of this.downlinkStreams.videos) this.conn.unsubscribeVideo(streamId);
    if (this.downlinkStreams.audio !== null) this.conn.unsubscribeAudio(this.downlinkStreams.audio);
    this.downlinkSubscribed = false;
  }

  private retireAudioOutput(output: TiRtcAudioOutput) {
    if (this.audioOutput !== output) return;
    const audioStreamId = this.downlinkStreams?.audio;
    if (this.conn !== null && audioStreamId !== null && audioStreamId !== undefined) {
      this.conn.unsubscribeAudio(audioStreamId);
    }
    this.audioOutput = null;
    output.detach();
    output.dispose();
  }

  private markVideoRendering(streamId: number, size: TiRtcSize | null) {
    const nextSize = validSize(size);
    if (nextSize !== null) {
      this.renderSizes.set(streamId, nextSize);
      this.firstVideoRendered = true;
      this.setStatus(`video ${streamId} rendering ${nextSize.width}x${nextSize.height}`);
      return;
    }
    this.firstVideoRendered = true;
    this.setStatus(`video ${streamId} rendering`);
  }

  private setTalkbackState(state: TiRtcInputState) {
    this.talkbackState = state;
    this.onTalkbackStateChanged?.(state === TiRtcInputState.running);
  }

  private debugRenderSize(output: TiRtcVideoOutput): TiRtcSize | null {
    const snapshot = output.getDebugSnapshot().snapshot;
    if (!snapshot) {
      return null;
    }
    return validSize({width: snapshot.width, height: snapshot.height});
  }

  private hasVideoRendered(output: TiRtcVideoOutput): boolean {
    return output.getMetricsSnapshot().snapshot?.startup.hasFirstOutput === true;
  }

  private handleReceivedCommand(commandId: number, payload: Uint8Array) {
    this.appendCommandEvent({
      direction: 'received',
      commandId,
      payload: clonePayload(payload),
      createdAt: Date.now(),
    });
    const echoCode = this.echoCommandIfNeeded(commandId, payload);
    if (echoCode !== null) {
      this.appendCommandEvent({
        direction: 'sent',
        commandId,
        payload: clonePayload(payload),
        resultCode: echoCode,
        createdAt: Date.now(),
      });
    }
    this.setStatus(`command received ${formatCommandId(commandId)} bytes=${payload.length}`);
  }

  private handleStreamMessage(expectedStreamId: number, streamId: number, payload: Uint8Array) {
    const event = this.streamMessageOverlay.handleIncoming({
      expectedStreamId,
      streamId,
      timestampMs: 0,
      payload,
      onHidden: () => {
        this.setStatus(this.firstVideoRendered ? 'video rendering' : 'client connected');
      },
    });
    if (event === null) {
      return;
    }
    this.setStatus(`stream message ${streamId} bytes=${payload.length}`);
  }

  private echoCommandIfNeeded(commandId: number, payload: Uint8Array): number | null {
    if (!isDemoEchoCommand(commandId, payload)) {
      return null;
    }
    if (this.pendingLocalEchoReplies > 0) {
      this.pendingLocalEchoReplies -= 1;
      return null;
    }
    const code = this.conn?.sendCommand(commandId, clonePayload(payload)) ?? commandInvalidStateCode;
    if (code === 0) {
      this.pendingLocalEchoReplies += 1;
    }
    return code;
  }

  private appendCommandEvent(event: CommandPanelEvent) {
    this.commandEvents = trimCommandEvents([...this.commandEvents, event]);
  }
}
