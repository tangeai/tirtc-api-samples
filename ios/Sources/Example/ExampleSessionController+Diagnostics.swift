import Foundation
import TiRTC

func exampleRawDumpEvidenceMarker(
    event: String, archive: TiRawDumpArchive, code: Int32? = nil, logId: String? = nil
) -> String? {
    var payload: [String: Any] = [
        "capture_id": archive.captureId,
        "archive_sha256": archive.sha256,
        "archive_path": archive.path,
    ]
    if let code { payload["code"] = code }
    if let logId { payload["log_id"] = logId }
    guard JSONSerialization.isValidJSONObject(payload),
        let data = try? JSONSerialization.data(withJSONObject: payload)
    else { return nil }
    let encoded = data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    return "raw_dump_evidence_\(event)_b64=\(encoded)"
}

func emitExampleRawDumpEvidenceMarker(_ marker: String) {
    print("[Example] \(marker)")
    fflush(stdout)
    guard let data = "\(marker)\n".data(using: .utf8),
        let cacheRoot = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    else { return }
    let url = cacheRoot.appendingPathComponent("raw-dump-evidence.log")
    try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    if !FileManager.default.fileExists(atPath: url.path) {
        FileManager.default.createFile(atPath: url.path, contents: nil)
    }
    guard let handle = try? FileHandle(forWritingTo: url) else { return }
    defer { try? handle.close() }
    _ = try? handle.seekToEnd()
    _ = try? handle.write(contentsOf: data)
}

func resetExampleRawDumpEvidenceMarkers() {
    guard let cacheRoot = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    else { return }
    try? FileManager.default.removeItem(
        at: cacheRoot.appendingPathComponent("raw-dump-evidence.log"))
}

