import {
  TiRtcAudioOutputState,
  TiRtcConnState,
  TiRtcVideoOutputState,
} from 'tirtc/Index';
import {
  PLAYER_BOTTOM_PADDING,
  PLAYER_TOP_PADDING,
} from './ExampleConfig';
import { runOnActivationKey } from './ExampleKeyboard';

export const PLAYER_ACTION_NONE = '';
export const PLAYER_ACTION_BACK = 'back';
export const PLAYER_ACTION_SEND_COMMAND = 'send_command';
export const PLAYER_ACTION_UPLOAD_LOGS = 'upload_logs';
export const PLAYER_ACTION_LOCAL_AUDIO = 'local_audio';
export const PLAYER_ACTION_AUDIO_VOLUME = 'audio_volume';
export const PLAYER_ACTION_TOGGLE = 'toggle';
const COMMAND_PANEL_SAMPLE_ID_LABEL = '0xffffffff';
const COMMAND_PANEL_ECHO_ID_TEXT = '0xffffffff';
const COMMAND_PANEL_MODE_HEX = 'hex';
const COMMAND_PANEL_MODE_TEXT = 'text';

@Component
export struct PlayerTopBar {
  @Prop title: string = '';
  @Prop commandEnabled: boolean = false;
  @Prop logUploadEnabled: boolean = false;
  @Prop commandAnchor: string = 'tirtc_example_player_command_button';
  @Prop logUploadAnchor: string = 'tirtc_example_player_log_upload_button';
  onBack: () => void = () => {};
  onSendCommand: () => void = () => {};
  onUploadLogs: () => void = () => {};
  onFocusedActionChanged: (action: string) => void = () => {};

  build() {
    Row() {
      Button('<')
        .width(42)
        .height(36)
        .fontSize(18)
        .fontColor('#659287')
        .backgroundColor('#00FFFFFF')
        .onClick(() => {
          this.onBack();
        })
        .onFocus(() => {
          this.onFocusedActionChanged(PLAYER_ACTION_BACK);
        })
        .onBlur(() => {
          this.onFocusedActionChanged(PLAYER_ACTION_NONE);
        })
        .onKeyEvent((event: KeyEvent): boolean => {
          return runOnActivationKey(event, () => {
            this.onBack();
          });
        })
      Text(this.title)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor('#659287')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      Button('发送命令')
        .id(this.commandAnchor)
        .height(36)
        .fontSize(12)
        .fontColor(this.commandEnabled ? '#659287' : '#777777')
        .backgroundColor('#00FFFFFF')
        .border({ width: 1, color: this.commandEnabled ? '#659287' : '#777777', radius: 10 })
        .enabled(this.commandEnabled)
        .onClick(() => {
          this.onSendCommand();
        })
        .onFocus(() => {
          this.onFocusedActionChanged(PLAYER_ACTION_SEND_COMMAND);
        })
        .onBlur(() => {
          this.onFocusedActionChanged(PLAYER_ACTION_NONE);
        })
        .onKeyEvent((event: KeyEvent): boolean => {
          if (!this.commandEnabled) {
            return false;
          }
          return runOnActivationKey(event, () => {
            this.onSendCommand();
          });
        })
      Blank().width(8)
      Button('上传日志')
        .id(this.logUploadAnchor)
        .height(36)
        .fontSize(12)
        .fontColor(this.logUploadEnabled ? '#659287' : '#777777')
        .backgroundColor('#00FFFFFF')
        .border({ width: 1, color: this.logUploadEnabled ? '#659287' : '#777777', radius: 10 })
        .enabled(this.logUploadEnabled)
        .onClick(() => {
          this.onUploadLogs();
        })
        .onFocus(() => {
          this.onFocusedActionChanged(PLAYER_ACTION_UPLOAD_LOGS);
        })
        .onBlur(() => {
          this.onFocusedActionChanged(PLAYER_ACTION_NONE);
        })
        .onKeyEvent((event: KeyEvent): boolean => {
          if (!this.logUploadEnabled) {
            return false;
          }
          return runOnActivationKey(event, () => {
            this.onUploadLogs();
          });
        })
    }
    .width('100%')
    .padding({ left: 8, right: 16, top: PLAYER_TOP_PADDING })
  }
}

