import type {
  TiRtcAudioCodec,
  TiRtcAudioOutputDebugSnapshot,
  TiRtcAudioOutputMetricsSnapshot,
  TiRtcConnMetricsSnapshot,
  TiRtcVideoCodec,
  TiRtcVideoDecoderBackend,
  TiRtcVideoOutputDebugSnapshot,
  TiRtcVideoOutputMetricsSnapshot,
} from 'tirtc-react-native';
import type {VideoDecoderPreference} from './ExampleTypes';

const MINIMUM_VIDEO_RENDER_CONTINUITY_RATIO = 0.8;

export type DownlinkMetricsOverlayModel = Readonly<{
  connectDurationMs: number | null;
  firstVideoOutputMs: number | null;
  firstAudioOutputMs: number | null;
  videoWidth: number | null;
  videoHeight: number | null;
  videoCodec: TiRtcVideoCodec | null;
  audioCodec: TiRtcAudioCodec | null;
  audioSampleRate: number | null;
  audioChannels: number | null;
  requestedDecoderPreference: VideoDecoderPreference;
  resolvedDecoderBackend: TiRtcVideoDecoderBackend | null;
  audioInputBitrateKbps: number | null;
  audioInputPacketRate: number | null;
  audioRenderCallbackRate: number | null;
  audioStatsRefreshIntervalMs: number | null;
  audioStatsUpdatedAtMs: number | null;
  audioStutterThresholdMs: number | null;
  audioOutputDurationMs: number | null;
  audioStutterTotalMs: number | null;
  audioStutterCount: number | null;
  audioStutterPeakMs: number | null;
  audioStutterAverageMs: number | null;
  audioStutterRate: number | null;
  audioEstimatedOutputLatencyMs: number | null;
  videoInputBitrateKbps: number | null;
  videoInputFps: number | null;
  videoDecodedFps: number | null;
  videoRenderFps: number | null;
  videoStatsRefreshIntervalMs: number | null;
  videoStatsUpdatedAtMs: number | null;
  videoStutterThresholdMs: number | null;
  videoOutputDurationMs: number | null;
  videoStutterTotalMs: number | null;
  videoStutterCount: number | null;
  videoStutterPeakMs: number | null;
  videoStutterAverageMs: number | null;
  videoStutterRate: number | null;
  videoEstimatedOutputLatencyMs: number | null;
}>;

export type DownlinkMetricsOverlayRow = Readonly<{
  rowKey: string;
  label: string;
  value: string;
  periodTextPresent: boolean;
  periodAvailable: boolean;
  unavailableReason: string | null;
}>;

