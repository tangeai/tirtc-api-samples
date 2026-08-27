# TiRTC API Samples

这个仓库集中维护 TiRTC 各端 SDK 的公开示例。每个目录都是可以独立理解和构建的工程；你只需要进入当前使用的技术栈目录，不必同时准备其他平台的工具链。

| 目录 | SDK | 工程 |
| --- | --- | --- |
| [`android/`](android/) | Android | Gradle 应用 |
| [`ios/`](ios/) | iOS 和 macOS | 包含 iOS、macOS target 的共享 Xcode 工程 |
| [`flutter/`](flutter/) | Flutter | 包含各端原生宿主的 Flutter 应用 |
| [`react-native/`](react-native/) | React Native | 包含 Android、iOS 宿主的 React Native 应用 |
| [`ohos/`](ohos/) | OpenHarmony / HarmonyOS NEXT | DevEco Studio 应用 |
| [`go/`](go/) | Go | RTC 与云存储命令行客户端 |
| [`device/`](device/) | Nano C SDK | macOS ARM64、Linux x86_64 设备端示例 |

应用端示例固定引用已经在公开 package registry 发布的精确 SDK 版本。设备端示例由开发者下载对应平台最新的 Nano `standard` 包。进入对应目录后，先阅读其中的 README，再按说明安装依赖并运行工程。

示例只保留理解 API 调用和基本串联方式所需的代码，不承载复杂业务逻辑。

[TiRTC 开发文档](https://docs.tange.ai/products/tirtc/)
