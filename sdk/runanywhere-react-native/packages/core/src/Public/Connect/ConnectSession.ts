import { Platform } from 'react-native';
import TcpSocket from 'react-native-tcp-socket';
import {
  ConnectClientFrame,
  ConnectClientHello,
  ConnectClientSessionState,
  ConnectClientStartRequest,
  ConnectHandshakeResponse,
  ConnectHostFrame,
  ConnectPlatform,
  ConnectPlatformPolicy,
  ConnectPlatformPolicyRequest,
  ConnectRoleAvailability,
  ConnectSessionState,
  type ConnectInvocationRequest,
  type ConnectModelDescriptor,
} from '@runanywhere/proto-ts/connect';
import {
  type LLMGenerateRequest,
  type LLMStreamEvent,
} from '@runanywhere/proto-ts/llm_service';
import { requireInitialized } from '../../Foundation/Initialization/InitializedGuard';
import { SDKException } from '../../Foundation/Errors/SDKException';
import { requireNativeModule } from '../../native/NativeRunAnywhereCore';
import {
  arrayBufferToBytes,
  bytesToArrayBuffer,
} from '../../services/ProtoBytes';

export interface ConnectHost {
  id: string;
  displayName: string;
  protocolVersion: number;
}

export interface ConnectModel {
  id: string;
  displayName: string;
  framework: string;
  contextWindow: number;
  supportsStreaming: boolean;
}

export type ConnectStatus =
  | 'idle'
  | 'discovering'
  | 'connecting'
  | 'connected'
  | 'disconnected'
  | 'failed';

export interface ConnectState {
  status: ConnectStatus;
  availableHosts: readonly ConnectHost[];
  connectingHost?: ConnectHost;
  activeHost?: ConnectHost;
  activeModel?: ConnectModel;
  lastDisconnectedHost?: ConnectHost;
  lastDisconnectedModel?: ConnectModel;
  message?: string;
}

type StateListener = (state: ConnectState) => void;

interface ConnectEndpoint {
  id: string;
  displayName: string;
  host: string;
  port: number;
}

const PROTOCOL_VERSION = 1;
const MAX_FRAME_LENGTH = 4 * 1024 * 1024;
type NativeSocket = ReturnType<typeof TcpSocket.createConnection>;

interface ZeroconfService {
  name: string;
  fullName?: string;
  host?: string;
  port: number;
  addresses?: string[];
}

interface ZeroconfInstance {
  scan(
    type: string,
    protocol?: string,
    domain?: string,
    implType?: string
  ): void;
  stop(implType?: string): void;
  removeDeviceListeners(): void;
  on(event: 'resolved', listener: (service: ZeroconfService) => void): void;
  on(event: 'remove', listener: (name: string) => void): void;
  on(event: 'error', listener: (error: Error) => void): void;
}

type ZeroconfConstructor = new () => ZeroconfInstance;

// The package does not publish TypeScript declarations. Keeping the narrow
// adapter type here avoids leaking its untyped event surface into the SDK.
const ZeroconfModule = require('react-native-zeroconf') as {
  default: ZeroconfConstructor;
  ImplType: { DNSSD: string; NSD: string };
};
const Zeroconf = ZeroconfModule.default;
const { ImplType } = ZeroconfModule;

/**
 * React Native client for a language model published by a Connect host.
 *
 * Discovery is intentionally opt-in. C++ commons owns role policy and
 * handshake validation; React Native owns mDNS, framed TCP, heartbeat, and
 * observable UI state.
 */
export class ConnectSession {
  private readonly displayName: string;
  private readonly endpoints = new Map<string, ConnectEndpoint>();
  private readonly listeners = new Set<StateListener>();
  private readonly transport = new ConnectSocket((error) =>
    this.handleDisconnect(error)
  );
  private zeroconf?: ZeroconfInstance;
  private activeSessionId?: string;
  private stateValue: ConnectState = {
    status: 'idle',
    availableHosts: [],
  };

  constructor(displayName = `${Platform.OS} device`) {
    this.displayName = displayName.trim() || `${Platform.OS} device`;
  }

  get state(): ConnectState {
    return this.stateValue;
  }

  subscribe(listener: StateListener): () => void {
    this.listeners.add(listener);
    listener(this.stateValue);
    return () => this.listeners.delete(listener);
  }

