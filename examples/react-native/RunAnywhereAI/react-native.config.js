/**
 * React Native configuration for RunAnywhere
 */
const enableRunAnywhereGenie =
  process.env.RUNANYWHERE_ENABLE_GENIE === '1' ||
  process.env.RUNANYWHERE_ENABLE_GENIE === 'true';

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
    // Closed-source Genie/QNN Android prebuilts are not 16 KB ELF-aligned yet.
    // Opt in only after compatible prebuilts are available by setting both
    // RUNANYWHERE_ENABLE_GENIE=1 and -Prunanywhere.enableGenie=true.
    '@runanywhere/genie': {
      platforms: {
        android: enableRunAnywhereGenie ? {} : null,
      },
    },
  },
};
