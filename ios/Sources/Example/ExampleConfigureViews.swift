import SwiftUI

struct ExampleClientConfigure: View {
    @ObservedObject var session: ExampleSessionController
    @State private var isCloudStoragePresented = false
    @State private var selectedProduct = "rtc"
    @State private var cloudStorageAppId: String
    @State private var cloudStorageEndpoint: String
    @State private var cloudStorageToken: String
    @State private var cloudStorageAudioChannelId: String
    @State private var cloudStorageVideoChannelIds: [String]
    @State private var resolvedCloudStorageToken = ""
    @State private var cloudStorageOpening = false
    @State private var cloudStorageOpenStatus = ""
    @State private var isCloudStorageQRCodeScannerPresented = false

    init(session: ExampleSessionController) {
        self.session = session
        _cloudStorageAppId = State(initialValue: session.appId)
        _cloudStorageEndpoint = State(initialValue: session.endpoint)
        _cloudStorageToken = State(initialValue: session.token)
        let defaults = UserDefaults.standard
        _cloudStorageAudioChannelId = State(
            initialValue:
                defaults.object(forKey: "example.cloud.audio_channel_id") == nil
                ? String(ExampleSessionController.StreamDefaults.audio)
                : defaults.string(forKey: "example.cloud.audio_channel_id") ?? "")
        let storedCloudVideos = defaults.array(forKey: "example.cloud.video_channel_ids") as? [String]
        _cloudStorageVideoChannelIds = State(
            initialValue:
                storedCloudVideos.map { Array($0.prefix(3)) }
                ?? [String(ExampleSessionController.StreamDefaults.video)])
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
                .sheet(isPresented: $isCloudStorageQRCodeScannerPresented) {
                    ExampleQRCodeScanner { payload in
                        isCloudStorageQRCodeScannerPresented = false
                        applyCloudStorageQRCodePayload(payload)
                    }
                }
        #else
            content
        #endif
    }

