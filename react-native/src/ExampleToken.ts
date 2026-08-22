import type {ExampleConfig} from './ExampleTypes';

export async function resolveToken(config: ExampleConfig): Promise<string> {
  if (config.token.trim()) {
    return normalizeToken(config.token);
  }
  const origin = normalizeTokenServerOrigin(config.tokenServerAddress);
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), TOKEN_REQUEST_TIMEOUT_MS);
  let response: Response;
  try {
    response = await fetch(`${origin}/v1/tokens`, {
      method: 'POST',
      headers: {'content-type': 'application/json'},
      body: JSON.stringify({remote_id: config.remoteId}),
      signal: controller.signal,
    });
  } catch (error) {
    if (controller.signal.aborted) {
      throw new Error('DevTools 服务请求超时');
    }
    throw error;
  } finally {
    clearTimeout(timeout);
  }
  if (!response.ok) {
    throw new Error(`DevTools 服务返回 HTTP ${response.status}`);
  }
  const contentLength = Number.parseInt(response.headers.get('content-length') ?? '', 10);
  if (Number.isFinite(contentLength) && contentLength > TOKEN_RESPONSE_LIMIT) {
    throw new Error('DevTools 服务响应过大');
  }
  const body = await response.text();
  if (body.length > TOKEN_RESPONSE_LIMIT) {
    throw new Error('DevTools 服务响应过大');
  }
  const decoded = JSON.parse(body) as unknown;
  if (decoded === null || typeof decoded !== 'object' || typeof (decoded as {token?: unknown}).token !== 'string') {
    throw new Error('DevTools 服务响应缺少 token');
  }
  return normalizeToken((decoded as {token: string}).token);
}

export async function resolveStoreToken(value: string): Promise<string> {
  const candidate = value.trim();
  if (!candidate) {
    throw new Error('token is required.');
  }
  if (!/^https?:\/\//i.test(candidate)) {
    return normalizeStoreToken(candidate);
  }

  const response = await fetch(candidate);
  if (!response.ok) {
    throw new Error(`token handoff failed (${response.status}).`);
  }
  const contentLength = Number.parseInt(response.headers.get('content-length') ?? '', 10);
  if (Number.isFinite(contentLength) && contentLength > STORE_TOKEN_LIMIT) {
    throw new Error('token handoff is too large.');
  }
  return normalizeStoreToken(await response.text());
}

const STORE_TOKEN_LIMIT = 64 * 1024;
const TOKEN_RESPONSE_LIMIT = 8 * 1024;
const TOKEN_REQUEST_TIMEOUT_MS = 10_000;

function normalizeTokenServerOrigin(value: string): string {
  const candidate = value.trim();
  let url: URL;
  try {
    url = new URL(candidate);
  } catch {
    throw new Error('请输入完整的 DevTools 服务地址。');
  }
  if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password ||
      (url.pathname !== '/' && url.pathname !== '') || url.search || url.hash) {
    throw new Error('请输入 http(s) DevTools 服务地址。');
  }
  return url.origin;
}

function normalizeStoreToken(value: string): string {
  if (
    !value ||
    value.length > STORE_TOKEN_LIMIT ||
    value !== value.trim() ||
    value.includes('\n') ||
    value.includes('\r') ||
    value.includes('\0')
  ) {
    throw new Error('token handoff is invalid.');
  }
  return value;
}

function normalizeToken(value: string): string {
  const token = value.trim();
  if (!token.startsWith('v1.')) {
    throw new Error('token must start with v1.');
  }
  return token;
}
