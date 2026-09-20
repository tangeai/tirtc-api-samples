import Foundation
import Photos
import SwiftUI
import TiRTC

#if os(iOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif

private enum TiCloudStorageExampleMedia {
    case recording(TiCloudStorageRecordingFile, UInt8)
    case snapshot(TiCloudStorageSnapshotFile, UInt8)

    var path: String {
        switch self {
        case .recording(let file, _): file.path
        case .snapshot(let file, _): file.path
        }
    }

    var isVideo: Bool {
        if case .recording = self { return true }
        return false
    }

    var targetId: UInt8 {
        switch self {
        case .recording(_, let targetId), .snapshot(_, let targetId): targetId
        }
    }

    func delete() async -> Int32 {
        switch self {
        case .recording(let file, _): await file.delete()
        case .snapshot(let file, _): await file.delete()
        }
    }
}

@MainActor
final class TiCloudStorageExampleFlow: NSObject, ObservableObject,
    TiCloudStorageAudioOutputDelegate,
    TiCloudStorageVideoOutputDelegate
{
    private let cloudStorage: TiCloudStorage
    let replay: TiCloudStorageReplay
    let audioOutput: TiCloudStorageAudioOutput?
    let videoOutputs: [UInt8: TiCloudStorageVideoOutput]
    let audioChannelId: UInt8?
    let videoChannelIds: [UInt8]

    @Published private(set) var recordings: [TiCloudStorageRecordingRange] = []
    @Published private(set) var recordingDays: [TiCloudStorageRecordingDay] = []
    @Published private(set) var selected: TiCloudStorageRecordingRange?
    @Published private(set) var currentTimeMs: Int64?
    @Published private(set) var videoState: TiCloudStorageVideoOutputState = .idle
    @Published private(set) var videoStates: [UInt8: TiCloudStorageVideoOutputState] = [:]
    @Published private(set) var audioState: TiCloudStorageAudioOutputState = .idle
    @Published var selectedVideoChannelId: UInt8?
    @Published var maximizedVideoChannelId: UInt8?
    @Published private(set) var status = "请选择录像"
    @Published private(set) var querying = false
    @Published private(set) var queryCode: Int32?
    @Published private(set) var daysQuerying = false
    @Published private(set) var daysQueryCode: Int32?
    @Published private(set) var mediaBusy = false
    @Published private(set) var recording = false
    @Published private(set) var exporting = false
    @Published private(set) var recordingGapCount = 0
    @Published private(set) var paused = false
    @Published private(set) var muted = false
    @Published private(set) var speed: TiCloudStorageReplaySpeed = .x1
    @Published private(set) var hasLatestMedia = false
    @Published private(set) var uploadingLogs = false
    @Published private(set) var rawDumpButtonState = ExampleRawDumpButtonState.idle

    var hasAudio: Bool { audioOutput != nil && audioState != .failed }

    var stageStatus: String {
        guard selected != nil else { return "请选择录像" }
        switch videoState {
        case .buffering:
            return "缓冲中"
        case .paused:
            return "已暂停"
        case .completed:
            return "播放完成"
        case .failed:
            return "播放失败"
        case .idle:
            return "加载中"
        case .rendering:
            return ""
        @unknown default:
            return "播放状态更新中"
        }
    }

    private var outputsAttached = false
    private var recordingTask: TiCloudStorageRecordingTask?
    private var recordingTargetId: UInt8?
    private var exportTask: TiCloudStorageExportTask?
    private var exportTargetId: UInt8?
    private var exportWaiters: [CheckedContinuation<Void, Never>] = []
    private var latestMedia: TiCloudStorageExampleMedia?
    private var queryTask: Task<Void, Never>?
    private var queuedQuery: (startTimeMs: Int64, endTimeMs: Int64)?
    private var queryGeneration = 0
    private var daysQueryTask: Task<Void, Never>?
    private var queuedDaysQuery: (startDate: String, endDate: String)?
    private var daysQueryGeneration = 0
    private var mediaTask: Task<Void, Never>?
    private var controlTask: Task<Void, Never>?
    private var rawDump: TiRawDump?
    private var rawDumpArchiveReady = false
    private var rawDumpArchiveEvidence: TiRawDumpArchive?
    private var closing = false

    init(token: String, audioChannelId: UInt8?, videoChannelIds: [UInt8]) {
        cloudStorage = TiCloudStorage(token: token)
        replay = cloudStorage.createReplay()
        self.audioChannelId = audioChannelId
        self.videoChannelIds = videoChannelIds
        self.audioOutput = audioChannelId.map { _ in TiCloudStorageAudioOutput() }
        self.videoOutputs = Dictionary(
            uniqueKeysWithValues: videoChannelIds.map { ($0, TiCloudStorageVideoOutput()) })
        self.selectedVideoChannelId = videoChannelIds.first
        super.init()
        audioOutput?.delegate = self
        for output in videoOutputs.values { output.delegate = self }
        replay.onTimeChanged = { [weak self] timeMs in
            self?.currentTimeMs = timeMs
        }
        replay.onError = { [weak self] code in
            self?.videoState = .failed
            self?.status = "播放失败：\(code)"
        }
        replay.onRecordingGap = { [weak self] gap in
            self?.recordingGapCount += 1
            self?.status = "录像缺口 \(gap.range.startTimeMs)-\(gap.range.endTimeMs)"
        }
    }

    func selectVideoChannel(_ channelId: UInt8) {
        if selectedVideoChannelId == channelId {
            maximizedVideoChannelId = maximizedVideoChannelId == channelId ? nil : channelId
        } else {
            selectedVideoChannelId = channelId
            maximizedVideoChannelId = nil
        }
        let next = videoStates[channelId] ?? .idle
        videoState = next == .completed && !outputsCompleted ? .rendering : next
    }

    func query(startTimeMs: Int64, endTimeMs: Int64) {
        guard !closing else { return }
        queryGeneration += 1
        queuedQuery = (startTimeMs, endTimeMs)
        querying = true
        queryCode = nil
        status = "正在查询…"
        recordings = []
        guard queryTask == nil else { return }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled, let request = queuedQuery {
                queuedQuery = nil
                let generation = queryGeneration
                let result = await cloudStorage.listRecordings(
                    startTimeMs: request.startTimeMs,
                    endTimeMs: request.endTimeMs
                )
                if Task.isCancelled { break }
                guard generation == queryGeneration else { continue }
                recordings = result.recordings.sorted { left, right in
                    if left.startTimeMs != right.startTimeMs {
                        return left.startTimeMs > right.startTimeMs
                    }
                    return left.endTimeMs > right.endTimeMs
                }
                queryCode = result.code
                status =
                    result.code == TiCloudStorageErrorCode.ok
                    ? "查询完成：\(result.recordings.count) 段录像" : "查询失败：\(result.code)"
            }
            querying = false
            queryTask = nil
        }
        queryTask = task
    }

    func queryDays(startDate: String, endDate: String) {
        guard !closing else { return }
        daysQueryGeneration += 1
        queuedDaysQuery = (startDate, endDate)
        daysQuerying = true
        daysQueryCode = nil
        recordingDays = []
        guard daysQueryTask == nil else { return }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled, let request = queuedDaysQuery {
                queuedDaysQuery = nil
                let generation = daysQueryGeneration
                let result = await cloudStorage.listRecordingDays(
                    startDate: request.startDate,
                    endDate: request.endDate,
                    timeZoneId: "Asia/Shanghai"
                )
                if Task.isCancelled { break }
                guard generation == daysQueryGeneration else { continue }
                recordingDays = result.days
                daysQueryCode = result.code
            }
            daysQuerying = false
            daysQueryTask = nil
        }
        daysQueryTask = task
    }

    func play(_ range: TiCloudStorageRecordingRange) {
        guard !closing else { return }
        guard audioChannelId != nil || !videoChannelIds.isEmpty else {
            status = "请至少选择一路音频或视频"
            return
        }
        if !outputsAttached {
            var attachedVideoCount = 0
            var firstVideoError = TiCloudStorageErrorCode.ok
            for channelId in videoChannelIds {
                let code =
                    videoOutputs[channelId]?.attach(replay: replay, channelId: channelId)
                    ?? TiCloudStorageErrorCode.invalidArgument
                if code == TiCloudStorageErrorCode.ok {
                    attachedVideoCount += 1
                } else {
                    if firstVideoError == TiCloudStorageErrorCode.ok { firstVideoError = code }
                    videoStates[channelId] = .failed
                }
            }
            var audioCode = TiCloudStorageErrorCode.ok
            if let audioChannelId, let audioOutput {
                audioCode = audioOutput.attach(replay: replay, channelId: audioChannelId)
                if audioCode != TiCloudStorageErrorCode.ok { audioState = .failed }
            }
            let audioAttached = audioChannelId != nil && audioCode == TiCloudStorageErrorCode.ok
            guard audioAttached || attachedVideoCount > 0 else {
                let code = audioCode != TiCloudStorageErrorCode.ok ? audioCode : firstVideoError
                status = "输出绑定失败：\(code)"
                return
            }
            outputsAttached = true
        }
        let code = replay.play(startTimeMs: range.startTimeMs, endTimeMs: range.endTimeMs)
        if code == TiCloudStorageErrorCode.ok {
            selected = range
            currentTimeMs = range.startTimeMs
            paused = false
            status = "正在播放"
        } else {
            status = "播放启动失败：\(code)"
        }
    }

    func seek(to timeMs: Int64) {
        let replay = replay
        performReplayControl(
            operation: { replay.seek(toTimeMs: timeMs) },
            completion: { [weak self] code in
                self?.status = code == TiCloudStorageErrorCode.ok ? "已跳转" : "跳转失败：\(code)"
            }
        )
    }

    func togglePause() {
        let shouldResume = paused
        let replay = replay
        performReplayControl(
            operation: { shouldResume ? replay.resume() : replay.pause() },
            completion: { [weak self] code in
                guard let self else { return }
                if code == TiCloudStorageErrorCode.ok { paused.toggle() }
                status =
                    code == TiCloudStorageErrorCode.ok
                    ? (paused ? "已暂停" : "继续播放") : "暂停操作失败：\(code)"
            }
        )
    }

    func setSpeed(_ next: TiCloudStorageReplaySpeed) {
        let replay = replay
        let rawValue = next.rawValue
        performReplayControl(
            operation: {
                replay.setSpeed(TiCloudStorageReplaySpeed(rawValue: rawValue) ?? .x1)
            },
            completion: { [weak self] code in
                guard let self else { return }
                if code == TiCloudStorageErrorCode.ok { speed = next }
                status =
                    code == TiCloudStorageErrorCode.ok ? "播放倍速：\(next.label)" : "倍速设置失败：\(code)"
            }
        )
    }

    func toggleMute() {
        guard let audioOutput else { return }
        let next = !muted
        let code = audioOutput.setVolume(next ? 0 : 100)
        if code == TiCloudStorageErrorCode.ok { muted = next }
        status = code == TiCloudStorageErrorCode.ok ? (muted ? "已静音" : "已恢复声音") : "音量设置失败：\(code)"
    }

    func takeSnapshot() {
        guard selected != nil, !mediaBusy, let channelId = selectedVideoChannelId,
            let videoOutput = videoOutputs[channelId]
        else { return }
        mediaBusy = true
        mediaTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await videoOutput.takeSnapshot()
            if let file = result.file, result.code == TiCloudStorageErrorCode.ok {
                await replaceLatest(.snapshot(file, channelId))
            }
            mediaBusy = false
            mediaTask = nil
            status = result.code == TiCloudStorageErrorCode.ok ? "截图完成" : "截图失败：\(result.code)"
        }
    }

    func toggleRecording() {
        guard selected != nil, !mediaBusy else { return }
        if let task = recordingTask {
            recordingTask = nil
            let targetId = recordingTargetId
            recordingTargetId = nil
            recording = false
            mediaBusy = true
            mediaTask = Task { @MainActor [weak self] in
                guard let self else { return }
                let result = await task.stop()
                if let file = result.file, result.code == TiCloudStorageErrorCode.ok {
                    await replaceLatest(.recording(file, targetId ?? 0))
                }
                mediaBusy = false
                mediaTask = nil
                status =
                    result.code == TiCloudStorageErrorCode.ok ? "边播边录完成" : "边播边录失败：\(result.code)"
            }
            return
        }
        guard let videoChannelId = selectedVideoChannelId else { return }
        let result = replay.startRecording(
            videoChannelId: Int(videoChannelId),
            audioChannelId: audioChannelId.map { NSNumber(value: $0) }
        )
        recordingTask = result.task
        recordingTargetId = result.task == nil ? nil : videoChannelId
        recording = result.code == TiCloudStorageErrorCode.ok && result.task != nil
        status = recording ? "边播边录已开始" : "边播边录启动失败：\(result.code)"
    }

    func export(_ range: TiCloudStorageRecordingRange) {
        guard exportTask == nil, !closing else { return }
        guard let videoChannelId = selectedVideoChannelId else { return }
        let request = TiCloudStorageExportRequest(
            startTimeMs: range.startTimeMs,
            endTimeMs: range.endTimeMs,
            videoChannelId: Int(videoChannelId),
            audioChannelId: audioChannelId.map { NSNumber(value: $0) }
        )
        let started = cloudStorage.exportRecording(
            request,
            progress: { [weak self] progress in
                Task { @MainActor in self?.status = "范围下载 \(Int(progress * 100))%" }
            },
            progressDetail: { [weak self] progress in
                Task { @MainActor in
                    self?.status =
                        "范围下载 \(Int(progress.fraction * 100))% · 已覆盖 \(progress.coveredDurationMs)ms"
                }
            },
            onRecordingGap: { [weak self] gap in
                Task { @MainActor in
                    self?.recordingGapCount += 1
                    self?.status = "导出缺口 \(gap.range.startTimeMs)-\(gap.range.endTimeMs)"
                }
            },
            completion: { [weak self] result in
                Task { @MainActor in await self?.finishExport(result) }
            }
        )
        exportTask = started.task
        exportTargetId = started.task == nil ? nil : videoChannelId
        exporting = started.code == TiCloudStorageErrorCode.ok && started.task != nil
        status = exporting ? "范围下载已开始" : "范围下载启动失败：\(started.code)"
    }

    func saveLatestToGallery() {
        guard let media = latestMedia, !mediaBusy else { return }
        mediaBusy = true
        mediaTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let copyCode = await publishToPhotos(media)
            let code: Int32
            if copyCode == TiCloudStorageErrorCode.ok {
                code = await media.delete()
                if code == TiCloudStorageErrorCode.ok, latestMedia?.path == media.path {
                    latestMedia = nil
                    hasLatestMedia = false
                }
            } else {
                code = copyCode
            }
            mediaBusy = false
            mediaTask = nil
            status = code == TiCloudStorageErrorCode.ok ? "已保存到系统相册" : "保存到相册失败：\(code)"
        }
    }

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
            rawDumpButtonState = .starting
            resetExampleRawDumpEvidenceMarkers()
            Task { @MainActor [weak self] in
                guard let self else { return }
                let result = await replay.startRawDump(
                    options: TiCloudStorageRawDumpOptions(
                        audioChannelIds: audioChannelId.map { [NSNumber(value: $0)] } ?? [],
                        videoChannelIds: videoChannelIds.map { NSNumber(value: $0) }
                    ))
                guard result.code == 0, let dump = result.dump else {
                    rawDumpButtonState = .captureFailed
                    status = "数据采集启动失败：\(result.code)"
                    return
                }
                rawDump = dump
                rawDumpArchiveReady = false
                rawDumpArchiveEvidence = nil
                rawDumpButtonState = .capturing
                status = "数据采集中"
            }
        }
    }

    private func finalizeRawDump(upload: Bool) async {
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
            status = "数据归档完成"
            if let marker = exampleRawDumpEvidenceMarker(event: "stop", archive: archive) {
                emitExampleRawDumpEvidenceMarker(marker)
            }
            if upload { beginLogUpload(isRawDumpUpload: true) }
        } else {
            rawDumpButtonState = .captureFailed
            status = "数据归档失败：\(result.code)"
        }
    }

    private func beginLogUpload(isRawDumpUpload: Bool) {
        guard !uploadingLogs else { return }
        uploadingLogs = true
        let code = TiRtcLogging.upload { [weak self] result in
            Task { @MainActor in
                self?.uploadingLogs = false
                self?.status =
                    result.succeeded ? "日志上传完成：\(result.logId ?? "")" : "日志上传失败：\(result.code)"
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
            }
        }
        if isRawDumpUpload { rawDumpButtonState = .uploading }
        if code != TiCloudStorageErrorCode.ok {
            uploadingLogs = false
            status = "日志上传启动失败：\(code)"
            if isRawDumpUpload { rawDumpButtonState = .uploadFailed }
        }
    }

    func close() async -> Int32 {
        guard !closing else { return TiCloudStorageErrorCode.ok }
        closing = true
        queryGeneration += 1
        daysQueryGeneration += 1
        queuedQuery = nil
        queuedDaysQuery = nil
        var code = TiCloudStorageErrorCode.ok
        await finalizeRawDump(upload: false)
        await controlTask?.value
        controlTask = nil
        await mediaTask?.value
        mediaTask = nil
        if let task = recordingTask {
            recordingTask = nil
            let result = await task.stop()
            code = firstError(code, result.code)
            if let file = result.file { code = firstError(code, await file.delete()) }
        }
        if let task = exportTask {
            _ = task.stop()
            await waitForExportTerminal()
        }
        await queryTask?.value
        queryTask = nil
        await daysQueryTask?.value
        daysQueryTask = nil
        if let latestMedia {
            code = firstError(code, await latestMedia.delete())
            self.latestMedia = nil
        }
        code = firstError(code, replay.stop())
        code = firstError(code, audioOutput?.detach() ?? 0)
        for output in videoOutputs.values {
            code = firstError(code, output.detach())
            code = firstError(code, output.detachView())
        }
        code = firstError(code, audioOutput?.dispose() ?? 0)
        for output in videoOutputs.values { code = firstError(code, output.dispose()) }
        code = firstError(code, replay.dispose())
        code = firstError(code, cloudStorage.dispose())
        return code
    }

    nonisolated func audioOutput(
        _ output: TiCloudStorageAudioOutput,
        didChangeState state: TiCloudStorageAudioOutputState
    ) {
        let rawValue = state.rawValue
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.audioState = TiCloudStorageAudioOutputState(rawValue: rawValue) ?? .failed
            self.publishCompletionIfReady()
        }
    }

    nonisolated func audioOutput(_ output: TiCloudStorageAudioOutput, didFailWithCode code: Int32) {
        Task { @MainActor [weak self] in
            self?.audioState = .failed
            self?.status = "音频输出失败：\(code)"
        }
    }

    nonisolated func videoOutput(
        _ output: TiCloudStorageVideoOutput,
        didChangeState state: TiCloudStorageVideoOutputState
    ) {
        let outputIdentity = ObjectIdentifier(output)
        let rawValue = state.rawValue
        Task { @MainActor [weak self] in
            let next = TiCloudStorageVideoOutputState(rawValue: rawValue) ?? .failed
            guard let self,
                let channelId = self.videoOutputs.first(where: {
                    ObjectIdentifier($0.value) == outputIdentity
                })?.key
            else { return }
            self.videoStates[channelId] = next
            if next == .completed {
                self.publishCompletionIfReady()
            } else if self.selectedVideoChannelId == channelId {
                self.videoState = next
            }
            if next == .failed { self.status = "视频 Channel \(channelId) 输出失败" }
        }
    }

    nonisolated func videoOutput(_ output: TiCloudStorageVideoOutput, didFailWithCode code: Int32) {
        let outputIdentity = ObjectIdentifier(output)
        Task { @MainActor [weak self] in
            guard let self,
                let channelId = self.videoOutputs.first(where: {
                    ObjectIdentifier($0.value) == outputIdentity
                })?.key
            else { return }
            self.videoStates[channelId] = .failed
            if self.selectedVideoChannelId == channelId { self.videoState = .failed }
            self.status = "视频 Channel \(channelId) 输出失败：\(code)"
        }
    }

    private var outputsCompleted: Bool {
        let audioCompleted = audioOutput == nil || audioState == .completed
        return audioCompleted && videoChannelIds.allSatisfy { videoStates[$0] == .completed }
    }

    private func publishCompletionIfReady() {
        guard outputsCompleted else { return }
        videoState = .completed
        status = "播放完成"
    }

    private func replaceLatest(_ next: TiCloudStorageExampleMedia) async {
        let previous = latestMedia
        latestMedia = next
        hasLatestMedia = true
        if let previous, previous.path != next.path { _ = await previous.delete() }
    }

    private func finishExport(_ result: TiCloudStorageExportResult) async {
        exportTask = nil
        let targetId = exportTargetId
        exportTargetId = nil
        exporting = false
        if let file = result.file, result.code == TiCloudStorageErrorCode.ok {
            if closing {
                _ = await file.delete()
            } else {
                await replaceLatest(.recording(file, targetId ?? 0))
            }
        }
        if let report = result.report {
            status =
                result.code == TiCloudStorageErrorCode.ok
                ? "范围下载完成 · 覆盖 \(report.coveredDurationMs)ms · 缺口 \(report.gaps.count)"
                : "范围下载失败：\(result.code) · 已覆盖 \(report.coveredDurationMs)ms"
        } else {
            status = result.code == TiCloudStorageErrorCode.ok ? "范围下载完成" : "范围下载失败：\(result.code)"
        }
        let waiters = exportWaiters
        exportWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    private func waitForExportTerminal() async {
        if exportTask == nil { return }
        await withCheckedContinuation { continuation in exportWaiters.append(continuation) }
    }

    private func performReplayControl(
        operation: @escaping @Sendable () -> Int32,
        completion: @escaping @MainActor (Int32) -> Void
    ) {
        guard controlTask == nil, !closing else { return }
        controlTask = Task { @MainActor [weak self] in
            let code = await Task.detached(priority: .userInitiated, operation: operation).value
            guard let self else { return }
            controlTask = nil
            completion(code)
        }
    }

    private func publishToPhotos(_ media: TiCloudStorageExampleMedia) async -> Int32 {
        await Self.publishToPhotos(
            path: media.path, isVideo: media.isVideo, targetId: media.targetId)
    }

    nonisolated private static func publishToPhotos(path: String, isVideo: Bool, targetId: UInt8)
        async -> Int32
    {
        var authorization = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if authorization == .notDetermined {
            authorization = await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization(for: .addOnly) {
                    continuation.resume(returning: $0)
                }
            }
        }
        guard authorization == .authorized || authorization == .limited else {
            return TiCloudStorageErrorCode.permissionDenied
        }
        let source = URL(fileURLWithPath: path)
        let alias = FileManager.default.temporaryDirectory.appendingPathComponent(
            "tirtc-\(isVideo ? "recording" : "snapshot")-channel-\(targetId).\(isVideo ? "mp4" : "jpg")"
        )
        do {
            try? FileManager.default.removeItem(at: alias)
            try FileManager.default.copyItem(at: source, to: alias)
        } catch {
            return TiCloudStorageErrorCode.fileWriteFailed
        }
        let result: Int32 = await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                if isVideo {
                    _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: alias)
                } else {
                    _ = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: alias)
                }
            } completionHandler: { success, _ in
                let result: Int32
                if success {
                    result = TiCloudStorageErrorCode.ok
                } else {
                    result = TiCloudStorageErrorCode.fileWriteFailed
                }
                continuation.resume(returning: result)
            }
        }
        try? FileManager.default.removeItem(at: alias)
        return result
    }

    private func firstError(_ current: Int32, _ next: Int32) -> Int32 {
        if next == TiCloudStorageErrorCode.ok
            || next == TiCloudStorageErrorCode.notStarted
            || next == TiCloudStorageErrorCode.notBound
        {
            return current
        }
        return current == TiCloudStorageErrorCode.ok ? next : current
    }
}