@Component
export struct PlayerMetricsOverlay {
  @Prop metricsLabel: string = '';
  @State private expanded: boolean = true;
  @State private explanationVisible: boolean = false;

  build() {
    if (!this.expanded) {
      Row() {
        Blank()
        Button('▮ 即时统计')
          .id('tirtc_example_downlink_metrics_stats_expand_action')
          .height(26)
          .fontSize(10)
          .fontWeight(FontWeight.Bold)
          .fontColor('#111111')
          .backgroundColor('#FFFFFF')
          .borderRadius(18)
          .shadow({ radius: 10, color: '#23000000', offsetX: 0, offsetY: 3 })
          .onClick(() => {
            this.expanded = true;
          })
        Blank()
      }
      .width('100%')
      .margin({ left: 18, right: 18, top: 18 })
    } else {
      Column() {
        Row() {
          Text('即时统计')
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontColor('#111111')
            .layoutWeight(1)
          Button('?')
            .width(28)
            .height(24)
            .fontSize(13)
            .fontColor('#659287')
            .backgroundColor('#00FFFFFF')
            .onClick(() => {
              this.explanationVisible = !this.explanationVisible;
            })
          Blank().width(6)
          Button('⌃ 收起')
            .id('tirtc_example_downlink_metrics_stats_collapse_action')
            .height(20)
            .fontSize(10)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
            .backgroundColor('#4F86D9')
            .borderRadius(12)
            .onClick(() => {
              this.expanded = false;
            })
        }
        .width('100%')
        Blank().height(6)
        this.metricLine('媒体参数', 'tirtc_example_downlink_metrics_media_params_text')
        this.metricLine('视频接收', 'tirtc_example_downlink_metrics_video_receive_text')
        this.metricLine('音频接收', 'tirtc_example_downlink_metrics_audio_receive_text')
        this.metricLine('估算延迟', 'tirtc_example_downlink_metrics_latency_stats_text')
        this.metricLine('启动耗时', 'tirtc_example_downlink_metrics_startup_text')
        this.metricLine('卡顿统计', 'tirtc_example_downlink_metrics_stutter_text')
        if (this.explanationVisible) {
          Blank().height(6)
          Text('连接耗时、首帧等待、卡顿统计时机、卡顿定义、接收、音频卡顿和估算延迟均来自 SDK 最近采样窗口。')
            .fontSize(10)
            .fontColor('#848282')
            .lineHeight(15)
            .maxLines(4)
            .width('100%')
        }
      }
      .id('tirtc_example_downlink_metrics_stats_panel')
      .width('100%')
      .constraintSize({ maxWidth: 430 })
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .backgroundColor('#FFFFFF')
      .border({ width: 0, radius: 20 })
      .shadow({ radius: 14, color: '#28000000', offsetX: 0, offsetY: 5 })
      .margin({ left: 18, right: 18, top: 18 })
    }
  }

  @Builder
  private metricLine(label: string, anchor: string) {
    Text(`${label}：${this.metricValue(label)}`)
      .id(anchor)
      .fontSize(10)
      .fontWeight(FontWeight.Medium)
      .fontColor('#111111')
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .width('100%')
      .padding({ bottom: 4 })
  }

  private metricValue(label: string): string {
    const prefix = `${label}：`;
    const lines = this.metricsLabel.split('\n');
    for (let index = 0; index < lines.length; index += 1) {
      const line = lines[index];
      if (line.startsWith(prefix)) {
        return line.substring(prefix.length);
      }
    }
    return '--';
  }
}

@Component
export struct StreamMessageBubble {
  @Prop status: string = '';

