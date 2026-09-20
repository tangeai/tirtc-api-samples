type ExampleApi = import('../shared/types').ExampleApi;
type ExampleConfig = import('../shared/types').ExampleConfig;
type ExampleSettings = import('../shared/types').ExampleSettings;
type ExampleState = import('../shared/types').ExampleState;
type TiCloudStorageExampleConfig = import('../shared/types').TiCloudStorageExampleConfig;
type TiCloudStorageExampleState = import('../shared/types').TiCloudStorageExampleState;
type TiCloudStorageReplaySpeed = import('tirtc-electron').TiCloudStorageReplaySpeed;

const example = (window as typeof window & {readonly tirtcExample: ExampleApi}).tirtcExample;

const form = document.querySelector<HTMLFormElement>('#config')!;
const settingsPage = document.querySelector<HTMLElement>('#settings')!;
const player = document.querySelector<HTMLElement>('.player')!;
const configStatus = document.querySelector<HTMLElement>('#config-status')!;
const statusElement = document.querySelector<HTMLElement>('#status')!;
const stageStatus = document.querySelector<HTMLElement>('#stage-status')!;
const metrics = document.querySelector<HTMLElement>('#metrics')!;
const remoteVideoGrid = document.querySelector<HTMLElement>('#remote-video-grid')!;
const metricsPanel = document.querySelector<HTMLElement>('.metrics-panel')!;
const commandPanel = document.querySelector<HTMLDialogElement>('#command-panel')!;
const preferenceSheet = document.querySelector<HTMLDialogElement>('#preference-sheet')!;
const messageBubble = document.querySelector<HTMLElement>('#message-bubble')!;
const recordButton = document.querySelector<HTMLButtonElement>('#record')!;
const saveMediaButton = document.querySelector<HTMLButtonElement>('#save-media')!;
const muteButton = document.querySelector<HTMLButtonElement>('#mute')!;
const localAudioButton = document.querySelector<HTMLButtonElement>('#local-audio')!;
const rawDumpButton = document.querySelector<HTMLButtonElement>('#raw-dump')!;
let currentState: ExampleState | null = null;
let settingsVisible = false;
let productMode: 'rtc' | 'ti-cloud-storage' = 'rtc';
let rtcMaximizedVideoId: number | null = null;
let cloudMaximizedVideoId: number | null = null;

const DEFAULT_SETTINGS: ExampleSettings = {
  videoDecoderPreference: 'auto',
  outputBufferPolicy: 'automatic',
  consoleLogEnabled: false,
  localAudioCodec: 'g711a',
  localAudioSampleRateHz: 16000,
  localAudioStreamId: 14,
  localAudioAecEnabled: false,
  localAudioAgcLevel: 'disabled',
  localAudioAnsLevel: 'disabled',
};

type SettingKey = keyof ExampleSettings;
type SettingOption = Readonly<{value: string | number; label: string}>;
const SETTING_OPTIONS: Partial<Record<SettingKey, ReadonlyArray<SettingOption>>> = {
  videoDecoderPreference: [
    {value: 'auto', label: '自动'}, {value: 'hardware', label: '硬解'}, {value: 'software', label: '软解'},
  ],
  outputBufferPolicy: [{value: 'automatic', label: '自动'}, {value: 'noBuffer', label: '不缓冲'}],
  localAudioCodec: [
    {value: 'g711a', label: 'G711A'}, {value: 'aac', label: 'AAC'}, {value: 'pcm', label: 'PCM'},
    {value: 'opus', label: 'OPUS'}, {value: 'amr', label: 'AMR'},
  ],
  localAudioSampleRateHz: [{value: 8000, label: '8 kHz'}, {value: 16000, label: '16 kHz'}],
  localAudioStreamId: Array.from({length: 16}, (_, value) => ({value, label: String(value)})),
  localAudioAgcLevel: [
    {value: 'disabled', label: '关闭'}, {value: 'low', label: '低'},
    {value: 'medium', label: '中'}, {value: 'high', label: '高'},
  ],
  localAudioAnsLevel: [
    {value: 'disabled', label: '关闭'}, {value: 'low', label: '低'},
    {value: 'medium', label: '中'}, {value: 'high', label: '高'},
  ],
};
const SETTING_TITLES: Partial<Record<SettingKey, string>> = {
  videoDecoderPreference: '视频解码偏好', outputBufferPolicy: '输出缓冲策略',
  localAudioCodec: '编码格式', localAudioSampleRateHz: '采样率',
  localAudioStreamId: '传输 Stream ID', localAudioAgcLevel: 'AGC', localAudioAnsLevel: 'ANS',
};

function loadSettings(): ExampleSettings {
  try {
    const stored = JSON.parse(localStorage.getItem('tirtc_example.settings') ?? '{}') as Partial<ExampleSettings>;
    return {...DEFAULT_SETTINGS, ...stored};
  } catch {
    return DEFAULT_SETTINGS;
  }
}

let settings = loadSettings();

function settingLabel(key: SettingKey): string {
  return SETTING_OPTIONS[key]?.find((option) => option.value === settings[key])?.label ?? String(settings[key]);
}

function renderSettings(): void {
  for (const key of Object.keys(SETTING_OPTIONS) as SettingKey[]) {
    document.querySelector(`#setting-${key}`)!.textContent = settingLabel(key);
  }
  for (const key of ['localAudioAecEnabled', 'consoleLogEnabled'] as const) {
    document.querySelector<HTMLInputElement>(`input[name="${key}"]`)!.checked = settings[key];
  }
  localStorage.setItem('tirtc_example.settings', JSON.stringify(settings));
}

function showSettings(visible: boolean): void {
  settingsVisible = visible;
  if (visible) {
    form.hidden = true;
    player.hidden = true;
    tiCloudStorageForm.hidden = true;
    tiCloudStoragePlayer.hidden = true;
    settingsPage.hidden = false;
  } else {
    settingsPage.hidden = true;
    showProduct(productMode);
  }
}

document.querySelector('#open-settings')!.addEventListener('click', () => showSettings(true));
document.querySelector('#close-settings')!.addEventListener('click', () => showSettings(false));
for (const key of ['localAudioAecEnabled', 'consoleLogEnabled'] as const) {
  document.querySelector<HTMLInputElement>(`input[name="${key}"]`)!.addEventListener('change', (event) => {
    settings = {...settings, [key]: (event.target as HTMLInputElement).checked};
    renderSettings();
  });
}
document.querySelectorAll<HTMLButtonElement>('[data-setting]').forEach((button) => {
  button.addEventListener('click', () => {
    const key = button.dataset.setting as SettingKey;
    const options = SETTING_OPTIONS[key];
    if (!options) return;
    document.querySelector('#preference-title')!.textContent = SETTING_TITLES[key] ?? '';
    const target = document.querySelector<HTMLElement>('#preference-options')!;
    target.replaceChildren(...options.map((option) => {
      const choice = document.createElement('button');
      choice.type = 'button';
      choice.className = `preference-option${option.value === settings[key] ? ' selected' : ''}`;
      choice.innerHTML = '<i></i><span></span>';
      choice.querySelector('span')!.textContent = option.label;
      choice.addEventListener('click', () => {
        settings = {...settings, [key]: option.value};
        if (key === 'localAudioCodec' && option.value === 'amr') {
          settings = {...settings, localAudioSampleRateHz: 8000};
        }
        renderSettings();
        preferenceSheet.close();
      });
      return choice;
    }));
    preferenceSheet.showModal();
  });
});
renderSettings();

function optionalNumericField(data: FormData, name: string): number | null {
  const text = String(data.get(name) ?? '').trim();
  return text === '' ? null : Number(text);
}

