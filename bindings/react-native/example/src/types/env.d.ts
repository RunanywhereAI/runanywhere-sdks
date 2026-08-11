// Types for the react-native-dotenv `@env` module. Values are inlined at build
// time from the gitignored .env; undefined when a key is absent.
declare module '@env' {
  export const RUNANYWHERE_BASE_URL: string | undefined;
  export const RUNANYWHERE_API_KEY: string | undefined;
}
