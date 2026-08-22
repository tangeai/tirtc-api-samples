import SwiftUI
import TiRTC

struct ExampleClientPlayer: View {
    @ObservedObject var session: ExampleSessionController

    var body: some View {
        ExampleVideoPage(
            title: session.remoteId.isEmpty ? "Client" : session.remoteId,
            pageIdentifier: "client.player.page",
            leadingActions: {
                EmptyView()
            },
            trailingActions: {
                HStack(spacing: 0) {
                    ExamplePlayerCommandButton {
                        session.isCommandPanelPresented = true
                    }
                    .accessibilityIdentifier("client.send_command")
                    ExamplePlayerLogUploadButton(
                        title: "上传日志",
                        isUploading: session.isLogUploadInProgress
                    ) {
                        session.uploadLogs()
                    }
                    .accessibilityIdentifier("client.upload_logs")
                }
            },
            showStageOverlay: !session.isClientVideoRendering || session.errorSummary != nil,
            stageStatusLabel: session.errorSummary ?? (session.isClientConnecting ? "连接中" : "加载中"),
            stageMode: session.errorSummary == nil ? .loading : .error,
            video: {
                ExampleVideoSurface(session: session)
            },
            overlay: {
                if session.isClientVideoRendering {
                    ExampleMetricsOverlay(session: session)
                }
            },
            bottomAction: {
                ExamplePlayerControls(session: session)
            },
            showBottomSafeArea: true,
            statusValue: session.statusText,
            logUploadResult: session.logUploadResult,
            dismissLogUploadResult: {
                session.logUploadResult = nil
            }
        )
        .sheet(isPresented: $session.isCommandPanelPresented) {
            ExampleCommandPanel(session: session)
                .modifier(ExampleCommandPanelDetentModifier())
        }
    }
}

private struct ExamplePlayerControls: View {
    @ObservedObject var session: ExampleSessionController

    var body: some View {
        if #available(macOS 13.0, iOS 16.0, *) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { controls }
                VStack(alignment: .trailing, spacing: 12) {
                    HStack(spacing: 12) { mediaControls }
                    HStack(spacing: 12) { playbackControls }
                }
            }
        } else {
            VStack(alignment: .trailing, spacing: 12) {
                HStack(spacing: 12) { mediaControls }
                HStack(spacing: 12) { playbackControls }
            }
        }
    }

    @ViewBuilder private var controls: some View {
        mediaControls
        playbackControls
    }

    @ViewBuilder private var mediaControls: some View {
        ExampleMediaIconButton(
            systemImage: session.isRecording ? "stop.circle" : "record.circle",
            enabled: session.isClientVideoRendering && !session.isMediaFileBusy,
            accessibilityLabel: session.isRecording ? "停止本地保存" : "开始本地保存"
        ) { session.toggleRecording() }
        .accessibilityIdentifier("client.recording")
        ExampleMediaIconButton(
            systemImage: "camera",
            enabled: session.isClientVideoRendering && !session.isMediaFileBusy,
            accessibilityLabel: "截图"
        ) { session.takeSnapshot() }
        .accessibilityIdentifier("client.snapshot")
        ExampleMediaIconButton(
            systemImage: "photo.on.rectangle.angled",
            enabled: session.hasLatestMedia && !session.isMediaFileBusy,
            accessibilityLabel: "保存到系统相册"
        ) { session.saveLatestToGallery() }
        .accessibilityIdentifier("client.gallery")
    }

    @ViewBuilder private var playbackControls: some View {
        ExampleAudioOutputVolumeButton(
            enabled: session.conn?.state == .connected,
            muted: session.isAudioOutputMuted
        ) { session.toggleAudioOutputVolume() }
        .accessibilityIdentifier("client.audio_output_volume")
        .accessibilityValue(session.audioOutputVolumeStatus)
        ExampleLocalAudioControlButton(
            enabled: session.conn?.state == .connected,
            busy: session.isClientLocalAudioBusy,
            running: session.isClientLocalAudioRunning
        ) { session.toggleClientLocalAudio() }
        .accessibilityIdentifier("client.local_audio")
        .accessibilityValue(session.clientLocalAudioStatus)
        ExampleDownlinkControlButton(
            connecting: session.isClientConnecting,
            playing: session.isClientVideoRendering
        ) { session.stopClient() }
        .accessibilityIdentifier("client.stop")
    }
}

private struct ExampleCommandPanelDetentModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 16.0, macOS 13.0, *) {
            content
                .presentationDetents([.fraction(0.5)])
                .presentationDragIndicator(.visible)
        } else {
            content
        }
    }
}

private struct ExampleMediaIconButton: View {
    let systemImage: String
    let enabled: Bool
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(ExampleColors.primary)
                .frame(width: 48, height: 48)
                .background(ExampleColors.primary.opacity(0.16))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.55)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct ExampleVideoPage<Leading: View, Trailing: View, Video: View, Overlay: View, Bottom: View>:
    View
{
    let title: String
    let pageIdentifier: String
    let leadingActions: Leading
    let trailingActions: Trailing
    let showStageOverlay: Bool
    let stageStatusLabel: String
    let stageMode: ExampleStageIndicatorMode
    let video: Video
    let overlay: Overlay
    let bottomAction: Bottom
    let showBottomSafeArea: Bool
    let statusValue: String
    let logUploadResult: ExampleLogUploadResult?
    let dismissLogUploadResult: () -> Void

    init(
        title: String,
        pageIdentifier: String,
        @ViewBuilder leadingActions: () -> Leading,
        @ViewBuilder trailingActions: () -> Trailing,
        showStageOverlay: Bool,
        stageStatusLabel: String,
        stageMode: ExampleStageIndicatorMode,
        @ViewBuilder video: () -> Video,
        @ViewBuilder overlay: () -> Overlay,
        @ViewBuilder bottomAction: () -> Bottom,
        showBottomSafeArea: Bool,
        statusValue: String,
        logUploadResult: ExampleLogUploadResult?,
        dismissLogUploadResult: @escaping () -> Void
    ) {
        self.title = title
        self.pageIdentifier = pageIdentifier
        self.leadingActions = leadingActions()
        self.trailingActions = trailingActions()
        self.showStageOverlay = showStageOverlay
        self.stageStatusLabel = stageStatusLabel
        self.stageMode = stageMode
        self.video = video()
        self.overlay = overlay()
        self.bottomAction = bottomAction()
        self.showBottomSafeArea = showBottomSafeArea
        self.statusValue = statusValue
        self.logUploadResult = logUploadResult
        self.dismissLogUploadResult = dismissLogUploadResult
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    leadingActions
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(ExampleColors.primary)
                        .lineLimit(1)
                        .accessibilityIdentifier(pageIdentifier)
                        .accessibilityValue(statusValue)
                    Spacer()
                    trailingActions
                }
                .padding(.leading, 16)
                .frame(height: 56)
                .background(ExampleColors.background)

                ZStack {
                    ExampleDownlinkVideoStage(
                        video: video,
                        showStageOverlay: showStageOverlay,
                        stageStatusLabel: stageStatusLabel,
                        indicatorMode: stageMode
                    )
                    ExampleVideoGradient()
                    VStack(alignment: .leading, spacing: 0) {
                        overlay
                        Spacer()
                        HStack {
                            Spacer()
                            bottomAction
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let logUploadResult {
                ExampleLogUploadResultDialog(result: logUploadResult, dismiss: dismissLogUploadResult)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ExampleColors.background.ignoresSafeArea())
        .modifier(ExampleVideoPageFullscreenModifier())
    }
}

private struct ExampleLogUploadResultDialog: View {
    let result: ExampleLogUploadResult
    let dismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.34)
                .ignoresSafeArea()
            VStack(spacing: 14) {
                Text(result.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(ExampleColors.primary)
                Text(result.message)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(ExampleColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                Button(action: dismiss) {
                    Text("OK")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(ExampleColors.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("log_upload_result.ok")
            }
            .padding(18)
            .frame(width: 286)
            .background(ExampleColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .accessibilityIdentifier("log_upload_result.dialog")
            .accessibilityValue(result.message)
        }
    }
}

private struct ExampleStateProbe: View {
    let identifier: String
    let value: String

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .accessibilityIdentifier(identifier)
            .accessibilityLabel(value)
            .accessibilityValue(value)
    }
}

private struct ExampleVideoPageFullscreenModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
            content.ignoresSafeArea(.container, edges: .bottom)
        #else
            content
        #endif
    }
}

private enum ExampleStageIndicatorMode {
    case loading
    case running
    case error
}

private struct ExampleDownlinkVideoStage<Video: View>: View {
    let video: Video
    let showStageOverlay: Bool
    let stageStatusLabel: String
    let indicatorMode: ExampleStageIndicatorMode

    var body: some View {
        ZStack {
            ExampleColors.videoBackground
            video
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if showStageOverlay {
                ExampleCenterLoading(label: stageStatusLabel, mode: indicatorMode)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ExampleCenterLoading: View {
    let label: String
    let mode: ExampleStageIndicatorMode

    var body: some View {
        VStack(spacing: 12) {
            switch mode {
            case .loading:
                HStack(spacing: 7) {
                    ForEach(0..<3) { index in
                        Circle()
                            .fill(index == 1 ? Color.white : ExampleColors.primary.opacity(0.84))
                            .frame(width: 8, height: 8)
                            .shadow(color: Color.white.opacity(0.28), radius: 10)
                    }
                }
            case .running:
                Image(systemName: "record.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(ExampleColors.primary)
            case .error:
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 36))
                    .foregroundColor(ExampleColors.failure)
            }
            Text(label)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 240)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 24)
        .background(Color.black.opacity(0.46))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.white.opacity(0.11), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .shadow(color: Color.black.opacity(0.22), radius: 22, y: 10)
        .allowsHitTesting(false)
    }
}

private struct ExampleMetricsOverlay: View {
    @ObservedObject var session: ExampleSessionController
    @State private var expanded = true

    var body: some View {
        if !expanded {
            Button(action: { expanded = true }) {
                Label("即时统计", systemImage: "chart.bar.fill")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundColor(Color(red: 0.31, green: 0.53, blue: 0.85))
                    .padding(.horizontal, 12)
                    .frame(height: 26)
                    .background(Color.white)
                    .clipShape(Capsule())
                    .shadow(color: Color.black.opacity(0.14), radius: 10, y: 3)
            }
            .buttonStyle(.plain)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ExampleStateProbe(identifier: "client.metrics.overlay", value: session.metricsSummary)
                ExampleStateProbe(identifier: "client.metrics.debug_snapshot", value: session.debugSummary)
                HStack(spacing: 6) {
                    Text("即时统计")
                        .font(.system(size: 11, weight: .black))
                        .foregroundColor(Color.black.opacity(0.87))
                    Spacer()
                    Button(action: { session.isMetricsExplanationPresented = true }) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 16))
                            .foregroundColor(ExampleColors.primary)
                    }
                    .buttonStyle(.plain)
                    Button(action: { expanded = false }) {
                        Label("收起", systemImage: "chevron.up")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .frame(height: 18)
                            .background(Color(red: 0.31, green: 0.53, blue: 0.85))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 6)
                ExampleMetricLine(
                    identifier: "client.metrics.media_parameters",
                    label: "媒体参数",
                    value: session.mediaParameterSummary)
                ExampleMetricLine(
                    identifier: "client.metrics.video_receive",
                    label: "视频接收",
                    value: session.videoReceiveSummary)
                ExampleMetricLine(
                    identifier: "client.metrics.audio_receive",
                    label: "音频接收",
                    value: session.audioReceiveSummary)
                ExampleMetricLine(
                    identifier: "client.metrics.latency", label: "估算延迟",
                    value: "视频 \(session.videoOutputLatencySummary) · 音频 \(session.audioOutputLatencySummary)")
                ExampleMetricLine(
                    identifier: "client.metrics.startup", label: "启动耗时",
                    value: "连接 \(session.connectionDurationSummary) · 首帧 \(session.firstFrameDurationSummary)")
                ExampleMetricLine(
                    identifier: "client.metrics.stutter", label: "卡顿统计",
                    value:
                        "视频比例 \(session.sessionStutterRatioSummary) · \(session.sessionStutterCountSummary) / 最长 \(session.sessionStutterPeakSummary) · 音频 \(session.audioStutterSummary)",
                    maxLines: 2
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: 430)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: Color.black.opacity(0.16), radius: 14, y: 5)
            .alert(isPresented: $session.isMetricsExplanationPresented) {
                Alert(
                    title: Text("指标说明"),
                    message: Text(
                        "连接耗时表示连接建立用时；首帧等待从连接成功统计到首个视频帧显示。播放卡顿从首帧成功显示后统计，接收码率、视频 FPS 与音频 PPS 来自 Runtime 最近采样窗口；估算延迟来自当前输出延迟估算。"
                    ),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }
}

private struct ExampleMetricLine: View {
    let identifier: String
    let label: String
    let value: String
    var maxLines = 1

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text("\(label)：")
                .font(.system(size: 10, weight: .heavy))
                .foregroundColor(ExampleColors.primary)
                .lineLimit(1)
                .fixedSize()
            Text(value)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color.black.opacity(0.8))
                .lineLimit(maxLines)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier(identifier)
                .accessibilityLabel(value)
                .accessibilityValue(value)
        }
        .padding(.bottom, 4)
    }
}

