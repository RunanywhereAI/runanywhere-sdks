// main.ts — runs in the Electron MAIN process. Forks the utilityProcess that
// hosts the native addon and brokers a direct renderer<->utility MessagePort via
// MessageChannelMain, so heavy inference never touches the main or renderer
// process. Respawns the utility on crash (a fresh connect() re-forks it).
import * as path from 'path';

import { MessageChannelMain, utilityProcess } from 'electron';
import type { UtilityProcess, WebContents } from 'electron';

export interface RunAnywhereMainOptions {
  /** Path to the compiled utility host (defaults to ./host.js beside this file). */
  hostPath?: string;
  /** Value for RUNANYWHERE_NATIVE_PATH inside the utility (locates the .node). */
  nativePath?: string;
  /** Called when the utility exits (crash or intentional). */
  onExit?: (code: number) => void;
}

export class RunAnywhereMain {
  private child: UtilityProcess | undefined;
  private readonly hostPath: string;
  private readonly nativePath?: string;
  private readonly onExit?: (code: number) => void;

  constructor(opts: RunAnywhereMainOptions = {}) {
    this.hostPath = opts.hostPath ?? path.join(__dirname, 'host.js');
    this.nativePath = opts.nativePath;
    this.onExit = opts.onExit;
  }

  /** Fork the utility if needed and wire `webContents` to it over a fresh port. */
  connect(webContents: WebContents, channel = 'runanywhere-port'): void {
    const child = this.ensureChild();
    const { port1, port2 } = new MessageChannelMain();
    child.postMessage({ type: 'connect' }, [port1]);
    webContents.postMessage(channel, null, [port2]);
  }

  /** Kill the utility (e.g. to exercise crash recovery); it re-forks on connect(). */
  kill(): void {
    this.child?.kill();
    this.child = undefined;
  }

  private ensureChild(): UtilityProcess {
    if (this.child) return this.child;
    const env: Record<string, string | undefined> = { ...process.env };
    if (this.nativePath) env.RUNANYWHERE_NATIVE_PATH = this.nativePath;
    const child = utilityProcess.fork(this.hostPath, [], { env, stdio: 'inherit' });
    child.on('exit', (code) => {
      this.child = undefined; // lazily re-fork on the next connect()
      this.onExit?.(code);
    });
    this.child = child;
    return child;
  }
}
