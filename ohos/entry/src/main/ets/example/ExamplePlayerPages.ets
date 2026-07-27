import {
  TiRtcAudioOutputState,
  TiRtcConnState,
  TiRtcVideoOutput,
  TiRtcVideoOutputView,
  TiRtcVideoOutputState,
} from 'tirtc/Index';
import { isActivationKey } from './ExampleKeyboard';
import {
  PLAYER_ACTION_BACK,
  PLAYER_ACTION_AUDIO_VOLUME,
  PLAYER_ACTION_LOCAL_AUDIO,
  PLAYER_ACTION_NONE,
  PLAYER_ACTION_SEND_COMMAND,
  PLAYER_ACTION_TOGGLE,
  PLAYER_ACTION_UPLOAD_LOGS,
  CommandPanelSheet,
  LogUploadNotice,
  PlayerBottomButton,
  PlayerMetricsOverlay,
  PlayerStageOverlay,
  PlayerTopBar,
  StreamMessageBubble,
} from './ExamplePlayerChrome';

function parseAreaDimension(value: Length): number {
  if (typeof value === 'number') {
    return value;
  }
  if (typeof value !== 'string') {
    return 0;
  }
  return Number.parseFloat(value);
}

@Component
export struct DownlinkPlayerPage {
  @Prop remoteId: string = '';
  @Prop statusLabel: string = '';
  @Prop detailLabel: string = '';
  @Prop connecting: boolean = false;
  @Prop playing: boolean = false;
  @Prop connState: TiRtcConnState = TiRtcConnState.idle;
  @Prop audioState: TiRtcAudioOutputState = TiRtcAudioOutputState.idle;
  @Prop videoState: TiRtcVideoOutputState = TiRtcVideoOutputState.idle;
  @Prop outputSurfaceWidth: number | string = '100%';
  @Prop outputSurfaceHeight: number | string = '100%';
  videoOutput: TiRtcVideoOutput = new TiRtcVideoOutput();
  @Prop localAudioStarted: boolean = false;
  @Prop audioOutputMuted: boolean = false;
  @Prop metricsLabel: string = '';
  @Prop commandStatus: string = '';
  @Prop streamMessageStatus: string = '';
  @Prop logUploadStatus: string = '';
  onBack: () => void = () => {};
  onToggle: () => void = () => {};
  onLocalAudioToggle: () => void = () => {};
  onAudioOutputVolumeToggle: () => void = () => {};
  onSendCommand: (commandId: number, payload: Uint8Array) => number = () => 0;
  onUploadLogs: () => void = () => {};
  onStageAreaChanged: (width: number, height: number) => void = () => {};
  private focusedAction: string = PLAYER_ACTION_NONE;
  @State private commandPanelVisible: boolean = false;

  build() {
    Column() {
      this.topBar()
      this.videoStage()
    }
    .id('tirtc_example_player_page')
    .width('100%')
    .height('100%')
    .backgroundColor('#FFF8E8')
    .onKeyEvent((event: KeyEvent): boolean => {
      return this.activateFocusedAction(event);
    })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  @Builder
  private topBar() {
    PlayerTopBar({
      title: this.remoteId,
      commandAnchor: 'tirtc_example_player_command_button',
      logUploadAnchor: 'tirtc_example_player_log_upload_button',
      onBack: this.onBack,
      commandEnabled: this.playing,
      logUploadEnabled: this.playing,
      onSendCommand: () => {
        this.commandPanelVisible = true;
      },
      onUploadLogs: this.onUploadLogs,
      onFocusedActionChanged: (action: string) => {
        this.focusedAction = action;
      },
    })
      .backgroundColor('#FFF8E8')
  }

  @Builder
  private videoStage() {
    Stack() {
      Stack({ alignContent: Alignment.Center }) {
        TiRtcVideoOutputView({
          output: this.videoOutput,
          width: this.outputSurfaceWidth,
          height: this.outputSurfaceHeight,
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#252525')
      .onAreaChange((oldArea: Area, newArea: Area) => {
        this.onStageAreaChanged(parseAreaDimension(newArea.width), parseAreaDimension(newArea.height));
      })
      Column() {
        if (this.playing) {
          PlayerMetricsOverlay({ metricsLabel: this.metricsLabel })
        }
        Blank()
        Row() {
          Blank()
          LogUploadNotice({ status: this.logUploadStatus })
        }
        .width('100%')
        .padding({ left: 20, right: 20, bottom: 10 })
        Row() {
          Blank()
          StreamMessageBubble({ status: this.streamMessageStatus })
        }
        .width('100%')
        .padding({ left: 20, right: 20, bottom: 12 })
        PlayerBottomButton({
          label: this.playing ? '停止播放' : (this.connecting ? '连接中' : '开始播放'),
          danger: this.playing,
          actionEnabled: !this.connecting,
          localAudioStarted: this.localAudioStarted,
          localAudioEnabled: this.playing && !this.connecting,
          audioOutputMuted: this.audioOutputMuted,
          audioOutputVolumeEnabled: this.playing && !this.connecting,
          onAction: this.onToggle,
          onLocalAudioAction: this.onLocalAudioToggle,
          onAudioOutputVolumeAction: this.onAudioOutputVolumeToggle,
          onFocusedActionChanged: (action: string) => {
            this.focusedAction = action;
          },
        })
      }
      .width('100%')
      .height('100%')
      .linearGradient({
        angle: 180,
        colors: [['#33000000', 0.0], ['#00000000', 0.45], ['#66000000', 1.0]]
      })
      if (!this.playing) {
        Stack({ alignContent: Alignment.Center }) {
          PlayerStageOverlay({
            statusLabel: this.statusLabel,
            detailLabel: this.detailLabel,
            connState: this.connState,
            audioState: this.audioState,
            videoState: this.videoState,
          })
        }
        .width('100%')
        .height('100%')
      }
      if (this.commandPanelVisible) {
        Column() {
          Blank()
          CommandPanelSheet({
            title: '发送命令',
            connected: this.playing,
            commandStatus: this.commandStatus,
            onClose: () => {
              this.commandPanelVisible = false;
            },
            onSendCommand: this.onSendCommand,
          })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#00000000')
      }
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor('#252525')
  }

  private activateFocusedAction(event: KeyEvent): boolean {
    if (!isActivationKey(event)) {
      return false;
    }
    if (this.focusedAction === PLAYER_ACTION_BACK) {
      this.onBack();
      return true;
    }
    if (this.playing && this.focusedAction === PLAYER_ACTION_SEND_COMMAND) {
      this.commandPanelVisible = true;
      return true;
    }
    if (this.playing && this.focusedAction === PLAYER_ACTION_UPLOAD_LOGS) {
      this.onUploadLogs();
      return true;
    }
    if (this.playing && this.focusedAction === PLAYER_ACTION_LOCAL_AUDIO) {
      this.onLocalAudioToggle();
      return true;
    }
    if (this.playing && this.focusedAction === PLAYER_ACTION_AUDIO_VOLUME) {
      this.onAudioOutputVolumeToggle();
      return true;
    }
    if (!this.connecting && this.focusedAction === PLAYER_ACTION_TOGGLE) {
      this.onToggle();
      return true;
    }
    return false;
  }
}
