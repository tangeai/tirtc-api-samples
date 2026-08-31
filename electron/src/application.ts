import fs from 'node:fs';
import path from 'node:path';
import {app, BrowserWindow, ipcMain, screen, shell, systemPreferences} from 'electron';
import type {Rectangle} from 'electron';
import type {TiCloudStorageReplaySpeed} from 'tirtc-electron';

import {ExampleSession} from './session';
import type {ExampleSessionConfig} from './session';
import {TiCloudStorageExampleSession} from './storage_session';
import type {TiCloudStorageExampleSessionConfig} from './storage_session';
import type {ExampleConfig, TiCloudStorageExampleConfig} from './shared/types';
import {cleanupSessions, finishQuit} from './application_cleanup';

export type ExampleApplication = Readonly<{
  window: BrowserWindow;
  session: ExampleSession;
  tiCloudStorageSession: TiCloudStorageExampleSession;
}>;

let activeApplication: ExampleApplication | null = null;
let cleanupPromise: Promise<void> | null = null;
let ipcInstalled = false;
let quittingAfterCleanup = false;

const credentialCache = new Map<string, string>();

function mainProcessCredential(name: string, format: 'rtc-v1' | 'opaque'): string | null {
  const cached = credentialCache.get(name);
  if (cached) return cached;
  const descriptorName = `${name}_FD`;
  const descriptorText = process.env[descriptorName];
  const descriptor = descriptorText === undefined ? null : Number(descriptorText);
  let supplied = process.env[name] ?? '';
  try {
    if (descriptor !== null) {
      if (!Number.isSafeInteger(descriptor) || descriptor < 3) {
        throw new TypeError(`${descriptorName} must identify an inherited credential file descriptor`);
      }
      supplied = fs.readFileSync(descriptor, 'utf8');
    }
  } finally {
    delete process.env[name];
    delete process.env[descriptorName];
    if (descriptor !== null && Number.isSafeInteger(descriptor) && descriptor >= 3) {
      try { fs.closeSync(descriptor); } catch {}
    }
  }
  const token = supplied.trim();
  if (!token) return null;
  if (format === 'rtc-v1' && !token.startsWith('v1.')) {
    throw new TypeError(`${name} must contain a v1 Token`);
  }
  credentialCache.set(name, token);
  return token;
}

async function resolveExampleToken(config: ExampleConfig): Promise<ExampleSessionConfig> {
  const supplied = mainProcessCredential('TIRTC_EXAMPLE_RTC_TOKEN', 'rtc-v1');
  if (supplied) return {...config, token: supplied};
  let origin: URL;
  try {
    origin = new URL(config.tokenServerAddress?.trim() ?? '');
  } catch {
    throw new TypeError('tokenServerAddress must be a valid URL origin');
  }
  if ((origin.protocol !== 'http:' && origin.protocol !== 'https:') || origin.username ||
      origin.password || (origin.pathname !== '/' && origin.pathname !== '') ||
      origin.search || origin.hash) {
    throw new TypeError('tokenServerAddress must be an HTTP(S) URL origin');
  }
  origin.pathname = '/v1/tokens';
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 10_000);
  try {
    const response = await fetch(origin, {
      method: 'POST',
      headers: {'content-type': 'application/json'},
      body: JSON.stringify({remote_id: config.remoteId}),
      signal: controller.signal,
    });
    if (!response.ok || !response.body) throw new Error('token server request failed');
    const reader = response.body.getReader();
    const chunks: Uint8Array[] = [];
    let size = 0;
    while (true) {
      const {done, value} = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > 8192) {
        await reader.cancel();
        throw new Error('token server response is too large');
      }
      chunks.push(value);
    }
    const body = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) {
      body.set(chunk, offset);
      offset += chunk.byteLength;
    }
    const parsed = JSON.parse(new TextDecoder().decode(body)) as {token?: unknown};
    if (typeof parsed.token !== 'string' || !parsed.token.trim().startsWith('v1.')) {
      throw new Error('token server returned an invalid token');
    }
    return {...config, token: parsed.token.trim()};
  } catch (error) {
    throw new Error('unable to obtain a token from the token server', {cause: error});
  } finally {
    clearTimeout(timer);
  }
}

