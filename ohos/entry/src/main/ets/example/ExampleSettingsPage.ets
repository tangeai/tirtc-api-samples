import {
  TiRtcAudioAecMode,
  TiRtcAudioAgcLevel,
  TiRtcAudioAnsLevel,
  TiRtcAudioChannelCount,
  TiRtcAudioCodec,
  TiRtcAudioSampleRate,
  TiRtcOutputBufferStrategy,
  TiRtcVideoDecoderPreference,
} from 'tirtc/Index';
import {
  audioAecModeLabel,
  audioCodecLabel,
  audioLevelLabel,
  audioSampleRateLabel,
  CONFIGURE_BOTTOM_PADDING,
  outputBufferStrategyLabel,
  SETTINGS_TOP_PADDING,
  videoDecoderPreferenceLabel,
} from './ExampleConfig';
import { runOnActivationKey } from './ExampleKeyboard';

@Component
export struct SettingsPage {
  @Prop videoDecoderPreference: TiRtcVideoDecoderPreference = TiRtcVideoDecoderPreference.auto;
  @Prop outputBufferStrategy: TiRtcOutputBufferStrategy = TiRtcOutputBufferStrategy.automatic;
  @Prop audioInputCodec: TiRtcAudioCodec = TiRtcAudioCodec.g711a;
  @Prop audioInputSampleRate: TiRtcAudioSampleRate = TiRtcAudioSampleRate.rate16k;
  @Prop audioInputChannels: TiRtcAudioChannelCount = TiRtcAudioChannelCount.mono;
  @Prop audioAecMode: TiRtcAudioAecMode = TiRtcAudioAecMode.disabled;
  @Prop audioAgcLevel: TiRtcAudioAgcLevel = TiRtcAudioAgcLevel.disabled;
  @Prop audioAnsLevel: TiRtcAudioAnsLevel = TiRtcAudioAnsLevel.disabled;
  @Prop audioStreamId: string = '';
  @Prop consoleLogEnabled: boolean = false;
  onBack: () => void = () => {};
  onDecoderPreferenceChanged: (value: TiRtcVideoDecoderPreference) => void = () => {};
  onOutputBufferStrategyChanged: (value: TiRtcOutputBufferStrategy) => void = () => {};
  onAudioInputCodecChanged: (value: TiRtcAudioCodec) => void = () => {};
  onAudioInputSampleRateChanged: (value: TiRtcAudioSampleRate) => void = () => {};
  onAudioAecModeChanged: (value: TiRtcAudioAecMode) => void = () => {};
  onAudioAgcLevelChanged: (value: TiRtcAudioAgcLevel) => void = () => {};
  onAudioAnsLevelChanged: (value: TiRtcAudioAnsLevel) => void = () => {};
  onAudioStreamIdChanged: (value: string) => void = () => {};
  onConsoleLogEnabledChanged: (value: boolean) => void = () => {};

  build() {
    Scroll() {
      Column() {
        Row() {
          Button('<')
            .id('tirtc_example_settings_back_button')
            .width(42)
            .height(36)
            .fontSize(18)
            .fontColor('#659287')
            .backgroundColor('#00FFFFFF')
            .onClick(() => {
              this.onBack();
            })
            .onKeyEvent((event: KeyEvent): boolean => {
              return runOnActivationKey(event, () => {
                this.onBack();
              });
            })
          Text('设置')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor('#767676')
            .layoutWeight(1)
        }
        .width('100%')
        .height(42)
        Blank().height(20)
        this.sectionTitle('客户端')
        this.clientSection()
        Blank().height(20)
        this.sectionTitle('本地音频采集与传输')
        this.localAudioSection()
        Blank().height(20)
        this.sectionTitle('通用')
        this.consoleSection()
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: SETTINGS_TOP_PADDING, bottom: CONFIGURE_BOTTOM_PADDING })
    }
    .width('100%')
    .height('100%')
    .id('tirtc_example_settings_page')
    .backgroundColor('#FFF8E8')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  private sectionTitle(label: string) {
    Text(label)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor('#767676')
      .width('100%')
      .padding({ left: 4, bottom: 10 })
  }