  async startBrowsing(): Promise<void> {
    requireInitialized();
    const native = requireNativeModule();
    const policyRequest = ConnectPlatformPolicyRequest.encode({
      platform: ConnectPlatform.CONNECT_PLATFORM_REACT_NATIVE,
    }).finish();
    const policyBytes = await native.connectGetPlatformPolicyProto(
      bytesToArrayBuffer(policyRequest)
    );
    const policy = ConnectPlatformPolicy.decode(
      arrayBufferToBytes(policyBytes)
    );
    if (
      policy.clientRole !==
      ConnectRoleAvailability.CONNECT_ROLE_AVAILABILITY_ENABLED
    ) {
      throw SDKException.networkError(
        'Connect client support is not enabled for React Native'
      );
    }
    if (this.zeroconf) return;

    this.emit({
      ...this.stateValue,
      status:
        this.stateValue.status === 'connected' ? 'connected' : 'discovering',
      message: undefined,
    });
    const zeroconf = new Zeroconf();
    zeroconf.on('resolved', (service) => this.resolveService(service));
    zeroconf.on('remove', (name) => this.removeService(name));
    zeroconf.on('error', (error) => {
      // The active framed TCP channel and heartbeat are authoritative after
      // connection. Losing the discovery browser must not demote a healthy
      // hosted-model session.
      if (this.stateValue.status === 'connected') return;
      this.releaseDiscovery();
      this.emit({
        ...this.stateValue,
        status: 'failed',
        availableHosts: [],
        message: messageFor(error, 'Unable to search the local network'),
      });
    });
    this.zeroconf = zeroconf;
    zeroconf.scan(
      'runanywhere-connect',
      'tcp',
      'local.',
      Platform.OS === 'android' ? ImplType.DNSSD : undefined
    );
  }

  stopBrowsing(): void {
    this.releaseDiscovery();
    this.emit({
      ...this.stateValue,
      status:
        this.stateValue.status === 'discovering'
          ? 'idle'
          : this.stateValue.status,
      availableHosts: [],
    });
  }

  async connect(host: ConnectHost): Promise<void> {
    requireInitialized();
    const endpoint = this.endpoints.get(host.id);
    if (!endpoint) {
      throw SDKException.networkError(
        'The selected host is no longer available'
      );
    }

    this.activeSessionId = undefined;
    this.emit({
      status: 'connecting',
      availableHosts: this.stateValue.availableHosts,
      connectingHost: host,
    });

    try {
      const native = requireNativeModule();
      const request = ConnectClientStartRequest.encode({
        displayName: this.displayName.slice(0, 128),
        platform: ConnectPlatform.CONNECT_PLATFORM_REACT_NATIVE,
        protocolVersion: PROTOCOL_VERSION,
      }).finish();
      const helloBytes = await native.connectClientCreateHelloProto(
        bytesToArrayBuffer(request)
      );
      const hello = ConnectClientHello.decode(arrayBufferToBytes(helloBytes));
      const response = await this.transport.connect(endpoint, hello);
      const responseBytes = ConnectHandshakeResponse.encode(response).finish();
      const sessionBytes = await native.connectClientValidateHostProto(
        bytesToArrayBuffer(responseBytes)
      );
      const session = ConnectClientSessionState.decode(
        arrayBufferToBytes(sessionBytes)
      );
      if (
        session.state !== ConnectSessionState.CONNECT_SESSION_STATE_CONNECTED ||
        !session.sessionId ||
        !session.host ||
        !session.model?.modelId
      ) {
        throw SDKException.networkError(
          session.errorMessage ||
            'The selected host could not provide a language model'
        );
      }

      const activeHost: ConnectHost = {
        id: host.id,
        displayName: session.host.displayName || host.displayName,
        protocolVersion: session.host.protocolVersion,
      };
      const activeModel = modelFromDescriptor(session.model);
      this.activeSessionId = session.sessionId;
      this.emit({
        status: 'connected',
        availableHosts: this.stateValue.availableHosts,
        activeHost,
        activeModel,
      });
      this.transport.startHeartbeat(session.sessionId);
    } catch (error) {
      this.transport.close();
      this.activeSessionId = undefined;
      this.emit({
        status: 'failed',
        availableHosts: this.stateValue.availableHosts,
        message: messageFor(error, 'Unable to connect to the selected host'),
      });
      throw error;
    }
  }

  async *generateStream(
    request: LLMGenerateRequest
  ): AsyncGenerator<LLMStreamEvent> {
    const sessionId = this.activeSessionId;
    const model = this.stateValue.activeModel;
    if (this.stateValue.status !== 'connected' || !sessionId || !model) {
      throw SDKException.networkError(
        'Connect to a host before generating text'
      );
    }
    const requestId = request.requestId || randomId();
    const invocation: ConnectInvocationRequest = {
      sessionId,
      requestId,
      generation: {
        ...request,
        requestId,
        modelId: model.id,
      },
    };
    try {
      yield* this.transport.generate(invocation);
    } catch (error) {
      this.handleDisconnect(error);
      throw error;
    }
  }

