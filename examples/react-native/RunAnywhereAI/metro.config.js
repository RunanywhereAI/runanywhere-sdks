const path = require('path');
const { getDefaultConfig, mergeConfig } = require('@react-native/metro-config');

// Repo root — watched so edits to the portal-linked SDK packages hot-reload.
const repoRoot = path.resolve(__dirname, '../../../');
const bufbuildProtobufRoot = path.resolve(
  __dirname,
  'node_modules/@bufbuild/protobuf'
);
// Use binary-encoding.js directly — the wire/index.js barrel re-exports can be
// empty in Hermes production bundles, breaking ts-proto's `new BinaryWriter()`.
const bufbuildWireCjs = path.join(
  bufbuildProtobufRoot,
  'dist/cjs/wire/binary-encoding.js'
);

const defaultConfig = getDefaultConfig(__dirname);
// Allow Metro to resolve .mjs/.cjs entry points (default sourceExts omit them).
defaultConfig.resolver.sourceExts.push('mjs', 'cjs');

// Don't crawl/watch native build output. The Android `.cxx`/`build` dirs churn
// during gradle builds (CMake TryCompile temp dirs created+deleted), which makes
// Metro's fallback file watcher crash with ENOENT. Excluding them keeps Metro
// stable whether or not watchman is installed.
defaultConfig.resolver.blockList = [
  /.*\/android\/\.cxx\/.*/,
  /.*\/android\/build\/.*/,
  /.*\/ios\/build\/.*/,
];

/**
 * Metro configuration
 * https://reactnative.dev/docs/metro
 *
 * Standalone yarn project: the @runanywhere/* SDK packages resolve via the
 * portal: protocol, so Metro watches the repo root for their sources and
 * resolves all modules from this app's own node_modules.
 *
 * @type {import('metro-config').MetroConfig}
 */
const config = {
  // Watch the repo root so portal-linked SDK package edits trigger reload.
  watchFolders: [repoRoot],
  resolver: {
    nodeModulesPaths: [
      path.resolve(__dirname, 'node_modules'),
    ],
    // Single instance enforcement for shared peer deps (RN forbids duplicates).
    extraNodeModules: {
      'react-native': path.resolve(__dirname, 'node_modules/react-native'),
      'react-native-nitro-modules': path.resolve(__dirname, 'node_modules/react-native-nitro-modules'),
      'react': path.resolve(__dirname, 'node_modules/react'),
      // ts-proto generated code uses @bufbuild/protobuf/wire; Metro must resolve the CJS build.
      '@bufbuild/protobuf': bufbuildProtobufRoot,
    },
    resolveRequest: (context, moduleName, platform) => {
      if (
        moduleName === '@bufbuild/protobuf/wire' ||
        moduleName === '@bufbuild/protobuf/dist/cjs/wire/index.js' ||
        moduleName === '@bufbuild/protobuf/dist/cjs/wire/binary-encoding.js' ||
        moduleName === '@bufbuild/protobuf/wire/binary-encoding'
      ) {
        return { type: 'sourceFile', filePath: bufbuildWireCjs };
      }
      // Delegate to Metro's own default resolver. Metro pre-sets
      // `context.resolveRequest` to its internal `resolve` (with the
      // `resolveRequest !== resolve` recursion guard pointing at the same
      // module instance). Importing a separate `metro-resolver` package here
      // would bind a *different* `resolve` identity — when the root
      // metro-resolver (v0.84.x) and metro's bundled copy (v0.83.x) differ,
      // that guard never matches and delegation recurses infinitely
      // ("Maximum call stack size exceeded" in metro-resolver/src/resolve.js).
      return context.resolveRequest(context, moduleName, platform);
    },

    // Standard hierarchical lookup; yarn workspace symlinks resolve cleanly.
    disableHierarchicalLookup: false,
    unstable_enableSymlinks: true,
  },
};

module.exports = mergeConfig(defaultConfig, config);
