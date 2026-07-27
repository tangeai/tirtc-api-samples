import {
  CONFIGURE_BOTTOM_PADDING,
  CONFIGURE_TOP_PADDING,
  LOG_DOMAIN,
  LOG_TAG,
} from './ExampleConfig';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { runOnActivationKey } from './ExampleKeyboard';
import { DemoTokenSource } from './ExampleTokenAcquisition';

@Component
export struct ClientConfigurePage {
  @Prop endpoint: string = '';
  @Prop appId: string = '';
  @Prop remoteId: string = '';
  @Prop token: string = '';
  @Prop tokenIssuerBaseUrl: string = '';
  @Prop tokenSource: DemoTokenSource = DemoTokenSource.issuer;
  @Prop audioStreamId: string = '';
  @Prop videoStreamId: string = '';
  @Prop connecting: boolean = false;
  @Prop lastError: string = '';
  onOpenSettings: () => void = () => {};
  onEndpointChanged: (value: string) => void = () => {};
  onAppIdChanged: (value: string) => void = () => {};
  onRemoteIdChanged: (value: string) => void = () => {};
  onTokenChanged: (value: string) => void = () => {};
  onTokenIssuerBaseUrlChanged: (value: string) => void = () => {};
  onTokenSourceChanged: (value: DemoTokenSource) => void = () => {};
  onOpenQrScanner: () => void = () => {};
  onAudioStreamIdChanged: (value: string) => void = () => {};
  onVideoStreamIdChanged: (value: string) => void = () => {};
  onStartDownlink: () => void = () => {};

