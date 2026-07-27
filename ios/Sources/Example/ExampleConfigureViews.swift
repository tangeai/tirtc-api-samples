import SwiftUI

struct ExampleClientConfigure: View {
    @ObservedObject var session: ExampleSessionController

    var body: some View {
        #if os(iOS)
            content
                .sheet(isPresented: $session.isClientQRCodeScannerPresented) {
                    ExampleQRCodeScanner { payload in
                        session.isClientQRCodeScannerPresented = false
                        session.applyClientQRCodePayload(payload)
                    }
                }
        #else
            content
        #endif
    }

    private var content: some View {
        ExampleConfigureBackground {
            VStack(spacing: 0) {
                ExampleConfigureHeader(
                    scanSupported: ExamplePlatform.scanSupported,
                    primaryAction: {
                        session.isSettingsPresented.toggle()
                    },
                    scanAction: {
                        session.isClientQRCodeScannerPresented = true
                    }
                )
                .padding(.bottom, 20)

                ExampleConfigureCard {
                    VStack(spacing: 16) {
                        ExampleTextInput(
                            "app_id",
                            hint: "TiRTC 应用标识，进入播放页前必须提供。",
                            text: $session.appId,
                            accessibilityIdentifier: "client.app_id"
                        )
                        ExampleTextInput(
                            "endpoint",
                            hint: "接入的云端环境，留空则使用默认环境。",
                            text: $session.endpoint,
                            accessibilityIdentifier: "client.endpoint"
                        )
                        ExampleTextInput(
                            "remote_id",
                            hint: "待连接的远端目标 ID",
                            text: $session.remoteId,
                            accessibilityIdentifier: "client.remote_id"
                        )
                        HStack(spacing: 16) {
                            ExampleTextInput(
                                "audio_stream_id",
                                hint: "音频流 ID，默认 10",
                                text: $session.audioStreamId,
                                accessibilityIdentifier: "client.audio_stream_id"
                            )
                            ExampleTextInput(
                                "video_stream_id",
                                hint: "视频流 ID，默认 11",
                                text: $session.videoStreamId,
                                accessibilityIdentifier: "client.video_stream_id"
                            )
                        }
                        ExampleSegmentedField("token_source") {
                            Picker("token_source", selection: $session.tokenSource) {
                                Text("Issuer").tag(ExampleTokenSource.issuer.rawValue)
                                Text("One-time").tag(ExampleTokenSource.oneTime.rawValue)
                            }
                            .pickerStyle(.segmented)
                            .accessibilityIdentifier("client.token_source")
                        }
                        if (ExampleTokenSource(rawValue: session.tokenSource) ?? .oneTime) == .issuer {
                            ExampleTextInput(
                                "token_issuer_base_url",
                                hint: "Token issuer 地址；根路径会请求 /v1/tokens。",
                                text: $session.tokenIssuerBaseUrl,
                                accessibilityIdentifier: "client.token_issuer_base_url"
                            )
                        } else {
                            ExampleTextInput(
                                "one_time_token",
                                hint: "进行一次连接所需的有效 token",
                                text: $session.token,
                                minHeight: 110,
                                accessibilityIdentifier: "client.token"
                            )
                        }
                        ExamplePrimaryButton(title: "进入播放页面") {
                            session.startClient()
                        }
                        .padding(.top, 4)
                        .accessibilityIdentifier("client.enter_player")
                    }
                }
            }
        }
        .accessibilityIdentifier("client.configure.page")
        .accessibilityValue(session.statusText)
        .sheet(isPresented: $session.isSettingsPresented) {
            ExampleSettingsSheet(session: session)
        }
    }
}

private struct ExampleConfigureBackground<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            configuredContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ExampleColors.configureGradient.ignoresSafeArea())
    }

    @ViewBuilder
    private var configuredContent: some View {
        #if os(iOS)
            content
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 32)
        #else
            HStack {
                Spacer(minLength: 0)
                content
                    .frame(maxWidth: 460)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity)
        #endif
    }
}

private struct ExampleConfigureCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(ExampleColors.surface.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 30))
    }
}

private struct ExampleConfigureHeader: View {
    let scanSupported: Bool
    let primaryAction: () -> Void
    let scanAction: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("Ti RTC")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(ExampleColors.brandText)
            Spacer()
            Button(action: primaryAction) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(ExamplePillIconButtonStyle())
            if scanSupported {
                Button(action: scanAction) {
                    Label("扫一扫", systemImage: "qrcode.viewfinder")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(height: 40)
                }
                .buttonStyle(ExamplePillButtonStyle())
            }
        }
    }
}

private struct ExampleSegmentedField<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(ExampleColors.textSecondary)
            content
        }
    }
}

private struct ExampleTextInput: View {
    let title: String
    let hint: String
    @Binding var text: String
    var minHeight: CGFloat = 58
    let accessibilityIdentifier: String

