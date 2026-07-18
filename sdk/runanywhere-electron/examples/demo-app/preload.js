// Demo preload: loads the SDK preload (which sets up window.runanywhere +
// window.runanywhereTest), then adds a tiny conversation/settings store backed by
// the main process (JSON files in userData). Kept in the DEMO, not the SDK.
require('../../dist/process/preload');
const { contextBridge, ipcRenderer, webUtils } = require('electron');

contextBridge.exposeInMainWorld('demoStore', {
  loadConversations: () => ipcRenderer.invoke('demo:conversations:load'),
  saveConversations: (data) => ipcRenderer.invoke('demo:conversations:save', data),
  loadSettings: () => ipcRenderer.invoke('demo:settings:load'),
  saveSettings: (data) => ipcRenderer.invoke('demo:settings:save', data),
  loadCustomModels: () => ipcRenderer.invoke('demo:models:load'),
  saveCustomModels: (data) => ipcRenderer.invoke('demo:models:save', data),
  // Modern Electron removed File.path; webUtils.getPathForFile is the replacement.
  getPathForFile: (file) => webUtils.getPathForFile(file),
});