function installVideoIdEditor(
  containerId: string, addId: string, fieldName: string, label: string,
  fieldTestPrefix: string, removeTestPrefix: string,
): (next: readonly string[]) => void {
  const container = document.querySelector<HTMLElement>(`#${containerId}`)!;
  const add = document.querySelector<HTMLButtonElement>(`#${addId}`)!;
  const values = () => [...container.querySelectorAll<HTMLInputElement>(`input[name="${fieldName}"]`)].map((input) => input.value);
  const render = (next: readonly string[]) => {
    container.replaceChildren(...next.map((value, index) => {
      const row = document.createElement('label');
      row.className = 'field video-id-field';
      const title = document.createElement('span');
      title.textContent = `${label} ${index + 1}`;
      const input = document.createElement('input');
      input.name = fieldName;
      input.inputMode = 'numeric';
      input.value = value;
      input.dataset.testid = `${fieldTestPrefix}_${index + 1}`;
      const remove = document.createElement('button');
      remove.type = 'button';
      remove.className = 'remove-video-id';
      remove.textContent = '删除';
      remove.dataset.testid = `${removeTestPrefix}_${index + 1}`;
      remove.addEventListener('click', () => render(values().filter((_, itemIndex) => itemIndex !== index)));
      row.append(title, input, remove);
      return row;
    }));
    add.disabled = next.length >= 3;
    add.textContent = `＋ 添加视频（${next.length}/3）`;
  };
  add.addEventListener('click', () => { if (values().length < 3) render([...values(), '']); });
  render(values());
  return render;
}

const renderRtcVideoIds = installVideoIdEditor(
  'rtc-video-stream-fields', 'rtc-add-video-stream', 'videoStreamId', 'video_stream_id',
  'tirtc_example_video_stream_id_field', 'tirtc_example_remove_video_stream_id_button',
);
const renderCloudVideoIds = installVideoIdEditor(
  'cloud-video-channel-fields', 'cloud-add-video-channel', 'videoChannelId', 'video_channel_id',
  'tirtc_example_cloud_storage_video_channel_field', 'tirtc_example_remove_cloud_storage_video_channel_button',
);

function storedVideoIds(listKey: string, fallback: readonly string[]): readonly string[] {
  const stored = localStorage.getItem(listKey);
  if (stored !== null) {
    try {
      const values = JSON.parse(stored) as unknown;
      if (Array.isArray(values)) return values.filter((value): value is string => typeof value === 'string').slice(0, 3);
    } catch { /* fall through to the current default */ }
  }
  return fallback;
}

renderRtcVideoIds(storedVideoIds('tirtc_example.rtc.video_stream_ids', ['11']));
renderCloudVideoIds(storedVideoIds(
  'tirtc_example.cloud.video_channel_ids', ['11']));
(form.elements.namedItem('audioStreamId') as HTMLInputElement).value =
  localStorage.getItem('tirtc_example.rtc.audio_stream_id') ?? '10';
(document.querySelector<HTMLInputElement>('#ti-cloud-storage-config input[name="audioChannelId"]')!).value =
  localStorage.getItem('tirtc_example.cloud.audio_channel_id') ?? '10';

function config(): ExampleConfig {
  const data = new FormData(form);
  return {
    appId: String(data.get('appId') ?? '').trim(),
    endpoint: String(data.get('endpoint') ?? '').trim(),
    remoteId: String(data.get('remoteId') ?? '').trim(),
    tokenServerAddress: String(data.get('tokenServerAddress') ?? '').trim(),
    audioStreamId: optionalNumericField(data, 'audioStreamId'),
    videoStreamIds: data.getAll('videoStreamId').map(String).map((value) => value.trim()).filter(Boolean).map(Number),
    settings,
  };
}

async function updateBounds(): Promise<void> {
  await Promise.all([...remoteVideoGrid.querySelectorAll<HTMLElement>('[data-video-id]')].map((tile) => {
    const bounds = tile.getBoundingClientRect();
    return example.setVideoBounds(Number(tile.dataset.videoId), {
      x: Math.round(bounds.x), y: Math.round(bounds.y),
      width: Math.round(bounds.width), height: Math.round(bounds.height),
    });
  }));
}

function syncGridViewportClass(grid: HTMLElement): void {
  grid.classList.toggle('wide', innerWidth >= 600);
  grid.classList.toggle('compact', innerWidth < 600);
}

function setBusy(busy: boolean, uploadingLogs = false): void {
  const submit = form.querySelector<HTMLButtonElement>('.primary-button')!;
  submit.disabled = busy || uploadingLogs;
  submit.querySelector('.connect-label')!.textContent = busy ? '初始化中' : '开始连接、拉流播放';
  const configLogs = document.querySelector<HTMLButtonElement>('#config-logs')!;
  configLogs.disabled = busy || uploadingLogs;
  configLogs.textContent = uploadingLogs ? '上传中' : '上传日志';
}

form.addEventListener('submit', async (event) => {
  event.preventDefault();
  const next = config();
  const videos = next.videoStreamIds ?? [];
  if ((next.audioStreamId !== null && (!Number.isInteger(next.audioStreamId) || next.audioStreamId! < 0 || next.audioStreamId! > 15)) ||
      videos.length > 3 || videos.some((id) => !Number.isInteger(id) || id < 0 || id > 15) ||
      new Set(videos).size !== videos.length || (next.audioStreamId !== null && videos.includes(next.audioStreamId!))) {
    configStatus.textContent = '可选一路音频和最多三路不重复视频，Stream ID 必须是 0..15 内的整数。';
    return;
  }
  setBusy(true);
  localStorage.setItem('tirtc_example.rtc.audio_stream_id', next.audioStreamId === null ? '' : String(next.audioStreamId));
  localStorage.setItem('tirtc_example.rtc.video_stream_ids', JSON.stringify(videos.map(String)));
  configStatus.textContent = '';
  document.querySelector('#player-remote-id')!.textContent = next.remoteId;
  try {
    await example.configure(next);
    requestAnimationFrame(() => void updateBounds());
  } catch (error) {
    configStatus.textContent = `连接失败 · ${errorMessage(error)}`;
    setBusy(false);
  }
});

window.addEventListener('resize', () => {
  syncGridViewportClass(remoteVideoGrid);
  syncGridViewportClass(tiCloudStorageVideoGrid);
  requestAnimationFrame(() => {
    if (productMode === 'rtc') void updateBounds();
    else void tiCloudStorageUpdateBounds();
  });
});

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

async function command(operation: () => Promise<void>): Promise<void> {
  try {
    await operation();
  } catch (error) {
    setPlayerFeedback(`操作失败 · ${errorMessage(error)}`);
  }
}

function setPlayerFeedback(message: string): void {
  statusElement.textContent = message;
  statusElement.hidden = message.length === 0;
}

recordButton.addEventListener('click', () => {
  void command(() => currentState?.recording ? example.stopRecording() : example.startRecording());
});
document.querySelector('#snapshot')!.addEventListener('click', () =>
  void command(() => example.takeSnapshot()));
saveMediaButton.addEventListener('click', () => {
  const kind = currentState?.recentSnapshot ? 'snapshot' : 'recording';
  void command(() => example.saveRecent(kind));
});
document.querySelector('#save-recording')!.addEventListener('click', () =>
  void command(() => example.saveRecent('recording')));
document.querySelector('#save-snapshot')!.addEventListener('click', () =>
  void command(() => example.saveRecent('snapshot')));
document.querySelector('#logs')!.addEventListener('click', () =>
  void command(() => example.uploadLogs()));
rawDumpButton.addEventListener('click', () =>
  void command(() => example.toggleRawDump()));
document.querySelector('#config-logs')!.addEventListener('click', () =>
  void command(() => example.uploadLogs()));
document.querySelector('#ti-cloud-storage-config-logs')!.addEventListener('click', () =>
  void tiCloudStorageCommand(() => example.tiCloudStorageUploadLogs()));
