import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  TiRtcAudioAecMode,
  TiRtcAudioAgcLevel,
  TiRtcAudioAnsLevel,
  TiRtcAudioChannelCount,
  TiRtcAudioCodec,
  TiRtcAudioSampleRate,
  TiRtcAudioOutputState,
  TiRtcConnState,
  TiRtcOutputBufferStrategy,
  TiRtcVideoDecoderPreference,
  TiRtcVideoOutput,
  TiRtcVideoOutputState,
} from 'tirtc/Index';
import {
  DEFAULT_DOWNLINK_VIDEO_HEIGHT,
  DEFAULT_DOWNLINK_VIDEO_WIDTH,
  ExampleView,
  LOG_DOMAIN,
  LOG_TAG,
  parseStreamId,
  VideoFitSize,
} from './ExampleConfig';
import { ClientConfigurePage } from './ExampleConfigurePages';
import { QrScannerPage } from './ExampleQrScannerPage';
import { SettingsPage } from './ExampleSettingsPage';
import { DownlinkPlayerPage } from './ExamplePlayerPages';
import { TiStoreExamplePage } from './TiStoreExamplePage';
import { DemoTokenSource } from './ExampleTokenAcquisition';

@Component
export struct ExampleRouteHost {
  @Prop view: ExampleView = ExampleView.configure;
  @Prop endpoint: string = '';
  @Prop appId: string = '';
  @Prop remoteId: string = '';
  @Prop token: string = '';
  @Prop storeAppId: string = '';
  @Prop storeEndpoint: string = '';
  @Prop storeToken: string = '';
  @Prop storeAudioChannelId: string = '';
  @Prop storeVideoChannelId: string = '';
  @Prop tokenIssuerBaseUrl: string = '';
  @Prop tokenSource: DemoTokenSource = DemoTokenSource.issuer;
  @Prop qrPayloadText: string = '';
  @Prop qrErrorText: string = '';
  @Prop qrForStore: boolean = false;
  @Prop audioStreamId: string = '';
  @Prop videoStreamId: string = '';
  @Prop videoDecoderPreference: TiRtcVideoDecoderPreference = TiRtcVideoDecoderPreference.auto;
  @Prop outputBufferStrategy: TiRtcOutputBufferStrategy = TiRtcOutputBufferStrategy.automatic;
  @Prop audioInputCodec: TiRtcAudioCodec = TiRtcAudioCodec.g711a;
  @Prop audioInputSampleRate: TiRtcAudioSampleRate = TiRtcAudioSampleRate.rate16k;
  @Prop audioInputChannels: TiRtcAudioChannelCount = TiRtcAudioChannelCount.mono;
  @Prop audioAecMode: TiRtcAudioAecMode = TiRtcAudioAecMode.disabled;
  @Prop audioAgcLevel: TiRtcAudioAgcLevel = TiRtcAudioAgcLevel.disabled;
  @Prop audioAnsLevel: TiRtcAudioAnsLevel = TiRtcAudioAnsLevel.disabled;
  @Prop consoleLogEnabled: boolean = false;
  @Prop statusLabel: string = '';
  @Prop detailLabel: string = '';
  @Prop connecting: boolean = false;
  @Prop playing: boolean = false;
  @Prop lastError: string = '';
  @Prop connState: TiRtcConnState = TiRtcConnState.idle;
  @Prop audioState: TiRtcAudioOutputState = TiRtcAudioOutputState.idle;
  @Prop videoState: TiRtcVideoOutputState = TiRtcVideoOutputState.idle;
  @Prop localAudioStarted: boolean = false;
  @Prop audioOutputMuted: boolean = false;
  @Prop recording: boolean = false;
  @Prop mediaAvailable: boolean = false;
  @Prop metricsLabel: string = '';
  @Prop commandStatus: string = '';
  @Prop streamMessageStatus: string = '';
  @Prop logUploadStatus: string = '';
  @Prop downlinkRenderWidth: number = 0;
  @Prop downlinkRenderHeight: number = 0;
  videoOutput: TiRtcVideoOutput = new TiRtcVideoOutput();
  onOpenSettings: () => void = () => {};
  onEndpointChanged: (value: string) => void = () => {};
  onAppIdChanged: (value: string) => void = () => {};
  onRemoteIdChanged: (value: string) => void = () => {};
  onTokenChanged: (value: string) => void = () => {};
  onStoreAppIdChanged: (value: string) => void = () => {};
  onStoreEndpointChanged: (value: string) => void = () => {};
  onStoreTokenChanged: (value: string) => void = () => {};
  onStoreAudioChannelIdChanged: (value: string) => void = () => {};
  onStoreVideoChannelIdChanged: (value: string) => void = () => {};
  onTokenIssuerBaseUrlChanged: (value: string) => void = () => {};
  onTokenSourceChanged: (value: DemoTokenSource) => void = () => {};
  onOpenQrScanner: () => void = () => {};
  onOpenStoreQrScanner: () => void = () => {};
  onQrScannerBack: () => void = () => {};
  onQrPayloadChanged: (value: string) => void = () => {};
  onApplyQrPayload: () => void = () => {};
  onAudioStreamIdChanged: (value: string) => void = () => {};
  onVideoStreamIdChanged: (value: string) => void = () => {};
  onOpenPlayer: () => void = () => {};
  onOpenStore: () => void = () => {};
  onStoreBack: () => void = () => {};
  onSettingsBack: () => void = () => {};
  onDecoderPreferenceChanged: (value: TiRtcVideoDecoderPreference) => void = () => {};
  onOutputBufferStrategyChanged: (value: TiRtcOutputBufferStrategy) => void = () => {};
  onAudioInputCodecChanged: (value: TiRtcAudioCodec) => void = () => {};
  onAudioInputSampleRateChanged: (value: TiRtcAudioSampleRate) => void = () => {};
  onAudioAecModeChanged: (value: TiRtcAudioAecMode) => void = () => {};
  onAudioAgcLevelChanged: (value: TiRtcAudioAgcLevel) => void = () => {};
  onAudioAnsLevelChanged: (value: TiRtcAudioAnsLevel) => void = () => {};
  onConsoleLogEnabledChanged: (value: boolean) => void = () => {};
  onPlayerBack: () => void = () => {};
  onPlayerToggle: () => void = () => {};
  onPlayerLocalAudioToggle: () => void = () => {};
  onPlayerAudioOutputVolumeToggle: () => void = () => {};
  onPlayerRecordingToggle: () => void = () => {};
  onPlayerSnapshot: () => void = () => {};
  onPlayerSaveMedia: () => void = () => {};
  onSendDownlinkCommand: (commandId: number, payload: Uint8Array) => number = () => 0;
  onUploadDownlinkLogs: () => void = () => {};
  @State private videoStageWidth: number = 0;
  @State private videoStageHeight: number = 0;

