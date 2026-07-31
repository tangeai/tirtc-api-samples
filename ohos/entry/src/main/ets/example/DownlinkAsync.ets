import { hilog } from '@kit.PerformanceAnalysisKit';
import { TiRtcConn, TiRtcConnState, TiRtcVideoOutput } from 'tirtc/Index';
import {
  asciiBytes,
  CONNECT_WAIT_INTERVAL_MS,
  LOG_DOMAIN,
  LOG_TAG,
  SAMPLE_COMMAND_ID,
  SAMPLE_COMMAND_PAYLOAD,
  SURFACE_WAIT_INTERVAL_MS,
  STREAM_MESSAGE_TIMEOUT_MS,
} from './ExampleConfig';

export async function waitConnected(conn: TiRtcConn, timeoutMs: number): Promise<boolean> {
  const startedAt = Date.now();
  return new Promise<boolean>((resolve) => {
    const poll = (): void => {
      const metrics = conn.getMetricsSnapshot();
      if (metrics.code === 0
        && metrics.snapshot?.hasConnected === true
        && conn.state === TiRtcConnState.connected) {
        hilog.info(LOG_DOMAIN, LOG_TAG, 'TIRTC_downlink_connected wait_ms=%{public}d',
          Date.now() - startedAt);
        resolve(true);
        return;
      }
      if (Date.now() - startedAt >= timeoutMs) {
        hilog.error(LOG_DOMAIN, LOG_TAG, 'TIRTC_downlink_connect_wait_timeout timeout_ms=%{public}d', timeoutMs);
        resolve(false);
        return;
      }
      setTimeout(poll, CONNECT_WAIT_INTERVAL_MS);
    };
    poll();
  });
}

export async function waitVideoRenderSize(
  videoOutput: TiRtcVideoOutput,
  timeoutMs: number,
  applySize: (width: number, height: number) => void,
  hasSize: () => boolean,
): Promise<boolean> {
  return new Promise<boolean>((resolve) => {
    const startedAt = Date.now();
    const poll = (): void => {
      const size = videoOutput.renderSize;
      if (size !== undefined) {
        applySize(size.width, size.height);
      }
      if (hasSize()) {
        resolve(true);
        return;
      }
      if (Date.now() - startedAt >= timeoutMs) {
        hilog.error(LOG_DOMAIN, LOG_TAG, 'TIRTC_video_size_wait_timeout timeout_ms=%{public}d',
          timeoutMs);
        resolve(false);
        return;
      }
      setTimeout(poll, SURFACE_WAIT_INTERVAL_MS);
    };
    poll();
  });
}

export async function sendDownlinkSampleMessages(
  conn: TiRtcConn,
  videoStream: number,
): Promise<void> {
  const commandPayload = asciiBytes(SAMPLE_COMMAND_PAYLOAD);
  const commandCode = conn.sendCommand({ commandId: SAMPLE_COMMAND_ID, data: commandPayload });
  hilog.info(LOG_DOMAIN, LOG_TAG, 'TIRTC_sample_command_sent code=%{public}d command_id=%{public}d',
    commandCode, SAMPLE_COMMAND_ID);

  const epochSeconds = Math.floor(Date.now() / 1000);
  const streamCode = conn.sendStreamMessage({ streamId: videoStream, timestampMs: 0, data: asciiBytes(`${epochSeconds}`) });
  hilog.info(LOG_DOMAIN, LOG_TAG, 'TIRTC_sample_stream_message_sent code=%{public}d stream_id=%{public}d timeout_ms=%{public}d',
    streamCode, videoStream, STREAM_MESSAGE_TIMEOUT_MS);
}
