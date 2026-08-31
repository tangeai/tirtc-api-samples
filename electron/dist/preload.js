"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const electron_1 = require("electron");
const api = Object.freeze({
    configure: (config) => electron_1.ipcRenderer.invoke('tirtc-example:configure', config),
    setVideoBounds: (bounds) => electron_1.ipcRenderer.invoke('tirtc-example:video-bounds', bounds),
    sendMessage: (message) => electron_1.ipcRenderer.invoke('tirtc-example:message', message),
    sendCommand: (commandId, message) => electron_1.ipcRenderer.invoke('tirtc-example:command', commandId, message),
    startRecording: () => electron_1.ipcRenderer.invoke('tirtc-example:recording-start'),
    stopRecording: () => electron_1.ipcRenderer.invoke('tirtc-example:recording-stop'),
    takeSnapshot: () => electron_1.ipcRenderer.invoke('tirtc-example:snapshot'),
    saveRecent: (kind) => electron_1.ipcRenderer.invoke('tirtc-example:save-recent', kind),
    revealRecent: (kind) => electron_1.ipcRenderer.invoke('tirtc-example:reveal-recent', kind),
    setAudioMuted: (muted) => electron_1.ipcRenderer.invoke('tirtc-example:audio-muted', muted),
    setLocalAudioRunning: (running) => electron_1.ipcRenderer.invoke('tirtc-example:local-audio-running', running),
    uploadLogs: () => electron_1.ipcRenderer.invoke('tirtc-example:logs-upload'),
    leave: () => electron_1.ipcRenderer.invoke('tirtc-example:leave'),
    onState(listener) {
        const callback = (_event, state) => listener(state);
        electron_1.ipcRenderer.on('tirtc-example:state', callback);
        return () => electron_1.ipcRenderer.removeListener('tirtc-example:state', callback);
    },
    tiCloudStorageConfigure: (config) => electron_1.ipcRenderer.invoke('tirtc-example:ti-cloud-storage-configure', config),
    tiCloudStorageQuery: (startTimeMs, endTimeMs) => electron_1.ipcRenderer.invoke('tirtc-example:ti-cloud-storage-query', startTimeMs, endTimeMs),
    tiCloudStorageQueryDays: (startDate, endDate, timeZoneId) => electron_1.ipcRenderer.invoke('tirtc-example:ti-cloud-storage-query-days', startDate, endDate, timeZoneId),
    tiCloudStoragePlayRange: (index) => electron_1.ipcRenderer.invoke('tirtc-example:ti-cloud-storage-play', index),
    tiCloudStorageSetVideoBounds: (bounds) => electron_1.ipcRenderer.invoke('tirtc-example:ti-cloud-storage-video-bounds', bounds),
    tiCloudStoragePause: () => electron_1.ipcRenderer.invoke('tirtc-example:ti-cloud-storage-pause'),
    tiCloudStorageResume: () => electron_1.ipcRenderer.invoke('tirtc-example:ti-cloud-storage-resume'),
    tiCloudStorageSeek: (timeMs) => electron_1.ipcRenderer.invoke('tirtc-example:ti-cloud-storage-seek', timeMs),
    tiCloudStorageSetSpeed: (speed) => electron_1.ipcRenderer.invoke('tirtc-example:ti-cloud-storage-speed', speed),
    tiCloudStorageSetMuted: (muted) => electron_1.ipcRenderer.invoke('tirtc-example:ti-cloud-storage-muted', muted),
    tiCloudStorageStartRecording: () => electron_1.ipcRenderer.invoke('tirtc-example:ti-cloud-storage-recording-start'),
    tiCloudStorageStopRecording: () => electron_1.ipcRenderer.invoke('tirtc-example:ti-cloud-storage-recording-stop'),
    tiCloudStorageTakeSnapshot: () => electron_1.ipcRenderer.invoke('tirtc-example:ti-cloud-storage-snapshot'),
    tiCloudStorageStartExport: (index) => electron_1.ipcRenderer.invoke('tirtc-example:ti-cloud-storage-export', index),
    tiCloudStorageSaveRecent: (kind) => electron_1.ipcRenderer.invoke('tirtc-example:ti-cloud-storage-save-recent', kind),
    tiCloudStorageUploadLogs: () => electron_1.ipcRenderer.invoke('tirtc-example:ti-cloud-storage-logs-upload'),
    tiCloudStorageLeave: () => electron_1.ipcRenderer.invoke('tirtc-example:ti-cloud-storage-leave'),
    tiCloudStorageOnState(listener) {
        const callback = (_event, state) => listener(state);
        electron_1.ipcRenderer.on('tirtc-example:ti-cloud-storage-state', callback);
        return () => electron_1.ipcRenderer.removeListener('tirtc-example:ti-cloud-storage-state', callback);
    },
});
electron_1.contextBridge.exposeInMainWorld('tirtcExample', api);
