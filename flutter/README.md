# TiRTC Flutter API 示例

这是一个可以独立运行的 Flutter 工程，支持 Android、iOS、macOS 和 OHOS。工程从 TiRTC 主仓的 `tirtc_flutter` Example 生成，并固定引用已经公开发布的 `tirtc_flutter 2.6.0-alpha.18` Git Tag。

## 运行

```bash
flutter pub get
flutter run
```

Android release 构建使用工程内固定的 Flutter Example 内测签名，只用于保持内测包可连续安装，不用于应用商店发布。日常 debug/profile 构建仍使用 Android debug 签名。

`tirtc_flutter` 已携带同版本的 Android、iOS、macOS 和 OHOS 原生依赖；本工程不另配 TiRTC Maven、Pod 或 OHPM 依赖。运行 OHOS 版本时，请使用 OpenHarmony Flutter 工具链。

更多 API 用法和服务配置见 [TiRTC 文档](https://docs.tange.ai/products/tirtc/)。