document.querySelector('#leave')!.addEventListener('click', () => void command(() => example.leave()));
document.querySelector('#stop-playback')!.addEventListener('click', () =>
  void command(() => example.leave()));
document.querySelector('#command-toggle')!.addEventListener('click', () => {
  commandPanel.showModal();
  document.querySelector<HTMLInputElement>('#message')!.focus();
});
commandPanel.addEventListener('close', () => {
  document.querySelector<HTMLElement>('[data-testid="tirtc_example_player_more_button"]')!.focus();
});
commandPanel.addEventListener('pointerdown', (event) => {
  if (event.target === commandPanel) commandPanel.close('cancel');
});
const actionMenus = [...document.querySelectorAll<HTMLDetailsElement>('.action-menu')];
function closeActionMenu(menu: HTMLDetailsElement, restoreFocus = true): void {
  if (!menu.open) return;
  menu.open = false;
  if (restoreFocus) menu.querySelector<HTMLElement>('summary')?.focus();
}
for (const menu of actionMenus) {
  menu.addEventListener('keydown', (event) => {
    if (event.key !== 'Escape' || !menu.open) return;
    event.preventDefault();
    event.stopPropagation();
    closeActionMenu(menu);
  });
  menu.querySelectorAll<HTMLButtonElement>('.action-menu-popover button').forEach((button) => {
    button.addEventListener('click', () => closeActionMenu(menu, button.id !== 'command-toggle'));
  });
}
document.addEventListener('pointerdown', (event) => {
  for (const menu of actionMenus) {
    if (menu.open && event.target instanceof Node && !menu.contains(event.target)) {
      event.preventDefault();
      closeActionMenu(menu);
    }
  }
});
document.querySelector('#send')!.addEventListener('click', () => {
  const input = document.querySelector<HTMLInputElement>('#message')!;
  const commandId = Number(document.querySelector<HTMLInputElement>('#command-id')!.value);
  void command(() => example.sendCommand(commandId, input.value));
});
document.querySelector('#echo-preset')!.addEventListener('click', () => {
  document.querySelector<HTMLInputElement>('#command-id')!.value = '1';
  document.querySelector<HTMLInputElement>('#message')!.value = 'echo';
});
muteButton.addEventListener('click', () =>
  void command(() => example.setAudioMuted(!(currentState?.audioMuted ?? false))));
localAudioButton.addEventListener('click', () =>
  void command(() => example.setLocalAudioRunning(!(currentState?.localAudioRunning ?? false))));
document.querySelector('#metrics-collapse')!.addEventListener('click', () => {
  metricsPanel.classList.toggle('collapsed');
  const button = document.querySelector<HTMLButtonElement>('#metrics-collapse')!;
  button.dataset.testid = metricsPanel.classList.contains('collapsed')
    ? 'tirtc_example_downlink_metrics_stats_expand_action'
    : 'tirtc_example_downlink_metrics_stats_collapse_action';
});
document.querySelector('#metrics-help')!.addEventListener('click', () => {
  document.querySelector<HTMLDialogElement>('#metrics-explanation')!.showModal();
});

function metricValue(source: unknown, key: string): unknown {
  return source && typeof source === 'object' ? (source as Record<string, unknown>)[key] : null;
}

function objectValue(source: unknown, key: string): Record<string, unknown> | null {
  const value = metricValue(source, key);
  return value && typeof value === 'object' ? value as Record<string, unknown> : null;
}

function finiteNumber(value: unknown): number | null {
  return typeof value === 'number' && Number.isFinite(value) ? value : null;
}

function duration(value: unknown): string {
  const number = finiteNumber(value);
  return number !== null && number >= 0 ? `${Math.round(number)} ms` : '--';
}

function rate(value: unknown, unit: string, digits = 1): string {
  const number = finiteNumber(value);
  return number !== null && number > 0
    ? `${number.toFixed(number >= 100 ? 0 : digits)} ${unit}`
    : '--';
}

function count(value: unknown): string {
  const number = finiteNumber(value);
  return number !== null && number >= 0 ? `${Math.round(number)} 次` : '--';
}

function setButtonIcon(button: HTMLButtonElement, path: string): void {
  const svg = button.querySelector('svg');
  if (svg) svg.innerHTML = `<path d="${path}"/>`;
}

function updateMetrics(state: ExampleState): void {
  const allMetrics = state.metrics as Record<string, unknown> | null;
  const connection = allMetrics?.connection;
  const video = allMetrics?.video;
  const audio = allMetrics?.audio;
  const videoStartup = objectValue(video, 'startup');
  const videoStutter = objectValue(video, 'stutter');
  const audioStutter = objectValue(audio, 'stutter');

  const width = finiteNumber(metricValue(video, 'videoWidth'));
  const height = finiteNumber(metricValue(video, 'videoHeight'));
  const size = width !== null && height !== null && width > 0 && height > 0
    ? `${Math.round(width)}x${Math.round(height)}`
    : '--';
  const videoCodec = String(metricValue(video, 'videoCodec') ?? '--').toUpperCase();
  const audioCodec = String(metricValue(audio, 'audioCodec') ?? '--').toUpperCase();
  const decoder = metricValue(video, 'decoderBackend') === 'hardware'
    ? '硬解'
    : metricValue(video, 'decoderBackend') === 'software' ? '软解' : '未确定';
  document.querySelector('#metric-media')!.textContent =
    `${size} · ${videoCodec} · ${audioCodec} · ${decoder}`;
  document.querySelector('#metric-video-receive')!.textContent =
    `码率 ${rate(metricValue(video, 'videoInputBitrateKbps'), 'kbps')} · ` +
    `接收 ${rate(metricValue(video, 'videoInputFps'), 'fps')}`;
  document.querySelector('#metric-audio-receive')!.textContent =
    `码率 ${rate(metricValue(audio, 'audioInputBitrateKbps'), 'kbps')} · ` +
    `PPS ${rate(metricValue(audio, 'audioInputPacketRate'), '/s')}`;
  document.querySelector('#metric-latency')!.textContent =
    `视频 ${duration(metricValue(video, 'estimatedOutputLatencyMs'))} · ` +
    `音频 ${duration(metricValue(audio, 'estimatedOutputLatencyMs'))}`;

  const connectMs = finiteNumber(metricValue(connection, 'connectDurationMs'));
  const firstOutputMs = finiteNumber(videoStartup?.timeToFirstOutputMs);
  document.querySelector('#metric-startup')!.textContent =
    connectMs !== null && firstOutputMs !== null && connectMs >= 0 && firstOutputMs >= connectMs
      ? `连接 ${duration(connectMs)} · 首帧等待 ${duration(firstOutputMs - connectMs)}`
      : `连接 ${duration(connectMs)} · 首帧总耗时 ${duration(firstOutputMs)}`;
  document.querySelector('#metric-stutter')!.textContent =
    `视频 ${count(videoStutter?.stutterCount)} / 最长 ${duration(videoStutter?.stutterPeakMs)} · ` +
    `音频 ${count(audioStutter?.stutterCount)} / 最长 ${duration(audioStutter?.stutterPeakMs)}`;
}

