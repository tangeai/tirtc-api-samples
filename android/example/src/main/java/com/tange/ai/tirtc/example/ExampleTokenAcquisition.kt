package com.tange.ai.tirtc.example

import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL

internal const val TOKEN_ISSUER_PATH = "/v1/tokens"

enum class DemoTokenSource {
    ISSUER,
    ONE_TIME,
}

internal fun resolveDemoToken(configuration: ClientConfiguration): ClientConfiguration {
    val token =
        when (configuration.tokenSource) {
            DemoTokenSource.ISSUER -> requestTokenFromIssuer(configuration.tokenIssuerBaseUrl, configuration.remoteId)
            DemoTokenSource.ONE_TIME -> normalizeConnectionToken(configuration.oneTimeToken)
        }
    return configuration.copy(token = token)
}

private fun requestTokenFromIssuer(
    rawUrl: String,
    remoteId: String,
): String {
    val request = tokenIssuerRequest(rawUrl, remoteId)
    val connection = request.url.openConnection() as HttpURLConnection
    connection.connectTimeout = TOKEN_REQUEST_TIMEOUT_MS
    connection.readTimeout = TOKEN_REQUEST_TIMEOUT_MS
    connection.requestMethod = request.method
    if (request.body != null) {
        connection.doOutput = true
        connection.setRequestProperty("Content-Type", "application/json")
        OutputStreamWriter(connection.outputStream, Charsets.UTF_8).use { writer ->
            writer.write(request.body)
        }
    }
    val statusCode = connection.responseCode
    val stream = if (statusCode in 200..299) connection.inputStream else connection.errorStream
    val body = stream.bufferedReader(Charsets.UTF_8).use { it.readText() }
    connection.disconnect()
    if (statusCode !in 200..299) {
        error("issuer returned HTTP $statusCode")
    }
    return parseTokenIssuerResponse(body)
}

private data class TokenIssuerRequest(
    val url: URL,
    val method: String,
    val body: String?,
)

private fun tokenIssuerRequest(
    rawUrl: String,
    remoteId: String,
): TokenIssuerRequest {
    val url = URL(rawUrl.trim())
    val protocol = url.protocol.lowercase()
    require(protocol == "http" || protocol == "https") {
        "tokenIssuerBaseUrl must be an http(s) URL"
    }
    val fixedPath = url.query == null && (url.path.isBlank() || url.path == "/" || url.path == TOKEN_ISSUER_PATH)
    if (!fixedPath) {
        return TokenIssuerRequest(url, "GET", null)
    }
    val tokenUrl = URL(protocol, url.host, url.port, TOKEN_ISSUER_PATH)
    val body = JSONObject().put("remote_id", remoteId).toString()
    return TokenIssuerRequest(tokenUrl, "POST", body)
}

private fun parseTokenIssuerResponse(body: String): String {
    val text = body.trim()
    if (connectionTokenLooksValid(text)) {
        return normalizeConnectionToken(text)
    }
    val token = JSONObject(text).optString("token").trim()
    return normalizeConnectionToken(token)
}

private fun normalizeConnectionToken(raw: String): String {
    val token = raw.trim()
    require(connectionTokenLooksValid(token)) {
        "token must start with v1."
    }
    return token
}

private fun connectionTokenLooksValid(value: String): Boolean = value.trim().startsWith("v1.")

private const val TOKEN_REQUEST_TIMEOUT_MS = 10_000
