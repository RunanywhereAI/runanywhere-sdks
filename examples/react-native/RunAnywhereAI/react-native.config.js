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
      },
    },
    'react-native-tts': {
      platforms: {
        ios: null,
      },
    },
  },
};