function renderRtcVideoGrid(state: ExampleState): void {
  const ids = [...state.videoStreamIds];
  const focusedLaneId = document.activeElement instanceof HTMLElement && remoteVideoGrid.contains(document.activeElement)
    ? document.activeElement.closest<HTMLElement>('[data-video-id]')?.dataset.videoId ?? null
    : null;
  if (rtcMaximizedVideoId !== null && !ids.includes(rtcMaximizedVideoId)) rtcMaximizedVideoId = null;
  remoteVideoGrid.className = `video-stage video-grid count-${ids.length}${rtcMaximizedVideoId === null ? '' : ' maximized'}`;
  syncGridViewportClass(remoteVideoGrid);
  if (ids.length === 0) {
    const empty = document.createElement('div');
    empty.className = 'video-tile-status';
    empty.textContent = state.hasAudio ? '仅音频播放' : '未配置音视频';
    remoteVideoGrid.replaceChildren(empty);
    return;
  }
  const orderedIds = [...ids].sort((left, right) =>
    left === state.selectedVideoStreamId ? -1 : right === state.selectedVideoStreamId ? 1 : 0);
  remoteVideoGrid.replaceChildren(...orderedIds.map((streamId) => {
    const index = ids.indexOf(streamId);
    const selected = state.selectedVideoStreamId === streamId;
    const tile = document.createElement('div');
    tile.className = `video-tile${selected ? ' selected primary' : ' secondary'}${rtcMaximizedVideoId === streamId ? ' maximized' : ''}`;
    tile.dataset.videoId = String(streamId);
    tile.dataset.testid = `tirtc_example_rtc_video_lane_${streamId}`;
    tile.tabIndex = 0;
    tile.role = 'button';
    tile.ariaLabel = `视频 ${index + 1}，Stream ${streamId}`;
    tile.ariaPressed = String(selected);
    if (rtcMaximizedVideoId !== null && rtcMaximizedVideoId !== streamId) tile.hidden = true;
    const label = document.createElement('span');
    label.className = 'video-tile-label';
    label.textContent = `视频 ${index + 1} · Stream ${streamId}`;
    const laneState = state.videoStates[String(streamId)] ?? 'idle';
    const status = document.createElement('span');
    status.className = 'video-tile-status';
    status.textContent = laneState === 'failed' ? '播放失败' : '等待视频';
    status.hidden = laneState === 'rendering';
    const action = document.createElement('button');
    action.className = 'video-tile-action';
    action.type = 'button';
    action.textContent = rtcMaximizedVideoId === streamId ? '宫格' : '放大';
    action.hidden = state.selectedVideoStreamId !== streamId;
    action.addEventListener('click', (event) => {
      event.stopPropagation();
      rtcMaximizedVideoId = rtcMaximizedVideoId === streamId ? null : streamId;
      renderRtcVideoGrid(state);
      requestAnimationFrame(() => void updateBounds());
    });
    const activate = () => {
      if (selected) {
        rtcMaximizedVideoId = rtcMaximizedVideoId === streamId ? null : streamId;
        renderRtcVideoGrid(state);
        requestAnimationFrame(() => void updateBounds());
      } else {
        void command(() => example.selectVideoStream(streamId));
      }
    };
    tile.addEventListener('click', activate);
    tile.addEventListener('keydown', (event) => {
      if (event.key === 'Enter' || event.key === ' ') {
        event.preventDefault();
        activate();
      }
    });
    tile.append(status, label, action);
    return tile;
  }));
  if (focusedLaneId !== null) {
    [...remoteVideoGrid.querySelectorAll<HTMLElement>('[data-video-id]')]
      .find((tile) => tile.dataset.videoId === focusedLaneId)?.focus();
  }
}

example.onState((state) => {
  currentState = state;
  if (productMode !== 'rtc') return;
  const configuring = state.phase === 'configuration';
  form.hidden = !configuring || settingsVisible;
  settingsPage.hidden = !configuring || !settingsVisible;
  player.hidden = configuring;
  renderRtcVideoGrid(state);
  setBusy(state.phase === 'connecting', state.uploadingLogs);
  const playerLogs = document.querySelector<HTMLButtonElement>('#logs')!;
  playerLogs.disabled = state.uploadingLogs;
  playerLogs.textContent = state.uploadingLogs ? '上传中' : '上传日志';
  rawDumpButton.classList.toggle('capturing', state.rawDumpPhase === 'capturing');
  rawDumpButton.disabled = ['finalizing', 'uploading'].includes(state.rawDumpPhase) ||
    state.connectionState !== 'connected';
  rawDumpButton.querySelector('strong')!.textContent =
    state.rawDumpPhase === 'capturing' ? '结束上传' :
      state.rawDumpPhase === 'failed' ? '重试上传' : '抓数据';

  setPlayerFeedback(state.lastError
    ? `${state.message} · ${state.lastError.message}`
    : state.lastSavedFile ? `已保存 · ${state.lastSavedFile}` : '');
  stageStatus.textContent = state.phase === 'playing' ? '' : state.phase === 'failed' ? '连接失败' : '连接中';
  stageStatus.hidden = state.phase === 'playing';
  messageBubble.textContent = state.message;
  messageBubble.hidden = !state.message || state.phase !== 'playing';
  if (state.messageDirection !== null) {
    const commandId = state.messageCommandId === null ? 'stream' : String(state.messageCommandId);
    const events = document.querySelector<HTMLElement>('#command-events')!;
    const signature = `${state.messageDirection}:${commandId}:${state.message}`;
    if (events.dataset.latest !== signature) {
      const event = document.createElement('p');
      event.dataset.testid = `tirtc_example_command_panel_event_${state.messageDirection}_${commandId}`;
      event.textContent = `${state.messageDirection === 'sent' ? '已发送' : '已收到'} · ${commandId} · ${state.message}`;
      events.append(event);
      events.dataset.latest = signature;
    }
  }

  recordButton.classList.toggle('recording', state.recording);
  setButtonIcon(recordButton, state.recording
    ? 'M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm-3 7h6v6H9V9z'
    : 'M12 5a7 7 0 1 0 0 14 7 7 0 0 0 0-14z');
  recordButton.title = state.recording ? '停止本地保存' : '开始本地保存';
  const selectedVideoReady = state.selectedVideoStreamId !== null &&
    state.videoStates[String(state.selectedVideoStreamId)] === 'rendering';
  recordButton.disabled = !state.recording && (state.phase !== 'playing' || !selectedVideoReady);
  recordButton.title = state.recording ? '停止本地保存' : `开始本地保存 · Stream ${state.selectedVideoStreamId ?? '-'}`;
  document.querySelector<HTMLButtonElement>('#snapshot')!.disabled = state.phase !== 'playing' || !selectedVideoReady;
  saveMediaButton.disabled = !state.recentRecording && !state.recentSnapshot;
  (document.querySelector<HTMLButtonElement>('#save-recording')!).disabled = !state.recentRecording;
  (document.querySelector<HTMLButtonElement>('#save-snapshot')!).disabled = !state.recentSnapshot;
  muteButton.classList.toggle('muted', state.audioMuted);
  setButtonIcon(muteButton, state.audioMuted
    ? 'M4 9v6h4l5 4V5L8 9H4zm11.5-.5v2.1a3 3 0 0 1 0 2.8v2.1a5 5 0 0 0 0-7zm0-3.5v2a7 7 0 0 1 0 10v2a9 9 0 0 0 0-14z'
    : 'M16.5 12 20 8.5l-1.4-1.4-3.5 3.5-3.5-3.5-1.4 1.4 3.5 3.5-3.5 3.5 1.4 1.4 3.5-3.5 3.5 3.5 1.4-1.4-3.5-3.5zM4 9h4l5-4v3.2L9.2 12 13 15.8V19l-5-4H4V9z');
  muteButton.querySelector('span')!.textContent = state.audioMuted ? '恢复声音' : '静音';
  muteButton.disabled = state.connectionState !== 'connected' || !state.hasAudio;
  localAudioButton.classList.toggle('active', state.localAudioRunning);
  setButtonIcon(localAudioButton, state.localAudioRunning
    ? 'm19 11-2 0a5 5 0 0 1-.5 2.2l1.5 1.5A7 7 0 0 0 19 11zM4.3 3 3 4.3l6 6V11a3 3 0 0 0 4.7 2.5l1.4 1.4A5 5 0 0 1 7 11H5a7 7 0 0 0 6 6.9V21H8v2h8v-2h-3v-3.1c1.3-.2 2.5-.8 3.5-1.6l3.2 3.2 1.3-1.3L4.3 3zM15 10.2V5a3 3 0 0 0-5.9-.7L15 10.2z'
    : 'M12 14a3 3 0 0 0 3-3V5a3 3 0 1 0-6 0v6a3 3 0 0 0 3 3zm5-3a5 5 0 0 1-10 0H5a7 7 0 0 0 6 6.9V21H8v2h8v-2h-3v-3.1A7 7 0 0 0 19 11h-2z');
  localAudioButton.querySelector('span')!.textContent =
    state.localAudioRunning ? '停止麦克风' : '启动麦克风';
  localAudioButton.disabled = state.connectionState !== 'connected';
  metricsPanel.hidden = state.phase !== 'playing' || state.metrics === null;
  updateMetrics(state);
  metrics.textContent = state.metrics ? JSON.stringify(state.metrics, null, 2) : 'Metrics unavailable';

  if (configuring) {
    configStatus.textContent = state.lastError ? `${state.message} · ${state.lastError.message}` : '';
  } else {
    requestAnimationFrame(() => void updateBounds());
  }
});