    private var content: some View {
        ExampleConfigureBackground { isWide in
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
                configurationSections(isWide: isWide)
            }
        }
        .accessibilityIdentifier("client.configure.page")
        .accessibilityValue(session.statusText)
        .sheet(isPresented: $session.isSettingsPresented) {
            ExampleSettingsSheet(session: session)
        }
        .sheet(isPresented: $isCloudStoragePresented) {
            TiCloudStorageExampleView(
                appId: cloudStorageAppId,
                endpoint: cloudStorageEndpoint,
                token: resolvedCloudStorageToken,
                audioChannelId: resolvedCloudStorageAudioChannelId,
                videoChannelIds: resolvedCloudStorageVideoChannelIds ?? []
            )
        }
    }

    @ViewBuilder
    private func configurationSections(isWide: Bool) -> some View {
        if isWide {
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 16) {
                    connectionSection
                    mediaSection
                }
                .frame(maxWidth: .infinity)
                authenticationSection.frame(maxWidth: .infinity)
            }
        } else {
            VStack(spacing: 16) {
                connectionSection
                mediaSection
                authenticationSection
            }
        }
    }

    private var connectionSection: some View {
        ExampleConfigureSection(
            title: "连接", symbol: "network",
            accessibilityIdentifier: "configure.section.connection"
        ) {
            if selectedProduct == "rtc" {
                ExampleTextInput(
                    "endpoint", hint: "接入的云端环境，留空则使用默认环境。",
                    text: $session.endpoint, accessibilityIdentifier: "client.endpoint")
                ExampleTextInput(
                    "app_id", hint: "TiRTC 应用标识，进入播放页前必须提供。",
                    text: $session.appId, accessibilityIdentifier: "client.app_id")
                ExampleTextInput(
                    "remote_id", hint: "待连接的远端目标 ID", text: $session.remoteId,
                    accessibilityIdentifier: "client.remote_id")
            } else {
                ExampleTextInput(
                    "app_id", hint: "Ti Cloud Storage 应用标识，进入播放页前必须提供。",
                    text: $cloudStorageAppId, accessibilityIdentifier: "ti-cloud-storage.app_id")
                ExampleTextInput(
                    "endpoint", hint: "接入的云端环境，留空则使用默认环境。",
                    text: $cloudStorageEndpoint,
                    accessibilityIdentifier: "ti-cloud-storage.endpoint")
            }
        }
    }

    private var mediaSection: some View {
        ExampleConfigureSection(
            title: "媒体", symbol: "play.rectangle",
            accessibilityIdentifier: "configure.section.media"
        ) {
            if selectedProduct == "rtc" {
                ExampleTextInput(
                    "音频 Stream ID", hint: "留空不接收音频", text: $session.audioStreamId,
                    accessibilityIdentifier: "client.audio_stream_id")
                mediaIdList(
                    title: "视频 Stream ID（最多 3 路）", values: $session.videoStreamIds,
                    identifierPrefix: "client.video_stream_id")
            } else {
                ExampleTextInput(
                    "音频 Channel ID", hint: "留空不接收音频",
                    text: $cloudStorageAudioChannelId,
                    accessibilityIdentifier: "ti-cloud-storage.audio_channel_id")
                mediaIdList(
                    title: "视频 Channel ID（最多 3 路）", values: $cloudStorageVideoChannelIds,
                    identifierPrefix: "ti-cloud-storage.video_channel_id")
            }
        }
    }

    private var authenticationSection: some View {
        ExampleConfigureSection(
            title: "鉴权", symbol: "key",
            accessibilityIdentifier: "configure.section.authentication"
        ) {
            if selectedProduct == "rtc" {
                ExampleScanFirstButton(
                    enabled: ExamplePlatform.scanSupported,
                    accessibilityIdentifier: "client.scan_qr",
                    action: { session.isClientQRCodeScannerPresented = true })
                ExampleManualEntryDivider()
                ExampleTextInput(
                    "一次性连接 Token", hint: "粘贴 v1.xxx 一次性 Token。", text: $session.token,
                    accessibilityIdentifier: "client.token")
                ExampleTextInput(
                    "TiRTC DevTools 服务地址", hint: "例如 http://192.168.1.10:8966",
                    text: $session.tokenIssuerBaseUrl,
                    accessibilityIdentifier: "client.token_issuer_base_url")
                ExamplePrimaryButton(title: "开始连接、拉流播放") {
                    session.tokenSource =
                        session.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? ExampleTokenSource.issuer.rawValue : ExampleTokenSource.oneTime.rawValue
                    session.startClient()
                }
                .accessibilityIdentifier("client.enter_player")
            } else {
                ExampleScanFirstButton(
                    enabled: ExamplePlatform.scanSupported,
                    accessibilityIdentifier: "ti-cloud-storage.scan_qr",
                    action: { isCloudStorageQRCodeScannerPresented = true })
                ExampleManualEntryDivider()
                ExampleTextInput(
                    "token", hint: "粘贴云录像客户端 Token。", text: $cloudStorageToken,
                    secure: true, accessibilityIdentifier: "ti-cloud-storage.token")
                if !cloudStorageOpenStatus.isEmpty {
                    Text(cloudStorageOpenStatus)
                        .font(.footnote)
                        .foregroundColor(ExampleColors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("ti-cloud-storage.configure.status")
                }
                ExamplePrimaryButton(title: cloudStorageOpening ? "连接中…" : "播放云录像") {
                    openCloudStorage()
                }
                .accessibilityIdentifier("ti-cloud-storage.enter_player")
                .disabled(!cloudStorageConfigurationValid || cloudStorageOpening)
                .opacity(cloudStorageConfigurationValid && !cloudStorageOpening ? 1 : 0.55)
            }
        }
    }

    private var resolvedCloudStorageAudioChannelId: UInt8? {
        let value = cloudStorageAudioChannelId.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : UInt8(value)
    }

    private var resolvedCloudStorageVideoChannelIds: [UInt8]? {
        let values =
            cloudStorageVideoChannelIds
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let ids = values.compactMap(UInt8.init)
        guard ids.count == values.count, Set(ids).count == ids.count else { return nil }
        return ids
    }

    private var cloudStorageConfigurationValid: Bool {
        let audio = cloudStorageAudioChannelId.trimmingCharacters(in: .whitespacesAndNewlines)
        return !cloudStorageAppId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !cloudStorageToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (audio.isEmpty || resolvedCloudStorageAudioChannelId != nil)
            && resolvedCloudStorageVideoChannelIds != nil
    }

    private func mediaIdList(
        title: String,
        values: Binding<[String]>,
        identifierPrefix: String
    ) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(title).font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    if values.wrappedValue.count < 3 { values.wrappedValue.append("") }
                } label: {
                    Image(systemName: "plus.circle")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .disabled(values.wrappedValue.count >= 3)
                .accessibilityIdentifier("\(identifierPrefix).add")
            }
            ForEach(Array(values.wrappedValue.indices), id: \.self) { index in
                HStack(spacing: 8) {
                    Text("\(index + 1)").foregroundColor(ExampleColors.textSecondary)
                    ExampleTextInput(
                        "视频 ID",
                        hint: "留空不接收该路视频",
                        text: Binding(
                            get: { values.wrappedValue[index] },
                            set: { values.wrappedValue[index] = $0 }),
                        accessibilityIdentifier: "\(identifierPrefix).\(index)"
                    )
                    Button {
                        values.wrappedValue.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("\(identifierPrefix).remove.\(index)")
                }
            }
        }
    }

    private func openCloudStorage() {
        guard cloudStorageConfigurationValid, !cloudStorageOpening else { return }
        UserDefaults.standard.set(cloudStorageAudioChannelId, forKey: "example.cloud.audio_channel_id")
        UserDefaults.standard.set(
            cloudStorageVideoChannelIds, forKey: "example.cloud.video_channel_ids")
        cloudStorageOpening = true
        cloudStorageOpenStatus = ""
        Task { @MainActor in
            defer { cloudStorageOpening = false }
            do {
                resolvedCloudStorageToken = try await resolveCloudStorageToken(cloudStorageToken)
                isCloudStoragePresented = true
            } catch {
                #if DEBUG
                    let diagnostic = error as NSError
                    cloudStorageOpenStatus =
                        "Token 获取失败，请检查地址与网络（\(diagnostic.domain):\(diagnostic.code)）"
                #else
                    cloudStorageOpenStatus = "Token 获取失败，请检查地址与网络"
                #endif
            }
        }
    }

    private func resolveCloudStorageToken(_ candidate: String) async throws -> String {
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

    private func applyCloudStorageQRCodePayload(_ payload: String) {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard trimmed.first == "{" else {
            cloudStorageToken = trimmed
            cloudStorageOpenStatus = "云录像 Token 已由扫码填入"
            return
        }
        guard let data = trimmed.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            Set(object.keys).isSubset(of: ["app_id", "endpoint", "token"]),
            let token = object["token"] as? String,
            !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            cloudStorageOpenStatus = "二维码内容无效，请使用云录像客户端 Token"
            return
        }
        cloudStorageToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if let appId = object["app_id"] as? String, !appId.isEmpty { cloudStorageAppId = appId }
        if let endpoint = object["endpoint"] as? String { cloudStorageEndpoint = endpoint }
        cloudStorageOpenStatus = "云录像配置已由扫码填入"
    }
}