  disconnect(): void {
    this.transport.close();
    this.activeSessionId = undefined;
    this.emit({
      status: 'idle',
      availableHosts: this.stateValue.availableHosts,
    });
  }

  stop(): void {
    this.stopBrowsing();
    this.transport.close();
    this.activeSessionId = undefined;
    this.listeners.clear();
    this.stateValue = { status: 'idle', availableHosts: [] };
  }

  private resolveService(service: ZeroconfService): void {
    if (!service.name || service.port < 1 || service.port > 65535) return;
    const address =
      service.addresses?.find((value) =>
        /^\d{1,3}(\.\d{1,3}){3}$/.test(value)
      ) ||
      service.addresses?.[0] ||
      service.host;
    if (!address) return;
    const id = service.fullName || service.name;
    this.endpoints.set(id, {
      id,
      displayName: service.name,
      host: address.replace(/\.$/, ''),
      port: service.port,
    });
    this.publishHosts();
  }

  private releaseDiscovery(): void {
    const zeroconf = this.zeroconf;
    this.zeroconf = undefined;
    this.endpoints.clear();
    if (!zeroconf) return;
    // Remove callbacks first so a native stop error cannot recursively enter
    // the discovery error handler while teardown is in progress.
    zeroconf.removeDeviceListeners();
    zeroconf.stop(Platform.OS === 'android' ? ImplType.DNSSD : undefined);
  }

  private removeService(name: string): void {
    for (const [id, endpoint] of this.endpoints) {
      if (id === name || endpoint.displayName === name)
        this.endpoints.delete(id);
    }
    this.publishHosts();
  }

  private publishHosts(): void {
    const availableHosts = [...this.endpoints.values()]
      .sort((a, b) => a.displayName.localeCompare(b.displayName))
      .map((endpoint) => ({
        id: endpoint.id,
        displayName: endpoint.displayName,
        protocolVersion: PROTOCOL_VERSION,
      }));
    this.emit({ ...this.stateValue, availableHosts });
  }

  private handleDisconnect(error: unknown): void {
    if (this.stateValue.status !== 'connected') return;
    const previous = this.stateValue;
    this.activeSessionId = undefined;
    this.transport.close();
    const hostName = previous.activeHost?.displayName || 'the host';
    this.emit({
      status: 'disconnected',
      availableHosts: previous.availableHosts,
      lastDisconnectedHost: previous.activeHost,
      lastDisconnectedModel: previous.activeModel,
      message:
        messageFor(error, '') ||
        `Connection to ${hostName} ended. The host may have stopped or left the network.`,
    });
  }

  private emit(state: ConnectState): void {
    this.stateValue = state;
    for (const listener of this.listeners) listener(state);
  }
}

class ConnectSocket {
  private socket?: NativeSocket;
  private buffer: number[] = [];
  private frames: Uint8Array[] = [];
  private waiters: Array<{
    resolve: (frame: Uint8Array) => void;
    reject: (error: Error) => void;
  }> = [];
  private heartbeat?: ReturnType<typeof setInterval>;
  private operationActive = false;
  private closed = true;
  private manualClose = false;

  constructor(private readonly onDisconnected: (error: Error) => void) {}

  async connect(
    endpoint: ConnectEndpoint,
    hello: ConnectClientHello
  ): Promise<ConnectHandshakeResponse> {
    this.close();
    this.closed = false;
    this.manualClose = false;
    const socket = await new Promise<NativeSocket>((resolve, reject) => {
      const candidate = TcpSocket.createConnection(
        { host: endpoint.host, port: endpoint.port, connectTimeout: 5000 },
        () => resolve(candidate)
      );
      this.socket = candidate;
      candidate.once('error', reject);
    });
    this.socket = socket;
    socket.setNoDelay(true);
    socket.removeAllListeners('error');
    socket.on('data', (data: Uint8Array | string) => this.receiveData(data));
    socket.on('error', (error: Error) => this.fail(error));
    socket.on('close', () => {
      if (!this.manualClose)
        this.fail(new Error('The connection to the host ended'));
    });
    this.writeFrame(ConnectClientHello.encode(hello).finish());
    return ConnectHandshakeResponse.decode(
      await withTimeout(this.nextFrame(), 5000, 'Connect handshake timed out')
    );
  }

  startHeartbeat(sessionId: string): void {
    if (this.heartbeat) clearInterval(this.heartbeat);
    let sequence = 0;
    this.heartbeat = setInterval(() => {
      if (this.closed || this.operationActive) return;
      void (async () => {
        this.operationActive = true;
        try {
          sequence += 1;
          this.writeFrame(
            ConnectClientFrame.encode({
              heartbeat: { sessionId, sequence },
            }).finish()
          );
          const frame = ConnectHostFrame.decode(
            await withTimeout(
              this.nextFrame(),
              2000,
              'Host heartbeat timed out'
            )
          );
          if (
            frame.heartbeat?.sessionId !== sessionId ||
            frame.heartbeat.sequence !== sequence
          ) {
            throw new Error('The Connect host returned an invalid heartbeat');
          }
        } catch (error) {
          this.fail(asError(error));
        } finally {
          this.operationActive = false;
        }
      })();
    }, 3000);
  }