const tiCloudStorageForm = document.querySelector<HTMLFormElement>('#ti-cloud-storage-config')!;
const tiCloudStoragePlayer = document.querySelector<HTMLElement>('#ti-cloud-storage-player')!;
const tiCloudStorageVideoGrid = document.querySelector<HTMLElement>('#ti-cloud-storage-video-grid')!;
const tiCloudStorageRanges = document.querySelector<HTMLElement>('#ti-cloud-storage-ranges')!;
const tiCloudStorageConfigStatus = document.querySelector<HTMLElement>('#ti-cloud-storage-config-status')!;
const tiCloudStorageStatus = document.querySelector<HTMLElement>('#ti-cloud-storage-status')!;
const tiCloudStorageSeek = document.querySelector<HTMLInputElement>('#ti-cloud-storage-seek')!;
const tiCloudStorageSeekPanel = document.querySelector<HTMLElement>('#ti-cloud-storage-seek-panel')!;
const tiCloudStorageSeekCurrent = document.querySelector<HTMLElement>('#ti-cloud-storage-seek-current')!;
const tiCloudStorageSeekEnd = document.querySelector<HTMLElement>('#ti-cloud-storage-seek-end')!;
const tiCloudStorageStageStatus = document.querySelector<HTMLElement>('#ti-cloud-storage-stage-status')!;
const tiCloudStorageRecordingsSheet = document.querySelector<HTMLDialogElement>('#ti-cloud-storage-recordings-sheet')!;
const tiCloudStorageCalendar = document.querySelector<HTMLElement>('#ti-cloud-storage-calendar')!;
const tiCloudStorageMonthTitle = document.querySelector<HTMLElement>('#ti-cloud-storage-month-title')!;
const tiCloudStorageQueryStatus = document.querySelector<HTMLElement>('#ti-cloud-storage-query-status')!;
const tiCloudStoragePause = document.querySelector<HTMLButtonElement>('#ti-cloud-storage-pause')!;
const tiCloudStorageSpeed = document.querySelector<HTMLSelectElement>('#ti-cloud-storage-speed')!;
const tiCloudStorageRecord = document.querySelector<HTMLButtonElement>('#ti-cloud-storage-record')!;
const tiCloudStorageSnapshot = document.querySelector<HTMLButtonElement>('#ti-cloud-storage-snapshot')!;
const tiCloudStorageSave = document.querySelector<HTMLButtonElement>('#ti-cloud-storage-save')!;
const tiCloudStorageMute = document.querySelector<HTMLButtonElement>('#ti-cloud-storage-mute')!;
const tiCloudStorageRawDump = document.querySelector<HTMLButtonElement>('#ti-cloud-storage-raw-dump')!;
let tiCloudStorageState: TiCloudStorageExampleState | null = null;
let tiCloudStorageMuted = false;
const TI_CLOUD_STORAGE_TIME_ZONE = 'Asia/Shanghai';
let tiCloudStorageSelectedDate = shanghaiDate(Date.now());
let tiCloudStorageVisibleMonth = tiCloudStorageSelectedDate.slice(0, 7);
let tiCloudStorageAvailableDates = new Set<string>();
let tiCloudStorageDayQueryGeneration = 0;
let tiCloudStorageMonthQueryGeneration = 0;
type RecordingsSurfaceState = Readonly<{
  kind: 'idle' | 'loading' | 'error' | 'empty' | 'populated' | 'export-busy';
  message: string;
}>;
let tiCloudStorageMonthStatus: RecordingsSurfaceState = {kind: 'idle', message: ''};
let tiCloudStoragePlaybackStatus: RecordingsSurfaceState = {kind: 'idle', message: ''};

function showProduct(mode: 'rtc' | 'ti-cloud-storage'): void {
  productMode = mode;
  settingsVisible = false;
  const rtcConfigVisible = mode === 'rtc' && (currentState?.phase ?? 'configuration') === 'configuration';
  form.hidden = !rtcConfigVisible;
  player.hidden = mode !== 'rtc' || rtcConfigVisible;
  settingsPage.hidden = true;
  const tiCloudStorageConfigured = (tiCloudStorageState?.phase ?? 'configuration') !== 'configuration';
  tiCloudStorageForm.hidden = mode !== 'ti-cloud-storage' || tiCloudStorageConfigured;
  tiCloudStoragePlayer.hidden = mode !== 'ti-cloud-storage' || !tiCloudStorageConfigured;
}

document.querySelector('#ti-cloud-storage-tab')!.addEventListener('click', () => showProduct('ti-cloud-storage'));
document.querySelector('#ti-cloud-storage-rtc-tab')!.addEventListener('click', () => showProduct('rtc'));
document.querySelector('#open-ti-cloud-storage-settings')!.addEventListener('click', () => showSettings(true));

function tiCloudStorageSelectedDay(): Readonly<{startTimeMs: number; endTimeMs: number}> | null {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(tiCloudStorageSelectedDate);
  if (!match) return null;
  const startTimeMs = Date.parse(`${tiCloudStorageSelectedDate}T00:00:00+08:00`);
  return {
    startTimeMs,
    endTimeMs: startTimeMs + 24 * 60 * 60 * 1000,
  };
}

function shanghaiDate(value: number): string {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: TI_CLOUD_STORAGE_TIME_ZONE, year: 'numeric', month: '2-digit', day: '2-digit',
  }).format(value);
}

function tiCloudStorageMonthBounds(month: string): [string, string] {
  const [year, value] = month.split('-').map(Number);
  const last = new Date(Date.UTC(year!, value!, 0)).getUTCDate();
  return [`${month}-01`, `${month}-${String(last).padStart(2, '0')}`];
}

function tiCloudStorageShiftMonth(delta: number): string {
  const [year, value] = tiCloudStorageVisibleMonth.split('-').map(Number);
  const date = new Date(Date.UTC(year!, value! - 1 + delta, 1));
  return `${date.getUTCFullYear()}-${String(date.getUTCMonth() + 1).padStart(2, '0')}`;
}

