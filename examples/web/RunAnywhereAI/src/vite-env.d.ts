/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_RUNANYWHERE_BASE_URL?: string;
  readonly VITE_RUNANYWHERE_RELAY_ENABLED?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