    init(
        _ title: String,
        hint: String,
        text: Binding<String>,
        minHeight: CGFloat = 58,
        accessibilityIdentifier: String
    ) {
        self.title = title
        self.hint = hint
        self.minHeight = minHeight
        self.accessibilityIdentifier = accessibilityIdentifier
        _text = text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(ExampleColors.textSecondary)
                .lineLimit(1)
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(hint)
                        .font(.system(size: 12))
                        .foregroundColor(ExampleColors.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(ExampleColors.textPrimary)
                    .accessibilityIdentifier(accessibilityIdentifier)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .background(ExampleColors.inputSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(ExampleColors.inputBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        #if os(iOS)
            .autocapitalization(.none)
            .disableAutocorrection(true)
        #endif
    }
}

private struct ExampleSettingsSheet: View {
    @ObservedObject var session: ExampleSessionController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("设置")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(ExampleColors.textPrimary)
                Text("本地仅保存连接配置，不保存 token。")
                    .font(.system(size: 14))
                    .foregroundColor(ExampleColors.textSecondary)
                ExampleSegmentedField("解码后端") {
                    Picker("decoderPreference", selection: $session.decoderPreference) {
                        Text("自动").tag(ExampleVideoDecoderPreference.automatic.rawValue)
                        Text("软解").tag(ExampleVideoDecoderPreference.software.rawValue)
                        Text("硬解").tag(ExampleVideoDecoderPreference.hardware.rawValue)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("settings.decoderPreference")
                }
                ExampleSegmentedField("输出缓冲") {
                    Picker("outputBufferPolicy", selection: $session.outputBufferPolicy) {
                        Text("自动").tag(ExampleOutputBufferPolicy.automatic.rawValue)
                        Text("无缓冲").tag(ExampleOutputBufferPolicy.noBuffer.rawValue)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("settings.output_buffer_policy")
                }
                ExampleSegmentedField("本地音频编码") {
                    Picker("localAudioCodec", selection: $session.localAudioCodec) {
                        Text("G711A").tag(ExampleAudioCodec.g711a.rawValue)
                        Text("AAC").tag(ExampleAudioCodec.aac.rawValue)
                        Text("PCM").tag(ExampleAudioCodec.pcm.rawValue)
                        Text("OPUS").tag(ExampleAudioCodec.opus.rawValue)
                        Text("AMR").tag(ExampleAudioCodec.amr.rawValue)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("settings.local_audio_codec")
                }
                ExampleSegmentedField("本地音频采样率") {
                    Picker("localAudioSampleRate", selection: $session.localAudioSampleRate) {
                        Text("8K").tag(String(ExampleAudioSampleRate.rate8k.rawValue))
                        Text("16K").tag(String(ExampleAudioSampleRate.rate16k.rawValue))
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("settings.local_audio_sample_rate")
                }
                ExampleTextInput(
                    "local_audio_stream_id",
                    hint: "播放器页麦克风对讲使用的本地音频流 ID。",
                    text: $session.localAudioStreamId,
                    accessibilityIdentifier: "settings.local_audio_stream_id"
                )
                Toggle("AEC", isOn: $session.localAudioAecEnabled)
                    .toggleStyle(.switch)
                    .accessibilityIdentifier("settings.local_audio_aec")
                ExampleSegmentedField("AGC") {
                    Picker("localAudioAgcLevel", selection: $session.localAudioAgcLevel) {
                        Text("关").tag("0")
                        Text("低").tag("1")
                        Text("中").tag("2")
                        Text("高").tag("3")
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("settings.local_audio_agc")
                }
                ExampleSegmentedField("ANS") {
                    Picker("localAudioAnsLevel", selection: $session.localAudioAnsLevel) {
                        Text("关").tag("0")
                        Text("低").tag("1")
                        Text("中").tag("2")
                        Text("高").tag("3")
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("settings.local_audio_ans")
                }
                Toggle("Console Log", isOn: $session.consoleLogEnabled)
                    .toggleStyle(.switch)
                    .accessibilityIdentifier("settings.console_log")
                ExamplePrimaryButton(title: "关闭") {
                    session.persistCurrentSettings()
                    session.isSettingsPresented = false
                }
            }
            .padding(24)
        }
        .frame(minWidth: 320)
        .background(ExampleColors.background)
    }
}

private struct ExamplePrimaryButton: View {
    let title: String
    var background = ExampleColors.primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .padding(.horizontal, 24)
                .background(background)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct ExamplePillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(ExampleColors.primary)
            .padding(.horizontal, 14)
            .background(ExampleColors.surface.opacity(configuration.isPressed ? 0.72 : 0.84))
            .overlay(
                Capsule()
                    .stroke(ExampleColors.primary.opacity(0.25), lineWidth: 1)
            )
            .clipShape(Capsule())
    }
}

private struct ExamplePillIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(ExampleColors.primary)
            .background(ExampleColors.surface.opacity(configuration.isPressed ? 0.72 : 0.84))
            .overlay(
                Circle()
                    .stroke(ExampleColors.primary.opacity(0.25), lineWidth: 1)
            )
            .clipShape(Circle())
    }
}

private enum ExamplePlatform {
    #if os(iOS)
        static let scanSupported = true
    #else
        static let scanSupported = false
    #endif
}
