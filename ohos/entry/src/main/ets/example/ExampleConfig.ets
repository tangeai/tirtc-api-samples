import {
  TiRtcAudioAecMode,
  TiRtcAudioAgcLevel,
  TiRtcAudioAnsLevel,
  TiRtcAudioChannelCount,
  TiRtcAudioCodec,
  TiRtcAudioSampleRate,
  TiRtcOutputBufferStrategy,
  TiRtcVideoDecoderPreference,
} from 'tirtc/Index';

export const LOG_DOMAIN: number = 0x5452;
export const LOG_TAG: string = 'TIRTC_OHOS_EXAMPLE';
export const DEFAULT_AUDIO_STREAM_ID: number = 10;
export const DEFAULT_VIDEO_STREAM_ID: number = 11;
export const DEFAULT_DOWNLINK_VIDEO_WIDTH: number = 16;
export const DEFAULT_DOWNLINK_VIDEO_HEIGHT: number = 9;
export const SAMPLE_COMMAND_ID: number = 0xffffffff;
export const SAMPLE_COMMAND_PAYLOAD: string = 'echo';
export const SURFACE_WAIT_INTERVAL_MS: number = 100;
export const VIDEO_SIZE_WAIT_TIMEOUT_MS: number = 5000;
export const CONNECT_WAIT_TIMEOUT_MS: number = 5000;
export const CONNECT_WAIT_INTERVAL_MS: number = 50;
export const LOCAL_AUDIO_CONNECT_WAIT_TIMEOUT_MS: number = 8000;
export const CONFIGURE_TOP_PADDING: number = 12;
export const CONFIGURE_BOTTOM_PADDING: number = 44;
export const SETTINGS_TOP_PADDING: number = 12;
export const PLAYER_TOP_PADDING: number = 42;
export const PLAYER_BOTTOM_PADDING: number = 42;
export const STREAM_MESSAGE_TIMEOUT_MS: number = 12000;

export interface VideoFitSize {
  width: number;
  height: number;
}

export enum ExampleView {
  configure,
  settings,
  qrScanner,
  cloudStorage,
  player,
}

export function appStorageString(key: string): string {
  return AppStorage.get<string>(key) ?? '';
}

export function parseStreamId(value: string, fallback: number): number {
  const normalized = value.trim();
  if (normalized.length === 0) {
    return fallback;
  }
  const parsed = Number(normalized);
  return Number.isInteger(parsed) ? parsed : fallback;
}

export function parseVideoDecoderPreference(value: string): TiRtcVideoDecoderPreference {
  const parsed = Number(value.trim());
  if (parsed === TiRtcVideoDecoderPreference.software || parsed === TiRtcVideoDecoderPreference.hardware) {
    return parsed;
  }
  return TiRtcVideoDecoderPreference.auto;
}

export function parseOutputBufferStrategy(value: string): TiRtcOutputBufferStrategy {
  const parsed = Number(value.trim());
  return parsed === TiRtcOutputBufferStrategy.noBuffer ?
    TiRtcOutputBufferStrategy.noBuffer :
    TiRtcOutputBufferStrategy.automatic;
}

export function parseAudioInputCodec(value: string): TiRtcAudioCodec {
  const parsed = Number(value.trim());
  if (parsed === TiRtcAudioCodec.aac) {
    return TiRtcAudioCodec.aac;
  }
  if (parsed === TiRtcAudioCodec.pcm) {
    return TiRtcAudioCodec.pcm;
  }
  if (parsed === TiRtcAudioCodec.opus) {
    return TiRtcAudioCodec.opus;
  }
  if (parsed === TiRtcAudioCodec.amr) {
    return TiRtcAudioCodec.amr;
  }
  return TiRtcAudioCodec.g711a;
}

export function parseAudioInputSampleRate(value: string): TiRtcAudioSampleRate {
  const parsed = Number(value.trim());
  return parsed === TiRtcAudioSampleRate.rate8k ? TiRtcAudioSampleRate.rate8k : TiRtcAudioSampleRate.rate16k;
}