function resolveTiCloudStorageToken(
  config: TiCloudStorageExampleConfig,
): TiCloudStorageExampleSessionConfig {
  const token = mainProcessCredential('TIRTC_EXAMPLE_TI_CLOUD_STORAGE_TOKEN', 'opaque');
  if (!token) throw new Error('Ti Cloud Storage Token is unavailable in the Main process');
  return {...config, token};
}

async function requestMediaPermissions(): Promise<boolean> {
  if (process.platform !== 'darwin') return true;
  return systemPreferences.askForMediaAccess('microphone');
}

function requireApplication(): ExampleApplication {
  if (!activeApplication) throw new Error('Electron Example is unavailable');
  return activeApplication;
}

function downloadsDestination(source: string): string {
  const parsed = path.parse(source);
  const directory = app.getPath('downloads');
  for (let suffix = 0; suffix < 10_000; suffix += 1) {
    const name = suffix === 0 ? parsed.base : `${parsed.name}-${suffix}${parsed.ext}`;
    const candidate = path.join(directory, name);
    if (!fs.existsSync(candidate)) return candidate;
  }
  throw new Error('unable to choose a unique Downloads file name');
}

function installIpc(): void {
  if (ipcInstalled) return;
  ipcInstalled = true;
  ipcMain.handle('tirtc-example:configure', async (_event, config: ExampleConfig) => {
    if (!(await requestMediaPermissions())) throw new Error('microphone permission denied');
    const current = requireApplication();
    await current.tiCloudStorageSession.leave();
    await current.session.configure(await resolveExampleToken(config));
  });
  ipcMain.handle('tirtc-example:video-bounds',
    (_event, bounds: Rectangle) => requireApplication().session.setVideoBounds(bounds));
  ipcMain.handle('tirtc-example:message', (_event, message: string) =>
    requireApplication().session.sendMessage(message));
  ipcMain.handle('tirtc-example:command', (_event, commandId: number, message: string) =>
    requireApplication().session.sendCommand(commandId, message));
  ipcMain.handle('tirtc-example:recording-start', () =>
    requireApplication().session.startRecording());
  ipcMain.handle('tirtc-example:recording-stop', () =>
    requireApplication().session.stopRecording());
  ipcMain.handle('tirtc-example:snapshot', () =>
    requireApplication().session.takeSnapshot());
  ipcMain.handle('tirtc-example:save-recent', async (_event, kind: 'recording' | 'snapshot') => {
    const session = requireApplication().session;
    const source = session.recentPath(kind);
    if (!source) throw new Error(`no recent ${kind} is available`);
    await session.saveRecent(kind, downloadsDestination(source));
  });
  ipcMain.handle('tirtc-example:reveal-recent', (_event, kind: 'recording' | 'snapshot') => {
    const file = requireApplication().session.recentPath(kind);
    if (!file) throw new Error(`no recent ${kind} is available`);
    shell.showItemInFolder(file);
  });
  ipcMain.handle('tirtc-example:audio-muted', (_event, muted: boolean) =>
    requireApplication().session.setAudioMuted(muted));
  ipcMain.handle('tirtc-example:local-audio-running', (_event, running: boolean) =>
    requireApplication().session.setLocalAudioRunning(running));
  ipcMain.handle('tirtc-example:logs-upload', () =>
    requireApplication().session.uploadLogs());
  ipcMain.handle('tirtc-example:leave', () =>
    requireApplication().session.leave());
  ipcMain.handle('tirtc-example:ti-cloud-storage-configure', async (
    _event,
    config: TiCloudStorageExampleConfig,
  ) => {
    const current = requireApplication();
    await current.session.leave();
    await current.tiCloudStorageSession.configure(resolveTiCloudStorageToken(config));
  });
  ipcMain.handle('tirtc-example:ti-cloud-storage-query', (_event, startTimeMs: number, endTimeMs: number) =>
    requireApplication().tiCloudStorageSession.query(startTimeMs, endTimeMs));
  ipcMain.handle('tirtc-example:ti-cloud-storage-query-days',
    (_event, startDate: string, endDate: string, timeZoneId: string) =>
      requireApplication().tiCloudStorageSession.queryDays(startDate, endDate, timeZoneId));
  ipcMain.handle('tirtc-example:ti-cloud-storage-play', (_event, index: number) =>
    requireApplication().tiCloudStorageSession.play(index));
  ipcMain.handle('tirtc-example:ti-cloud-storage-video-bounds', (_event, bounds: Rectangle) =>
    requireApplication().tiCloudStorageSession.setVideoBounds(bounds));
  ipcMain.handle('tirtc-example:ti-cloud-storage-pause', () =>
    requireApplication().tiCloudStorageSession.pause());
  ipcMain.handle('tirtc-example:ti-cloud-storage-resume', () =>
    requireApplication().tiCloudStorageSession.resume());
  ipcMain.handle('tirtc-example:ti-cloud-storage-seek', (_event, value: number) =>
    requireApplication().tiCloudStorageSession.seek(value));
  ipcMain.handle('tirtc-example:ti-cloud-storage-speed', (_event, value: TiCloudStorageReplaySpeed) =>
    requireApplication().tiCloudStorageSession.setSpeed(value));
  ipcMain.handle('tirtc-example:ti-cloud-storage-muted', (_event, value: boolean) =>
    requireApplication().tiCloudStorageSession.setMuted(value));
  ipcMain.handle('tirtc-example:ti-cloud-storage-recording-start', () =>
    requireApplication().tiCloudStorageSession.startRecording());
  ipcMain.handle('tirtc-example:ti-cloud-storage-recording-stop', () =>
    requireApplication().tiCloudStorageSession.stopRecording());
  ipcMain.handle('tirtc-example:ti-cloud-storage-snapshot', () =>
    requireApplication().tiCloudStorageSession.takeSnapshot());
  ipcMain.handle('tirtc-example:ti-cloud-storage-export', (_event, index: number) =>
    requireApplication().tiCloudStorageSession.startExport(index));
  ipcMain.handle('tirtc-example:ti-cloud-storage-save-recent', async (
    _event,
    kind: 'recording' | 'snapshot',
  ) => {
    const session = requireApplication().tiCloudStorageSession;
    const source = session.recentPath(kind);
    if (!source) throw new Error(`no recent ${kind} is available`);
    await session.saveRecent(kind, downloadsDestination(source));
  });
  ipcMain.handle('tirtc-example:ti-cloud-storage-leave', () =>
    requireApplication().tiCloudStorageSession.leave());
  ipcMain.handle('tirtc-example:ti-cloud-storage-logs-upload', () =>
    requireApplication().tiCloudStorageSession.uploadLogs());
}

