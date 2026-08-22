import Foundation
import Photos
import SwiftUI
import TiRTC

#if os(iOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif

private enum TiStoreExampleMedia {
    case recording(TiStoreRecordingFile)
    case snapshot(TiStoreSnapshotFile)

    var path: String {
        switch self {
        case .recording(let file): file.path
        case .snapshot(let file): file.path
        }
    }

    var isVideo: Bool {
        if case .recording = self { return true }
        return false
    }

    func delete() async -> Int32 {
        switch self {
        case .recording(let file): await file.delete()
        case .snapshot(let file): await file.delete()
        }
    }
}

@MainActor
final class TiStoreExampleFlow: NSObject, ObservableObject, TiStoreAudioOutputDelegate,
    TiStoreVideoOutputDelegate
{
    private let store: TiStore
    let replay: TiStoreReplay
    let audioOutput = TiStoreAudioOutput()
    let videoOutput = TiStoreVideoOutput()
    let audioChannelId: UInt8
    let videoChannelId: UInt8

    @Published private(set) var recordings: [TiStoreRecordingRange] = []
    @Published private(set) var recordingDays: [TiStoreRecordingDay] = []
    @Published private(set) var selected: TiStoreRecordingRange?
    @Published private(set) var currentTimeMs: Int64?
    @Published private(set) var videoState: TiStoreVideoOutputState = .idle
    @Published private(set) var status = "请选择录像"
    @Published private(set) var querying = false
    @Published private(set) var daysQuerying = false
    @Published private(set) var daysQueryCode: Int32?
    @Published private(set) var mediaBusy = false
    @Published private(set) var recording = false
    @Published private(set) var exporting = false
    @Published private(set) var paused = false
    @Published private(set) var muted = false
    @Published private(set) var speed: TiStoreReplaySpeed = .x1
    @Published private(set) var hasLatestMedia = false
    @Published private(set) var uploadingLogs = false

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
    private var recordingTask: TiStoreRecordingTask?
    private var exportTask: TiStoreExportTask?
    private var exportWaiters: [CheckedContinuation<Void, Never>] = []
    private var latestMedia: TiStoreExampleMedia?
    private var queryTask: Task<Void, Never>?
    private var queuedQuery: (startTimeMs: Int64, endTimeMs: Int64)?
    private var queryGeneration = 0
    private var daysQueryTask: Task<Void, Never>?
    private var queuedDaysQuery: (startDate: String, endDate: String)?
    private var daysQueryGeneration = 0
    private var mediaTask: Task<Void, Never>?
    private var controlTask: Task<Void, Never>?
    private var closing = false

    init(token: String, audioChannelId: UInt8, videoChannelId: UInt8) {
        store = TiStore(token: token)
        replay = store.createReplay()
        self.audioChannelId = audioChannelId
        self.videoChannelId = videoChannelId
        super.init()
        audioOutput.delegate = self
        videoOutput.delegate = self
        replay.onTimeChanged = { [weak self] timeMs in
            self?.currentTimeMs = timeMs
        }
        replay.onCompleted = { [weak self] in
            self?.videoState = .completed
        }
        replay.onError = { [weak self] code in
            self?.videoState = .failed
            self?.status = "播放失败：\(code)"
        }
    }

    func query(startTimeMs: Int64, endTimeMs: Int64) {
        guard !closing else { return }
        queryGeneration += 1
        queuedQuery = (startTimeMs, endTimeMs)
        querying = true
        status = "正在查询…"
        recordings = []
        guard queryTask == nil else { return }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled, let request = queuedQuery {
                queuedQuery = nil
                let generation = queryGeneration
                let result = await store.listRecordings(
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
                status =
                    result.code == TiStoreErrorCode.ok
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
                let result = await store.listRecordingDays(
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

    func play(_ range: TiStoreRecordingRange) {
        guard !closing else { return }
        if !outputsAttached {
            var code = videoOutput.attach(replay: replay, channelId: videoChannelId)
            if code == TiStoreErrorCode.ok {
                code = audioOutput.attach(replay: replay, channelId: audioChannelId)
            }
            guard code == TiStoreErrorCode.ok else {
                status = "输出绑定失败：\(code)"
                return
            }
            outputsAttached = true
        }
        let code = replay.play(startTimeMs: range.startTimeMs, endTimeMs: range.endTimeMs)
        if code == TiStoreErrorCode.ok {
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
                self?.status = code == TiStoreErrorCode.ok ? "已跳转" : "跳转失败：\(code)"
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
                if code == TiStoreErrorCode.ok { paused.toggle() }
                status = code == TiStoreErrorCode.ok ? (paused ? "已暂停" : "继续播放") : "暂停操作失败：\(code)"
            }
        )
    }

    func setSpeed(_ next: TiStoreReplaySpeed) {
        let replay = replay
        let rawValue = next.rawValue
        performReplayControl(
            operation: {
                replay.setSpeed(TiStoreReplaySpeed(rawValue: rawValue) ?? .x1)
            },
            completion: { [weak self] code in
                guard let self else { return }
                if code == TiStoreErrorCode.ok { speed = next }
                status = code == TiStoreErrorCode.ok ? "播放倍速：\(next.label)" : "倍速设置失败：\(code)"
            }
        )
    }

    func toggleMute() {
        let next = !muted
        let code = audioOutput.setVolume(next ? 0 : 100)
        if code == TiStoreErrorCode.ok { muted = next }
        status = code == TiStoreErrorCode.ok ? (muted ? "已静音" : "已恢复声音") : "音量设置失败：\(code)"
    }

    func takeSnapshot() {
        guard selected != nil, !mediaBusy else { return }
        mediaBusy = true
        mediaTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await videoOutput.takeSnapshot()
            if let file = result.file, result.code == TiStoreErrorCode.ok {
                await replaceLatest(.snapshot(file))
            }
            mediaBusy = false
            mediaTask = nil
            status = result.code == TiStoreErrorCode.ok ? "截图完成" : "截图失败：\(result.code)"
        }
    }

    func toggleRecording() {
        guard selected != nil, !mediaBusy else { return }
        if let task = recordingTask {
            recordingTask = nil
            recording = false
            mediaBusy = true
            mediaTask = Task { @MainActor [weak self] in
                guard let self else { return }
                let result = await task.stop()
                if let file = result.file, result.code == TiStoreErrorCode.ok {
                    await replaceLatest(.recording(file))
                }
                mediaBusy = false
                mediaTask = nil
                status = result.code == TiStoreErrorCode.ok ? "边播边录完成" : "边播边录失败：\(result.code)"
            }
            return
        }
        let result = replay.startRecording(
            videoChannelId: Int(videoChannelId),
            audioChannelId: NSNumber(value: audioChannelId)
        )
        recordingTask = result.task
        recording = result.code == TiStoreErrorCode.ok && result.task != nil
        status = recording ? "边播边录已开始" : "边播边录启动失败：\(result.code)"
    }

    func export(_ range: TiStoreRecordingRange) {
        guard exportTask == nil, !closing else { return }
        let request = TiStoreExportRequest(
            startTimeMs: range.startTimeMs,
            endTimeMs: range.endTimeMs,
            videoChannelId: Int(videoChannelId),
            audioChannelId: NSNumber(value: audioChannelId)
        )
        let started = store.exportRecording(
            request,
            progress: { [weak self] progress in
                Task { @MainActor in self?.status = "范围下载 \(Int(progress * 100))%" }
            },
            completion: { [weak self] result in
                Task { @MainActor in await self?.finishExport(result) }
            }
        )
        exportTask = started.task
        exporting = started.code == TiStoreErrorCode.ok && started.task != nil
        status = exporting ? "范围下载已开始" : "范围下载启动失败：\(started.code)"
    }

    func saveLatestToGallery() {
        guard let media = latestMedia, !mediaBusy else { return }
        mediaBusy = true
        mediaTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let copyCode = await publishToPhotos(media)
            let code: Int32
            if copyCode == TiStoreErrorCode.ok {
                code = await media.delete()
                if code == TiStoreErrorCode.ok, latestMedia?.path == media.path {
                    latestMedia = nil
                    hasLatestMedia = false
                }
            } else {
                code = copyCode
            }
            mediaBusy = false
            mediaTask = nil
            status = code == TiStoreErrorCode.ok ? "已保存到系统相册" : "保存到相册失败：\(code)"
        }
    }

    func uploadLogs() {
        guard !uploadingLogs else { return }
        uploadingLogs = true
        let code = TiRtcLogging.upload { [weak self] result in
            Task { @MainActor in
                self?.uploadingLogs = false
                self?.status = result.succeeded ? "日志上传完成：\(result.logId ?? "")" : "日志上传失败：\(result.code)"
            }
        }
        if code != TiStoreErrorCode.ok {
            uploadingLogs = false
            status = "日志上传启动失败：\(code)"
        }
    }

    func close() async -> Int32 {
        guard !closing else { return TiStoreErrorCode.ok }
        closing = true
        queryGeneration += 1
        daysQueryGeneration += 1
        queuedQuery = nil
        queuedDaysQuery = nil
        var code = TiStoreErrorCode.ok
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
        code = firstError(code, audioOutput.detach())
        code = firstError(code, videoOutput.detach())
        code = firstError(code, videoOutput.detachView())
        code = firstError(code, audioOutput.dispose())
        code = firstError(code, videoOutput.dispose())
        code = firstError(code, replay.dispose())
        code = firstError(code, store.dispose())
        return code
    }

    nonisolated func audioOutput(_ output: TiStoreAudioOutput, didChangeState state: TiStoreAudioOutputState) {}

    nonisolated func audioOutput(_ output: TiStoreAudioOutput, didFailWithCode code: Int32) {
        Task { @MainActor [weak self] in self?.status = "音频输出失败：\(code)" }
    }

    nonisolated func videoOutput(_ output: TiStoreVideoOutput, didChangeState state: TiStoreVideoOutputState) {
        let rawValue = state.rawValue
        Task { @MainActor [weak self] in
            let next = TiStoreVideoOutputState(rawValue: rawValue) ?? .failed
            self?.videoState = next
            if next == .failed { self?.status = "视频输出失败" }
        }
    }

    nonisolated func videoOutput(_ output: TiStoreVideoOutput, didFailWithCode code: Int32) {
        Task { @MainActor [weak self] in self?.status = "视频输出失败：\(code)" }
    }

    private func replaceLatest(_ next: TiStoreExampleMedia) async {
        let previous = latestMedia
        latestMedia = next
        hasLatestMedia = true
        if let previous, previous.path != next.path { _ = await previous.delete() }
    }

    private func finishExport(_ result: TiStoreRecordingResult) async {
        exportTask = nil
        exporting = false
        if let file = result.file, result.code == TiStoreErrorCode.ok {
            if closing {
                _ = await file.delete()
            } else {
                await replaceLatest(.recording(file))
            }
        }
        status = result.code == TiStoreErrorCode.ok ? "范围下载完成" : "范围下载失败：\(result.code)"
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

    private func publishToPhotos(_ media: TiStoreExampleMedia) async -> Int32 {
        await Self.publishToPhotos(path: media.path, isVideo: media.isVideo)
    }

    nonisolated private static func publishToPhotos(path: String, isVideo: Bool) async -> Int32 {
        var authorization = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if authorization == .notDetermined {
            authorization = await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { continuation.resume(returning: $0) }
            }
        }
        guard authorization == .authorized || authorization == .limited else {
            return TiStoreErrorCode.permissionDenied
        }
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                let url = URL(fileURLWithPath: path)
                if isVideo {
                    _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                } else {
                    _ = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
                }
            } completionHandler: { success, _ in
                continuation.resume(returning: success ? TiStoreErrorCode.ok : TiStoreErrorCode.fileWriteFailed)
            }
        }
    }

    private func firstError(_ current: Int32, _ next: Int32) -> Int32 {
        if next == TiStoreErrorCode.ok || next == TiStoreErrorCode.notStarted || next == TiStoreErrorCode.notBound {
            return current
        }
        return current == TiStoreErrorCode.ok ? next : current
    }
}

