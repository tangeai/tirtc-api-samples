# 使用 Nano SDK 上传云录像

这个示例持续向 Nano SDK 送入 H.264 视频帧和 G.711A 音频帧，上传一段两分钟的云录像。macOS ARM64 和 Linux x86_64 使用同一份 C 源码，运行脚本根据当前平台选择对应 SDK。

示例使用音频通道 `10` 和视频通道 `11`，与 TiRTC 客户端的默认播放通道保持一致。

示例所需的两份编码素材已经放在 `assets/`，来源于公开的 [tirtc-example-device assets](https://github.com/tangeai/tirtc-example-device/tree/main/assets)。运行时不下载媒体，也不依赖 FFmpeg。

## 下载 SDK

根据运行平台打开下载目录，选择其中最新的 `standard` 包：

| 平台 | 下载目录 | 解压位置 |
| --- | --- | --- |
| macOS ARM64 Desktop | [macos-arm64-desktop releases](https://repo-sdk.tange-ai.com/service/rest/repository/browse/tirtc-sdks/releases/macos-arm64-desktop/) | `sdk/macos-arm64-desktop/` |
| Linux x86_64 | [linux-x86_64 releases](https://repo-sdk.tange-ai.com/service/rest/repository/browse/tirtc-sdks/releases/linux-x86_64/) | `sdk/linux-x86_64/` |

在当前目录创建对应平台的 SDK 目录，再把下载的压缩包解压进去。例如：

```bash
mkdir -p sdk/macos-arm64-desktop
tar -xzf <下载的-macOS-standard.tgz> \
  -C sdk/macos-arm64-desktop \
  --strip-components=1
```

Linux 使用相同方式解压到 `sdk/linux-x86_64/`。解压后应当能看到 `include/tirtc/tistore.h` 和 `lib/`。

## 准备运行参数

运行示例前，从已经开通 TiStore 的应用和设备中取得下面四项输入：

| 参数 | 来源 |
| --- | --- |
| `endpoint` | 当前应用使用的 TiStore 服务地址 |
| `device_id` | 要上传录像的设备 ID |
| `device_secret_key` | 与该设备 ID 配对的设备密钥 |
| `device_access_token` | 业务服务端为该设备签发的短期 Device Access Token |

业务服务端在确认设备有权上传后签发 Device Access Token，再把 Token 交给设备使用。应用级凭据只保存在业务服务端，不能放进这个示例或设备程序。Device Access Token 必须绑定同一个 `device_id`，有效期需要覆盖本次两分钟上传；客户端查询和播放使用的 APP Access Token 不能用于设备上传。

## 运行示例

进入本目录，直接把设备上传需要的参数交给脚本：

```bash
./run.sh \
  --endpoint <endpoint> \
  --device-id <device_id> \
  --device-secret-key <device_secret_key> \
  --token <device_access_token>
```

macOS ARM64 会使用 `sdk/macos-arm64-desktop/`，Linux x86_64 会使用 `sdk/linux-x86_64/`。脚本编译后立即运行，不会把 SDK 或构建产物写入 Git。

上传请求会在送帧前创建。程序随后按实时节奏送帧约两分钟，Nano SDK 在这个过程中持续切片和上传，不会等两分钟数据全部送完才开始工作。运行中会打印首帧、每五秒一次的送帧统计、SDK 队列占用和每个上传切片的结果。

程序不自行生成或提交索引，这部分由 Nano SDK 管理。送帧结束后，程序会等待上传完成回调，并短暂保持 Service 运行，让 SDK 完成后台索引上报，再输出：

```text
[result] upload complete
```

这个结果表示设备侧上传请求已经完整结束；APP 侧查询和播放使用独立的 APP Access Token，并以客户端查询结果作为可见性判断。

## 在 macOS 上验证 Linux

先把 Linux SDK 解压到 `sdk/linux-x86_64/`，再从当前目录运行：

```bash
docker run --rm --platform linux/amd64 \
  -v "$PWD":/work \
  -w /work \
  ubuntu:22.04 \
  bash -lc 'apt-get update && apt-get install -y --no-install-recommends build-essential ca-certificates && ./run.sh --endpoint <endpoint> --device-id <device_id> --device-secret-key <device_secret_key> --token <device_access_token>'
```

`run.sh` 只负责构建和运行示例，不签发或保存凭据。
