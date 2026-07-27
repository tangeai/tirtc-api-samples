import CryptoKit
import Foundation
import TiRTC

enum ExampleValidationError: Error, Equatable {
    case invalidJSON
    case missingRequiredField(String)
    case invalidEndpoint
    case invalidStreamId(String)
}

enum ExampleAudioCodec: String, CaseIterable, Equatable {
    case g711a
    case aac
    case pcm
    case opus
    case amr
}

enum ExampleAudioSampleRate: Int, CaseIterable, Equatable {
    case rate8k = 8000
    case rate16k = 16000
}

enum ExampleOutputBufferPolicy: String, CaseIterable, Equatable {
    case automatic
    case noBuffer
}

enum ExampleTokenSource: String, CaseIterable, Equatable {
    case issuer
    case oneTime
}

enum ExampleLocalAudioProcessingLevel: Int, CaseIterable, Equatable {
    case disabled = 0
    case low = 1
    case medium = 2
    case high = 3
}

enum ExampleVideoDecoderPreference: String, CaseIterable, Equatable {
    case automatic
    case software
    case hardware

    var nativeValue: Int32 {
        switch self {
        case .automatic:
            return 0
        case .software:
            return 1
        case .hardware:
            return 2
        }
    }

    var sdkValue: TiRtcVideoDecoderPreference {
        switch self {
        case .automatic:
            return .auto
        case .software:
            return .software
        case .hardware:
            return .hardware
        }
    }
}

enum ExampleCommandPanelPayloadMode: String, CaseIterable, Equatable {
    case hex
    case text
}

enum ExampleCommandPanelCodec {
    static let callCommandId: UInt32 = 0x5452_4343
    static let echoCommandId = UInt32.max
    static let echoPayloadText = "echo"
    static let defaultCommandIdText = "0x00000000"

    static var echoPayload: Data {
        Data(echoPayloadText.utf8)
    }

