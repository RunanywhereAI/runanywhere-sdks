/// <reference types="svelte" />
/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_RUNANYWHERE_API_KEY?: string;
  readonly VITE_RUNANYWHERE_BASE_URL?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