  build() {
    Stack() {
      if (this.view === ExampleView.configure) {
        this.configurePage()
      } else if (this.view === ExampleView.settings) {
        this.settingsPage()
      } else if (this.view === ExampleView.qrScanner) {
        this.qrScannerPage()
      } else if (this.view === ExampleView.store) {
        this.storePage()
      } else {
        this.playerPage()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFF8E8')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  private configurePage() {
    ClientConfigurePage({
      endpoint: this.endpoint,
      appId: this.appId,
      remoteId: this.remoteId,
      token: this.token,
      storeAppId: this.storeAppId,
      storeEndpoint: this.storeEndpoint,
      storeToken: this.storeToken,
      storeAudioChannelId: this.storeAudioChannelId,
      storeVideoChannelId: this.storeVideoChannelId,
      tokenIssuerBaseUrl: this.tokenIssuerBaseUrl,
      tokenSource: this.tokenSource,
      audioStreamId: this.audioStreamId,
      videoStreamId: this.videoStreamId,
      connecting: this.connecting,
      lastError: this.lastError,
      onOpenSettings: this.onOpenSettings,
      onEndpointChanged: this.onEndpointChanged,
      onAppIdChanged: this.onAppIdChanged,
      onRemoteIdChanged: this.onRemoteIdChanged,
      onTokenChanged: this.onTokenChanged,
      onStoreAppIdChanged: this.onStoreAppIdChanged,
      onStoreEndpointChanged: this.onStoreEndpointChanged,
      onStoreTokenChanged: this.onStoreTokenChanged,
      onStoreAudioChannelIdChanged: this.onStoreAudioChannelIdChanged,
      onStoreVideoChannelIdChanged: this.onStoreVideoChannelIdChanged,
      onTokenIssuerBaseUrlChanged: this.onTokenIssuerBaseUrlChanged,
      onTokenSourceChanged: this.onTokenSourceChanged,
      onOpenQrScanner: this.onOpenQrScanner,
      onOpenStoreQrScanner: this.onOpenStoreQrScanner,
      onAudioStreamIdChanged: this.onAudioStreamIdChanged,
      onVideoStreamIdChanged: this.onVideoStreamIdChanged,
      onStartDownlink: this.onOpenPlayer,
      onOpenStore: this.onOpenStore,
    })
  }

  @Builder
  private storePage() {
    TiStoreExamplePage({
      appId: this.storeAppId,
      endpoint: this.storeEndpoint,
      token: this.storeToken,
      audioChannelId: parseStreamId(this.storeAudioChannelId, 10),
      videoChannelId: parseStreamId(this.storeVideoChannelId, 11),
      consoleLogEnabled: this.consoleLogEnabled,
      onBack: this.onStoreBack,
    })
  }

  @Builder
  private settingsPage() {
    SettingsPage({
      videoDecoderPreference: this.videoDecoderPreference,
      outputBufferStrategy: this.outputBufferStrategy,
      audioInputCodec: this.audioInputCodec,
      audioInputSampleRate: this.audioInputSampleRate,
      audioInputChannels: this.audioInputChannels,
      audioAecMode: this.audioAecMode,
      audioAgcLevel: this.audioAgcLevel,
      audioAnsLevel: this.audioAnsLevel,
      audioStreamId: this.audioStreamId,
      consoleLogEnabled: this.consoleLogEnabled,
      onBack: this.onSettingsBack,
      onDecoderPreferenceChanged: this.onDecoderPreferenceChanged,
      onOutputBufferStrategyChanged: this.onOutputBufferStrategyChanged,
      onAudioInputCodecChanged: this.onAudioInputCodecChanged,
      onAudioInputSampleRateChanged: this.onAudioInputSampleRateChanged,
      onAudioAecModeChanged: this.onAudioAecModeChanged,
      onAudioAgcLevelChanged: this.onAudioAgcLevelChanged,
      onAudioAnsLevelChanged: this.onAudioAnsLevelChanged,
      onAudioStreamIdChanged: this.onAudioStreamIdChanged,
      onConsoleLogEnabledChanged: this.onConsoleLogEnabledChanged,
    })
  }

  @Builder
  private qrScannerPage() {
    QrScannerPage({
      storeMode: this.qrForStore,
      payloadText: this.qrPayloadText,
      errorText: this.qrErrorText,
      onBack: this.onQrScannerBack,
      onPayloadChanged: this.onQrPayloadChanged,
      onApplyPayload: this.onApplyQrPayload,
    })
  }

  @Builder
  private playerPage() {
    DownlinkPlayerPage({
      remoteId: this.remoteId,
      statusLabel: this.statusLabel,
      detailLabel: this.detailLabel,
      connecting: this.connecting,
      playing: this.playing,
      connState: this.connState,
      audioState: this.audioState,
      videoState: this.videoState,
      outputSurfaceWidth: this.downlinkOutputSurfaceWidth(),
      outputSurfaceHeight: this.downlinkOutputSurfaceHeight(),
      videoOutput: this.videoOutput,
      localAudioStarted: this.localAudioStarted,
      audioOutputMuted: this.audioOutputMuted,
      recording: this.recording,
      mediaAvailable: this.mediaAvailable,
      metricsLabel: this.metricsLabel,
      commandStatus: this.commandStatus,
      streamMessageStatus: this.streamMessageStatus,
      logUploadStatus: this.logUploadStatus,
      onBack: this.onPlayerBack,
      onToggle: this.onPlayerToggle,
      onLocalAudioToggle: this.onPlayerLocalAudioToggle,
      onAudioOutputVolumeToggle: this.onPlayerAudioOutputVolumeToggle,
      onRecordingToggle: this.onPlayerRecordingToggle,
      onSnapshot: this.onPlayerSnapshot,
      onSaveMedia: this.onPlayerSaveMedia,
      onSendCommand: this.onSendDownlinkCommand,
      onUploadLogs: this.onUploadDownlinkLogs,
      onStageAreaChanged: (width: number, height: number): void => {
        this.updateVideoStageSize(width, height);
      },
    })
  }

  private updateVideoStageSize(width: number, height: number): void {
    if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) {
      return;
    }
    if (Math.abs(this.videoStageWidth - width) < 0.5 && Math.abs(this.videoStageHeight - height) < 0.5) {
      return;
    }
    this.videoStageWidth = width;
    this.videoStageHeight = height;
    hilog.info(LOG_DOMAIN, LOG_TAG, 'TIRTC_video_stage_size width=%{public}d height=%{public}d',
      Math.round(width), Math.round(height));
  }

  private downlinkOutputSurfaceWidth(): number | string {
    const fit = this.fitDownlinkOutputSurface();
    return fit.width > 0 ? fit.width : '100%';
  }

  private downlinkOutputSurfaceHeight(): number | string {
    const fit = this.fitDownlinkOutputSurface();
    return fit.height > 0 ? fit.height : '100%';
  }

  private fitDownlinkOutputSurface(): VideoFitSize {
    if (this.videoStageWidth <= 0 || this.videoStageHeight <= 0) {
      return { width: 0, height: 0 };
    }
    const sourceWidth = this.downlinkRenderWidth > 0 ? this.downlinkRenderWidth : DEFAULT_DOWNLINK_VIDEO_WIDTH;
    const sourceHeight = this.downlinkRenderHeight > 0 ? this.downlinkRenderHeight : DEFAULT_DOWNLINK_VIDEO_HEIGHT;
    const scale = Math.min(this.videoStageWidth / sourceWidth, this.videoStageHeight / sourceHeight);
    const visualWidth = Math.round(sourceWidth * scale);
    const visualHeight = Math.round(sourceHeight * scale);
    return {
      width: visualWidth,
      height: visualHeight,
    };
  }

}