extension TiCloudStorageReplaySpeed {
    fileprivate var label: String {
        switch self {
        case .x0_125: "1/8×"
        case .x0_25: "1/4×"
        case .x0_5: "1/2×"
        case .x1: "1×"
        case .x2: "2×"
        case .x4: "4×"
        case .x8: "8×"
        @unknown default: "1×"
        }
    }
}

extension TiCloudStorageVideoOutputState {
    fileprivate var accessibilityLabel: String {
        switch self {
        case .idle: "idle"
        case .buffering: "buffering"
        case .rendering: "rendering"
        case .failed: "failed"
        case .paused: "paused"
        case .completed: "completed"
        @unknown default: "unknown"
        }
    }

    fileprivate var statusLabel: String? {
        switch self {
        case .idle: "等待视频"
        case .buffering: "缓冲中"
        case .rendering: nil
        case .failed: "播放失败"
        case .paused: "已暂停"
        case .completed: "播放完成"
        @unknown default: "状态更新中"
        }
    }
}

struct TiCloudStorageExampleView: View {
    @Environment(\.presentationMode) private var presentationMode
    @Environment(\.sizeCategory) private var sizeCategory
    @StateObject private var flow: TiCloudStorageExampleFlow
    @State private var initCode: Int32
    @State private var selectedDate = Date()
    @State private var visibleMonth = Date()
    @State private var recordingsPresented = false
    @State private var secondaryActionsPresented = false
    @State private var speedActionsPresented = false
    @State private var seekPreview: Double?
    @State private var cleaning = false

