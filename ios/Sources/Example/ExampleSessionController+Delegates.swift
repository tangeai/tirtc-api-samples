import CoreGraphics
import Foundation
import TiRTC

extension ExampleSessionController: TiRtcConnDelegate, TiRtcAudioOutputDelegate,
    TiRtcVideoOutputDelegate, @preconcurrency TiRtcAudioInputDelegate
{
    nonisolated func conn(_ conn: TiRtcConn, didChangeState state: TiRtcConnState, errorCode: Int32) {
        let rawValue = state.rawValue
        let isConnected = state == .connected
        let isDisconnected = state == .disconnected
        Task { @MainActor [weak self] in
            self?.setStatus("conn state=\(rawValue) error=\(errorCode)")
            if isConnected {
                self?.appendStatusLogLine("connected")
                self?.subscribeDownlink(conn)
            }
            if isDisconnected {
                self?.appendStatusLogLine("disconnected error=\(errorCode)")
                if errorCode != 0 {
                    self?.showUserFacingError(code: errorCode, context: "connect")
                }
            }
        }
    }

    nonisolated func conn(_ conn: TiRtcConn, didReceiveCommand commandId: UInt32, data: Data) {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            self.handleReceivedCommand(commandId: commandId, data: data)
        }
    }

    nonisolated func conn(
        _ conn: TiRtcConn,
        didReceiveStreamMessage streamId: UInt8,
        timestampMs: UInt32,
        data: Data
    ) {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            let payloadText = self.decodedPayloadText(data)
            self.setStatus(
                "recv stream=\(streamId) ts=\(timestampMs) bytes=\(data.count) payload=\(payloadText)"
            )
            if streamId == ControlDefaults.probeStreamId {
                self.appendStatusLogLine(
                    "probe-stream-echo stream=\(streamId) ts=\(timestampMs) payload=\(payloadText)"
                )
            }
        }
    }

    nonisolated func audioOutput(
        _ output: TiRtcAudioOutput, didChangeState state: TiRtcAudioOutputState
    ) {
        let rawValue = state.rawValue
        Task { @MainActor [weak self] in
            self?.setStatus("audio state=\(rawValue)")
            self?.appendStatusLogLine("audio-state=\(rawValue)")
        }
    }

    nonisolated func audioOutput(
        _ output: TiRtcAudioOutput, didFailWithCode code: Int32, message: String?
    ) {
        Task { @MainActor [weak self] in
            self?.setStatus("audio error=\(code) msg=\(message ?? "")")
            self?.showUserFacingError(code: code, context: "audio")
        }
    }

    nonisolated func videoOutput(
        _ output: TiRtcVideoOutput, didChangeState state: TiRtcVideoOutputState
    ) {
        let rawValue = state.rawValue
        Task { @MainActor [weak self] in
            self?.setStatus("video state=\(rawValue)")
            self?.appendStatusLogLine("video-state=\(rawValue)")
        }
    }

    nonisolated func videoOutput(_ output: TiRtcVideoOutput, didChangeRenderSize size: CGSize) {
        Task { @MainActor [weak self] in
            guard let self, self.lastLoggedVideoOutputSize != size else {
                return
            }
            self.lastLoggedVideoOutputSize = size
            self.isClientConnecting = false
            self.isClientVideoRendering = true
            self.setStatus("video size=\(Int(size.width))x\(Int(size.height))")
            self.appendStatusLogLine("video \(Int(size.width))x\(Int(size.height))")
            self.startDiagnosticsRefreshLoop()
        }
    }

    nonisolated func videoOutput(
        _ output: TiRtcVideoOutput, didFailWithCode code: Int32, message: String?
    ) {
        Task { @MainActor [weak self] in
            self?.setStatus("video error=\(code) msg=\(message ?? "")")
            self?.showUserFacingError(code: code, context: "video")
        }
    }

    nonisolated func appendCallbackStatusLogLine(_ text: String) {
        Self.appendCallbackStatusLogLine(text, path: callbackStatusLogPath)
    }

    nonisolated static func appendCallbackStatusLogLine(_ text: String, path: String?) {
        guard let path else {
            return
        }
        let url = URL(fileURLWithPath: path)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            let line = "\(text)\n"
            if FileManager.default.fileExists(atPath: path),
                let handle = try? FileHandle(forWritingTo: url)
            {
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(line.utf8))
                try handle.close()
            } else {
                try line.write(to: url, atomically: true, encoding: .utf8)
            }
        } catch {
            print("[Example] callback-status-log-write-failed \(error.localizedDescription)")
            fflush(stdout)
        }
    }

    func audioInput(_ input: TiRtcAudioInput, didChangeState state: TiRtcInputState) {
        let rawValue = state.rawValue
        if input === clientLocalAudioInput {
            isClientLocalAudioRunning = state == .running
            if state == .stopped || state == .failed {
                isClientLocalAudioBusy = false
            }
            clientLocalAudioStatus = "client local audio state=\(rawValue)"
        }
        setStatus("audio input state=\(rawValue)")
        appendStatusLogLine("audio-input-state=\(rawValue)")
    }

    func audioInput(_ input: TiRtcAudioInput, didFailWithCode code: Int32, message: String?) {
        if input === clientLocalAudioInput {
            isClientLocalAudioBusy = false
            isClientLocalAudioRunning = false
            clientLocalAudioStatus = "client local audio error=\(code)"
        }
        setStatus("audio input error=\(code) msg=\(message ?? "")")
        showUserFacingError(code: code, context: "audio input")
    }

}
