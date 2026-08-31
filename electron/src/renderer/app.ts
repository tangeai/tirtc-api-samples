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
const remoteVideo = document.querySelector<HTMLElement>('#remote-video')!;
const metricsPanel = document.querySelector<HTMLElement>('.metrics-panel')!;
const commandPanel = document.querySelector<HTMLDialogElement>('#command-panel')!;
const preferenceSheet = document.querySelector<HTMLDialogElement>('#preference-sheet')!;
const messageBubble = document.querySelector<HTMLElement>('#message-bubble')!;
const recordButton = document.querySelector<HTMLButtonElement>('#record')!;
const saveMediaButton = document.querySelector<HTMLButtonElement>('#save-media')!;
const muteButton = document.querySelector<HTMLButtonElement>('#mute')!;
const localAudioButton = document.querySelector<HTMLButtonElement>('#local-audio')!;
let currentState: ExampleState | null = null;
let settingsVisible = false;
let productMode: 'rtc' | 'ti-cloud-storage' = 'rtc';

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

function numericField(data: FormData, name: string, fallback: number): number {
  const text = String(data.get(name) ?? '').trim();
  return text === '' ? fallback : Number(text);
}

function config(): ExampleConfig {
  const data = new FormData(form);
  return {
    appId: String(data.get('appId') ?? '').trim(),
    endpoint: String(data.get('endpoint') ?? '').trim(),
    remoteId: String(data.get('remoteId') ?? '').trim(),
    tokenServerAddress: String(data.get('tokenServerAddress') ?? '').trim(),
    audioStreamId: numericField(data, 'audioStreamId', 10),
    videoStreamId: numericField(data, 'videoStreamId', 11),
    settings,
  };
}

