import {
  LLMGenerateRequest,
  LLMStreamEvent,
  type LLMGenerateRequest as ProtoLLMGenerateRequest,
  type LLMStreamEvent as ProtoLLMStreamEvent,
} from '@runanywhere/proto-ts/llm_service';
import {
  LLMGenerationResult,
  type LLMGenerationResult as ProtoLLMGenerationResult,
} from '@runanywhere/proto-ts/llm_options';
import {
  STTOptions,
  STTOutput,
  STTPartialResult,
  type STTOptions as ProtoSTTOptions,
  type STTOutput as ProtoSTTOutput,
  type STTPartialResult as ProtoSTTPartialResult,
} from '@runanywhere/proto-ts/stt_options';
import {
  TTSOptions,
  TTSOutput,
  TTSVoiceInfo,
  type TTSOptions as ProtoTTSOptions,
  type TTSOutput as ProtoTTSOutput,
  type TTSVoiceInfo as ProtoTTSVoiceInfo,
} from '@runanywhere/proto-ts/tts_options';
import {
  SpeechActivityEvent,
  VADConfiguration,
  VADOptions,
  VADResult,
  VADStatistics,
  type SpeechActivityEvent as ProtoSpeechActivityEvent,
  type VADConfiguration as ProtoVADConfiguration,
  type VADOptions as ProtoVADOptions,
  type VADResult as ProtoVADResult,
  type VADStatistics as ProtoVADStatistics,
} from '@runanywhere/proto-ts/vad_options';
import {
  VLMGenerationOptions,
  VLMImage,
  VLMResult,
  type VLMGenerationOptions as ProtoVLMGenerationOptions,
  type VLMImage as ProtoVLMImage,
  type VLMResult as ProtoVLMResult,
} from '@runanywhere/proto-ts/vlm_options';
import {
  EmbeddingsRequest,
  EmbeddingsResult,
  type EmbeddingsRequest as ProtoEmbeddingsRequest,
  type EmbeddingsResult as ProtoEmbeddingsResult,
} from '@runanywhere/proto-ts/embeddings_options';
import {
  DiffusionGenerationOptions,
  DiffusionProgress,
  DiffusionResult,
  type DiffusionGenerationOptions as ProtoDiffusionGenerationOptions,
  type DiffusionProgress as ProtoDiffusionProgress,
  type DiffusionResult as ProtoDiffusionResult,
} from '@runanywhere/proto-ts/diffusion_options';
import {
  RAGConfiguration,
  RAGDocument,
  RAGQueryOptions,
  RAGResult,
  RAGStatistics,
  type RAGConfiguration as ProtoRAGConfiguration,
  type RAGDocument as ProtoRAGDocument,
  type RAGQueryOptions as ProtoRAGQueryOptions,
  type RAGResult as ProtoRAGResult,
  type RAGStatistics as ProtoRAGStatistics,
} from '@runanywhere/proto-ts/rag';
import {
  LoRAAdapterConfig,
  LoRAAdapterInfo,
  LoraAdapterCatalogEntry,
  LoraCompatibilityResult,
  type LoRAAdapterConfig as ProtoLoRAAdapterConfig,
  type LoRAAdapterInfo as ProtoLoRAAdapterInfo,
  type LoraAdapterCatalogEntry as ProtoLoraAdapterCatalogEntry,
  type LoraCompatibilityResult as ProtoLoraCompatibilityResult,
} from '@runanywhere/proto-ts/lora_options';
import {
  VoiceAgentComposeConfig,
  VoiceAgentResult,
  type VoiceAgentComposeConfig as ProtoVoiceAgentComposeConfig,
  type VoiceAgentResult as ProtoVoiceAgentResult,
} from '@runanywhere/proto-ts/voice_agent_service';
import {
  VoiceAgentComponentStates,
  type VoiceAgentComponentStates as ProtoVoiceAgentComponentStates,
} from '@runanywhere/proto-ts/voice_events';
import {
  SDKEvent,
  type SDKEvent as ProtoSDKEvent,
} from '@runanywhere/proto-ts/sdk_events';
import { SDKException } from '../Foundation/SDKException';
import { SDKLogger } from '../Foundation/SDKLogger';
import {
  formatRacResult,
  ProtoWasmBridge,
  type ProtoCodec,
  type ProtoWasmModule,
} from '../runtime/ProtoWasm';

const logger = new SDKLogger('ModalityProtoAdapter');

type CallbackSignature = 'viii' | 'iiii';
type CallbackResult = void | number;
type CallbackFn = (...args: number[]) => CallbackResult;

export interface ModalityProtoModule extends ProtoWasmModule {
  HEAPF32?: Float32Array;
  addFunction?(fn: CallbackFn, signature: string): number;
  removeFunction?(ptr: number): void;