export function createDownlinkMetricsOverlayModel({
  connSnapshot,
  videoSnapshot,
  audioSnapshot,
  videoDebugSnapshot,
  audioDebugSnapshot,
  requestedDecoderPreference,
}: {
  connSnapshot: TiRtcConnMetricsSnapshot;
  videoSnapshot: TiRtcVideoOutputMetricsSnapshot;
  audioSnapshot: TiRtcAudioOutputMetricsSnapshot;
  videoDebugSnapshot: TiRtcVideoOutputDebugSnapshot | null;
  audioDebugSnapshot: TiRtcAudioOutputDebugSnapshot | null;
  requestedDecoderPreference: VideoDecoderPreference;
}): DownlinkMetricsOverlayModel {
  const videoWidth = videoSnapshot.videoWidth;
  const videoHeight = videoSnapshot.videoHeight;
  const videoCodec = videoSnapshot.videoCodec;
  const audioCodec = audioSnapshot.audioCodec;
  const audioSampleRate = audioSnapshot.audioSampleRateHz;
  const audioChannels = audioSnapshot.audioChannels;
  const decoderBackend = videoSnapshot.decoderBackend;
  return {
    connectDurationMs: connSnapshot.connectDurationMs,
    firstVideoOutputMs: videoSnapshot.startup.timeToFirstOutputMs,
    firstAudioOutputMs: audioSnapshot.startup.timeToFirstOutputMs,
    videoWidth: videoWidth > 0 ? videoWidth : positiveOrNull(videoDebugSnapshot?.width),
    videoHeight: videoHeight > 0 ? videoHeight : positiveOrNull(videoDebugSnapshot?.height),
    videoCodec: videoCodec ?? videoDebugSnapshot?.codec ?? null,
    audioCodec: audioCodec ?? audioDebugSnapshot?.codec ?? null,
    audioSampleRate: audioSampleRate > 0 ? audioSampleRate : positiveOrNull(audioDebugSnapshot?.sampleRateHz),
    audioChannels: audioChannels > 0 ? audioChannels : positiveOrNull(audioDebugSnapshot?.channels),
    requestedDecoderPreference,
    resolvedDecoderBackend:
      decoderBackend !== 'unknown' ? decoderBackend : videoDebugSnapshot?.resolvedDecoderBackend ?? null,
    audioInputBitrateKbps: audioSnapshot.audioInputBitrateKbps,
    audioInputPacketRate: audioSnapshot.audioInputPacketRate,
    audioRenderCallbackRate: audioSnapshot.audioRenderCallbackRate,
    audioStatsRefreshIntervalMs: audioSnapshot.statsRefreshIntervalMs,
    audioStatsUpdatedAtMs: audioSnapshot.statsUpdatedAtMonotonicMs,
    audioStutterThresholdMs: audioSnapshot.stutter.stutterThresholdMs,
    audioOutputDurationMs: audioSnapshot.stutter.outputDurationMs,
    audioStutterTotalMs: audioSnapshot.stutter.stutterTotalMs,
    audioStutterCount: audioSnapshot.stutter.stutterCount,
    audioStutterPeakMs: audioSnapshot.stutter.stutterPeakMs,
    audioStutterAverageMs: audioSnapshot.stutter.stutterAverageMs,
    audioStutterRate: audioSnapshot.stutter.stutterRatePercent,
    audioEstimatedOutputLatencyMs: nonNegativeOrNull(audioSnapshot.estimatedOutputLatencyMs),
    videoInputBitrateKbps: videoSnapshot.videoInputBitrateKbps,
    videoInputFps: videoSnapshot.videoInputFps,
    videoDecodedFps: videoSnapshot.videoDecodedFps,
    videoRenderFps: videoSnapshot.videoRenderFps,
    videoStatsRefreshIntervalMs: videoSnapshot.statsRefreshIntervalMs,
    videoStatsUpdatedAtMs: videoSnapshot.statsUpdatedAtMonotonicMs,
    videoStutterThresholdMs: videoSnapshot.stutter.stutterThresholdMs,
    videoOutputDurationMs: videoSnapshot.stutter.outputDurationMs,
    videoStutterTotalMs: videoSnapshot.stutter.stutterTotalMs,
    videoStutterCount: videoSnapshot.stutter.stutterCount,
    videoStutterPeakMs: videoSnapshot.stutter.stutterPeakMs,
    videoStutterAverageMs: videoSnapshot.stutter.stutterAverageMs,
    videoStutterRate: videoSnapshot.stutter.stutterRatePercent,
    videoEstimatedOutputLatencyMs: nonNegativeOrNull(videoSnapshot.estimatedOutputLatencyMs),
  };
}

export function downlinkMetricsOverlayRows(metrics: DownlinkMetricsOverlayModel): DownlinkMetricsOverlayRow[] {
  const latencyReady = downlinkMetricsLatencyReady(metrics);
  const stutterReady = downlinkMetricsStutterReady(metrics);
  return [
    {
      rowKey: 'media_params',
      label: '媒体参数',
      value: `${displayVideoSize(metrics)} · ${displayVideoCodec(metrics.videoCodec)} · ${displayAudioCodec(
        metrics.audioCodec,
      )} · ${displayVideoDecoder(metrics.resolvedDecoderBackend)}`,
      periodTextPresent: false,
      periodAvailable: false,
      unavailableReason: null,
    },
    {
      rowKey: 'video_receive',
      label: '视频接收',
      value: `码率 ${formatKbps(metrics.videoInputBitrateKbps)} · 接收 ${formatFps(metrics.videoInputFps)}`,
      periodTextPresent: false,
      periodAvailable: false,
      unavailableReason: null,
    },
    {
      rowKey: 'audio_receive',
      label: '音频接收',
      value: `码率 ${formatKbps(metrics.audioInputBitrateKbps)} · PPS ${formatPerSecond(
        metrics.audioInputPacketRate,
      )}`,
      periodTextPresent: false,
      periodAvailable: false,
      unavailableReason: null,
    },
    {
      rowKey: 'latency_stats',
      label: '输出延迟',
      value: `视频 ${formatDuration(metrics.videoEstimatedOutputLatencyMs)} · 音频 ${formatDuration(
        metrics.audioEstimatedOutputLatencyMs,
      )}`,
      periodTextPresent: true,
      periodAvailable: latencyReady,
      unavailableReason: latencyReady ? null : 'latency_metrics_unavailable',
    },
    {
      rowKey: 'startup',
      label: '启动耗时',
      value: formatStartup(metrics.connectDurationMs, metrics.firstVideoOutputMs),
      periodTextPresent: false,
      periodAvailable: false,
      unavailableReason: null,
    },
    {
      rowKey: 'stutter',
      label: '卡顿统计',
      value: `视频 ${formatCount(metrics.videoStutterCount)} / 最长 ${formatDuration(
        metrics.videoStutterPeakMs,
      )} · 音频 ${formatCount(metrics.audioStutterCount)} / 最长 ${formatDuration(metrics.audioStutterPeakMs)}`,
      periodTextPresent: true,
      periodAvailable: stutterReady,
      unavailableReason: stutterReady ? null : 'stutter_metrics_unavailable',
    },
  ];
}