  build() {
    Scroll() {
      Column() {
        Row() {
          Text('Ti RTC')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor('#767676')
          Blank()
          Button('偏好设置')
            .type(ButtonType.Normal)
            .fontSize(13)
            .fontColor('#659287')
            .backgroundColor('#00FFFFFF')
            .border({ width: 1, color: '#B3659287', radius: 20 })
            .onClick(() => {
              hilog.info(LOG_DOMAIN, LOG_TAG, 'TIRTC_configure_settings_button_clicked');
              this.onOpenSettings();
            })
            .onKeyEvent((event: KeyEvent): boolean => {
              return runOnActivationKey(event, () => {
                this.onOpenSettings();
              });
            })
        }
        .width('100%')
        .height(42)
        Blank().height(20)
        Row() {
          this.rowInputField('app_id', 'TiRTC 应用标识', this.appId, this.onAppIdChanged,
            'tirtc_example_app_id_field')
          Blank().width(16)
          this.rowInputField('endpoint', '留空则使用默认环境', this.endpoint, this.onEndpointChanged,
            'tirtc_example_endpoint_field')
        }
        .width('100%')
        Blank().height(16)
        this.inputField('remote_id', '待连接的远端目标 ID', this.remoteId, this.onRemoteIdChanged,
          'tirtc_example_remote_id_field')
        Blank().height(16)
        Row() {
          this.streamField('audio_stream_id', '默认 10', this.audioStreamId, this.onAudioStreamIdChanged,
            'tirtc_example_audio_stream_id_field')
          Blank().width(16)
          this.streamField('video_stream_id', '默认 11', this.videoStreamId, this.onVideoStreamIdChanged,
            'tirtc_example_video_stream_id_field')
        }
        .width('100%')
        Blank().height(16)
        this.tokenSection()
        Blank().height(20)
        Button(this.connecting ? '初始化中' : '进入播放页面')
          .id('tirtc_example_start_downlink_button')
          .width('100%')
          .height(56)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .backgroundColor('#659287')
          .borderRadius(28)
          .enabled(!this.connecting)
          .onClick(() => {
            hilog.info(LOG_DOMAIN, LOG_TAG, 'TIRTC_configure_open_player_button_clicked');
            this.onStartDownlink();
          })
          .onKeyEvent((event: KeyEvent): boolean => {
            return runOnActivationKey(event, () => {
              this.onStartDownlink();
            });
          })
        this.errorLabel()
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: CONFIGURE_TOP_PADDING, bottom: CONFIGURE_BOTTOM_PADDING })
    }
    .width('100%')
    .height('100%')
    .id('tirtc_example_configure_page')
    .backgroundColor('#FFF8E8')
    .linearGradient({
      angle: 180,
      colors: [['#FFF8E8', 0.0], ['#FBF4E5', 0.5], ['#FFF8E8', 1.0]]
    })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  private inputField(
    label: string,
    hint: string,
    value: string,
    onChanged: (value: string) => void,
    anchor: string,
  ) {
    Column() {
      this.inputFieldContent(label, hint, value, onChanged, anchor)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private rowInputField(
    label: string,
    hint: string,
    value: string,
    onChanged: (value: string) => void,
    anchor: string,
  ) {
    Column() {
      this.inputFieldContent(label, hint, value, onChanged, anchor)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private inputFieldContent(
    label: string,
    hint: string,
    value: string,
    onChanged: (value: string) => void,
    anchor: string,
  ) {
    this.inputLabel(label)
    TextInput({ placeholder: hint, text: value })
      .id(anchor)
      .height(58)
      .fontSize(13)
      .fontColor('#666666')
      .placeholderColor('#848282')
      .backgroundColor('#FFFFFF')
      .border({ width: 0, radius: 20 })
      .padding({ left: 20, right: 20 })
      .onChange(onChanged)
  }

  @Builder
  private streamField(
    label: string,
    hint: string,
    value: string,
    onChanged: (value: string) => void,
    anchor: string,
  ) {
    Column() {
      this.inputLabel(label)
      TextInput({ placeholder: hint, text: value })
        .id(anchor)
        .height(58)
        .fontSize(13)
        .fontColor('#666666')
        .placeholderColor('#848282')
        .backgroundColor('#FFFFFF')
        .border({ width: 0, radius: 20 })
        .padding({ left: 16, right: 16 })
        .onChange(onChanged)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private tokenSection() {
    Column() {
      Text('连接 Token')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#767676')
        .width('100%')
      Blank().height(14)
      Row() {
        this.tokenSourceChip('Token 签发服务地址', DemoTokenSource.issuer,
          'tirtc_example_token_source_issuer_button')
        Blank().width(8)
        this.tokenSourceChip('一次性连接 Token', DemoTokenSource.oneTime,
          'tirtc_example_token_source_one_time_button')
      }
      .width('100%')
      Blank().height(16)
      if (this.tokenSource === DemoTokenSource.issuer) {
        Column() {
          this.inputLabel('Token 签发服务地址')
          TextInput({
            placeholder: '例如 http://127.0.0.1:8966 或 http://openapidemo.tange365.com/tirtc/token/Ue4rIG',
            text: this.tokenIssuerBaseUrl,
          })
            .id('tirtc_example_token_issuer_base_url_field')
            .height(58)
            .fontSize(13)
            .fontColor('#666666')
            .placeholderColor('#848282')
            .backgroundColor('#FFFFFF')
            .border({ width: 0, radius: 20 })
            .padding({ left: 20, right: 20 })
            .onChange(this.onTokenIssuerBaseUrlChanged)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      } else {
        Column() {
          this.inputLabel('一次性连接 Token')
          Row() {
            TextInput({ placeholder: '粘贴 TiRTC DevTools CLI 生成的一次性 Token', text: this.token })
              .id('tirtc_example_token_field')
              .height(58)
              .fontSize(13)
              .fontColor('#666666')
              .placeholderColor('#848282')
              .backgroundColor('#FFFFFF')
              .border({ width: 0, radius: 20 })
              .padding({ left: 20, right: 12 })
              .layoutWeight(1)
              .onChange(this.onTokenChanged)
              .onSubmit(() => {
                this.onStartDownlink();
              })
            Blank().width(10)
            Button('扫码')
              .id('tirtc_example_token_scan_button')
              .width(68)
              .height(48)
              .fontSize(13)
              .fontColor('#659287')
              .backgroundColor('#00FFFFFF')
              .border({ width: 1, color: '#659287', radius: 24 })
              .onClick(() => {
                this.onOpenQrScanner();
              })
              .onKeyEvent((event: KeyEvent): boolean => {
                return runOnActivationKey(event, () => {
                  this.onOpenQrScanner();
                });
              })
          }
          .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 18, bottom: 18 })
    .backgroundColor('#FFFFFF')
    .border({ width: 0, radius: 18 })
  }

  @Builder
  private tokenSourceChip(label: string, value: DemoTokenSource, anchor: string) {
    Button(label)
      .id(anchor)
      .height(36)
      .fontSize(12)
      .fontWeight(FontWeight.Bold)
      .fontColor(this.tokenSource === value ? '#659287' : '#848282')
      .backgroundColor(this.tokenSource === value ? '#26659287' : '#FFFFFF')
      .border({ width: 1, color: this.tokenSource === value ? '#99659287' : '#E1DBCF', radius: 18 })
      .enabled(!this.connecting)
      .onClick(() => {
        this.onTokenSourceChanged(value);
      })
      .onKeyEvent((event: KeyEvent): boolean => {
        if (this.connecting) {
          return false;
        }
        return runOnActivationKey(event, () => {
          this.onTokenSourceChanged(value);
        });
      })
  }

  @Builder
  private inputLabel(label: string) {
    Text(label)
      .fontSize(14)
      .fontWeight(FontWeight.Medium)
      .fontColor('#848282')
      .height(22)
      .padding({ left: 20, bottom: 4 })
  }

  @Builder
  private errorLabel() {
    if (this.lastError.length > 0) {
      Blank().height(12)
      Text(this.lastError)
        .fontSize(13)
        .fontColor('#B42318')
    }
  }
}
