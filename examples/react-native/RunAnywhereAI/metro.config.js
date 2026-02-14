const path = require('path');
const { getDefaultConfig, mergeConfig } = require('@react-native/metro-config');

// Path to the SDK package (symlinked via node_modules)
const sdkPath = path.resolve(__dirname, '../../../sdk/runanywhere-react-native');
const sdkPackagesPath = path.join(sdkPath, 'packages');
const sdkCorePath = path.join(sdkPackagesPath, 'core');
const sdkRagPath = path.join(sdkPackagesPath, 'rag');
const sdkLlamaPath = path.join(sdkPackagesPath, 'llamacpp');
const sdkOnnxPath = path.join(sdkPackagesPath, 'onnx');

/**
 * Metro configuration
 * https://reactnative.dev/docs/metro
 *
 * @type {import('metro-config').MetroConfig}
 */
const config = {
  watchFolders: [sdkPackagesPath],
  resolver: {
    // Ensure Metro resolves SDK packages from the workspace (symlinks can be flaky)
    extraNodeModules: {
      '@runanywhere/core': sdkCorePath,
      '@runanywhere/rag': sdkRagPath,
      '@runanywhere/llamacpp': sdkLlamaPath,
      '@runanywhere/onnx': sdkOnnxPath,
    },
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
