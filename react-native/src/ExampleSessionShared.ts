import {
  TiRtcAudioAecMode,
  TiRtcAudioAgcLevel,
  TiRtcAudioAnsLevel,
  TiRtcAudioChannelCount,
  TiRtcAudioSampleRate,
  TiRtcOutputBufferStrategy,
  type TiRtcAudioInputOptions,
  type TiRtcSize,
  TiRtcVideoDecoderPreference,
} from 'tirtc-react-native';
import {NativeModules, PermissionsAndroid, Platform} from 'react-native';
import type {ExampleConfig} from './ExampleTypes';

type ExampleMediaModule = Readonly<{
  requestGalleryWritePermission(): Promise<boolean>;
}>;

export function galleryFileName(extension: 'mp4' | 'jpg', targetId?: number, now: Date = new Date()): string {
  const part = (value: number, width: number) => value.toString().padStart(width, '0');
  return `客厅角落摄像头${targetId === undefined ? '' : `-${targetId}`}-${part(now.getFullYear(), 4)}-${part(now.getMonth() + 1, 2)}-${part(now.getDate(), 2)}-`
    + `${part(now.getHours(), 2)}-${part(now.getMinutes(), 2)}-${part(now.getSeconds(), 2)}-`
    + `${part(now.getMilliseconds(), 3)}.${extension}`;
}

export async function prepareGalleryWritePermission(): Promise<boolean> {
  if (Platform.OS === 'android') {
    const version = typeof Platform.Version === 'number' ? Platform.Version : Number(Platform.Version);
    if (version > 28) return true;
    const permission = PermissionsAndroid.PERMISSIONS.WRITE_EXTERNAL_STORAGE;
    if (await PermissionsAndroid.check(permission)) return true;
    return (await PermissionsAndroid.request(permission)) === PermissionsAndroid.RESULTS.GRANTED;
  }
  if (Platform.OS === 'ios') {
    const module = NativeModules.TiRtcExampleMedia as ExampleMediaModule | undefined;
    return module !== undefined && await module.requestGalleryWritePermission();
  }
  return true;
}

export function validSize(size: TiRtcSize | null): TiRtcSize | null {
  if (size === null || size.width <= 0 || size.height <= 0) {
    return null;
  }
  return size;
}

export function videoDecoderPreferenceFromConfig(value: string): TiRtcVideoDecoderPreference {
  switch (value) {
    case 'hardware':
      return TiRtcVideoDecoderPreference.hardware;
    case 'software':
      return TiRtcVideoDecoderPreference.software;
    default:
      return TiRtcVideoDecoderPreference.auto;
  }
}

export function outputBufferStrategyFromConfig(value: string): TiRtcOutputBufferStrategy {
  return value === 'no_buffer' ? TiRtcOutputBufferStrategy.noBuffer : TiRtcOutputBufferStrategy.automatic;
}

export function localAudioInputOptionsFromConfig(config: ExampleConfig): TiRtcAudioInputOptions {
  return {
    media: audioMediaFromConfig(config.localAudioCodec),
    sampleRate:
      config.localAudioSampleRateHz === '8000' ? TiRtcAudioSampleRate.rate8k : TiRtcAudioSampleRate.rate16k,
    channels: TiRtcAudioChannelCount.mono,
    aecMode: config.localAudioAecEnabled ? TiRtcAudioAecMode.enabled : TiRtcAudioAecMode.disabled,
    agcLevel: audioAgcLevelFromConfig(config.localAudioAgcLevel),
    ansLevel: audioAnsLevelFromConfig(config.localAudioAnsLevel),
  };
}

function audioMediaFromConfig(value: string): number {
  switch (value) {
    case 'aac':
      return 3;
    case 'pcm':
      return 1;
    case 'opus':
      return 4;
    case 'amr':
      return 5;
    default:
      return 2;
  }
}

function audioAgcLevelFromConfig(value: string): TiRtcAudioAgcLevel {
  switch (value) {
    case '1':
      return TiRtcAudioAgcLevel.low;
    case '2':
      return TiRtcAudioAgcLevel.medium;
    case '3':
      return TiRtcAudioAgcLevel.high;
    default:
      return TiRtcAudioAgcLevel.disabled;
  }
}

function audioAnsLevelFromConfig(value: string): TiRtcAudioAnsLevel {
  switch (value) {
    case '1':
      return TiRtcAudioAnsLevel.low;
    case '2':
      return TiRtcAudioAnsLevel.medium;
    case '3':
      return TiRtcAudioAnsLevel.high;
    default:
      return TiRtcAudioAnsLevel.disabled;
  }
}
