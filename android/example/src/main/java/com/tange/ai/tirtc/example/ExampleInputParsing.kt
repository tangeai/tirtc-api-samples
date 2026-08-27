package com.tange.ai.tirtc.example

import org.json.JSONObject
import java.nio.charset.StandardCharsets
import java.net.URI

internal fun parseClientQrPayload(
    payload: String,
    current: ClientConfiguration,
    onError: (String) -> Unit,
): ClientConfiguration? {
    val text = payload.trim()
    if (!text.startsWith("{")) {
        if (!text.startsWith("v1.")) {
            onError("二维码内容不是有效的一次性 Token")
            return null
        }
        return current.copy(token = text, oneTimeToken = text, tokenSource = DemoTokenSource.ONE_TIME)
    }
    return try {
        val json = JSONObject(text)
        if (!json.keys().asSequence().all { it in setOf("app_id", "remote_id", "endpoint", "token") }) {
            onError("二维码包含不支持的字段")
            return null
        }
        val appId = json.optString("app_id").trim()
        val remoteId = json.optString("remote_id").trim()
        val token = json.optString("token").trim()
        val endpoint = json.optString("endpoint").trim()
        if (appId.isBlank() || remoteId.isBlank() || !token.startsWith("v1.") || !validRtcEndpoint(endpoint)) {
            onError("二维码缺少 app_id、remote_id 或 token")
            null
        } else {
            current.copy(
                appId = appId,
                endpoint = endpoint,
                remoteId = remoteId,
                token = token,
                oneTimeToken = token,
                tokenSource = DemoTokenSource.ONE_TIME,
            )
        }
    } catch (error: Exception) {
        onError("二维码 JSON 无效：${error.message}")
        null
    }
}

internal fun parseCloudStorageQrPayload(
    payload: String,
    current: CloudStorageConfiguration,
    onError: (String) -> Unit,
): CloudStorageConfiguration? {
    val text = payload.trim()
    if (!text.startsWith("{")) {
        if (text.isEmpty() || text.any(Char::isWhitespace)) {
            onError("二维码内容不是有效的云录像 Token")
            return null
        }
        return current.copy(token = text)
    }
    return try {
        val json = JSONObject(text)
        if (!json.keys().asSequence().all { it in setOf("app_id", "endpoint", "token") }) {
            onError("二维码包含不支持的字段")
            return null
        }
        val appId = json.optString("app_id").trim()
        val endpoint = json.optString("endpoint").trim()
        val token = json.optString("token").trim()
        if (appId.isEmpty() || token.isEmpty() || token.any(Char::isWhitespace) || !validCloudStorageEndpoint(endpoint)) {
            onError("二维码缺少有效的 app_id、endpoint 或 token")
            null
        } else {
            current.copy(appId = appId, endpoint = endpoint, token = token)
        }
    } catch (error: Exception) {
        onError("二维码 JSON 无效：${error.message}")
        null
    }
}

private fun validRtcEndpoint(value: String): Boolean =
    value.isEmpty() || validHttpEndpoint(value, httpsOnly = false)

private fun validCloudStorageEndpoint(value: String): Boolean =
    value.isEmpty() || validHttpEndpoint(value, httpsOnly = true)

private fun validHttpEndpoint(
    value: String,
    httpsOnly: Boolean,
): Boolean =
    try {
        val uri = URI(value)
        uri.isAbsolute && uri.host?.isNotEmpty() == true && uri.userInfo == null && uri.fragment == null &&
            if (httpsOnly) uri.scheme == "https" else uri.scheme == "http" || uri.scheme == "https"
    } catch (_: Exception) {
        false
    }

internal fun parseCommandIdOrNull(
    text: String,
    onError: (String) -> Unit,
): Long? {
    val trimmed = text.trim()
    val value =
        if (trimmed.startsWith("0x", ignoreCase = true)) {
            trimmed.removePrefix("0x").removePrefix("0X").toLongOrNull(16)
        } else {
            trimmed.toLongOrNull()
        }
    if (value == null || value !in 0..MAX_COMMAND_ID) {
        onError("命令 ID 必须是 32 位无符号整数")
        return null
    }
    return value
}

internal fun parseHexPayloadOrNull(
    text: String,
    onError: (String) -> Unit,
): ByteArray? {
    val compact = text.filterNot { it.isWhitespace() }
    if (compact.length % 2 != 0 || !compact.all { it in '0'..'9' || it in 'a'..'f' || it in 'A'..'F' }) {
        onError("HEX 内容必须是偶数位有效字符")
        return null
    }
    return ByteArray(compact.length / 2) { index ->
        compact.substring(index * 2, index * 2 + 2).toInt(16).toByte()
    }
}

internal fun utf8Payload(text: String): ByteArray = text.toByteArray(StandardCharsets.UTF_8)

internal fun payloadText(payload: ByteArray): String = String(payload, StandardCharsets.UTF_8)

internal fun formatCommandId(command: Long): String = "0x${command.toString(16).uppercase()}"

internal fun maskSecretValue(value: String): String {
    if (value.length <= 4) {
        return "****"
    }
    return "${value.take(2)}****${value.takeLast(2)}"
}

internal const val MAX_COMMAND_ID = 0xFFFF_FFFFL
