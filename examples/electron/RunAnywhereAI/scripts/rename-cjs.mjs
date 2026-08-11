// package.json declares "type": "module", so Node reads a bare .js as ESM.
// tsc emits CommonJS for main and preload (Electron loads them that way), so the
// emitted files need a .cjs extension — and every relative require() inside them
// has to be rewritten to match, because tsc wrote them extensionless.
//
// Run after `tsc -p tsconfig.{main,preload}.build.json`.
import { readdirSync, readFileSync, renameSync, statSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const appRoot = fileURLToPath(new URL('..', import.meta.url));
// Everything tsc emitted: `main`, `preload`, and the `shared` modules both of
// them import. NOT `out/renderer` — that is Vite's ESM bundle and must stay .js.
const roots = [join(appRoot, 'out/main'), join(appRoot, 'out/preload'), join(appRoot, 'out/shared')];

/** Every .js file under `dir`, recursively. */
function jsFiles(dir) {
  const out = [];
  let entries;
  try {
    entries = readdirSync(dir);
  } catch {
    return out; // a target that was not built this run
  }
  for (const entry of entries) {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) out.push(...jsFiles(full));
    else if (entry.endsWith('.js')) out.push(full);
  }
  return out;
}

let renamed = 0;
for (const root of roots) {
  const files = jsFiles(root);
  for (const file of files) {
    // Point relative requires at the .cjs siblings this loop is creating.
    // Only relative specifiers are rewritten: a bare package name must keep
    // resolving through node_modules.
    const src = readFileSync(file, 'utf8');
    const patched = src.replace(
      /require\((["'])(\.[^"']*?)\1\)/g,
      (_match, quote, spec) => `require(${quote}${spec}${spec.endsWith('.cjs') ? '' : '.cjs'}${quote})`,
    );
    const target = `${file.slice(0, -3)}.cjs`;
    writeFileSync(file, patched);
    renameSync(file, target);
    renamed += 1;
  }
}

process.stdout.write(`rename-cjs: ${renamed} file(s) -> .cjs\n`);
