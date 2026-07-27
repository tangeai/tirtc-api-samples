import 'dart:async';
import 'dart:convert';
import 'dart:io';

const int demoTokenResponseByteLimit = 8192;
const Duration demoTokenRequestTimeout = Duration(seconds: 10);
const String demoTokenServerPath = '/v1/tokens';

final class DemoTokenAcquirer {
  const DemoTokenAcquirer({
    this.httpClient = demoDefaultTokenHttpClient,
  });

  final DemoTokenHttpClient httpClient;

  Future<String> resolve({
    required String token,
    String serverAddress = '',
    String remoteId = '',
  }) async {
    if (token.trim().isNotEmpty) {
      return normalizeDemoConnectionToken(token);
    }

    final DemoTokenHttpResponse response = await httpClient(
      DemoTokenHttpRequest(
        uri: demoTokenServerUri(serverAddress),
        jsonBody: <String, String>{'remote_id': remoteId},
      ),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('DevTools 服务返回 HTTP ${response.statusCode}');
    }
    return parseDemoTokenServerResponse(response.body);
  }
}

final class DemoTokenHttpRequest {
  const DemoTokenHttpRequest({
    required this.uri,
    required this.jsonBody,
  });

  final Uri uri;
  final Map<String, String> jsonBody;
}

final class DemoTokenHttpResponse {
  const DemoTokenHttpResponse({
    required this.statusCode,
    required this.body,
  });

  final int statusCode;
  final String body;
}

typedef DemoTokenHttpClient = Future<DemoTokenHttpResponse> Function(DemoTokenHttpRequest request);

Future<DemoTokenHttpResponse> demoDefaultTokenHttpClient(DemoTokenHttpRequest request) async {
  final HttpClient client = HttpClient();
  client.connectionTimeout = demoTokenRequestTimeout;
  try {
    final HttpClientRequest httpRequest = await client.postUrl(request.uri).timeout(demoTokenRequestTimeout);
    httpRequest.headers.contentType = ContentType.json;
    httpRequest.write(jsonEncode(request.jsonBody));

    final HttpClientResponse response = await httpRequest.close().timeout(demoTokenRequestTimeout);
    final List<int> bytes = await response.take(demoTokenResponseByteLimit + 1).fold<List<int>>(
      <int>[],
      (List<int> result, List<int> chunk) => result..addAll(chunk),
    );
    if (bytes.length > demoTokenResponseByteLimit) {
      throw StateError('DevTools 服务响应过大');
    }
    return DemoTokenHttpResponse(
      statusCode: response.statusCode,
      body: utf8.decode(bytes),
    );
  } finally {
    client.close(force: true);
  }
}

String normalizeDemoTokenServerAddress(String rawValue) {
  final Uri uri = _parseDemoTokenServerAddress(rawValue);
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
  ).toString();
}

Uri demoTokenServerUri(String rawValue) {
  final Uri uri = _parseDemoTokenServerAddress(rawValue);
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: demoTokenServerPath,
  );
}

Uri _parseDemoTokenServerAddress(String rawValue) {
  final Uri? uri = Uri.tryParse(rawValue.trim());
  if (uri == null ||
      uri.host.isEmpty ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      (uri.path.isNotEmpty && uri.path != '/') ||
      uri.hasQuery ||
      uri.hasFragment ||
      uri.userInfo.isNotEmpty) {
    throw const FormatException('DevTools server address must be an http(s) origin');
  }
  return uri;
}

String parseDemoTokenServerResponse(String body) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    throw StateError('DevTools 服务响应不是有效 JSON');
  }
  if (decoded is! Map<String, Object?> || decoded['token'] is! String) {
    throw StateError('DevTools 服务响应缺少 token');
  }
  return normalizeDemoConnectionToken(decoded['token']! as String);
}

String normalizeDemoConnectionToken(String rawValue) {
  final String token = rawValue.trim();
  if (!demoConnectionTokenLooksValid(token)) {
    throw const FormatException('token must start with v1.');
  }
  return token;
}

bool demoConnectionTokenLooksValid(String value) {
  return value.trim().startsWith('v1.');
}

final class DemoScanPayload {
  const DemoScanPayload({
    required this.token,
    this.appId,
    this.remoteId,
    this.endpoint,
  });

  final String token;
  final String? appId;
  final String? remoteId;
  final String? endpoint;

  bool get hasConnectionFields => appId != null && remoteId != null;

  static const Set<String> _allowedPayloadKeys = <String>{
    'app_id',
    'remote_id',
    'endpoint',
    'token',
  };

  static DemoScanPayload? tryParse(String rawValue) {
    final String text = rawValue.trim();
    if (text.isEmpty) {
      return null;
    }
    if (text.startsWith('{')) {
      return _tryParseJson(text);
    }
    if (demoConnectionTokenLooksValid(text)) {
      return DemoScanPayload(token: normalizeDemoConnectionToken(text));
    }
    return null;
  }

  static DemoScanPayload? _tryParseJson(String rawValue) {
    final Object? decoded;
    try {
      decoded = jsonDecode(_normalizeJson(rawValue));
    } on FormatException {
      return null;
    }
    if (decoded is! Map<Object?, Object?>) {
      return null;
    }

    for (final Object? key in decoded.keys) {
      if (key is! String || !_allowedPayloadKeys.contains(key)) {
        return null;
      }
    }

    final String appId = _stringValue(decoded['app_id']);
    final String remoteId = _stringValue(decoded['remote_id']);
    final String token = _stringValue(decoded['token']);
    final Object? rawEndpoint = decoded['endpoint'];
    if (appId.isEmpty || remoteId.isEmpty || token.isEmpty) {
      return null;
    }
    if (!demoConnectionTokenLooksValid(token)) {
      return null;
    }
    if (decoded.containsKey('endpoint') && rawEndpoint != null && rawEndpoint is! String) {
      return null;
    }
    final String? endpoint = rawEndpoint is String ? rawEndpoint.trim() : null;
    if (endpoint != null && endpoint.isNotEmpty && !_validEndpoint(endpoint)) {
      return null;
    }
    return DemoScanPayload(
      appId: appId,
      remoteId: remoteId,
      token: normalizeDemoConnectionToken(token),
      endpoint: endpoint == null || endpoint.isEmpty ? null : endpoint,
    );
  }

  static String _normalizeJson(String rawValue) {
    return rawValue.replaceAll(RegExp(r',\s*}'), '}').replaceAll(RegExp(r',\s*]'), ']');
  }

  static String _stringValue(Object? value) {
    return switch (value) {
      final String text => text.trim(),
      _ => '',
    };
  }
}

bool _validEndpoint(String text) {
  if (text.isEmpty) {
    return true;
  }
  final Uri? uri = Uri.tryParse(text);
  return uri != null && uri.host.isNotEmpty && (uri.scheme == 'http' || uri.scheme == 'https');
}
