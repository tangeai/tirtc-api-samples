import { runOnActivationKey } from './ExampleKeyboard';

@Component
export struct QrScannerPage {
  @Prop storeMode: boolean = false;
  @Prop payloadText: string = '';
  @Prop errorText: string = '';
  onBack: () => void = () => {};
  onPayloadChanged: (value: string) => void = () => {};
  onApplyPayload: () => void = () => {};

  build() {
    Scroll() {
      Column() {
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
            .onKeyEvent((event: KeyEvent): boolean => {
              return runOnActivationKey(event, () => {
                this.onBack();
              });
            })
          Text('扫描二维码')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor('#767676')
            .layoutWeight(1)
        }
        .width('100%')
        .height(42)
        Blank().height(18)
        Text(this.storeMode ?
          '扫描云录像 Token，或包含 app_id、token 和可选 endpoint 的配置 JSON。' :
          '将 TiRTC DevTools CLI 生成的二维码完整放入方框内，系统会自动填充一次性连接 Token。')
          .fontSize(14)
          .fontColor('#666666')
          .lineHeight(20)
          .width('100%')
        Blank().height(20)
        this.scanArea()
        Blank().height(20)
        this.manualPayloadField()
        Blank().height(16)
        if (!this.storeMode) {
          this.guideCard()
        }
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
  private scanArea() {
    Stack({ alignContent: Alignment.Top }) {
      Column() {
        Blank().height(44)
        Text('等待二维码内容')
          .fontSize(14)
          .fontColor('#B3B3B3')
        Blank()
      }
      .width('100%')
      .height('100%')
      Row() {
        Text('对准二维码')
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .padding({ left: 14, right: 14, top: 6, bottom: 6 })
          .backgroundColor('#66000000')
          .border({ width: 1, color: '#22FFFFFF', radius: 16 })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ top: 14 })
    }
    .width('100%')
    .aspectRatio(1)
    .backgroundColor('#252525')
    .border({ width: 0, radius: 30 })
  }

  @Builder
  private manualPayloadField() {
    Column() {
      TextArea({
        placeholder: this.storeMode ? '粘贴云录像 Token 或配置 JSON' : '粘贴二维码内容，可为 JSON payload 或纯 v1. Token',
        text: this.payloadText,
      })
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
  private guideCard() {
    Column() {
      Text('二维码内容格式')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#767676')
        .width('100%')
      Blank().height(8)
      Text('二维码可以是包含 app_id、remote_id、token 和可选 endpoint 的 JSON，也可以是纯 v1 Token。')
        .fontSize(13)
        .fontColor('#666666')
        .lineHeight(19)
        .width('100%')
      Blank().height(10)
      Text('{"app_id":"demo","remote_id":"device","endpoint":"https://example.com","token":"v1.example"}')
        .fontSize(11)
        .fontColor('#848282')
        .lineHeight(16)
        .width('100%')
      Blank().height(6)
      Text('v1.example-token')
        .fontSize(11)
        .fontColor('#848282')
        .width('100%')
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 16, bottom: 16 })
    .backgroundColor('#FFFFFF')
    .border({ width: 0, radius: 18 })
  }
}
