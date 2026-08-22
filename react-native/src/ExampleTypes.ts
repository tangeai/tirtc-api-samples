export type Page = 'configure' | 'player' | 'store' | 'settings' | 'qrScanner';
export type VideoDecoderPreference = 'auto' | 'hardware' | 'software';
export type OutputBufferPolicy = 'automatic' | 'no_buffer';
export type LocalAudioCodec = 'g711a' | 'aac' | 'pcm' | 'opus' | 'amr';
export type LocalAudioSampleRateHz = '8000' | '16000';
export type LocalAudioProcessingLevel = '0' | '1' | '2' | '3';

export type ExampleConfig = {
  appId: string;
  endpoint: string;
  remoteId: string;
  token: string;
  tokenServerAddress: string;
  storeToken: string;
  audioStreamId: string;
  videoStreamId: string;
  videoDecoderPreference: VideoDecoderPreference;
  outputBufferPolicy: OutputBufferPolicy;
  consoleLogEnabled: boolean;
  localAudioCodec: LocalAudioCodec;
  localAudioSampleRateHz: LocalAudioSampleRateHz;
  localAudioStreamId: string;
  localAudioAecEnabled: boolean;
  localAudioAgcLevel: LocalAudioProcessingLevel;
  localAudioAnsLevel: LocalAudioProcessingLevel;
};

const DEFAULT_DOWNLINK_AUDIO_STREAM_ID = 10;
const DEFAULT_DOWNLINK_VIDEO_STREAM_ID = 11;
const DEFAULT_LOCAL_AUDIO_STREAM_ID = 14;

export const initialConfig: ExampleConfig = {
  appId: '',
  endpoint: '',
  remoteId: '',
  token: '',
  tokenServerAddress: '',
  storeToken: '',
  audioStreamId: String(DEFAULT_DOWNLINK_AUDIO_STREAM_ID),
  videoStreamId: String(DEFAULT_DOWNLINK_VIDEO_STREAM_ID),
  videoDecoderPreference: 'auto',
  outputBufferPolicy: 'automatic',
  consoleLogEnabled: false,
  localAudioCodec: 'g711a',
  localAudioSampleRateHz: '16000',
  localAudioStreamId: String(DEFAULT_LOCAL_AUDIO_STREAM_ID),
  localAudioAecEnabled: false,
  localAudioAgcLevel: '0',
  localAudioAnsLevel: '0',
};

export type ExampleScanPayload = Readonly<{
  token: string;
  appId?: string;
  remoteId?: string;
  endpoint?: string;
}>;

export function parseStreamIds(config: ExampleConfig): {audio: number; video: number} {
  return {
    audio: Number.parseInt(config.audioStreamId, 10) || DEFAULT_DOWNLINK_AUDIO_STREAM_ID,
    video: Number.parseInt(config.videoStreamId, 10) || DEFAULT_DOWNLINK_VIDEO_STREAM_ID,
  };
}

export function parseLocalAudioStreamId(config: ExampleConfig): number {
  return Number.parseInt(config.localAudioStreamId, 10) || DEFAULT_LOCAL_AUDIO_STREAM_ID;
}

export function parseScanPayload(rawValue: string): ExampleScanPayload | null {
  const text = rawValue.trim();
  if (text.length === 0) {
    return null;
  }
  if (!text.startsWith('{')) {
    return looksLikeToken(text) ? {token: text} : null;
  }
  const decoded = decodeScanJson(text);
  if (decoded === null) {
    return null;
  }
  const keys = Object.keys(decoded);
  if (keys.some((key) => !['app_id', 'remote_id', 'endpoint', 'token'].includes(key))) {
    return null;
  }
  const token = stringValue(decoded.token);
  const appId = stringValue(decoded.app_id);
  const remoteId = stringValue(decoded.remote_id);
  const endpoint = stringValue(decoded.endpoint);
  if (!looksLikeToken(token) || appId.length === 0 || remoteId.length === 0) {
    return null;
  }
  return {
    token,
    appId,
    remoteId,
    endpoint: endpoint.length > 0 ? endpoint : undefined,
  };
}

export function parseStoreScanPayload(rawValue: string): ExampleScanPayload | null {
  const text = rawValue.trim();
  if (text.length === 0) {
    return null;
  }
  if (!text.startsWith('{')) {
    return looksLikeStoreToken(text) ? {token: text} : null;
  }
  const decoded = decodeScanJson(text);
  if (decoded === null || Object.keys(decoded).some((key) => !['app_id', 'endpoint', 'token'].includes(key))) {
    return null;
  }
  const token = stringValue(decoded.token);
  const appId = stringValue(decoded.app_id);
  if (!looksLikeStoreToken(token) || appId.length === 0) {
    return null;
  }
  if ('endpoint' in decoded && decoded.endpoint !== null && typeof decoded.endpoint !== 'string') {
    return null;
  }
  const endpoint = stringValue(decoded.endpoint);
  if (endpoint.length > 0 && !validStoreEndpoint(endpoint)) {
    return null;
  }
  return {token, appId, endpoint: endpoint || undefined};
}

function decodeScanJson(text: string): Record<string, unknown> | null {
  try {
    const normalized = text.replace(/,\s*}/g, '}').replace(/,\s*]/g, ']');
    const decoded = JSON.parse(normalized) as unknown;
    return decoded !== null && typeof decoded === 'object' && !Array.isArray(decoded)
      ? (decoded as Record<string, unknown>)
      : null;
  } catch {
    return null;
  }
}

function looksLikeToken(value: string): boolean {
  return value.trim().startsWith('v1.');
}

function looksLikeStoreToken(value: string): boolean {
  const token = value.trim();
  return token.length > 0 && token.length <= 64 * 1024 && !/\s/.test(token);
}

function validStoreEndpoint(value: string): boolean {
  try {
    const endpoint = new URL(value);
    return endpoint.protocol === 'https:' && endpoint.hostname.length > 0 &&
      endpoint.username.length === 0 && endpoint.password.length === 0 && endpoint.hash.length === 0;
  } catch {
    return false;
  }
}

function stringValue(value: unknown): string {
  return typeof value === 'string' ? value.trim() : '';
}
