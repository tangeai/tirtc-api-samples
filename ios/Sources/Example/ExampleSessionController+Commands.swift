import Foundation

@MainActor
extension ExampleSessionController {
    func sendCommandFromPanel() {
        guard let conn else {
            setStatus("connection not ready")
            return
        }
        guard let commandId = ExampleCommandPanelCodec.parseCommandId(commandIdText) else {
            setStatus("command id is invalid")
            return
        }
        let payloadMode =
            ExampleCommandPanelPayloadMode(rawValue: commandPayloadMode) ?? .hex
        guard
            let commandPayload = ExampleCommandPanelCodec.parsePayload(
                mode: payloadMode,
                text: commandPayloadText)
        else {
            setStatus("command payload is invalid")
            return
        }
        let commandCode = conn.sendCommand(commandId: commandId, data: commandPayload)
        trackLocalEchoSend(commandId: commandId, payload: commandPayload, resultCode: commandCode)
        recordCommandEvent(
            .sent,
            commandId: commandId,
            payload: ExampleCommandPanelCodec.formatPayloadHex(commandPayload),
            resultCode: commandCode)
        setStatus("command=\(commandCode)")
        appendStatusLogLine(
            "command-dispatch command_id=\(ExampleCommandPanelCodec.formatCommandId(commandId)) payload_mode=\(payloadMode.rawValue) payload_bytes=\(commandPayload.count) code=\(commandCode)"
        )
        if commandCode != 0 {
            showUserFacingError(code: commandCode, context: "command")
        }
    }

    func applyEchoCommandPreset() {
        commandIdText = ExampleCommandPanelCodec.formatCommandId(ExampleCommandPanelCodec.echoCommandId)
        commandPayloadMode = ExampleCommandPanelPayloadMode.text.rawValue
        commandPayloadText = ExampleCommandPanelCodec.echoPayloadText
    }

    func applyCallCommandPreset(_ action: ExampleCallCommandAction) {
        let command = ExampleCallCommand(
            action: action,
            requestId: UUID().uuidString,
            audioEnabled: true,
            videoEnabled: true,
            reason: action == .callReject ? "manual_reject" : nil)
        commandIdText = ExampleCommandPanelCodec.formatCommandId(ExampleCommandPanelCodec.callCommandId)
        commandPayloadMode = ExampleCommandPanelPayloadMode.text.rawValue
        commandPayloadText = String(data: command.encode(), encoding: .utf8) ?? ""
    }

    func recordCommandEvent(
        _ direction: ExampleCommandPanelEvent.Direction,
        commandId: UInt32,
        payload: String,
        resultCode: Int32?
    ) {
        let event = ExampleCommandPanelEvent(
            direction: direction,
            commandId: commandId,
            payload: payload,
            resultCode: resultCode
        )
        commandEvents = ExampleCommandPanelEvent.appending(event, to: commandEvents)
    }

    func handleReceivedCommand(commandId: UInt32, data: Data) {
        let payloadHex = ExampleCommandPanelCodec.formatPayloadHex(data)
        let receivedCallCommand = ExampleCallCommand.decode(commandId: commandId, data: data)
        recordCommandEvent(
            .received,
            commandId: commandId,
            payload: payloadHex,
            resultCode: nil)
        setStatus(
            "recv command=\(ExampleCommandPanelCodec.formatCommandId(commandId)) bytes=\(data.count) payload=\(payloadHex)"
        )
        if let receivedCallCommand {
            appendStatusLogLine(
                "call_command_received action=\(receivedCallCommand.action.rawValue) request_id=\(receivedCallCommand.requestId)"
            )
            if receivedCallCommand.action == .startCall {
                replyCallReady(receivedCallCommand)
            }
            return
        }
        guard ExampleCommandPanelCodec.isEchoCommand(commandId: commandId, payload: data) else {
            return
        }
        if pendingLocalEchoReplies > 0 {
            pendingLocalEchoReplies -= 1
            appendStatusLogLine(
                "echo-reply-received command_id=\(ExampleCommandPanelCodec.formatCommandId(commandId))"
            )
            return
        }
        guard let target = conn else {
            appendStatusLogLine(
                "echo-command-reply-skipped command_id=\(ExampleCommandPanelCodec.formatCommandId(commandId)) reason=no_active_connection"
            )
            return
        }
        let code = target.sendCommand(commandId: commandId, data: data)
        trackLocalEchoSend(commandId: commandId, payload: data, resultCode: code)
        recordCommandEvent(
            .sent,
            commandId: commandId,
            payload: payloadHex,
            resultCode: code)
        appendStatusLogLine(
            "echo-command-replied command_id=\(ExampleCommandPanelCodec.formatCommandId(commandId)) code=\(code)"
        )
        if code != 0 {
            showUserFacingError(code: code, context: "echo command")
        }
    }

    func decodedPayloadText(_ data: Data) -> String {
        let text = String(data: data, encoding: .utf8) ?? "<non-utf8>"
        return text.replacingOccurrences(of: "\n", with: "\\n")
    }

    private func replyCallReady(_ command: ExampleCallCommand) {
        guard let target = conn else {
            appendStatusLogLine("call_ready_skipped reason=no_active_connection")
            return
        }
        let response = ExampleCallCommand(
            action: .callReady,
            requestId: command.requestId,
            audioEnabled: command.audioEnabled,
            videoEnabled: command.videoEnabled,
            reason: nil)
        let payload = response.encode()
        let code = target.sendCommand(commandId: ExampleCommandPanelCodec.callCommandId, data: payload)
        recordCommandEvent(
            .sent,
            commandId: ExampleCommandPanelCodec.callCommandId,
            payload: ExampleCommandPanelCodec.formatPayloadHex(payload),
            resultCode: code)
        appendStatusLogLine("call_ready_sent request_id=\(command.requestId) code=\(code)")
        if code != 0 {
            showUserFacingError(code: code, context: "call_ready")
        }
    }

    private func trackLocalEchoSend(commandId: UInt32, payload: Data, resultCode: Int32) {
        guard resultCode == 0,
            ExampleCommandPanelCodec.isEchoCommand(commandId: commandId, payload: payload)
        else {
            return
        }
        pendingLocalEchoReplies += 1
    }
}
