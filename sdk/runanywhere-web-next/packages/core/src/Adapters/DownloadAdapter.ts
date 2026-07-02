import {
  DownloadCancelRequest,
  DownloadCancelResult,
  DownloadPlanRequest,
  DownloadPlanResult,
  DownloadProgress,
  DownloadResumeRequest,
  DownloadResumeResult,
  DownloadStartRequest,
  DownloadStartResult,
  DownloadSubscribeRequest,
  type DownloadCancelRequest as ProtoDownloadCancelRequest,
  type DownloadCancelResult as ProtoDownloadCancelResult,
  type DownloadPlanRequest as ProtoDownloadPlanRequest,
  type DownloadPlanResult as ProtoDownloadPlanResult,
  type DownloadProgress as ProtoDownloadProgress,
  type DownloadResumeRequest as ProtoDownloadResumeRequest,
  type DownloadResumeResult as ProtoDownloadResumeResult,
  type DownloadStartRequest as ProtoDownloadStartRequest,
  type DownloadStartResult as ProtoDownloadStartResult,
  type DownloadSubscribeRequest as ProtoDownloadSubscribeRequest,
} from '@runanywhere/proto-ts/download_service';
import { InferenceFramework } from '@runanywhere/proto-ts/model_types';
import { clientFor, type Capability } from '../runtime/HostRegistry';
import { Arg, type WorkerProtoClient } from '../runtime/WorkerProtoClient';

const SET_PROGRESS_CALLBACK = 'rac_download_set_progress_proto_callback';

export type ProtoDownloadProgressHandler = (progress: ProtoDownloadProgress) => void;

function frameworkCapability(framework: InferenceFramework | string): Capability | null {
  if (typeof framework === 'string') {
    const name = framework.toLowerCase();
    if (name === 'llamacpp' || name === 'onnx' || name === 'sherpa') return name;
    return null;
  }
  switch (framework) {
    case InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP: return 'llamacpp';
    case InferenceFramework.INFERENCE_FRAMEWORK_ONNX: return 'onnx';
    case InferenceFramework.INFERENCE_FRAMEWORK_SHERPA: return 'sherpa';
    case InferenceFramework.INFERENCE_FRAMEWORK_PIPER_TTS: return 'sherpa';
    default: return null;
  }
}

export class DownloadAdapter {
  static tryDefault(): DownloadAdapter | null {
    const client = clientFor('commons');
    return client ? new DownloadAdapter(client) : null;
  }

  static tryDefaultForFramework(
    framework: InferenceFramework | string | undefined | null,
  ): DownloadAdapter | null {
    if (framework !== undefined && framework !== null && framework !== '') {
      const cap = frameworkCapability(framework);
      const client = cap ? clientFor(cap) : null;
      if (client) return new DownloadAdapter(client);
    }
    return DownloadAdapter.tryDefault();
  }

  constructor(private readonly client: WorkerProtoClient) {}

  plan(request: ProtoDownloadPlanRequest): Promise<ProtoDownloadPlanResult | null> {
    return this.client.callProto(
      'rac_download_plan_proto',
      [Arg.bytes(DownloadPlanRequest.encode(request).finish()), Arg.outProto()],
      DownloadPlanResult,
    );
  }

  start(request: ProtoDownloadStartRequest): Promise<ProtoDownloadStartResult | null> {
    return this.client.callProto(
      'rac_download_start_proto',
      [Arg.bytes(DownloadStartRequest.encode(request).finish()), Arg.outProto()],
      DownloadStartResult,
    );
  }

  cancel(request: ProtoDownloadCancelRequest): Promise<ProtoDownloadCancelResult | null> {
    return this.client.callProto(
      'rac_download_cancel_proto',
      [Arg.bytes(DownloadCancelRequest.encode(request).finish()), Arg.outProto()],
      DownloadCancelResult,
    );
  }

  resume(request: ProtoDownloadResumeRequest): Promise<ProtoDownloadResumeResult | null> {
    return this.client.callProto(
      'rac_download_resume_proto',
      [Arg.bytes(DownloadResumeRequest.encode(request).finish()), Arg.outProto()],
      DownloadResumeResult,
    );
  }

  poll(request: ProtoDownloadSubscribeRequest): Promise<ProtoDownloadProgress | null> {
    return this.client.callProto(
      'rac_download_progress_poll_proto',
      [Arg.bytes(DownloadSubscribeRequest.encode(request).finish()), Arg.outProto()],
      DownloadProgress,
    );
  }

  setProgressHandler(handler: ProtoDownloadProgressHandler): () => void {
    return this.client.subscribe(
      SET_PROGRESS_CALLBACK,
      { fn: SET_PROGRESS_CALLBACK, args: [Arg.num(0), Arg.num(0)] },
      [Arg.streamCb(false), Arg.num(0)],
      DownloadProgress,
      handler,
    );
  }
}