  @Builder
  private clientSection() {
    Column() {
      this.preferenceRow('视频解码偏好', videoDecoderPreferenceLabel(this.videoDecoderPreference))
      Blank().height(12)
      Row() {
        this.decoderPreferenceButton('自动', TiRtcVideoDecoderPreference.auto)
        Blank().width(10)
        this.decoderPreferenceButton('硬解', TiRtcVideoDecoderPreference.hardware)
        Blank().width(10)
        this.decoderPreferenceButton('软解', TiRtcVideoDecoderPreference.software)
      }
      .width('100%')
      Blank().height(18)
      this.preferenceRow('输出缓冲策略', outputBufferStrategyLabel(this.outputBufferStrategy))
      Blank().height(12)
      Row() {
        this.outputBufferButton('自动', TiRtcOutputBufferStrategy.automatic)
        Blank().width(10)
        this.outputBufferButton('不缓冲', TiRtcOutputBufferStrategy.noBuffer)
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 18, bottom: 18 })
    .backgroundColor('#FFFFFF')
    .border({ width: 0, radius: 20 })
  }

  @Builder
  private localAudioSection() {
    Column() {
      this.preferenceRow('编码格式', audioCodecLabel(this.audioInputCodec))
      Blank().height(12)
      Row() {
        this.audioCodecButton('G711A', TiRtcAudioCodec.g711a)
        Blank().width(10)
        this.audioCodecButton('AAC', TiRtcAudioCodec.aac)
        Blank().width(10)
        this.audioCodecButton('PCM', TiRtcAudioCodec.pcm)
        Blank().width(10)
        this.audioCodecButton('OPUS', TiRtcAudioCodec.opus)
        Blank().width(10)
        this.audioCodecButton('AMR', TiRtcAudioCodec.amr)
      }
      .width('100%')
      Blank().height(18)
      this.preferenceRow('采样率', audioSampleRateLabel(this.audioInputSampleRate))
      Blank().height(12)
      Row() {
        this.audioSampleRateButton('8 kHz', TiRtcAudioSampleRate.rate8k)
        Blank().width(10)
        this.audioSampleRateButton('16 kHz', TiRtcAudioSampleRate.rate16k)
      }
      .width('100%')
      Blank().height(18)
      this.preferenceRow('传输 Stream ID', this.audioStreamId)
      Blank().height(10)
      TextInput({ placeholder: '10', text: this.audioStreamId })
        .height(50)
        .fontSize(13)
        .fontColor('#666666')
        .placeholderColor('#848282')
        .backgroundColor('#FFFFFF')
        .border({ width: 1, color: '#E1DBCF', radius: 18 })
        .padding({ left: 16, right: 16 })
        .onChange(this.onAudioStreamIdChanged)
      Blank().height(18)
      Row() {
        Column() {
          Text('AEC')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor('#454545')
          Text(audioAecModeLabel(this.audioAecMode))
            .fontSize(12)
            .fontColor('#767676')
        }
        .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.audioAecMode === TiRtcAudioAecMode.enabled })
          .selectedColor('#659287')
          .onChange((enabled: boolean) => {
            this.onAudioAecModeChanged(enabled ? TiRtcAudioAecMode.enabled : TiRtcAudioAecMode.disabled);
          })
      }
      .width('100%')
      Blank().height(18)
      this.preferenceRow('AGC', audioLevelLabel(this.audioAgcLevel))
      Blank().height(12)
      Row() {
        this.audioAgcButton('关闭', TiRtcAudioAgcLevel.disabled)
        Blank().width(8)
        this.audioAgcButton('低', TiRtcAudioAgcLevel.low)
        Blank().width(8)
        this.audioAgcButton('中', TiRtcAudioAgcLevel.medium)
        Blank().width(8)
        this.audioAgcButton('高', TiRtcAudioAgcLevel.high)
      }
      .width('100%')
      Blank().height(18)
      this.preferenceRow('ANS', audioLevelLabel(this.audioAnsLevel))
      Blank().height(12)
      Row() {
        this.audioAnsButton('关闭', TiRtcAudioAnsLevel.disabled)
        Blank().width(8)
        this.audioAnsButton('低', TiRtcAudioAnsLevel.low)
        Blank().width(8)
        this.audioAnsButton('中', TiRtcAudioAnsLevel.medium)
        Blank().width(8)
        this.audioAnsButton('高', TiRtcAudioAnsLevel.high)
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 18, bottom: 18 })
    .backgroundColor('#FFFFFF')
    .border({ width: 0, radius: 18 })
  }

  @Builder
  private consoleSection() {
    Row() {
      Column() {
        Text('启用控制台输出')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#454545')
          .width('100%')
        Blank().height(4)
        Text(this.consoleLogEnabled ? '已启用' : '已关闭')
          .fontSize(12)
          .fontColor('#767676')
          .width('100%')
      }
      .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.consoleLogEnabled })
        .id('tirtc_example_console_log_toggle')
        .selectedColor('#659287')
        .onChange((enabled: boolean) => {
          this.onConsoleLogEnabledChanged(enabled);
        })
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 16, bottom: 16 })
    .backgroundColor('#FFFFFF')
    .border({ width: 0, radius: 20 })
  }

  @Builder
  private preferenceRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor('#454545')
        .layoutWeight(1)
      Text(value)
        .fontSize(13)
        .fontColor('#767676')
    }
    .width('100%')
  }

  @Builder
  private audioCodecButton(label: string, value: TiRtcAudioCodec) {
    Button(label)
      .layoutWeight(1)
      .height(40)
      .fontSize(13)
      .fontColor(this.audioInputCodec === value ? '#FFFFFF' : '#659287')
      .backgroundColor(this.audioInputCodec === value ? '#659287' : '#00FFFFFF')
      .border({ width: 1, color: '#659287', radius: 20 })
      .onClick(() => {
        this.onAudioInputCodecChanged(value);
      })
      .onKeyEvent((event: KeyEvent): boolean => {
        return runOnActivationKey(event, () => {
          this.onAudioInputCodecChanged(value);
        });
      })
  }

  @Builder
  private audioSampleRateButton(label: string, value: TiRtcAudioSampleRate) {
    Button(label)
      .layoutWeight(1)
      .height(40)
      .fontSize(13)
      .fontColor(this.audioInputSampleRate === value ? '#FFFFFF' : '#659287')
      .backgroundColor(this.audioInputSampleRate === value ? '#659287' : '#00FFFFFF')
      .border({ width: 1, color: '#659287', radius: 20 })
      .onClick(() => {
        this.onAudioInputSampleRateChanged(value);
      })
      .onKeyEvent((event: KeyEvent): boolean => {
        return runOnActivationKey(event, () => {
          this.onAudioInputSampleRateChanged(value);
        });
      })
  }

  @Builder
  private audioAgcButton(label: string, value: TiRtcAudioAgcLevel) {
    Button(label)
      .layoutWeight(1)
      .height(36)
      .fontSize(12)
      .fontColor(this.audioAgcLevel === value ? '#FFFFFF' : '#659287')
      .backgroundColor(this.audioAgcLevel === value ? '#659287' : '#00FFFFFF')
      .border({ width: 1, color: '#659287', radius: 18 })
      .onClick(() => {
        this.onAudioAgcLevelChanged(value);
      })
      .onKeyEvent((event: KeyEvent): boolean => {
        return runOnActivationKey(event, () => {
          this.onAudioAgcLevelChanged(value);
        });
      })
  }

  @Builder
  private audioAnsButton(label: string, value: TiRtcAudioAnsLevel) {
    Button(label)
      .layoutWeight(1)
      .height(36)
      .fontSize(12)
      .fontColor(this.audioAnsLevel === value ? '#FFFFFF' : '#659287')
      .backgroundColor(this.audioAnsLevel === value ? '#659287' : '#00FFFFFF')
      .border({ width: 1, color: '#659287', radius: 18 })
      .onClick(() => {
        this.onAudioAnsLevelChanged(value);
      })
      .onKeyEvent((event: KeyEvent): boolean => {
        return runOnActivationKey(event, () => {
          this.onAudioAnsLevelChanged(value);
        });
      })
  }

  @Builder
  private decoderPreferenceButton(label: string, value: TiRtcVideoDecoderPreference) {
    Button(label)
      .layoutWeight(1)
      .height(40)
      .fontSize(13)
      .fontColor(this.videoDecoderPreference === value ? '#FFFFFF' : '#659287')
      .backgroundColor(this.videoDecoderPreference === value ? '#659287' : '#00FFFFFF')
      .border({ width: 1, color: '#659287', radius: 20 })
      .onClick(() => {
        this.onDecoderPreferenceChanged(value);
      })
      .onKeyEvent((event: KeyEvent): boolean => {
        return runOnActivationKey(event, () => {
          this.onDecoderPreferenceChanged(value);
        });
      })
  }

  @Builder
  private outputBufferButton(label: string, value: TiRtcOutputBufferStrategy) {
    Button(label)
      .layoutWeight(1)
      .height(40)
      .fontSize(13)
      .fontColor(this.outputBufferStrategy === value ? '#FFFFFF' : '#659287')
      .backgroundColor(this.outputBufferStrategy === value ? '#659287' : '#00FFFFFF')
      .border({ width: 1, color: '#659287', radius: 20 })
      .onClick(() => {
        this.onOutputBufferStrategyChanged(value);
      })
      .onKeyEvent((event: KeyEvent): boolean => {
        return runOnActivationKey(event, () => {
          this.onOutputBufferStrategyChanged(value);
        });
      })
  }

}
