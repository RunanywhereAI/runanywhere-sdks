import { WasmWorkerHost } from './WasmWorkerHost';
import { WorkerProtoClient } from './WorkerProtoClient';

export type Capability =
  | 'commons'
  | 'llm'
  | 'vlm'
  | 'stt'
  | 'tts'
  | 'vad'
  | 'embedding'
  | 'rag'
  | 'diffusion'
  | 'structured-output'
  | 'tool-calling'
  | 'lora'
  | 'voice-agent'
  | 'llamacpp'
  | 'onnx'
  | 'sherpa';

interface HostEntry {
  host: WasmWorkerHost;
  client: WorkerProtoClient;
}

const slots = new Map<Capability, HostEntry>();

export function registerHost(capabilities: Capability[], host: WasmWorkerHost): void {
  const entry: HostEntry = { host, client: new WorkerProtoClient(host) };
  for (const cap of capabilities) slots.set(cap, entry);
}

export function unregisterHost(host: WasmWorkerHost): void {
  for (const [cap, entry] of [...slots]) {
    if (entry.host === host) slots.delete(cap);
  }
}

export function clientFor(capability: Capability): WorkerProtoClient | null {
  return slots.get(capability)?.client ?? null;
}

export function hostFor(capability: Capability): WasmWorkerHost | null {
  return slots.get(capability)?.host ?? null;
}

export function allClients(): WorkerProtoClient[] {
  const seen = new Set<WorkerProtoClient>();
  for (const entry of slots.values()) seen.add(entry.client);
  return [...seen];
}

export function hasCapability(capability: Capability): boolean {
  return slots.has(capability);
}

export function clearHosts(): void {
  slots.clear();
}
