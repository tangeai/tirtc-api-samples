# TiRTC Go client Example

这个 headless client 连接一台 RTC 设备，消费 decoded/encoded 音视频，并发送和接收命令与流消息。它还会请求视频关键帧、保存一段 MP4 和一张 JPEG，最后逆序关闭资源。

必填 Secret：

```bash
export TIRTC_APP_ID='...'
export TIRTC_TOKEN='...'
```

运行时必须传入远端设备 ID、SDK cache 和应用输出目录。两个目录都必须是可写绝对路径：

```bash
go tool tirtc-build build --output dist/bin/tirtc-client ./example/client
./dist/bin/tirtc-client \
  --remote-id 'device-id' \
  --cache-dir '/absolute/path/to/cache' \
  --output-dir '/absolute/path/to/output' \
  --audio-stream-id 10 \
  --video-stream-id 11
```

非默认环境可追加 `--endpoint`。成功运行会在 `--output-dir` 写入：

- `rtc-recording.mp4`
- `rtc-snapshot.jpg`

Example 只在收到录像开始后的媒体帧后停止录像。保存过程拒绝 symlink、非普通文件和超过 512 MiB 的输入，并使用 exclusive create，避免覆盖已有应用文件。Runtime cache 中的临时源文件在保存成功后通过 `Delete()` 删除。
