#!/usr/bin/env node

import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const exampleRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const typeScript = path.join(exampleRoot, 'node_modules/typescript/bin/tsc');
fs.rmSync(path.join(exampleRoot, 'dist'), {recursive: true, force: true});
execFileSync(process.execPath, [typeScript, '-p',
  path.join(exampleRoot, 'tsconfig.json')], {stdio: 'inherit'});
const rendererSource = path.join(exampleRoot, 'src/renderer');
const rendererOutput = path.join(exampleRoot, 'dist/renderer');
fs.mkdirSync(rendererOutput, {recursive: true});
for (const file of ['index.html', 'styles.css']) {
  fs.copyFileSync(path.join(rendererSource, file), path.join(rendererOutput, file));
}
