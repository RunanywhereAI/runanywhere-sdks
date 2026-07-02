import { InferenceFramework } from '@runanywhere/proto-ts/model_types';
import {
  ToolCallingSessionCreateRequest,
  ToolCallingSessionEvent,
  ToolCallingSessionStepWithResultRequest,
  type ToolCallingSessionCreateRequest as ProtoToolCallingSessionCreateRequest,
  type ToolCallingSessionEvent as ProtoToolCallingSessionEvent,
} from '@runanywhere/proto-ts/tool_calling';
import { clientFor, type Capability } from '../runtime/HostRegistry';
import { Arg, type WorkerProtoClient } from '../runtime/WorkerProtoClient';

const CREATE = 'rac_tool_calling_session_create_proto';
const STEP = 'rac_tool_calling_session_step_with_result_proto';
const DESTROY = 'rac_tool_calling_session_destroy_proto';

function frameworkCapability(framework: InferenceFramework | string | undefined | null): Capability {
  if (typeof framework === 'string') {
    const name = framework.toLowerCase();
    if (name === 'onnx' || name === 'sherpa') return name;
    return 'llamacpp';
  }
  switch (framework) {
    case InferenceFramework.INFERENCE_FRAMEWORK_ONNX: return 'onnx';
    case InferenceFramework.INFERENCE_FRAMEWORK_SHERPA: return 'sherpa';
    default: return 'llamacpp';
  }
}

export interface ToolSession {
  handle: number;
  close(): void;
}

export class ToolCallingAdapter {
  static tryDefaultForFramework(
    framework: InferenceFramework | string | undefined | null,
  ): ToolCallingAdapter | null {
    const client = clientFor(frameworkCapability(framework));
    return client ? new ToolCallingAdapter(client) : null;
  }

  private constructor(private readonly client: WorkerProtoClient) {}

  createSession(
    request: ProtoToolCallingSessionCreateRequest,
    onEvent: (event: ProtoToolCallingSessionEvent) => void,
  ): Promise<ToolSession> {
    const bytes = ToolCallingSessionCreateRequest.encode(request).finish();
    return this.client
      .subscribeWithHandle(
        CREATE,
        { fn: DESTROY, args: [Arg.u64(0)] },
        [Arg.bytes(bytes), Arg.streamCb(false), Arg.num(0), Arg.outU64()],
        ToolCallingSessionEvent,
        onEvent,
      )
      .then(({ handle, unsubscribe }) => ({ handle, close: unsubscribe }));
  }

  stepWithResult(handle: number, toolCallId: string, resultJson: string, error?: string): Promise<number> {
    const bytes = ToolCallingSessionStepWithResultRequest.encode({
      sessionHandle: handle,
      toolCallId,
      resultJson,
      error,
    }).finish();
    return this.client.callRc(STEP, [Arg.bytes(bytes)]);
  }

  destroy(handle: number): Promise<number> {
    return this.client.callRc(DESTROY, [Arg.u64(handle)]);
  }
}
