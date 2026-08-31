"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.startExampleApplication = startExampleApplication;
const node_fs_1 = __importDefault(require("node:fs"));
const node_path_1 = __importDefault(require("node:path"));
const electron_1 = require("electron");
const session_1 = require("./session");
const storage_session_1 = require("./storage_session");
const application_cleanup_1 = require("./application_cleanup");
let activeApplication = null;
let cleanupPromise = null;
let ipcInstalled = false;
let quittingAfterCleanup = false;
const credentialCache = new Map();
function mainProcessCredential(name, format) {
    const cached = credentialCache.get(name);
    if (cached)
        return cached;
    const descriptorName = `${name}_FD`;
    const descriptorText = process.env[descriptorName];
    const descriptor = descriptorText === undefined ? null : Number(descriptorText);
    let supplied = process.env[name] ?? '';
    try {
        if (descriptor !== null) {
            if (!Number.isSafeInteger(descriptor) || descriptor < 3) {
                throw new TypeError(`${descriptorName} must identify an inherited credential file descriptor`);
            }
            supplied = node_fs_1.default.readFileSync(descriptor, 'utf8');
        }
    }
    finally {
        delete process.env[name];
        delete process.env[descriptorName];
        if (descriptor !== null && Number.isSafeInteger(descriptor) && descriptor >= 3) {
            try {
                node_fs_1.default.closeSync(descriptor);
            }
            catch { }
        }
    }
    const token = supplied.trim();
    if (!token)
        return null;
    if (format === 'rtc-v1' && !token.startsWith('v1.')) {
        throw new TypeError(`${name} must contain a v1 Token`);
    }
    credentialCache.set(name, token);
    return token;
}
async function resolveExampleToken(config) {
    const supplied = mainProcessCredential('TIRTC_EXAMPLE_RTC_TOKEN', 'rtc-v1');
    if (supplied)
        return { ...config, token: supplied };
    let origin;
    try {
        origin = new URL(config.tokenServerAddress?.trim() ?? '');
    }
    catch {
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
            headers: { 'content-type': 'application/json' },
            body: JSON.stringify({ remote_id: config.remoteId }),
            signal: controller.signal,
        });
        if (!response.ok || !response.body)
            throw new Error('token server request failed');
        const reader = response.body.getReader();
        const chunks = [];
        let size = 0;
        while (true) {
            const { done, value } = await reader.read();
            if (done)
                break;
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
        const parsed = JSON.parse(new TextDecoder().decode(body));
        if (typeof parsed.token !== 'string' || !parsed.token.trim().startsWith('v1.')) {
            throw new Error('token server returned an invalid token');
        }
        return { ...config, token: parsed.token.trim() };
    }
    catch (error) {
        throw new Error('unable to obtain a token from the token server', { cause: error });
    }
    finally {
        clearTimeout(timer);
    }
}
function resolveTiCloudStorageToken(config) {
    const token = mainProcessCredential('TIRTC_EXAMPLE_TI_CLOUD_STORAGE_TOKEN', 'opaque');
    if (!token)
        throw new Error('Ti Cloud Storage Token is unavailable in the Main process');
    return { ...config, token };
}
async function requestMediaPermissions() {
    if (process.platform !== 'darwin')
        return true;
    return electron_1.systemPreferences.askForMediaAccess('microphone');
}
function requireApplication() {
    if (!activeApplication)
        throw new Error('Electron Example is unavailable');
    return activeApplication;
}
function downloadsDestination(source) {
    const parsed = node_path_1.default.parse(source);
    const directory = electron_1.app.getPath('downloads');
    for (let suffix = 0; suffix < 10_000; suffix += 1) {
        const name = suffix === 0 ? parsed.base : `${parsed.name}-${suffix}${parsed.ext}`;
        const candidate = node_path_1.default.join(directory, name);
        if (!node_fs_1.default.existsSync(candidate))
            return candidate;
    }
    throw new Error('unable to choose a unique Downloads file name');
}
function installIpc() {
    if (ipcInstalled)
        return;
    ipcInstalled = true;
    electron_1.ipcMain.handle('tirtc-example:configure', async (_event, config) => {
        if (!(await requestMediaPermissions()))
            throw new Error('microphone permission denied');
        const current = requireApplication();
        await current.tiCloudStorageSession.leave();
        await current.session.configure(await resolveExampleToken(config));
    });
    electron_1.ipcMain.handle('tirtc-example:video-bounds', (_event, bounds) => requireApplication().session.setVideoBounds(bounds));
    electron_1.ipcMain.handle('tirtc-example:message', (_event, message) => requireApplication().session.sendMessage(message));
    electron_1.ipcMain.handle('tirtc-example:command', (_event, commandId, message) => requireApplication().session.sendCommand(commandId, message));
    electron_1.ipcMain.handle('tirtc-example:recording-start', () => requireApplication().session.startRecording());
    electron_1.ipcMain.handle('tirtc-example:recording-stop', () => requireApplication().session.stopRecording());
    electron_1.ipcMain.handle('tirtc-example:snapshot', () => requireApplication().session.takeSnapshot());
    electron_1.ipcMain.handle('tirtc-example:save-recent', async (_event, kind) => {
        const session = requireApplication().session;
        const source = session.recentPath(kind);
        if (!source)
            throw new Error(`no recent ${kind} is available`);
        await session.saveRecent(kind, downloadsDestination(source));
    });
    electron_1.ipcMain.handle('tirtc-example:reveal-recent', (_event, kind) => {
        const file = requireApplication().session.recentPath(kind);
        if (!file)
            throw new Error(`no recent ${kind} is available`);
        electron_1.shell.showItemInFolder(file);
    });
    electron_1.ipcMain.handle('tirtc-example:audio-muted', (_event, muted) => requireApplication().session.setAudioMuted(muted));
    electron_1.ipcMain.handle('tirtc-example:local-audio-running', (_event, running) => requireApplication().session.setLocalAudioRunning(running));
    electron_1.ipcMain.handle('tirtc-example:logs-upload', () => requireApplication().session.uploadLogs());
    electron_1.ipcMain.handle('tirtc-example:leave', () => requireApplication().session.leave());
    electron_1.ipcMain.handle('tirtc-example:ti-cloud-storage-configure', async (_event, config) => {
        const current = requireApplication();
        await current.session.leave();
        await current.tiCloudStorageSession.configure(resolveTiCloudStorageToken(config));
    });
    electron_1.ipcMain.handle('tirtc-example:ti-cloud-storage-query', (_event, startTimeMs, endTimeMs) => requireApplication().tiCloudStorageSession.query(startTimeMs, endTimeMs));
    electron_1.ipcMain.handle('tirtc-example:ti-cloud-storage-query-days', (_event, startDate, endDate, timeZoneId) => requireApplication().tiCloudStorageSession.queryDays(startDate, endDate, timeZoneId));
    electron_1.ipcMain.handle('tirtc-example:ti-cloud-storage-play', (_event, index) => requireApplication().tiCloudStorageSession.play(index));
    electron_1.ipcMain.handle('tirtc-example:ti-cloud-storage-video-bounds', (_event, bounds) => requireApplication().tiCloudStorageSession.setVideoBounds(bounds));
    electron_1.ipcMain.handle('tirtc-example:ti-cloud-storage-pause', () => requireApplication().tiCloudStorageSession.pause());
    electron_1.ipcMain.handle('tirtc-example:ti-cloud-storage-resume', () => requireApplication().tiCloudStorageSession.resume());
    electron_1.ipcMain.handle('tirtc-example:ti-cloud-storage-seek', (_event, value) => requireApplication().tiCloudStorageSession.seek(value));
    electron_1.ipcMain.handle('tirtc-example:ti-cloud-storage-speed', (_event, value) => requireApplication().tiCloudStorageSession.setSpeed(value));
    electron_1.ipcMain.handle('tirtc-example:ti-cloud-storage-muted', (_event, value) => requireApplication().tiCloudStorageSession.setMuted(value));
    electron_1.ipcMain.handle('tirtc-example:ti-cloud-storage-recording-start', () => requireApplication().tiCloudStorageSession.startRecording());
    electron_1.ipcMain.handle('tirtc-example:ti-cloud-storage-recording-stop', () => requireApplication().tiCloudStorageSession.stopRecording());
    electron_1.ipcMain.handle('tirtc-example:ti-cloud-storage-snapshot', () => requireApplication().tiCloudStorageSession.takeSnapshot());
    electron_1.ipcMain.handle('tirtc-example:ti-cloud-storage-export', (_event, index) => requireApplication().tiCloudStorageSession.startExport(index));
    electron_1.ipcMain.handle('tirtc-example:ti-cloud-storage-save-recent', async (_event, kind) => {
        const session = requireApplication().tiCloudStorageSession;
        const source = session.recentPath(kind);
        if (!source)
            throw new Error(`no recent ${kind} is available`);
        await session.saveRecent(kind, downloadsDestination(source));
    });
    electron_1.ipcMain.handle('tirtc-example:ti-cloud-storage-leave', () => requireApplication().tiCloudStorageSession.leave());
    electron_1.ipcMain.handle('tirtc-example:ti-cloud-storage-logs-upload', () => requireApplication().tiCloudStorageSession.uploadLogs());
}
function beginCleanup(application) {
    if (activeApplication === application)
        activeApplication = null;
    cleanupPromise ??= (0, application_cleanup_1.cleanupSessions)([application.session, application.tiCloudStorageSession])
        .then(() => { credentialCache.clear(); })
        .finally(() => { cleanupPromise = null; });
    return cleanupPromise;
}
async function startExampleApplication() {
    if (activeApplication || cleanupPromise)
        throw new Error('Electron Example is already active');
    await electron_1.app.whenReady();
    installIpc();
    const workArea = electron_1.screen.getPrimaryDisplay().workAreaSize;
    const height = Math.round(Math.min(workArea.height * 0.82, 900));
    const width = Math.round(height / (19.5 / 9));
    const window = new electron_1.BrowserWindow({
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
            preload: node_path_1.default.join(__dirname, 'preload.js'),
        },
    });
    const application = {
        window,
        session: new session_1.ExampleSession(window),
        tiCloudStorageSession: new storage_session_1.TiCloudStorageExampleSession(window),
    };
    activeApplication = application;
    window.on('closed', () => {
        void beginCleanup(application).catch((error) => console.error('Electron Example cleanup failed after bounded retries', error));
    });
    await window.loadFile(node_path_1.default.join(__dirname, 'renderer/index.html'));
    return application;
}
electron_1.app.on('window-all-closed', () => electron_1.app.quit());
electron_1.app.on('before-quit', (event) => {
    if (quittingAfterCleanup || (!activeApplication && !cleanupPromise))
        return;
    event.preventDefault();
    const pending = activeApplication ? beginCleanup(activeApplication) : cleanupPromise;
    (0, application_cleanup_1.finishQuit)(pending, () => {
        quittingAfterCleanup = true;
        electron_1.app.quit();
    }, (error) => {
        console.error('Electron Example cleanup failed after bounded retries', error);
        electron_1.app.exit(1);
    });
});
