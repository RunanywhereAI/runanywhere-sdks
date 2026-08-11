/**
 * The single definition of every IPC channel and its payload.
 *
 * Both sides import from here, so a channel name or a payload shape can never
 * drift between main and renderer — the compiler catches it. Adding a channel
 * means adding it to `IpcChannel` and to the request/response maps below.
 */

/** Channels the renderer invokes and awaits a reply on (`ipcRenderer.invoke`). */
export const IpcChannel = {
  ConversationsLoad: 'store:conversations:load',
  ConversationsSave: 'store:conversations:save',
  SettingsLoad: 'store:settings:load',
  SettingsSave: 'store:settings:save',
  CustomModelsLoad: 'store:models:load',
  CustomModelsSave: 'store:models:save',
  BackendConfig: 'app:backend-config',
  PlatformInfo: 'app:platform-info',
  ThemeGet: 'app:theme:get',
  ThemeSet: 'app:theme:set',
  RevealPath: 'app:reveal-path',
  OpenExternal: 'app:open-external',
  PickFiles: 'app:pick-files',
  LogWrite: 'app:log',
  /**
   * The renderer publishes what the focused view can do, so the menu can grey
   * out unavailable items. Equivalent to SwiftUI's focused-value publish.
   */
  MenuCapabilities: 'app:menu-capabilities',
  /**
   * Open or focus the preferences BrowserWindow. Owned by main (singleton),
   * mirroring macOS `Settings { }` — not a sidebar route.
   */
  OpenSettingsWindow: 'app:settings:open',
} as const;

export type IpcChannel = (typeof IpcChannel)[keyof typeof IpcChannel];

/** Channels main pushes to the renderer (`webContents.send`). */
export const IpcEvent = {
  ThemeChanged: 'app:theme:changed',
  MenuCommand: 'app:menu-command',
  /** Fired after a settings save so every open window can reload. */
  SettingsChanged: 'app:settings:changed',
} as const;

export type IpcEvent = (typeof IpcEvent)[keyof typeof IpcEvent];

/**
 * Menu-driven navigation. The native menu cannot call renderer functions, so a
 * command crosses as a discriminated string and the shell resolves it to the
 * same entry points the UI uses. Mirrors AppCommands.swift.
 */
export const MenuCommand = {
  NewConversation: 'new-conversation',
  OpenSettings: 'open-settings',
  ToggleSidebar: 'toggle-sidebar',
  ShowChat: 'show-chat',
  ShowModels: 'show-models',
  ShowAdvanced: 'show-advanced',
  ShowChatDetails: 'show-chat-details',
  FocusComposer: 'focus-composer',
  OpenModelPicker: 'open-model-picker',
  StopGeneration: 'stop-generation',
  PasteAttachment: 'paste-attachment',
  ImportDocument: 'import-document',
} as const;

export type MenuCommand = (typeof MenuCommand)[keyof typeof MenuCommand];

/** Resolved appearance. `system` is a preference; it is never a rendered state. */
export type ThemePreference = 'light' | 'dark' | 'system';
export type ResolvedTheme = 'light' | 'dark';

/**
 * Control-plane credentials read from a gitignored `.env` (or the environment).
 * With both a base URL and an API key, the SDK initializes in PRODUCTION
 * (org-scoped, authed telemetry); with neither, DEVELOPMENT (keyless).
 * Mirrors the Android example's `local.properties` contract.
 */
export interface BackendConfig {
  readonly apiKey: string;
  readonly baseUrl: string;
  readonly environment: 'production' | 'development';
}

/**
 * What the renderer is allowed to know about the host. Everything here comes
 * from main; the renderer never probes the platform itself.
 */
export interface PlatformInfo {
  readonly platform: 'darwin' | 'win32' | 'linux';
  readonly arch: string;
  /** True when the OS keychain backs the secure store (macOS Keychain / Win32 DPAPI). */
  readonly secureStorageAvailable: boolean;
  /** Human-readable name of the secure store, for settings copy. */
  readonly secureStorageLabel: string;
  /** Where models and the secure store live, for the storage screen's Reveal action. */
  readonly modelsDirectory: string;
  readonly userDataDirectory: string;
  readonly appVersion: string;
}

export interface PickFilesRequest {
  readonly title?: string;
  /** Electron dialog filter shape. */
  readonly filters?: ReadonlyArray<{ readonly name: string; readonly extensions: readonly string[] }>;
  readonly multiple?: boolean;
}

export type LogLevel = 'debug' | 'info' | 'warn' | 'error';

export interface LogRecord {
  readonly level: LogLevel;
  readonly scope: string;
  readonly message: string;
}