private struct ExamplePlayerCommandButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("发送命令")
                .font(.system(size: 12))
                .foregroundColor(ExampleColors.primary)
                .frame(minWidth: 92, minHeight: 28)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(ExampleColors.primary, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .padding(.trailing, 8)
    }
}

private struct ExamplePlayerLogUploadButton: View {
    let title: String
    let isUploading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(isUploading ? "上传中..." : title)
                .font(.system(size: 12))
                .foregroundColor(ExampleColors.primary)
                .frame(minWidth: 84, minHeight: 28)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(ExampleColors.primary, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(isUploading)
        .opacity(isUploading ? 0.64 : 1)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .padding(.trailing, 16)
    }
}

private struct ExampleLocalAudioControlButton: View {
    let enabled: Bool
    let busy: Bool
    let running: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if busy {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .frame(width: 18, height: 18)
                } else {
                    Image(systemName: running ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: 16, weight: .semibold))
                }
                Text(running ? "停止麦克风" : "启动麦克风")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(running ? .white : ExampleColors.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(running ? Color.orange.opacity(0.95) : ExampleColors.surface)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled || busy)
        .opacity(enabled ? 1 : 0.55)
    }
}

private struct ExampleAudioOutputVolumeButton: View {
    let enabled: Bool
    let muted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(
                muted ? "恢复声音" : "静音",
                systemImage: muted ? "speaker.wave.2.fill" : "speaker.slash.fill"
            )
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(muted ? .white : ExampleColors.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(muted ? Color.orange.opacity(0.95) : ExampleColors.surface)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.55)
    }
}

