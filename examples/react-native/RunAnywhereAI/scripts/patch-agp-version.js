/**
 * Patches React Native gradle plugin to use AGP 8.11.1 so Android Studio
 * (max supported 8.11.1) accepts the project. Run automatically after npm install.
 */
const fs = require('fs');
const path = require('path');

const tomlPath = path.join(
  __dirname,
  '..',
  'node_modules',
  '@react-native',
  'gradle-plugin',
  'gradle',
  'libs.versions.toml'
);

if (!fs.existsSync(tomlPath)) return;

let content = fs.readFileSync(tomlPath, 'utf8');
if (content.includes('agp = "8.12.0"')) {
  content = content.replace('agp = "8.12.0"', 'agp = "8.11.1"');
  fs.writeFileSync(tomlPath, content);
  console.log('[postinstall] Patched AGP to 8.11.1 for Android Studio compatibility.');
}
