import {contextBridge, ipcRenderer} from 'electron';
import type {Rectangle} from 'electron';

import type {ExampleApi, ExampleConfig, ExampleState} from './shared/types';

const api: ExampleApi = Object.freeze({
  configure: (config: ExampleConfig) => ipcRenderer.invoke('tirtc-example:configure', config),
  setVideoBounds: (bounds: Rectangle) =>
    ipcRenderer.invoke('tirtc-example:video-bounds', bounds),
  sendMessage: (message: string) => ipcRenderer.invoke('tirtc-example:message', message),
  sendCommand: (commandId: number, message: string) =>
    ipcRenderer.invoke('tirtc-example:command', commandId, message),
  startRecording: () => ipcRenderer.invoke('tirtc-example:recording-start'),
  stopRecording: () => ipcRenderer.invoke('tirtc-example:recording-stop'),
  takeSnapshot: () => ipcRenderer.invoke('tirtc-example:snapshot'),
  saveRecent: (kind) => ipcRenderer.invoke('tirtc-example:save-recent', kind),
  revealRecent: (kind) => ipcRenderer.invoke('tirtc-example:reveal-recent', kind),
  setAudioMuted: (muted) => ipcRenderer.invoke('tirtc-example:audio-muted', muted),
  setLocalAudioRunning: (running) => ipcRenderer.invoke('tirtc-example:local-audio-running', running),
  uploadLogs: () => ipcRenderer.invoke('tirtc-example:logs-upload'),
  leave: () => ipcRenderer.invoke('tirtc-example:leave'),
  onState(listener: (state: ExampleState) => void) {
    const callback = (_event: Electron.IpcRendererEvent, state: ExampleState) => listener(state);
    ipcRenderer.on('tirtc-example:state', callback);
    return () => ipcRenderer.removeListener('tirtc-example:state', callback);
  },
  tiCloudStorageConfigure: (config) => ipcRenderer.invoke('tirtc-example:ti-cloud-storage-configure', config),
  tiCloudStorageQuery: (startTimeMs, endTimeMs) =>
    ipcRenderer.invoke('tirtc-example:ti-cloud-storage-query', startTimeMs, endTimeMs),
  tiCloudStorageQueryDays: (startDate, endDate, timeZoneId) =>
    ipcRenderer.invoke('tirtc-example:ti-cloud-storage-query-days', startDate, endDate, timeZoneId),
  tiCloudStoragePlayRange: (index) => ipcRenderer.invoke('tirtc-example:ti-cloud-storage-play', index),
  tiCloudStorageSetVideoBounds: (bounds) => ipcRenderer.invoke('tirtc-example:ti-cloud-storage-video-bounds', bounds),
  tiCloudStoragePause: () => ipcRenderer.invoke('tirtc-example:ti-cloud-storage-pause'),
  tiCloudStorageResume: () => ipcRenderer.invoke('tirtc-example:ti-cloud-storage-resume'),
  tiCloudStorageSeek: (timeMs) => ipcRenderer.invoke('tirtc-example:ti-cloud-storage-seek', timeMs),
  tiCloudStorageSetSpeed: (speed) => ipcRenderer.invoke('tirtc-example:ti-cloud-storage-speed', speed),
  tiCloudStorageSetMuted: (muted) => ipcRenderer.invoke('tirtc-example:ti-cloud-storage-muted', muted),
  tiCloudStorageStartRecording: () => ipcRenderer.invoke('tirtc-example:ti-cloud-storage-recording-start'),
  tiCloudStorageStopRecording: () => ipcRenderer.invoke('tirtc-example:ti-cloud-storage-recording-stop'),
  tiCloudStorageTakeSnapshot: () => ipcRenderer.invoke('tirtc-example:ti-cloud-storage-snapshot'),
  tiCloudStorageStartExport: (index) => ipcRenderer.invoke('tirtc-example:ti-cloud-storage-export', index),
  tiCloudStorageSaveRecent: (kind) => ipcRenderer.invoke('tirtc-example:ti-cloud-storage-save-recent', kind),
  tiCloudStorageUploadLogs: () => ipcRenderer.invoke('tirtc-example:ti-cloud-storage-logs-upload'),
  tiCloudStorageLeave: () => ipcRenderer.invoke('tirtc-example:ti-cloud-storage-leave'),
  tiCloudStorageOnState(listener) {
    const callback = (_event: Electron.IpcRendererEvent, state: import('./shared/types').TiCloudStorageExampleState) => listener(state);
    ipcRenderer.on('tirtc-example:ti-cloud-storage-state', callback);
    return () => ipcRenderer.removeListener('tirtc-example:ti-cloud-storage-state', callback);
  },
});

contextBridge.exposeInMainWorld('tirtcExample', api);
