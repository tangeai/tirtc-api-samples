import {validSize} from './ExampleSessionShared';
import type {TiRtcSize} from 'tirtc-react-native';

export function formatDuration(value: number | null | undefined): string {
  return value === null || value === undefined ? '-' : `${Math.round(value)}ms`;
}

export function formatFps(value: number | null | undefined): string {
  return value === null || value === undefined ? '-' : `${value.toFixed(1)}fps`;
}

export function formatRate(value: number | null | undefined): string {
  return value === null || value === undefined ? '-' : `${value.toFixed(1)}kbps`;
}

export function formatSize(size: TiRtcSize | null): string {
  return size ? `${size.width}x${size.height}` : '-';
}

export function videoDebugSize(snapshot: {width: number; height: number} | null | undefined): TiRtcSize | null {
  return snapshot ? validSize({width: snapshot.width, height: snapshot.height}) : null;
}
