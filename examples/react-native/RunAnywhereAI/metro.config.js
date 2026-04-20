const path = require('path');
const { getDefaultConfig, mergeConfig } = require('@react-native/metro-config');

// Path to the SDK package (single TS package post-v2 cutover; backend
// register entry points + native bindings live in @runanywhere/core).
const sdkCorePath = path.resolve(__dirname, '../../../sdk/ts');

// Genie package — consumed from npm (@runanywhere/genie)
const geniePkgPath = path.resolve(__dirname, 'node_modules/@runanywhere/genie');

/**
 * Metro configuration
 * https://reactnative.dev/docs/metro
 *
 * @type {import('metro-config').MetroConfig}
 */
const config = {
  watchFolders: [sdkCorePath, geniePkgPath],
  resolver: {
    extraNodeModules: {
      '@runanywhere/core': sdkCorePath,
      '@runanywhere/genie': geniePkgPath,
      // Force single instances of shared peer dependencies (avoid version conflicts)
      'react-native': path.resolve(__dirname, 'node_modules/react-native'),
      'react-native-nitro-modules': path.resolve(__dirname, 'node_modules/react-native-nitro-modules'),
      'react': path.resolve(__dirname, 'node_modules/react'),
    },
    // Allow Metro to resolve modules from the SDK and genie package
    nodeModulesPaths: [
      path.resolve(__dirname, 'node_modules'),
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
