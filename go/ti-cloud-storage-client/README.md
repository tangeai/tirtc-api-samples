# Ti Cloud Storage Go Example

这个 headless client 查询一台设备的录像自然日和可回放范围，并使用 decoded/encoded 音视频 Output 播放一段录像。它还演示暂停、恢复、Seek、固定七档播放速度、当前时间、Snapshot、回放录像和独立范围导出。

必填 Secret：

```bash
export TI_CLOUD_STORAGE_APP_ID='...'
export TI_CLOUD_STORAGE_ACCESS_TOKEN='...'
```

Token 过期时，查询先返回 `ErrTokenExpired`。Example 从 `TI_CLOUD_STORAGE_REFRESHED_ACCESS_TOKEN` 读取服务端签发的新 Token，调用 `UpdateToken` 后显式重试一次。SDK 不提供过期通知，也不自动刷新或重试。

运行时必须传入 UTC Unix 毫秒时间窗、SDK cache 和应用输出目录：

```bash
go tool tirtc-build build --output dist/bin/ti-cloud-storage-client ./example/storage
./dist/bin/ti-cloud-storage-client \
  --cache-dir '/absolute/path/to/cache' \
  --output-dir '/absolute/path/to/output' \
  --start-ms 1767225600000 \
  --end-ms 1767312000000 \
  --audio-channel-id 0 \
  --video-channel-id 1
```

两个目录必须是可写绝对路径，Channel ID 必须位于 `0..255` 且彼此不同。非默认环境可追加 `--endpoint`。

成功运行会等待 Replay 自然完成，并在 `--output-dir` 写入：

- `ti-cloud-storage-snapshot.jpg`
- `ti-cloud-storage-replay-recording.mp4`
- `ti-cloud-storage-range-export.mp4`

文件保存采用与 RTC Example 相同的有界、exclusive create 规则，成功后删除 Runtime cache 中的临时源文件。
