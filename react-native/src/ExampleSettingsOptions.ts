import type {ExampleConfig} from './ExampleTypes';

export type PreferenceOption = Readonly<{
  value: string;
  label: string;
}>;

export const VIDEO_DECODER_OPTIONS = [
  {value: 'auto', label: '自动'},
  {value: 'hardware', label: '硬解'},
  {value: 'software', label: '软解'},
] as const;

export const OUTPUT_BUFFER_OPTIONS = [
  {value: 'automatic', label: '自动'},
  {value: 'no_buffer', label: '不缓冲'},
] as const;

export const LOCAL_AUDIO_CODEC_OPTIONS = [
  {value: 'g711a', label: 'G711A'},
  {value: 'aac', label: 'AAC'},
  {value: 'pcm', label: 'PCM'},
  {value: 'opus', label: 'OPUS'},
  {value: 'amr', label: 'AMR'},
] as const;

export const LOCAL_AUDIO_SAMPLE_RATE_OPTIONS = [
  {value: '8000', label: '8 kHz'},
  {value: '16000', label: '16 kHz'},
] as const;

export const AUDIO_PROCESSING_LEVEL_OPTIONS = [
  {value: '0', label: '关闭'},
  {value: '1', label: '低'},
  {value: '2', label: '中'},
  {value: '3', label: '高'},
] as const;

export const MIN_LOCAL_AUDIO_STREAM_ID = 0;
export const MAX_LOCAL_AUDIO_STREAM_ID = 15;

export function videoDecoderPreferenceLabel(value: string): string {
  switch (value) {
    case 'hardware':
      return '硬解';
    case 'software':
      return '软解';
    default:
      return '自动';
  }
}

export function outputBufferPolicyLabel(value: string): string {
  return value === 'no_buffer' ? '不缓冲' : '自动';
}

export function localAudioCodecLabel(value: string): string {
  switch (value) {
    case 'aac':
      return 'AAC';
    case 'pcm':
      return 'PCM';
    case 'opus':
      return 'OPUS';
    case 'amr':
      return 'AMR';
    default:
      return 'G711A';
  }
}

export function localAudioSampleRateLabel(value: string): string {
  return value === '8000' ? '8 kHz' : '16 kHz';
}

export function localAudioProcessingLevelLabel(value: string): string {
  switch (value) {
    case '1':
      return '低';
    case '2':
      return '中';
    case '3':
      return '高';
    default:
      return '关闭';
  }
}

export function isVideoDecoderPreference(value: string): value is ExampleConfig['videoDecoderPreference'] {
  return value === 'auto' || value === 'hardware' || value === 'software';
}

export function isOutputBufferPolicy(value: string): value is ExampleConfig['outputBufferPolicy'] {
  return value === 'automatic' || value === 'no_buffer';
}

export function isLocalAudioCodec(value: string): value is ExampleConfig['localAudioCodec'] {
  return value === 'g711a' || value === 'aac' || value === 'pcm' || value === 'opus' || value === 'amr';
}

export function isLocalAudioSampleRate(value: string): value is ExampleConfig['localAudioSampleRateHz'] {
  return value === '8000' || value === '16000';
}

export function isLocalAudioProcessingLevel(value: string): value is ExampleConfig['localAudioAgcLevel'] {
  return value === '0' || value === '1' || value === '2' || value === '3';
}
