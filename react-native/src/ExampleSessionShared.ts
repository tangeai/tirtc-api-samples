import {
  TiRtcAudioAecMode,
  TiRtcAudioAgcLevel,
  TiRtcAudioAnsLevel,
  TiRtcAudioChannelCount,
  TiRtcAudioCodec,
  TiRtcAudioSampleRate,
  TiRtcOutputBufferStrategy,
  type TiRtcAudioInputOptions,
  type TiRtcSize,
  TiRtcVideoDecoderPreference,
} from 'tirtc-react-native';
import type {ExampleConfig} from './ExampleTypes';

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
    codec: audioCodecFromConfig(config.localAudioCodec),
    sampleRate:
      config.localAudioSampleRateHz === '8000' ? TiRtcAudioSampleRate.rate8k : TiRtcAudioSampleRate.rate16k,
    channels: TiRtcAudioChannelCount.mono,
    aecMode: config.localAudioAecEnabled ? TiRtcAudioAecMode.enabled : TiRtcAudioAecMode.disabled,
    agcLevel: audioAgcLevelFromConfig(config.localAudioAgcLevel),
    ansLevel: audioAnsLevelFromConfig(config.localAudioAnsLevel),
  };
}

function audioCodecFromConfig(value: string): TiRtcAudioCodec {
  switch (value) {
    case 'aac':
      return TiRtcAudioCodec.aac;
    case 'pcm':
      return TiRtcAudioCodec.pcm;
    case 'opus':
      return TiRtcAudioCodec.opus;
    case 'amr':
      return TiRtcAudioCodec.amr;
    default:
      return TiRtcAudioCodec.g711a;
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
