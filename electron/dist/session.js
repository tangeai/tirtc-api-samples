"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.ExampleSession = void 0;
const node_fs_1 = __importDefault(require("node:fs"));
const node_path_1 = __importDefault(require("node:path"));
const tirtc_electron_1 = require("tirtc-electron");
const operation_barrier_1 = require("./operation_barrier");
const AUDIO_STREAM_ID = 10;
const VIDEO_STREAM_ID = 11;
const LOCAL_AUDIO_STREAM_ID = 14;
const DEFAULT_SETTINGS = {
    videoDecoderPreference: 'auto',
    outputBufferPolicy: 'automatic',
    consoleLogEnabled: false,
    localAudioCodec: 'g711a',
    localAudioSampleRateHz: 16000,
    localAudioStreamId: LOCAL_AUDIO_STREAM_ID,
    localAudioAecEnabled: false,
    localAudioAgcLevel: 'disabled',
    localAudioAnsLevel: 'disabled',
};
function failureOf(reason) {
    if (reason instanceof tirtc_electron_1.TiRtcError)
        return { code: reason.code, message: reason.message };
    return {
        code: 'invalid-input',
        message: reason instanceof Error ? reason.message : String(reason),
    };
}
async function retryWhileInUse(operation) {
    for (let attempt = 0; attempt < 250; attempt += 1) {
        try {
            operation();
            return;
        }
        catch (reason) {
            if (!(reason instanceof tirtc_electron_1.TiRtcError) || reason.code !== 'in-use')
                throw reason;
        }
        await new Promise((resolve) => setTimeout(resolve, 20));
    }
    throw new Error('resource remained in use during teardown');
}
const OPERATION_DRAIN_TIMEOUT_MS = 5_000;
class ExampleSession {
    #window;
    #operationDrainTimeoutMs;
    #connection = null;
    #audioInput = null;
    #audioOutput = null;
    #videoOutput = null;
    #remoteView = null;
    #acceptVideoBounds = false;
    #metricsTimer = null;
    #recordingTask = null;
    #recentRecording = null;
    #recentSnapshot = null;
    #persistedDestinations = new WeakMap();
    #retiredMedia = new Set();
    #acceptedOperations = new operation_barrier_1.OperationBarrier();
    #quiescing = true;
    #leavePromise = null;
    #initialized = false;
    #audioStreamId = AUDIO_STREAM_ID;
    #videoStreamId = VIDEO_STREAM_ID;
    #state = {
        phase: 'configuration',
        message: '',
        messageDirection: null,
        messageCommandId: null,
        connectionState: 'idle',
        recording: false,
        audioState: 'idle',
        audioMuted: false,
        localAudioRunning: false,
        recentRecording: false,
        recentSnapshot: false,
        lastSavedFile: null,
        uploadingLogs: false,
        lastError: null,
        metrics: null,
    };
    constructor(window, operationDrainTimeoutMs = OPERATION_DRAIN_TIMEOUT_MS) {
        this.#window = window;
        this.#operationDrainTimeoutMs = operationDrainTimeoutMs;
    }
    get state() { return this.#state; }
    async configure(config) {
        await this.leave();
        this.#quiescing = false;
        try {
            const audioStreamId = config.audioStreamId ?? AUDIO_STREAM_ID;
            const videoStreamId = config.videoStreamId ?? VIDEO_STREAM_ID;
            if (!Number.isSafeInteger(audioStreamId) || !Number.isSafeInteger(videoStreamId) ||
                audioStreamId < 0 || audioStreamId > 15 || videoStreamId < 0 || videoStreamId > 15 ||
                audioStreamId === videoStreamId) {
                throw new TypeError('audio and video Stream IDs must be different integers from 0 through 15');
            }
            const settings = config.settings ?? DEFAULT_SETTINGS;
            if (!Number.isSafeInteger(settings.localAudioStreamId) || settings.localAudioStreamId < 0 ||
                settings.localAudioStreamId > 15) {
                throw new TypeError('local audio Stream ID must be an integer from 0 through 15');
            }
            this.#audioStreamId = audioStreamId;
            this.#videoStreamId = videoStreamId;
            tirtc_electron_1.TiRtc.init({
                appId: config.appId,
                endpoint: config.endpoint,
                consoleLogEnabled: settings.consoleLogEnabled,
            });
            this.#initialized = true;
            this.#connection = new tirtc_electron_1.TiRtcConn();
            this.#audioInput = new tirtc_electron_1.TiRtcAudioInput();
            this.#audioOutput = new tirtc_electron_1.TiRtcAudioOutput();
            this.#videoOutput = new tirtc_electron_1.TiRtcVideoOutput();
            this.#connection.onStateChanged = (state, error) => {
                this.update({
                    connectionState: state,
                    phase: state === 'connected' ? 'playing' : this.#state.phase,
                });
                if (state === 'connected') {
                    try {
                        this.#connection.subscribeAudio(this.#audioStreamId);
                        this.#connection.subscribeVideo(this.#videoStreamId);
                    }
                    catch (reason) {
                        this.captureFailure(reason);
                    }
                }
                if (error !== null)
                    this.captureFailure(error);
            };
            this.#connection.onStreamMessage = (_streamId, _timestampMs, data) => {
                this.update({ message: new TextDecoder().decode(data), messageDirection: 'received', messageCommandId: null });
            };
            this.#connection.onCommand = (commandId, data) => {
                this.update({ message: new TextDecoder().decode(data), messageDirection: 'received', messageCommandId: commandId });
            };
            this.#audioOutput.onStateChanged = (state) => this.update({ audioState: state });
            this.#audioInput.onStateChanged = (state) => this.update({ localAudioRunning: state === 'running' });
            this.#audioInput.onError = (error) => this.captureFailure(error);
            this.#audioOutput.onError = (error) => this.captureFailure(error);
            this.#videoOutput.onError = (error) => this.captureFailure(error);
            this.#videoOutput.onStateChanged = () => this.publish();
            this.#videoOutput.onRenderSizeChanged = () => this.publish();
            this.#audioInput.setOptions({
                codec: settings.localAudioCodec,
                sampleRateHz: settings.localAudioCodec === 'amr' ? 8000 : settings.localAudioSampleRateHz,
                channels: 1,
                aecMode: settings.localAudioAecEnabled ? 'enabled' : 'disabled',
                agcLevel: settings.localAudioAgcLevel,
                ansLevel: settings.localAudioAnsLevel,
            });
            this.#audioOutput.setOptions({ bufferStrategy: settings.outputBufferPolicy });
            this.#videoOutput.setOptions({
                decoderPreference: settings.videoDecoderPreference,
                bufferStrategy: settings.outputBufferPolicy,
            });
            this.#audioInput.attach(this.#connection, settings.localAudioStreamId);
            this.#audioOutput.attach(this.#connection, this.#audioStreamId);
            this.#videoOutput.attach(this.#connection, this.#videoStreamId);
            this.#acceptVideoBounds = true;
            this.#metricsTimer = setInterval(() => this.publishMetrics(), 1000);
            this.update({ phase: 'connecting', lastError: null, message: '', messageDirection: null, messageCommandId: null });
            this.#connection.connect({ remoteId: config.remoteId, token: config.token });
        }
        catch (reason) {
            let failure = reason;
            try {
                await this.leave();
            }
            catch (cleanupError) {
                failure = cleanupError;
            }
            this.captureFailure(failure);
            throw failure;
        }
    }
    setVideoBounds(bounds) {
        this.ensureAccepting();
        if (!this.#acceptVideoBounds || this.#videoOutput === null)
            return;
        if (this.#remoteView === null) {
            this.#remoteView = new tirtc_electron_1.TiVideoView(this.#window, bounds);
            this.#videoOutput.mount(this.#remoteView);
        }
        else {
            this.#remoteView.setBounds(bounds);
        }
    }
    sendMessage(message) {
        this.ensureAccepting();
        if (this.#connection === null)
            throw new Error('RTC connection is unavailable');
        this.#connection.sendStreamMessage({
            streamId: 0,
            timestampMs: Date.now() >>> 0,
            data: new TextEncoder().encode(message),
        });
    }
    sendCommand(commandId, message) {
        this.ensureAccepting();
        if (this.#connection === null)
            throw new Error('RTC connection is unavailable');
        this.#connection.sendCommand(commandId, new TextEncoder().encode(message));
        this.update({ message, messageDirection: 'sent', messageCommandId: commandId });
    }
    startRecording() {
        this.ensureAccepting();
        if (this.#connection === null || this.#recordingTask !== null) {
            throw new Error('recording is unavailable');
        }
        this.#recordingTask = this.#connection.startRecording({
            videoStreamId: this.#videoStreamId,
            audioStreamId: this.#audioStreamId,
        });
        this.update({ recording: true });
    }
    stopRecording() {
        this.ensureAccepting();
        return this.track(this.stopRecordingOwned(), 'recording', 'connection', 'core');
    }
    async stopRecordingOwned() {
        if (this.#recordingTask === null)
            throw new Error('recording has not started');
        const task = this.#recordingTask;
        this.#recordingTask = null;
        let stopped = false;
        try {
            const file = await task.stop();
            stopped = true;
            await this.replaceRecent('recording', file);
            this.update({ recording: false });
        }
        catch (reason) {
            if (!stopped && this.#recordingTask === null)
                this.#recordingTask = task;
            this.update({ recording: !stopped });
            this.captureFailure(reason);
            throw reason;
        }
    }
    takeSnapshot() {
        this.ensureAccepting();
        return this.track(this.takeSnapshotOwned(), 'videoOutput', 'connection', 'core');
    }
    async takeSnapshotOwned() {
        if (this.#videoOutput === null)
            throw new Error('video output is unavailable');
        try {
            await this.replaceRecent('snapshot', await this.#videoOutput.takeSnapshot());
        }
        catch (reason) {
            this.captureFailure(reason);
            throw reason;
        }
    }
    saveRecent(kind, destinationPath) {
        this.ensureAccepting();
        return this.track(this.saveRecentOwned(kind, destinationPath), 'file', 'core');
    }
    async saveRecentOwned(kind, destinationPath) {
        const file = kind === 'recording' ? this.#recentRecording : this.#recentSnapshot;
        if (file === null)
            throw new Error('there is no recent media file');
        if (!node_path_1.default.isAbsolute(destinationPath) || node_path_1.default.resolve(destinationPath) === node_path_1.default.resolve(file.path)) {
            throw new TypeError('destinationPath must be a different absolute path');
        }
        let persisted = this.#persistedDestinations.get(file);
        if (persisted === undefined) {
            await node_fs_1.default.promises.copyFile(file.path, destinationPath, node_fs_1.default.constants.COPYFILE_EXCL);
            persisted = destinationPath;
            this.#persistedDestinations.set(file, persisted);
        }
        await this.deleteRecent(file);
        if (kind === 'recording') {
            this.#recentRecording = null;
            this.update({ recentRecording: false, lastSavedFile: node_path_1.default.basename(persisted) });
        }
        else {
            this.#recentSnapshot = null;
            this.update({ recentSnapshot: false, lastSavedFile: node_path_1.default.basename(persisted) });
        }
    }
    recentPath(kind) {
        const file = kind === 'recording' ? this.#recentRecording : this.#recentSnapshot;
        return file === null ? null : this.#persistedDestinations.get(file) ?? file.path;
    }
    setAudioMuted(muted) {
        this.ensureAccepting();
        if (this.#audioOutput === null)
            throw new Error('audio output is unavailable');
        this.#audioOutput.setVolume(muted ? 0 : 100);
        this.update({ audioMuted: muted });
    }
    setLocalAudioRunning(running) {
        this.ensureAccepting();
        if (this.#audioInput === null)
            throw new Error('audio input is unavailable');
        if (running)
            this.#audioInput.start();
        else
            this.#audioInput.stop();
        this.update({ localAudioRunning: running });
    }
    uploadLogs() {
        this.ensureAccepting();
        return this.track(this.uploadLogsOwned(), 'core');
    }
    async uploadLogsOwned() {
        this.update({ uploadingLogs: true });
        try {
            const logId = await tirtc_electron_1.TiRtcLogging.upload();
            this.update({ uploadingLogs: false, message: `Log ID: ${logId}`,
                messageDirection: null, messageCommandId: null, lastError: null });
        }
        catch (reason) {
            this.update({ uploadingLogs: false });
            this.captureFailure(reason);
            throw reason;
        }
    }
    leave() {
        if (this.#leavePromise === null) {
            const operation = this.leaveOwned();
            this.#leavePromise = operation.finally(() => { this.#leavePromise = null; });
        }
        return this.#leavePromise;
    }
    async leaveOwned() {
        this.#quiescing = true;
        this.#acceptVideoBounds = false;
        if (this.#metricsTimer !== null) {
            clearInterval(this.#metricsTimer);
            this.#metricsTimer = null;
        }
        let firstError = null;
        const attempt = async (operation) => {
            try {
                await operation();
                return true;
            }
            catch (reason) {
                firstError ??= reason;
                return false;
            }
        };
        if (!await this.drainAcceptedOperations()) {
            firstError ??= new Error('RTC accepted operations did not settle during teardown');
        }
        if (this.#recordingTask !== null && !this.ownerBusy('recording')) {
            await attempt(() => this.track(this.stopRecordingOwned(), 'recording', 'connection', 'core'));
        }
        if (!await this.drainAcceptedOperations()) {
            firstError ??= new Error('RTC teardown operations did not settle');
        }
        if (!this.ownerBusy('file') && this.#recentRecording !== null &&
            await attempt(() => this.deleteRecent(this.#recentRecording))) {
            this.#recentRecording = null;
        }
        if (!this.ownerBusy('file') && this.#recentSnapshot !== null &&
            await attempt(() => this.deleteRecent(this.#recentSnapshot))) {
            this.#recentSnapshot = null;
        }
        if (!this.ownerBusy('file')) {
            for (const file of [...this.#retiredMedia])
                await attempt(() => this.deleteRecent(file));
        }
        if (this.#audioInput !== null) {
            if (this.#audioInput.state !== 'idle' && this.#audioInput.state !== 'stopped') {
                await attempt(() => retryWhileInUse(() => this.#audioInput.stop()));
            }
            await attempt(() => retryWhileInUse(() => this.#audioInput.detach()));
            if (await attempt(() => retryWhileInUse(() => this.#audioInput.dispose())))
                this.#audioInput = null;
        }
        if (this.#audioOutput !== null) {
            await attempt(() => retryWhileInUse(() => this.#audioOutput.detach()));
            if (await attempt(() => retryWhileInUse(() => this.#audioOutput.dispose())))
                this.#audioOutput = null;
        }
        if (this.#videoOutput !== null && !this.ownerBusy('videoOutput')) {
            await attempt(() => retryWhileInUse(() => this.#videoOutput.detach()));
            await attempt(() => retryWhileInUse(() => this.#videoOutput.unmount()));
        }
        if (!this.ownerBusy('videoOutput') && this.#remoteView !== null &&
            await attempt(() => retryWhileInUse(() => this.#remoteView.dispose())))
            this.#remoteView = null;
        if (!this.ownerBusy('videoOutput') && this.#videoOutput !== null &&
            await attempt(() => retryWhileInUse(() => this.#videoOutput.dispose())))
            this.#videoOutput = null;
        if (this.#connection !== null && !this.ownerBusy('connection') && this.#audioInput === null &&
            this.#audioOutput === null && this.#videoOutput === null && this.#recordingTask === null) {
            await attempt(() => retryWhileInUse(() => this.#connection.disconnect()));
            if (await attempt(() => retryWhileInUse(() => this.#connection.dispose())))
                this.#connection = null;
        }
        if (this.#initialized && this.#connection === null && this.#audioInput === null &&
            this.#audioOutput === null && this.#videoOutput === null && this.#remoteView === null &&
            this.#recordingTask === null && this.#recentRecording === null && this.#recentSnapshot === null &&
            this.#retiredMedia.size === 0 && !this.ownerBusy('core')) {
            if (await attempt(() => retryWhileInUse(() => tirtc_electron_1.TiRtc.shutdown())))
                this.#initialized = false;
        }
        if (this.#initialized && firstError === null) {
            firstError = new Error('RTC session teardown did not reach shutdown');
        }
        this.#state = {
            phase: firstError === null ? 'configuration' : 'failed',
            message: firstError === null ? '' : failureOf(firstError).message,
            messageDirection: null, messageCommandId: null,
            connectionState: 'idle', recording: false,
            audioState: 'idle', audioMuted: false, localAudioRunning: false,
            recentRecording: this.#recentRecording !== null,
            recentSnapshot: this.#recentSnapshot !== null,
            lastSavedFile: null,
            uploadingLogs: false,
            lastError: firstError === null ? null : failureOf(firstError), metrics: null,
        };
        this.publish();
        if (firstError !== null)
            throw firstError;
    }
    async replaceRecent(kind, file) {
        if (kind === 'recording') {
            const previous = this.#recentRecording;
            this.#recentRecording = file;
            this.update({ recentRecording: true, lastSavedFile: null });
            if (previous !== null) {
                try {
                    await this.deleteRecent(previous);
                }
                catch (reason) {
                    this.#retiredMedia.add(previous);
                    throw reason;
                }
            }
        }
        else {
            const previous = this.#recentSnapshot;
            this.#recentSnapshot = file;
            this.update({ recentSnapshot: true, lastSavedFile: null });
            if (previous !== null) {
                try {
                    await this.deleteRecent(previous);
                }
                catch (reason) {
                    this.#retiredMedia.add(previous);
                    throw reason;
                }
            }
        }
    }
    async deleteRecent(file) {
        if (file !== null) {
            await file.delete();
            this.#retiredMedia.delete(file);
        }
    }
    ensureAccepting() {
        if (this.#quiescing)
            throw new Error('RTC session is leaving');
    }
    track(operation, ...owners) {
        return this.#acceptedOperations.track(operation, ...owners);
    }
    async drainAcceptedOperations() {
        return this.#acceptedOperations.drain(this.#operationDrainTimeoutMs);
    }
    ownerBusy(owner) {
        return this.#acceptedOperations.busy(owner);
    }
    publishMetrics() {
        if (this.#connection === null || this.#audioOutput === null || this.#videoOutput === null)
            return;
        try {
            this.update({ metrics: {
                    connection: this.#connection.getMetricsSnapshot(),
                    audio: this.#audioOutput.getMetricsSnapshot(),
                    video: this.#videoOutput.getMetricsSnapshot(),
                } });
        }
        catch { }
    }
    captureFailure(reason) {
        const failure = failureOf(reason);
        this.update({ phase: 'failed', message: failure.message, lastError: failure });
    }
    update(patch) {
        this.#state = { ...this.#state, ...patch };
        this.publish();
    }
    publish() {
        if (!this.#window.isDestroyed())
            this.#window.webContents.send('tirtc-example:state', this.#state);
    }
}
exports.ExampleSession = ExampleSession;