async function updateBounds(): Promise<void> {
  const bounds = remoteVideo.getBoundingClientRect();
  if (bounds.width < 1 || bounds.height < 1) return;
  await example.setVideoBounds({
    x: Math.round(bounds.x), y: Math.round(bounds.y),
    width: Math.round(bounds.width), height: Math.round(bounds.height),
  });
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
  if (!Number.isInteger(next.audioStreamId) || !Number.isInteger(next.videoStreamId) ||
      next.audioStreamId! < 0 || next.audioStreamId! > 15 ||
      next.videoStreamId! < 0 || next.videoStreamId! > 15 ||
      next.audioStreamId === next.videoStreamId) {
    configStatus.textContent = '音频和视频流 ID 必须是 0..15 内不同的整数。';
    return;
  }
  setBusy(true);
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

window.addEventListener('resize', () => { void updateBounds(); });

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

example.onState((state) => {
  currentState = state;
  if (productMode !== 'rtc') return;
  const configuring = state.phase === 'configuration';
  form.hidden = !configuring || settingsVisible;
  settingsPage.hidden = !configuring || !settingsVisible;
  player.hidden = configuring;
  setBusy(state.phase === 'connecting', state.uploadingLogs);
  const playerLogs = document.querySelector<HTMLButtonElement>('#logs')!;
  playerLogs.disabled = state.uploadingLogs;
  playerLogs.textContent = state.uploadingLogs ? '上传中' : '上传日志';

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
  recordButton.disabled = state.phase !== 'playing';
  document.querySelector<HTMLButtonElement>('#snapshot')!.disabled = state.phase !== 'playing';
  saveMediaButton.disabled = !state.recentRecording && !state.recentSnapshot;
  (document.querySelector<HTMLButtonElement>('#save-recording')!).disabled = !state.recentRecording;
  (document.querySelector<HTMLButtonElement>('#save-snapshot')!).disabled = !state.recentSnapshot;
  muteButton.classList.toggle('muted', state.audioMuted);
  setButtonIcon(muteButton, state.audioMuted
    ? 'M4 9v6h4l5 4V5L8 9H4zm11.5-.5v2.1a3 3 0 0 1 0 2.8v2.1a5 5 0 0 0 0-7zm0-3.5v2a7 7 0 0 1 0 10v2a9 9 0 0 0 0-14z'
    : 'M16.5 12 20 8.5l-1.4-1.4-3.5 3.5-3.5-3.5-1.4 1.4 3.5 3.5-3.5 3.5 1.4 1.4 3.5-3.5 3.5 3.5 1.4-1.4-3.5-3.5zM4 9h4l5-4v3.2L9.2 12 13 15.8V19l-5-4H4V9z');
  muteButton.querySelector('span')!.textContent = state.audioMuted ? '恢复声音' : '静音';
  muteButton.disabled = state.connectionState !== 'connected';
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
const tiCloudStorageVideo = document.querySelector<HTMLElement>('#ti-cloud-storage-video')!;
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
let tiCloudStorageState: TiCloudStorageExampleState | null = null;
let tiCloudStorageMuted = false;
const TI_CLOUD_STORAGE_TIME_ZONE = 'Asia/Shanghai';
let tiCloudStorageSelectedDate = shanghaiDate(Date.now());
let tiCloudStorageVisibleMonth = tiCloudStorageSelectedDate.slice(0, 7);
let tiCloudStorageAvailableDates = new Set<string>();
let tiCloudStorageDayQueryGeneration = 0;
let tiCloudStorageMonthQueryGeneration = 0;

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
  tiCloudStorageCalendar.replaceChildren(...cells);
}

async function tiCloudStorageQueryMonth(): Promise<void> {
  const month = tiCloudStorageVisibleMonth;
  const generation = ++tiCloudStorageMonthQueryGeneration;
  tiCloudStorageAvailableDates = new Set();
  tiCloudStorageRenderCalendar();
  tiCloudStorageQueryStatus.textContent = '正在加载月份…';
  document.querySelector<HTMLButtonElement>('#ti-cloud-storage-calendar-retry')!.hidden = true;
  let result: Awaited<ReturnType<ExampleApi['tiCloudStorageQueryDays']>>;
  try {
    result = await example.tiCloudStorageQueryDays(
      ...tiCloudStorageMonthBounds(month), TI_CLOUD_STORAGE_TIME_ZONE,
    );
  } catch (error) {
    if (generation === tiCloudStorageMonthQueryGeneration && month === tiCloudStorageVisibleMonth) {
      tiCloudStorageQueryStatus.textContent = `月份加载失败 · ${errorMessage(error)} · 点击月份切换按钮重试`;
      document.querySelector<HTMLButtonElement>('#ti-cloud-storage-calendar-retry')!.hidden = false;
    }
    return;
  }
  if (generation !== tiCloudStorageMonthQueryGeneration || month !== tiCloudStorageVisibleMonth) return;
  tiCloudStorageAvailableDates = new Set(result.filter((day) => day.hasRecording).map((day) => day.date));
  tiCloudStorageRenderCalendar();
  tiCloudStorageQueryStatus.textContent = tiCloudStorageAvailableDates.size === 0 ? '本月没有可用录像' : '';
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
    audioChannelId: Number(data.get('audioChannelId')),
    videoChannelId: Number(data.get('videoChannelId')),
  };
}

async function tiCloudStorageQueryDay(): Promise<void> {
  const date = tiCloudStorageSelectedDate;
  const generation = ++tiCloudStorageDayQueryGeneration;
  const bounds = tiCloudStorageSelectedDay();
  if (!bounds) {
    tiCloudStorageQueryStatus.textContent = '请选择有效日期。';
    return;
  }
  try {
    await example.tiCloudStorageQuery(bounds.startTimeMs, bounds.endTimeMs);
  } catch (error) {
    if (generation === tiCloudStorageDayQueryGeneration && date === tiCloudStorageSelectedDate) {
      tiCloudStorageQueryStatus.textContent = `查询失败 · ${errorMessage(error)}`;
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
  if (!Number.isInteger(next.audioChannelId) || next.audioChannelId < 0 || next.audioChannelId > 255 ||
      !Number.isInteger(next.videoChannelId) || next.videoChannelId < 0 || next.videoChannelId > 255) {
    tiCloudStorageConfigStatus.textContent = '音频和视频 Channel ID 必须是 0..255 内的整数。';
    return;
  }
  tiCloudStorageConfigStatus.textContent = '初始化中…';
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
  const bounds = tiCloudStorageVideo.getBoundingClientRect();
  if (bounds.width < 1 || bounds.height < 1) return;
  await example.tiCloudStorageSetVideoBounds({
    x: Math.round(bounds.x), y: Math.round(bounds.y),
    width: Math.round(bounds.width), height: Math.round(bounds.height),
  });
}

window.addEventListener('resize', () => { if (productMode === 'ti-cloud-storage') void tiCloudStorageUpdateBounds(); });
document.querySelector('#ti-cloud-storage-leave')!.addEventListener('click', async () => {
  tiCloudStorageDayQueryGeneration += 1;
  tiCloudStorageMonthQueryGeneration += 1;
  if (tiCloudStorageRecordingsSheet.open) tiCloudStorageRecordingsSheet.close();
  await example.tiCloudStorageLeave();
  showProduct('ti-cloud-storage');
});
document.querySelector('#ti-cloud-storage-open-recordings')!.addEventListener('click', () => tiCloudStorageOpenRecordings(false));
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

example.tiCloudStorageOnState((state) => {
  tiCloudStorageState = state;
  if (productMode !== 'ti-cloud-storage') return;
  const configured = state.phase !== 'configuration';
  tiCloudStorageForm.hidden = configured;
  tiCloudStoragePlayer.hidden = !configured;
  tiCloudStorageQueryStatus.textContent = state.querying ? '正在查询录像…' :
    state.lastError ? `查询失败 · ${state.lastError.message}` :
      state.ranges.length === 0 ? '当天没有可用录像' : '';
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
  tiCloudStorageRecord.disabled = !playing;
  tiCloudStorageRecord.classList.toggle('recording', state.recording);
  tiCloudStorageRecord.textContent = state.recording ? '■' : '●';
  tiCloudStorageRecord.title = state.recording ? '停止本地保存' : '开始本地保存';
  tiCloudStorageSnapshot.disabled = !playing;
  tiCloudStorageMute.disabled = !playing || state.speed !== 1;
  tiCloudStorageMute.classList.toggle('muted', tiCloudStorageMuted || state.speed !== 1);
  tiCloudStorageSave.disabled = !state.recentRecording && !state.recentSnapshot;
  document.querySelector<HTMLButtonElement>('#ti-cloud-storage-logs')!.textContent = state.uploadingLogs ? '上传中' : '上传日志';
  tiCloudStorageStatus.textContent = state.lastError ? `操作失败 · ${state.lastError.message}` :
    state.exportProgress !== null ? `正在导出 · ${Math.round(state.exportProgress * 100)}%` :
      state.message || (state.lastSavedFile ? `已保存 · ${state.lastSavedFile}` : '');
});
