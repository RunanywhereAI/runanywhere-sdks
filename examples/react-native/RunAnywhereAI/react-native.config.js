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
    // Disable autolinking for audio libraries that are incompatible with New Architecture.
    // iOS: These libraries don't support the New Architecture (TurboModules/Fabric).
    // Android: Some libraries also disabled on Android due to build conflicts or
    //          because we use custom native implementations instead.
    'react-native-live-audio-stream': {
      platforms: {
        ios: null,
      },
    },
    'react-native-audio-recorder-player': {
      platforms: {
        ios: null,
        android: null, // Disabled on both platforms - using custom audio implementation
      },
    },
    'react-native-sound': {
      platforms: {
        ios: null,
        android: null, // Disabled on both platforms - using custom audio implementation
      },
    },
    'react-native-tts': {
      platforms: {
        ios: null,
      },
    },
  },
};
