import AVFoundation
import Foundation
import SwiftUI
import TiRTC

private func appendInputMediaStatus(_ message: String) {
    FileHandle.standardOutput.write(Data((message + "\n").utf8))
    guard
        let path = ProcessInfo.processInfo.environment["TIRTC_INPUT_MEDIA_STATUS_LOG"],
        !path.isEmpty
    else { return }
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true)
    if !FileManager.default.fileExists(atPath: path) {
        _ = FileManager.default.createFile(atPath: path, contents: nil)
    }
    guard let handle = FileHandle(forWritingAtPath: path) else { return }
    defer { handle.closeFile() }
    handle.seekToEndOfFile()
    handle.write(Data((message + "\n").utf8))
}

// This test-owned App replaces only the entry point in the generated Example workspace.
@main
struct InputMediaApp: App {
    var body: some Scene { WindowGroup { InputMediaView() } }
}

private struct InputMediaView: View {
    @State private var result = "Input Media Case Running"
    var body: some View {
        Text(result).padding().onAppear {
            Task {
                do {
                    let environment = ProcessInfo.processInfo.environment
                    let payloadFile = environment["TIRTC_INPUT_MEDIA_PAYLOAD_FILE"] ?? ""
                    let encoded =
                        environment["TIRTC_INPUT_MEDIA_PAYLOAD"]
                        ?? (try? String(contentsOfFile: payloadFile, encoding: .utf8)) ?? ""
                    guard let data = Data(base64Encoded: encoded),
                        let payload = try JSONSerialization.jsonObject(with: data) as? [String: String]
                    else {
                        throw NSError(domain: "InputMediaCapture payload", code: 6000)
                    }
                    try await InputMediaCaptureCase().run(
                        payload: payload, status: appendInputMediaStatus)
                    result = "Input Media Case Passed"
                } catch { result = "Input Media Case Failed: \(error)" }
                appendInputMediaStatus(result)
            }
        }
    }
}
