# TiRTC Go client Example

这个 headless client 使用 Runtime 托管凭据连接一台 RTC 设备，消费 decoded/encoded 音视频，收发命令和流消息，并保存一段 MP4 与一张 JPEG。

```bash
export TIRTC_APP_ID='...'
export TIRTC_ACCESS_KEY_ID='...'
export TIRTC_SECRET_KEY_ID='...'

go tool tirtc-build build --output dist/bin/tirtc-client ./example/client
./dist/bin/tirtc-client \
  --remote-id 'device-id' \
  --cache-dir '/absolute/path/to/cache' \
  --output-dir '/absolute/path/to/output' \
  --audio-stream-id 10 \
  --video-stream-id 11
```

非默认环境可追加 `--endpoint`。`Connect` 的 context 覆盖签发与初次建连；成功后立即订阅。运行成功会写入 `rtc-recording.mp4` 和 `rtc-snapshot.jpg`，然后逆序释放 Output、Connection 与 Client。

保存过程拒绝 symlink、非普通文件和超过 512 MiB 的输入，并使用 exclusive create，避免覆盖已有业务文件。Runtime 临时源文件在保存成功后通过 `Delete()` 删除。
