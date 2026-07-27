import Foundation
import TiRTC

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
