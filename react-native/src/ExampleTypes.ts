export type Page = 'configure' | 'player' | 'tiCloudStorage' | 'settings' | 'qrScanner';
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
  tiCloudStorageToken: string;
  audioStreamId: string;
  videoStreamIds: string[];
  tiCloudStorageAudioChannelId: string;
  tiCloudStorageVideoChannelIds: string[];
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
  tiCloudStorageToken: '',
  audioStreamId: String(DEFAULT_DOWNLINK_AUDIO_STREAM_ID),
  videoStreamIds: [String(DEFAULT_DOWNLINK_VIDEO_STREAM_ID)],
  tiCloudStorageAudioChannelId: String(DEFAULT_DOWNLINK_AUDIO_STREAM_ID),
  tiCloudStorageVideoChannelIds: [String(DEFAULT_DOWNLINK_VIDEO_STREAM_ID)],
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

export type MediaSelection = Readonly<{audio: number | null; videos: readonly number[]}>;

export function parseStreamIds(config: ExampleConfig): MediaSelection {
  return parseMediaSelection(config.audioStreamId, config.videoStreamIds, 15, 'Stream');
}

export function parseCloudStorageChannelIds(config: ExampleConfig): MediaSelection {
  return parseMediaSelection(
    config.tiCloudStorageAudioChannelId,
    config.tiCloudStorageVideoChannelIds,
    255,
    'Channel',
    true,
  );
}

function parseMediaSelection(
  audioText: string,
  videoTexts: readonly string[],
  maximum: number,
  label: string,
  allowAudioVideoMatch = false,
): MediaSelection {
  const audio = parseOptionalId(audioText, maximum, `Audio ${label} ID`);
  if (videoTexts.length > 3) throw new Error('最多选择三路视频');
  const videos = videoTexts
    .filter((value) => value.trim().length > 0)
    .map((value, index) => parseRequiredId(value, maximum, `Video ${label} ${index + 1} ID`));
  if (new Set(videos).size !== videos.length) throw new Error(`Video ${label} IDs 不能重复`);
  if (!allowAudioVideoMatch && audio !== null && videos.includes(audio)) {
    throw new Error(`Audio 与 Video ${label} IDs 不能相同`);
  }
  return {audio, videos};
}

function parseOptionalId(value: string, maximum: number, label: string): number | null {
  return value.trim().length === 0 ? null : parseRequiredId(value, maximum, label);
}

function parseRequiredId(value: string, maximum: number, label: string): number {
  const normalized = value.trim();
  const parsed = Number(normalized);
  if (normalized.length === 0 || !Number.isInteger(parsed) || parsed < 0 || parsed > maximum) {
    throw new Error(`${label} 必须是 0..${maximum} 的整数`);
  }
  return parsed;
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

export function tiCloudStorageParseScanPayload(rawValue: string): ExampleScanPayload | null {
  const text = rawValue.trim();
  if (text.length === 0) {
    return null;
  }
  if (!text.startsWith('{')) {
    return tiCloudStorageLooksLikeToken(text) ? {token: text} : null;
  }
  const decoded = decodeScanJson(text);
  if (decoded === null || Object.keys(decoded).some((key) => !['app_id', 'endpoint', 'token'].includes(key))) {
    return null;
  }
  const token = stringValue(decoded.token);
  const appId = stringValue(decoded.app_id);
  if (!tiCloudStorageLooksLikeToken(token) || appId.length === 0) {
    return null;
  }
  if ('endpoint' in decoded && decoded.endpoint !== null && typeof decoded.endpoint !== 'string') {
    return null;
  }
  const endpoint = stringValue(decoded.endpoint);
  if (endpoint.length > 0 && !tiCloudStorageEndpointIsValid(endpoint)) {
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

function tiCloudStorageLooksLikeToken(value: string): boolean {
  const token = value.trim();
  return token.length > 0 && token.length <= 64 * 1024 && !/\s/.test(token);
}

function tiCloudStorageEndpointIsValid(value: string): boolean {
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