@MainActor
extension ExampleSessionController {
    func uploadLogs() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.finalizeRawDump(upload: false)
            self.beginLogUpload(isRawDumpUpload: false)
        }
    }

    func rawDumpButtonTapped() {
        guard rawDumpButtonState.enabled else { return }
        if rawDump != nil {
            Task { @MainActor [weak self] in await self?.finalizeRawDump(upload: true) }
        } else if rawDumpArchiveReady {
            beginLogUpload(isRawDumpUpload: true)
        } else {
            startRawDump()
        }
    }

    func finalizeRawDump(upload: Bool) async {
        guard let rawDump else {
            if upload, rawDumpArchiveReady { beginLogUpload(isRawDumpUpload: true) }
            return
        }
        rawDumpButtonState = .finalizing
        async let firstStop = rawDump.stop()
        async let secondStop = rawDump.stop()
        let (result, repeated) = await (firstStop, secondStop)
        if result.code == 0, repeated.code == 0,
            result.archive?.captureId == repeated.archive?.captureId, result.archive != nil
        {
            guard let archive = result.archive else { return }
            self.rawDump = nil
            rawDumpArchiveReady = true
            rawDumpArchiveEvidence = archive
            rawDumpButtonState = .completed
            appendStatusLogLine(
                "raw_dump_archive_ready capture_id=\(archive.captureId) repeated_stop=true")
            if let marker = exampleRawDumpEvidenceMarker(event: "stop", archive: archive) {
                emitExampleRawDumpEvidenceMarker(marker)
            }
            if upload { beginLogUpload(isRawDumpUpload: true) }
        } else {
            rawDumpButtonState = .captureFailed
            setStatus("raw dump stop failed: code=\(result.code)")
        }
    }

    private func startRawDump() {
        guard let conn, let configuration = activeClientConfiguration else {
            rawDumpButtonState = .captureFailed
            return
        }
        rawDumpButtonState = .starting
        resetExampleRawDumpEvidenceMarkers()
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await conn.startRawDump(
                options: TiRtcRawDumpOptions(
                    audioStreamIds: configuration.audioStreamId.map { [NSNumber(value: $0)] } ?? [],
                    videoStreamIds: configuration.videoStreamIds.map { NSNumber(value: $0) },
                    uplinkAudioStreamIds: UInt8(
                        self.localAudioStreamId.trimmingCharacters(in: .whitespacesAndNewlines)
                    ).map { [NSNumber(value: $0)] } ?? []
                ))
            guard result.code == 0, let dump = result.dump else {
                self.rawDumpButtonState = .captureFailed
                self.setStatus("raw dump start failed: code=\(result.code)")
                return
            }
            self.rawDump = dump
            self.rawDumpArchiveReady = false
            self.rawDumpArchiveEvidence = nil
            self.rawDumpButtonState = .capturing
            self.appendStatusLogLine("raw_dump_started flow=client")
        }
    }

    private func beginLogUpload(isRawDumpUpload: Bool) {
        if isLogUploadInProgress {
            return
        }
        appendStatusLogLine("log_upload_ui_visible flow=client")
        isLogUploadInProgress = true
        let code = TiRtcLogging.upload { [weak self] result in
            DispatchQueue.main.async {
                self?.isLogUploadInProgress = false
                let resolvedLogId = result.logId ?? "nil"
                self?.logUploadResult = ExampleLogUploadResult(code: result.code, logId: result.logId)
                let status = "log upload finished: code=\(result.code) log_id=\(resolvedLogId)"
                self?.setStatus(status)
                if isRawDumpUpload {
                    if let self, let archive = self.rawDumpArchiveEvidence,
                        let marker = exampleRawDumpEvidenceMarker(
                            event: "upload", archive: archive, code: result.code,
                            logId: result.logId ?? "")
                    {
                        emitExampleRawDumpEvidenceMarker(marker)
                    }
                    self?.rawDumpButtonState = result.succeeded ? .idle : .uploadFailed
                    if result.succeeded {
                        self?.rawDumpArchiveReady = false
                        self?.rawDumpArchiveEvidence = nil
                    }
                }
                if !result.succeeded {
                    self?.showUserFacingError(code: result.code, context: "log upload")
                }
            }
        }
        if isRawDumpUpload { rawDumpButtonState = .uploading }
        setStatus("log upload started")
        if code != 0 {
            isLogUploadInProgress = false
            logUploadResult = ExampleLogUploadResult(code: code, logId: nil)
            appendStatusLogLine("log upload finished: code=\(code) log_id=nil")
            showUserFacingError(code: code, context: "log upload")
            if isRawDumpUpload { rawDumpButtonState = .uploadFailed }
        }
    }

    func refreshDiagnostics() {
        guard let conn else {
            metricsSummary = "metrics unavailable"
            debugSummary = "debug unavailable"
            return
        }
        let videoOutput = selectedVideoStreamId.flatMap { videoOutputs[$0] }

        let connMetrics = conn.getMetricsSnapshot()
        let audioMetrics = audioOutput?.getMetricsSnapshot()
        let videoMetrics = videoOutput?.getMetricsSnapshot()
        let audioDebug = audioOutput?.getDebugSnapshot()
        let videoDebug = videoOutput?.getDebugSnapshot()
        metricsSummary =
            "conn=\(connMetrics.code) audio=\(audioMetrics?.code ?? 0) video=\(videoMetrics?.code ?? 0)"
        let audioSnapshot = audioDebug?.snapshot
        let audioMetricsSnapshot = audioMetrics?.snapshot
        let videoDebugSnapshot = videoDebug?.snapshot
        let videoMetricsSnapshot = videoMetrics?.snapshot
        debugSummary =
            "audio=\(audioDebug?.code ?? 0) audio_codec=\(audioSnapshot?.codec ?? 0) audio_sample_rate_hz=\(audioSnapshot?.sampleRate ?? 0) audio_channels=\(audioSnapshot?.channels ?? 0) video=\(videoDebug?.code ?? 0) video_codec=\(videoDebugSnapshot?.codec ?? 0) width=\(videoDebugSnapshot?.width ?? 0) height=\(videoDebugSnapshot?.height ?? 0) decoder_backend=\(videoDebugSnapshot?.resolvedDecoderBackend ?? 0)"
        mediaParameterSummary =
            "\(displayVideoSize(videoDebugSnapshot)) · \(displayVideoCodec(videoDebugSnapshot?.codec)) · \(displayAudioCodec(audioSnapshot?.codec)) · \(displayVideoDecoder(videoDebugSnapshot))"
        videoReceiveSummary =
            "码率 \(formatKbps(videoMetricsSnapshot?.videoInputBitrateKbps)) · 接收 \(formatRate(videoMetricsSnapshot?.videoInputFps, suffix: "FPS"))"
        audioReceiveSummary =
            "码率 \(formatKbps(audioMetricsSnapshot?.audioInputBitrateKbps)) · PPS \(formatRate(audioMetricsSnapshot?.audioInputPacketRate, suffix: "/s"))"
        audioStutterSummary =
            "\(formatCount(audioMetricsSnapshot?.stutter.stutterCount)) / 最长 \(formatDuration(audioMetricsSnapshot?.stutter.stutterPeakMs))"
        videoOutputLatencySummary =
            formatOutputLatency(videoMetricsSnapshot?.estimatedOutputLatencyMs)
        audioOutputLatencySummary =
            formatOutputLatency(audioMetricsSnapshot?.estimatedOutputLatencyMs)
        connectionDurationSummary =
            formatDuration(connMetrics.snapshot?.connectDurationMs)
        firstFrameDurationSummary =
            formatDuration(videoMetricsSnapshot?.startup.timeToFirstOutputMs)
        sessionStutterRatioSummary =
            formatRatio(videoMetricsSnapshot?.stutter.stutterRate)
        sessionStutterCountSummary =
            formatCount(videoMetricsSnapshot?.stutter.stutterCount)
        sessionStutterPeakSummary =
            formatDuration(videoMetricsSnapshot?.stutter.stutterPeakMs)
        pendingSummary =
            "audio estimated_output_latency_ms=\(audioMetricsSnapshot?.estimatedOutputLatencyMs ?? -1) video estimated_output_latency_ms=\(videoMetricsSnapshot?.estimatedOutputLatencyMs ?? -1)"
        let debugLine =
            "debug_stats_ready metrics=\"\(metricsSummary)\" debug=\"\(debugSummary)\" media=\"\(mediaParameterSummary)\" video=\"\(videoReceiveSummary)\" audio=\"\(audioReceiveSummary)\" audio_stutter=\"\(audioStutterSummary)\" video_output_latency=\"\(videoOutputLatencySummary)\" audio_output_latency=\"\(audioOutputLatencySummary)\" pending=\"\(pendingSummary)\" audio_output_duration_ms=\(audioMetricsSnapshot?.stutter.outputDurationMs ?? -1) audio_stats_updated_at_ms=\(audioMetricsSnapshot?.statsUpdatedAtMs ?? -1) video_stats_updated_at_ms=\(videoMetricsSnapshot?.statsUpdatedAtMs ?? -1)"
        appendStatusLogLine(debugLine)
        print("[Example] \(debugLine)")
        fflush(stdout)
    }

    func startDiagnosticsRefreshLoop() {
        diagnosticsRefreshGeneration += 1
        let generation = diagnosticsRefreshGeneration
        refreshDiagnostics()
        scheduleDiagnosticsRefresh(generation: generation)
    }

    func stopDiagnosticsRefreshLoop() {
        diagnosticsRefreshGeneration += 1
    }

    private func scheduleDiagnosticsRefresh(generation: Int) {
        DispatchQueue.main.asyncAfter(
            deadline: .now() + DiagnosticsDefaults.refreshIntervalSeconds
        ) { [weak self] in
            guard let self,
                self.diagnosticsRefreshGeneration == generation,
                self.isClientVideoRendering
            else {
                return
            }
            self.refreshDiagnostics()
            self.scheduleDiagnosticsRefresh(generation: generation)
        }
    }

    private func displayVideoSize(_ snapshot: TiRtcVideoOutputDebugSnapshot?) -> String {
        guard let snapshot, snapshot.width > 0, snapshot.height > 0 else {
            return "--"
        }
        return "\(snapshot.width)x\(snapshot.height)"
    }

    private func displayVideoCodec(_ codec: Int32?) -> String {
        switch codec {
        case MetricsDisplayDefaults.mediaCodecVideoH264:
            return "H264"
        case MetricsDisplayDefaults.mediaCodecVideoH265:
            return "H265"
        case MetricsDisplayDefaults.mediaCodecVideoMJPEG:
            return "MJPEG"
        default:
            return "--"
        }
    }

    private func displayAudioCodec(_ codec: Int32?) -> String {
        switch codec {
        case MetricsDisplayDefaults.mediaCodecAudioG711A:
            return "G711A"
        case MetricsDisplayDefaults.mediaCodecAudioAAC:
            return "AAC"
        case MetricsDisplayDefaults.mediaCodecAudioPCM:
            return "PCM"
        case MetricsDisplayDefaults.mediaCodecAudioOPUS:
            return "OPUS"
        case MetricsDisplayDefaults.mediaCodecAudioAMR:
            return "AMR"
        default:
            return "--"
        }
    }

    private func displayVideoDecoder(_ snapshot: TiRtcVideoOutputDebugSnapshot?) -> String {
        let suffix =
            snapshot?.decoderPreference == MetricsDisplayDefaults.decoderPreferenceAutomatic
            ? "（自动）" : ""
        switch snapshot?.resolvedDecoderBackend {
        case MetricsDisplayDefaults.decoderBackendHardware:
            return "硬解\(suffix)"
        case MetricsDisplayDefaults.decoderBackendSoftware:
            return "软解\(suffix)"
        default:
            return "未确定"
        }
    }

    private func formatDuration(_ durationMs: Int64?) -> String {
        guard let durationMs, durationMs >= 0 else {
            return "--"
        }
        return "\(durationMs) ms"
    }

    private func formatRatio(_ ratio: Double?) -> String {
        guard let ratio, !ratio.isNaN, !ratio.isInfinite else {
            return "--"
        }
        return String(format: "%.1f%%", ratio * 100.0)
    }

    private func formatCount(_ count: Int64?) -> String {
        guard let count, count >= 0 else {
            return "--"
        }
        return "\(count) 次"
    }

    private func formatKbps(_ value: Double?) -> String {
        guard isPositive(value) else {
            return "--"
        }
        let value = value ?? 0
        return value >= 100.0
            ? "\(String(format: "%.0f", value)) Kbps"
            : "\(String(format: "%.1f", value)) Kbps"
    }

    private func formatRate(_ value: Double?, suffix: String) -> String {
        guard isPositive(value), let value else {
            return "--"
        }
        return "\(String(format: "%.1f", value)) \(suffix)"
    }

    private func formatOutputLatency(_ latencyMs: Int64?) -> String {
        guard let latencyMs, latencyMs >= 0 else {
            return "--"
        }
        return "估算输出 \(latencyMs) ms"
    }

    private func audioOutputHealthText(_ snapshot: TiRtcAudioOutputMetricsSnapshot?) -> String {
        guard let snapshot,
            isPositive(snapshot.audioInputBitrateKbps),
            isPositive(snapshot.audioInputPacketRate),
            isPositive(snapshot.audioRenderCallbackRate),
            isPositive(snapshot.statsRefreshIntervalMs),
            snapshot.estimatedOutputLatencyMs >= 0,
            snapshot.stutter.stutterCount == 0
        else {
            return "断续风险"
        }
        return "稳定"
    }

    private func isPositive(_ value: Double?) -> Bool {
        guard let value else {
            return false
        }
        return value > 0 && !value.isNaN && !value.isInfinite
    }

    private func isPositive(_ value: Int64?) -> Bool {
        guard let value else {
            return false
        }
        return value > 0
    }
}