function tiCloudStorageRenderCalendar(): void {
  tiCloudStorageMonthTitle.textContent = tiCloudStorageVisibleMonth;
  const [year, value] = tiCloudStorageVisibleMonth.split('-').map(Number);
  const leading = new Date(Date.UTC(year!, value! - 1, 1)).getUTCDay();
  const last = new Date(Date.UTC(year!, value!, 0)).getUTCDate();
  const cells: HTMLElement[] = Array.from({length: leading}, () => document.createElement('i'));
  for (let day = 1; day <= last; day += 1) {
    const date = `${tiCloudStorageVisibleMonth}-${String(day).padStart(2, '0')}`;
    const button = document.createElement('button');
    button.type = 'button';
    button.dataset.testid = `tirtc-example-ti-cloud-storage-calendar-day_${date}`;
    const number = document.createElement('strong');
    number.textContent = String(day);
    const state = document.createElement('small');
    state.textContent = tiCloudStorageAvailableDates.has(date) ? '有录像' : '无录像';
    button.append(number, state);
    button.disabled = !tiCloudStorageAvailableDates.has(date);
    button.classList.toggle('selected', date === tiCloudStorageSelectedDate);
    button.setAttribute('aria-label', `选择 ${date}`);
    button.addEventListener('click', () => {
      tiCloudStorageSelectedDate = date;
      tiCloudStorageRenderCalendar();
      void tiCloudStorageQueryDay();
    });
    cells.push(button);
  }
  while (cells.length < 42) {
    const trailing = document.createElement('i');
    trailing.setAttribute('aria-hidden', 'true');
    cells.push(trailing);
  }
  tiCloudStorageCalendar.replaceChildren(...cells);
}

function renderTiCloudStorageRecordingsState(): void {
  const visible = tiCloudStoragePlaybackStatus.kind === 'export-busy'
    ? tiCloudStoragePlaybackStatus
    : ['error', 'loading'].includes(tiCloudStorageMonthStatus.kind)
      ? tiCloudStorageMonthStatus
      : tiCloudStoragePlaybackStatus.kind !== 'idle'
        ? tiCloudStoragePlaybackStatus
        : tiCloudStorageMonthStatus;
  tiCloudStorageRecordingsSheet.dataset.state = visible.kind;
  tiCloudStorageRecordingsSheet.dataset.monthState = tiCloudStorageMonthStatus.kind;
  tiCloudStorageRecordingsSheet.dataset.playbackState = tiCloudStoragePlaybackStatus.kind;
  tiCloudStorageQueryStatus.textContent = visible.message;
}

function setTiCloudStorageMonthStatus(kind: RecordingsSurfaceState['kind'], message: string): void {
  tiCloudStorageMonthStatus = {kind, message};
  renderTiCloudStorageRecordingsState();
}

function setTiCloudStoragePlaybackStatus(kind: RecordingsSurfaceState['kind'], message: string): void {
  tiCloudStoragePlaybackStatus = {kind, message};
  renderTiCloudStorageRecordingsState();
}

async function tiCloudStorageQueryMonth(): Promise<void> {
  const month = tiCloudStorageVisibleMonth;
  const generation = ++tiCloudStorageMonthQueryGeneration;
  tiCloudStorageAvailableDates = new Set();
  tiCloudStorageRenderCalendar();
  setTiCloudStorageMonthStatus('loading', '正在加载月份…');
  document.querySelector<HTMLButtonElement>('#ti-cloud-storage-calendar-retry')!.hidden = true;
  let result: Awaited<ReturnType<ExampleApi['tiCloudStorageQueryDays']>>;
  try {
    result = await example.tiCloudStorageQueryDays(
      ...tiCloudStorageMonthBounds(month), TI_CLOUD_STORAGE_TIME_ZONE,
    );
  } catch (error) {
    if (generation === tiCloudStorageMonthQueryGeneration && month === tiCloudStorageVisibleMonth) {
      setTiCloudStorageMonthStatus(
        'error', `月份加载失败 · ${errorMessage(error)} · 点击月份切换按钮重试`,
      );
      document.querySelector<HTMLButtonElement>('#ti-cloud-storage-calendar-retry')!.hidden = false;
    }
    return;
  }
  if (generation !== tiCloudStorageMonthQueryGeneration || month !== tiCloudStorageVisibleMonth) return;
  tiCloudStorageAvailableDates = new Set(result.filter((day) => day.hasRecording).map((day) => day.date));
  tiCloudStorageRenderCalendar();
  setTiCloudStorageMonthStatus(
    tiCloudStorageAvailableDates.size === 0 ? 'empty' : 'populated',
    tiCloudStorageAvailableDates.size === 0 ? '本月没有可用录像' : `本月有 ${tiCloudStorageAvailableDates.size} 天录像`,
  );
}

function tiCloudStorageFormatClock(timeMs: number): string {
  return new Date(timeMs).toLocaleTimeString('zh-CN', {
    timeZone: TI_CLOUD_STORAGE_TIME_ZONE,
    hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false,
  });
}

function tiCloudStorageFormatDuration(durationMs: number): string {
  const seconds = Math.max(0, Math.round(durationMs / 1000));
  return `${Math.floor(seconds / 60)} 分 ${String(seconds % 60).padStart(2, '0')} 秒`;
}

function tiCloudStorageConfig(): TiCloudStorageExampleConfig {
  const data = new FormData(tiCloudStorageForm);
  return {
    appId: String(data.get('appId') ?? '').trim(),
    endpoint: String(data.get('endpoint') ?? '').trim(),
    audioChannelId: optionalNumericField(data, 'audioChannelId'),
    videoChannelIds: data.getAll('videoChannelId').map(String).map((value) => value.trim()).filter(Boolean).map(Number),
  };
}

async function tiCloudStorageQueryDay(): Promise<void> {
  const date = tiCloudStorageSelectedDate;
  const generation = ++tiCloudStorageDayQueryGeneration;
  const bounds = tiCloudStorageSelectedDay();
  if (!bounds) {
    setTiCloudStoragePlaybackStatus('error', '请选择有效日期。');
    return;
  }
  try {
    await example.tiCloudStorageQuery(bounds.startTimeMs, bounds.endTimeMs);
  } catch (error) {
    if (generation === tiCloudStorageDayQueryGeneration && date === tiCloudStorageSelectedDate) {
      setTiCloudStoragePlaybackStatus('error', `查询失败 · ${errorMessage(error)}`);
    }
  }
}

function tiCloudStorageOpenRecordings(query: boolean): void {
  if (!tiCloudStorageRecordingsSheet.open) tiCloudStorageRecordingsSheet.showModal();
  void tiCloudStorageQueryMonth();
  if (query) void tiCloudStorageQueryDay();
}

tiCloudStorageForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  const next = tiCloudStorageConfig();
  const videos = next.videoChannelIds;
  if ((next.audioChannelId !== null && (!Number.isInteger(next.audioChannelId) || next.audioChannelId < 0 || next.audioChannelId > 255)) ||
      videos.length > 3 || videos.some((id) => !Number.isInteger(id) || id < 0 || id > 255) ||
      new Set(videos).size !== videos.length) {
    tiCloudStorageConfigStatus.textContent = '可选一路音频和最多三路不重复视频，Channel ID 必须是 0..255 内的整数。';
    return;
  }
  tiCloudStorageConfigStatus.textContent = '初始化中…';
  localStorage.setItem('tirtc_example.cloud.audio_channel_id',
    next.audioChannelId === null ? '' : String(next.audioChannelId));
  localStorage.setItem('tirtc_example.cloud.video_channel_ids', JSON.stringify(videos.map(String)));
  try {
    await example.tiCloudStorageConfigure(next);
    tiCloudStorageConfigStatus.textContent = '';
    showProduct('ti-cloud-storage');
    requestAnimationFrame(() => tiCloudStorageOpenRecordings(true));
  } catch (error) {
    tiCloudStorageConfigStatus.textContent = `初始化失败 · ${errorMessage(error)}`;
  }
});

async function tiCloudStorageUpdateBounds(): Promise<void> {
  await Promise.all([...tiCloudStorageVideoGrid.querySelectorAll<HTMLElement>('[data-video-id]')].map((tile) => {
    const bounds = tile.getBoundingClientRect();
    return example.tiCloudStorageSetVideoBounds(Number(tile.dataset.videoId), {
      x: Math.round(bounds.x), y: Math.round(bounds.y),
      width: Math.round(bounds.width), height: Math.round(bounds.height),
    });
  }));
}