extension TiStoreReplaySpeed {
    fileprivate var label: String {
        switch self {
        case .x1: "x1"
        case .x2: "x2"
        case .x4: "x4"
        case .x8: "x8"
        @unknown default: "x1"
        }
    }
}

extension TiStoreVideoOutputState {
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
}

struct TiStoreExampleView: View {
    @Environment(\.presentationMode) private var presentationMode
    @StateObject private var flow: TiStoreExampleFlow
    @State private var initCode: Int32
    @State private var selectedDate = Date()
    @State private var visibleMonth = Date()
    @State private var recordingsPresented = false
    @State private var seekPreview: Double?
    @State private var cleaning = false

    init(appId: String, endpoint: String, token: String, audioChannelId: UInt8, videoChannelId: UInt8) {
        let code = TiStore.initialize(
            appId: appId.trimmingCharacters(in: .whitespacesAndNewlines),
            endpoint: endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
            consoleLogEnabled: false
        )
        _initCode = State(initialValue: code)
        _flow = StateObject(
            wrappedValue: TiStoreExampleFlow(
                token: token.trimmingCharacters(in: .whitespacesAndNewlines),
                audioChannelId: audioChannelId,
                videoChannelId: videoChannelId
            ))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(action: closeAndDismiss) {
                    Text("关闭")
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("store.close")
                Text("云录像")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(ExampleColors.primary)
                    .accessibilityIdentifier("store.player.page")
                Spacer()
                Button(action: { recordingsPresented = true }) {
                    Text("选择录像")
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(initCode != TiStoreErrorCode.ok)
                .accessibilityIdentifier("store.recordings")
                Button(action: { flow.uploadLogs() }) {
                    Text(flow.uploadingLogs ? "上传中…" : "上传日志")
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(flow.uploadingLogs)
                .accessibilityIdentifier("store.upload_logs")
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(ExampleColors.background)

            ZStack {
                TiStoreExampleVideoSurface(output: flow.videoOutput)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                LinearGradient(
                    colors: [Color.black.opacity(0.35), .clear, Color.black.opacity(0.68)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                if flow.selected == nil || flow.videoState != .rendering {
                    Text(initCode == TiStoreErrorCode.ok ? flow.stageStatus : "初始化失败：\(initCode)")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(18)
                        .background(Color.black.opacity(0.48))
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                }
                VStack {
                    Spacer()
                    storeControls
                }
                .padding(20)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("store.video_stage")
            .accessibilityLabel(flow.videoState.accessibilityLabel)
            .accessibilityValue(flow.videoState.accessibilityLabel)
        }
        .frame(minWidth: 320, minHeight: 560)
        .background(ExampleColors.background)
        .sheet(isPresented: $recordingsPresented) { recordingsSheetContainer }
        .onAppear {
            guard initCode == TiStoreErrorCode.ok else { return }
            recordingsPresented = true
            queryVisibleMonth()
            querySelectedWindow()
        }
        .onDisappear { closeWithoutDismiss() }
    }

    private var storeControls: some View {
        VStack(alignment: .trailing, spacing: 12) {
            if let range = flow.selected {
                HStack {
                    Text(formatTime(currentTime(range)))
                    Slider(
                        value: Binding(
                            get: { seekValue(range) },
                            set: { seekPreview = $0 }
                        ),
                        in: Double(range.startTimeMs)...Double(max(range.startTimeMs + 1, range.endTimeMs - 1)),
                        onEditingChanged: { editing in
                            guard !editing, let seekPreview else { return }
                            flow.seek(to: Int64(seekPreview))
                            self.seekPreview = nil
                        }
                    )
                    .accessibilityIdentifier("store.seek")
                    Text(formatTime(range.endTimeMs))
                }
                .font(.system(size: 12))
                .foregroundColor(.white)
                .padding(12)
                .background(Color.black.opacity(0.48))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            HStack(spacing: 10) {
                storeAction(flow.recording ? "停止本地保存" : "开始本地保存", "store.recording") {
                    flow.toggleRecording()
                }
                storeAction("截图", "store.snapshot") { flow.takeSnapshot() }
                storeAction("保存到系统相册", "store.gallery", enabled: flow.hasLatestMedia) {
                    flow.saveLatestToGallery()
                }
            }
            HStack(spacing: 10) {
                storeAction(flow.muted ? "恢复声音" : "静音", "store.mute", enabled: flow.speed == .x1) {
                    flow.toggleMute()
                }
                Picker("倍速", selection: Binding(get: { flow.speed }, set: { flow.setSpeed($0) })) {
                    Text("x1").tag(TiStoreReplaySpeed.x1)
                    Text("x2").tag(TiStoreReplaySpeed.x2)
                    Text("x4").tag(TiStoreReplaySpeed.x4)
                    Text("x8").tag(TiStoreReplaySpeed.x8)
                }
                .pickerStyle(.menu)
                .disabled(flow.selected == nil)
                .accessibilityIdentifier("store.speed")
                storeAction(flow.paused ? "继续播放" : "暂停播放", "store.pause") { flow.togglePause() }
            }
            Text(flow.status)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.82))
                .accessibilityIdentifier("store.status")
        }
    }

    private var recordingsSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("选择录像").font(.system(size: 20, weight: .bold))
                Spacer()
                Button(action: { recordingsPresented = false }) {
                    Text("关闭")
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("store.recordings.close")
            }
            recordingCalendar
            Divider()
            if flow.recordings.isEmpty {
                Text(flow.querying ? "正在查询…" : "当天没有可用录像")
                    .foregroundColor(ExampleColors.textSecondary)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(Array(flow.recordings.enumerated()), id: \.offset) { _, range in
                            HStack {
                                Button("\(formatTime(range.startTimeMs)) — \(formatTime(range.endTimeMs))") {
                                    recordingsPresented = false
                                    flow.play(range)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("store.play.\(range.startTimeMs)")
                                Spacer()
                                Button(flow.exporting ? "下载中…" : "下载") { flow.export(range) }
                                    .disabled(flow.exporting)
                                    .accessibilityIdentifier("store.export.\(range.startTimeMs)")
                            }
                            .padding(10)
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 320, minHeight: 420)
        .background(ExampleColors.background)
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
        VStack(spacing: 8) {
            HStack {
                Button("‹") { changeVisibleMonth(by: -1) }
                    .disabled(flow.daysQuerying)
                    .accessibilityIdentifier("store.calendar.previous")
                Spacer()
                Text(monthTitle)
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button("›") { changeVisibleMonth(by: 1) }
                    .disabled(flow.daysQuerying)
                    .accessibilityIdentifier("store.calendar.next")
            }
            HStack(spacing: 4) {
                ForEach(["日", "一", "二", "三", "四", "五", "六"], id: \.self) { value in
                    Text(value)
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(Array(monthGridDays.enumerated()), id: \.offset) { _, day in
                    if let day {
                        let available = hasRecording(day: day)
                        let selected = isSelected(day: day)
                        Button(action: { select(day: day) }) {
                            VStack(spacing: 2) {
                                Text("\(day)").font(.system(size: 13, weight: .semibold))
                                Text(available ? "有录像" : "无录像").font(.system(size: 8))
                            }
                            .foregroundColor(selected ? .white : available ? ExampleColors.primary : .gray)
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .background(selected ? ExampleColors.primary : ExampleColors.inputSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .disabled(flow.daysQuerying || !available)
                        .accessibilityIdentifier("store.calendar.day.\(dateText(day: day))")
                    } else {
                        Color.clear.frame(minHeight: 42)
                    }
                }
            }
            if flow.daysQuerying {
                ProgressView("月份正在加载")
                    .accessibilityIdentifier("store.calendar.loading")
            } else if let code = flow.daysQueryCode, code != TiStoreErrorCode.ok {
                VStack(spacing: 8) {
                    Text("月份查询失败：\(code)")
                    Button("重试月份") { queryVisibleMonth() }
                        .accessibilityIdentifier("store.calendar.retry")
                }
            } else {
                Text("\(flow.recordingDays.filter(\.hasRecording).count) 天有录像，灰色日期不可选择")
                    .font(.system(size: 11))
                    .foregroundColor(ExampleColors.textSecondary)
            }
        }
        .accessibilityIdentifier("store.calendar")
    }

    private func storeAction(
        _ title: String,
        _ identifier: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(ExampleColors.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.92))
            .clipShape(Capsule())
            .disabled(flow.selected == nil || flow.mediaBusy || !enabled)
            .opacity(flow.selected == nil || flow.mediaBusy || !enabled ? 0.55 : 1)
            .accessibilityIdentifier(identifier)
    }

    private func querySelectedWindow() {
        let environment = ProcessInfo.processInfo.environment
        if let start = environment["TIRTC_STORE_QUERY_START_MS"].flatMap(Int64.init),
            let end = environment["TIRTC_STORE_QUERY_END_MS"].flatMap(Int64.init), end > start
        {
            flow.query(startTimeMs: start, endTimeMs: end)
            return
        }
        let start = storeCalendar.startOfDay(for: selectedDate)
        let end = storeCalendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
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
            _ = TiStore.shutdown()
            presentationMode.wrappedValue.dismiss()
        }
    }

    private func closeWithoutDismiss() {
        guard !cleaning else { return }
        cleaning = true
        Task { @MainActor in
            _ = await flow.close()
            _ = TiStore.shutdown()
        }
    }

    private func currentTime(_ range: TiStoreRecordingRange) -> Int64 {
        Int64(seekPreview ?? Double(flow.currentTimeMs ?? range.startTimeMs))
    }

    private func seekValue(_ range: TiStoreRecordingRange) -> Double {
        seekPreview ?? Double(flow.currentTimeMs ?? range.startTimeMs)
    }

    private func formatTime(_ timeMs: Int64) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.timeZone = storeTimeZone
        return formatter.string(from: Date(timeIntervalSince1970: Double(timeMs) / 1000))
    }

    private var storeTimeZone: TimeZone { TimeZone(identifier: "Asia/Shanghai")! }

    private var storeCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = storeTimeZone
        return calendar
    }

    private var monthTitle: String {
        let components = storeCalendar.dateComponents([.year, .month], from: visibleMonth)
        return "\(components.year ?? 0) 年 \(components.month ?? 0) 月"
    }

    private var monthGridDays: [Int?] {
        let components = storeCalendar.dateComponents([.year, .month], from: visibleMonth)
        guard let start = storeCalendar.date(from: components),
            let range = storeCalendar.range(of: .day, in: .month, for: start)
        else { return [] }
        let leading = storeCalendar.component(.weekday, from: start) - 1
        return Array(repeating: nil, count: leading) + range.map(Optional.some)
    }

    private func dateText(day: Int) -> String {
        let components = storeCalendar.dateComponents([.year, .month], from: visibleMonth)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, day)
    }

    private func hasRecording(day: Int) -> Bool {
        flow.recordingDays.contains { $0.date == dateText(day: day) && $0.hasRecording }
    }

    private func isSelected(day: Int) -> Bool {
        let selected = storeCalendar.dateComponents([.year, .month, .day], from: selectedDate)
        let visible = storeCalendar.dateComponents([.year, .month], from: visibleMonth)
        return selected.year == visible.year && selected.month == visible.month && selected.day == day
    }

    private func select(day: Int) {
        var components = storeCalendar.dateComponents([.year, .month], from: visibleMonth)
        components.day = day
        guard let date = storeCalendar.date(from: components) else { return }
        selectedDate = date
        querySelectedWindow()
    }

    private func changeVisibleMonth(by value: Int) {
        guard let next = storeCalendar.date(byAdding: .month, value: value, to: visibleMonth) else { return }
        visibleMonth = next
        queryVisibleMonth()
    }

    private func queryVisibleMonth() {
        let components = storeCalendar.dateComponents([.year, .month], from: visibleMonth)
        guard let start = storeCalendar.date(from: components),
            let range = storeCalendar.range(of: .day, in: .month, for: start),
            let last = range.last
        else { return }
        flow.queryDays(startDate: dateText(day: 1), endDate: dateText(day: last))
    }
}

#if os(iOS)
    private struct TiStoreExampleVideoSurface: UIViewRepresentable {
        let output: TiStoreVideoOutput

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
    private struct TiStoreExampleVideoSurface: NSViewRepresentable {
        let output: TiStoreVideoOutput

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
        let videoResult = ExamplePayloadParser.parseOptionalStreamId(
            videoStreamId,
            fieldName: "video_stream_id"
        )
        switch (audioResult, videoResult) {
        case (.failure(let error), _), (_, .failure(let error)):
            return .failure(error)
        case (.success(let audio), .success(let video)):
            return ExampleClientConfiguration(
                appId: appId,
                endpoint: endpoint,
                remoteId: remoteId,
                audioStreamId: audio ?? StreamDefaults.audio,
                videoStreamId: video ?? StreamDefaults.video,
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
        audioStreamId = String(configuration.audioStreamId)
        videoStreamId = String(configuration.videoStreamId)
        token = configuration.token
    }

    func persistClientSettings(_ configuration: ExampleClientConfiguration) {
        settingsStore.save(
            ExampleSettingsSnapshot(
                appId: configuration.appId,
                endpoint: configuration.endpoint,
                remoteId: configuration.remoteId,
                audioStreamId: configuration.audioStreamId,
                videoStreamId: configuration.videoStreamId,
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
        audioStreamId =
            snapshot.audioStreamId == 0 ? String(StreamDefaults.audio) : String(snapshot.audioStreamId)
        videoStreamId =
            snapshot.videoStreamId == 0 ? String(StreamDefaults.video) : String(snapshot.videoStreamId)
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
        settingsStore.save(
            ExampleSettingsSnapshot(
                appId: appId,
                endpoint: endpoint,
                remoteId: remoteId,
                audioStreamId: UInt8(audioStreamId) ?? StreamDefaults.audio,
                videoStreamId: UInt8(videoStreamId) ?? StreamDefaults.video,
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
            _ = FileManager.default.createFile(atPath: statusLogURL.path, contents: nil, attributes: nil)
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
