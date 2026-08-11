module.exports = {
  presets: ['module:@react-native/babel-preset'],
  plugins: [
    // Inline build-time env from .env (gitignored) as `@env` imports — used for
    // the staging telemetry base URL + API key. Mirrors the Flutter example's
    // --dart-define and the Android example's local.properties -> BuildConfig.
    ['module:react-native-dotenv', { moduleName: '@env', path: '.env', allowUndefined: true }],
    // Required by react-native-reanimated v4 (worklets). Must be the last plugin.
    'react-native-worklets/plugin',
  ],
};
