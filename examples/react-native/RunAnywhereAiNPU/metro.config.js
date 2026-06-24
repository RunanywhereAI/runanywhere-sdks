const path = require('path');
const { getDefaultConfig, mergeConfig } = require('@react-native/metro-config');

// Yarn workspace root (where node_modules with all hoisted deps lives)
const workspaceRoot = path.resolve(__dirname, '../../../');
const bufbuildProtobufRoot = path.resolve(
  workspaceRoot,
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
 * Yarn workspace setup: deps are hoisted to repo root. Metro must:
 *   1. Watch all workspace folders so source changes hot-reload.
 *   2. Look up modules in the root node_modules (where yarn hoists them).
 *
 * @type {import('metro-config').MetroConfig}
 */
const config = {
  // Watch source for all workspace packages so edits trigger reload.
  watchFolders: [workspaceRoot],
  resolver: {
    // Search node_modules first locally (in case of nohoist), then at workspace root.
    nodeModulesPaths: [
      path.resolve(__dirname, 'node_modules'),
      path.resolve(workspaceRoot, 'node_modules'),
    ],
    // Single instance enforcement for shared peer deps (RN forbids duplicates).
    extraNodeModules: {
      'react-native': path.resolve(workspaceRoot, 'node_modules/react-native'),
      'react-native-nitro-modules': path.resolve(workspaceRoot, 'node_modules/react-native-nitro-modules'),
      'react': path.resolve(workspaceRoot, 'node_modules/react'),
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
