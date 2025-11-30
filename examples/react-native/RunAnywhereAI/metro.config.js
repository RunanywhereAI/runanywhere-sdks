const path = require('path');
const { getDefaultConfig, mergeConfig } = require('@react-native/metro-config');

// Path to the SDK package
const sdkPath = path.resolve(__dirname, '../../../sdk/runanywhere-react-native');

/**
 * Metro configuration
 * https://reactnative.dev/docs/metro
 *
 * @type {import('metro-config').MetroConfig}
 */
const config = {
  watchFolders: [sdkPath],
  resolver: {
    // Ensure symlinks are followed
    nodeModulesPaths: [
      path.resolve(__dirname, 'node_modules'),
      path.resolve(sdkPath, 'node_modules'),
    ],
    // Don't hoist packages from the SDK
    disableHierarchicalLookup: false,
  },
};

module.exports = mergeConfig(getDefaultConfig(__dirname), config);
