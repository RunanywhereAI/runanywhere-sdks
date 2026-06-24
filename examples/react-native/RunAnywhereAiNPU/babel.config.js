module.exports = {
  presets: ['module:@react-native/babel-preset'],
  // Required by react-native-reanimated v4 (worklets). Must be the last plugin.
  plugins: ['react-native-worklets/plugin'],
};