    init(
        appId: String, endpoint: String, token: String, audioChannelId: UInt8?,
        videoChannelIds: [UInt8]
    ) {
        let code = TiCloudStorage.initialize(
            appId: appId.trimmingCharacters(in: .whitespacesAndNewlines),
            endpoint: endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
            consoleLogEnabled: false
        )
        _initCode = State(initialValue: code)
        _flow = StateObject(
            wrappedValue: TiCloudStorageExampleFlow(
                token: token.trimmingCharacters(in: .whitespacesAndNewlines),
                audioChannelId: audioChannelId,
                videoChannelIds: videoChannelIds
            ))
    }

    var body: some View {
        VStack(spacing: 0) {
            cloudHeader
                .padding(.horizontal, 16)
                .frame(height: 56)
                .background(ExampleColors.background)

            ZStack {
                GeometryReader { proxy in
                    let visibleIds =
                        flow.maximizedVideoChannelId.map { [$0] } ?? flow.videoChannelIds
                    let ordered = ExamplePlaybackLayout.promoted(
                        visibleIds,
                        selected: flow.selectedVideoChannelId
                    )
                    cloudVideoLayout(
                        ordered,
                        layout: ExamplePlaybackLayout.resolve(
                            itemCount: ordered.count,
                            availableWidth: Double(proxy.size.width)
                        )
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(Color.black)
                LinearGradient(
                    colors: [Color.black.opacity(0.35), .clear, Color.black.opacity(0.68)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                ExampleRawDumpButton(
                    state: flow.rawDumpButtonState,
                    action: flow.rawDumpButtonTapped
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.leading, 12)
                if initCode != TiCloudStorageErrorCode.ok || flow.videoChannelIds.isEmpty {
                    Text(
                        initCode == TiCloudStorageErrorCode.ok
                            ? flow.stageStatus : "初始化失败：\(initCode)"
                    )
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(18)
                    .background(Color.black.opacity(0.48))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                }
                VStack {
                    Spacer()
                    cloudStorageControls
                }
                .padding(20)
                #if os(iOS)
                    if secondaryActionsPresented || speedActionsPresented {
                        Color.black.opacity(0.001)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                secondaryActionsPresented = false
                                speedActionsPresented = false
                            }
                    }
                    if secondaryActionsPresented {
                        VStack(alignment: .leading, spacing: 8) {
                            cloudRecordingButton
                            cloudSnapshotButton
                            cloudGalleryButton
                        }
                        .padding(16)
                        .frame(minWidth: 220)
                        .background(ExampleColors.background)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: Color.black.opacity(0.24), radius: 12, y: 4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(.trailing, 20)
                        .padding(.bottom, flow.selected == nil ? 100 : 140)
                        .accessibilityElement(children: .contain)
                        .accessibilityAction(.escape) { secondaryActionsPresented = false }
                    }
                    if speedActionsPresented {
                        VStack(alignment: .leading, spacing: 4) {
                            cloudSpeedChoice("1/8×", .x0_125)
                            cloudSpeedChoice("1/4×", .x0_25)
                            cloudSpeedChoice("1/2×", .x0_5)
                            cloudSpeedChoice("1×", .x1)
                            cloudSpeedChoice("2×", .x2)
                            cloudSpeedChoice("4×", .x4)
                            cloudSpeedChoice("8×", .x8)
                        }
                        .padding(12)
                        .frame(minWidth: 120)
                        .background(ExampleColors.background)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: Color.black.opacity(0.24), radius: 12, y: 4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(.trailing, 72)
                        .padding(.bottom, flow.selected == nil ? 100 : 140)
                        .accessibilityElement(children: .contain)
                        .accessibilityAction(.escape) { speedActionsPresented = false }
                    }
                #endif
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("cloudStorage.video_stage")
            .accessibilityLabel(flow.videoState.accessibilityLabel)
            .accessibilityValue(flow.videoState.accessibilityLabel)
        }
        .frame(minWidth: 320, minHeight: 560)
        .background(ExampleColors.background)
        .sheet(isPresented: $recordingsPresented) { recordingsSheetContainer }
        .onAppear {
            guard initCode == TiCloudStorageErrorCode.ok else { return }
            recordingsPresented = true
            queryVisibleMonth()
            querySelectedWindow()
        }
        .onDisappear { closeWithoutDismiss() }
    }

    private var cloudHeader: some View {
        GeometryReader { proxy in
            HStack(spacing: 8) {
                cloudCloseButton
                cloudTitle
                Spacer()
                if proxy.size.width < CGFloat(ExamplePlaybackLayout.compactBreakpoint) {
                    cloudRecordingsIconButton
                    cloudUploadLogsIconButton
                } else {
                    cloudRecordingsButton
                    cloudUploadLogsButton
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var cloudCloseButton: some View {
        Button(action: closeAndDismiss) {
            Text("关闭")
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("cloudStorage.close")
    }

    private var cloudTitle: some View {
        Text("云录像")
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(ExampleColors.primary)
            .accessibilityIdentifier("cloudStorage.player.page")
    }

    private var cloudRecordingsButton: some View {
        Button(action: { recordingsPresented = true }) {
            Label("选择录像", systemImage: "calendar")
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(initCode != TiCloudStorageErrorCode.ok)
        .accessibilityIdentifier("cloudStorage.recordings")
    }

    private var cloudRecordingsIconButton: some View {
        Button(action: { recordingsPresented = true }) {
            Image(systemName: "calendar")
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .disabled(initCode != TiCloudStorageErrorCode.ok)
        .accessibilityIdentifier("cloudStorage.recordings")
        .accessibilityLabel("选择录像")
    }

    private var cloudUploadLogsButton: some View {
        Button(action: { flow.uploadLogs() }) {
            Label(flow.uploadingLogs ? "上传中…" : "上传日志", systemImage: "arrow.up.doc")
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(flow.uploadingLogs)
        .accessibilityIdentifier("cloudStorage.upload_logs")
    }

    private var cloudUploadLogsIconButton: some View {
        Button(action: { flow.uploadLogs() }) {
            Image(systemName: flow.uploadingLogs ? "hourglass" : "arrow.up.doc")
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .disabled(flow.uploadingLogs)
        .accessibilityIdentifier("cloudStorage.upload_logs")
        .accessibilityLabel(flow.uploadingLogs ? "上传中" : "上传日志")
    }

    private var cloudStorageControls: some View {
        GeometryReader { proxy in
            let compact =
                proxy.size.width < CGFloat(ExamplePlaybackLayout.compactBreakpoint)
                || sizeCategory.isAccessibilityCategory

            VStack(spacing: 6) {
                if let range = flow.selected {
                    HStack(spacing: 8) {
                        Text(formatTime(currentTime(range)))
                        Slider(
                            value: Binding(
                                get: { seekValue(range) },
                                set: { seekPreview = $0 }
                            ),
                            in: Double(
                                range.startTimeMs)...Double(
                                    max(range.startTimeMs + 1, range.endTimeMs - 1)),
                            onEditingChanged: { editing in
                                guard !editing, let seekPreview else { return }
                                flow.seek(to: Int64(seekPreview))
                                self.seekPreview = nil
                            }
                        )
                        .accessibilityIdentifier("cloudStorage.seek")
                        .accessibilityLabel("录像进度")
                        .accessibilityValue(
                            "\(formatTime(currentTime(range))) / \(formatTime(range.endTimeMs))"
                        )
                        Text(formatTime(range.endTimeMs))
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.white)
                    .frame(minHeight: 30)
                }

                HStack(spacing: compact ? 6 : 10) {
                    cloudStorageIconAction(
                        flow.paused ? "继续播放" : "暂停播放",
                        flow.paused ? "play.fill" : "pause.fill",
                        "cloudStorage.pause"
                    ) {
                        flow.togglePause()
                    }
                    cloudStorageIconAction(
                        flow.muted ? "恢复声音" : "静音",
                        flow.muted ? "speaker.wave.2.fill" : "speaker.slash.fill",
                        "cloudStorage.mute",
                        enabled: flow.hasAudio && flow.speed == .x1
                    ) {
                        flow.toggleMute()
                    }
                    speedMenu
                    if compact {
                        cloudSecondaryMenu
                    } else if flow.selectedVideoChannelId != nil {
                        cloudRecordingButton
                        cloudSnapshotButton
                        cloudGalleryButton
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                Text(flow.status)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.88))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("cloudStorage.status")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.68))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("cloudStorage.control_surface")
            .accessibilityLabel("云录像播放控制")
            .accessibilityValue(flow.status)
        }
        .frame(height: flow.selected == nil ? 72 : 112)
    }

    private var speedMenu: some View {
        #if os(macOS)
            Menu {
                Button("1/8×") { flow.setSpeed(.x0_125) }
                Button("1/4×") { flow.setSpeed(.x0_25) }
                Button("1/2×") { flow.setSpeed(.x0_5) }
                Button("1×") { flow.setSpeed(.x1) }
                Button("2×") { flow.setSpeed(.x2) }
                Button("4×") { flow.setSpeed(.x4) }
                Button("8×") { flow.setSpeed(.x8) }
            } label: {
                cloudSpeedLabel
            }
            .disabled(flow.selected == nil || flow.mediaBusy)
            .accessibilityIdentifier("cloudStorage.speed")
            .accessibilityLabel("播放倍速")
            .accessibilityValue(flow.speed.label)
        #else
            Button(action: { speedActionsPresented.toggle() }) {
                cloudSpeedLabel
            }
            .buttonStyle(.plain)
            .disabled(flow.selected == nil || flow.mediaBusy)
            .accessibilityIdentifier("cloudStorage.speed")
            .accessibilityLabel("播放倍速")
            .accessibilityValue(flow.speed.label)
        #endif
    }

    private var cloudSpeedLabel: some View {
        Text(flow.speed.label)
            .font(.subheadline.weight(.semibold))
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
    }

    private func cloudSpeedChoice(_ title: String, _ speed: TiCloudStorageReplaySpeed) -> some View {
        Button(
            action: {
                speedActionsPresented = false
                flow.setSpeed(speed)
            },
            label: {
                Text(title)
                    .frame(minWidth: 96, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            })
    }

    private var cloudSecondaryMenu: some View {
        #if os(macOS)
            Menu {
                cloudRecordingButton
                cloudSnapshotButton
                cloudGalleryButton
            } label: {
                cloudMoreLabel
            }
            .accessibilityIdentifier("cloudStorage.more")
            .accessibilityLabel("更多播放操作")
        #else
            Button(action: { secondaryActionsPresented.toggle() }) {
                cloudMoreLabel
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("cloudStorage.more")
            .accessibilityLabel("更多播放操作")
        #endif
    }

    private var cloudMoreLabel: some View {
        Image(systemName: "ellipsis.circle")
            .font(.title3.weight(.semibold))
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
    }

    private var cloudRecordingButton: some View {
        Button(action: {
            secondaryActionsPresented = false
            flow.toggleRecording()
        }) {
            Label(
                flow.recording ? "停止本地保存" : "开始本地保存",
                systemImage: flow.recording ? "stop.circle" : "record.circle"
            )
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .disabled(flow.selected == nil || flow.selectedVideoChannelId == nil || flow.mediaBusy)
        .accessibilityIdentifier("cloudStorage.recording")
        .accessibilityValue(flow.recording ? "正在保存" : "未保存")
    }

    private var cloudSnapshotButton: some View {
        Button(action: {
            secondaryActionsPresented = false
            flow.takeSnapshot()
        }) {
            Label("截图", systemImage: "camera")
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .disabled(flow.selected == nil || flow.selectedVideoChannelId == nil || flow.mediaBusy)
        .accessibilityIdentifier("cloudStorage.snapshot")
    }

    private var cloudGalleryButton: some View {
        Button(action: {
            secondaryActionsPresented = false
            flow.saveLatestToGallery()
        }) {
            Label("保存到系统相册", systemImage: "photo.on.rectangle.angled")
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .disabled(flow.selected == nil || !flow.hasLatestMedia || flow.mediaBusy)
        .accessibilityIdentifier("cloudStorage.gallery")
    }

    private func cloudStorageIconAction(
        _ title: String,
        _ systemImage: String,
        _ identifier: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(flow.selected == nil || flow.mediaBusy || !enabled)
        .opacity(flow.selected == nil || flow.mediaBusy || !enabled ? 0.55 : 1)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private func cloudVideoLayout(
        _ ids: [UInt8],
        layout: ExamplePlaybackLayout
    ) -> some View {
        switch layout {
        case .empty:
            Color.clear
        case .single:
            cloudVideoLane(ids[0])
        case .twoVertical:
            VStack(spacing: 6) {
                cloudVideoLane(ids[0])
                cloudVideoLane(ids[1])
            }
        case .twoHorizontal:
            HStack(spacing: 6) {
                cloudVideoLane(ids[0])
                cloudVideoLane(ids[1])
            }
        case .threePrimaryTop:
            VStack(spacing: 6) {
                cloudVideoLane(ids[0])
                HStack(spacing: 6) {
                    cloudVideoLane(ids[1])
                    cloudVideoLane(ids[2])
                }
            }
        case .threePrimaryLeading:
            HStack(spacing: 6) {
                cloudVideoLane(ids[0])
                VStack(spacing: 6) {
                    cloudVideoLane(ids[1])
                    cloudVideoLane(ids[2])
                }
            }
        }
    }

    private func cloudVideoLane(_ channelId: UInt8) -> some View {
        let laneNumber = (flow.videoChannelIds.firstIndex(of: channelId) ?? 0) + 1
        let selected = flow.selectedVideoChannelId == channelId
        let maximized = flow.maximizedVideoChannelId == channelId
        return ZStack(alignment: .topLeading) {
            if let output = flow.videoOutputs[channelId] {
                TiCloudStorageExampleVideoSurface(output: output)
                    .aspectRatio(16 / 9, contentMode: .fit)
            }
            if let status = (flow.videoStates[channelId] ?? .idle).statusLabel {
                Text(status)
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.62))
            }
            Text("视频 \(laneNumber) · ID \(channelId)")
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.68))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(8)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(selected ? ExampleColors.primary : .clear, lineWidth: 3)
        )
        .contentShape(Rectangle())
        .onTapGesture { flow.selectVideoChannel(channelId) }
        .accessibilityIdentifier("cloudStorage.video_lane.\(channelId)")
        .accessibilityLabel("视频 \(laneNumber)，ID \(channelId)")
        .accessibilityValue(
            "\(flow.videoStates[channelId]?.accessibilityLabel ?? "idle"), "
                + "\(maximized ? "已最大化" : selected ? "已选择" : "未选择")"
        )
        .accessibilityHint(selected ? "轻点可最大化或恢复" : "轻点可选为主画面")
    }

    private var recordingsSheet: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("选择录像")
                                .font(.title2.bold())
                                .accessibilityAddTraits(.isHeader)
                            Text("先选日期，再播放或下载录像段")
                                .font(.footnote)
                                .foregroundColor(ExampleColors.textSecondary)
                        }
                        Spacer()
                        Button(action: { recordingsPresented = false }) {
                            Text("关闭")
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("cloudStorage.recordings.close")
                    }
                    if ExampleAuxiliaryLayout.isWide(availableWidth: Double(proxy.size.width)) {
                        HStack(alignment: .top, spacing: 20) {
                            recordingCalendar.frame(maxWidth: .infinity)
                            recordingList.frame(maxWidth: .infinity)
                        }
                    } else {
                        VStack(spacing: 16) {
                            recordingCalendar
                            Divider()
                            recordingList
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: 980)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(minWidth: 320, minHeight: 480)
        .background(ExampleColors.background)
        .accessibilityIdentifier("cloudStorage.recordings.page")
    }

    @ViewBuilder
    private var recordingList: some View {
        if flow.querying {
            VStack(spacing: 10) {
                ProgressView()
                Text("正在查询当天录像…")
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("cloudStorage.recordings.loading")
        } else if let code = flow.queryCode, code != TiCloudStorageErrorCode.ok {
            VStack(spacing: 12) {
                Text("录像查询失败：\(code)")
                    .foregroundColor(ExampleColors.textSecondary)
                Button("重试当天") { querySelectedWindow() }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("cloudStorage.recordings.retry")
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .accessibilityIdentifier("cloudStorage.recordings.error")
        } else if flow.recordings.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.title)
                Text("当天没有可用录像")
                    .font(.headline)
                Text("请选择带状态点的日期")
                    .font(.footnote)
                    .foregroundColor(ExampleColors.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("cloudStorage.recordings.empty")
        } else {
            LazyVStack(spacing: 8) {
                ForEach(Array(flow.recordings.enumerated()), id: \.offset) { _, range in
                    HStack(spacing: 12) {
                        Button("\(formatTime(range.startTimeMs)) — \(formatTime(range.endTimeMs))") {
                            recordingsPresented = false
                            flow.play(range)
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                        .accessibilityIdentifier("cloudStorage.play.\(range.startTimeMs)")
                        Button(flow.exporting ? "下载中…" : "下载") { flow.export(range) }
                            .frame(minWidth: 64, minHeight: 44)
                            .disabled(flow.exporting)
                            .accessibilityIdentifier("cloudStorage.export.\(range.startTimeMs)")
                    }
                    .padding(.horizontal, 12)
                    .background(ExampleColors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .accessibilityIdentifier("cloudStorage.recordings.list")
        }
    }

    @ViewBuilder
    private var recordingsSheetContainer: some View {
        if #available(iOS 16.0, macOS 13.0, *) {
            recordingsSheet
                .presentationDetents([.fraction(0.88)])
                .presentationDragIndicator(.visible)
        } else {
            recordingsSheet
        }
    }

    private var recordingCalendar: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(spacing: 8) {
                    HStack {
                        Button(action: { changeVisibleMonth(by: -1) }) {
                            Image(systemName: "chevron.left")
                                .frame(width: 44, height: 44)
                        }
                        .disabled(flow.daysQuerying)
                        .accessibilityLabel("上个月")
                        .accessibilityIdentifier("cloudStorage.calendar.previous")
                        Spacer()
                        Text(monthTitle)
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        Button(action: { changeVisibleMonth(by: 1) }) {
                            Image(systemName: "chevron.right")
                                .frame(width: 44, height: 44)
                        }
                        .disabled(flow.daysQuerying)
                        .accessibilityLabel("下个月")
                        .accessibilityIdentifier("cloudStorage.calendar.next")
                    }
                    HStack(spacing: 4) {
                        ForEach(["日", "一", "二", "三", "四", "五", "六"], id: \.self) { value in
                            Text(value)
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .accessibilityAddTraits(.isHeader)
                        }
                    }
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(), spacing: 4), count: 7),
                        spacing: 4
                    ) {
                        ForEach(Array(monthGridDays.enumerated()), id: \.offset) { _, day in
                            if let day {
                                calendarDay(day)
                            } else {
                                Color.clear.frame(height: 44).accessibilityHidden(true)
                            }
                        }
                    }
                    calendarStatus
                }
                .frame(
                    width: CGFloat(
                        ExampleAuxiliaryLayout.calendarContentWidth(
                            availableWidth: Double(proxy.size.width))))
            }
        }
        .frame(minHeight: 430)
        .accessibilityIdentifier("cloudStorage.calendar")
    }

    private func calendarDay(_ day: Int) -> some View {
        let available = hasRecording(day: day)
        let selected = isSelected(day: day)
        let date = dateText(day: day)
        return Button(action: { select(day: day) }) {
            VStack(spacing: 4) {
                Text("\(day)")
                    .font(.body.weight(.semibold))
                    .minimumScaleFactor(0.8)
                Circle()
                    .fill(available ? (selected ? Color.white : ExampleColors.primary) : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .foregroundColor(selected ? .white : available ? ExampleColors.primary : .gray)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(selected ? ExampleColors.primary : ExampleColors.inputSurface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(flow.daysQuerying || !available)
        .accessibilityLabel("\(date)，\(available ? "有录像" : "无录像")")
        .accessibilityValue(selected ? "已选择" : "未选择")
        .accessibilityIdentifier("cloudStorage.calendar.day.\(date)")
    }

    @ViewBuilder
    private var calendarStatus: some View {
        if flow.daysQuerying {
            ProgressView("月份正在加载")
                .frame(minHeight: 44)
                .accessibilityIdentifier("cloudStorage.calendar.loading")
        } else if let code = flow.daysQueryCode, code != TiCloudStorageErrorCode.ok {
            VStack(spacing: 8) {
                Text("月份查询失败：\(code)")
                Button("重试月份") { queryVisibleMonth() }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("cloudStorage.calendar.retry")
            }
        } else {
            Text("\(flow.recordingDays.filter(\.hasRecording).count) 天有录像，灰色日期不可选择")
                .font(.footnote)
                .foregroundColor(ExampleColors.textSecondary)
                .frame(minHeight: 44)
                .accessibilityIdentifier("cloudStorage.calendar.status")
        }
    }

    private func querySelectedWindow() {
        let environment = ProcessInfo.processInfo.environment
        if let start = environment["TIRTC_STORE_QUERY_START_MS"].flatMap(Int64.init),
            let end = environment["TIRTC_STORE_QUERY_END_MS"].flatMap(Int64.init), end > start
        {
            flow.query(startTimeMs: start, endTimeMs: end)
            return
        }
        let start = cloudStorageCalendar.startOfDay(for: selectedDate)
        let end =
            cloudStorageCalendar.date(byAdding: .day, value: 1, to: start)
            ?? start.addingTimeInterval(86_400)
        flow.query(
            startTimeMs: Int64(start.timeIntervalSince1970 * 1000),
            endTimeMs: Int64(end.timeIntervalSince1970 * 1000)
        )
    }

    private func closeAndDismiss() {
        guard !cleaning else { return }
        cleaning = true
        Task { @MainActor in
            _ = await flow.close()
            _ = TiCloudStorage.shutdown()
            presentationMode.wrappedValue.dismiss()
        }
    }

    private func closeWithoutDismiss() {
        guard !cleaning else { return }
        cleaning = true
        Task { @MainActor in
            _ = await flow.close()
            _ = TiCloudStorage.shutdown()
        }
    }

    private func currentTime(_ range: TiCloudStorageRecordingRange) -> Int64 {
        Int64(seekPreview ?? Double(flow.currentTimeMs ?? range.startTimeMs))
    }

    private func seekValue(_ range: TiCloudStorageRecordingRange) -> Double {
        seekPreview ?? Double(flow.currentTimeMs ?? range.startTimeMs)
    }

    private func formatTime(_ timeMs: Int64) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.timeZone = cloudStorageTimeZone
        return formatter.string(from: Date(timeIntervalSince1970: Double(timeMs) / 1000))
    }

    private var cloudStorageTimeZone: TimeZone { TimeZone(identifier: "Asia/Shanghai")! }

    private var cloudStorageCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = cloudStorageTimeZone
        return calendar
    }

    private var monthTitle: String {
        let components = cloudStorageCalendar.dateComponents([.year, .month], from: visibleMonth)
        return "\(components.year ?? 0) 年 \(components.month ?? 0) 月"
    }

    private var monthGridDays: [Int?] {
        let components = cloudStorageCalendar.dateComponents([.year, .month], from: visibleMonth)
        guard let start = cloudStorageCalendar.date(from: components),
            let range = cloudStorageCalendar.range(of: .day, in: .month, for: start)
        else { return [] }
        let leading = cloudStorageCalendar.component(.weekday, from: start) - 1
        return Array(repeating: nil, count: leading) + range.map(Optional.some)
    }

    private func dateText(day: Int) -> String {
        let components = cloudStorageCalendar.dateComponents([.year, .month], from: visibleMonth)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, day)
    }

    private func hasRecording(day: Int) -> Bool {
        flow.recordingDays.contains { $0.date == dateText(day: day) && $0.hasRecording }
    }

    private func isSelected(day: Int) -> Bool {
        let selected = cloudStorageCalendar.dateComponents(
            [.year, .month, .day], from: selectedDate)
        let visible = cloudStorageCalendar.dateComponents([.year, .month], from: visibleMonth)
        return selected.year == visible.year && selected.month == visible.month
            && selected.day == day
    }

    private func select(day: Int) {
        var components = cloudStorageCalendar.dateComponents([.year, .month], from: visibleMonth)
        components.day = day
        guard let date = cloudStorageCalendar.date(from: components) else { return }
        selectedDate = date
        querySelectedWindow()
    }

    private func changeVisibleMonth(by value: Int) {
        guard let next = cloudStorageCalendar.date(byAdding: .month, value: value, to: visibleMonth)
        else { return }
        visibleMonth = next
        queryVisibleMonth()
    }

    private func queryVisibleMonth() {
        let components = cloudStorageCalendar.dateComponents([.year, .month], from: visibleMonth)
        guard let start = cloudStorageCalendar.date(from: components),
            let range = cloudStorageCalendar.range(of: .day, in: .month, for: start),
            let last = range.last
        else { return }
        flow.queryDays(startDate: dateText(day: 1), endDate: dateText(day: last))
    }
}

#if os(iOS)
    private struct TiCloudStorageExampleVideoSurface: UIViewRepresentable {
        let output: TiCloudStorageVideoOutput

        func makeUIView(context: Context) -> UIView {
            let view = UIView()
            view.backgroundColor = .black
            _ = output.attachView(view)
            return view
        }

        func updateUIView(_ uiView: UIView, context: Context) { _ = output.attachView(uiView) }
        static func dismantleUIView(_ uiView: UIView, coordinator: Void) {}
    }
#elseif os(macOS)
    private struct TiCloudStorageExampleVideoSurface: NSViewRepresentable {
        let output: TiCloudStorageVideoOutput

        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.black.cgColor
            _ = output.attachView(view)
            return view
        }

        func updateNSView(_ nsView: NSView, context: Context) { _ = output.attachView(nsView) }
        static func dismantleNSView(_ nsView: NSView, coordinator: Void) {}
    }
#endif

@MainActor
extension ExampleSessionController {
    func currentClientConfiguration(tokenOverride: String? = nil) -> Result<
        ExampleClientConfiguration, ExampleValidationError
    > {
        let audioResult = ExamplePayloadParser.parseOptionalStreamId(
            audioStreamId,
            fieldName: "audio_stream_id"
        )
        let videoResults = videoStreamIds.map {
            ExamplePayloadParser.parseOptionalStreamId($0, fieldName: "video_stream_id")
        }
        if case .failure(let error) = audioResult { return .failure(error) }
        var videos: [UInt8] = []
        for result in videoResults {
            switch result {
            case .failure(let error): return .failure(error)
            case .success(let value): if let value { videos.append(value) }
            }
        }
        guard Set(videos).count == videos.count, videos.count <= 3 else {
            return .failure(.invalidStreamId("video_stream_id"))
        }
        switch audioResult {
        case .failure(let error): return .failure(error)
        case .success(let audio):
            guard audio.map({ !videos.contains($0) }) ?? true else {
                return .failure(.invalidStreamId("audio_stream_id"))
            }
            return ExampleClientConfiguration(
                appId: appId,
                endpoint: endpoint,
                remoteId: remoteId,
                audioStreamId: audio,
                videoStreamIds: videos,
                token: tokenOverride ?? token
            ).validated()
        }
    }

    func currentClientConfiguration() -> Result<ExampleClientConfiguration, ExampleValidationError> {
        currentClientConfiguration(tokenOverride: nil)
    }

    func clientConfigurationFromEnvironment() -> ExampleClientConfiguration? {
        let environment = ProcessInfo.processInfo.environment
        if let json = environment["TIRTC_EXAMPLE_PAYLOAD_JSON"] {
            return tryResult(ExamplePayloadParser.parseClientQRCode(json, preserving: endpoint))
        }
        guard let remoteId = environment["TIRTC_EXAMPLE_REMOTE_ID"],
            let token = environment["TIRTC_EXAMPLE_TOKEN"]
        else {
            return nil
        }

        let legacyStreamId = environment["TIRTC_EXAMPLE_STREAM_ID"].flatMap { UInt8($0) }
        let configuration = ExampleClientConfiguration(
            appId: environment["TIRTC_EXAMPLE_APP_ID"] ?? appId,
            endpoint: environment["TIRTC_EXAMPLE_ENDPOINT"] ?? endpoint,
            remoteId: remoteId,
            audioStreamId: legacyStreamId ?? StreamDefaults.audio,
            videoStreamId: legacyStreamId ?? StreamDefaults.video,
            token: token
        )
        return tryResult(configuration.validated())
    }

    func apply(_ configuration: ExampleClientConfiguration) {
        appId = configuration.appId
        endpoint = configuration.endpoint
        remoteId = configuration.remoteId
        audioStreamId = configuration.audioStreamId.map(String.init) ?? ""
        videoStreamIds = configuration.videoStreamIds.map(String.init)
        token = configuration.token
    }

    func persistClientSettings(_ configuration: ExampleClientConfiguration) {
        settingsStore.saveMediaSelection(
            audio: configuration.audioStreamId.map(String.init) ?? "",
            videos: configuration.videoStreamIds.map(String.init))
        settingsStore.save(
            ExampleSettingsSnapshot(
                appId: configuration.appId,
                endpoint: configuration.endpoint,
                remoteId: configuration.remoteId,
                outputBufferPolicy: ExampleOutputBufferPolicy(rawValue: outputBufferPolicy)
                    ?? .automatic,
                localAudioCodec: ExampleAudioCodec(rawValue: localAudioCodec) ?? .g711a,
                localAudioSampleRate: Int(localAudioSampleRate)
                    .flatMap { ExampleAudioSampleRate(rawValue: $0) } ?? .rate16k,
                localAudioStreamId: UInt8(localAudioStreamId) ?? StreamDefaults.audio,
                localAudioAecEnabled: localAudioAecEnabled,
                localAudioAgcLevel: Int(localAudioAgcLevel)
                    .flatMap { ExampleLocalAudioProcessingLevel(rawValue: $0) } ?? .disabled,
                localAudioAnsLevel: Int(localAudioAnsLevel)
                    .flatMap { ExampleLocalAudioProcessingLevel(rawValue: $0) } ?? .disabled,
                decoderPreference: ExampleVideoDecoderPreference(rawValue: decoderPreference)
                    ?? .automatic,
                consoleLogEnabled: consoleLogEnabled
            ))
    }

    func loadSettings() {
        let snapshot = settingsStore.load()
        if !snapshot.appId.isEmpty {
            appId = snapshot.appId
        }
        endpoint = snapshot.endpoint
        remoteId = snapshot.remoteId
        if let media = settingsStore.loadMediaSelection() {
            audioStreamId = media.audio
            videoStreamIds = media.videos
        } else {
            audioStreamId = String(StreamDefaults.audio)
            videoStreamIds = [String(StreamDefaults.video)]
        }
        outputBufferPolicy = snapshot.outputBufferPolicy.rawValue
        localAudioCodec = snapshot.localAudioCodec.rawValue
        localAudioSampleRate = String(snapshot.localAudioSampleRate.rawValue)
        localAudioStreamId =
            snapshot.localAudioStreamId == 0
            ? String(StreamDefaults.audio) : String(snapshot.localAudioStreamId)
        localAudioAecEnabled = snapshot.localAudioAecEnabled
        localAudioAgcLevel = String(snapshot.localAudioAgcLevel.rawValue)
        localAudioAnsLevel = String(snapshot.localAudioAnsLevel.rawValue)
        decoderPreference = snapshot.decoderPreference.rawValue
        consoleLogEnabled = snapshot.consoleLogEnabled
    }

    func persistCurrentSettings() {
        settingsStore.saveMediaSelection(audio: audioStreamId, videos: videoStreamIds)
        settingsStore.save(
            ExampleSettingsSnapshot(
                appId: appId,
                endpoint: endpoint,
                remoteId: remoteId,
                outputBufferPolicy: ExampleOutputBufferPolicy(rawValue: outputBufferPolicy)
                    ?? .automatic,
                localAudioCodec: ExampleAudioCodec(rawValue: localAudioCodec) ?? .g711a,
                localAudioSampleRate: Int(localAudioSampleRate)
                    .flatMap { ExampleAudioSampleRate(rawValue: $0) } ?? .rate16k,
                localAudioStreamId: UInt8(localAudioStreamId) ?? StreamDefaults.audio,
                localAudioAecEnabled: localAudioAecEnabled,
                localAudioAgcLevel: Int(localAudioAgcLevel)
                    .flatMap { ExampleLocalAudioProcessingLevel(rawValue: $0) } ?? .disabled,
                localAudioAnsLevel: Int(localAudioAnsLevel)
                    .flatMap { ExampleLocalAudioProcessingLevel(rawValue: $0) } ?? .disabled,
                decoderPreference: ExampleVideoDecoderPreference(rawValue: decoderPreference)
                    ?? .automatic,
                consoleLogEnabled: consoleLogEnabled
            ))
    }

    func showValidationError(_ error: ExampleValidationError) {
        let message: String
        switch error {
        case .invalidJSON:
            message = "payload is not valid JSON"
        case .missingRequiredField(let field):
            message = "\(field) is required"
        case .invalidEndpoint:
            message = "endpoint must be http or https"
        case .invalidStreamId(let field):
            message = "\(field) must be 0...255"
        }
        errorSummary = message
        if isClientPlayerActive {
            isClientConnecting = false
        }
        setStatus(message)
    }

    func tryResult<T>(_ result: Result<T, ExampleValidationError>) -> T? {
        if case .success(let value) = result {
            return value
        }
        return nil
    }

    func setStatus(_ text: String) {
        statusText = text
        print("[Example] \(text)")
        fflush(stdout)
        appendStatusLogLine(text)
    }

    func showUserFacingError(code: Int32, context: String) {
        errorSummary = "\(context): \(code)"
        if isClientPlayerActive {
            isClientConnecting = false
        }
        appendStatusLogLine(
            "user-facing-error context=\(context) code=\(code) summary=\(errorSummary ?? "")")
    }

    func clearUserFacingError() {
        errorSummary = nil
    }

    func appendStatusLogLine(_ text: String) {
        guard let statusLogURL else {
            return
        }

        let directoryURL = statusLogURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            print("[Example] status-log-dir-create-failed \(error.localizedDescription)")
            fflush(stdout)
            return
        }

        let line = text + "\n"
        guard let data = line.data(using: .utf8) else {
            return
        }

        if !FileManager.default.fileExists(atPath: statusLogURL.path) {
            _ = FileManager.default.createFile(
                atPath: statusLogURL.path, contents: nil, attributes: nil)
        }

        guard let handle = FileHandle(forWritingAtPath: statusLogURL.path) else {
            print("[Example] status-log-open-failed path=\(statusLogURL.path)")
            fflush(stdout)
            return
        }

        defer {
            handle.closeFile()
        }

        handle.seekToEndOfFile()
        handle.write(data)
    }
}
