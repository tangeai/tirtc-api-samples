# TiRTC React Native API 示例

这个工程固定引用 GitHub Release 的 `tirtc-react-native@2.6.0-alpha.18` tgz：`https://github.com/tangeai/tirtc-sdk-react-native/releases/download/v2.6.0-alpha.18/tirtc-react-native-2.6.0-alpha.18.tgz`。包已携带 Android 和 iOS 使用的同批 TiRTC 原生依赖；npm/Yarn 根据准确 URL 和锁文件安装。

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

`Podfile.lock` 在本机生成，不提交到仓库。发布检查会核对 package 内原生清单与实际构建输入。

更多 API 用法和服务配置见 [TiRTC 文档](https://docs.tange.ai/products/tirtc/)。
