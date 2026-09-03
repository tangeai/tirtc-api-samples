# TiRTC React Native API 示例

这个工程固定引用 npm 公开仓库中的 `tirtc-react-native@2.4.1`。Android 和 iOS 使用的 TiRTC 原生依赖由该 package 自动解析。

## 安装依赖

```bash
npm ci
```

## 运行

```bash
npm run android
npm run ios
```

运行 iOS 版本前，先执行 `cd ios && pod install`，再打开 `ios/TiRtcExample.xcworkspace`。如果需要在真机运行，请使用自己的 Apple Developer Team 完成签名配置。

`Podfile.lock` 在本机生成，不提交到仓库。发布检查会单独保存实际解析的 lock，并验证 TiRTC CocoaPods 依赖是否为预期的精确版本。

更多 API 用法和服务配置见 [TiRTC 文档](https://docs.tange.ai/products/tirtc/)。
