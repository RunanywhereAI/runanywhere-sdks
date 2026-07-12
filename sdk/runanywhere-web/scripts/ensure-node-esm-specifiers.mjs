#!/usr/bin/env node

import {
  existsSync,
  readdirSync,
  readFileSync,
  statSync,
  writeFileSync,
} from 'node:fs';
import { dirname, extname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import ts from 'typescript';

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const webRoot = resolve(scriptDirectory, '..');
const sourceRoots = [
  resolve(webRoot, 'packages/core/src'),
  resolve(webRoot, 'packages/llamacpp/src'),
  resolve(webRoot, 'packages/onnx/src'),
];
const write = process.argv.includes('--write');
const unexpectedArguments = process.argv.slice(2).filter((argument) => argument !== '--write');

if (unexpectedArguments.length > 0) {
  process.stderr.write(
    `Usage: node scripts/ensure-node-esm-specifiers.mjs [--write]\n`
      + `Unexpected arguments: ${unexpectedArguments.join(' ')}\n`,
  );
  process.exit(2);
}

function sourceFiles(directory) {
  const files = [];
  for (const entry of readdirSync(directory)) {
    const absolutePath = join(directory, entry);
    const info = statSync(absolutePath);
    if (info.isDirectory()) {
      files.push(...sourceFiles(absolutePath));
    } else if (entry.endsWith('.ts') || entry.endsWith('.tsx')) {
      files.push(absolutePath);
    }
  }
  return files;
}

function moduleSpecifierNodes(sourceFile) {
  const nodes = [];
  const seenStarts = new Set();

  const add = (node) => {
    if (!node || !ts.isStringLiteralLike(node)) return;
    const start = node.getStart(sourceFile);
    if (seenStarts.has(start)) return;
    seenStarts.add(start);
    nodes.push(node);
  };

  const visit = (node) => {
    if (ts.isImportDeclaration(node) || ts.isExportDeclaration(node)) {
      add(node.moduleSpecifier);
    } else if (
      ts.isCallExpression(node)
      && node.expression.kind === ts.SyntaxKind.ImportKeyword
    ) {
      add(node.arguments[0]);
    } else if (ts.isImportTypeNode(node) && ts.isLiteralTypeNode(node.argument)) {
      add(node.argument.literal);
    } else if (
      ts.isImportEqualsDeclaration(node)
      && ts.isExternalModuleReference(node.moduleReference)
    ) {
      add(node.moduleReference.expression);
    }
    ts.forEachChild(node, visit);
  };

  visit(sourceFile);
  return nodes;
}

function splitSuffix(specifier) {
  const suffixIndex = specifier.search(/[?#]/);
  return suffixIndex === -1
    ? { path: specifier, suffix: '' }
    : { path: specifier.slice(0, suffixIndex), suffix: specifier.slice(suffixIndex) };
}

function rewrittenSpecifier(sourcePath, specifier) {
  if (!specifier.startsWith('./') && !specifier.startsWith('../')) return null;

  const { path: importPath, suffix } = splitSuffix(specifier);
  if (/\.(?:[cm]?js|json|wasm|css|scss|sass|less|svg|png|jpe?g|gif|webp)$/i.test(importPath)) {
    return null;
  }

  const sourceExtension = extname(importPath).toLowerCase();
  if (sourceExtension === '.ts' || sourceExtension === '.tsx') {
    return `${importPath.slice(0, -sourceExtension.length)}.js${suffix}`;
  }
  if (sourceExtension === '.mts') {
    return `${importPath.slice(0, -sourceExtension.length)}.mjs${suffix}`;
  }
  if (sourceExtension === '.cts') {
    return `${importPath.slice(0, -sourceExtension.length)}.cjs${suffix}`;
  }

  const absoluteTarget = resolve(dirname(sourcePath), importPath);
  if (existsSync(absoluteTarget) && statSync(absoluteTarget).isFile()) return null;

  const directCandidates = ['.ts', '.tsx', '.mts', '.cts', '.d.ts'];
  if (directCandidates.some((extension) => existsSync(`${absoluteTarget}${extension}`))) {
    return `${importPath}.js${suffix}`;
  }

  const indexCandidates = ['index.ts', 'index.tsx', 'index.mts', 'index.cts', 'index.d.ts'];
  if (indexCandidates.some((filename) => existsSync(join(absoluteTarget, filename)))) {
    return `${importPath.replace(/\/$/, '')}/index.js${suffix}`;
  }

  return undefined;
}

const violations = [];
let changedFiles = 0;
let changedSpecifiers = 0;

for (const sourcePath of sourceRoots.flatMap(sourceFiles).sort()) {
  const sourceText = readFileSync(sourcePath, 'utf8');
  const sourceFile = ts.createSourceFile(
    sourcePath,
    sourceText,
    ts.ScriptTarget.Latest,
    true,
    sourcePath.endsWith('.tsx') ? ts.ScriptKind.TSX : ts.ScriptKind.TS,
  );
  const edits = [];

  for (const node of moduleSpecifierNodes(sourceFile)) {
    const specifier = node.text;
    if (!specifier.startsWith('./') && !specifier.startsWith('../')) continue;
    const replacement = rewrittenSpecifier(sourcePath, specifier);
    if (replacement === null) continue;

    const position = sourceFile.getLineAndCharacterOfPosition(node.getStart(sourceFile));
    violations.push({
      sourcePath,
      line: position.line + 1,
      column: position.character + 1,
      specifier,
      replacement,
    });
    if (replacement !== undefined) {
      edits.push({
        start: node.getStart(sourceFile) + 1,
        end: node.getEnd() - 1,
        replacement,
      });
    }
  }

  if (write && edits.length > 0) {
    let output = sourceText;
    for (const edit of edits.sort((left, right) => right.start - left.start)) {
      output = output.slice(0, edit.start) + edit.replacement + output.slice(edit.end);
    }
    writeFileSync(sourcePath, output);
    changedFiles += 1;
    changedSpecifiers += edits.length;
  }
}

if (violations.length === 0) {
  process.stdout.write(
    'Verified explicit Node-compatible ESM specifiers in core, llamacpp, and onnx sources.\n',
  );
  process.exit(0);
}

if (write) {
  const unresolved = violations.filter((violation) => violation.replacement === undefined);
  process.stdout.write(
    `Updated ${changedSpecifiers} relative ESM specifiers across ${changedFiles} source files.\n`,
  );
  if (unresolved.length === 0) process.exit(0);
  process.stderr.write('Unresolved relative module specifiers remain:\n');
  for (const violation of unresolved) {
    process.stderr.write(
      `  ${violation.sourcePath}:${violation.line}:${violation.column} ${violation.specifier}\n`,
    );
  }
  process.exit(1);
}

process.stderr.write(
  'Relative TypeScript module specifiers must use their emitted Node ESM extension. '
    + 'Run `npm run fix:esm-specifiers`.\n',
);
for (const violation of violations) {
  const suggestion = violation.replacement ?? '<unresolved target>';
  process.stderr.write(
    `  ${violation.sourcePath}:${violation.line}:${violation.column} `
      + `${violation.specifier} -> ${suggestion}\n`,
  );
}
process.exit(1);