private struct ExampleConfigureBackground<Content: View>: View {
    let content: (Bool) -> Content

    init(@ViewBuilder content: @escaping (Bool) -> Content) {
        self.content = content
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                configuredContent(
                    isWide: ExampleAuxiliaryLayout.isWide(
                        availableWidth: Double(proxy.size.width)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ExampleColors.configureGradient.ignoresSafeArea())
        }
    }

    private func configuredContent(isWide: Bool) -> some View {
        content(isWide)
            .frame(maxWidth: isWide ? 1120 : 560, alignment: .top)
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity)
    }
}

private struct ExampleConfigureSection<Content: View>: View {
    let title: String
    let symbol: String
    let accessibilityIdentifier: String
    let content: Content

    init(
        title: String, symbol: String, accessibilityIdentifier: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.symbol = symbol
        self.accessibilityIdentifier = accessibilityIdentifier
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundColor(ExampleColors.brandText)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(accessibilityIdentifier)
            content
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(16)
        .background(ExampleColors.surface.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct ExampleScanFirstButton: View {
    let enabled: Bool
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(enabled ? "扫描二维码" : "此平台不支持扫码", systemImage: "qrcode.viewfinder")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(enabled ? .white : ExampleColors.textSecondary)
        .background(enabled ? ExampleColors.primary : ExampleColors.inputSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .disabled(!enabled)
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityHint(enabled ? "打开相机扫描配置" : "请手动输入 Token")
    }
}

private struct ExampleManualEntryDivider: View {
    var body: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(ExampleColors.inputBorder)
                .frame(height: 1)
            Text("或手动输入")
                .font(.caption)
                .foregroundColor(ExampleColors.textSecondary)
                .fixedSize()
            Rectangle()
                .fill(ExampleColors.inputBorder)
                .frame(height: 1)
        }
        .accessibilityHidden(true)
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
                    .frame(minHeight: 44)
            }
            .buttonStyle(ExamplePillButtonStyle())
            .accessibilityIdentifier("settings.open")
        }
    }
}

private struct ExampleProductTabs: View {
    @Binding var selectedProduct: String

