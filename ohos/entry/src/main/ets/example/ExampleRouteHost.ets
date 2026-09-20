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
import { TiCloudStorageExamplePage } from './TiCloudStorageExamplePage';
import { DemoTokenSource } from './ExampleTokenAcquisition';

@Component
export struct ExampleRouteHost {
  @Prop view: ExampleView = ExampleView.configure;
  @Prop endpoint: string = '';
  @Prop appId: string = '';
  @Prop remoteId: string = '';
  @Prop token: string = '';
  @Prop cloudStorageAppId: string = '';
  @Prop cloudStorageEndpoint: string = '';
  @Prop cloudStorageToken: string = '';
  @Prop cloudStorageAudioChannelId: string = '';
  @Prop cloudStorageVideoChannelIds: Array<string> = ['11'];
  @Prop tokenIssuerBaseUrl: string = '';
  @Prop tokenSource: DemoTokenSource = DemoTokenSource.issuer;
  @Prop qrPayloadText: string = '';
  @Prop qrErrorText: string = '';
  @Prop qrForCloudStorage: boolean = false;
  @Prop audioStreamId: string = '';
  @Prop videoStreamIds: Array<string> = ['11'];
  @Prop configureProductIndex: number = 0;
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
  @Prop videoStates: Array<TiRtcVideoOutputState> = [TiRtcVideoOutputState.idle];
  @Prop selectedVideoStreamId: number = 11;
  @Prop localAudioStarted: boolean = false;
  @Prop audioOutputMuted: boolean = false;
  @Prop recording: boolean = false;
  @Prop rawDumpCapturing: boolean = false;
  @Prop rawDumpBusy: boolean = false;
  @Prop rawDumpUploadPending: boolean = false;
  @Prop mediaAvailable: boolean = false;
  @Prop metricsLabel: string = '';
  @Prop commandStatus: string = '';
  @Prop streamMessageStatus: string = '';
  @Prop logUploadStatus: string = '';
  @Prop downlinkRenderWidth: number = 0;
  @Prop downlinkRenderHeight: number = 0;
  @Prop videoOutputCount: number = 0;
  videoOutputAt: (index: number) => TiRtcVideoOutput = (_index: number): TiRtcVideoOutput =>
    new TiRtcVideoOutput();
  onOpenSettings: () => void = () => {};
  onConfigureProductIndexChanged: (value: number) => void = () => {};
  onEndpointChanged: (value: string) => void = () => {};
  onAppIdChanged: (value: string) => void = () => {};
  onRemoteIdChanged: (value: string) => void = () => {};
  onTokenChanged: (value: string) => void = () => {};
  onCloudStorageAppIdChanged: (value: string) => void = () => {};
  onCloudStorageEndpointChanged: (value: string) => void = () => {};
  onCloudStorageTokenChanged: (value: string) => void = () => {};
  onCloudStorageAudioChannelIdChanged: (value: string) => void = () => {};
  onCloudStorageVideoChannelIdChanged: (index: number, value: string) => void = () => {};
  onAddCloudStorageVideoChannelId: () => void = () => {};
  onRemoveCloudStorageVideoChannelId: (index: number) => void = () => {};
  onTokenIssuerBaseUrlChanged: (value: string) => void = () => {};
  onTokenSourceChanged: (value: DemoTokenSource) => void = () => {};
  onOpenQrScanner: () => void = () => {};
  onOpenCloudStorageQrScanner: () => void = () => {};
  onQrScannerBack: () => void = () => {};
  onQrPayloadChanged: (value: string) => void = () => {};
  onApplyQrPayload: () => void = () => {};
  onAudioStreamIdChanged: (value: string) => void = () => {};
  onVideoStreamIdChanged: (index: number, value: string) => void = () => {};
  onAddVideoStreamId: () => void = () => {};
  onRemoveVideoStreamId: (index: number) => void = () => {};
  onOpenPlayer: () => void = () => {};
  onOpenCloudStorage: () => void = () => {};
  onCloudStorageBack: () => void = () => {};
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
  onPlayerVideoSelected: (streamId: number) => void = () => {};
  onPlayerRecordingToggle: () => void = () => {};
  onPlayerRawDumpToggle: () => void = () => {};
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
      } else if (this.view === ExampleView.cloudStorage) {
        this.cloudStoragePage()
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
      cloudStorageAppId: this.cloudStorageAppId,
      cloudStorageEndpoint: this.cloudStorageEndpoint,
      cloudStorageToken: this.cloudStorageToken,
      cloudStorageAudioChannelId: this.cloudStorageAudioChannelId,
      cloudStorageVideoChannelIds: this.cloudStorageVideoChannelIds,
      tokenIssuerBaseUrl: this.tokenIssuerBaseUrl,
      tokenSource: this.tokenSource,
      audioStreamId: this.audioStreamId,
      videoStreamIds: this.videoStreamIds,
      productIndex: this.configureProductIndex,
      connecting: this.connecting,
      lastError: this.lastError,
      onOpenSettings: this.onOpenSettings,
      onProductIndexChanged: this.onConfigureProductIndexChanged,
      onEndpointChanged: this.onEndpointChanged,
      onAppIdChanged: this.onAppIdChanged,
      onRemoteIdChanged: this.onRemoteIdChanged,
      onTokenChanged: this.onTokenChanged,
      onCloudStorageAppIdChanged: this.onCloudStorageAppIdChanged,
      onCloudStorageEndpointChanged: this.onCloudStorageEndpointChanged,
      onCloudStorageTokenChanged: this.onCloudStorageTokenChanged,
      onCloudStorageAudioChannelIdChanged: this.onCloudStorageAudioChannelIdChanged,
      onCloudStorageVideoChannelIdChanged: this.onCloudStorageVideoChannelIdChanged,
      onAddCloudStorageVideoChannelId: this.onAddCloudStorageVideoChannelId,
      onRemoveCloudStorageVideoChannelId: this.onRemoveCloudStorageVideoChannelId,
      onTokenIssuerBaseUrlChanged: this.onTokenIssuerBaseUrlChanged,
      onTokenSourceChanged: this.onTokenSourceChanged,
      onOpenQrScanner: this.onOpenQrScanner,
      onOpenCloudStorageQrScanner: this.onOpenCloudStorageQrScanner,
      onAudioStreamIdChanged: this.onAudioStreamIdChanged,
      onVideoStreamIdChanged: this.onVideoStreamIdChanged,
      onAddVideoStreamId: this.onAddVideoStreamId,
      onRemoveVideoStreamId: this.onRemoveVideoStreamId,
      onStartDownlink: this.onOpenPlayer,
      onOpenCloudStorage: this.onOpenCloudStorage,
    })
  }

  @Builder
  private cloudStoragePage() {
    TiCloudStorageExamplePage({
      appId: this.cloudStorageAppId,
      endpoint: this.cloudStorageEndpoint,
      token: this.cloudStorageToken,
      audioChannelId: this.cloudStorageAudioChannelId.trim().length === 0 ? null :
        parseStreamId(this.cloudStorageAudioChannelId, 10),
      videoChannelIds: this.cloudStorageVideoChannelIds.map((value: string): number => parseStreamId(value, 11)),
      consoleLogEnabled: this.consoleLogEnabled,
      onBack: this.onCloudStorageBack,
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
      cloudStorageMode: this.qrForCloudStorage,
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
      videoStates: this.videoStates,
      videoStreamIds: this.videoStreamIds.map((value: string): number => parseStreamId(value, 11)),
      selectedVideoStreamId: this.selectedVideoStreamId,
      outputSurfaceWidth: this.downlinkOutputSurfaceWidth(),
      outputSurfaceHeight: this.downlinkOutputSurfaceHeight(),
      videoOutputCount: this.videoOutputCount,
      videoOutputAt: this.videoOutputAt,
      localAudioStarted: this.localAudioStarted,
      audioOutputMuted: this.audioOutputMuted,
      recording: this.recording,
      rawDumpCapturing: this.rawDumpCapturing,
      rawDumpBusy: this.rawDumpBusy,
      rawDumpUploadPending: this.rawDumpUploadPending,
      mediaAvailable: this.mediaAvailable,
      metricsLabel: this.metricsLabel,
      commandStatus: this.commandStatus,
      streamMessageStatus: this.streamMessageStatus,
      logUploadStatus: this.logUploadStatus,
      onBack: this.onPlayerBack,
      onToggle: this.onPlayerToggle,
      onLocalAudioToggle: this.onPlayerLocalAudioToggle,
      onAudioOutputVolumeToggle: this.onPlayerAudioOutputVolumeToggle,
      onVideoSelected: this.onPlayerVideoSelected,
      onRecordingToggle: this.onPlayerRecordingToggle,
      onRawDumpToggle: this.onPlayerRawDumpToggle,
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
