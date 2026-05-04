const path = require('path');
const { getDefaultConfig, mergeConfig } = require('@react-native/metro-config');

// Yarn workspace root (where node_modules with all hoisted deps lives)
const workspaceRoot = path.resolve(__dirname, '../../../');

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
    },
    // Standard hierarchical lookup; yarn workspace symlinks resolve cleanly.
    disableHierarchicalLookup: false,
    unstable_enableSymlinks: true,
  },
};

module.exports = mergeConfig(getDefaultConfig(__dirname), config);
