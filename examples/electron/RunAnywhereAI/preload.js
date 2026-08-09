// App preload: loads the SDK preload (which exposes window.runanywhere over the
// MessagePort), then adds this app's own local store — conversations, settings,
// and custom models, persisted as JSON in userData by the main process.
// This app's catalog, staged before anything resolves a model id. Registration
// is per process: main.js hands the same file to the utility host, which is the
// process that downloads.
const { registerCatalog } = require('../../../sdk/runanywhere-electron/dist/catalog');
const { CATALOG } = require('./model-catalog');
registerCatalog(CATALOG);
require('../../../sdk/runanywhere-electron/dist/process/preload');
const { contextBridge, ipcRenderer, webUtils } = require('electron');
const { migrateSettings } = require('./store');

contextBridge.exposeInMainWorld('appStore', {
  loadConversations: () => ipcRenderer.invoke('store:conversations:load'),
  saveConversations: (data) => ipcRenderer.invoke('store:conversations:save', data),
  loadSettings: () => ipcRenderer.invoke('store:settings:load'),
  // Upgrade settings a previous build persisted (see store.js). Without this a
  // saved copy of a superseded default silently overrides the current one.
  migrateSettings: (saved, defaults) => migrateSettings(saved, defaults),
  saveSettings: (data) => ipcRenderer.invoke('store:settings:save', data),
  loadCustomModels: () => ipcRenderer.invoke('store:models:load'),
  saveCustomModels: (data) => ipcRenderer.invoke('store:models:save', data),
  backendConfig: () => ipcRenderer.invoke('app:backend-config'),
  // Modern Electron removed File.path; webUtils.getPathForFile is the replacement.
  getPathForFile: (file) => webUtils.getPathForFile(file),
});