  async *generate(
    invocation: ConnectInvocationRequest
  ): AsyncGenerator<LLMStreamEvent> {
    if (this.closed || !this.socket) {
      throw SDKException.networkError(
        'The selected host is no longer connected'
      );
    }
    if (this.operationActive) {
      throw SDKException.networkError(
        'Another Connect operation is already running'
      );
    }
    this.operationActive = true;
    try {
      this.writeFrame(ConnectClientFrame.encode({ invocation }).finish());
      while (true) {
        const frame = ConnectHostFrame.decode(await this.nextFrame());
        const event = frame.invocationEvent;
        if (event?.requestId !== invocation.requestId || !event.event) {
          throw SDKException.networkError(
            'The Connect host returned an invalid response'
          );
        }
        yield event.event;
        if (event.event.isFinal) return;
      }
    } finally {
      this.operationActive = false;
    }
  }

  close(): void {
    this.manualClose = true;
    this.closed = true;
    this.operationActive = false;
    if (this.heartbeat) clearInterval(this.heartbeat);
    this.heartbeat = undefined;
    this.socket?.destroy();
    this.socket = undefined;
    this.rejectWaiters(new Error('Connect session closed'));
    this.buffer = [];
    this.frames = [];
  }

  private receiveData(data: Uint8Array | string): void {
    if (typeof data === 'string') return;
    this.buffer.push(...data);
    while (this.buffer.length >= 4) {
      const length =
        ((this.buffer[0] << 24) >>> 0) |
        (this.buffer[1] << 16) |
        (this.buffer[2] << 8) |
        this.buffer[3];
      if (length < 1 || length > MAX_FRAME_LENGTH) {
        this.fail(new Error('The Connect host returned an invalid frame size'));
        return;
      }
      if (this.buffer.length < length + 4) return;
      const frame = Uint8Array.from(this.buffer.slice(4, length + 4));
      this.buffer.splice(0, length + 4);
      const waiter = this.waiters.shift();
      if (waiter) waiter.resolve(frame);
      else this.frames.push(frame);
    }
  }

  private writeFrame(payload: Uint8Array): void {
    if (
      !this.socket ||
      payload.length < 1 ||
      payload.length > MAX_FRAME_LENGTH
    ) {
      throw SDKException.networkError('Connect frame size is invalid');
    }
    const frame = new Uint8Array(payload.length + 4);
    const view = new DataView(frame.buffer);
    view.setUint32(0, payload.length, false);
    frame.set(payload, 4);
    this.socket.write(frame);
  }

  private nextFrame(): Promise<Uint8Array> {
    const frame = this.frames.shift();
    if (frame) return Promise.resolve(frame);
    if (this.closed) return Promise.reject(new Error('Connect session closed'));
    return new Promise((resolve, reject) =>
      this.waiters.push({ resolve, reject })
    );
  }

  private fail(error: Error): void {
    if (this.closed) return;
    this.closed = true;
    if (this.heartbeat) clearInterval(this.heartbeat);
    this.heartbeat = undefined;
    this.operationActive = false;
    this.rejectWaiters(error);
    this.socket?.destroy();
    this.socket = undefined;
    this.onDisconnected(error);
  }

  private rejectWaiters(error: Error): void {
    const waiters = this.waiters.splice(0);
    for (const waiter of waiters) waiter.reject(error);
  }
}

function modelFromDescriptor(model: ConnectModelDescriptor): ConnectModel {
  return {
    id: model.modelId,
    displayName: model.displayName,
    framework: model.framework,
    contextWindow: model.contextWindow,
    supportsStreaming: model.supportsStreaming,
  };
}

function randomId(): string {
  return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
}

function asError(error: unknown): Error {
  return error instanceof Error ? error : new Error(String(error));
}

function messageFor(error: unknown, fallback: string): string {
  const value =
    error instanceof Error ? error.message.trim() : String(error).trim();
  return value || fallback;
}

async function withTimeout<T>(
  promise: Promise<T>,
  milliseconds: number,
  message: string
): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([
      promise,
      new Promise<T>((_, reject) => {
        timer = setTimeout(
          () => reject(SDKException.timeout(message)),
          milliseconds
        );
      }),
    ]);
  } finally {
    if (timer) clearTimeout(timer);
  }
}