document.querySelector('#ti-cloud-storage-leave')!.addEventListener('click', async () => {
  tiCloudStorageDayQueryGeneration += 1;
  tiCloudStorageMonthQueryGeneration += 1;
  if (tiCloudStorageRecordingsSheet.open) tiCloudStorageRecordingsSheet.close();
  await example.tiCloudStorageLeave();
  showProduct('ti-cloud-storage');
});
document.querySelector('#ti-cloud-storage-open-recordings')!.addEventListener('click', () => tiCloudStorageOpenRecordings(false));
tiCloudStorageRecordingsSheet.addEventListener('pointerdown', (event) => {
  if (event.target === tiCloudStorageRecordingsSheet) tiCloudStorageRecordingsSheet.close('cancel');
});
tiCloudStorageRecordingsSheet.addEventListener('close', () => {
  document.querySelector<HTMLButtonElement>('#ti-cloud-storage-open-recordings')!.focus();
});
document.querySelector('#ti-cloud-storage-previous-month')!.addEventListener('click', () => {
  tiCloudStorageVisibleMonth = tiCloudStorageShiftMonth(-1);
  void tiCloudStorageQueryMonth();
});
document.querySelector('#ti-cloud-storage-next-month')!.addEventListener('click', () => {
  tiCloudStorageVisibleMonth = tiCloudStorageShiftMonth(1);
  void tiCloudStorageQueryMonth();
});
document.querySelector('#ti-cloud-storage-refresh')!.addEventListener('click', () => {
  void tiCloudStorageQueryMonth();
  void tiCloudStorageQueryDay();
});
document.querySelector('#ti-cloud-storage-query-retry')!.addEventListener('click', () => {
  void tiCloudStorageQueryDay();
});
document.querySelector('#ti-cloud-storage-calendar-retry')!.addEventListener('click', () => {
  void tiCloudStorageQueryMonth();
});
tiCloudStorageRenderCalendar();

async function tiCloudStorageCommand(operation: () => Promise<void>, success = ''): Promise<void> {
  try {
    await operation();
    tiCloudStorageStatus.textContent = success;
  } catch (error) {
    tiCloudStorageStatus.textContent = `操作失败 · ${errorMessage(error)}`;
  }
}

tiCloudStoragePause.addEventListener('click', () => {
  const paused = tiCloudStorageState?.replayState === 'paused';
  void tiCloudStorageCommand(() => paused ? example.tiCloudStorageResume() : example.tiCloudStoragePause(), paused ? '继续播放' : '已暂停');
});
tiCloudStorageSpeed.addEventListener('change', () => {
  void tiCloudStorageCommand(
    () => example.tiCloudStorageSetSpeed(Number(tiCloudStorageSpeed.value) as TiCloudStorageReplaySpeed),
    `播放倍速：${tiCloudStorageSpeed.value}`,
  );
});
tiCloudStorageRecord.addEventListener('click', () => {
  const recording = tiCloudStorageState?.recording === true;
  void tiCloudStorageCommand(
    () => recording ? example.tiCloudStorageStopRecording() : example.tiCloudStorageStartRecording(),
    recording ? '边播边录完成' : '边播边录已开始',
  );
});
tiCloudStorageSnapshot.addEventListener('click', () =>
  void tiCloudStorageCommand(() => example.tiCloudStorageTakeSnapshot(), '截图完成'));
tiCloudStorageRawDump.addEventListener('click', () =>
  void tiCloudStorageCommand(() => example.tiCloudStorageToggleRawDump()));
tiCloudStorageMute.addEventListener('click', () => {
  tiCloudStorageMuted = !tiCloudStorageMuted;
  void tiCloudStorageCommand(async () => {
    try {
      await example.tiCloudStorageSetMuted(tiCloudStorageMuted);
    } catch (error) {
      tiCloudStorageMuted = !tiCloudStorageMuted;
      throw error;
    }
  }, tiCloudStorageMuted ? '已静音' : '已取消静音');
});
tiCloudStorageSave.addEventListener('click', () => {
  const kind = tiCloudStorageState?.recentSnapshot ? 'snapshot' : 'recording';
  void tiCloudStorageCommand(() => example.tiCloudStorageSaveRecent(kind), kind === 'snapshot' ? '截图已保存' : '录像已保存');
});
document.querySelector('#ti-cloud-storage-logs')!.addEventListener('click', () =>
  void tiCloudStorageCommand(() => example.tiCloudStorageUploadLogs()));
tiCloudStorageSeek.addEventListener('change', () => {
  if (!tiCloudStorageState || tiCloudStorageState.selectedIndex === null) return;
  const range = tiCloudStorageState.ranges[tiCloudStorageState.selectedIndex];
  if (!range) return;
  const value = range.startTimeMs + Math.round(
    (range.endTimeMs - range.startTimeMs) * Number(tiCloudStorageSeek.value) / 1000);
  void tiCloudStorageCommand(() => example.tiCloudStorageSeek(value), '已跳转');
});

function renderTiCloudStorageVideoGrid(state: TiCloudStorageExampleState): void {
  const ids = [...state.videoChannelIds];
  const focusedLaneId = document.activeElement instanceof HTMLElement && tiCloudStorageVideoGrid.contains(document.activeElement)
    ? document.activeElement.closest<HTMLElement>('[data-video-id]')?.dataset.videoId ?? null
    : null;
  if (cloudMaximizedVideoId !== null && !ids.includes(cloudMaximizedVideoId)) cloudMaximizedVideoId = null;
  tiCloudStorageVideoGrid.className = `video-stage video-grid count-${ids.length}${cloudMaximizedVideoId === null ? '' : ' maximized'}`;
  syncGridViewportClass(tiCloudStorageVideoGrid);
  if (ids.length === 0) {
    const empty = document.createElement('div');
    empty.className = 'video-tile-status';
    empty.textContent = state.hasAudio ? '仅音频回放' : '未配置音视频';
    tiCloudStorageVideoGrid.replaceChildren(empty);
    return;
  }
  const orderedIds = [...ids].sort((left, right) =>
    left === state.selectedVideoChannelId ? -1 : right === state.selectedVideoChannelId ? 1 : 0);
  tiCloudStorageVideoGrid.replaceChildren(...orderedIds.map((channelId) => {
    const index = ids.indexOf(channelId);
    const selected = state.selectedVideoChannelId === channelId;
    const tile = document.createElement('div');
    tile.className = `video-tile${selected ? ' selected primary' : ' secondary'}${cloudMaximizedVideoId === channelId ? ' maximized' : ''}`;
    tile.dataset.videoId = String(channelId);
    tile.dataset.testid = `tirtc_example_cloud_video_lane_${channelId}`;
    tile.tabIndex = 0;
    tile.role = 'button';
    tile.ariaLabel = `视频 ${index + 1}，Channel ${channelId}`;
    tile.ariaPressed = String(selected);
    if (cloudMaximizedVideoId !== null && cloudMaximizedVideoId !== channelId) tile.hidden = true;
    const label = document.createElement('span');
    label.className = 'video-tile-label';
    label.textContent = `视频 ${index + 1} · Channel ${channelId}`;
    const laneState = state.videoStates[String(channelId)] ?? 'idle';
    const status = document.createElement('span');
    status.className = 'video-tile-status';
    status.textContent = laneState === 'failed' ? '播放失败' : laneState === 'completed' ? '播放完成' : '等待视频';
    status.hidden = ['rendering', 'playing'].includes(laneState);
    const action = document.createElement('button');
    action.className = 'video-tile-action';
    action.type = 'button';
    action.textContent = cloudMaximizedVideoId === channelId ? '宫格' : '放大';
    action.hidden = state.selectedVideoChannelId !== channelId;
    action.addEventListener('click', (event) => {
      event.stopPropagation();
      cloudMaximizedVideoId = cloudMaximizedVideoId === channelId ? null : channelId;
      renderTiCloudStorageVideoGrid(state);
      requestAnimationFrame(() => void tiCloudStorageUpdateBounds());
    });
    const activate = () => {
      if (selected) {
        cloudMaximizedVideoId = cloudMaximizedVideoId === channelId ? null : channelId;
        renderTiCloudStorageVideoGrid(state);
        requestAnimationFrame(() => void tiCloudStorageUpdateBounds());
      } else {
        void tiCloudStorageCommand(() => example.tiCloudStorageSelectVideo(channelId));
      }
    };
    tile.addEventListener('click', activate);
    tile.addEventListener('keydown', (event) => {
      if (event.key === 'Enter' || event.key === ' ') {
        event.preventDefault();
        activate();
      }
    });
    tile.append(status, label, action);
    return tile;
  }));
  if (focusedLaneId !== null) {
    [...tiCloudStorageVideoGrid.querySelectorAll<HTMLElement>('[data-video-id]')]
      .find((tile) => tile.dataset.videoId === focusedLaneId)?.focus();
  }
}

