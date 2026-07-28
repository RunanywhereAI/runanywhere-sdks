// App preload: loads the SDK preload (which exposes window.runanywhere over the
// MessagePort), then adds this app's own local store — conversations, settings,
// and custom models, persisted as JSON in userData by the main process.
require('../../sdk/runanywhere-electron/dist/process/preload');
const { contextBridge, ipcRenderer, webUtils } = require('electron');

contextBridge.exposeInMainWorld('appStore', {
  loadConversations: () => ipcRenderer.invoke('store:conversations:load'),
  saveConversations: (data) => ipcRenderer.invoke('store:conversations:save', data),
  loadSettings: () => ipcRenderer.invoke('store:settings:load'),
  saveSettings: (data) => ipcRenderer.invoke('store:settings:save', data),
  loadCustomModels: () => ipcRenderer.invoke('store:models:load'),
  saveCustomModels: (data) => ipcRenderer.invoke('store:models:save', data),
  // Modern Electron removed File.path; webUtils.getPathForFile is the replacement.
  getPathForFile: (file) => webUtils.getPathForFile(file),
});
