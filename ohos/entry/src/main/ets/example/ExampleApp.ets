import { hilog } from '@kit.PerformanceAnalysisKit';
import type { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import {
  TiRtcAudioAecMode,
  TiRtcAudioAgcLevel,
  TiRtcAudioAnsLevel,
  TiRtcAudioChannelCount,
  TiRtcAudioCodec,
  TiRtcAudioOutputState,
  TiRtcAudioSampleRate,
  TiRtcConnState,
  TiRtcOutputBufferStrategy,
  TiRtcVideoDecoderPreference,
  TiRtcVideoOutputState,
} from 'tirtc/Index';
import {
  appStorageString,
  DEFAULT_AUDIO_STREAM_ID,
  DEFAULT_VIDEO_STREAM_ID,
  ExampleView,
  LOG_DOMAIN,
  LOG_TAG,
  parseAudioInputChannels,
  parseAudioInputCodec,
  parseAudioInputSampleRate,
  parseAudioAecMode,
  parseAudioAgcLevel,
  parseAudioAnsLevel,
  parseConsoleLogEnabled,
  parseOutputBufferStrategy,
  parseStreamId,
  parseVideoDecoderPreference,
  writeAppStorageString,
} from './ExampleConfig';
import { DownlinkRoleSession } from './DownlinkRoleSession';
import { requestMicrophonePermission } from './ExamplePermissions';
import { saveMediaFileToGallery } from './ExampleMediaGallery';
import { ExampleRouteHost } from './ExampleRouteHost';
import {
  DemoTokenSource,
  demoTokenSourceStorageValue,
  normalizeDemoTokenIssuerBaseUrl,
  parseDemoTokenSource,
  resolveDemoConnectionToken,
  tryParseDemoScanPayload,
  tryParseDemoCloudStorageScanPayload,
} from './ExampleTokenAcquisition';

@Component
export struct ExampleApp {
  private downlinkSession: DownlinkRoleSession = new DownlinkRoleSession();

  @State private view: ExampleView = ExampleView.configure;
  @State private appId: string = appStorageString('tirtc.app_id');
  @State private endpoint: string = appStorageString('tirtc.endpoint');
  @State private remoteId: string = appStorageString('tirtc.remote_id');
  @State private token: string = appStorageString('tirtc.token');
  @State private cloudStorageAppId: string = appStorageString('ti_cloud_storage.app_id');
  @State private cloudStorageEndpoint: string = appStorageString('ti_cloud_storage.endpoint');
  @State private cloudStorageToken: string = appStorageString('ti_cloud_storage.app_token');
  @State private cloudStorageAudioChannelId: string = appStorageString('ti_cloud_storage.audio_channel_id') || '10';
  @State private cloudStorageVideoChannelId: string = appStorageString('ti_cloud_storage.video_channel_id') || '11';
  @State private tokenIssuerBaseUrl: string = appStorageString('tirtc.token_issuer_base_url');
  @State private tokenSource: DemoTokenSource = parseDemoTokenSource(appStorageString('tirtc.token_source'));
  @State private qrPayloadText: string = '';
  @State private qrErrorText: string = '';
  @State private qrForCloudStorage: boolean = false;
  @State private audioStreamId: string = appStorageString('tirtc.audio_stream_id');
  @State private videoStreamId: string = appStorageString('tirtc.video_stream_id');
  @State private videoDecoderPreference: TiRtcVideoDecoderPreference =
    parseVideoDecoderPreference(appStorageString('tirtc.video_decoder_preference'));
  @State private outputBufferStrategy: TiRtcOutputBufferStrategy =
    parseOutputBufferStrategy(appStorageString('tirtc.output_buffer_strategy'));
  @State private audioInputCodec: TiRtcAudioCodec = parseAudioInputCodec(appStorageString('tirtc.audio_input_codec'));
  @State private audioInputSampleRate: TiRtcAudioSampleRate =
    parseAudioInputSampleRate(appStorageString('tirtc.audio_input_sample_rate'));
  @State private audioInputChannels: TiRtcAudioChannelCount =
    parseAudioInputChannels(appStorageString('tirtc.audio_input_channels'));
  @State private audioAecMode: TiRtcAudioAecMode = parseAudioAecMode(appStorageString('tirtc.audio_aec_mode'));
  @State private audioAgcLevel: TiRtcAudioAgcLevel = parseAudioAgcLevel(appStorageString('tirtc.audio_agc_level'));
  @State private audioAnsLevel: TiRtcAudioAnsLevel = parseAudioAnsLevel(appStorageString('tirtc.audio_ans_level'));
  @State private consoleLogEnabled: boolean = parseConsoleLogEnabled(appStorageString('tirtc.console_log_enabled'));
  @State private statusLabel: string = '加载中';
  @State private detailLabel: string = '填写参数后开始连接';
  @State private connecting: boolean = false;
  @State private playing: boolean = false;
  @State private lastError: string = '';
  @State private connState: TiRtcConnState = TiRtcConnState.idle;
  @State private audioState: TiRtcAudioOutputState = TiRtcAudioOutputState.idle;
  @State private videoState: TiRtcVideoOutputState = TiRtcVideoOutputState.idle;
  @State private localAudioStarted: boolean = false;
  @State private audioOutputMuted: boolean = false;
  @State private recording: boolean = false;
  @State private mediaAvailable: boolean = false;
  @State private metricsLabel: string = '';
  @State private commandStatus: string = '';
  @State private streamMessageStatus: string = '';
  @State private logUploadStatus: string = '';
  @State private downlinkRenderWidth: number = 0;
  @State private downlinkRenderHeight: number = 0;

  aboutToDisappear(): void {
    void this.stopDownlink('page_disappear');
  }

  build() {
    Stack() {
      ExampleRouteHost({
        view: this.view,
        endpoint: this.endpoint,
        appId: this.appId,
        remoteId: this.remoteId,
        token: this.token,
        cloudStorageAppId: this.cloudStorageAppId,
        cloudStorageEndpoint: this.cloudStorageEndpoint,
        cloudStorageToken: this.cloudStorageToken,
        cloudStorageAudioChannelId: this.cloudStorageAudioChannelId,
        cloudStorageVideoChannelId: this.cloudStorageVideoChannelId,
        tokenIssuerBaseUrl: this.tokenIssuerBaseUrl,
        tokenSource: this.tokenSource,
        qrPayloadText: this.qrPayloadText,
        qrErrorText: this.qrErrorText,
        qrForCloudStorage: this.qrForCloudStorage,
        audioStreamId: this.audioStreamId,
        videoStreamId: this.videoStreamId,
        videoDecoderPreference: this.videoDecoderPreference,
        outputBufferStrategy: this.outputBufferStrategy,
        audioInputCodec: this.audioInputCodec,
        audioInputSampleRate: this.audioInputSampleRate,
        audioInputChannels: this.audioInputChannels,
        audioAecMode: this.audioAecMode,
        audioAgcLevel: this.audioAgcLevel,
        audioAnsLevel: this.audioAnsLevel,
        consoleLogEnabled: this.consoleLogEnabled,
        statusLabel: this.statusLabel,
        detailLabel: this.detailLabel,
        connecting: this.connecting,
        playing: this.playing,
        lastError: this.lastError,
        connState: this.connState,
        audioState: this.audioState,
        videoState: this.videoState,
        localAudioStarted: this.localAudioStarted,
        audioOutputMuted: this.audioOutputMuted,
        recording: this.recording,
        mediaAvailable: this.mediaAvailable,
        metricsLabel: this.metricsLabel,
        commandStatus: this.commandStatus,
        streamMessageStatus: this.streamMessageStatus,
        logUploadStatus: this.logUploadStatus,
        downlinkRenderWidth: this.downlinkRenderWidth,
        downlinkRenderHeight: this.downlinkRenderHeight,
        videoOutput: this.downlinkSession.videoOutputViewModel(),
        onOpenSettings: (): void => {
          hilog.info(LOG_DOMAIN, LOG_TAG, 'TIRTC_open_settings_requested');
          this.setSystemBarContentColor('#000000');
          this.view = ExampleView.settings;
        },
        onEndpointChanged: (value: string): void => {
          this.endpoint = value;
          writeAppStorageString('tirtc.endpoint', value);
        },
        onAppIdChanged: (value: string): void => {
          this.appId = value;
          writeAppStorageString('tirtc.app_id', value);
        },
        onRemoteIdChanged: (value: string): void => {
          this.remoteId = value;
          writeAppStorageString('tirtc.remote_id', value);
        },
        onTokenChanged: (value: string): void => {
          this.token = value;
          if (value.trim().length > 0) this.tokenSource = DemoTokenSource.oneTime;
          writeAppStorageString('tirtc.token', value);
        },
        onCloudStorageAppIdChanged: (value: string): void => {
          this.cloudStorageAppId = value;
          writeAppStorageString('ti_cloud_storage.app_id', value);
        },
        onCloudStorageEndpointChanged: (value: string): void => {
          this.cloudStorageEndpoint = value;
          writeAppStorageString('ti_cloud_storage.endpoint', value);
        },
        onCloudStorageTokenChanged: (value: string): void => {
          this.cloudStorageToken = value;
          writeAppStorageString('ti_cloud_storage.app_token', value);
        },
        onCloudStorageAudioChannelIdChanged: (value: string): void => {
          this.cloudStorageAudioChannelId = value;
          writeAppStorageString('ti_cloud_storage.audio_channel_id', value);
        },
        onCloudStorageVideoChannelIdChanged: (value: string): void => {
          this.cloudStorageVideoChannelId = value;
          writeAppStorageString('ti_cloud_storage.video_channel_id', value);
        },
        onTokenIssuerBaseUrlChanged: (value: string): void => {
          this.tokenIssuerBaseUrl = value;
          if (value.trim().length > 0) this.tokenSource = DemoTokenSource.issuer;
          writeAppStorageString('tirtc.token_issuer_base_url', value);
        },
        onTokenSourceChanged: (value: DemoTokenSource): void => {
          this.tokenSource = value;
          writeAppStorageString('tirtc.token_source', demoTokenSourceStorageValue(value));
        },
        onOpenQrScanner: (): void => {
          this.qrForCloudStorage = false;
          this.qrPayloadText = '';
          this.qrErrorText = '';
          this.view = ExampleView.qrScanner;
        },
        onOpenCloudStorageQrScanner: (): void => {
          this.qrForCloudStorage = true;
          this.qrPayloadText = '';
          this.qrErrorText = '';
          this.view = ExampleView.qrScanner;
        },
        onQrScannerBack: (): void => {
          this.qrErrorText = '';
          this.view = ExampleView.configure;
        },
        onQrPayloadChanged: (value: string): void => {
          this.qrPayloadText = value;
          this.qrErrorText = '';
        },
        onApplyQrPayload: (): void => {
          this.applyQrPayload();
        },
        onAudioStreamIdChanged: (value: string): void => {
          this.audioStreamId = value;
          writeAppStorageString('tirtc.audio_stream_id', value);
        },
        onVideoStreamIdChanged: (value: string): void => {
          this.videoStreamId = value;
          writeAppStorageString('tirtc.video_stream_id', value);
        },
        onOpenPlayer: (): void => {
          void this.openPlayer();
        },
        onOpenCloudStorage: (): void => {
          const audioChannelId = parseStreamId(this.cloudStorageAudioChannelId, -1);
          const videoChannelId = parseStreamId(this.cloudStorageVideoChannelId, -1);
          if (this.cloudStorageAppId.trim().length === 0 || this.cloudStorageToken.length === 0 ||
            this.cloudStorageToken !== this.cloudStorageToken.trim() || audioChannelId < 0 || audioChannelId > 255 ||
            videoChannelId < 0 || videoChannelId > 255) {
            this.lastError = '请补全云录像参数；Token 首尾不能有空白，Channel ID 必须为 0..255。';
            return;
          }
          this.lastError = '';
          this.view = ExampleView.cloudStorage;
        },
        onCloudStorageBack: (): void => {
          this.view = ExampleView.configure;
        },
        onSettingsBack: (): void => {
          this.setSystemBarContentColor('#000000');
          this.view = ExampleView.configure;
        },
        onDecoderPreferenceChanged: (value: TiRtcVideoDecoderPreference): void => {
          this.videoDecoderPreference = value;
          writeAppStorageString('tirtc.video_decoder_preference', `${value}`);
        },
        onOutputBufferStrategyChanged: (value: TiRtcOutputBufferStrategy): void => {
          this.outputBufferStrategy = value;
          writeAppStorageString('tirtc.output_buffer_strategy', `${value}`);
        },
        onAudioInputCodecChanged: (value: TiRtcAudioCodec): void => {
          this.audioInputCodec = value;
          writeAppStorageString('tirtc.audio_input_codec', `${value}`);
        },
        onAudioInputSampleRateChanged: (value: TiRtcAudioSampleRate): void => {
          this.audioInputSampleRate = value;
          writeAppStorageString('tirtc.audio_input_sample_rate', `${value}`);
        },
        onAudioAecModeChanged: (value: TiRtcAudioAecMode): void => {
          this.audioAecMode = value;
          writeAppStorageString('tirtc.audio_aec_mode', `${value}`);
        },
        onAudioAgcLevelChanged: (value: TiRtcAudioAgcLevel): void => {
          this.audioAgcLevel = value;
          writeAppStorageString('tirtc.audio_agc_level', `${value}`);
        },
        onAudioAnsLevelChanged: (value: TiRtcAudioAnsLevel): void => {
          this.audioAnsLevel = value;
          writeAppStorageString('tirtc.audio_ans_level', `${value}`);
        },
        onConsoleLogEnabledChanged: (value: boolean): void => {
          this.consoleLogEnabled = value;
          writeAppStorageString('tirtc.console_log_enabled', value ? 'true' : 'false');
        },
        onPlayerBack: (): void => {
          this.stopDownlink('back_to_configure');
          this.setSystemBarContentColor('#000000');
          this.view = ExampleView.configure;
        },
        onPlayerToggle: (): void => {
          if (this.playing) {
            this.stopDownlink('manual_stop');
          } else {
            this.startDownlink();
          }
        },
        onPlayerLocalAudioToggle: (): void => {
          void this.toggleDownlinkLocalAudio();
        },
        onPlayerAudioOutputVolumeToggle: (): void => {
          this.toggleDownlinkAudioOutputVolume();
        },
        onPlayerRecordingToggle: (): void => {
          void this.toggleDownlinkRecording();
        },
        onPlayerSnapshot: (): void => {
          void this.takeDownlinkSnapshot();
        },
        onPlayerSaveMedia: (): void => {
          void this.saveDownlinkMedia();
        },
        onSendDownlinkCommand: (commandId: number, payload: Uint8Array): number => {
          return this.sendDownlinkControlMessage(commandId, payload);
        },
        onUploadDownlinkLogs: (): void => {
          this.uploadDownlinkLogs();
        },
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFF8E8')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  private async openPlayer(): Promise<void> {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'TIRTC_open_player_requested');
    if (!this.validateConfiguration()) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'TIRTC_open_player_validation_failed reason=%{public}s', this.lastError);
      return;
    }
    const resolvedToken = await this.resolveClientToken();
    if (resolvedToken.length === 0) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'TIRTC_open_player_token_resolve_failed reason=%{public}s', this.lastError);
      return;
    }
    this.setSystemBarContentColor('#FFFFFF');
    this.view = ExampleView.player;
    this.statusLabel = '加载中';
    this.detailLabel = '正在连接远端设备';
    this.resetPlayerEvidenceLabels();
    setTimeout((): void => {
      void this.startDownlink();
    }, 0);
    hilog.info(LOG_DOMAIN, LOG_TAG,
      'TIRTC_open_player_ready remote_id=%{public}s audio_stream=%{public}s video_stream=%{public}s',
      this.remoteId, this.audioStreamId, this.videoStreamId);
  }

  private validateConfiguration(): boolean {
    if (this.appId.trim().length === 0 || this.remoteId.trim().length === 0) {
      this.lastError = '请先补全 app_id / remote_id。';
      return false;
    }
    if (this.tokenSource === DemoTokenSource.issuer && this.tokenIssuerBaseUrl.trim().length === 0) {
      this.lastError = '请先补全 Token 签发服务地址。';
      return false;
    }
    if (this.tokenSource === DemoTokenSource.oneTime && this.token.trim().length === 0) {
      this.lastError = '请先补全一次性连接 Token。';
      return false;
    }
    this.lastError = '';
    return true;
  }

  private async resolveClientToken(): Promise<string> {
    this.connecting = true;
    this.lastError = '';
    try {
      const token = await resolveDemoConnectionToken(
        this.tokenSource,
        this.tokenIssuerBaseUrl,
        this.token,
        this.remoteId.trim(),
      );
      if (this.tokenSource === DemoTokenSource.issuer) {
        const normalizedUrl = normalizeDemoTokenIssuerBaseUrl(this.tokenIssuerBaseUrl);
        this.tokenIssuerBaseUrl = normalizedUrl;
        writeAppStorageString('tirtc.token_issuer_base_url', normalizedUrl);
      }
      this.token = token;
      writeAppStorageString('tirtc.token', token);
      return token;
    } catch (error) {
      this.lastError = '连接 Token 无效或签发失败，请检查 Token 配置。';
      this.statusLabel = 'Token 获取失败';
      this.detailLabel = error instanceof Error ? error.message : String(error);
      return '';
    } finally {
      this.connecting = false;
    }
  }

  private applyQrPayload(): void {
    if (this.qrForCloudStorage) {
      const payload = tryParseDemoCloudStorageScanPayload(this.qrPayloadText);
      if (payload === undefined) {
        this.qrErrorText = '二维码内容不是有效的云录像 Token。';
        return;
      }
      this.cloudStorageToken = payload.token;
      writeAppStorageString('ti_cloud_storage.app_token', payload.token);
      if (payload.appId !== undefined) {
        this.cloudStorageAppId = payload.appId;
        writeAppStorageString('ti_cloud_storage.app_id', payload.appId);
      }
      if (payload.endpoint !== undefined) {
        this.cloudStorageEndpoint = payload.endpoint;
        writeAppStorageString('ti_cloud_storage.endpoint', payload.endpoint);
      }
      this.qrPayloadText = '';
      this.qrErrorText = '';
      this.view = ExampleView.configure;
      return;
    }
    const payload = tryParseDemoScanPayload(this.qrPayloadText);
    if (payload === undefined) {
      this.qrErrorText = '二维码内容无效，请检查必填字段与字段格式。';
      return;
    }
    if (payload.appId !== undefined) {
      this.appId = payload.appId;
      writeAppStorageString('tirtc.app_id', payload.appId);
    }
    if (payload.remoteId !== undefined) {
      this.remoteId = payload.remoteId;
      writeAppStorageString('tirtc.remote_id', payload.remoteId);
    }
    if (payload.endpoint !== undefined) {
      this.endpoint = payload.endpoint;
      writeAppStorageString('tirtc.endpoint', payload.endpoint);
    }
    this.token = payload.token;
    this.tokenSource = DemoTokenSource.oneTime;
    writeAppStorageString('tirtc.token', payload.token);
    writeAppStorageString('tirtc.token_source', demoTokenSourceStorageValue(DemoTokenSource.oneTime));
    this.qrPayloadText = '';
    this.qrErrorText = '';
    this.view = ExampleView.configure;
  }

  private async startDownlink(): Promise<void> {
    if (this.view !== ExampleView.player || this.connecting || this.playing) {
      return;
    }
    const context = getContext(this) as common.UIAbilityContext;
    const audioStream = parseStreamId(this.audioStreamId, DEFAULT_AUDIO_STREAM_ID);
    const videoStream = parseStreamId(this.videoStreamId, DEFAULT_VIDEO_STREAM_ID);
    await this.downlinkSession.start({
      context,
      endpoint: this.endpoint.trim(),
      appId: this.appId.trim(),
      remoteId: this.remoteId.trim(),
      token: this.token.trim(),
      audioStreamId: audioStream,
      videoStreamId: videoStream,
      videoDecoderPreference: this.videoDecoderPreference,
      outputBufferStrategy: this.outputBufferStrategy,
      consoleLogEnabled: this.consoleLogEnabled,
    }, {
      onConnectingChanged: (value: boolean): void => {
        this.connecting = value;
      },
      onPlayingChanged: (value: boolean): void => {
        this.playing = value;
      },
      onStatusChanged: (status: string, detail: string): void => {
        this.statusLabel = status;
        this.detailLabel = detail;
      },
      onLastErrorChanged: (error: string): void => {
        this.lastError = error;
      },
      onConnStateChanged: (state: TiRtcConnState): void => {
        this.connState = state;
      },
      onAudioStateChanged: (state: TiRtcAudioOutputState): void => {
        this.audioState = state;
      },
      onVideoStateChanged: (state: TiRtcVideoOutputState): void => {
        this.videoState = state;
      },
      onMetricsChanged: (value: string): void => {
        this.metricsLabel = value;
      },
      onRenderSizeChanged: (width: number, height: number): void => {
        this.downlinkRenderWidth = width;
        this.downlinkRenderHeight = height;
      },
      onCommandStatusChanged: (value: string): void => {
        this.commandStatus = value;
      },
      onStreamMessageStatusChanged: (value: string): void => {
        this.streamMessageStatus = value;
      },
      onLogUploadStatusChanged: (value: string): void => {
        this.logUploadStatus = value;
      },
      onLocalAudioStartedChanged: (value: boolean): void => {
        this.localAudioStarted = value;
      },
      onAudioOutputMutedChanged: (value: boolean): void => {
        this.audioOutputMuted = value;
      },
    });
  }

  private async stopDownlink(reason: string): Promise<void> {
    await this.downlinkSession.stop(reason);
    this.recording = false;
    this.mediaAvailable = false;
    this.localAudioStarted = false;
    this.audioOutputMuted = false;
  }

  private async toggleDownlinkRecording(): Promise<void> {
    this.statusLabel = await this.downlinkSession.toggleRecording();
    this.recording = this.downlinkSession.isRecording();
    this.mediaAvailable = this.downlinkSession.latestMediaPath().length > 0;
  }

  private async takeDownlinkSnapshot(): Promise<void> {
    const path = await this.downlinkSession.takeSnapshot();
    if (path.length === 0) {
      this.statusLabel = '截图失败';
      return;
    }
    this.statusLabel = `截图完成 · ${path}`;
    this.mediaAvailable = true;
  }

  private async saveDownlinkMedia(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    const saved = await saveMediaFileToGallery(
      context,
      this.downlinkSession.latestMediaPath(),
      this.downlinkSession.latestMediaKind(),
    );
    this.statusLabel = saved ? '已保存到系统相册' : '保存到系统相册失败';
  }

  private async toggleDownlinkLocalAudio(): Promise<void> {
    if (!this.playing) {
      return;
    }
    if (!this.localAudioStarted) {
      const context = getContext(this) as common.UIAbilityContext;
      const granted = await requestMicrophonePermission(context);
      if (!granted) {
        this.lastError = '需要允许麦克风权限后才能启动本地麦克风。';
        this.statusLabel = '权限未允许';
        this.detailLabel = this.lastError;
        return;
      }
    }
    const code = await this.downlinkSession.toggleLocalAudio({
      streamId: parseStreamId(this.audioStreamId, DEFAULT_AUDIO_STREAM_ID),
      codec: this.audioInputCodec,
      sampleRate: this.audioInputSampleRate,
      channels: this.audioInputChannels,
      aecMode: this.audioAecMode,
      agcLevel: this.audioAgcLevel,
      ansLevel: this.audioAnsLevel,
    });
    if (code !== 0) {
      this.lastError = `本地麦克风操作失败 #${code}`;
      this.statusLabel = '本地麦克风失败';
      this.detailLabel = this.lastError;
    }
  }

  private toggleDownlinkAudioOutputVolume(): void {
    const code = this.downlinkSession.toggleAudioOutputVolume();
    if (code !== 0) {
      this.lastError = `音频输出音量操作失败 #${code}`;
      this.statusLabel = '音频输出音量失败';
      this.detailLabel = this.lastError;
    }
  }

  private sendDownlinkControlMessage(commandId: number, payload: Uint8Array): number {
    return this.downlinkSession.sendControlMessage(commandId, payload);
  }

  private uploadDownlinkLogs(): void {
    this.downlinkSession.uploadLogs();
  }

  private resetPlayerEvidenceLabels(): void {
    this.metricsLabel = '';
    this.commandStatus = '';
    this.streamMessageStatus = '';
    this.logUploadStatus = '';
    this.localAudioStarted = false;
    this.audioOutputMuted = false;
    this.downlinkRenderWidth = 0;
    this.downlinkRenderHeight = 0;
  }

  private setSystemBarContentColor(color: string): void {
    const context = getContext(this) as common.UIAbilityContext;
    window.getLastWindow(context)
      .then((mainWindow: window.Window) => {
        return mainWindow.setWindowSystemBarProperties({
          statusBarContentColor: color,
          navigationBarContentColor: color,
        });
      })
      .catch((error: Error) => {
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'window_system_bar_content_color_failed message=%{public}s',
          error.message);
      });
  }

}
