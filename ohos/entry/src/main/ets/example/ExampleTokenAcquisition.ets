import { http } from '@kit.NetworkKit';

export const DEMO_TOKEN_ISSUER_TOKEN_PATH: string = '/v1/tokens';
const TOKEN_REQUEST_TIMEOUT_MS: number = 10000;
const TOKEN_RESPONSE_BYTE_LIMIT: number = 8192;

export enum DemoTokenSource {
  issuer,
  oneTime,
}

export interface DemoScanPayload {
  appId?: string;
  remoteId?: string;
  endpoint?: string;
  token: string;
}

interface DemoTokenIssuerParts {
  scheme: string;
  authority: string;
  path: string;
  query: string;
  hasQuery: boolean;
}

interface DemoTokenHttpRequest {
  url: string;
  method: string;
  jsonBody?: string;
}

type JsonObject = Record<string, Object | null>;

export function parseDemoTokenSource(value: string): DemoTokenSource {
  return value.trim() === 'one_time' ? DemoTokenSource.oneTime : DemoTokenSource.issuer;
}

export function demoTokenSourceStorageValue(value: DemoTokenSource): string {
  return value === DemoTokenSource.oneTime ? 'one_time' : 'issuer';
}

export function demoConnectionTokenLooksValid(value: string): boolean {
  return value.trim().startsWith('v1.');
}

export function normalizeDemoConnectionToken(rawValue: string): string {
  const token = rawValue.trim();
  if (!demoConnectionTokenLooksValid(token)) {
    throw new Error('token must start with v1.');
  }
  return token;
}

export function normalizeDemoTokenIssuerBaseUrl(rawValue: string): string {
  const parts = parseIssuerUrl(rawValue);
  if (isFixedPathIssuerAddress(parts)) {
    return issuerOrigin(parts);
  }
  return buildUrl(parts);
}

export async function resolveDemoConnectionToken(
  source: DemoTokenSource,
  tokenIssuerBaseUrl: string,
  oneTimeToken: string,
  remoteId: string,
): Promise<string> {
  if (source === DemoTokenSource.oneTime) {
    return normalizeDemoConnectionToken(oneTimeToken);
  }
  const request = demoTokenIssuerRequest(tokenIssuerBaseUrl, remoteId);
  const client = http.createHttp();
  try {
    let options: http.HttpRequestOptions;
    if (request.method === 'POST') {
      const headers: Record<string, string> = { 'Content-Type': 'application/json' };
      options = {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: request.jsonBody ?? '',
        connectTimeout: TOKEN_REQUEST_TIMEOUT_MS,
        readTimeout: TOKEN_REQUEST_TIMEOUT_MS,
      };
    } else {
      options = {
        method: http.RequestMethod.GET,
        connectTimeout: TOKEN_REQUEST_TIMEOUT_MS,
        readTimeout: TOKEN_REQUEST_TIMEOUT_MS,
      };
    }
    const response = await client.request(request.url, options);
    const resultText = response.result === undefined ? '' : String(response.result);
    if (resultText.length > TOKEN_RESPONSE_BYTE_LIMIT) {
      throw new Error('token response too large');
    }
    if (response.responseCode < 200 || response.responseCode >= 300) {
      throw new Error(`issuer returned HTTP ${response.responseCode}`);
    }
    return parseDemoTokenIssuerResponse(resultText);
  } finally {
    client.destroy();
  }
}

export function parseDemoTokenIssuerResponse(body: string): string {
  const value = body.trim();
  if (demoConnectionTokenLooksValid(value)) {
    return normalizeDemoConnectionToken(value);
  }
  const decoded = parseJsonObject(value);
  if (decoded === undefined) {
    throw new Error('issuer response is not a token or JSON object');
  }
  const token = stringValue(decoded['token']);
  return normalizeDemoConnectionToken(token);
}

