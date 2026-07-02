import { installWorkerServer } from '@runanywhere/web/internal';

installWorkerServer(self as unknown as {
  onmessage: ((ev: MessageEvent) => void) | null;
  postMessage(msg: unknown, transfer?: Transferable[]): void;
});
