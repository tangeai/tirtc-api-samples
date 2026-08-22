import SwiftUI

struct ExampleClientConfigure: View {
    @ObservedObject var session: ExampleSessionController
    @State private var isStorePresented = false
    @State private var selectedProduct = "rtc"
    @State private var storeAppId: String
    @State private var storeEndpoint: String
    @State private var storeToken: String
    @State private var storeAudioChannelId: String
    @State private var storeVideoChannelId: String
    @State private var resolvedStoreToken = ""
    @State private var storeOpening = false
    @State private var storeOpenStatus = ""
    @State private var isStoreQRCodeScannerPresented = false

    init(session: ExampleSessionController) {
        self.session = session
        _storeAppId = State(initialValue: session.appId)
        _storeEndpoint = State(initialValue: session.endpoint)
        _storeToken = State(initialValue: session.token)
        _storeAudioChannelId = State(initialValue: session.audioStreamId)
        _storeVideoChannelId = State(initialValue: session.videoStreamId)
    }

    var body: some View {
        #if os(iOS)
            content
                .sheet(isPresented: $session.isClientQRCodeScannerPresented) {
                    ExampleQRCodeScanner { payload in
                        session.isClientQRCodeScannerPresented = false
                        session.applyClientQRCodePayload(payload)
                    }
                }
                .sheet(isPresented: $isStoreQRCodeScannerPresented) {
                    ExampleQRCodeScanner { payload in
                        isStoreQRCodeScannerPresented = false
                        applyStoreQRCodePayload(payload)
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
                    primaryAction: {
                        session.isSettingsPresented.toggle()
                    }
                )
                .padding(.bottom, 16)

                ExampleProductTabs(selectedProduct: $selectedProduct)
                    .padding(.bottom, 20)
                    .accessibilityIdentifier("product.tabs")
                ExampleConfigureCard {
                    VStack(spacing: 16) {
                        if selectedProduct == "rtc" {
                            ExampleTextInput(
                                "endpoint",
                                hint: "接入的云端环境，留空则使用默认环境。",
                                text: $session.endpoint,
                                accessibilityIdentifier: "client.endpoint"
                            )
                            ExampleTextInput(
                                "app_id",
                                hint: "TiRTC 应用标识，进入播放页前必须提供。",
                                text: $session.appId,
                                accessibilityIdentifier: "client.app_id"
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
                            HStack(alignment: .top, spacing: 10) {
                                ExampleTextInput(
                                    "一次性连接 Token",
                                    hint: "粘贴 v1.xxx 一次性 Token，或点右侧扫码。",
                                    text: $session.token,
                                    accessibilityIdentifier: "client.token"
                                )
                                ExampleInlineScanButton(
                                    enabled: ExamplePlatform.scanSupported,
                                    action: { session.isClientQRCodeScannerPresented = true }
                                )
                            }
                            Text("或")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(ExampleColors.textSecondary)
                                .frame(maxWidth: .infinity)
                            ExampleTextInput(
                                "TiRTC DevTools 服务地址",
                                hint: "例如 http://192.168.1.10:8966",
                                text: $session.tokenIssuerBaseUrl,
                                accessibilityIdentifier: "client.token_issuer_base_url"
                            )
                            ExamplePrimaryButton(title: "开始连接、拉流播放") {
                                session.tokenSource =
                                    session.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? ExampleTokenSource.issuer.rawValue : ExampleTokenSource.oneTime.rawValue
                                session.startClient()
                            }
                            .padding(.top, 4)
                            .accessibilityIdentifier("client.enter_player")
                        } else {
                            ExampleTextInput(
                                "app_id",
                                hint: "TiStore 应用标识，进入播放页前必须提供。",
                                text: $storeAppId,
                                accessibilityIdentifier: "store.app_id"
                            )
                            ExampleTextInput(
                                "endpoint",
                                hint: "接入的云端环境，留空则使用默认环境。",
                                text: $storeEndpoint,
                                accessibilityIdentifier: "store.endpoint"
                            )
                            HStack(alignment: .top, spacing: 10) {
                                ExampleTextInput(
                                    "token",
                                    hint: "粘贴云录像客户端 Token，或点右侧扫码。",
                                    text: $storeToken,
                                    secure: true,
                                    accessibilityIdentifier: "store.token"
                                )
                                ExampleInlineScanButton(
                                    enabled: ExamplePlatform.scanSupported,
                                    action: { isStoreQRCodeScannerPresented = true }
                                )
                            }
                            HStack(spacing: 16) {
                                ExampleTextInput(
                                    "audio_channel_id",
                                    hint: "音频 Channel，0..255",
                                    text: $storeAudioChannelId,
                                    accessibilityIdentifier: "store.audio_channel_id"
                                )
                                ExampleTextInput(
                                    "video_channel_id",
                                    hint: "视频 Channel，0..255",
                                    text: $storeVideoChannelId,
                                    accessibilityIdentifier: "store.video_channel_id"
                                )
                            }
                            if !storeOpenStatus.isEmpty {
                                Text(storeOpenStatus)
                                    .font(.system(size: 12))
                                    .foregroundColor(ExampleColors.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .accessibilityIdentifier("store.configure.status")
                            }
                            ExamplePrimaryButton(title: storeOpening ? "连接中…" : "播放云录像") {
                                openStore()
                            }
                            .padding(.top, 4)
                            .accessibilityIdentifier("store.enter_player")
                            .disabled(!storeConfigurationValid || storeOpening)
                            .opacity(storeConfigurationValid && !storeOpening ? 1 : 0.55)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("client.configure.page")
        .accessibilityValue(session.statusText)
        .sheet(isPresented: $session.isSettingsPresented) {
            ExampleSettingsSheet(session: session)
        }
        .sheet(isPresented: $isStorePresented) {
            TiStoreExampleView(
                appId: storeAppId,
                endpoint: storeEndpoint,
                token: resolvedStoreToken,
                audioChannelId: UInt8(storeAudioChannelId) ?? ExampleSessionController.StreamDefaults.audio,
                videoChannelId: UInt8(storeVideoChannelId) ?? ExampleSessionController.StreamDefaults.video
            )
        }
    }

    private var storeConfigurationValid: Bool {
        !storeAppId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !storeToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && UInt8(storeAudioChannelId) != nil
            && UInt8(storeVideoChannelId) != nil
    }

    private func openStore() {
        guard storeConfigurationValid, !storeOpening else { return }
        storeOpening = true
        storeOpenStatus = ""
        Task { @MainActor in
            defer { storeOpening = false }
            do {
                resolvedStoreToken = try await resolveStoreToken(storeToken)
                isStorePresented = true
            } catch {
                #if DEBUG
                    let diagnostic = error as NSError
                    storeOpenStatus =
                        "Token 获取失败，请检查地址与网络（\(diagnostic.domain):\(diagnostic.code)）"
                #else
                    storeOpenStatus = "Token 获取失败，请检查地址与网络"
                #endif
            }
        }
    }

    private func resolveStoreToken(_ candidate: String) async throws -> String {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        else {
            return trimmed
        }
        for attempt in 0..<20 {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let response = response as? HTTPURLResponse,
                    (200..<300).contains(response.statusCode),
                    let object = try JSONSerialization.jsonObject(with: data) as? [String: String],
                    let token = object["token"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                    !token.isEmpty
                else {
                    throw URLError(.cannotParseResponse)
                }
                return token
            } catch let error as URLError
                where attempt < 19
                && [
                    URLError.notConnectedToInternet,
                    .networkConnectionLost,
                    .cannotConnectToHost,
                    .timedOut,
                    .dataNotAllowed,
                ].contains(error.code)
            {
                try await Task<Never, Never>.sleep(nanoseconds: 500_000_000)
            }
        }
        throw URLError(.cannotConnectToHost)
    }

    private func applyStoreQRCodePayload(_ payload: String) {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard trimmed.first == "{" else {
            storeToken = trimmed
            storeOpenStatus = "云录像 Token 已由扫码填入"
            return
        }
        guard let data = trimmed.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            Set(object.keys).isSubset(of: ["app_id", "endpoint", "token"]),
            let token = object["token"] as? String,
            !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            storeOpenStatus = "二维码内容无效，请使用云录像客户端 Token"
            return
        }
        storeToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if let appId = object["app_id"] as? String, !appId.isEmpty { storeAppId = appId }
        if let endpoint = object["endpoint"] as? String { storeEndpoint = endpoint }
        storeOpenStatus = "云录像配置已由扫码填入"
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
    let primaryAction: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Ti RTC")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(ExampleColors.brandText)
                Text("Based on Darwin")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(ExampleColors.textSecondary)
            }
            Spacer()
            Button(action: primaryAction) {
                Text("偏好设置")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 14)
                    .frame(height: 40)
            }
            .buttonStyle(ExamplePillButtonStyle())
        }
    }
}

private struct ExampleProductTabs: View {
    @Binding var selectedProduct: String

    var body: some View {
        HStack(spacing: 0) {
            tab("RTC", value: "rtc")
            tab("云录像", value: "store")
        }
        .padding(3)
        .frame(height: 44)
        .background(ExampleColors.inputSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func tab(_ title: String, value: String) -> some View {
        Button(action: { selectedProduct = value }) {
            Text(title)
                .font(.system(size: 14, weight: selectedProduct == value ? .bold : .semibold))
                .foregroundColor(selectedProduct == value ? .white : ExampleColors.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(selectedProduct == value ? ExampleColors.primary : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 17))
        }
        .buttonStyle(.plain)
    }
}

private struct ExampleInlineScanButton: View {
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button("扫码", action: action)
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(enabled ? ExampleColors.primary : ExampleColors.textSecondary)
            .padding(.horizontal, 16)
            .frame(minWidth: 56, minHeight: 56)
            .background(ExampleColors.inputSurface)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.55)
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
    var minHeight: CGFloat = 56
    var secure = false
    let accessibilityIdentifier: String

    init(
        _ title: String,
        hint: String,
        text: Binding<String>,
        minHeight: CGFloat = 56,
        secure: Bool = false,
        accessibilityIdentifier: String
    ) {
        self.title = title
        self.hint = hint
        self.minHeight = minHeight
        self.secure = secure
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
                Group {
                    if secure {
                        SecureField("", text: $text)
                    } else {
                        TextField("", text: $text)
                    }
                }
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
    var foreground = Color.white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(foreground)
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
