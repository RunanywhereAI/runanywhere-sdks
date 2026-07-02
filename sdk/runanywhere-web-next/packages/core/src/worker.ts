import { installWorkerServer } from './runtime/WorkerEntry';

installWorkerServer(self as unknown as {
  onmessage: ((ev: MessageEvent) => void) | null;
  postMessage(msg: unknown, transfer?: Transferable[]): void;
});
