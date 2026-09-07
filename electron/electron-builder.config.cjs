'use strict';

const asar = require('@electron/asar');
const fs = require('node:fs');
const path = require('node:path');

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

async function filterNativeTuples(context) {
  const resources = context.electronPlatformName === 'darwin'
    ? path.join(context.appOutDir, `${context.packager.appInfo.productFilename}.app`, 'Contents', 'Resources')
    : path.join(context.appOutDir, 'resources');
  const archive = path.join(resources, 'app.asar');
  const unpacked = `${archive}.unpacked`;
  const stage = path.join(context.appOutDir, '.tirtc-asar-stage');
  const rebuilt = path.join(context.appOutDir, '.tirtc-app.asar');
  fs.rmSync(stage, {recursive: true, force: true});
  fs.rmSync(rebuilt, {force: true});
  fs.rmSync(`${rebuilt}.unpacked`, {recursive: true, force: true});
  asar.extractAll(archive, stage);
  const nativeRoot = path.join(stage, 'node_modules/tirtc-electron/native');
  for (const candidate of supportedTuples) {
    if (candidate !== tuple) fs.rmSync(path.join(nativeRoot, candidate), {recursive: true, force: true});
  }
  await asar.createPackageWithOptions(stage, rebuilt, {
    unpackDir: `node_modules/tirtc-electron/native/${tuple}`,
  });
  fs.rmSync(archive, {force: true});
  fs.rmSync(unpacked, {recursive: true, force: true});
  fs.renameSync(rebuilt, archive);
  fs.renameSync(`${rebuilt}.unpacked`, unpacked);
  fs.rmSync(stage, {recursive: true, force: true});
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
    'node_modules/tirtc-electron/README.md',
    'node_modules/tirtc-electron/api/**/*',
    'node_modules/tirtc-electron/dist/**/*',
    'node_modules/tirtc-electron/licenses/**/*',
    `node_modules/tirtc-electron/native/${tuple}/**/*`,
  ],
  asarUnpack: [`node_modules/tirtc-electron/native/${tuple}/**/*`],
  afterPack: filterNativeTuples,
  mac: {
    target: [{target: 'dir', arch: [targetArch]}],
    extendInfo: {NSMicrophoneUsageDescription: 'TiRTC uses the microphone for RTC audio.'},
  },
  win: {target: [{target: 'dir', arch: [targetArch]}]},
};
