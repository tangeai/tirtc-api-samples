package com.tange.ai.tirtc.example

internal const val DEMO_CALL_COMMAND_ID = 0x54524343L
internal const val CALL_START = "start_call"
internal const val CALL_READY = "call_ready"
internal const val CALL_REJECT = "call_reject"

internal enum class DemoCallCommandAction(
    val wireName: String,
) {
    START(CALL_START),
    READY(CALL_READY),
    REJECT(CALL_REJECT),
}

internal fun demoCallCommandActionFromPayload(payload: ByteArray): DemoCallCommandAction? {
    val text = payloadText(payload).trim()
    return DemoCallCommandAction.entries.firstOrNull { it.wireName == text }
}

internal fun demoCommandResponsePayload(
    commandId: Long,
    payload: ByteArray,
): ByteArray? {
    if (commandId != DEMO_CALL_COMMAND_ID) {
        return payload
    }
    return when (demoCallCommandActionFromPayload(payload)) {
        DemoCallCommandAction.START -> utf8Payload(CALL_READY)
        DemoCallCommandAction.READY,
        DemoCallCommandAction.REJECT,
        null,
        -> null
    }
}

internal fun demoCommandPresetPayload(position: Int): String {
    return when (position) {
        1 -> CALL_START
        2 -> CALL_READY
        3 -> CALL_REJECT
        else -> "echo"
    }
}