  _rac_llm_generate_proto?(
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  _rac_llm_generate_stream_proto?(
    requestBytes: number,
    requestSize: number,
    callbackPtr: number,
    userData: number,
  ): number;
  _rac_llm_cancel_proto?(outEvent: number): number;

  _rac_stt_component_transcribe_proto?(
    handle: number,
    audioData: number,
    audioSize: number,
    optionsBytes: number,
    optionsSize: number,
    outResult: number,
  ): number;
  _rac_stt_component_transcribe_stream_proto?(
    handle: number,
    audioData: number,
    audioSize: number,
    optionsBytes: number,
    optionsSize: number,
    callbackPtr: number,
    userData: number,
  ): number;

  _rac_tts_component_list_voices_proto?(
    handle: number,
    callbackPtr: number,
    userData: number,
  ): number;
  _rac_tts_component_synthesize_proto?(
    handle: number,
    text: number,
    optionsBytes: number,
    optionsSize: number,
    outResult: number,
  ): number;
  _rac_tts_component_synthesize_stream_proto?(
    handle: number,
    text: number,
    optionsBytes: number,
    optionsSize: number,
    callbackPtr: number,
    userData: number,
  ): number;

  _rac_vad_component_configure_proto?(
    handle: number,
    configBytes: number,
    configSize: number,
  ): number;
  _rac_vad_component_process_proto?(
    handle: number,
    samples: number,
    numSamples: number,
    optionsBytes: number,
    optionsSize: number,
    outResult: number,
  ): number;
  _rac_vad_component_get_statistics_proto?(
    handle: number,
    outResult: number,
  ): number;
  _rac_vad_component_set_activity_proto_callback?(
    handle: number,
    callbackPtr: number,
    userData: number,
  ): number;

  _rac_voice_agent_initialize_proto?(
    handle: number,
    configBytes: number,
    configSize: number,
    outComponentStates: number,
  ): number;
  _rac_voice_agent_component_states_proto?(
    handle: number,
    outComponentStates: number,
  ): number;
  _rac_voice_agent_process_voice_turn_proto?(
    handle: number,
    audioData: number,
    audioSize: number,
    outResult: number,
  ): number;

  _rac_vlm_process_proto?(
    handle: number,
    imageBytes: number,
    imageSize: number,
    optionsBytes: number,
    optionsSize: number,
    outResult: number,
  ): number;
  _rac_vlm_process_stream_proto?(
    handle: number,
    imageBytes: number,
    imageSize: number,
    optionsBytes: number,
    optionsSize: number,
    callbackPtr: number,
    userData: number,
    outResult: number,
  ): number;
  _rac_vlm_cancel_proto?(handle: number): number;

  _rac_embeddings_embed_batch_proto?(
    handle: number,
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;

  _rac_diffusion_generate_proto?(
    handle: number,
    optionsBytes: number,
    optionsSize: number,
    outResult: number,
  ): number;
  _rac_diffusion_generate_with_progress_proto?(
    handle: number,
    optionsBytes: number,
    optionsSize: number,
    callbackPtr: number,
    userData: number,
    outResult: number,
  ): number;
  _rac_diffusion_cancel_proto?(handle: number): number;

  _rac_rag_session_create_proto?(
    configBytes: number,
    configSize: number,
    outSession: number,
  ): number;
  _rac_rag_session_destroy_proto?(session: number): void;
  _rac_rag_ingest_proto?(
    session: number,
    documentBytes: number,
    documentSize: number,
    outStats: number,
  ): number;
  _rac_rag_query_proto?(
    session: number,
    queryBytes: number,
    querySize: number,
    outResult: number,
  ): number;
  _rac_rag_clear_proto?(session: number, outStats: number): number;
  _rac_rag_stats_proto?(session: number, outStats: number): number;

  _rac_lora_register_proto?(
    registry: number,
    entryBytes: number,
    entrySize: number,
    outEntry: number,
  ): number;
  _rac_lora_compatibility_proto?(
    llmComponent: number,
    configBytes: number,
    configSize: number,
    outResult: number,
  ): number;
  _rac_lora_load_proto?(
    llmComponent: number,
    configBytes: number,
    configSize: number,
    outInfo: number,
  ): number;
  _rac_lora_remove_proto?(
    llmComponent: number,
    configBytes: number,
    configSize: number,
    outInfo: number,
  ): number;
  _rac_lora_clear_proto?(llmComponent: number, outInfo: number): number;
}

export type ProtoEventHandler<T> = (event: T) => void;

let defaultModule: ModalityProtoModule | null = null;
const vadActivityCallbackPtrs = new Map<number, number>();

export class ModalityProtoAdapter {
  static setDefaultModule(module: ModalityProtoModule): void {
    defaultModule = module;
  }

  static clearDefaultModule(): void {
    if (defaultModule) {
      for (const [handle, callbackPtr] of vadActivityCallbackPtrs) {
        defaultModule._rac_vad_component_set_activity_proto_callback?.(handle, 0, 0);
        defaultModule.removeFunction?.(callbackPtr);
      }
    }
    vadActivityCallbackPtrs.clear();
    defaultModule = null;
  }

  static tryDefault(): ModalityProtoAdapter | null {
    return defaultModule ? new ModalityProtoAdapter(defaultModule) : null;
  }

  constructor(private readonly module: ModalityProtoModule) {}

  llm(): LLMProtoAdapter {
    return new LLMProtoAdapter(this.module);
  }

  stt(): STTProtoAdapter {
    return new STTProtoAdapter(this.module);
  }

  tts(): TTSProtoAdapter {
    return new TTSProtoAdapter(this.module);
  }

  vad(): VADProtoAdapter {
    return new VADProtoAdapter(this.module);
  }

  voiceAgent(): VoiceAgentProtoAdapter {
    return new VoiceAgentProtoAdapter(this.module);
  }

  vlm(): VLMProtoAdapter {
    return new VLMProtoAdapter(this.module);
  }

  embeddings(): EmbeddingsProtoAdapter {
    return new EmbeddingsProtoAdapter(this.module);
  }

  diffusion(): DiffusionProtoAdapter {
    return new DiffusionProtoAdapter(this.module);
  }

  rag(): RAGProtoAdapter {
    return new RAGProtoAdapter(this.module);
  }

  lora(): LoRAProtoAdapter {
    return new LoRAProtoAdapter(this.module);
  }
}

export class LLMProtoAdapter {
  static tryDefault(): LLMProtoAdapter | null {
    return ModalityProtoAdapter.tryDefault()?.llm() ?? null;
  }

  constructor(private readonly module: ModalityProtoModule) {}

  supportsProtoLLM(): boolean {
    return this.missingExports([
      '_rac_llm_generate_proto',
      '_rac_llm_generate_stream_proto',
      '_rac_llm_cancel_proto',
    ]).length === 0;
  }

  generate(request: ProtoLLMGenerateRequest): ProtoLLMGenerationResult | null {
    if (!this.ensureExports('llm.generate', ['_rac_llm_generate_proto'])) return null;
    return this.bridge().withEncodedRequest(
      request,
      LLMGenerateRequest,
      LLMGenerationResult,
      (requestPtr, requestSize, outResult) => (
        this.module._rac_llm_generate_proto!(requestPtr, requestSize, outResult)
      ),
      'rac_llm_generate_proto',
    );
  }

  generateStream(request: ProtoLLMGenerateRequest): AsyncIterable<ProtoLLMStreamEvent> {
    this.requireExports('llm.generateStream', ['_rac_llm_generate_stream_proto']);
    const encoded = LLMGenerateRequest.encode({ ...request, streamingEnabled: true }).finish();
    return streamCallback(
      this.module,
      LLMStreamEvent,
      'rac_llm_generate_stream_proto',
      (callbackPtr) => (
        this.bridge().withHeapBytes(encoded, (requestPtr, requestSize) => (
          this.module._rac_llm_generate_stream_proto!(
            requestPtr,
            requestSize,
            callbackPtr,
            0,
          )
        ))
      ),
      (event) => event.isFinal,
      () => {
        this.cancel();
      },
    );
  }

  cancel(): ProtoSDKEvent | null {
    if (!this.ensureExports('llm.cancel', ['_rac_llm_cancel_proto'])) return null;
    return this.bridge().callResultProto(
      SDKEvent,
      (outEvent) => this.module._rac_llm_cancel_proto!(outEvent),
      'rac_llm_cancel_proto',
    );
  }

  private bridge(): ProtoWasmBridge {
    return new ProtoWasmBridge(this.module, logger);
  }

  private ensureExports(operation: string, required: Array<keyof ModalityProtoModule>): boolean {
    return ensureExports(this.module, operation, required);
  }

  private requireExports(operation: string, required: Array<keyof ModalityProtoModule>): void {
    requireExports(this.module, operation, required);
  }

  private missingExports(required: Array<keyof ModalityProtoModule>): string[] {
    return missingExports(this.module, required);
  }
}

export class STTProtoAdapter {
  static tryDefault(): STTProtoAdapter | null {
    return ModalityProtoAdapter.tryDefault()?.stt() ?? null;
  }

  constructor(private readonly module: ModalityProtoModule) {}

  supportsProtoSTT(): boolean {
    return missingExports(this.module, [
      '_rac_stt_component_transcribe_proto',
      '_rac_stt_component_transcribe_stream_proto',
    ]).length === 0;
  }

  transcribe(
    handle: number,
    audioData: Uint8Array,
    options: ProtoSTTOptions,
  ): ProtoSTTOutput | null {
    if (!ensureExports(this.module, 'stt.transcribe', ['_rac_stt_component_transcribe_proto'])) {
      return null;
    }
    const optionsBytes = STTOptions.encode(options).finish();
    const bridge = this.bridge();
    return bridge.withHeapBytes(audioData, (audioPtr, audioSize) => (
      bridge.withHeapBytes(optionsBytes, (optionsPtr, optionsSize) => (
        bridge.callResultProto(
          STTOutput,
          (outResult) => this.module._rac_stt_component_transcribe_proto!(
            handle,
            audioPtr,
            audioSize,
            optionsPtr,
            optionsSize,
            outResult,
          ),
          'rac_stt_component_transcribe_proto',
        )
      ))
    ));
  }

  transcribeStream(
    handle: number,
    audioData: Uint8Array,
    options: ProtoSTTOptions,
  ): AsyncIterable<ProtoSTTPartialResult> {
    requireExports(this.module, 'stt.transcribeStream', [
      '_rac_stt_component_transcribe_stream_proto',
    ]);
    const optionsBytes = STTOptions.encode(options).finish();
    return streamCallback(
      this.module,
      STTPartialResult,
      'rac_stt_component_transcribe_stream_proto',
      (callbackPtr) => this.bridge().withHeapBytes(audioData, (audioPtr, audioSize) => (
        this.bridge().withHeapBytes(optionsBytes, (optionsPtr, optionsSize) => (
          this.module._rac_stt_component_transcribe_stream_proto!(
            handle,
            audioPtr,
            audioSize,
            optionsPtr,
            optionsSize,
            callbackPtr,
            0,
          )
        ))
      )),
      (event) => event.isFinal,
    );
  }

  private bridge(): ProtoWasmBridge {
    return new ProtoWasmBridge(this.module, logger);
  }
}

export class TTSProtoAdapter {
  static tryDefault(): TTSProtoAdapter | null {
    return ModalityProtoAdapter.tryDefault()?.tts() ?? null;
  }

  constructor(private readonly module: ModalityProtoModule) {}

  supportsProtoTTS(): boolean {
    return missingExports(this.module, [
      '_rac_tts_component_list_voices_proto',
      '_rac_tts_component_synthesize_proto',
      '_rac_tts_component_synthesize_stream_proto',
    ]).length === 0;
  }

  listVoices(handle: number): ProtoTTSVoiceInfo[] | null {
    if (!ensureExports(this.module, 'tts.listVoices', ['_rac_tts_component_list_voices_proto'])) {
      return null;
    }
    return collectCallback(
      this.module,
      TTSVoiceInfo,
      'rac_tts_component_list_voices_proto',
      (callbackPtr) => this.module._rac_tts_component_list_voices_proto!(handle, callbackPtr, 0),
    );
  }

  synthesize(
    handle: number,
    text: string,
    options: ProtoTTSOptions,
  ): ProtoTTSOutput | null {
    if (!ensureExports(this.module, 'tts.synthesize', ['_rac_tts_component_synthesize_proto'])) {
      return null;
    }
    const bridge = this.bridge();
    const optionsBytes = TTSOptions.encode(options).finish();
    const textPtr = bridge.allocUtf8(text);
    if (!textPtr) return null;
    try {
      return bridge.withHeapBytes(optionsBytes, (optionsPtr, optionsSize) => (
        bridge.callResultProto(
          TTSOutput,
          (outResult) => this.module._rac_tts_component_synthesize_proto!(
            handle,
            textPtr,
            optionsPtr,
            optionsSize,
            outResult,
          ),
          'rac_tts_component_synthesize_proto',
        )
      ));
    } finally {
      bridge.free(textPtr);
    }
  }

  synthesizeStream(
    handle: number,
    text: string,
    options: ProtoTTSOptions,
  ): AsyncIterable<ProtoTTSOutput> {
    requireExports(this.module, 'tts.synthesizeStream', [
      '_rac_tts_component_synthesize_stream_proto',
    ]);
    const optionsBytes = TTSOptions.encode(options).finish();
    return streamCallback(
      this.module,
      TTSOutput,
      'rac_tts_component_synthesize_stream_proto',
      (callbackPtr) => {
        const bridge = this.bridge();
        const textPtr = bridge.allocUtf8(text);
        if (!textPtr) return -903;
        try {
          return bridge.withHeapBytes(optionsBytes, (optionsPtr, optionsSize) => (
            this.module._rac_tts_component_synthesize_stream_proto!(
              handle,
              textPtr,
              optionsPtr,
              optionsSize,
              callbackPtr,
              0,
            )
          ));
        } finally {
          bridge.free(textPtr);
        }
      },
    );
  }

  private bridge(): ProtoWasmBridge {
    return new ProtoWasmBridge(this.module, logger);
  }
}

export class VADProtoAdapter {
  static tryDefault(): VADProtoAdapter | null {
    return ModalityProtoAdapter.tryDefault()?.vad() ?? null;
  }

  constructor(private readonly module: ModalityProtoModule) {}

  supportsProtoVAD(): boolean {
    return missingExports(this.module, [
      '_rac_vad_component_configure_proto',
      '_rac_vad_component_process_proto',
      '_rac_vad_component_get_statistics_proto',
      '_rac_vad_component_set_activity_proto_callback',
    ]).length === 0;
  }

  configure(handle: number, config: ProtoVADConfiguration): boolean {
    if (!ensureExports(this.module, 'vad.configure', ['_rac_vad_component_configure_proto'])) {
      return false;
    }
    const bytes = VADConfiguration.encode(config).finish();
    const rc = this.bridge().withHeapBytes(bytes, (ptr, size) => (
      this.module._rac_vad_component_configure_proto!(handle, ptr, size)
    ));
    if (rc !== 0) logger.warning(`rac_vad_component_configure_proto returned ${formatRacResult(rc)}`);
    return rc === 0;
  }

  process(
    handle: number,
    samples: Float32Array,
    options: ProtoVADOptions,
  ): ProtoVADResult | null {
    if (!ensureExports(this.module, 'vad.process', ['_rac_vad_component_process_proto'])) {
      return null;
    }
    const sampleBytes = new Uint8Array(samples.buffer, samples.byteOffset, samples.byteLength);
    const optionsBytes = VADOptions.encode(options).finish();
    const bridge = this.bridge();
    return bridge.withHeapBytes(sampleBytes, (samplesPtr) => (
      bridge.withHeapBytes(optionsBytes, (optionsPtr, optionsSize) => (
        bridge.callResultProto(
          VADResult,
          (outResult) => this.module._rac_vad_component_process_proto!(
            handle,
            samplesPtr,
            samples.length,
            optionsPtr,
            optionsSize,
            outResult,
          ),
          'rac_vad_component_process_proto',
        )
      ))
    ));
  }

  statistics(handle: number): ProtoVADStatistics | null {
    if (!ensureExports(this.module, 'vad.statistics', ['_rac_vad_component_get_statistics_proto'])) {
      return null;
    }
    return this.bridge().callResultProto(
      VADStatistics,
      (outResult) => this.module._rac_vad_component_get_statistics_proto!(handle, outResult),
      'rac_vad_component_get_statistics_proto',
    );
  }

  setActivityHandler(
    handle: number,
    handler: ProtoEventHandler<ProtoSpeechActivityEvent> | null,
  ): boolean {
    if (!ensureExports(this.module, 'vad.setActivityHandler', [
      '_rac_vad_component_set_activity_proto_callback',
    ])) {
      return false;
    }
    if (!this.module.addFunction || !this.module.removeFunction || !this.module.HEAPU8) {
      logger.warning('vad.setActivityHandler: module missing callback/heap helpers');
      return false;
    }

    const previousPtr = vadActivityCallbackPtrs.get(handle);
    if (previousPtr) {
      this.module._rac_vad_component_set_activity_proto_callback!(handle, 0, 0);
      this.module.removeFunction(previousPtr);
      vadActivityCallbackPtrs.delete(handle);
    }
    if (!handler) return true;

    const callbackPtr = this.module.addFunction((bytesPtr: number, size: number) => {
      if (!bytesPtr || size <= 0) return;
      const bytes = this.module.HEAPU8!.slice(bytesPtr, bytesPtr + size);
      handler(SpeechActivityEvent.decode(bytes));
    }, 'viii');
    const rc = this.module._rac_vad_component_set_activity_proto_callback!(handle, callbackPtr, 0);
    if (rc !== 0) {
      this.module.removeFunction(callbackPtr);
      logger.warning(`rac_vad_component_set_activity_proto_callback returned ${formatRacResult(rc)}`);
      return false;
    }
    vadActivityCallbackPtrs.set(handle, callbackPtr);
    return true;
  }

  private bridge(): ProtoWasmBridge {
    return new ProtoWasmBridge(this.module, logger);
  }
}

export class VoiceAgentProtoAdapter {
  static tryDefault(): VoiceAgentProtoAdapter | null {
    return ModalityProtoAdapter.tryDefault()?.voiceAgent() ?? null;
  }

  constructor(private readonly module: ModalityProtoModule) {}

  supportsProtoVoiceAgent(): boolean {
    return missingExports(this.module, [
      '_rac_voice_agent_initialize_proto',
      '_rac_voice_agent_component_states_proto',
      '_rac_voice_agent_process_voice_turn_proto',
    ]).length === 0;
  }

  initialize(
    handle: number,
    config: ProtoVoiceAgentComposeConfig,
  ): ProtoVoiceAgentComponentStates | null {
    if (!ensureExports(this.module, 'voiceAgent.initialize', [
      '_rac_voice_agent_initialize_proto',
    ])) {
      return null;
    }
    return this.bridge().withEncodedRequest(
      config,
      VoiceAgentComposeConfig,
      VoiceAgentComponentStates,
      (configPtr, configSize, outResult) => (
        this.module._rac_voice_agent_initialize_proto!(
          handle,
          configPtr,
          configSize,
          outResult,
        )
      ),
      'rac_voice_agent_initialize_proto',
    );
  }

  componentStates(handle: number): ProtoVoiceAgentComponentStates | null {
    if (!ensureExports(this.module, 'voiceAgent.componentStates', [
      '_rac_voice_agent_component_states_proto',
    ])) {
      return null;
    }
    return this.bridge().callResultProto(
      VoiceAgentComponentStates,
      (outResult) => this.module._rac_voice_agent_component_states_proto!(handle, outResult),
      'rac_voice_agent_component_states_proto',
    );
  }

  processVoiceTurn(handle: number, audioData: Uint8Array): ProtoVoiceAgentResult | null {
    if (!ensureExports(this.module, 'voiceAgent.processVoiceTurn', [
      '_rac_voice_agent_process_voice_turn_proto',
    ])) {
      return null;
    }
    const bridge = this.bridge();
    return bridge.withHeapBytes(audioData, (audioPtr, audioSize) => (
      bridge.callResultProto(
        VoiceAgentResult,
        (outResult) => this.module._rac_voice_agent_process_voice_turn_proto!(
          handle,
          audioPtr,
          audioSize,
          outResult,
        ),
        'rac_voice_agent_process_voice_turn_proto',
      )
    ));
  }

  private bridge(): ProtoWasmBridge {
    return new ProtoWasmBridge(this.module, logger);
  }
}

export class VLMProtoAdapter {
  static tryDefault(): VLMProtoAdapter | null {
    return ModalityProtoAdapter.tryDefault()?.vlm() ?? null;
  }

  constructor(private readonly module: ModalityProtoModule) {}

  supportsProtoVLM(): boolean {
    return missingExports(this.module, [
      '_rac_vlm_process_proto',
      '_rac_vlm_process_stream_proto',
      '_rac_vlm_cancel_proto',
    ]).length === 0;
  }

  process(
    handle: number,
    image: ProtoVLMImage,
    options: ProtoVLMGenerationOptions,
  ): ProtoVLMResult | null {
    if (!ensureExports(this.module, 'vlm.process', ['_rac_vlm_process_proto'])) {
      return null;
    }
    const imageBytes = VLMImage.encode(image).finish();
    const optionsBytes = VLMGenerationOptions.encode(options).finish();
    const bridge = this.bridge();
    return bridge.withHeapBytes(imageBytes, (imagePtr, imageSize) => (
      bridge.withHeapBytes(optionsBytes, (optionsPtr, optionsSize) => (
        bridge.callResultProto(
          VLMResult,
          (outResult) => this.module._rac_vlm_process_proto!(
            handle,
            imagePtr,
            imageSize,
            optionsPtr,
            optionsSize,
            outResult,
          ),
          'rac_vlm_process_proto',
        )
      ))
    ));
  }

  processStream(
    handle: number,
    image: ProtoVLMImage,
    options: ProtoVLMGenerationOptions,
    onEvent: ProtoEventHandler<ProtoSDKEvent> | null,
  ): ProtoVLMResult | null {
    if (!ensureExports(this.module, 'vlm.processStream', ['_rac_vlm_process_stream_proto'])) {
      return null;
    }
    const imageBytes = VLMImage.encode(image).finish();
    const optionsBytes = VLMGenerationOptions.encode(options).finish();
    const bridge = this.bridge();
    return withOptionalCallback(this.module, SDKEvent, onEvent, 'rac_vlm_process_stream_proto', (callbackPtr) => (
      bridge.withHeapBytes(imageBytes, (imagePtr, imageSize) => (
        bridge.withHeapBytes(optionsBytes, (optionsPtr, optionsSize) => (
          bridge.callResultProto(
            VLMResult,
            (outResult) => this.module._rac_vlm_process_stream_proto!(
              handle,
              imagePtr,
              imageSize,
              optionsPtr,
              optionsSize,
              callbackPtr,
              0,
              outResult,
            ),
            'rac_vlm_process_stream_proto',
          )
        ))
      ))
    ));
  }

  cancel(handle: number): boolean {
    if (!ensureExports(this.module, 'vlm.cancel', ['_rac_vlm_cancel_proto'])) return false;
    const rc = this.module._rac_vlm_cancel_proto!(handle);
    if (rc !== 0) logger.warning(`rac_vlm_cancel_proto returned ${formatRacResult(rc)}`);
    return rc === 0;
  }

  private bridge(): ProtoWasmBridge {
    return new ProtoWasmBridge(this.module, logger);
  }
}

export class EmbeddingsProtoAdapter {
  static tryDefault(): EmbeddingsProtoAdapter | null {
    return ModalityProtoAdapter.tryDefault()?.embeddings() ?? null;
  }

  constructor(private readonly module: ModalityProtoModule) {}

  supportsProtoEmbeddings(): boolean {
    return missingExports(this.module, ['_rac_embeddings_embed_batch_proto']).length === 0;
  }

  embedBatch(
    handle: number,
    request: ProtoEmbeddingsRequest,
  ): ProtoEmbeddingsResult | null {
    if (!ensureExports(this.module, 'embeddings.embedBatch', [
      '_rac_embeddings_embed_batch_proto',
    ])) {
      return null;
    }
    return this.bridge().withEncodedRequest(
      request,
      EmbeddingsRequest,
      EmbeddingsResult,
      (requestPtr, requestSize, outResult) => (
        this.module._rac_embeddings_embed_batch_proto!(
          handle,
          requestPtr,
          requestSize,
          outResult,
        )
      ),
      'rac_embeddings_embed_batch_proto',
    );
  }

  private bridge(): ProtoWasmBridge {
    return new ProtoWasmBridge(this.module, logger);
  }
}

export class DiffusionProtoAdapter {
  static tryDefault(): DiffusionProtoAdapter | null {
    return ModalityProtoAdapter.tryDefault()?.diffusion() ?? null;
  }

  constructor(private readonly module: ModalityProtoModule) {}

  supportsProtoDiffusion(): boolean {
    return missingExports(this.module, [
      '_rac_diffusion_generate_proto',
      '_rac_diffusion_generate_with_progress_proto',
      '_rac_diffusion_cancel_proto',
    ]).length === 0;
  }

  generate(
    handle: number,
    options: ProtoDiffusionGenerationOptions,
  ): ProtoDiffusionResult | null {
    if (!ensureExports(this.module, 'diffusion.generate', ['_rac_diffusion_generate_proto'])) {
      return null;
    }
    return this.bridge().withEncodedRequest(
      options,
      DiffusionGenerationOptions,
      DiffusionResult,
      (optionsPtr, optionsSize, outResult) => (
        this.module._rac_diffusion_generate_proto!(
          handle,
          optionsPtr,
          optionsSize,
          outResult,
        )
      ),
      'rac_diffusion_generate_proto',
    );
  }

  generateWithProgress(
    handle: number,
    options: ProtoDiffusionGenerationOptions,
    onProgress: ProtoEventHandler<ProtoDiffusionProgress> | null,
  ): ProtoDiffusionResult | null {
    if (!ensureExports(this.module, 'diffusion.generateWithProgress', [
      '_rac_diffusion_generate_with_progress_proto',
    ])) {
      return null;
    }
    const optionsBytes = DiffusionGenerationOptions.encode(options).finish();
    const bridge = this.bridge();
    return withOptionalCallback(
      this.module,
      DiffusionProgress,
      onProgress,
      'rac_diffusion_generate_with_progress_proto',
      (callbackPtr) => bridge.withHeapBytes(optionsBytes, (optionsPtr, optionsSize) => (
        bridge.callResultProto(
          DiffusionResult,
          (outResult) => this.module._rac_diffusion_generate_with_progress_proto!(
            handle,
            optionsPtr,
            optionsSize,
            callbackPtr,
            0,
            outResult,
          ),
          'rac_diffusion_generate_with_progress_proto',
        )
      )),
    );
  }

  cancel(handle: number): boolean {
    if (!ensureExports(this.module, 'diffusion.cancel', ['_rac_diffusion_cancel_proto'])) {
      return false;
    }
    const rc = this.module._rac_diffusion_cancel_proto!(handle);
    if (rc !== 0) logger.warning(`rac_diffusion_cancel_proto returned ${formatRacResult(rc)}`);
    return rc === 0;
  }

  private bridge(): ProtoWasmBridge {
    return new ProtoWasmBridge(this.module, logger);
  }
}

export class RAGProtoAdapter {
  static tryDefault(): RAGProtoAdapter | null {
    return ModalityProtoAdapter.tryDefault()?.rag() ?? null;
  }

  constructor(private readonly module: ModalityProtoModule) {}

  missingRAGExports(): string[] {
    return missingExports(this.module, [
      '_rac_rag_session_create_proto',
      '_rac_rag_session_destroy_proto',
      '_rac_rag_ingest_proto',
      '_rac_rag_query_proto',
      '_rac_rag_clear_proto',
      '_rac_rag_stats_proto',
    ]);
  }

  supportsProtoRAG(): boolean {
    return this.missingRAGExports().length === 0;
  }

  createSession(config: ProtoRAGConfiguration): number | null {
    if (!ensureExports(this.module, 'rag.createSession', ['_rac_rag_session_create_proto'])) {
      return null;
    }
    const bridge = this.bridge();
    const outSession = bridge.allocOutPtr();
    if (!outSession) return null;
    try {
      const bytes = RAGConfiguration.encode(config).finish();
      const rc = bridge.withHeapBytes(bytes, (configPtr, configSize) => (
        this.module._rac_rag_session_create_proto!(configPtr, configSize, outSession)
      ));
      if (rc !== 0) {
        logger.warning(`rac_rag_session_create_proto returned ${formatRacResult(rc)}`);
        return null;
      }
      return bridge.readU32(outSession) || null;
    } finally {
      bridge.free(outSession);
    }
  }

  destroySession(session: number): void {
    if (!this.module._rac_rag_session_destroy_proto) {
      logger.warning('rag.destroySession: module missing _rac_rag_session_destroy_proto');
      return;
    }
    this.module._rac_rag_session_destroy_proto(session);
  }

  ingest(session: number, document: ProtoRAGDocument): ProtoRAGStatistics | null {
    if (!ensureExports(this.module, 'rag.ingest', ['_rac_rag_ingest_proto'])) return null;
    return this.bridge().withEncodedRequest(
      document,
      RAGDocument,
      RAGStatistics,
      (documentPtr, documentSize, outStats) => (
        this.module._rac_rag_ingest_proto!(session, documentPtr, documentSize, outStats)
      ),
      'rac_rag_ingest_proto',
    );
  }

  query(session: number, query: ProtoRAGQueryOptions): ProtoRAGResult | null {
    if (!ensureExports(this.module, 'rag.query', ['_rac_rag_query_proto'])) return null;
    return this.bridge().withEncodedRequest(
      query,
      RAGQueryOptions,
      RAGResult,
      (queryPtr, querySize, outResult) => (
        this.module._rac_rag_query_proto!(session, queryPtr, querySize, outResult)
      ),
      'rac_rag_query_proto',
    );
  }

  clear(session: number): ProtoRAGStatistics | null {
    if (!ensureExports(this.module, 'rag.clear', ['_rac_rag_clear_proto'])) return null;
    return this.bridge().callResultProto(
      RAGStatistics,
      (outStats) => this.module._rac_rag_clear_proto!(session, outStats),
      'rac_rag_clear_proto',
    );
  }

  statistics(session: number): ProtoRAGStatistics | null {
    if (!ensureExports(this.module, 'rag.statistics', ['_rac_rag_stats_proto'])) return null;
    return this.bridge().callResultProto(
      RAGStatistics,
      (outStats) => this.module._rac_rag_stats_proto!(session, outStats),
      'rac_rag_stats_proto',
    );
  }

  private bridge(): ProtoWasmBridge {
    return new ProtoWasmBridge(this.module, logger);
  }
}

export class LoRAProtoAdapter {
  static tryDefault(): LoRAProtoAdapter | null {
    return ModalityProtoAdapter.tryDefault()?.lora() ?? null;
  }

  constructor(private readonly module: ModalityProtoModule) {}

  supportsProtoLoRA(): boolean {
    return missingExports(this.module, [
      '_rac_lora_register_proto',
      '_rac_lora_compatibility_proto',
      '_rac_lora_load_proto',
      '_rac_lora_remove_proto',
      '_rac_lora_clear_proto',
    ]).length === 0;
  }

  register(
    registry: number,
    entry: ProtoLoraAdapterCatalogEntry,
  ): ProtoLoraAdapterCatalogEntry | null {
    if (!ensureExports(this.module, 'lora.register', ['_rac_lora_register_proto'])) return null;
    return this.bridge().withEncodedRequest(
      entry,
      LoraAdapterCatalogEntry,
      LoraAdapterCatalogEntry,
      (entryPtr, entrySize, outEntry) => (
        this.module._rac_lora_register_proto!(registry, entryPtr, entrySize, outEntry)
      ),
      'rac_lora_register_proto',
    );
  }

  compatibility(
    llmComponent: number,
    config: ProtoLoRAAdapterConfig,
  ): ProtoLoraCompatibilityResult | null {
    if (!ensureExports(this.module, 'lora.compatibility', [
      '_rac_lora_compatibility_proto',
    ])) {
      return null;
    }
    return this.bridge().withEncodedRequest(
      config,
      LoRAAdapterConfig,
      LoraCompatibilityResult,
      (configPtr, configSize, outResult) => (
        this.module._rac_lora_compatibility_proto!(
          llmComponent,
          configPtr,
          configSize,
          outResult,
        )
      ),
      'rac_lora_compatibility_proto',
    );
  }

  load(llmComponent: number, config: ProtoLoRAAdapterConfig): ProtoLoRAAdapterInfo | null {
    if (!ensureExports(this.module, 'lora.load', ['_rac_lora_load_proto'])) return null;
    return this.bridge().withEncodedRequest(
      config,
      LoRAAdapterConfig,
      LoRAAdapterInfo,
      (configPtr, configSize, outInfo) => (
        this.module._rac_lora_load_proto!(llmComponent, configPtr, configSize, outInfo)
      ),
      'rac_lora_load_proto',
    );
  }

  remove(llmComponent: number, config: ProtoLoRAAdapterConfig): ProtoLoRAAdapterInfo | null {
    if (!ensureExports(this.module, 'lora.remove', ['_rac_lora_remove_proto'])) return null;
    return this.bridge().withEncodedRequest(
      config,
      LoRAAdapterConfig,
      LoRAAdapterInfo,
      (configPtr, configSize, outInfo) => (
        this.module._rac_lora_remove_proto!(llmComponent, configPtr, configSize, outInfo)
      ),
      'rac_lora_remove_proto',
    );
  }

  clear(llmComponent: number): ProtoLoRAAdapterInfo | null {
    if (!ensureExports(this.module, 'lora.clear', ['_rac_lora_clear_proto'])) return null;
    return this.bridge().callResultProto(
      LoRAAdapterInfo,
      (outInfo) => this.module._rac_lora_clear_proto!(llmComponent, outInfo),
      'rac_lora_clear_proto',
    );
  }

  private bridge(): ProtoWasmBridge {
    return new ProtoWasmBridge(this.module, logger);
  }
}

function streamCallback<T>(
  module: ModalityProtoModule,
  codec: ProtoCodec<T>,
  functionName: string,
  call: (callbackPtr: number) => number,
  stopWhen?: (event: T) => boolean,
  onCancel?: () => void,
): AsyncIterable<T> {
  return {
    [Symbol.asyncIterator](): AsyncIterator<T> {
      const queue: T[] = [];
      const waiters: Array<{
        resolve(value: IteratorResult<T>): void;
        reject(reason?: unknown): void;
      }> = [];
      let callbackPtr = 0;
      let started = false;
      let finished = false;
      let callActive = false;

      const cleanup = (): void => {
        if (callbackPtr && !callActive) {
          module.removeFunction?.(callbackPtr);
          callbackPtr = 0;
        }
      };

      const finish = (): void => {
        if (finished) return;
        finished = true;
        while (waiters.length > 0) {
          waiters.shift()!.resolve({ value: undefined as T, done: true });
        }
        cleanup();
      };

      const fail = (error: unknown): void => {
        if (finished) return;
        finished = true;
        while (waiters.length > 0) {
          waiters.shift()!.reject(error);
        }
        cleanup();
      };

      const emit = (event: T): void => {
        if (finished) return;
        if (waiters.length > 0) {
          waiters.shift()!.resolve({ value: event, done: false });
        } else {
          queue.push(event);
        }
        if (stopWhen?.(event)) finish();
      };

      const start = (): void => {
        if (started) return;
        started = true;
        if (!module.addFunction || !module.removeFunction || !module.HEAPU8) {
          fail(SDKException.wasmNotLoaded(`${functionName}: module missing callback helpers`));
          return;
        }

        callbackPtr = module.addFunction((bytesPtr: number, size: number): void => {
          if (!bytesPtr || size <= 0) return;
          try {
            const bytes = module.HEAPU8!.slice(bytesPtr, bytesPtr + size);
            emit(codec.decode(bytes));
          } catch (error) {
            fail(error);
          }
        }, 'viii');

        callActive = true;
        try {
          const rc = call(callbackPtr);
          if (rc !== 0) {
            fail(SDKException.fromRACResult(rc, functionName));
            return;
          }
          if (!finished) finish();
        } catch (error) {
          fail(error);
        } finally {
          callActive = false;
          cleanup();
        }
      };

      return {
        next(): Promise<IteratorResult<T>> {
          start();
          if (queue.length > 0) {
            return Promise.resolve({ value: queue.shift()!, done: false });
          }
          if (finished) {
            return Promise.resolve({ value: undefined as T, done: true });
          }
          return new Promise((resolve, reject) => {
            waiters.push({ resolve, reject });
          });
        },
        return(): Promise<IteratorResult<T>> {
          try {
            onCancel?.();
          } finally {
            finish();
          }
          return Promise.resolve({ value: undefined as T, done: true });
        },
      };
    },
  };
}

function collectCallback<T>(
  module: ModalityProtoModule,
  codec: ProtoCodec<T>,
  functionName: string,
  call: (callbackPtr: number) => number,
): T[] | null {
  if (!module.addFunction || !module.removeFunction || !module.HEAPU8) {
    logger.warning(`${functionName}: module missing callback helpers`);
    return null;
  }
  const values: T[] = [];
  const callbackPtr = module.addFunction((bytesPtr: number, size: number): void => {
    if (!bytesPtr || size <= 0) return;
    const bytes = module.HEAPU8!.slice(bytesPtr, bytesPtr + size);
    values.push(codec.decode(bytes));
  }, 'viii');
  try {
    const rc = call(callbackPtr);
    if (rc !== 0) {
      logger.warning(`${functionName} returned ${formatRacResult(rc)}`);
      return null;
    }
    return values;
  } finally {
    module.removeFunction(callbackPtr);
  }
}

function withOptionalCallback<T, R>(
  module: ModalityProtoModule,
  codec: ProtoCodec<T>,
  handler: ProtoEventHandler<T> | null,
  functionName: string,
  call: (callbackPtr: number) => R,
): R | null {
  if (!handler) return call(0);
  if (!module.addFunction || !module.removeFunction || !module.HEAPU8) {
    logger.warning(`${functionName}: module missing callback helpers`);
    return null;
  }
  const callbackPtr = module.addFunction((bytesPtr: number, size: number): number => {
    if (!bytesPtr || size <= 0) return 1;
    const bytes = module.HEAPU8!.slice(bytesPtr, bytesPtr + size);
    handler(codec.decode(bytes));
    return 1;
  }, callbackSignature(true));
  try {
    return call(callbackPtr);
  } finally {
    module.removeFunction(callbackPtr);
  }
}

function callbackSignature(returnsBool: boolean): CallbackSignature {
  return returnsBool ? 'iiii' : 'viii';
}

function bridgeFor(module: ModalityProtoModule): ProtoWasmBridge {
  return new ProtoWasmBridge(module, logger);
}

function missingExports(
  module: ModalityProtoModule,
  required: Array<keyof ModalityProtoModule>,
): string[] {
  return [
    ...bridgeFor(module).missingProtoBufferExports(),
    ...required.filter((key) => !module[key]).map(String),
  ];
}

function ensureExports(
  module: ModalityProtoModule,
  operation: string,
  required: Array<keyof ModalityProtoModule>,
): boolean {
  const missing = missingExports(module, required);
  if (missing.length > 0) {
    logger.warning(`${operation}: module missing modality proto exports: ${missing.join(', ')}`);
    return false;
  }
  return true;
}

function requireExports(
  module: ModalityProtoModule,
  operation: string,
  required: Array<keyof ModalityProtoModule>,
): void {
  const missing = missingExports(module, required);
  if (missing.length > 0) {
    throw SDKException.backendNotAvailable(
      operation,
      `WASM module missing modality proto exports: ${missing.join(', ')}`,
    );
  }
}