  build() {
    if (this.visibleText().length > 0) {
      Row() {
        Text(this.visibleText())
          .fontSize(13)
          .fontColor('#6B7280')
          .fontStyle(FontStyle.Italic)
          .maxLines(3)
      }
      .padding({ left: 16, right: 18, top: 9, bottom: 9 })
      .backgroundColor('#DEFFFFFF')
      .border({ width: 0, radius: 22 })
      .shadow({ radius: 14, color: '#1A000000', offsetX: 0, offsetY: 5 })
      .constraintSize({ maxWidth: '72%' })
      .id('tirtc_example_stream_message_bubble')
    }
  }

  private visibleText(): string {
    if (this.status.indexOf('已发送') >= 0) {
      return '流消息：已发送';
    }
    if (this.status.indexOf('收到') >= 0 || this.status.indexOf('已接收') >= 0) {
      return '流消息：已接收';
    }
    return '';
  }
}

@Component
export struct LogUploadNotice {
  @Prop status: string = '';

  build() {
    if (this.visibleText().length > 0) {
      Text(this.visibleText())
        .fontSize(13)
        .fontColor('#FFFFFF')
        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .backgroundColor('#88000000')
        .border({ width: 1, color: '#22FFFFFF', radius: 18 })
    }
  }

  private visibleText(): string {
    if (this.status.length === 0) {
      return '';
    }
    if (this.status.indexOf('已上传') >= 0) {
      return '日志上传成功';
    }
    if (this.status.indexOf('上传中') >= 0) {
      return '日志上传中';
    }
    if (this.status.indexOf('失败') >= 0 || this.status.indexOf('异常') >= 0) {
      return '日志上传失败';
    }
    return '';
  }
}

@Component
export struct CommandPanelSheet {
  @Prop title: string = '';
  @Prop connected: boolean = false;
  @Prop commandStatus: string = '';
  onClose: () => void = () => {};
  onSendCommand: (commandId: number, payload: Uint8Array) => number = () => 0;
  @State private commandIdText: string = COMMAND_PANEL_ECHO_ID_TEXT;
  @State private payloadMode: string = COMMAND_PANEL_MODE_TEXT;
  @State private payloadText: string = 'echo';
  @State private eventLines: string[] = [];

