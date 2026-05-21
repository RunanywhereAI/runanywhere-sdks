#!/usr/bin/env node
/**
 * Post-nitrogen script to fix generated code
 * Removes the non-existent Null.hpp include from generated files
 */

const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, '../nitrogen/generated/shared/c++/HybridRunAnywhereCoreSpec.hpp');

if (fs.existsSync(filePath)) {
  let content = fs.readFileSync(filePath, 'utf8');

  // Replace the Null.hpp include with a comment.
  // Pin pair (see dependencies/versions.json _notes): nitrogen ^0.34.1 (codegen)
  // / react-native-nitro-modules ^0.33.9 (runtime). The 0.34.x codegen emits
  // <NitroModules/Null.hpp>, but that header does not ship in the 0.33.9
  // runtime; this post-patch strips the include so the generated spec compiles
  // against the pinned runtime.
  content = content.replace(
    /#include <NitroModules\/Null\.hpp>/g,
    '// #include <NitroModules/Null.hpp> // Removed - file does not ship in react-native-nitro-modules 0.33.9 (nitrogen 0.34.1 codegen emits it; runtime pin pair documented in dependencies/versions.json)'
  );

  fs.writeFileSync(filePath, content, 'utf8');
  console.log('✅ Fixed Null.hpp include in HybridRunAnywhereCoreSpec.hpp');
} else {
  console.log('⚠️  File not found:', filePath);
}
