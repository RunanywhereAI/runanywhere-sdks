const path = require('path');
const { getDefaultConfig, mergeConfig } = require('@react-native/metro-config');

// Path to the SDK package (symlinked via node_modules)
const sdkPath = path.resolve(__dirname, '../../../sdk/runanywhere-react-native');
const sdkPackagesPath = path.join(sdkPath, 'packages');
const sdkCorePath = path.join(sdkPackagesPath, 'core');
const sdkLlamaPath = path.join(sdkPackagesPath, 'llamacpp');
const sdkOnnxPath = path.join(sdkPackagesPath, 'onnx');
// proto-ts is a sibling SDK package outside packages/ — Metro won't auto-discover it
const sdkProtoTsPath = path.resolve(__dirname, '../../../sdk/runanywhere-proto-ts');

// Genie package — consumed from npm (@runanywhere/genie)
const geniePkgPath = path.resolve(__dirname, 'node_modules/@runanywhere/genie');

/**
 * Metro configuration
 * https://reactnative.dev/docs/metro
 *
 * @type {import('metro-config').MetroConfig}
 */
const config = {
  watchFolders: [sdkPackagesPath, geniePkgPath, sdkProtoTsPath],
  resolver: {
    // Ensure Metro resolves SDK packages from the workspace (symlinks can be flaky)
    extraNodeModules: {
      '@runanywhere/core': sdkCorePath,
      '@runanywhere/llamacpp': sdkLlamaPath,
      '@runanywhere/onnx': sdkOnnxPath,
      '@runanywhere/proto-ts': sdkProtoTsPath,
      '@runanywhere/genie': geniePkgPath,
      // Force single instances of shared peer dependencies (avoid version conflicts)
      'react-native': path.resolve(__dirname, 'node_modules/react-native'),
      'react-native-nitro-modules': path.resolve(__dirname, 'node_modules/react-native-nitro-modules'),
      'react': path.resolve(__dirname, 'node_modules/react'),
    },
    // Allow Metro to resolve modules from the SDK and genie package
    nodeModulesPaths: [
      path.resolve(__dirname, 'node_modules'),
      path.resolve(sdkPath, 'node_modules'),
    ],
    // Don't hoist packages from the SDK - ensure local node_modules takes precedence
    disableHierarchicalLookup: false,
    // Ensure symlinks are followed
    unstable_enableSymlinks: true,
    // B-RN-MetroExports-002/003: Metro 0.83's exports resolver rejects proto-ts subpath
    // patterns regardless of glob shape. Disable exports honoring entirely so legacy
    // file-path resolution applies (proto-ts has no `type:module` so this is safe).
    unstable_enablePackageExports: false,
    // Prefer .js/.json over .ts/.tsx for compiled packages
    sourceExts: ['js', 'json', 'ts', 'tsx'],
  },
};

module.exports = mergeConfig(getDefaultConfig(__dirname), config);
