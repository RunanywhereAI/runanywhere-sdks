#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';

const projectRoot = process.cwd();
const stageRoot = path.join(projectRoot, '.vercel-stage');
const projectLink = path.join(projectRoot, '.vercel/project.json');

if (!fs.existsSync(projectLink)) {
  throw new Error("This checkout is not linked to Vercel. Run 'vercel link' first.");
}

fs.rmSync(stageRoot, { recursive: true, force: true });
fs.mkdirSync(stageRoot, { recursive: true });

function copy(relativePath) {
  const source = path.join(projectRoot, relativePath);
  if (!fs.existsSync(source)) throw new Error(`Required release input is missing: ${relativePath}`);
  const destination = path.join(stageRoot, relativePath);
  fs.mkdirSync(path.dirname(destination), { recursive: true });
  fs.cpSync(source, destination, { recursive: true });
}

for (const relativePath of [
  'dist',
  'api/runanywhere.ts',
  'server/control-plane-relay.ts',
  'src/services/control-plane-relay.ts',
  'scripts/verify-release-output.mjs',
  'package.json',
  'package-lock.json',
]) {
  copy(relativePath);
}

copy('.vercel/project.json');

const sourceConfig = JSON.parse(fs.readFileSync(path.join(projectRoot, 'vercel.json'), 'utf8'));
sourceConfig.buildCommand = 'npm run release:verify';
fs.writeFileSync(
  path.join(stageRoot, 'vercel.json'),
  `${JSON.stringify(sourceConfig, null, 2)}\n`,
);

process.stdout.write(`Staged the prebuilt app and relay source in ${stageRoot}\n`);