private struct ExampleCommandPanel: View {
    @ObservedObject var session: ExampleSessionController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ExampleCommandConnectionPill(connected: session.conn?.state == .connected)
            HStack {
                Text("命令")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(ExampleColors.textPrimary)
                    .accessibilityIdentifier("client.command_panel")
                Spacer()
                Button("关闭") {
                    session.isCommandPanelPresented = false
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("client.command_panel.close")
            }
            ExampleCommandTextField(
                title: "命令 ID",
                text: $session.commandIdText,
                accessibilityIdentifier: "client.command_panel.command_id"
            )
            ExampleSegmentedCommandField("payload_mode") {
                Picker("payload_mode", selection: $session.commandPayloadMode) {
                    Text("HEX").tag(ExampleCommandPanelPayloadMode.hex.rawValue)
                    Text("文本").tag(ExampleCommandPanelPayloadMode.text.rawValue)
                }
                .pickerStyle(.segmented)
            }
            ExampleCommandTextField(
                title: "命令内容",
                text: $session.commandPayloadText,
                minHeight: 76,
                accessibilityIdentifier: "client.command_panel.payload"
            )
            VStack(alignment: .leading, spacing: 8) {
                Text("常用命令")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(ExampleColors.textSecondary)
                HStack(spacing: 8) {
                    ExampleCommandPresetButton(title: "Echo", identifier: "client.command_panel.echo_preset") {
                        session.applyEchoCommandPreset()
                    }
                    ExampleCommandPresetButton(
                        title: "start_call",
                        identifier: "client.command_panel.start_call_preset"
                    ) {
                        session.applyCallCommandPreset(.startCall)
                    }
                    ExampleCommandPresetButton(
                        title: "call_ready",
                        identifier: "client.command_panel.call_ready_preset"
                    ) {
                        session.applyCallCommandPreset(.callReady)
                    }
                    ExampleCommandPresetButton(
                        title: "call_reject",
                        identifier: "client.command_panel.call_reject_preset"
                    ) {
                        session.applyCallCommandPreset(.callReject)
                    }
                }
            }
            ExamplePrimaryCommandButton(title: "发送", accessibilityIdentifier: "client.command_panel.send") {
                session.sendCommandFromPanel()
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(session.commandEvents) { event in
                        Text(
                            "\(event.direction.rawValue) id=\(event.commandIdLabel)\(event.resultCode.map { " code=\($0)" } ?? "") payload=\(event.payloadHex.isEmpty ? "空" : event.payloadHex)"
                        )
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(ExampleColors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(minHeight: 90, maxHeight: 180)
        }
        .padding(20)
        .frame(minWidth: 340)
        .background(ExampleColors.background)
        .accessibilityElement(children: .contain)
    }
}

private struct ExampleCommandPresetButton: View {
    let title: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(ExampleColors.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(ExampleColors.primary.opacity(0.1))
            .clipShape(Capsule())
            .accessibilityIdentifier(identifier)
    }
}

private struct ExampleCommandConnectionPill: View {
    let connected: Bool

    var body: some View {
        Text(connected ? "已连接" : "未连接")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(connected ? ExampleColors.primary : ExampleColors.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((connected ? ExampleColors.primary : ExampleColors.textSecondary).opacity(0.1))
            .clipShape(Capsule())
            .accessibilityIdentifier("client.command_panel.connection")
    }
}

private struct ExampleCommandTextField: View {
    let title: String
    @Binding var text: String
    var minHeight: CGFloat = 54
    let accessibilityIdentifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(ExampleColors.textSecondary)
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(ExampleColors.textPrimary)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
                .background(ExampleColors.inputSurface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .accessibilityIdentifier(accessibilityIdentifier)
        }
    }
}

private struct ExampleSegmentedCommandField<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(ExampleColors.textSecondary)
            content
        }
    }
}

