const path = require('path');
const { getDefaultConfig, mergeConfig } = require('@react-native/metro-config');
const metroConfigPath = path.dirname(require.resolve('metro-config/package.json'));
const exclusionList = require(path.join(metroConfigPath, 'src/defaults/exclusionList')).default;

// Path to the SDK package (symlinked via node_modules)
const sdkPath = path.resolve(__dirname, '../../../sdk/runanywhere-react-native');
const sdkPackagesPath = path.join(sdkPath, 'packages');

/**
 * Metro configuration
 * https://reactnative.dev/docs/metro
 *
 * @type {import('metro-config').MetroConfig}
 */
const config = {
  watchFolders: [sdkPackagesPath],
  resolver: {
        // Exclude TypeScript source files from @runanywhere/rag symlinked package
        // Force Metro to only see the compiled lib/ directory
        blacklistRE: exclusionList([
          // Ignore src directory in RAG package to force Metro to use lib/
          /.*\/node_modules\/@runanywhere\/rag\/src\/.*/,
        ]),
    // Allow Metro to resolve modules from the SDK
    nodeModulesPaths: [
      path.resolve(__dirname, 'node_modules'),
      path.resolve(sdkPath, 'node_modules'),
    ],
    // Don't hoist packages from the SDK - ensure local node_modules takes precedence
    disableHierarchicalLookup: false,
    // Ensure symlinks are followed
    unstable_enableSymlinks: true,
    // Prefer .js/.json over .ts/.tsx for compiled packages
    sourceExts: ['js', 'json', 'ts', 'tsx'],
  },
};

module.exports = mergeConfig(getDefaultConfig(__dirname), config);