export function downlinkMetricsDebugStatsReady(metrics: DownlinkMetricsOverlayModel): boolean {
  return (
    positive(metrics.videoWidth) &&
    positive(metrics.videoHeight) &&
    isKnownVideoCodec(metrics.videoCodec) &&
    isKnownAudioCodec(metrics.audioCodec) &&
    isKnownAudioSampleRate(metrics.audioSampleRate) &&
    isKnownAudioChannels(metrics.audioChannels) &&
    isResolvedDecoderBackend(metrics.resolvedDecoderBackend)
  );
}

export function downlinkMetricsAvStatsReady(metrics: DownlinkMetricsOverlayModel): boolean {
  return audioOutputMetricsReady(metrics) && videoOutputMetricsReady(metrics);
}

export function downlinkMetricsAudioOutputContinuityRatio(metrics: DownlinkMetricsOverlayModel): number | null {
  return rateRatio(metrics.audioRenderCallbackRate, metrics.audioInputPacketRate);
}

export function downlinkMetricsAudioOutputHealthOk(metrics: DownlinkMetricsOverlayModel): boolean {
  return audioOutputMetricsReady(metrics) && (metrics.audioStutterCount ?? 0) === 0;
}

export function downlinkMetricsVideoRenderContinuityRatio(metrics: DownlinkMetricsOverlayModel): number | null {
  return rateRatio(metrics.videoRenderFps, metrics.videoInputFps);
}

export function downlinkMetricsVideoOutputHealthOk(metrics: DownlinkMetricsOverlayModel): boolean {
  const ratio = downlinkMetricsVideoRenderContinuityRatio(metrics);
  return (
    videoOutputMetricsReady(metrics) &&
    ratio !== null &&
    ratio >= MINIMUM_VIDEO_RENDER_CONTINUITY_RATIO &&
    (metrics.videoStutterCount ?? 0) === 0
  );
}

export function downlinkMetricsAvOutputHealthOk(metrics: DownlinkMetricsOverlayModel): boolean {
  return downlinkMetricsAudioOutputHealthOk(metrics) && downlinkMetricsVideoOutputHealthOk(metrics);
}

export function downlinkMetricsLatencyReady(metrics: DownlinkMetricsOverlayModel): boolean {
  return (
    nonNegative(metrics.audioEstimatedOutputLatencyMs) &&
    nonNegative(metrics.videoEstimatedOutputLatencyMs)
  );
}

export function downlinkMetricsStutterReady(metrics: DownlinkMetricsOverlayModel): boolean {
  return (
    nonNegative(metrics.audioOutputDurationMs) &&
    nonNegative(metrics.videoOutputDurationMs) &&
    nonNegative(metrics.audioStutterTotalMs) &&
    nonNegative(metrics.videoStutterTotalMs) &&
    nonNegative(metrics.audioStutterRate) &&
    nonNegative(metrics.videoStutterRate)
  );
}

function audioOutputMetricsReady(metrics: DownlinkMetricsOverlayModel): boolean {
  return (
    positive(metrics.audioInputBitrateKbps) &&
    positive(metrics.audioInputPacketRate) &&
    positive(metrics.audioRenderCallbackRate) &&
    positive(metrics.audioStatsRefreshIntervalMs) &&
    nonNegative(metrics.audioEstimatedOutputLatencyMs)
  );
}

function videoOutputMetricsReady(metrics: DownlinkMetricsOverlayModel): boolean {
  return (
    positive(metrics.videoInputBitrateKbps) &&
    positive(metrics.videoInputFps) &&
    positive(metrics.videoDecodedFps) &&
    positive(metrics.videoRenderFps) &&
    positive(metrics.videoStatsRefreshIntervalMs) &&
    nonNegative(metrics.videoEstimatedOutputLatencyMs)
  );
}

