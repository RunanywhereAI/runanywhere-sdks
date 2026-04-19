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
  
  // Replace the Null.hpp include with a comment
  content = content.replace(
    /#include <NitroModules\/Null\.hpp>/g,
    '// #include <NitroModules/Null.hpp> // Removed - file does not exist in nitro-modules 0.31.3'
  );
  
  fs.writeFileSync(filePath, content, 'utf8');
  console.log('✅ Fixed Null.hpp include in HybridRunAnywhereCoreSpec.hpp');
} else {
  console.log('⚠️  File not found:', filePath);
}
