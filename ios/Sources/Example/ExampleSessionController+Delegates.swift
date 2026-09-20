import CoreGraphics
import Foundation
import TiRTC

extension ExampleSessionController: TiRtcConnDelegate, TiRtcAudioOutputDelegate,
    TiRtcVideoOutputDelegate, @preconcurrency TiRtcAudioInputDelegate
{
    nonisolated func conn(_ conn: TiRtcConn, didChangeState state: TiRtcConnState, errorCode: Int32) {
        let connectionIdentity = ObjectIdentifier(conn)
        let rawValue = state.rawValue
        let isConnected = state == .connected
        let isDisconnected = state == .disconnected
        Task { @MainActor [weak self] in
            guard let self, let activeConnection = self.conn,
                ObjectIdentifier(activeConnection) == connectionIdentity
            else { return }
            self.setStatus("conn state=\(rawValue) error=\(errorCode)")
            if isConnected {
                self.appendStatusLogLine("connected")
                self.subscribeDownlink(activeConnection)
            }
            if isDisconnected {
                self.appendStatusLogLine("disconnected error=\(errorCode)")
                if errorCode != 0 {
                    self.showUserFacingError(code: errorCode, context: "connect")
                }
            }
        }
    }

    nonisolated func conn(_ conn: TiRtcConn, didReceiveCommand commandId: UInt32, data: Data) {
        let connectionIdentity = ObjectIdentifier(conn)
        Task { @MainActor [weak self] in
            guard let self, let activeConnection = self.conn,
                ObjectIdentifier(activeConnection) == connectionIdentity
            else { return }
            self.handleReceivedCommand(commandId: commandId, data: data)
        }
    }

    nonisolated func conn(
        _ conn: TiRtcConn,
        didReceiveStreamMessage streamId: UInt8,
        timestampMs: UInt32,
        data: Data
    ) {
        let connectionIdentity = ObjectIdentifier(conn)
        Task { @MainActor [weak self] in
            guard let self, let activeConnection = self.conn,
                ObjectIdentifier(activeConnection) == connectionIdentity
            else { return }
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
        let outputIdentity = ObjectIdentifier(output)
        let rawValue = state.rawValue
        let nextState = TiRtcAudioOutputState(rawValue: rawValue) ?? .failed
        Task { @MainActor [weak self] in
            guard let self, let audioOutput = self.audioOutput,
                ObjectIdentifier(audioOutput) == outputIdentity
            else { return }
            self.isAudioOutputAvailable = nextState != .failed && nextState != .completed
            if nextState == .playing {
                self.isClientConnecting = false
                if !self.isAudioOutputMuted {
                    self.audioOutputVolumeStatus = "audible"
                }
            } else if !self.isAudioOutputAvailable,
                !self.videoStates.values.contains(where: { $0 != .failed })
            {
                self.isClientConnecting = false
            }
            self.setStatus("audio state=\(rawValue)")
            self.appendStatusLogLine("audio-state=\(rawValue)")
        }
    }

    nonisolated func audioOutput(
        _ output: TiRtcAudioOutput, didFailWithCode code: Int32, message: String?
    ) {
        let outputIdentity = ObjectIdentifier(output)
        Task { @MainActor [weak self] in
            guard let self, let audioOutput = self.audioOutput,
                ObjectIdentifier(audioOutput) == outputIdentity
            else { return }
            self.isAudioOutputAvailable = false
            self.audioOutputVolumeStatus = "failed code=\(code)"
            self.isClientConnecting = false
            self.setStatus("audio error=\(code) msg=\(message ?? "")")
            self.appendStatusLogLine("audio-output-failed phase=runtime code=\(code)")
        }
    }

    nonisolated func videoOutput(
        _ output: TiRtcVideoOutput, didChangeState state: TiRtcVideoOutputState
    ) {
        let outputIdentity = ObjectIdentifier(output)
        let rawValue = state.rawValue
        Task { @MainActor [weak self] in
            guard let self,
                let streamId = self.videoOutputs.first(where: {
                    ObjectIdentifier($0.value) == outputIdentity
                })?.key
            else { return }
            self.videoStates[streamId] = TiRtcVideoOutputState(rawValue: rawValue) ?? .failed
            self.isClientVideoRendering = self.videoStates.values.contains(.rendering)
            if !self.videoStates.values.contains(where: { $0 != .failed }),
                !self.isAudioOutputAvailable
            {
                self.isClientConnecting = false
            }
            self.setStatus("video[\(streamId)] state=\(rawValue)")
            self.appendStatusLogLine("video-state stream_id=\(streamId) state=\(rawValue)")
        }
    }

    nonisolated func videoOutput(_ output: TiRtcVideoOutput, didChangeRenderSize size: CGSize) {
        let outputIdentity = ObjectIdentifier(output)
        let width = size.width
        let height = size.height
        Task { @MainActor [weak self] in
            guard let self,
                let streamId = self.videoOutputs.first(where: {
                    ObjectIdentifier($0.value) == outputIdentity
                })?.key
            else { return }
            self.lastLoggedVideoOutputSize = CGSize(width: width, height: height)
            self.isClientConnecting = false
            self.isClientVideoRendering = true
            self.setStatus("video[\(streamId)] size=\(Int(width))x\(Int(height))")
            self.appendStatusLogLine("video stream_id=\(streamId) \(Int(width))x\(Int(height))")
            self.startDiagnosticsRefreshLoop()
        }
    }

    nonisolated func videoOutput(
        _ output: TiRtcVideoOutput, didFailWithCode code: Int32, message: String?
    ) {
        let outputIdentity = ObjectIdentifier(output)
        Task { @MainActor [weak self] in
            guard let self,
                let streamId = self.videoOutputs.first(where: {
                    ObjectIdentifier($0.value) == outputIdentity
                })?.key
            else { return }
            self.videoStates[streamId] = .failed
            self.isClientVideoRendering = self.videoStates.values.contains(.rendering)
            if !self.videoStates.values.contains(where: { $0 != .failed }) {
                self.isClientConnecting = false
            }
            self.setStatus("video[\(streamId)] error=\(code) msg=\(message ?? "")")
            self.appendStatusLogLine(
                "video-output-failed phase=runtime stream_id=\(streamId) code=\(code)")
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
