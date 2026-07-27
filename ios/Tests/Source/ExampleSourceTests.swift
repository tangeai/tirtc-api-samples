import Foundation
import XCTest

@testable import DarwinExampleSupport

final class ExampleSourceTests: XCTestCase {
    func testClientQRCodeParsesValidPayloadAndPreservesEndpointWhenOmitted() throws {
        let json = """
            {
              "app_id": " app ",
              "remote_id": " remote ",
              "token": " token ",
              "ignored": true
            }
            """

        let config = try XCTUnwrap(
            tryResult(
                ExamplePayloadParser.parseClientQRCode(
                    json,
                    preserving: "https://typed.example"
                )))

        XCTAssertEqual(config.appId, "app")
        XCTAssertEqual(config.endpoint, "https://typed.example")
        XCTAssertEqual(config.remoteId, "remote")
        XCTAssertEqual(config.audioStreamId, 10)
        XCTAssertEqual(config.videoStreamId, 11)
        XCTAssertEqual(config.token, "token")
    }

    func testClientQRCodeRejectsInvalidPayloadsWithoutPartialMutation() {
        XCTAssertEqual(
            failure(ExamplePayloadParser.parseClientQRCode("not json")),
            .invalidJSON
        )
        XCTAssertEqual(
            failure(ExamplePayloadParser.parseClientQRCode(#"{"app_id":"app","token":"token"}"#)),
            .missingRequiredField("remote_id")
        )
        XCTAssertEqual(
            failure(
                ExamplePayloadParser.parseClientQRCode(
                    #"{"app_id":"app","remote_id":"remote","token":"token","endpoint":"ftp://example.invalid"}"#
                )),
            .invalidEndpoint
        )
    }

    func testEndpointAndStreamValidation() {
        XCTAssertTrue(ExampleEndpointValidator.isValid("http://example.invalid"))
        XCTAssertTrue(ExampleEndpointValidator.isValid("https://example.invalid/path"))
        XCTAssertFalse(ExampleEndpointValidator.isValid(""))
        XCTAssertFalse(ExampleEndpointValidator.isValid("ftp://example.invalid"))
        XCTAssertFalse(ExampleEndpointValidator.isValid("https://"))

        XCTAssertEqual(
            tryResult(ExamplePayloadParser.parseOptionalStreamId("12", fieldName: "audio_stream_id")), 12)
        XCTAssertNil(
            tryResult(ExamplePayloadParser.parseOptionalStreamId("", fieldName: "audio_stream_id")) ?? nil
        )
        XCTAssertEqual(
            failure(ExamplePayloadParser.parseOptionalStreamId("999", fieldName: "audio_stream_id")),
            .invalidStreamId("audio_stream_id")
        )
    }

    func testRedactionKeepsSecretsOutOfEvidencePayloads() throws {
        let client = ExampleClientConfiguration(
            appId: "app",
            endpoint: "https://example.invalid",
            remoteId: "remote",
            token: "super-token"
        )
        let clientPayload = ExampleEvidenceRedactor.redactedClientPayload(client)

        XCTAssertNil(clientPayload["token"])
        XCTAssertFalse(clientPayload.values.contains("super-token"))
        XCTAssertTrue(clientPayload["token_fingerprint"]?.hasPrefix("sha256:") == true)
        XCTAssertEqual(clientPayload["token_fingerprint"]?.count, 71)
    }

    func testSettingsPersistenceExcludesSecrets() {
        let suiteName = "darwin-example-source-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = ExampleSettingsStore(userDefaults: defaults)
        let snapshot = ExampleSettingsSnapshot(
            appId: "app",
            endpoint: "https://example.invalid",
            remoteId: "remote",
            audioStreamId: 10,
            videoStreamId: 11,
            decoderPreference: .software,
            consoleLogEnabled: false
        )

        store.save(snapshot)

        XCTAssertEqual(store.load(), snapshot)
        XCTAssertNil(defaults.string(forKey: "example.token"))
    }

    func testCommandPanelEventsKeepLatestTwenty() {
        let events = (0..<25).reduce([ExampleCommandPanelEvent]()) { storedEvents, index in
            ExampleCommandPanelEvent.appending(
                ExampleCommandPanelEvent(
                    direction: .sent,
                    commandId: UInt32(index),
                    payload: "payload-\(index)",
                    resultCode: 0
                ),
                to: storedEvents
            )
        }

        XCTAssertEqual(events.count, 20)
        XCTAssertEqual(events.first?.commandId, 5)
        XCTAssertEqual(events.last?.commandId, 24)
    }

    func testCommandPanelParsesFlutterEchoPresetShape() {
        XCTAssertEqual(ExampleCommandPanelCodec.defaultCommandIdText, "0x00000000")
        XCTAssertEqual(
            ExampleCommandPanelCodec.formatCommandId(ExampleCommandPanelCodec.echoCommandId),
            "0xFFFFFFFF")
        XCTAssertEqual(ExampleCommandPanelCodec.echoPayloadText, "echo")
        XCTAssertTrue(
            ExampleCommandPanelCodec.isEchoCommand(
                commandId: ExampleCommandPanelCodec.echoCommandId,
                payload: Data(ExampleCommandPanelCodec.echoPayloadText.utf8)))
    }

    func testCommandPanelParsesUInt32CommandIdsAndPayloadModes() {
        XCTAssertEqual(ExampleCommandPanelCodec.parseCommandId("0xFFFFFFFF"), UInt32.max)
        XCTAssertEqual(ExampleCommandPanelCodec.parseCommandId("4294967295"), UInt32.max)
        XCTAssertNil(ExampleCommandPanelCodec.parseCommandId("4294967296"))
        XCTAssertEqual(
            ExampleCommandPanelCodec.parsePayload(mode: .hex, text: "65 63,68 6F"),
            Data("echo".utf8))
        XCTAssertEqual(
            ExampleCommandPanelCodec.parsePayload(mode: .text, text: "echo"),
            Data("echo".utf8))
        XCTAssertNil(ExampleCommandPanelCodec.parsePayload(mode: .hex, text: "0"))
        XCTAssertNil(ExampleCommandPanelCodec.parsePayload(mode: .hex, text: "zz"))
    }

    func testDecoderPreferenceMapsToNativeValues() {
        XCTAssertEqual(ExampleVideoDecoderPreference.automatic.nativeValue, 0)
        XCTAssertEqual(ExampleVideoDecoderPreference.software.nativeValue, 1)
        XCTAssertEqual(ExampleVideoDecoderPreference.hardware.nativeValue, 2)
    }

    func testThemeConstantsMatchFlutterSemantics() {
        XCTAssertEqual(ExampleTheme.backgroundHex, "#FFF8E8")
        XCTAssertEqual(ExampleTheme.primaryHex, "#659287")
        XCTAssertEqual(ExampleTheme.foregroundHex, "#FFFFFF")
        XCTAssertEqual(ExampleTheme.textPrimaryHex, "#666666")
        XCTAssertEqual(ExampleTheme.textSecondaryHex, "#848282")
        XCTAssertEqual(ExampleTheme.inputSurfaceHex, "#F4F1EA")
        XCTAssertEqual(ExampleTheme.inputBorderHex, "#E1DBCF")
        XCTAssertEqual(ExampleTheme.videoBackgroundHex, "#252525")
        XCTAssertEqual(ExampleTheme.failureHex, "#B42318")
    }

    private func tryResult<T>(_ result: Result<T, ExampleValidationError>) -> T? {
        if case .success(let value) = result {
            return value
        }
        return nil
    }

    private func failure<T>(_ result: Result<T, ExampleValidationError>) -> ExampleValidationError? {
        if case .failure(let error) = result {
            return error
        }
        return nil
    }
}
