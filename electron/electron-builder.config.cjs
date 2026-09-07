'use strict';

const supportedTuples = new Set(['darwin-arm64', 'darwin-x64', 'win32-x64']);
const hostTuple = `${process.platform}-${process.arch}`;
const tuple = process.env.TIRTC_ELECTRON_TARGET_TUPLE || hostTuple;

if (!supportedTuples.has(tuple)) {
  throw new Error(`unsupported Electron target tuple: ${tuple}`);
}

const targetPlatform = tuple.startsWith('darwin-') ? 'darwin' : 'win32';
const targetArch = tuple.endsWith('-arm64') ? 'arm64' : 'x64';
const internalAutomation = require('./package.json').main === 'dist/internal/automation.js';
const requestedPlatform = process.env.npm_config_platform;
const requestedArch = process.env.npm_config_arch;
if (requestedPlatform && requestedPlatform !== targetPlatform) {
  throw new Error(`target platform ${requestedPlatform} does not match ${tuple}`);
}
if (requestedArch && requestedArch !== targetArch) {
  throw new Error(`target arch ${requestedArch} does not match ${tuple}`);
}

module.exports = {
  appId: 'com.tangeai.tirtc.example',
  productName: 'TiRTC Example',
  asar: true,
  npmRebuild: false,
  directories: {output: 'release'},
  files: [
    'dist/**/*',
    ...internalAutomation ? [] : ['!dist/internal/**/*'],
    'package.json',
    'node_modules/tirtc-electron/package.json',
    'node_modules/tirtc-electron/identity.json',
    'node_modules/tirtc-electron/README.md',
    'node_modules/tirtc-electron/api/**/*',
    'node_modules/tirtc-electron/dist/**/*',
    'node_modules/tirtc-electron/licenses/**/*',
    ...[...supportedTuples]
      .filter((candidate) => candidate !== tuple)
      .map((candidate) => `!node_modules/tirtc-electron/native/${candidate}{,/**/*}`),
    `node_modules/tirtc-electron/native/${tuple}/**/*`,
  ],
  asarUnpack: [`node_modules/tirtc-electron/native/${tuple}/**/*`],
  mac: {
    target: [{target: 'dir', arch: [targetArch]}],
    extendInfo: {NSMicrophoneUsageDescription: 'TiRTC uses the microphone for RTC audio.'},
  },
  win: {target: [{target: 'dir', arch: [targetArch]}]},
};
