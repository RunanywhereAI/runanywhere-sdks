/**
 * React Native configuration for RunAnywhere
 */
module.exports = {
  project: {
    ios: {
      automaticPodsInstallation: true,
    },
  },
  dependencies: {
    // Nitro modules requires Turbo codegen for iOS (NitroModulesSpec.h)
    'react-native-nitro-modules': {
      platforms: {
        android: null,
        ios: {},
      },
    },
    // Disable audio libraries on iOS - they're incompatible with New Architecture
    'react-native-live-audio-stream': {
      platforms: {
        ios: null,
      },
    },
    'react-native-audio-recorder-player': {
      platforms: {
        ios: null,
        android: null,
      },
    },
    'react-native-sound': {
      platforms: {
        ios: null,
        android: null,
      },
    },
    'react-native-tts': {
      platforms: {
        ios: null,
      },
    },
  },
};
