module.exports = {
  project: {
    ios: {
      automaticPodsInstallation: true,
    },
  },
  dependencies: {
    'react-native-nitro-modules': {
      platforms: {
        android: null,
        ios: {},
      },
    },
    'react-native-live-audio-stream': {
      platforms: {
        ios: null,
      },
    },
  },
};