  build() {
    Column() {
      Row() {
        Text(this.title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor('#454545')
          .layoutWeight(1)
        Button('×')
          .id('tirtc_example_command_panel_close_button')
          .height(34)
          .fontSize(18)
          .fontColor('#659287')
          .backgroundColor('#00FFFFFF')
          .onClick(() => {
            this.onClose();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 12, top: 10, bottom: 8 })
      Divider().color('#E5DDCE')
      Scroll() {
        Column() {
          Row() {
            Text(this.connected ? '已连接' : '未连接')
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.connected ? '#659287' : '#848282')
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .backgroundColor(this.connected ? '#26659287' : '#22FFFFFF')
              .border({ width: 1, color: this.connected ? '#99659287' : '#E1DBCF', radius: 16 })
            Blank()
          }
          .width('100%')
          Blank().height(10)
          this.inputLabel('命令 ID')
          TextInput({ placeholder: '0xffffffff', text: this.commandIdText })
            .id('tirtc_example_command_panel_command_id_field')
            .height(42)
            .fontSize(13)
            .fontColor('#666666')
            .backgroundColor('#FFFFFF')
            .border({ width: 1, color: '#E1DBCF', radius: 18 })
            .padding({ left: 14, right: 14 })
            .onChange((value: string) => {
              this.commandIdText = value;
            })
          Blank().height(10)
          Row() {
            this.payloadModeButton('HEX', COMMAND_PANEL_MODE_HEX)
            Blank().width(8)
            this.payloadModeButton('文本', COMMAND_PANEL_MODE_TEXT)
          }
          .width('100%')
          Blank().height(8)
          this.inputLabel('命令内容')
          TextArea({ placeholder: this.payloadMode === COMMAND_PANEL_MODE_HEX ? '65 63 68 6f' : 'echo', text: this.payloadText })
            .id('tirtc_example_command_panel_payload_field')
            .height(62)
            .fontSize(13)
            .fontColor('#666666')
            .backgroundColor('#FFFFFF')
            .border({ width: 1, color: '#E1DBCF', radius: 18 })
            .padding({ left: 14, right: 14, top: 8, bottom: 8 })
            .onChange((value: string) => {
              this.payloadText = value;
            })
          Blank().height(10)
          Row() {
            Text('常用命令')
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .fontColor('#767676')
            Blank().width(10)
            Button('Echo')
              .id('tirtc_example_command_panel_echo_preset')
              .height(30)
              .fontSize(12)
              .fontColor('#659287')
              .backgroundColor('#FFFFFF')
              .border({ width: 1, color: '#659287', radius: 16 })
              .onClick(() => {
                this.commandIdText = COMMAND_PANEL_ECHO_ID_TEXT;
                this.payloadMode = COMMAND_PANEL_MODE_TEXT;
                this.payloadText = 'echo';
              })
          }
          .width('100%')
          Blank().height(10)
          ForEach(this.eventLines, (line: string) => {
            Text(line)
              .fontSize(11)
              .fontColor('#848282')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .padding({ bottom: 5 })
          }, (line: string) => line)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 8 })
      }
      .width('100%')
      .layoutWeight(1)
      Blank().height(8)
      Text(this.visibleCommandStatus())
        .id('tirtc_example_command_panel_status_text')
        .fontSize(12)
        .fontColor('#767676')
        .width('100%')
        .padding({ left: 16, right: 16 })
      Blank().height(8)
      Button('发送')
        .id('tirtc_example_command_panel_send_button')
        .width('100%')
        .height(46)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFFFFF')
        .backgroundColor(this.connected ? '#659287' : '#A1A1A1')
        .borderRadius(23)
        .enabled(this.connected)
        .margin({ left: 16, right: 16 })
        .onClick(() => {
          this.sendCurrentCommand();
        })
      Blank().height(14)
    }
    .id('tirtc_example_command_panel_sheet')
    .width('100%')
    .height('50%')
    .backgroundColor('#FFF8E8')
    .border({ width: 0, radius: 16 })
    .shadow({ radius: 18, color: '#24000000', offsetX: 0, offsetY: -3 })
  }

  private visibleCommandStatus(): string {
    if (this.commandStatus.indexOf('echo_received') >= 0) {
      return `已收到 ${COMMAND_PANEL_SAMPLE_ID_LABEL}`;
    }
    if (this.commandStatus.indexOf('发送中') >= 0) {
      return '发送中';
    }
    if (this.commandStatus.indexOf('mismatch_received') >= 0) {
      return '已收到';
    }
    return '暂无命令记录';
  }

  @Builder
  private inputLabel(label: string) {
    Text(label)
      .fontSize(12)
      .fontWeight(FontWeight.Bold)
      .fontColor('#767676')
      .width('100%')
      .padding({ left: 4, bottom: 5 })
  }

  @Builder
  private payloadModeButton(label: string, value: string) {
    Button(label)
      .layoutWeight(1)
      .height(34)
      .fontSize(12)
      .fontWeight(FontWeight.Bold)
      .fontColor(this.payloadMode === value ? '#FFFFFF' : '#659287')
      .backgroundColor(this.payloadMode === value ? '#659287' : '#00FFFFFF')
      .border({ width: 1, color: '#659287', radius: 17 })
      .onClick(() => {
        this.payloadMode = value;
      })
  }

  private sendCurrentCommand(): void {
    const commandId = this.parseCommandId(this.commandIdText);
    const payload = this.payloadMode === COMMAND_PANEL_MODE_HEX ?
      this.parseHexPayload(this.payloadText) :
      this.textPayload(this.payloadText);
    if (commandId < 0 || payload === undefined) {
      this.addEvent('发送失败：命令 ID 或 payload 无效');
      return;
    }
    const code = this.onSendCommand(commandId, payload);
    this.addEvent(`sent ${this.formatCommandId(commandId)} code=${code} payload=${this.payloadHex(payload)}`);
  }

