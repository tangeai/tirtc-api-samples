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
import {parseLocalAudioStreamId, type ExampleConfig} from './ExampleTypes';

export class ClientSession {
  conn: TiRtcConn | null = null;
  audioOutput: TiRtcAudioOutput | null = null;
  videoOutput: TiRtcVideoOutput | null = null;
  talkback: TiRtcAudioInput | null = null;
  renderSize: TiRtcSize | null = null;
  audioOutputMuted = false;
  onTalkbackStateChanged: ((running: boolean) => void) | null = null;
  recordingTask: TiRtcRecordingTask | null = null;
  private latestMediaFile: TiRtcRecordingFile | TiRtcSnapshotFile | null = null;
  private readonly ownedMediaFiles = new Set<TiRtcRecordingFile | TiRtcSnapshotFile>();
  private connState: TiRtcConnState = TiRtcConnState.idle;
  private audioState: TiRtcAudioOutputState = TiRtcAudioOutputState.idle;
  private videoState: TiRtcVideoOutputState = TiRtcVideoOutputState.idle;
  private talkbackState: TiRtcInputState = TiRtcInputState.idle;
  private firstVideoRendered = false;
  private renderPoll: ReturnType<typeof setInterval> | null = null;
  private downlinkStreams: {audio: number; video: number} | null = null;
  private downlinkSubscribed = false;
  private readonly streamMessageOverlay = new DemoStreamMessageOverlayController();
  private pendingLocalEchoReplies = 0;
  commandEvents: CommandPanelEvent[] = [];

  constructor(private readonly setStatus: (status: string) => void) {}

