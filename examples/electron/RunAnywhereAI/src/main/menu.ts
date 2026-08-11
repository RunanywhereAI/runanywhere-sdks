/**
 * The application menu.
 *
 * Mirrors `App/AppCommands.swift` item for item and accelerator for accelerator.
 * Two rules carried over from the Swift implementation:
 *
 *  * The menu is **replaced, not hidden.** `setMenuBarVisibility(false)` alone
 *    leaves accelerators live, so Ctrl/Cmd+Shift+I would still open DevTools in a
 *    shipped build and hand anyone who can talk a user through a keystroke full
 *    access to the contextBridge.
 *  * **An unavailable action is a greyed-out item**, never a hidden one. In Swift
 *    a nil closure disables its `Button`; here the renderer pushes a capability
 *    snapshot and the menu is rebuilt from it.
 */
import { Menu, type MenuItemConstructorOptions, shell } from 'electron';

import { MenuCommand } from '../shared/ipc-contract';

const IS_MAC = process.platform === 'darwin';
const DOCS_URL = 'https://docs.runanywhere.ai';

/**
 * What the focused renderer can do right now — the equivalent of SwiftUI's
 * focused-value publish. Items whose capability is false are greyed out.
 */
export interface MenuCapabilities {
  readonly canStopGeneration: boolean;
  readonly canShowChatDetails: boolean;
  readonly canPasteAttachment: boolean;
}

export const DEFAULT_CAPABILITIES: MenuCapabilities = {
  canStopGeneration: false,
  canShowChatDetails: false,
  canPasteAttachment: false,
};

export type MenuCommandSink = (command: MenuCommand) => void;

export function buildAppMenu(send: MenuCommandSink, caps: MenuCapabilities): Menu {
  const item = (
    label: string,
    accelerator: string,
    command: MenuCommand,
    enabled = true,
  ): MenuItemConstructorOptions => ({
    label,
    accelerator,
    enabled,
    click: () => send(command),
  });

  const template: MenuItemConstructorOptions[] = [];

  // On macOS the first submenu IS the application menu. Without it there is no
  // About, no Hide, no Preferences, and no Cmd+Q.
  if (IS_MAC) {
    template.push({
      role: 'appMenu',
      submenu: [
        { role: 'about' },
        { type: 'separator' },
        item('Settings…', 'CmdOrCtrl+,', MenuCommand.OpenSettings),
        { type: 'separator' },
        { role: 'services' },
        { type: 'separator' },
        { role: 'hide' },
        { role: 'hideOthers' },
        { role: 'unhide' },
        { type: 'separator' },
        { role: 'quit' },
      ],
    });
  }

  // Replacing the default File menu drops AppKit's "New" (which would open a
  // second empty window before the SDK is up) and puts conversation creation on
  // Cmd+N, where a chat app belongs.
  template.push({
    label: 'File',
    submenu: [
      item('New Conversation', 'CmdOrCtrl+N', MenuCommand.NewConversation),
      { type: 'separator' },
      item('Import Document…', 'CmdOrCtrl+O', MenuCommand.ImportDocument),
      ...(IS_MAC
        ? []
        : [
            { type: 'separator' as const },
            item('Settings…', 'CmdOrCtrl+,', MenuCommand.OpenSettings),
            { type: 'separator' as const },
            { role: 'quit' as const },
          ]),
    ],
  });

  template.push({
    label: 'Edit',
    submenu: [
      { role: 'undo' },
      { role: 'redo' },
      { type: 'separator' },
      { role: 'cut' },
      { role: 'copy' },
      { role: 'paste' },
      { role: 'selectAll' },
      { type: 'separator' },
      // Shift+Cmd+V, not Cmd+V: the composer is a focused text field and the OS
      // gives it Cmd+V first, so a paste bound there never reaches the chat — and
      // Cmd+V pasting text into the message is what a writer expects anyway.
      // Attaching what is on the clipboard is a different intent.
      item('Paste Attachment', 'Shift+CmdOrCtrl+V', MenuCommand.PasteAttachment, caps.canPasteAttachment),
      ...(IS_MAC ? [{ type: 'separator' as const }, { role: 'startSpeaking' as const }] : []),
    ],
  });

  template.push({
    label: 'Model',
    submenu: [
      item('Load Model…', 'Shift+CmdOrCtrl+L', MenuCommand.OpenModelPicker),
      { type: 'separator' },
      item('Stop Generating', 'CmdOrCtrl+.', MenuCommand.StopGeneration, caps.canStopGeneration),
    ],
  });

  template.push({
    label: 'View',
    submenu: [
      item('Chat', 'CmdOrCtrl+1', MenuCommand.ShowChat),
      item('Models', 'CmdOrCtrl+2', MenuCommand.ShowModels),
      item('Advanced', 'CmdOrCtrl+3', MenuCommand.ShowAdvanced),
      { type: 'separator' },
      item('Chat Details', 'CmdOrCtrl+I', MenuCommand.ShowChatDetails, caps.canShowChatDetails),
      item('Focus Composer', 'Shift+CmdOrCtrl+Return', MenuCommand.FocusComposer),
      { type: 'separator' },
      // SwiftUI gets this from SidebarCommands(); Electron has no such role.
      item('Show/Hide Sidebar', IS_MAC ? 'Control+Command+S' : 'Ctrl+Shift+S', MenuCommand.ToggleSidebar),
      { type: 'separator' },
      { role: 'resetZoom' },
      { role: 'zoomIn' },
      { role: 'zoomOut' },
      { type: 'separator' },
      { role: 'togglefullscreen' },
    ],
  });

  template.push({ role: 'windowMenu' });

  template.push({
    role: 'help',
    submenu: [
      {
        label: 'RunAnywhere Documentation',
        click: () => {
          void shell.openExternal(DOCS_URL);
        },
      },
    ],
  });

  return Menu.buildFromTemplate(template);
}

export function installAppMenu(send: MenuCommandSink, caps: MenuCapabilities = DEFAULT_CAPABILITIES): void {
  Menu.setApplicationMenu(buildAppMenu(send, caps));
}
