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
  @Prop videoStates: Array<TiRtcVideoOutputState> = [];
  @Prop videoStreamIds: Array<number> = [];
  @Prop selectedVideoStreamId: number = -1;
  @Prop outputSurfaceWidth: number | string = '100%';
  @Prop outputSurfaceHeight: number | string = '100%';
  @Prop videoOutputCount: number = 0;
  videoOutputAt: (index: number) => TiRtcVideoOutput = (_index: number): TiRtcVideoOutput =>
    new TiRtcVideoOutput();
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
  onBack: () => void = () => {};
  onToggle: () => void = () => {};
  onLocalAudioToggle: () => void = () => {};
  onAudioOutputVolumeToggle: () => void = () => {};
  onVideoSelected: (streamId: number) => void = () => {};
  onRecordingToggle: () => void = () => {};
  onRawDumpToggle: () => void = () => {};
  onSnapshot: () => void = () => {};
  onSaveMedia: () => void = () => {};
  onSendCommand: (commandId: number, payload: Uint8Array) => number = () => 0;
  onUploadLogs: () => void = () => {};
  onStageAreaChanged: (width: number, height: number) => void = () => {};
  private focusedAction: string = PLAYER_ACTION_NONE;
  @State private commandPanelVisible: boolean = false;
  @State private maximizedVideoStreamId: number = -1;
  @State private stageWidth: number = 0;

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
      logUploadEnabled: true,
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
        if (this.videoOutputCount === 0) {
          Text(this.audioState === TiRtcAudioOutputState.playing ? '仅音频播放' : '未配置视频流')
            .fontSize(14)
            .fontColor('#CCFFFFFF')
        } else {
          this.videoMosaic()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#252525')
      .onAreaChange((oldArea: Area, newArea: Area) => {
        this.stageWidth = parseAreaDimension(newArea.width);
        this.onStageAreaChanged(this.stageWidth, parseAreaDimension(newArea.height));
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
          recording: this.recording,
          mediaAvailable: this.mediaAvailable,
          mediaEnabled: this.playing && !this.connecting && this.selectedVideoStreamId >= 0,
          onRecordingAction: this.onRecordingToggle,
          onSnapshotAction: this.onSnapshot,
          onSaveMediaAction: this.onSaveMedia,
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
      .hitTestBehavior(HitTestMode.Transparent)
      Row() {
        Column({ space: 5 }) {
          Button(this.rawDumpCapturing ? '结束上传' : (this.rawDumpUploadPending ? '重试上传' : '抓数据'))
            .id('tirtc_example_raw_dump_button')
            .accessibilityText(this.rawDumpCapturing ? '停止诊断抓取' : '开始诊断抓取')
            .width(56)
            .height(56)
            .fontSize(11)
            .fontColor('#FFFFFF')
            .backgroundColor(this.rawDumpCapturing ? '#E68A35' : '#659287')
            .borderRadius(28)
            .enabled(this.playing && !this.rawDumpBusy)
            .onClick(this.onRawDumpToggle)
          if (this.rawDumpCapturing) {
            Text('正在抓取诊断数据')
              .fontSize(10)
              .fontColor('#FFFFFF')
              .padding({ left: 6, right: 6, top: 3, bottom: 3 })
              .backgroundColor('#8F000000')
              .borderRadius(8)
          } else if (this.rawDumpUploadPending) {
            Text('诊断数据上传失败 · 点击重试上传')
              .fontSize(10)
              .fontColor('#FFFFFF')
              .padding({ left: 6, right: 6, top: 3, bottom: 3 })
              .backgroundColor('#8F000000')
              .borderRadius(8)
          }
        }
        .alignItems(HorizontalAlign.Start)
        Blank()
      }
      .width('100%')
      .padding({ left: 12 })
      if (!this.playing) {
        Stack({ alignContent: Alignment.Center }) {
          PlayerStageOverlay({
            statusLabel: this.statusLabel,
            detailLabel: this.detailLabel,
            connState: this.connState,
            audioState: this.audioState,
            videoState: this.selectedVideoState(),
          })
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.None)
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

  @Builder
  private videoMosaic() {
    if (this.maximizedVideoStreamId >= 0 && this.maximizedVideoStreamId === this.selectedVideoStreamId) {
      this.videoLane(this.videoStreamIds.indexOf(this.maximizedVideoStreamId))
    } else if (this.selectedVideoStreamId === this.videoStreamIds[1]) {
      this.videoMosaicForPrimary(1)
    } else if (this.selectedVideoStreamId === this.videoStreamIds[2]) {
      this.videoMosaicForPrimary(2)
    } else {
      this.videoMosaicForPrimary(0)
    }
  }

  @Builder
  private videoMosaicForPrimary(primaryIndex: number) {
    if (this.videoOutputCount === 1) {
      this.videoLane(0)
    } else if (this.videoOutputCount === 2) {
      if (this.stageWidth >= 600) {
        Row({ space: 4 }) {
          this.videoLane(primaryIndex)
          this.videoLane(this.otherVideoIndexes(primaryIndex)[0])
        }
        .width('100%')
        .height('100%')
      } else {
        Column({ space: 4 }) {
          this.videoLane(primaryIndex)
          this.videoLane(this.otherVideoIndexes(primaryIndex)[0])
        }
        .width('100%')
        .height('100%')
      }
    } else {
      if (this.stageWidth >= 600) {
        Row({ space: 4 }) {
          Column() { this.videoLane(primaryIndex) }.layoutWeight(2).height('100%')
          Column({ space: 4 }) {
            this.videoLane(this.otherVideoIndexes(primaryIndex)[0])
            this.videoLane(this.otherVideoIndexes(primaryIndex)[1])
          }
          .layoutWeight(1)
          .height('100%')
        }
        .width('100%')
        .height('100%')
      } else {
        Column({ space: 4 }) {
          Column() { this.videoLane(primaryIndex) }.layoutWeight(2).width('100%')
          Row({ space: 4 }) {
            this.videoLane(this.otherVideoIndexes(primaryIndex)[0])
            this.videoLane(this.otherVideoIndexes(primaryIndex)[1])
          }
          .layoutWeight(1)
          .width('100%')
        }
        .width('100%')
        .height('100%')
      }
    }
  }

  @Builder
  private videoLane(index: number) {
    Stack({ alignContent: Alignment.Center }) {
      TiRtcVideoOutputView({ output: this.videoOutputAt(index) })
      if (this.videoStates[index] !== TiRtcVideoOutputState.rendering) {
        Text(this.videoStates[index] === TiRtcVideoOutputState.failed ? '播放失败' : '等待视频')
          .fontSize(13)
          .fontColor('#FFFFFF')
      }
      Column() {
        Row() {
          if (this.selectedVideoStreamId === this.videoStreamIds[index]) {
            if (this.maximizedVideoStreamId === this.videoStreamIds[index]) {
              Button(`视频 ${index + 1} · Stream ${this.videoStreamIds[index]}`)
                .id(`tirtc_example_player_video_lane_${this.videoStreamIds[index]}_maximized`)
                .accessibilityText(`视频 ${index + 1}，Stream ${this.videoStreamIds[index]}，点击恢复宫格`)
                .height(44)
                .fontSize(11)
                .fontColor('#FFFFFF')
                .padding({ left: 12, right: 12 })
                .backgroundColor('#75000000')
                .borderRadius(8)
                .onClick((): void => {
                  this.maximizedVideoStreamId = -1;
                })
            } else {
              Button(`视频 ${index + 1} · Stream ${this.videoStreamIds[index]}`)
                .id(`tirtc_example_player_video_lane_${this.videoStreamIds[index]}_selected`)
                .accessibilityText(`视频 ${index + 1}，Stream ${this.videoStreamIds[index]}，点击最大化`)
                .height(44)
                .fontSize(11)
                .fontColor('#FFFFFF')
                .padding({ left: 12, right: 12 })
                .backgroundColor('#75000000')
                .borderRadius(8)
                .onClick((): void => {
                  this.maximizedVideoStreamId = this.videoStreamIds[index];
                })
            }
          } else {
            Button(`视频 ${index + 1} · Stream ${this.videoStreamIds[index]}`)
              .id(`tirtc_example_player_video_lane_${this.videoStreamIds[index]}`)
              .accessibilityText(`视频 ${index + 1}，Stream ${this.videoStreamIds[index]}，点击选择`)
              .height(44)
              .fontSize(11)
              .fontColor('#FFFFFF')
              .padding({ left: 12, right: 12 })
              .backgroundColor('#75000000')
              .borderRadius(8)
              .onClick((): void => {
                this.maximizedVideoStreamId = -1;
                this.onVideoSelected(this.videoStreamIds[index]);
              })
          }
          Blank()
        }
        .width('100%')
        Blank()
      }
      .width('100%')
      .height('100%')
      .padding({ left: 8, right: 8, top: 72, bottom: 8 })
    }
    .id(`tirtc_example_player_video_lane_surface_${this.videoStreamIds[index]}`)
    .layoutWeight(1)
    .width('100%')
    .height('100%')
    .border({ width: this.selectedVideoStreamId === this.videoStreamIds[index] ? 2 : 0, color: '#659287' })
  }

  private otherVideoIndexes(primary: number): Array<number> {
    const indexes: Array<number> = [];
    for (let index = 0; index < Math.min(3, this.videoOutputCount); index += 1) {
      if (index !== primary) indexes.push(index);
    }
    return indexes;
  }

  private selectedVideoState(): TiRtcVideoOutputState {
    const index = this.videoStreamIds.indexOf(this.selectedVideoStreamId);
    return index >= 0 ? this.videoStates[index] : TiRtcVideoOutputState.idle;
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
