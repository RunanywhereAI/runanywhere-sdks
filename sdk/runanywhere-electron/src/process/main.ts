// main.ts — runs in the Electron MAIN process. Forks the utilityProcess that
// hosts the native addon and brokers a direct renderer<->utility MessagePort via
// MessageChannelMain, so heavy inference never touches the main or renderer
// process. When the utility exits (crash or kill) it sends 'runanywhere-host-exited'
// to every connected renderer (whose preload then fails all in-flight calls) and
// lazily re-forks on the next connect() — call connect() again to recover.
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
  private readonly connected = new Set<WebContents>();
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
    // Remember so we can notify this renderer if the host later dies. Register the
    // 'destroyed' cleanup only ONCE per webContents — connect() is called on every
    // renderer reload, and adding a listener each time leaks them.
    if (!this.connected.has(webContents)) {
      this.connected.add(webContents);
      webContents.once('destroyed', () => this.connected.delete(webContents));
    }
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
      // Only clear if THIS child is still current — a kill() + connect() may have
      // already forked a replacement, and a late exit from the old child must not
      // drop the new one.
      if (this.child === child) this.child = undefined; // lazily re-fork on the next connect()
      // Tell every connected renderer so its preload rejects in-flight calls
      // instead of hanging forever waiting on a reply that will never come.
      for (const wc of this.connected) {
        if (!wc.isDestroyed()) wc.send('runanywhere-host-exited', code);
      }
      this.onExit?.(code);
    });
    this.child = child;
    return child;
  }
}
