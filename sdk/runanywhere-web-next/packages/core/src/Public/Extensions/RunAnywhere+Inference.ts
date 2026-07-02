import { allClients } from '../../runtime/HostRegistry';
import { Arg } from '../../runtime/WorkerProtoClient';
import { RunAnywhereSDK } from '../RunAnywhere';

declare module '../RunAnywhere' {
  interface RunAnywhereSDK {
    /**
     * Set the CPU thread count for on-device inference backends (ONNX Runtime
     * thread pool used by Sherpa STT/TTS). Broadcast to every worker. Takes
     * effect on the NEXT model load — call it before loading. `<= 0` = auto
     * (hardware_concurrency). Small speech models are usually fastest at 1-2.
     */
    setInferenceThreads(numThreads: number): Promise<void>;
  }
}

RunAnywhereSDK.prototype.setInferenceThreads = async function (this: RunAnywhereSDK, numThreads) {
  const n = Number.isFinite(numThreads) ? Math.max(0, Math.trunc(numThreads)) : 0;
  await Promise.all(allClients().map((client) => client.callRc('rac_set_inference_threads', [Arg.num(n)])));
};