    var body: some View {
        HStack(spacing: 0) {
            tab("RTC", value: "rtc")
            tab("云录像", value: "ti-cloud-storage")
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
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("设置")
                            .font(.title2.bold())
                            .foregroundColor(ExampleColors.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        Text("本地仅保存连接配置，不保存 token。")
                            .font(.body)
                            .foregroundColor(ExampleColors.textSecondary)
                    }
                    Spacer()
                    Button("完成") { close() }
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityIdentifier("settings.close")
                }

                ExampleSettingsSection(title: "播放", symbol: "play.rectangle") {
                    ExampleSettingsPicker("解码后端") {
                        Picker("decoderPreference", selection: $session.decoderPreference) {
                            Text("自动").tag(ExampleVideoDecoderPreference.automatic.rawValue)
                            Text("软解").tag(ExampleVideoDecoderPreference.software.rawValue)
                            Text("硬解").tag(ExampleVideoDecoderPreference.hardware.rawValue)
                        }
                        .accessibilityIdentifier("settings.decoderPreference")
                    }
                    ExampleSettingsPicker("输出缓冲") {
                        Picker("outputBufferPolicy", selection: $session.outputBufferPolicy) {
                            Text("自动").tag(ExampleOutputBufferPolicy.automatic.rawValue)
                            Text("无缓冲").tag(ExampleOutputBufferPolicy.noBuffer.rawValue)
                        }
                        .accessibilityIdentifier("settings.output_buffer_policy")
                    }
                }

                ExampleSettingsSection(title: "本地音频", symbol: "mic") {
                    ExampleSettingsPicker("编码") {
                        Picker("localAudioCodec", selection: $session.localAudioCodec) {
                            Text("G711A").tag(ExampleAudioCodec.g711a.rawValue)
                            Text("AAC").tag(ExampleAudioCodec.aac.rawValue)
                            Text("PCM").tag(ExampleAudioCodec.pcm.rawValue)
                            Text("OPUS").tag(ExampleAudioCodec.opus.rawValue)
                            Text("AMR").tag(ExampleAudioCodec.amr.rawValue)
                        }
                        .accessibilityIdentifier("settings.local_audio_codec")
                    }
                    ExampleSettingsPicker("采样率") {
                        Picker("localAudioSampleRate", selection: $session.localAudioSampleRate) {
                            Text("8K").tag(String(ExampleAudioSampleRate.rate8k.rawValue))
                            Text("16K").tag(String(ExampleAudioSampleRate.rate16k.rawValue))
                        }
                        .accessibilityIdentifier("settings.local_audio_sample_rate")
                    }
                    ExampleTextInput(
                        "local_audio_stream_id",
                        hint: "播放器页麦克风对讲使用的本地音频流 ID。",
                        text: $session.localAudioStreamId,
                        accessibilityIdentifier: "settings.local_audio_stream_id")
                    Toggle("回声消除（AEC）", isOn: $session.localAudioAecEnabled)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("settings.local_audio_aec")
                    ExampleSettingsPicker("自动增益（AGC）") {
                        Picker("localAudioAgcLevel", selection: $session.localAudioAgcLevel) {
                            Text("关").tag("0")
                            Text("低").tag("1")
                            Text("中").tag("2")
                            Text("高").tag("3")
                        }
                        .accessibilityIdentifier("settings.local_audio_agc")
                    }
                    ExampleSettingsPicker("降噪（ANS）") {
                        Picker("localAudioAnsLevel", selection: $session.localAudioAnsLevel) {
                            Text("关").tag("0")
                            Text("低").tag("1")
                            Text("中").tag("2")
                            Text("高").tag("3")
                        }
                        .accessibilityIdentifier("settings.local_audio_ans")
                    }
                }

                ExampleSettingsSection(title: "诊断", symbol: "waveform.path.ecg") {
                    Toggle("Console Log", isOn: $session.consoleLogEnabled)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("settings.console_log")
                }
            }
            .padding(24)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 320, minHeight: 480)
        .background(ExampleColors.background)
        .accessibilityIdentifier("settings.page")
    }

    private func close() {
        session.persistCurrentSettings()
        session.isSettingsPresented = false
    }
}

private struct ExampleSettingsSection<Content: View>: View {
    let title: String
    let symbol: String
    let content: Content

    init(title: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundColor(ExampleColors.brandText)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ExampleColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct ExampleSettingsPicker<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            content.pickerStyle(.menu)
        }
        .frame(minHeight: 44)
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