function beginCleanup(application: ExampleApplication): Promise<void> {
  if (activeApplication === application) activeApplication = null;
  cleanupPromise ??= cleanupSessions([application.session, application.tiCloudStorageSession])
    .then(() => { credentialCache.clear(); })
    .finally(() => { cleanupPromise = null; });
  return cleanupPromise;
}

export async function startExampleApplication(): Promise<ExampleApplication> {
  if (activeApplication || cleanupPromise) throw new Error('Electron Example is already active');
  await app.whenReady();
  installIpc();
  const workArea = screen.getPrimaryDisplay().workAreaSize;
  const height = Math.round(Math.min(workArea.height * 0.82, 900));
  const width = Math.round(height / (19.5 / 9));
  const window = new BrowserWindow({
    width,
    height,
    minWidth: width,
    minHeight: height,
    maxWidth: width,
    maxHeight: height,
    resizable: false,
    maximizable: false,
    backgroundColor: '#FFF8E8',
    title: 'Ti RTC',
    webPreferences: {
      contextIsolation: true,
      sandbox: true,
      nodeIntegration: false,
      preload: path.join(__dirname, 'preload.js'),
    },
  });
  const application: ExampleApplication = {
    window,
    session: new ExampleSession(window),
    tiCloudStorageSession: new TiCloudStorageExampleSession(window),
  };
  activeApplication = application;
  window.on('closed', () => {
    void beginCleanup(application).catch((error) =>
      console.error('Electron Example cleanup failed after bounded retries', error));
  });
  await window.loadFile(path.join(__dirname, 'renderer/index.html'));
  return application;
}

app.on('window-all-closed', () => app.quit());
app.on('before-quit', (event) => {
  if (quittingAfterCleanup || (!activeApplication && !cleanupPromise)) return;
  event.preventDefault();
  const pending = activeApplication ? beginCleanup(activeApplication) : cleanupPromise!;
  finishQuit(pending, () => {
    quittingAfterCleanup = true;
    app.quit();
  }, (error) => {
    console.error('Electron Example cleanup failed after bounded retries', error);
    app.exit(1);
  });
});