  private addEvent(line: string): void {
    const next: string[] = [`${Date.now()} ${line}`];
    for (let index = 0; index < this.eventLines.length && index < 19; index += 1) {
      next.push(this.eventLines[index]);
    }
    this.eventLines = next;
  }

  private parseCommandId(value: string): number {
    const text = value.trim();
    if (text.length === 0) {
      return -1;
    }
    if (text.startsWith('0x') || text.startsWith('0X')) {
      if (!/^0[xX][0-9a-fA-F]+$/.test(text)) {
        return -1;
      }
    } else if (!/^[0-9]+$/.test(text)) {
      return -1;
    }
    const parsed = text.startsWith('0x') || text.startsWith('0X') ?
      Number.parseInt(text.substring(2), 16) :
      Number.parseInt(text, 10);
    if (!Number.isFinite(parsed) || parsed < 0 || parsed > 0xffffffff) {
      return -1;
    }
    return Math.floor(parsed);
  }

  private parseHexPayload(value: string): Uint8Array | undefined {
    const normalized = value.replace(/\s|,/g, '');
    if (normalized.length % 2 !== 0) {
      return undefined;
    }
    const bytes = new Uint8Array(normalized.length / 2);
    for (let index = 0; index < normalized.length; index += 2) {
      const byte = Number.parseInt(normalized.substring(index, index + 2), 16);
      if (!Number.isFinite(byte)) {
        return undefined;
      }
      bytes[index / 2] = byte;
    }
    return bytes;
  }

  private textPayload(value: string): Uint8Array {
    const bytes = new Uint8Array(value.length);
    for (let index = 0; index < value.length; index += 1) {
      bytes[index] = value.charCodeAt(index) & 0xFF;
    }
    return bytes;
  }

  private formatCommandId(commandId: number): string {
    return `0x${commandId.toString(16).padStart(8, '0')}`;
  }

  private payloadHex(payload: Uint8Array): string {
    let result = '';
    for (let index = 0; index < payload.byteLength; index += 1) {
      result += payload[index].toString(16).padStart(2, '0');
    }
    return result;
  }
}

@Component
export struct PlayerStageOverlay {
  @Prop statusLabel: string = '';
  @Prop detailLabel: string = '';
  @Prop connState: TiRtcConnState = TiRtcConnState.idle;
  @Prop audioState: TiRtcAudioOutputState = TiRtcAudioOutputState.idle;
  @Prop videoState: TiRtcVideoOutputState = TiRtcVideoOutputState.idle;

  build() {
    Column() {
      Text(this.statusLabel)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFFFFF')
      Blank().height(8)
      Text(this.detailLabel)
        .fontSize(12)
        .fontColor('#D8D8D8')
        .textAlign(TextAlign.Center)
        .maxLines(4)
    }
    .width('78%')
    .padding({ left: 18, right: 18, top: 18, bottom: 18 })
    .backgroundColor('#77000000')
    .border({ width: 1, color: '#22FFFFFF', radius: 24 })
    .alignSelf(ItemAlign.Center)
  }
}

@Component
export struct PlayerBottomButton {
  @Prop label: string = '';
  @Prop danger: boolean = false;
  @Prop actionEnabled: boolean = true;
  @Prop localAudioStarted: boolean = false;
  @Prop localAudioEnabled: boolean = true;
  @Prop audioOutputMuted: boolean = false;
  @Prop audioOutputVolumeEnabled: boolean = true;
  @Prop recording: boolean = false;
  @Prop mediaEnabled: boolean = false;
  @Prop mediaAvailable: boolean = false;
  onRecordingAction: () => void = () => {};
  onSnapshotAction: () => void = () => {};
  onSaveMediaAction: () => void = () => {};
  onAction: () => void = () => {};
  onLocalAudioAction: () => void = () => {};
  onAudioOutputVolumeAction: () => void = () => {};
  onFocusedActionChanged: (action: string) => void = () => {};

