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

成功运行会保存 `ti-cloud-storage-snapshot.jpg`、`ti-cloud-storage-replay-recording.mp4` 和 `ti-cloud-storage-range-export.mp4`。部分 Export 也可能产生有效文件；应同时检查 `ExportResult.Report.Complete`、`Gaps` 与 `UnprocessedRanges`。临时源文件保存后通过 `Delete()` 清理。

保存导出结果后，Example 从报告中的来源片段扣除已确认缺口，选择最多五秒的已覆盖范围再启动一次 Export，等处理进度达到终局后关闭 Client，再首次调用该任务的 `Wait()`、保存 `ti-cloud-storage-export-after-close.mp4` 并确认该次报告完整、删除临时文件；重复 `Wait()` 的结果也可幂等删除。这展示成功结果的文件生命周期独立于 Client，部分导出仍按其实际报告保存。
