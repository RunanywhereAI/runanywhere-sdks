#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

const rnRoot = path.resolve(__dirname, '..');
const packagesRoot = path.join(rnRoot, 'packages');

function rewrite(filePath, transform) {
  if (!fs.existsSync(filePath)) return;
  const before = fs.readFileSync(filePath, 'utf8');
  const after = transform(before);
  if (after !== before) fs.writeFileSync(filePath, after, 'utf8');
}

for (const packageName of fs.readdirSync(packagesRoot)) {
  const androidGenerated = path.join(
    packagesRoot,
    packageName,
    'nitrogen/generated/android',
  );
  if (!fs.existsSync(androidGenerated)) continue;

  for (const fileName of fs.readdirSync(androidGenerated)) {
    if (!/OnLoad\.(?:hpp|cpp)$/.test(fileName)) continue;
    const filePath = path.join(androidGenerated, fileName);
    rewrite(filePath, (content) => content
      .replace(
        /\n\s*\[\[deprecated\("Use registerNatives\(\) instead\."\)\]\]\n\s*int initialize\(JavaVM\* vm\);\n/g,
        '\n',
      )
      .replace(
        /\nint initialize\(JavaVM\* vm\) \{[\s\S]*?\n\}\n+(?=void registerAllNatives)/g,
        '\n',
      ));
  }
}

// Nitrogen 0.34 emits a header absent from the pinned Nitro runtime 0.33.9.
const coreSpec = path.join(
  packagesRoot,
  'core/nitrogen/generated/shared/c++/HybridRunAnywhereCoreSpec.hpp',
);
rewrite(coreSpec, (content) => content.replace(
  /#include <NitroModules\/Null\.hpp>/g,
  '// Null.hpp is not present in the pinned Nitro runtime.',
));

for (const packageName of fs.readdirSync(packagesRoot)) {
  const androidGenerated = path.join(
    packagesRoot,
    packageName,
    'nitrogen/generated/android',
  );
  if (!fs.existsSync(androidGenerated)) continue;
  for (const fileName of fs.readdirSync(androidGenerated)) {
    if (!/OnLoad\.(?:hpp|cpp)$/.test(fileName)) continue;
    const content = fs.readFileSync(path.join(androidGenerated, fileName), 'utf8');
    if (content.includes('int initialize(JavaVM* vm)')) {
      throw new Error(`Deprecated Nitrogen initialize shim remains in ${packageName}/${fileName}`);
    }
  }
}

console.log('Nitrogen output normalized.');
