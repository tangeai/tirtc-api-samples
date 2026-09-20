import {
  CONFIGURE_BOTTOM_PADDING,
  CONFIGURE_TOP_PADDING,
  LOG_DOMAIN,
  LOG_TAG,
} from './ExampleConfig';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { runOnActivationKey } from './ExampleKeyboard';
import { DemoTokenSource } from './ExampleTokenAcquisition';

const CONFIGURE_WIDE_BREAKPOINT: number = 840;

function configureAreaWidth(value: Length): number {
  if (typeof value === 'number') return value;
  return typeof value === 'string' ? Number.parseFloat(value) : 0;
}

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
  @Prop cloudStorageVideoChannelIds: Array<string> = ['11'];
  @Prop tokenIssuerBaseUrl: string = '';
  @Prop tokenSource: DemoTokenSource = DemoTokenSource.issuer;
  @Prop audioStreamId: string = '';
  @Prop videoStreamIds: Array<string> = ['11'];
  @Prop connecting: boolean = false;
  @Prop lastError: string = '';
  @Prop productIndex: number = 0;
  @State private visibleVideoStreamIds: Array<string> = ['11'];
  @State private visibleCloudStorageVideoChannelIds: Array<string> = ['11'];
  @State private pageWidth: number = 0;
  onOpenSettings: () => void = () => {};
  onProductIndexChanged: (value: number) => void = () => {};
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
  onAudioStreamIdChanged: (value: string) => void = () => {};
  onVideoStreamIdChanged: (index: number, value: string) => void = () => {};
  onAddVideoStreamId: () => void = () => {};
  onRemoveVideoStreamId: (index: number) => void = () => {};
  onStartDownlink: () => void = () => {};
  onOpenCloudStorage: () => void = () => {};

  aboutToAppear(): void {
    this.visibleVideoStreamIds = this.videoStreamIds.slice();
    this.visibleCloudStorageVideoChannelIds = this.cloudStorageVideoChannelIds.slice();
  }

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
            .height(44)
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
        .height(48)
        Blank().height(20)
        this.productTabs()
        Blank().height(20)
        this.configurationLayout()
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
    .onAreaChange((oldArea: Area, newArea: Area): void => {
      this.pageWidth = configureAreaWidth(newArea.width);
    })
  }

  @Builder
  private configurationLayout() {
    if (this.pageWidth >= CONFIGURE_WIDE_BREAKPOINT) {
      Row({ space: 20 }) {
        Column({ space: 16 }) {
          if (this.productIndex === 0) {
            this.rtcConnectionCard()
            this.rtcMediaCard()
          } else {
            this.cloudConnectionCard()
            this.cloudMediaCard()
          }
        }
        .layoutWeight(1)
        Column({ space: 16 }) {
          if (this.productIndex === 0) {
            this.rtcAuthenticationCard()
            this.startRtcButton()
          } else {
            this.cloudAuthenticationCard()
            this.startCloudButton()
          }
        }
        .layoutWeight(1)
      }
      .id('tirtc_example_configure_wide_columns')
      .width('100%')
      .alignItems(VerticalAlign.Top)
    } else {
      Column({ space: 16 }) {
        if (this.productIndex === 0) {
          this.rtcConnectionCard()
          this.rtcMediaCard()
          this.rtcAuthenticationCard()
          this.startRtcButton()
        } else {
          this.cloudConnectionCard()
          this.cloudMediaCard()
          this.cloudAuthenticationCard()
          this.startCloudButton()
        }
      }
      .id('tirtc_example_configure_compact_column')
      .width('100%')
    }
  }

  @Builder
  private productTabs() {
    Row() {
      this.productTab('RTC', 0, 'tirtc_example_rtc_product_tab')
      Blank().width(3)
      this.productTab('云录像', 1, 'tirtc_example_ti_cloud_storage_product_tab')
    }
    .width('100%')
    .height(50)
    .padding(3)
    .backgroundColor('#1A659287')
    .borderRadius(22)
  }

  @Builder
  private productTab(label: string, index: number, anchor: string) {
    Button(label)
      .id(anchor)
      .layoutWeight(1)
      .height(44)
      .fontSize(14)
      .fontWeight(FontWeight.Bold)
      .fontColor(this.productIndex === index ? '#FFFFFF' : '#659287')
      .backgroundColor(this.productIndex === index ? '#659287' : '#00FFFFFF')
      .borderRadius(20)
      .enabled(!this.connecting)
      .onClick((): void => {
        this.onProductIndexChanged(index);
      })
  }

  @Builder
  private rtcConnectionCard() {
    Column() {
      this.sectionTitle('连接')
    this.inputField('endpoint', '留空则使用默认环境', this.endpoint, this.onEndpointChanged,
      'tirtc_example_endpoint_field')
    Blank().height(16)
    this.inputField('app_id', 'TiRTC 应用标识', this.appId, this.onAppIdChanged,
      'tirtc_example_app_id_field')
    Blank().height(16)
    this.inputField('remote_id', '待连接的远端目标 ID', this.remoteId, this.onRemoteIdChanged,
      'tirtc_example_remote_id_field')
    }
    .width('100%')
    .padding(18)
    .backgroundColor('#FFFFFF')
    .borderRadius(20)
  }

  @Builder
  private rtcMediaCard() {
    Column() {
    this.sectionTitle('媒体')
    this.inputField('audio_stream_id', '留空不接收音频', this.audioStreamId, this.onAudioStreamIdChanged,
      'tirtc_example_audio_stream_id_field')
    Blank().height(12)
    this.videoIdFields('stream')
    }
    .width('100%')
    .padding(18)
    .backgroundColor('#FFFFFF')
    .borderRadius(20)
  }

  @Builder
  private rtcAuthenticationCard() {
    Column() {
    this.sectionTitle('鉴权')
    this.tokenSection()
    }
    .width('100%')
    .padding(18)
    .backgroundColor('#FFFFFF')
    .borderRadius(20)
  }

  @Builder
  private startRtcButton() {
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
  private cloudConnectionCard() {
    Column() {
    this.sectionTitle('连接')
    this.inputField('app_id', 'Ti Cloud Storage 应用标识', this.cloudStorageAppId, this.onCloudStorageAppIdChanged,
      'tirtc_example_ti_cloud_storage_app_id_field')
    Blank().height(16)
    this.inputField('endpoint', '留空则使用默认环境', this.cloudStorageEndpoint,
      this.onCloudStorageEndpointChanged, 'tirtc_example_ti_cloud_storage_endpoint_field')
    }
    .width('100%')
    .padding(18)
    .backgroundColor('#FFFFFF')
    .borderRadius(20)
  }

  @Builder
  private cloudAuthenticationCard() {
    Column() {
    this.sectionTitle('鉴权')
    Row() {
      Column() {
        this.inputFieldContent('token', '粘贴 Ti Cloud Storage APP Token', this.cloudStorageToken,
          this.onCloudStorageTokenChanged, 'tirtc_example_ti_cloud_storage_token_field', true)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Blank().width(10)
      Button('粘贴')
        .id('tirtc_example_ti_cloud_storage_token_scan_button')
        .accessibilityText('扫码不可用，打开手动粘贴')
        .width(68)
        .height(56)
        .fontSize(13)
        .fontColor('#659287')
        .backgroundColor('#FFFFFF')
        .border({ width: 1, color: '#659287', radius: 20 })
        .onClick(this.onOpenCloudStorageQrScanner)
    }
    .width('100%')
    Text('OHOS Example 未接入相机扫码，请手动粘贴 Token 或配置 JSON。')
      .fontSize(12)
      .fontColor('#848282')
      .margin({ top: 8 })
    }
    .width('100%')
    .padding(18)
    .backgroundColor('#FFFFFF')
    .borderRadius(20)
  }

  @Builder
  private cloudMediaCard() {
    Column() {
    this.sectionTitle('媒体')
    this.inputField('audio_channel_id', '留空不接收音频', this.cloudStorageAudioChannelId,
      this.onCloudStorageAudioChannelIdChanged, 'tirtc_example_ti_cloud_storage_audio_channel_field')
    Blank().height(12)
    this.videoIdFields('channel')
    }
    .width('100%')
    .padding(18)
    .backgroundColor('#FFFFFF')
    .borderRadius(20)
  }

  @Builder
  private startCloudButton() {
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
  private videoIdFields(kind: string) {
    Column({ space: 8 }) {
      ForEach(kind === 'stream' ? this.visibleVideoStreamIds : this.visibleCloudStorageVideoChannelIds,
        (value: string, index: number) => {
        Row({ space: 8 }) {
          Column() {
            this.inputLabel(`video_${kind}_id ${index + 1}`)
            TextInput({ placeholder: '0..255', text: value })
              .id(kind === 'stream' ? `tirtc_example_video_stream_id_field_${index + 1}` :
                `tirtc_example_cloud_storage_video_channel_field_${index + 1}`)
              .height(52)
              .fontSize(13)
              .backgroundColor('#FFFFFF')
              .borderRadius(20)
              .padding({ left: 16, right: 16 })
              .onChange((next: string): void => this.changeVideoId(kind, index, next))
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          Button('删除')
            .id(kind === 'stream' ? `tirtc_example_remove_video_stream_id_button_${index + 1}` :
              `tirtc_example_remove_cloud_storage_video_channel_button_${index + 1}`)
            .height(44)
            .fontSize(12)
            .fontColor('#B42318')
            .backgroundColor('#00FFFFFF')
            .onClick((): void => this.removeVideoId(kind, index))
        }
        .width('100%')
      }, (_: string, index: number): string => `${kind}-${index}`)
      Button(`＋ 添加视频（${kind === 'stream' ? this.visibleVideoStreamIds.length :
        this.visibleCloudStorageVideoChannelIds.length}/3）`)
        .id(kind === 'stream' ? 'tirtc_example_add_video_stream_id_button' :
          'tirtc_example_add_cloud_storage_video_channel_button')
        .height(44)
        .fontSize(13)
        .fontColor('#659287')
        .backgroundColor('#12659287')
        .borderRadius(20)
        .enabled((kind === 'stream' ? this.visibleVideoStreamIds.length :
          this.visibleCloudStorageVideoChannelIds.length) < 3)
        .onClick((): void => {
          hilog.info(LOG_DOMAIN, LOG_TAG, 'TIRTC_configure_add_video_button_clicked kind=%{public}s', kind);
          this.addVideoId(kind);
        })
    }
    .width('100%')
  }

  private addVideoId(kind: string): void {
    if (kind === 'stream') {
      if (this.visibleVideoStreamIds.length >= 3) return;
      this.visibleVideoStreamIds = this.visibleVideoStreamIds.concat(['']);
      this.onAddVideoStreamId();
      return;
    }
    if (this.visibleCloudStorageVideoChannelIds.length >= 3) return;
    this.visibleCloudStorageVideoChannelIds = this.visibleCloudStorageVideoChannelIds.concat(['']);
    this.onAddCloudStorageVideoChannelId();
  }

  private removeVideoId(kind: string, index: number): void {
    if (kind === 'stream') {
      this.visibleVideoStreamIds = this.visibleVideoStreamIds.filter(
        (_: string, itemIndex: number): boolean => itemIndex !== index);
      this.onRemoveVideoStreamId(index);
      return;
    }
    this.visibleCloudStorageVideoChannelIds = this.visibleCloudStorageVideoChannelIds.filter(
      (_: string, itemIndex: number): boolean => itemIndex !== index);
    this.onRemoveCloudStorageVideoChannelId(index);
  }

  private changeVideoId(kind: string, index: number, value: string): void {
    if (kind === 'stream') {
      const next = this.visibleVideoStreamIds.slice();
      next[index] = value;
      this.visibleVideoStreamIds = next;
      this.onVideoStreamIdChanged(index, value);
      return;
    }
    const next = this.visibleCloudStorageVideoChannelIds.slice();
    next[index] = value;
    this.visibleCloudStorageVideoChannelIds = next;
    this.onCloudStorageVideoChannelIdChanged(index, value);
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
        Button('粘贴')
          .id('tirtc_example_token_scan_button')
          .accessibilityText('扫码不可用，打开手动粘贴')
          .width(68)
          .height(56)
          .fontSize(13)
          .fontColor('#659287')
          .backgroundColor('#FFFFFF')
          .border({ width: 1, color: '#659287', radius: 20 })
          .onClick(this.onOpenQrScanner)
      }
      .width('100%')
      Text('OHOS Example 未接入相机扫码，请手动粘贴二维码内容。')
        .fontSize(12)
        .fontColor('#848282')
        .margin({ top: 8 })
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
      .height(44)
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
  private sectionTitle(label: string) {
    Text(label)
      .fontSize(16)
      .fontWeight(FontWeight.Bold)
      .fontColor('#454545')
      .width('100%')
      .padding({ bottom: 12 })
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