  build() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Blank()
        Button(this.recording ? '◉' : '●')
          .id('tirtc_example_player_recording_button')
          .width(48).height(48).fontSize(18).fontColor('#659287')
          .backgroundColor('#D9E5E2').borderRadius(24).enabled(this.mediaEnabled)
          .onClick(this.onRecordingAction)
        Button('▣')
          .id('tirtc_example_player_snapshot_button')
          .width(48).height(48).fontSize(18).fontColor('#659287')
          .backgroundColor('#D9E5E2').borderRadius(24).enabled(this.mediaEnabled)
          .onClick(this.onSnapshotAction)
        Button('▧')
          .id('tirtc_example_player_gallery_button')
          .accessibilityText('保存到系统相册')
          .width(48).height(48).fontSize(18).fontColor('#659287')
          .backgroundColor('#D9E5E2').borderRadius(24).enabled(this.mediaAvailable)
          .onClick(this.onSaveMediaAction)
      }
      .width('100%')
      Row() {
      Blank()
      Button(this.audioOutputMuted ? '恢复声音' : '静音')
        .id('tirtc_example_player_audio_volume_button')
        .height(50)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.audioOutputMuted ? '#FFFFFF' : '#659287')
        .backgroundColor(this.audioOutputMuted ? '#F59E0B' : '#FFFFFF')
        .borderRadius(25)
        .enabled(this.audioOutputVolumeEnabled)
        .onClick(() => {
          this.onAudioOutputVolumeAction();
        })
        .onFocus(() => {
          this.onFocusedActionChanged(PLAYER_ACTION_AUDIO_VOLUME);
        })
        .onBlur(() => {
          this.onFocusedActionChanged(PLAYER_ACTION_NONE);
        })
        .onKeyEvent((event: KeyEvent): boolean => {
          if (!this.audioOutputVolumeEnabled) {
            return false;
          }
          return runOnActivationKey(event, () => {
            this.onAudioOutputVolumeAction();
          });
        })
      Blank().width(10)
      Button(this.localAudioStarted ? '停止麦克风' : '启动麦克风')
        .id('tirtc_example_player_local_audio_button')
        .height(50)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.localAudioStarted ? '#FFFFFF' : '#659287')
        .backgroundColor(this.localAudioStarted ? '#F59E0B' : '#FFFFFF')
        .borderRadius(25)
        .enabled(this.localAudioEnabled)
        .onClick(() => {
          this.onLocalAudioAction();
        })
        .onFocus(() => {
          this.onFocusedActionChanged(PLAYER_ACTION_LOCAL_AUDIO);
        })
        .onBlur(() => {
          this.onFocusedActionChanged(PLAYER_ACTION_NONE);
        })
        .onKeyEvent((event: KeyEvent): boolean => {
          if (!this.localAudioEnabled) {
            return false;
          }
          return runOnActivationKey(event, () => {
            this.onLocalAudioAction();
          });
        })
      Blank().width(10)
      Button(this.label)
        .height(56)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFFFFF')
        .backgroundColor(this.danger ? '#F87171' : '#659287')
        .borderRadius(28)
        .enabled(this.actionEnabled)
        .onClick(() => {
          this.onAction();
        })
        .onFocus(() => {
          this.onFocusedActionChanged(PLAYER_ACTION_TOGGLE);
        })
        .onBlur(() => {
          this.onFocusedActionChanged(PLAYER_ACTION_NONE);
        })
        .defaultFocus(true)
        .onKeyEvent((event: KeyEvent): boolean => {
          if (!this.actionEnabled) {
            return false;
          }
          return runOnActivationKey(event, () => {
            this.onAction();
          });
        })
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 20, right: 20, bottom: PLAYER_BOTTOM_PADDING })
  }
}
