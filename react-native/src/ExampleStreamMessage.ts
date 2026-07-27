export const demoStreamMessagePeriodMs = 10_000;
export const demoStreamMessageBubbleDurationMs = 4_000;
export const streamMessageInvalidStateCode = 6000;

export type StreamMessageConnection = Readonly<{
  sendStreamMessage(streamId: number, timestampMs: number, data: Uint8Array): number;
}>;

export type StreamMessageReceiveEvent = Readonly<{
  streamId: number;
  timestampMs: number;
  epochSeconds: number;
  payloadBytes: number;
  count: number;
}>;

export type StreamMessageSendEvent = Readonly<{
  streamId: number;
  epochSeconds: number;
  payloadBytes: number;
  resultCode: number;
  sentCount: number;
}>;

export function encodeDemoStreamMessagePayload(nowMs: number = Date.now()): Uint8Array {
  const epochSeconds = Math.floor(nowMs / 1000).toString();
  const bytes = new Uint8Array(epochSeconds.length);
  for (let index = 0; index < epochSeconds.length; index += 1) {
    bytes[index] = epochSeconds.charCodeAt(index);
  }
  return bytes;
}

export function decodeDemoStreamMessageEpochSeconds(payload: Uint8Array): number | null {
  if (payload.length === 0) {
    return null;
  }
  let text = '';
  for (const byte of payload) {
    if (byte < 0x30 || byte > 0x39) {
      return null;
    }
    text += String.fromCharCode(byte);
  }
  const epochSeconds = Number.parseInt(text, 10);
  return Number.isFinite(epochSeconds) && epochSeconds > 0 ? epochSeconds : null;
}

export class DemoStreamMessageOverlayController {
  private hideTimer: ReturnType<typeof setTimeout> | null = null;
  private receivedCount = 0;
  text: string | null = null;

  handleIncoming({
    expectedStreamId,
    streamId,
    timestampMs,
    payload,
    onHidden,
  }: {
    expectedStreamId: number;
    streamId: number;
    timestampMs: number;
    payload: Uint8Array;
    onHidden: () => void;
  }): StreamMessageReceiveEvent | null {
    if (streamId !== expectedStreamId) {
      return null;
    }
    const epochSeconds = decodeDemoStreamMessageEpochSeconds(payload);
    if (epochSeconds === null) {
      return null;
    }

    this.receivedCount += 1;
    this.text = epochSeconds.toString();
    if (this.hideTimer !== null) {
      clearTimeout(this.hideTimer);
    }
    this.hideTimer = setTimeout(() => {
      this.hideTimer = null;
      this.text = null;
      onHidden();
    }, demoStreamMessageBubbleDurationMs);

    return {
      streamId,
      timestampMs,
      epochSeconds,
      payloadBytes: payload.length,
      count: this.receivedCount,
    };
  }

  clear() {
    if (this.hideTimer !== null) {
      clearTimeout(this.hideTimer);
      this.hideTimer = null;
    }
    this.text = null;
  }
}

export class DemoStreamMessageSender {
  private timer: ReturnType<typeof setInterval> | null = null;
  private sentCount = 0;

  constructor(private readonly onSent?: (event: StreamMessageSendEvent) => void) {}

  start(connection: StreamMessageConnection, streamId: number) {
    this.stop();
    this.sentCount = 0;
    this.send(connection, streamId);
    this.timer = setInterval(() => {
      this.send(connection, streamId);
    }, demoStreamMessagePeriodMs);
  }

  stop() {
    if (this.timer !== null) {
      clearInterval(this.timer);
      this.timer = null;
    }
    this.sentCount = 0;
  }

  send(connection: StreamMessageConnection | null, streamId: number): number {
    if (connection === null) {
      return streamMessageInvalidStateCode;
    }
    const payload = encodeDemoStreamMessagePayload();
    const epochSeconds = decodeDemoStreamMessageEpochSeconds(payload) ?? 0;
    const resultCode = connection.sendStreamMessage(streamId, 0, payload);
    if (resultCode === 0) {
      this.sentCount += 1;
    }
    this.onSent?.({
      streamId,
      epochSeconds,
      payloadBytes: payload.length,
      resultCode,
      sentCount: this.sentCount,
    });
    return resultCode;
  }
}