export function parseAudioInputChannels(value: string): TiRtcAudioChannelCount {
  return TiRtcAudioChannelCount.mono;
}

export function parseAudioAecMode(value: string): TiRtcAudioAecMode {
  const parsed = Number(value.trim());
  return parsed === TiRtcAudioAecMode.enabled ? TiRtcAudioAecMode.enabled : TiRtcAudioAecMode.disabled;
}

export function parseAudioAgcLevel(value: string): TiRtcAudioAgcLevel {
  const parsed = Number(value.trim());
  if (parsed === TiRtcAudioAgcLevel.low || parsed === TiRtcAudioAgcLevel.medium ||
    parsed === TiRtcAudioAgcLevel.high) {
    return parsed;
  }
  return TiRtcAudioAgcLevel.disabled;
}

export function parseAudioAnsLevel(value: string): TiRtcAudioAnsLevel {
  const parsed = Number(value.trim());
  if (parsed === TiRtcAudioAnsLevel.low || parsed === TiRtcAudioAnsLevel.medium ||
    parsed === TiRtcAudioAnsLevel.high) {
    return parsed;
  }
  return TiRtcAudioAnsLevel.disabled;
}

export function parseConsoleLogEnabled(value: string): boolean {
  return value === 'true';
}

export function videoDecoderPreferenceLabel(value: TiRtcVideoDecoderPreference): string {
  if (value === TiRtcVideoDecoderPreference.software) {
    return '软解';
  }
  if (value === TiRtcVideoDecoderPreference.hardware) {
    return '硬解';
  }
  return '自动';
}

export function outputBufferStrategyLabel(value: TiRtcOutputBufferStrategy): string {
  return value === TiRtcOutputBufferStrategy.noBuffer ? '不缓冲' : '自动';
}

export function audioCodecLabel(value: TiRtcAudioCodec): string {
  if (value === TiRtcAudioCodec.aac) {
    return 'AAC';
  }
  if (value === TiRtcAudioCodec.pcm) {
    return 'PCM';
  }
  if (value === TiRtcAudioCodec.opus) {
    return 'OPUS';
  }
  if (value === TiRtcAudioCodec.amr) {
    return 'AMR';
  }
  return 'G711A';
}

export function audioSampleRateLabel(value: TiRtcAudioSampleRate): string {
  return value === TiRtcAudioSampleRate.rate8k ? '8 kHz' : '16 kHz';
}

export function audioAecModeLabel(value: TiRtcAudioAecMode): string {
  return value === TiRtcAudioAecMode.enabled ? '已开启' : '已关闭';
}

export function audioLevelLabel(value: TiRtcAudioAgcLevel | TiRtcAudioAnsLevel): string {
  if (value === TiRtcAudioAgcLevel.low) {
    return '低';
  }
  if (value === TiRtcAudioAgcLevel.medium) {
    return '中';
  }
  if (value === TiRtcAudioAgcLevel.high) {
    return '高';
  }
  return '关闭';
}

export function writeAppStorageString(key: string, value: string): void {
  if (AppStorage.has(key)) {
    AppStorage.set<string>(key, value);
  } else {
    AppStorage.setOrCreate<string>(key, value);
  }
}

export function asciiPayload(bytes: Uint8Array): string {
  let result = '';
  for (let index = 0; index < bytes.byteLength; index += 1) {
    const value = bytes[index];
    result += value >= 32 && value <= 126 ? String.fromCharCode(value) : '.';
  }
  return result;
}

export function asciiBytes(value: string): Uint8Array {
  const bytes = new Uint8Array(value.length);
  for (let index = 0; index < value.length; index += 1) {
    bytes[index] = value.charCodeAt(index) & 0x7F;
  }
  return bytes;
}

export function bytesEqual(left: Uint8Array, right: Uint8Array): boolean {
  if (left.byteLength !== right.byteLength) {
    return false;
  }
  for (let index = 0; index < left.byteLength; index += 1) {
    if (left[index] !== right[index]) {
      return false;
    }
  }
  return true;
}