    static func parseCommandId(_ rawValue: String) -> UInt32? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return nil
        }
        if trimmed.hasPrefix("0x") || trimmed.hasPrefix("0X") {
            return UInt32(trimmed.dropFirst(2), radix: 16)
        }
        return UInt32(trimmed)
    }

    static func parsePayload(mode: ExampleCommandPanelPayloadMode, text: String) -> Data? {
        switch mode {
        case .hex:
            return parseHexPayload(text)
        case .text:
            return Data(text.utf8)
        }
    }

    static func formatCommandId(_ commandId: UInt32) -> String {
        let digits = String(commandId, radix: 16, uppercase: true)
        return "0x" + String(repeating: "0", count: max(0, 8 - digits.count)) + digits
    }

    static func formatPayloadHex(_ payload: Data) -> String {
        payload.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    static func isEchoCommand(commandId: UInt32, payload: Data) -> Bool {
        commandId == echoCommandId && payload == echoPayload
    }

    private static func parseHexPayload(_ rawValue: String) -> Data? {
        let normalized =
            rawValue
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
            .replacingOccurrences(of: ",", with: "")
        if normalized.isEmpty {
            return Data()
        }
        guard normalized.count.isMultiple(of: 2),
            normalized.range(of: #"^[0-9a-fA-F]+$"#, options: .regularExpression) != nil
        else {
            return nil
        }

        var payload = Data()
        var index = normalized.startIndex
        while index < normalized.endIndex {
            let next = normalized.index(index, offsetBy: 2)
            guard let byte = UInt8(normalized[index..<next], radix: 16) else {
                return nil
            }
            payload.append(contentsOf: [byte])
            index = next
        }
        return payload
    }
}

enum ExampleCallCommandAction: String, CaseIterable, Equatable {
    case startCall = "start_call"
    case callReady = "call_ready"
    case callReject = "call_reject"
}

struct ExampleCallCommand: Equatable {
    var action: ExampleCallCommandAction
    var requestId: String
    var audioEnabled: Bool
    var videoEnabled: Bool
    var reason: String?

    func encode() -> Data {
        var payload: [String: Any] = [
            "schema_version": 1,
            "action": action.rawValue,
            "request_id": requestId,
        ]
        if action == .callReject {
            if let reason, !reason.isEmpty {
                payload["reason"] = reason
            }
        } else {
            payload["audio_enabled"] = audioEnabled
            payload["video_enabled"] = videoEnabled
            if audioEnabled {
                payload["initiator_audio_stream_id"] = 10
                payload["responder_audio_stream_id"] = 20
            }
            if videoEnabled {
                payload["initiator_video_stream_id"] = 11
                payload["responder_video_stream_id"] = 21
            }
        }
        return (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data()
    }

    static func decode(commandId: UInt32, data: Data) -> ExampleCallCommand? {
        guard commandId == ExampleCommandPanelCodec.callCommandId,
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            object["schema_version"] as? Int == 1,
            let rawAction = object["action"] as? String,
            let action = ExampleCallCommandAction(rawValue: rawAction),
            let requestId = object["request_id"] as? String,
            !requestId.isEmpty
        else {
            return nil
        }
        if action == .callReject {
            return ExampleCallCommand(
                action: action,
                requestId: requestId,
                audioEnabled: false,
                videoEnabled: false,
                reason: object["reason"] as? String)
        }
        guard let audioEnabled = object["audio_enabled"] as? Bool,
            let videoEnabled = object["video_enabled"] as? Bool
        else {
            return nil
        }
        return ExampleCallCommand(
            action: action,
            requestId: requestId,
            audioEnabled: audioEnabled,
            videoEnabled: videoEnabled,
            reason: nil)
    }
}

struct ExampleCommandPanelEvent: Equatable, Identifiable {
    enum Direction: String, Equatable {
        case sent
        case received
    }

    static let maxStoredEvents = 20

    let id: UUID
    let direction: Direction
    let commandId: UInt32
    let payload: String
    let resultCode: Int32?
    let createdAt: Date

    var commandIdLabel: String {
        ExampleCommandPanelCodec.formatCommandId(commandId)
    }

    var payloadHex: String {
        payload
    }

    init(
        direction: Direction,
        commandId: UInt32,
        payload: String,
        resultCode: Int32? = nil,
        createdAt: Date = Date(),
        id: UUID = UUID()
    ) {
        self.id = id
        self.direction = direction
        self.commandId = commandId
        self.payload = payload
        self.resultCode = resultCode
        self.createdAt = createdAt
    }

    static func appending(
        _ event: ExampleCommandPanelEvent,
        to events: [ExampleCommandPanelEvent]
    ) -> [ExampleCommandPanelEvent] {
        Array((events + [event]).suffix(maxStoredEvents))
    }
}

struct ExampleLogUploadResult: Identifiable {
    let id = UUID()
    let code: Int32
    let logId: String?

    var succeeded: Bool {
        code == 0 && !(logId ?? "").isEmpty
    }

    var title: String {
        succeeded ? "日志上传完成" : "日志上传失败"
    }

    var message: String {
        if let logId, !logId.isEmpty {
            return "code=\(code) log_id=\(logId)"
        }
        return "code=\(code)"
    }
}

struct ExampleClientConfiguration: Equatable {
    static let defaultAudioStreamId: UInt8 = 10
    static let defaultVideoStreamId: UInt8 = 11

    var appId: String
    var endpoint: String
    var remoteId: String
    var audioStreamId: UInt8
    var videoStreamId: UInt8
    var token: String

    init(
        appId: String,
        endpoint: String = "",
        remoteId: String,
        audioStreamId: UInt8 = defaultAudioStreamId,
        videoStreamId: UInt8 = defaultVideoStreamId,
        token: String
    ) {
        self.appId = appId
        self.endpoint = endpoint
        self.remoteId = remoteId
        self.audioStreamId = audioStreamId
        self.videoStreamId = videoStreamId
        self.token = token
    }

    func validated() -> Result<ExampleClientConfiguration, ExampleValidationError> {
        let normalized = ExampleClientConfiguration(
            appId: appId.trimmedForExample(),
            endpoint: endpoint.trimmedForExample(),
            remoteId: remoteId.trimmedForExample(),
            audioStreamId: audioStreamId,
            videoStreamId: videoStreamId,
            token: token.trimmedForExample()
        )
        if normalized.appId.isEmpty {
            return .failure(.missingRequiredField("app_id"))
        }
        if normalized.remoteId.isEmpty {
            return .failure(.missingRequiredField("remote_id"))
        }
        if normalized.token.isEmpty {
            return .failure(.missingRequiredField("token"))
        }
        if !normalized.endpoint.isEmpty, !ExampleEndpointValidator.isValid(normalized.endpoint) {
            return .failure(.invalidEndpoint)
        }
        return .success(normalized)
    }
}

enum ExamplePayloadParser {
    static func parseClientQRCode(
        _ json: String,
        preserving currentEndpoint: String = ""
    ) -> Result<ExampleClientConfiguration, ExampleValidationError> {
        guard let object = jsonObject(from: json) else {
            return .failure(.invalidJSON)
        }

        let endpoint = stringValue(object["endpoint"])?.trimmedForExample()
        let config = ExampleClientConfiguration(
            appId: stringValue(object["app_id"]) ?? "",
            endpoint: endpoint?.isEmpty == false ? endpoint! : currentEndpoint,
            remoteId: stringValue(object["remote_id"]) ?? "",
            audioStreamId: ExampleClientConfiguration.defaultAudioStreamId,
            videoStreamId: ExampleClientConfiguration.defaultVideoStreamId,
            token: stringValue(object["token"]) ?? ""
        )
        return config.validated()
    }

    static func parseOptionalStreamId(_ rawValue: String, fieldName: String) -> Result<
        UInt8?, ExampleValidationError
    > {
        let trimmed = rawValue.trimmedForExample()
        if trimmed.isEmpty {
            return .success(Optional<UInt8>.none)
        }
        guard let value = UInt8(trimmed) else {
            return .failure(.invalidStreamId(fieldName))
        }
        return .success(value)
    }

    private static func jsonObject(from json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return object
    }

    private static func stringValue(_ rawValue: Any?) -> String? {
        rawValue as? String
    }

}

enum ExampleEndpointValidator {
    static func isValid(_ endpoint: String) -> Bool {
        let trimmed = endpoint.trimmedForExample()
        guard let components = URLComponents(string: trimmed),
            let scheme = components.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            components.host?.isEmpty == false
        else {
            return false
        }
        return true
    }
}

enum ExampleEvidenceRedactor {
    static func tokenFingerprint(_ token: String) -> String {
        let digest = SHA256.hash(data: Data(token.utf8))
        return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    static func redactedClientPayload(_ config: ExampleClientConfiguration) -> [String: String] {
        [
            "app_id": config.appId,
            "endpoint": config.endpoint,
            "remote_id": config.remoteId,
            "audio_stream_id": String(config.audioStreamId),
            "video_stream_id": String(config.videoStreamId),
            "token_fingerprint": tokenFingerprint(config.token),
        ]
    }

}

struct ExampleSettingsSnapshot: Equatable {
    var appId: String
    var endpoint: String
    var remoteId: String
    var audioStreamId: UInt8
    var videoStreamId: UInt8
    var outputBufferPolicy: ExampleOutputBufferPolicy = .automatic
    var localAudioCodec: ExampleAudioCodec = .g711a
    var localAudioSampleRate: ExampleAudioSampleRate = .rate16k
    var localAudioStreamId: UInt8 = ExampleClientConfiguration.defaultAudioStreamId
    var localAudioAecEnabled = false
    var localAudioAgcLevel: ExampleLocalAudioProcessingLevel = .disabled
    var localAudioAnsLevel: ExampleLocalAudioProcessingLevel = .disabled
    var decoderPreference: ExampleVideoDecoderPreference
    var consoleLogEnabled: Bool
}

final class ExampleSettingsStore {
    private enum Key {
        static let appId = "example.app_id"
        static let endpoint = "example.endpoint"
        static let remoteId = "example.remote_id"
        static let audioStreamId = "example.audio_stream_id"
        static let videoStreamId = "example.video_stream_id"
        static let outputBufferPolicy = "example.output_buffer_policy"
        static let localAudioCodec = "example.local_audio_codec"
        static let localAudioSampleRate = "example.local_audio_sample_rate_hz"
        static let localAudioStreamId = "example.local_audio_stream_id"
        static let localAudioAecEnabled = "example.local_audio_aec_enabled"
        static let localAudioAgcLevel = "example.local_audio_agc_level"
        static let localAudioAnsLevel = "example.local_audio_ans_level"
        static let decoderPreference = "example.decoder_preference"
        static let consoleLogEnabled = "example.console_log_enabled"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    func save(_ snapshot: ExampleSettingsSnapshot) {
        userDefaults.set(snapshot.appId, forKey: Key.appId)
        userDefaults.set(snapshot.endpoint, forKey: Key.endpoint)
        userDefaults.set(snapshot.remoteId, forKey: Key.remoteId)
        userDefaults.set(Int(snapshot.audioStreamId), forKey: Key.audioStreamId)
        userDefaults.set(Int(snapshot.videoStreamId), forKey: Key.videoStreamId)
        userDefaults.set(snapshot.outputBufferPolicy.rawValue, forKey: Key.outputBufferPolicy)
        userDefaults.set(snapshot.localAudioCodec.rawValue, forKey: Key.localAudioCodec)
        userDefaults.set(snapshot.localAudioSampleRate.rawValue, forKey: Key.localAudioSampleRate)
        userDefaults.set(Int(snapshot.localAudioStreamId), forKey: Key.localAudioStreamId)
        userDefaults.set(snapshot.localAudioAecEnabled, forKey: Key.localAudioAecEnabled)
        userDefaults.set(snapshot.localAudioAgcLevel.rawValue, forKey: Key.localAudioAgcLevel)
        userDefaults.set(snapshot.localAudioAnsLevel.rawValue, forKey: Key.localAudioAnsLevel)
        userDefaults.set(snapshot.decoderPreference.rawValue, forKey: Key.decoderPreference)
        userDefaults.set(snapshot.consoleLogEnabled, forKey: Key.consoleLogEnabled)
    }

    func load() -> ExampleSettingsSnapshot {
        ExampleSettingsSnapshot(
            appId: userDefaults.string(forKey: Key.appId) ?? "",
            endpoint: userDefaults.string(forKey: Key.endpoint) ?? "",
            remoteId: userDefaults.string(forKey: Key.remoteId) ?? "",
            audioStreamId: UInt8(userDefaults.integer(forKey: Key.audioStreamId)),
            videoStreamId: UInt8(userDefaults.integer(forKey: Key.videoStreamId)),
            outputBufferPolicy: ExampleOutputBufferPolicy(
                rawValue: userDefaults.string(forKey: Key.outputBufferPolicy) ?? ""
            ) ?? .automatic,
            localAudioCodec: ExampleAudioCodec(
                rawValue: userDefaults.string(forKey: Key.localAudioCodec) ?? ""
            ) ?? .g711a,
            localAudioSampleRate: ExampleAudioSampleRate(
                rawValue: userDefaults.integer(forKey: Key.localAudioSampleRate)
            ) ?? .rate16k,
            localAudioStreamId: UInt8(userDefaults.integer(forKey: Key.localAudioStreamId)),
            localAudioAecEnabled: userDefaults.object(forKey: Key.localAudioAecEnabled) as? Bool
                ?? false,
            localAudioAgcLevel: ExampleLocalAudioProcessingLevel(
                rawValue: userDefaults.integer(forKey: Key.localAudioAgcLevel)
            ) ?? .disabled,
            localAudioAnsLevel: ExampleLocalAudioProcessingLevel(
                rawValue: userDefaults.integer(forKey: Key.localAudioAnsLevel)
            ) ?? .disabled,
            decoderPreference: ExampleVideoDecoderPreference(
                rawValue: userDefaults.string(forKey: Key.decoderPreference) ?? ""
            ) ?? .automatic,
            consoleLogEnabled: userDefaults.object(forKey: Key.consoleLogEnabled) as? Bool ?? true
        )
    }
}

extension String {
    fileprivate func trimmedForExample() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
