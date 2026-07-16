/// <reference types="vite/client" />

interface ImportMetaEnv {
  /** Public browser credential injected by Vite/Vercel at build time. */
  readonly VITE_RUNANYWHERE_API_KEY?: string;
  /** Production RunAnywhere API origin injected by Vite/Vercel at build time. */
  readonly VITE_RUNANYWHERE_BASE_URL?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
