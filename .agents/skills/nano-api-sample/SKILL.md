---
name: nano-api-sample
description: 在 tirtc-api-samples 中新增或维护只依赖公开 Nano SDK 的设备端 C API 示例时使用；负责 device 子工程、公开 README、跨平台运行入口和真实验证。不用于 Runtime 集成、Nano SDK 更新或 SDK 发布。
---

# Nano API Sample

## 交付边界

- 只修改当前公开 API Sample 仓库。示例放在 `device/<capability>/`，并从根 README 和 `device/README.md` 提供入口。
- 示例只能消费开发者可以下载的 Nano 公开头文件和二进制，不依赖 TiRTC Runtime、内部源码、DevTools CLI 或私有服务实现。
- SDK 包不提交到 Git，也不锁定具体版本、URL 或哈希。README 链接到对应平台的 release 上级目录，指导开发者选择最新 `standard` 包并解压到示例约定的 `sdk/<platform>/`。
- macOS ARM64 与 Linux x86_64 共用一套业务源码。平台差异只收敛在构建、链接和运行时动态库准备中，不复制上传逻辑。

## 示例形态

- README 从下载 SDK、解压目录、运行命令和成功信号组织最短路径。启动所需字段直接使用 `run.sh` 的命名参数，不增加环境变量、配置文件或交互式输入。
- README 说明 Endpoint、设备身份和 Device Access Token 的来源，明确应用级凭据只属于业务服务端，设备上传 Token 不能与客户端 APP Access Token 混用。内部 CLI 不能成为外部开发者的准备步骤。
- API 主线应直接展示公开 Nano 调用顺序、异步结果和完整释放。媒体读取、容器解析等辅助职责放到相邻私有源码，不包装或改造 Nano API。
- 示例素材确有必要时随示例提交；不要在运行期依赖另一个 TiRTC 仓库，也不要为方便而引入 FFmpeg 等与目标 API 无关的运行时工具。
- 送帧日志保留首帧、周期摘要、上传进度和最终结果；不逐帧打印，也不输出 Token、设备密钥或完整凭据。

## 验证

1. 使用 README 所述最新 `standard` 包，确认公共 Header、目标动态库和必要伴随库存在。
2. 串行验证 macOS ARM64 原生运行和 Ubuntu 22.04 Linux amd64 Docker 运行。至少证明同一源码在两端编译；拥有联调凭据且用户授权真实上传时，再分别确认公开完成回调和云端可查询结果。
3. 内部 DevTools CLI 可以只为验证签发 Device Token、准备身份或查询结果，但不得进入公开源码依赖和开发者 README。
4. 新建或修改 Skill 后运行 skill validator；复核 Git 状态，确认 SDK、构建目录和测试凭据均未进入工作树。

真实上传、发布和推送是独立外部动作，只在用户明确授权后执行。
