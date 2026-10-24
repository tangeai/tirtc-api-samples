# Ti Cloud Storage Go Example

这个 headless client 使用 Runtime 托管凭据查询一台设备的录像自然日和可回放范围，运行 decoded/encoded Output、Replay 控制、Snapshot、Replay Recording 和独立范围 Export。Replay 与 Export 会打印已确认的录像缺口；Export 还打印覆盖进度和最终报告。

```bash
export TI_CLOUD_STORAGE_APP_ID='...'
export TI_CLOUD_STORAGE_ACCESS_KEY_ID='...'
export TI_CLOUD_STORAGE_ACCESS_KEY_SECRET='...'
export TI_CLOUD_STORAGE_DEVICE_ID='...'

go tool tirtc-build build --output dist/bin/ti-cloud-storage-client ./example/storage
./dist/bin/ti-cloud-storage-client \
  --cache-dir '/absolute/path/to/cache' \
  --output-dir '/absolute/path/to/output' \
  --start-ms 1767225600000 \
  --end-ms 1767312000000 \
  --audio-channel-id 0 \
  --video-channel-id 1
```

两个目录必须是可写绝对路径，Channel ID 位于 `0..255` 且彼此不同。非默认环境可追加 `--endpoint`。Runtime 在每个操作内签发或刷新设备 Token，Example 不接收预签 Token，也不实现重试状态机。

程序保存 Snapshot、Replay Recording、范围 Export 与部分覆盖 Export，打印对应覆盖报告。应用可在 Client 关闭后取得已经成功交付的文件，用标准文件 API 保存，并通过 `Delete()` 删除 Runtime 临时源。测试判据与证据范围见 [Go TEST.html](https://gitlab.tange-ai.com/tirtc-nexus/tirtc/-/blob/develop/go/TEST.html)。
