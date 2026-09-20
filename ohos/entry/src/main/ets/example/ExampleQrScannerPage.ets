import { runOnActivationKey } from './ExampleKeyboard';

@Component
export struct QrScannerPage {
  @Prop cloudStorageMode: boolean = false;
  @Prop payloadText: string = '';
  @Prop errorText: string = '';
  @State private formatHelpExpanded: boolean = false;
  onBack: () => void = () => {};
  onPayloadChanged: (value: string) => void = () => {};
  onApplyPayload: () => void = () => {};

  build() {
    Scroll() {
      Column() {
        Row() {
          Button('<')
            .width(44)
            .height(44)
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
          Text('导入二维码内容')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor('#767676')
            .layoutWeight(1)
        }
        .width('100%')
        .height(44)
        Blank().height(18)
        Text('当前 OHOS Example 未接入相机扫码。请复制二维码内容并在下方手动粘贴。')
          .fontSize(14)
          .fontColor('#666666')
          .lineHeight(20)
          .width('100%')
        Blank().height(20)
        this.scannerUnavailableCard()
        Blank().height(20)
        this.manualPayloadField()
        Blank().height(16)
        this.formatHelp()
        if (this.errorText.length > 0) {
          Blank().height(12)
          Text(this.errorText)
            .fontSize(13)
            .fontColor('#B42318')
            .width('100%')
        }
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 12, bottom: 44 })
    }
    .id('tirtc_example_qr_scanner_page')
    .width('100%')
    .height('100%')
    .backgroundColor('#FFF8E8')
    .linearGradient({
      angle: 180,
      colors: [['#FFF8E8', 0.0], ['#FBF4E5', 0.5], ['#FFF8E8', 1.0]]
    })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  private scannerUnavailableCard() {
    Column({ space: 8 }) {
      Text('相机扫码不可用')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#767676')
      Text('此示例没有申请相机权限，也不会显示虚构的取景框。')
        .fontSize(13)
        .fontColor('#848282')
        .textAlign(TextAlign.Center)
      Button('扫码功能未接入')
        .id('tirtc_example_qr_scanner_disabled_action')
        .accessibilityText('扫码功能未接入，请手动粘贴')
        .height(44)
        .fontSize(13)
        .fontColor('#848282')
        .backgroundColor('#EEE8DC')
        .borderRadius(22)
        .enabled(false)
    }
    .id('tirtc_example_qr_scanner_unavailable')
    .width('100%')
    .padding({ left: 18, right: 18, top: 24, bottom: 24 })
    .backgroundColor('#FFFFFF')
    .borderRadius(20)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private manualPayloadField() {
    Column() {
      TextArea({
        placeholder: this.cloudStorageMode ? '粘贴云录像 Token 或配置 JSON' : '粘贴二维码内容，可为 JSON payload 或纯 v1. Token',
        text: this.payloadText,
      })
        .id('tirtc_example_qr_manual_payload_field')
        .height(120)
        .fontSize(13)
        .fontColor('#666666')
        .placeholderColor('#848282')
        .backgroundColor('#FFFFFF')
        .border({ width: 0, radius: 20 })
        .padding({ left: 18, right: 18, top: 14, bottom: 14 })
        .onChange(this.onPayloadChanged)
      Blank().height(12)
      Button('应用二维码内容')
        .id('tirtc_example_qr_apply_payload_button')
        .width('100%')
        .height(48)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFFFFF')
        .backgroundColor('#659287')
        .borderRadius(24)
        .onClick(() => {
          this.onApplyPayload();
        })
        .onKeyEvent((event: KeyEvent): boolean => {
          return runOnActivationKey(event, () => {
            this.onApplyPayload();
          });
        })
    }
    .width('100%')
  }

  @Builder
  private formatHelp() {
    Column() {
      Button(this.formatHelpExpanded ? '收起内容格式' : '查看内容格式')
        .id('tirtc_example_qr_format_help_button')
        .height(44)
        .fontSize(14)
        .fontColor('#659287')
        .backgroundColor('#00FFFFFF')
        .width('100%')
        .onClick((): void => {
          this.formatHelpExpanded = !this.formatHelpExpanded;
        })
      if (this.formatHelpExpanded) {
        Text(this.cloudStorageMode ?
          '可粘贴纯 APP Token，或包含 app_id、token 和可选 endpoint 的 JSON。' :
          '可粘贴纯 v1 Token，或包含 app_id、remote_id、token 和可选 endpoint 的 JSON。')
          .fontSize(13)
          .fontColor('#666666')
          .lineHeight(19)
          .width('100%')
          .padding({ top: 8 })
      }
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 16, bottom: 16 })
    .backgroundColor('#FFFFFF')
    .border({ width: 0, radius: 18 })
  }
}
