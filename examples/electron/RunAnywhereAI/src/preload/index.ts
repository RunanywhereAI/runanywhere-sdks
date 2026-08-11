/**
 * The preload.
 *
 * Two jobs, and the ORDER of the first two statements matters: the catalog must
 * be registered BEFORE the SDK's preload is loaded, because registration is
 * per-process and the SDK's `initialize()` seeds the staged entries into the
 * commons registry.
 *
 * Runs with `contextIsolation: true`, `nodeIntegration: false`, `sandbox: false`
 * — the last because a sandboxed preload cannot require SDK modules.
 */
import { contextBridge, ipcRenderer, webUtils } from 'electron';

import { registerCatalog, type Catalog as SdkCatalog } from '@runanywhere/electron';
import { CATALOG } from '../shared/model-catalog';

// The SDK's `Catalog` types its entries' `files` as a mutable array while this
// app's table is deeply readonly (it is constant data). The cast is at the seam
// only; `registerCatalog` copies what it is given and never mutates it.
registerCatalog(CATALOG as unknown as SdkCatalog);

// Publishes `window.runanywhere`. Imported for its side effect, after the
// catalog is staged.
import '@runanywhere/electron/preload';

import type { ConversationsFile } from '../shared/conversation';
import {
  IpcChannel,
  IpcEvent,
  type BackendConfig,
  type LogLevel,
  type MenuCommand,
  type PickFilesRequest,
  type PlatformInfo,
  type ResolvedTheme,
  type ThemePreference,
} from '../shared/ipc-contract';
import { migrateSettings, type AppSettings } from '../shared/settings';

import type { AppBridge, CustomModelRecord } from './bridge-types';

/** Subscribe to a main->renderer push, returning an unsubscribe. */
function subscribe<T>(channel: string, listener: (value: T) => void): () => void {
  const handler = (_event: Electron.IpcRendererEvent, value: T): void => listener(value);
  ipcRenderer.on(channel, handler);
  return () => ipcRenderer.off(channel, handler);
}

const bridge: AppBridge = {
  loadConversations: () => ipcRenderer.invoke(IpcChannel.ConversationsLoad) as Promise<ConversationsFile>,
  saveConversations: (data) => ipcRenderer.invoke(IpcChannel.ConversationsSave, data) as Promise<boolean>,
  loadSettings: () => ipcRenderer.invoke(IpcChannel.SettingsLoad) as Promise<unknown>,
  saveSettings: (data) => ipcRenderer.invoke(IpcChannel.SettingsSave, data) as Promise<boolean>,
  loadCustomModels: () => ipcRenderer.invoke(IpcChannel.CustomModelsLoad) as Promise<CustomModelRecord[]>,
  saveCustomModels: (data) => ipcRenderer.invoke(IpcChannel.CustomModelsSave, data) as Promise<boolean>,

  // Pure function, run here rather than over IPC: the renderer needs merged
  // settings before its first paint.
  migrateSettings: (saved: unknown, defaults: AppSettings) => migrateSettings(saved, defaults),

  backendConfig: () => ipcRenderer.invoke(IpcChannel.BackendConfig) as Promise<BackendConfig>,
  platformInfo: () => ipcRenderer.invoke(IpcChannel.PlatformInfo) as Promise<PlatformInfo>,

  getTheme: () => ipcRenderer.invoke(IpcChannel.ThemeGet) as Promise<ResolvedTheme>,
  setTheme: (preference: ThemePreference) =>
    ipcRenderer.invoke(IpcChannel.ThemeSet, preference) as Promise<ResolvedTheme>,
  onThemeChanged: (listener) => subscribe<ResolvedTheme>(IpcEvent.ThemeChanged, listener),

  onMenuCommand: (listener) => subscribe<MenuCommand>(IpcEvent.MenuCommand, listener),
  setMenuCapabilities: (caps) => ipcRenderer.send(IpcChannel.MenuCapabilities, caps),

  pickFiles: (request: PickFilesRequest) => ipcRenderer.invoke(IpcChannel.PickFiles, request) as Promise<string[]>,
  // Modern Electron removed File.path; webUtils.getPathForFile is the replacement.
  getPathForFile: (file: File) => webUtils.getPathForFile(file),
  revealPath: (target: string) => ipcRenderer.invoke(IpcChannel.RevealPath, target) as Promise<void>,
  openExternal: (url: string) => ipcRenderer.invoke(IpcChannel.OpenExternal, url) as Promise<void>,

  log: (level: LogLevel, scope: string, message: string) =>
    ipcRenderer.send(IpcChannel.LogWrite, { level, scope, message }),
};

contextBridge.exposeInMainWorld('appStore', bridge);
