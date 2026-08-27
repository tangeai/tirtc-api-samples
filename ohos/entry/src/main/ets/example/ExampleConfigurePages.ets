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
  @Prop cloudStorageAppId: string = '';
  @Prop cloudStorageEndpoint: string = '';
  @Prop cloudStorageToken: string = '';
  @Prop cloudStorageAudioChannelId: string = '';
  @Prop cloudStorageVideoChannelId: string = '';
  @Prop tokenIssuerBaseUrl: string = '';
  @Prop tokenSource: DemoTokenSource = DemoTokenSource.issuer;
  @Prop audioStreamId: string = '';
  @Prop videoStreamId: string = '';
  @Prop connecting: boolean = false;
  @Prop lastError: string = '';
  @State private productIndex: number = 0;
  onOpenSettings: () => void = () => {};
  onEndpointChanged: (value: string) => void = () => {};
  onAppIdChanged: (value: string) => void = () => {};
  onRemoteIdChanged: (value: string) => void = () => {};
  onTokenChanged: (value: string) => void = () => {};
  onCloudStorageAppIdChanged: (value: string) => void = () => {};
  onCloudStorageEndpointChanged: (value: string) => void = () => {};
  onCloudStorageTokenChanged: (value: string) => void = () => {};
  onCloudStorageAudioChannelIdChanged: (value: string) => void = () => {};
  onCloudStorageVideoChannelIdChanged: (value: string) => void = () => {};
  onTokenIssuerBaseUrlChanged: (value: string) => void = () => {};
  onTokenSourceChanged: (value: DemoTokenSource) => void = () => {};
  onOpenQrScanner: () => void = () => {};
  onOpenCloudStorageQrScanner: () => void = () => {};
  onAudioStreamIdChanged: (value: string) => void = () => {};
  onVideoStreamIdChanged: (value: string) => void = () => {};
  onStartDownlink: () => void = () => {};
  onOpenCloudStorage: () => void = () => {};

  build() {
    Scroll() {
      Column() {
        Row() {
          Column() {
            Text('Ti RTC')
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor('#767676')
            Text('Based on OpenHarmony')
              .fontSize(12)
              .fontColor('#B3B3B3')
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          Blank()
          Button('偏好设置')
            .id('tirtc_example_settings_button')
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
        this.productTabs()
        Blank().height(20)
        if (this.productIndex === 0) {
          this.rtcConfiguration()
        } else {
          this.cloudStorageConfiguration()
        }
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
  private productTabs() {
    Row() {
      this.productTab('RTC', 0, 'tirtc_example_rtc_product_tab')
      Blank().width(3)
      this.productTab('云录像', 1, 'tirtc_example_ti_cloud_storage_product_tab')
    }
    .width('100%')
    .height(44)
    .padding(3)
    .backgroundColor('#1A659287')
    .borderRadius(22)
  }

  @Builder
  private productTab(label: string, index: number, anchor: string) {
    Button(label)
      .id(anchor)
      .layoutWeight(1)
      .height(38)
      .fontSize(14)
      .fontWeight(FontWeight.Bold)
      .fontColor(this.productIndex === index ? '#FFFFFF' : '#659287')
      .backgroundColor(this.productIndex === index ? '#659287' : '#00FFFFFF')
      .borderRadius(20)
      .enabled(!this.connecting)
      .onClick((): void => {
        this.productIndex = index;
      })
  }

  @Builder
  private rtcConfiguration() {
    this.inputField('endpoint', '留空则使用默认环境', this.endpoint, this.onEndpointChanged,
      'tirtc_example_endpoint_field')
    Blank().height(16)
    this.inputField('app_id', 'TiRTC 应用标识', this.appId, this.onAppIdChanged,
      'tirtc_example_app_id_field')
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
    Button(this.connecting ? '初始化中' : '开始连接、拉流播放')
      .id('tirtc_example_start_downlink_button')
      .width('100%')
      .height(56)
      .fontSize(16)
      .fontWeight(FontWeight.Medium)
      .fontColor('#FFFFFF')
      .backgroundColor('#659287')
      .borderRadius(28)
      .enabled(!this.connecting)
      .onClick((): void => {
        hilog.info(LOG_DOMAIN, LOG_TAG, 'TIRTC_configure_open_player_button_clicked');
        this.onStartDownlink();
      })
  }

  @Builder
  private cloudStorageConfiguration() {
    this.inputField('app_id', 'Ti Cloud Storage 应用标识', this.cloudStorageAppId, this.onCloudStorageAppIdChanged,
      'tirtc_example_ti_cloud_storage_app_id_field')
    Blank().height(16)
    this.inputField('endpoint', '留空则使用默认环境', this.cloudStorageEndpoint,
      this.onCloudStorageEndpointChanged, 'tirtc_example_ti_cloud_storage_endpoint_field')
    Blank().height(16)
    Row() {
      Column() {
        this.inputFieldContent('token', '粘贴 Ti Cloud Storage APP Token', this.cloudStorageToken,
          this.onCloudStorageTokenChanged, 'tirtc_example_ti_cloud_storage_token_field', true)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Blank().width(10)
      Button('扫码')
        .id('tirtc_example_ti_cloud_storage_token_scan_button')
        .width(68)
        .height(56)
        .fontSize(13)
        .fontColor('#659287')
        .backgroundColor('#FFFFFF')
        .border({ width: 1, color: '#659287', radius: 20 })
        .onClick(this.onOpenCloudStorageQrScanner)
    }
    .width('100%')
    Blank().height(16)
    Row() {
      this.streamField('audio_channel_id', '默认 10', this.cloudStorageAudioChannelId,
        this.onCloudStorageAudioChannelIdChanged, 'tirtc_example_ti_cloud_storage_audio_channel_field')
      Blank().width(16)
      this.streamField('video_channel_id', '默认 11', this.cloudStorageVideoChannelId,
        this.onCloudStorageVideoChannelIdChanged, 'tirtc_example_ti_cloud_storage_video_channel_field')
    }
    .width('100%')
    Blank().height(20)
    Button('播放云录像')
      .id('tirtc_example_open_ti_cloud_storage_button')
      .width('100%')
      .height(56)
      .fontSize(16)
      .fontWeight(FontWeight.Medium)
      .fontColor('#FFFFFF')
      .backgroundColor('#659287')
      .borderRadius(28)
      .enabled(!this.connecting)
      .onClick(this.onOpenCloudStorage)
  }

  @Builder
  private inputField(
    label: string,
    hint: string,
    value: string,
    onChanged: (value: string) => void,
    anchor: string,
    secure: boolean = false,
  ) {
    Column() {
      this.inputFieldContent(label, hint, value, onChanged, anchor, secure)
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
    secure: boolean = false,
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
    secure: boolean = false,
  ) {
    this.inputLabel(label)
    TextInput({ placeholder: hint, text: value })
      .id(anchor)
      .type(secure ? InputType.Password : InputType.Normal)
      .height(56)
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
        .height(56)
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
      Row() {
        Column() {
          this.inputFieldContent('一次性连接 Token', '粘贴 v1.xxx 一次性 Token', this.token,
            this.onTokenChanged, 'tirtc_example_token_field')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Blank().width(10)
        Button('扫码')
          .id('tirtc_example_token_scan_button')
          .width(68)
          .height(56)
          .fontSize(13)
          .fontColor('#659287')
          .backgroundColor('#FFFFFF')
          .border({ width: 1, color: '#659287', radius: 20 })
          .onClick(this.onOpenQrScanner)
      }
      .width('100%')
      Text('或')
        .width('100%')
        .fontSize(12)
        .fontColor('#B3B3B3')
        .textAlign(TextAlign.Center)
        .margin({ top: 8, bottom: 8 })
      this.inputFieldContent('TiRTC DevTools 服务地址', '例如 http://192.168.1.10:8966',
        this.tokenIssuerBaseUrl, this.onTokenIssuerBaseUrlChanged,
        'tirtc_example_token_issuer_base_url_field')
    }
    .width('100%')
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