function displayVideoSize(metrics: DownlinkMetricsOverlayModel): string {
  const width = metrics.videoWidth;
  const height = metrics.videoHeight;
  if (width === null || height === null || width <= 0 || height <= 0) {
    return '--';
  }
  return `${width}x${height}`;
}

function displayVideoCodec(codec: TiRtcVideoCodec | null): string {
  switch (codec) {
    case 'h264':
      return 'H264';
    case 'h265':
      return 'H265';
    case 'mjpeg':
      return 'MJPEG';
    default:
      return '--';
  }
}

function displayAudioCodec(codec: TiRtcAudioCodec | null): string {
  switch (codec) {
    case 'g711a':
      return 'G711A';
    case 'aac':
      return 'AAC';
    case 'pcm':
      return 'PCM';
    case 'opus':
      return 'OPUS';
    case 'amr':
      return 'AMR';
    default:
      return '--';
  }
}

function displayVideoDecoder(backend: TiRtcVideoDecoderBackend | null): string {
  switch (backend) {
    case 'hardware':
      return '硬解';
    case 'software':
      return '软解';
    default:
      return '未确定';
  }
}

function formatDuration(durationMs: number | null): string {
  if (durationMs === null || durationMs < 0) {
    return '--';
  }
  return `${Math.round(durationMs)} ms`;
}

function formatKbps(value: number | null): string {
  if (value === null || !Number.isFinite(value) || value <= 0) {
    return '--';
  }
  return `${value.toFixed(value >= 100 ? 0 : 1)} kbps`;
}

function formatFps(value: number | null): string {
  if (value === null || !Number.isFinite(value) || value <= 0) {
    return '--';
  }
  return `${value.toFixed(1)} fps`;
}

function formatPerSecond(value: number | null): string {
  if (value === null || !Number.isFinite(value) || value <= 0) {
    return '--';
  }
  return `${value.toFixed(1)}/s`;
}

function formatCount(count: number | null): string {
  if (count === null || count < 0) {
    return '--';
  }
  return `${Math.round(count)} 次`;
}

function formatStartup(connectDurationMs: number | null, firstOutputMs: number | null): string {
  const connectText = `连接 ${formatDuration(connectDurationMs)}`;
  if (
    connectDurationMs !== null &&
    firstOutputMs !== null &&
    connectDurationMs >= 0 &&
    firstOutputMs >= connectDurationMs
  ) {
    return `${connectText} · 首帧等待 ${formatDuration(firstOutputMs - connectDurationMs)}`;
  }
  return `${connectText} · 首帧总耗时 ${formatDuration(firstOutputMs)}`;
}

function isKnownVideoCodec(codec: TiRtcVideoCodec | null): boolean {
  return codec === 'h264' || codec === 'h265' || codec === 'mjpeg';
}

function isKnownAudioCodec(codec: TiRtcAudioCodec | null): boolean {
  return codec === 'g711a' || codec === 'aac' || codec === 'pcm' || codec === 'opus' || codec === 'amr';
}

function isKnownAudioSampleRate(sampleRate: number | null): boolean {
  return sampleRate === 8000 || sampleRate === 16000;
}

function isKnownAudioChannels(channels: number | null): boolean {
  return channels === 1 || channels === 2;
}

function isResolvedDecoderBackend(backend: TiRtcVideoDecoderBackend | null): boolean {
  return backend === 'hardware' || backend === 'software';
}

function positive(value: number | null): boolean {
  return value !== null && Number.isFinite(value) && value > 0;
}

function nonNegative(value: number | null): boolean {
  return value !== null && Number.isFinite(value) && value >= 0;
}

function nonNegativeOrNull(value: number | null | undefined): number | null {
  return value !== null && value !== undefined && Number.isFinite(value) && value >= 0 ? value : null;
}

function rateRatio(numerator: number | null, denominator: number | null): number | null {
  if (
    numerator === null ||
    denominator === null ||
    !Number.isFinite(numerator) ||
    !Number.isFinite(denominator) ||
    numerator <= 0 ||
    denominator <= 0
  ) {
    return null;
  }
  return numerator / denominator;
}

function positiveOrNull(value: number | null | undefined): number | null {
  return value !== null && value !== undefined && value > 0 ? value : null;
}