export function tryParseDemoScanPayload(rawValue: string): DemoScanPayload | undefined {
  const text = rawValue.trim();
  if (text.length === 0) {
    return undefined;
  }
  if (!text.startsWith('{')) {
    if (demoConnectionTokenLooksValid(text)) {
      return { token: normalizeDemoConnectionToken(text) };
    }
    return undefined;
  }

  const decoded = parseJsonObject(normalizeScanJson(text));
  if (decoded === undefined) {
    return undefined;
  }
  const keys = Object.keys(decoded);
  for (let index = 0; index < keys.length; index += 1) {
    const key = keys[index];
    if (key !== 'app_id' && key !== 'remote_id' && key !== 'endpoint' && key !== 'token') {
      return undefined;
    }
  }

  const appId = stringValue(decoded['app_id']);
  const remoteId = stringValue(decoded['remote_id']);
  const token = stringValue(decoded['token']);
  const endpointRaw = decoded['endpoint'];
  const hasEndpoint = keys.indexOf('endpoint') >= 0;
  if (appId.length === 0 || remoteId.length === 0 || token.length === 0) {
    return undefined;
  }
  if (!demoConnectionTokenLooksValid(token)) {
    return undefined;
  }
  if (hasEndpoint && typeof endpointRaw !== 'string') {
    return undefined;
  }
  const endpoint = typeof endpointRaw === 'string' ? endpointRaw.trim() : '';
  if (endpoint.length > 0 && !validHttpEndpoint(endpoint)) {
    return undefined;
  }
  return {
    appId,
    remoteId,
    token: normalizeDemoConnectionToken(token),
    endpoint: endpoint.length > 0 ? endpoint : undefined,
  };
}

function demoTokenIssuerRequest(rawValue: string, remoteId: string): DemoTokenHttpRequest {
  const parts = parseIssuerUrl(rawValue);
  if (isFixedPathIssuerAddress(parts)) {
    return {
      url: `${issuerOrigin(parts)}${DEMO_TOKEN_ISSUER_TOKEN_PATH}`,
      method: 'POST',
      jsonBody: JSON.stringify({ remote_id: remoteId }),
    };
  }
  return {
    url: buildUrl(parts),
    method: 'GET',
  };
}

function parseIssuerUrl(rawValue: string): DemoTokenIssuerParts {
  const value = rawValue.trim();
  const match = /^(https?):\/\/([^\/?#]+)([^?#]*)(\?[^#]*)?$/i.exec(value);
  if (match === null || match[2].length === 0) {
    throw new Error('token issuer address must be a full http(s) URL');
  }
  if (match[2].indexOf('@') >= 0) {
    throw new Error('token issuer address must not include user info');
  }
  const scheme = match[1].toLowerCase();
  const authority = match[2];
  const path = match[3] ?? '';
  const query = match[4] === undefined ? '' : match[4].substring(1);
  return {
    scheme,
    authority,
    path,
    query,
    hasQuery: match[4] !== undefined,
  };
}

function isFixedPathIssuerAddress(parts: DemoTokenIssuerParts): boolean {
  return !parts.hasQuery &&
    (parts.path.length === 0 || parts.path === '/' || parts.path === DEMO_TOKEN_ISSUER_TOKEN_PATH);
}

function issuerOrigin(parts: DemoTokenIssuerParts): string {
  return `${parts.scheme}://${parts.authority}`;
}

function buildUrl(parts: DemoTokenIssuerParts): string {
  const path = parts.path.length === 0 ? '/' : parts.path;
  return parts.hasQuery ? `${issuerOrigin(parts)}${path}?${parts.query}` : `${issuerOrigin(parts)}${path}`;
}

function validHttpEndpoint(text: string): boolean {
  return /^(https?):\/\/([^\/?#@]+)([^?#]*)(\?[^#]*)?$/i.test(text.trim());
}

function normalizeScanJson(rawValue: string): string {
  return rawValue.replace(/,\s*}/g, '}').replace(/,\s*]/g, ']');
}

function parseJsonObject(text: string): JsonObject | undefined {
  try {
    const decoded = JSON.parse(text) as JsonObject;
    if (decoded === null || Array.isArray(decoded) || typeof decoded !== 'object') {
      return undefined;
    }
    return decoded;
  } catch (_) {
    return undefined;
  }
}

function stringValue(value: Object | null | undefined): string {
  return typeof value === 'string' ? value.trim() : '';
}
