/**
 * The shape of `window.appStore` — this app's own bridge, alongside the SDK's.
 *
 * Kept in its own module (rather than inside the preload) so the renderer can
 * import the type without importing preload code, which would pull `electron`
 * into a renderer bundle.
 */
import type { ConversationsFile } from '../shared/conversation';
import type {
  BackendConfig,
  LogLevel,
  MenuCommand,
  PickFilesRequest,
  PlatformInfo,
  ResolvedTheme,
  ThemePreference,
} from '../shared/ipc-contract';
import type { AppSettings } from '../shared/settings';

/** A custom model the user added by HF repo, URL, or local path. */
export interface CustomModelRecord {
  readonly id: string;
  readonly source: string;
  readonly type: string;
  readonly label: string;
  /** Pinned engine, when the user chose one (e.g. the Hexagon NPU). */
  readonly engine?: string;
}

export interface AppBridge {
  // ---- persistence (main owns the files; these are thin IPC calls) ----
  loadConversations(): Promise<ConversationsFile>;
  saveConversations(data: ConversationsFile): Promise<boolean>;
  loadSettings(): Promise<unknown>;
  saveSettings(data: AppSettings): Promise<boolean>;
  loadCustomModels(): Promise<CustomModelRecord[]>;
  saveCustomModels(data: readonly CustomModelRecord[]): Promise<boolean>;

  /**
   * Merge persisted settings over the defaults. Runs synchronously in the preload
   * rather than over IPC, because it is a pure function and the renderer needs it
   * before its first paint.
   */
  migrateSettings(saved: unknown, defaults: AppSettings): AppSettings;

  // ---- host facts (the renderer never probes the platform itself) ----
  backendConfig(): Promise<BackendConfig>;
  platformInfo(): Promise<PlatformInfo>;

  // ---- appearance ----
  getTheme(): Promise<ResolvedTheme>;
  setTheme(preference: ThemePreference): Promise<ResolvedTheme>;
  /** Fires when the OS appearance changes. Returns an unsubscribe. */
  onThemeChanged(listener: (theme: ResolvedTheme) => void): () => void;

  // ---- native chrome ----
  /** Fires when a menu item is chosen. Returns an unsubscribe. */
  onMenuCommand(listener: (command: MenuCommand) => void): () => void;
  /** Publish what the focused view can do, so unavailable menu items grey out. */
  setMenuCapabilities(caps: {
    readonly canStopGeneration: boolean;
    readonly canShowChatDetails: boolean;
    readonly canPasteAttachment: boolean;
  }): void;

  // ---- files and links ----
  /** Native open dialog. Returns [] when cancelled. */
  pickFiles(request: PickFilesRequest): Promise<string[]>;
  /**
   * Turn a dropped or picked `File` into an on-disk path. `webUtils.getPathForFile`
   * is the only route — Electron removed `File.path`.
   */
  getPathForFile(file: File): string;
  revealPath(target: string): Promise<void>;
  openExternal(url: string): Promise<void>;

  // ---- diagnostics ----
  /** Renderer logs are forwarded to a main-side file log so they survive packaging. */
  log(level: LogLevel, scope: string, message: string): void;
}