example.tiCloudStorageOnState((state) => {
  tiCloudStorageState = state;
  if (productMode !== 'ti-cloud-storage') return;
  const configured = state.phase !== 'configuration';
  tiCloudStorageForm.hidden = configured;
  tiCloudStoragePlayer.hidden = !configured;
  renderTiCloudStorageVideoGrid(state);
  if (state.exportProgress !== null) {
    setTiCloudStoragePlaybackStatus('export-busy', `正在导出 · ${Math.round(state.exportProgress * 100)}%`);
  } else if (state.querying) {
    setTiCloudStoragePlaybackStatus('loading', '正在查询录像…');
  } else if (state.lastError) {
    setTiCloudStoragePlaybackStatus('error', `查询失败 · ${state.lastError.message}`);
  } else if (state.ranges.length === 0) {
    setTiCloudStoragePlaybackStatus('empty', '当天没有可用录像');
  } else {
    setTiCloudStoragePlaybackStatus('populated', `找到 ${state.ranges.length} 段录像`);
  }
  document.querySelector<HTMLButtonElement>('#ti-cloud-storage-query-retry')!.hidden =
    state.querying || state.lastError === null;
  tiCloudStorageRanges.replaceChildren(...state.ranges.map((range, index) => {
    const row = document.createElement('div');
    row.className = 'ti-cloud-storage-range-row';
    const playButton = document.createElement('button');
    playButton.type = 'button';
    playButton.className = 'ti-cloud-storage-range-main';
    playButton.innerHTML = '<strong></strong><small></small>';
    playButton.querySelector('strong')!.textContent =
      `${tiCloudStorageFormatClock(range.startTimeMs)} — ${tiCloudStorageFormatClock(range.endTimeMs)}`;
    playButton.querySelector('small')!.textContent = tiCloudStorageFormatDuration(range.endTimeMs - range.startTimeMs);
    playButton.setAttribute('aria-label', `播放录像 ${index + 1}，${playButton.querySelector('strong')!.textContent}`);
    playButton.addEventListener('click', async () => {
      try {
        await example.tiCloudStoragePlayRange(index);
        tiCloudStorageRecordingsSheet.close();
        requestAnimationFrame(() => void tiCloudStorageUpdateBounds());
      } catch (error) {
        tiCloudStorageStatus.textContent = `操作失败 · ${errorMessage(error)}`;
      }
    });
    const exportButton = document.createElement('button');
    exportButton.type = 'button';
    exportButton.className = 'ti-cloud-storage-range-export';
    exportButton.textContent = state.exportProgress === null ? '⇩' : `${Math.round(state.exportProgress * 100)}%`;
    exportButton.title = '下载';
    exportButton.setAttribute('aria-label', state.exportProgress === null
      ? `导出录像 ${index + 1}` : `正在导出录像 ${index + 1}，${Math.round(state.exportProgress * 100)}%`);
    exportButton.disabled = state.exportProgress !== null;
    exportButton.addEventListener('click', () =>
      void tiCloudStorageCommand(() => example.tiCloudStorageStartExport(index), '范围下载已开始'));
    row.append(playButton, exportButton);
    return row;
  }));
  const selectedRange = state.selectedIndex === null ? null : state.ranges[state.selectedIndex] ?? null;
  tiCloudStorageSeekPanel.hidden = selectedRange === null;
  if (selectedRange && state.currentTimeMs !== null) {
    const range = selectedRange;
    tiCloudStorageSeek.value = String(Math.max(0, Math.min(1000, Math.round(
      (state.currentTimeMs - range.startTimeMs) * 1000 / (range.endTimeMs - range.startTimeMs)))));
    tiCloudStorageSeekCurrent.textContent = tiCloudStorageFormatClock(state.currentTimeMs);
    tiCloudStorageSeekEnd.textContent = tiCloudStorageFormatClock(range.endTimeMs);
  }
  const playing = selectedRange !== null;
  tiCloudStorageStageStatus.hidden = playing && ['rendering', 'playing'].includes(state.replayState);
  tiCloudStorageStageStatus.textContent = !playing ? '请选择录像' :
    state.replayState === 'buffering' ? '缓冲中' :
      state.replayState === 'paused' ? '已暂停' :
        state.replayState === 'completed' ? '播放完成' : '';
  tiCloudStoragePause.disabled = !playing;
  tiCloudStoragePause.querySelector('span')!.textContent = state.replayState === 'paused' ? '继续播放' : '暂停播放';
  tiCloudStorageSpeed.disabled = !playing;
  tiCloudStorageSpeed.value = String(state.speed);
  const hasSelectedVideo = state.selectedVideoChannelId !== null;
  tiCloudStorageRecord.disabled = !playing || !hasSelectedVideo;
  tiCloudStorageRecord.classList.toggle('recording', state.recording);
  tiCloudStorageRecord.textContent = state.recording ? '■' : '●';
  tiCloudStorageRecord.title = state.recording ? '停止本地保存' : `开始本地保存 · Channel ${state.selectedVideoChannelId ?? '-'}`;
  tiCloudStorageSnapshot.disabled = !playing || !hasSelectedVideo;
  tiCloudStorageSnapshot.title = `截图 · Channel ${state.selectedVideoChannelId ?? '-'}`;
  tiCloudStorageMute.disabled = !playing || state.speed !== 1 || !state.hasAudio;
  tiCloudStorageMute.classList.toggle('muted', tiCloudStorageMuted || state.speed !== 1);
  tiCloudStorageSave.disabled = !state.recentRecording && !state.recentSnapshot;
  tiCloudStorageRawDump.classList.toggle('capturing', state.rawDumpPhase === 'capturing');
  tiCloudStorageRawDump.disabled = ['finalizing', 'uploading'].includes(state.rawDumpPhase) || !playing;
  tiCloudStorageRawDump.querySelector('strong')!.textContent =
    state.rawDumpPhase === 'capturing' ? '结束上传' :
      state.rawDumpPhase === 'failed' ? '重试上传' : '抓数据';
  document.querySelector<HTMLButtonElement>('#ti-cloud-storage-logs')!.textContent = state.uploadingLogs ? '上传中' : '上传日志';
  tiCloudStorageStatus.textContent = state.lastError ? `操作失败 · ${state.lastError.message}` :
    state.exportProgress !== null ? `正在导出 · ${Math.round(state.exportProgress * 100)}%` :
      state.message || (state.lastSavedFile ? `已保存 · ${state.lastSavedFile}` : '');
  if (configured) requestAnimationFrame(() => void tiCloudStorageUpdateBounds());
});
