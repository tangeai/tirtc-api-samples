export type CommandPayloadMode = 'hex' | 'text';
export type CommandEventDirection = 'sent' | 'received';

export type CommandPanelEvent = Readonly<{
  direction: CommandEventDirection;
  commandId: number;
  payload: Uint8Array;
  resultCode?: number;
  createdAt: number;
}>;

export type CommandPreset = Readonly<{
  label: string;
  commandId: number;
  payloadMode: CommandPayloadMode;
  payloadText: string;
}>;

export type CommandParseResult<T> = Readonly<
  | {valid: true; value: T; error: null}
  | {valid: false; value: null; error: string}
>;

export const commandInvalidStateCode = 6000;
export const commandPanelEventLimit = 20;
export const demoEchoCommandId = 0xffffffff;
export const demoEchoCommandPayloadText = 'echo';

export const demoCommonCommandPresets: readonly CommandPreset[] = [
  {
    label: 'Echo',
    commandId: demoEchoCommandId,
    payloadMode: 'text',
    payloadText: demoEchoCommandPayloadText,
  },
];

export function parseCommandId(input: string): CommandParseResult<number> {
  const value = input.trim();
  if (value.length === 0) {
    return {valid: false, value: null, error: '请输入命令 ID'};
  }
  const hex = value.startsWith('0x') || value.startsWith('0X');
  const digits = hex ? value.slice(2) : value;
  if (digits.length === 0) {
    return {valid: false, value: null, error: '请输入命令 ID'};
  }
  if (!(hex ? /^[0-9a-fA-F]+$/.test(digits) : /^\d+$/.test(digits))) {
    return {valid: false, value: null, error: '命令 ID 必须是 32 位无符号整数'};
  }
  const commandId = Number.parseInt(digits, hex ? 16 : 10);
  if (!Number.isFinite(commandId) || commandId < 0 || commandId > demoEchoCommandId) {
    return {valid: false, value: null, error: '命令 ID 必须是 32 位无符号整数'};
  }
  return {valid: true, value: commandId, error: null};
}

export function parseCommandPayload(input: string, mode: CommandPayloadMode): CommandParseResult<Uint8Array> {
  if (mode === 'text') {
    return {valid: true, value: encodeUtf8(input), error: null};
  }
  const normalized = input.replace(/[\s,]+/g, '');
  if (normalized.length === 0) {
    return {valid: true, value: new Uint8Array(0), error: null};
  }
  if (!/^[0-9a-fA-F]+$/.test(normalized)) {
    return {valid: false, value: null, error: 'HEX 内容包含无效字符'};
  }
  if (normalized.length % 2 !== 0) {
    return {valid: false, value: null, error: 'HEX 内容必须是偶数位'};
  }
  const bytes = new Uint8Array(normalized.length / 2);
  for (let offset = 0; offset < normalized.length; offset += 2) {
    bytes[offset / 2] = Number.parseInt(normalized.slice(offset, offset + 2), 16);
  }
  return {valid: true, value: bytes, error: null};
}

export function formatCommandId(commandId: number): string {
  const normalized = commandId >>> 0;
  return `0x${normalized.toString(16).toUpperCase().padStart(8, '0')}`;
}

export function formatCommandPayloadHex(payload: Uint8Array): string {
  return Array.from(payload, (byte) => byte.toString(16).toUpperCase().padStart(2, '0')).join(' ');
}

export function trimCommandEvents(events: readonly CommandPanelEvent[]): CommandPanelEvent[] {
  if (events.length <= commandPanelEventLimit) {
    return [...events];
  }
  return events.slice(events.length - commandPanelEventLimit);
}

export function clonePayload(payload: Uint8Array): Uint8Array {
  return Uint8Array.from(payload);
}

export function demoEchoPayload(): Uint8Array {
  return encodeUtf8(demoEchoCommandPayloadText);
}

export function isDemoEchoCommand(commandId: number, payload: Uint8Array): boolean {
  return commandId === demoEchoCommandId && sameBytes(payload, demoEchoPayload());
}

function encodeUtf8(input: string): Uint8Array {
  const bytes: number[] = [];
  for (let index = 0; index < input.length; index += 1) {
    let codePoint = input.charCodeAt(index);
    if (codePoint >= 0xd800 && codePoint <= 0xdbff && index + 1 < input.length) {
      const next = input.charCodeAt(index + 1);
      if (next >= 0xdc00 && next <= 0xdfff) {
        codePoint = 0x10000 + ((codePoint - 0xd800) << 10) + (next - 0xdc00);
        index += 1;
      }
    }
    if (codePoint <= 0x7f) {
      bytes.push(codePoint);
    } else if (codePoint <= 0x7ff) {
      bytes.push(0xc0 | (codePoint >> 6), 0x80 | (codePoint & 0x3f));
    } else if (codePoint <= 0xffff) {
      bytes.push(0xe0 | (codePoint >> 12), 0x80 | ((codePoint >> 6) & 0x3f), 0x80 | (codePoint & 0x3f));
    } else {
      bytes.push(
        0xf0 | (codePoint >> 18),
        0x80 | ((codePoint >> 12) & 0x3f),
        0x80 | ((codePoint >> 6) & 0x3f),
        0x80 | (codePoint & 0x3f),
      );
    }
  }
  return Uint8Array.from(bytes);
}

function sameBytes(left: Uint8Array, right: Uint8Array): boolean {
  if (left.length !== right.length) {
    return false;
  }
  for (let index = 0; index < left.length; index += 1) {
    if (left[index] !== right[index]) {
      return false;
    }
  }
  return true;
}
