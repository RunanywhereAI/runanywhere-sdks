import { WasmWorkerServer, type PostResponse } from './WasmWorkerServer';
import type { SecureStore } from './PlatformAdapter';
import type { WorkerRequest } from './WorkerProtocol';

interface WorkerScope {
  onmessage: ((ev: MessageEvent) => void) | null;
  postMessage(msg: unknown, transfer?: Transferable[]): void;
}

export function installWorkerServer(scope: WorkerScope, secureStore?: SecureStore): void {
  const post: PostResponse = (msg, transfer) => scope.postMessage(msg, transfer ?? []);
  const server = new WasmWorkerServer(post, secureStore);
  scope.onmessage = (ev: MessageEvent) => { void server.handle(ev.data as WorkerRequest); };
}
