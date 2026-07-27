import AsyncStorage from '@react-native-async-storage/async-storage';
import type {ExampleConfig} from './ExampleTypes';
import {initialConfig} from './ExampleTypes';

const STORAGE_KEY = 'tirtc.reactNativeExample.config.v1';

type StoredConfig = Pick<
  ExampleConfig,
  | 'appId'
  | 'endpoint'
  | 'remoteId'
  | 'audioStreamId'
  | 'videoStreamId'
  | 'videoDecoderPreference'
  | 'outputBufferPolicy'
  | 'consoleLogEnabled'
  | 'localAudioCodec'
  | 'localAudioSampleRateHz'
  | 'localAudioStreamId'
  | 'localAudioAecEnabled'
  | 'localAudioAgcLevel'
  | 'localAudioAnsLevel'
>;

export async function loadStoredConfig(): Promise<Partial<ExampleConfig>> {
  const raw = await AsyncStorage.getItem(STORAGE_KEY);
  if (raw === null) {
    return {};
  }
  try {
    const decoded = JSON.parse(raw) as Partial<StoredConfig>;
    return sanitizeStoredConfig(decoded);
  } catch {
    return {};
  }
}

export async function saveStoredConfig(config: ExampleConfig): Promise<void> {
  const stored: StoredConfig = {
    appId: config.appId,
    endpoint: config.endpoint,
    remoteId: config.remoteId,
    audioStreamId: config.audioStreamId,
    videoStreamId: config.videoStreamId,
    videoDecoderPreference: config.videoDecoderPreference,
    outputBufferPolicy: config.outputBufferPolicy,
    consoleLogEnabled: config.consoleLogEnabled,
    localAudioCodec: config.localAudioCodec,
    localAudioSampleRateHz: config.localAudioSampleRateHz,
    localAudioStreamId: config.localAudioStreamId,
    localAudioAecEnabled: config.localAudioAecEnabled,
    localAudioAgcLevel: config.localAudioAgcLevel,
    localAudioAnsLevel: config.localAudioAnsLevel,
  };
  await AsyncStorage.setItem(STORAGE_KEY, JSON.stringify(stored));
}

function sanitizeStoredConfig(decoded: Partial<StoredConfig>): Partial<ExampleConfig> {
  const localAudioCodec = choiceOrDefault(
    decoded.localAudioCodec,
    ['g711a', 'aac', 'pcm', 'opus', 'amr'],
    initialConfig.localAudioCodec,
  );
  const localAudioSampleRateHz =
    localAudioCodec === 'amr'
      ? '8000'
      : choiceOrDefault(decoded.localAudioSampleRateHz, ['8000', '16000'], initialConfig.localAudioSampleRateHz);
  return {
    appId: stringOrDefault(decoded.appId),
    endpoint: stringOrDefault(decoded.endpoint),
    remoteId: stringOrDefault(decoded.remoteId),
    audioStreamId: stringOrDefault(decoded.audioStreamId, initialConfig.audioStreamId),
    videoStreamId: stringOrDefault(decoded.videoStreamId, initialConfig.videoStreamId),
    videoDecoderPreference: choiceOrDefault(
      decoded.videoDecoderPreference,
      ['auto', 'hardware', 'software'],
      initialConfig.videoDecoderPreference,
    ),
    outputBufferPolicy: choiceOrDefault(
      decoded.outputBufferPolicy,
      ['automatic', 'no_buffer'],
      initialConfig.outputBufferPolicy,
    ),
    consoleLogEnabled: booleanOrDefault(decoded.consoleLogEnabled, initialConfig.consoleLogEnabled),
    localAudioCodec,
    localAudioSampleRateHz,
    localAudioStreamId: stringOrDefault(decoded.localAudioStreamId, initialConfig.localAudioStreamId),
    localAudioAecEnabled: booleanOrDefault(decoded.localAudioAecEnabled, initialConfig.localAudioAecEnabled),
    localAudioAgcLevel: choiceOrDefault(decoded.localAudioAgcLevel, ['0', '1', '2', '3'], '0'),
    localAudioAnsLevel: choiceOrDefault(decoded.localAudioAnsLevel, ['0', '1', '2', '3'], '0'),
  };
}

function stringOrDefault(value: unknown, fallback = ''): string {
  return typeof value === 'string' ? value : fallback;
}

function booleanOrDefault(value: unknown, fallback: boolean): boolean {
  return typeof value === 'boolean' ? value : fallback;
}

function choiceOrDefault<const T extends string>(
  value: unknown,
  choices: readonly T[],
  fallback: T,
): T {
  return typeof value === 'string' && choices.includes(value as T) ? (value as T) : fallback;
}