private struct ExamplePrimaryCommandButton: View {
    let title: String
    let accessibilityIdentifier: String
    let action: () -> Void

    init(title: String, accessibilityIdentifier: String, action: @escaping () -> Void) {
        self.title = title
        self.accessibilityIdentifier = accessibilityIdentifier
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(ExampleColors.primary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .accessibilityIdentifier(accessibilityIdentifier)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct ExampleDownlinkControlButton: View {
    let connecting: Bool
    let playing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(
                connecting ? "连接中" : (playing ? "停止播放" : "开始播放"),
                systemImage: connecting ? "circle.dotted" : (playing ? "stop.circle" : "play.circle.fill")
            )
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .background(playing ? ExampleColors.redAccent : ExampleColors.primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(connecting)
        .opacity(connecting ? 0.72 : 1)
    }
}

private struct ExampleVideoGradient: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color.black.opacity(0.46),
                Color.black.opacity(0),
                Color.black.opacity(0.6),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
    }
}

#if os(iOS)
    private struct ExampleVideoSurface: UIViewRepresentable {
        @ObservedObject var session: ExampleSessionController

        func makeUIView(context: Context) -> UIView {
            let view = UIView()
            view.backgroundColor = .black
            session.attachPlatformVideoView(view)
            return view
        }

        func updateUIView(_ uiView: UIView, context: Context) {
            session.attachPlatformVideoView(uiView)
        }
    }

#elseif os(macOS)
    private struct ExampleVideoSurface: NSViewRepresentable {
        @ObservedObject var session: ExampleSessionController

        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.black.cgColor
            session.attachPlatformVideoView(view)
            return view
        }

        func updateNSView(_ nsView: NSView, context: Context) {
            session.attachPlatformVideoView(nsView)
        }
    }

#endif