  async start(config: ExampleConfig, streams: {audio: number; video: number}) {
    await this.stop();
    this.stopRenderPoll();
    this.renderSize = null;
    this.audioOutputMuted = false;
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

    this.conn = new TiRtcConn();
    this.conn.onStateChanged = (state, code) => {
      this.connState = state;
      if (state === TiRtcConnState.connected) {
        const subscribeCode = this.subscribeDownlinkIfReady();
        if (subscribeCode !== 0) {
          void this.failStartup(`订阅失败 · ${TiRtc.formatError(subscribeCode)}`);
          return;
        }
        this.setStatus('client connected');
        return;
      }
      if (state === TiRtcConnState.disconnected && code !== 0) {
        this.setStatus(`连接失败 · ${TiRtc.formatError(code)}`);
        return;
      }
      this.setStatus(`conn ${state} code=${code}`);
    };
    this.conn.onCommand = (commandId, data) => {
      this.handleReceivedCommand(commandId, data);
    };
    this.conn.onStreamMessage = (streamId, _timestampMs, data) => {
      this.handleStreamMessage(streams.video, streamId, data);
    };

    this.audioOutput = new TiRtcAudioOutput();
    this.videoOutput = new TiRtcVideoOutput();
    this.audioOutput.onStateChanged = (state) => {
      this.audioState = state;
      if (state === TiRtcAudioOutputState.playing) {
        this.setStatus('audio playing');
      }
    };
    this.videoOutput.onStateChanged = (state) => {
      this.videoState = state;
      if (state === TiRtcVideoOutputState.rendering) {
        this.markVideoRendering(this.videoOutput?.renderSize ?? null);
      }
    };
    this.audioOutput.onError = (code) => {
      this.setStatus(`音频播放失败 · ${TiRtc.formatError(code)}`);
    };
    this.videoOutput.onError = (code) => {
      this.setStatus(`视频播放失败 · ${TiRtc.formatError(code)}`);
    };
    this.videoOutput.onRenderSizeChanged = (size) => {
      this.markVideoRendering(size);
    };
    const outputBufferStrategy = outputBufferStrategyFromConfig(config.outputBufferPolicy);
    const audioOptionsCode = this.audioOutput.configure({bufferStrategy: outputBufferStrategy});
    TiRtcLogging.i('TiRtcRnExample', `client_audio_output_options_done code=${audioOptionsCode}`);
    if (audioOptionsCode !== 0) {
      await this.failStartup(`音频播放配置失败 · ${TiRtc.formatError(audioOptionsCode)}`);
      return;
    }
    const videoOptionsCode = this.videoOutput.setOptions({
      decoderPreference: videoDecoderPreferenceFromConfig(config.videoDecoderPreference),
      bufferStrategy: outputBufferStrategy,
    });
    TiRtcLogging.i('TiRtcRnExample', `client_video_output_options_done code=${videoOptionsCode}`);
    if (videoOptionsCode !== 0) {
      await this.failStartup(`视频播放配置失败 · ${TiRtc.formatError(videoOptionsCode)}`);
      return;
    }
    const audioAttachCode = this.audioOutput.attach(this.conn, streams.audio);
    TiRtcLogging.i(
      'TiRtcRnExample',
      `client_audio_output_attach_done code=${audioAttachCode} stream_id=${streams.audio}`,
    );
    if (audioAttachCode !== 0) {
      await this.failStartup(`音频播放启动失败 · ${TiRtc.formatError(audioAttachCode)}`);
      return;
    }
    const videoAttachCode = this.videoOutput.attach(this.conn, streams.video);
    TiRtcLogging.i(
      'TiRtcRnExample',
      `client_video_output_attach_done code=${videoAttachCode} stream_id=${streams.video}`,
    );
    if (videoAttachCode !== 0) {
      await this.failStartup(`视频播放启动失败 · ${TiRtc.formatError(videoAttachCode)}`);
      return;
    }
    this.downlinkStreams = {...streams};
    const connectCode = this.conn.connect(config.remoteId, config.token);
    TiRtcLogging.i('TiRtcRnExample', `client_connect_done code=${connectCode}`);
    if (connectCode !== 0) {
      await this.failStartup(`连接失败 · ${TiRtc.formatError(connectCode)}`);
      return;
    }
    const subscribeCode = this.subscribeDownlinkIfReady();
    if (subscribeCode !== 0) {
      await this.failStartup(`订阅失败 · ${TiRtc.formatError(subscribeCode)}`);
      return;
    }
    this.setStatus(this.downlinkSubscribed ? '等待首帧' : '等待连接');
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
    const streamId = parseLocalAudioStreamId(config);
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
      `video ${this.videoState} · ${formatFps(videoMetrics?.videoRenderFps)}`,
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
    if (this.recordingTask !== null) {
      const result = await this.recordingTask.stop();
      if (result.success && result.data !== null) {
        this.ownedMediaFiles.add(result.data);
      }
      this.recordingTask = null;
    }
    for (const file of this.ownedMediaFiles) {
      if (await file.delete() === 0) {
        this.ownedMediaFiles.delete(file);
      }
    }
    if (this.ownedMediaFiles.size === 0) this.latestMediaFile = null;
    this.stopRenderPoll();
    this.streamMessageOverlay.clear();
    await this.stopTalkback();
    this.unsubscribeDownlink();
    this.audioOutput?.detach();
    this.videoOutput?.detach();
    this.conn?.disconnect();
    this.audioOutput?.dispose();
    this.videoOutput?.dispose();
    this.conn?.dispose();
    this.audioOutput = null;
    this.audioOutputMuted = false;
    this.videoOutput = null;
    this.conn = null;
    this.downlinkStreams = null;
    this.downlinkSubscribed = false;
    this.renderSize = null;
    this.connState = TiRtcConnState.idle;
    this.audioState = TiRtcAudioOutputState.idle;
    this.videoState = TiRtcVideoOutputState.idle;
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
        this.ownedMediaFiles.add(result.data);
      }
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
    const result = connection.startRecording({
      videoStreamId: streams.video,
      audioStreamId: streams.audio,
    });
    if (!result.success || result.data === null) {
      return `开始本地保存失败 · #${result.code ?? 0}`;
    }
    this.recordingTask = result.data;
    return '正在本地保存';
  }

  async takeSnapshot(): Promise<string> {
    const result = await this.videoOutput?.takeSnapshot();
    if (result?.success === true && result.data !== null) {
      this.latestMediaFile = result.data;
      this.ownedMediaFiles.add(result.data);
      return result.data.path;
    }
    return '';
  }

  async moveLatestMediaToGallery(): Promise<boolean> {
    if (this.latestMediaFile === null) return false;
    if (!await prepareGalleryWritePermission()) return false;
    const file = this.latestMediaFile;
    const result = await file.moveToGallery(
      galleryFileName('durationMs' in file ? 'mp4' : 'jpg'),
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
      const output = this.videoOutput;
      if (!output) {
        this.stopRenderPoll();
        return;
      }
      const size = validSize(output.renderSize) ?? this.debugRenderSize(output);
      if (output.state === TiRtcVideoOutputState.rendering || this.hasVideoRendered(output) || size !== null) {
        this.markVideoRendering(size);
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
    const audioCode = this.conn.subscribeAudio(this.downlinkStreams.audio);
    TiRtcLogging.i(
      'TiRtcRnExample',
      `client_subscribe_audio_done code=${audioCode} stream_id=${this.downlinkStreams.audio}`,
    );
    if (audioCode !== 0) {
      return audioCode;
    }
    const videoCode = this.conn.subscribeVideo(this.downlinkStreams.video);
    TiRtcLogging.i(
      'TiRtcRnExample',
      `client_subscribe_video_done code=${videoCode} stream_id=${this.downlinkStreams.video}`,
    );
    if (videoCode !== 0) {
      return videoCode;
    }
    const keyFrameCode = this.conn.requestKeyFrame(this.downlinkStreams.video);
    TiRtcLogging.i(
      'TiRtcRnExample',
      `client_request_key_frame_done code=${keyFrameCode} stream_id=${this.downlinkStreams.video}`,
    );
    if (keyFrameCode !== 0) {
      return keyFrameCode;
    }
    this.downlinkSubscribed = true;
    return 0;
  }

  private unsubscribeDownlink() {
    if (this.conn === null || this.downlinkStreams === null) {
      return;
    }
    const videoCode = this.conn.unsubscribeVideo(this.downlinkStreams.video);
    const audioCode = this.conn.unsubscribeAudio(this.downlinkStreams.audio);
    TiRtcLogging.i(
      'TiRtcRnExample',
      `client_unsubscribe_downlink_done audio_code=${audioCode} video_code=${videoCode}`,
    );
    this.downlinkSubscribed = false;
  }

  private markVideoRendering(size: TiRtcSize | null) {
    const nextSize = validSize(size);
    if (nextSize !== null) {
      this.renderSize = nextSize;
      this.firstVideoRendered = true;
      this.stopRenderPoll();
      this.setStatus(`video rendering ${nextSize.width}x${nextSize.height}`);
      return;
    }
    this.firstVideoRendered = true;
    this.setStatus('video rendering');
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
