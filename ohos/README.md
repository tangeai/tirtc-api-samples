# TiRTC OHOS API 示例

这个工程展示 TiRTC OHOS 客户端的拉流播放和麦克风对讲流程，固定引用已经公开发布的 `tirtc@2.4.0-alpha.3`。

## 环境准备

- DevEco Studio，以及兼容 API 23 的 OpenHarmony / HarmonyOS NEXT SDK
- OHPM

## 运行

1. 使用 DevEco Studio 打开当前 `ohos/` 目录。
2. 执行 `ohpm install`。
3. 如果需要在真机运行，打开 `Project Structure → SigningConfigs`，按平台建议启用 DevEco Studio 自动签名。
4. 选择 `entry` 模块并运行应用。

证书、Profile 和签名配置由 DevEco Studio 保存在本机，不应提交到仓库。

## 依赖版本

根工程与 `entry` 模块都使用同一个公开版本：

```json5
{
  "dependencies": {
    "tirtc": "2.4.0-alpha.3"
  }
}
```

更多 API 用法和服务配置见 [TiRTC 文档](https://docs.tange.ai/products/tirtc/)。
