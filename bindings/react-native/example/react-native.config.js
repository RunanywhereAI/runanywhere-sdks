/**
 * React Native configuration for RunAnywhere
 */
module.exports = {
  project: {
    ios: {
      automaticPodsInstallation: true,
    },
  },
  assets: ['./assets/fonts'],
  dependencies: {
    // Nitro modules requires Turbo codegen for iOS (NitroModulesSpec.h)
    'react-native-nitro-modules': {
      platforms: {
        android: null,
        ios: {},
      },
    },
  },
};
