# TiRTC iOS / macOS API 示例

这是 TiRTC 在 Apple 平台共用的一份示例工程，包含 `ExampleIOS` 和 `ExampleMacOS` 两个应用 target。工程固定引用已经公开发布的 `TiRTC 2.2.9` CocoaPod。

## 运行

```bash
pod install
open Example.xcworkspace
```

在 Xcode 中选择 `ExampleIOS` 或 `ExampleMacOS`。如果需要在 iOS 真机运行，请使用自己的 Apple Developer Team 完成签名配置。

## 编译说明

两个应用 target 使用当前 Swift 编译器的 Swift 5 语言模式。已经发布的 `TiRTC 2.2.9` 二进制模块中，部分 delegate 对象类型尚未提供 Swift 6 的 `Sendable` 标注，因此示例需要保留这项编译设置。示例应用源码本身没有因此改动。

更多 API 用法和服务配置见 [TiRTC 文档](https://docs.tange.ai/products/tirtc/)。
