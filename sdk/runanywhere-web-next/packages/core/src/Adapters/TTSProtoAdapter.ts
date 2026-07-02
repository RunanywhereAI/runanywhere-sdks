import {
  TTSOptions,
  TTSOutput,
  TTSVoiceInfo,
  type TTSOptions as ProtoTTSOptions,
  type TTSOutput as ProtoTTSOutput,
  type TTSVoiceInfo as ProtoTTSVoiceInfo,
} from '@runanywhere/proto-ts/tts_options';
import { clientFor } from '../runtime/HostRegistry';
import { Arg, type WorkerProtoClient } from '../runtime/WorkerProtoClient';

export class TTSProtoAdapter {
  static tryDefault(): TTSProtoAdapter | null {
    const client = clientFor('tts');
    return client ? new TTSProtoAdapter(client) : null;
  }

  constructor(private readonly client: WorkerProtoClient) {}

  async createComponent(): Promise<number> {
    const { rc, outValues } = await this.client.call('rac_tts_component_create', [Arg.outU32()]);
    if (rc !== 0) throw new Error(`rac_tts_component_create failed (rc=${rc})`);
    const handle = outValues?.[0] ?? 0;
    if (!handle) throw new Error('rac_tts_component_create returned a null handle');
    return handle;
  }

  async loadVoice(handle: number, voicePath: string, voiceId = '', voiceName = ''): Promise<void> {
    const rc = await this.client.callRc('rac_tts_component_load_voice', [
      Arg.num(handle),
      Arg.string(voicePath),
      Arg.string(voiceId),
      Arg.string(voiceName),
    ]);
    if (rc !== 0) throw new Error(`rac_tts_component_load_voice failed (rc=${rc})`);
  }

  destroy(handle: number): Promise<number> {
    return this.client.callRc('rac_tts_component_destroy', [Arg.num(handle)]);
  }

  listVoices(handle: number): Promise<ProtoTTSVoiceInfo[]> {
    return this.client.collectProto(
      'rac_tts_component_list_voices_proto',
      [Arg.num(handle), Arg.streamCb(false), Arg.num(0)],
      TTSVoiceInfo,
    );
  }

  synthesize(
    handle: number,
    text: string,
    options: ProtoTTSOptions,
  ): Promise<ProtoTTSOutput | null> {
    const optionsBytes = TTSOptions.encode(options).finish();
    return this.client.callProto(
      'rac_tts_component_synthesize_proto',
      [Arg.num(handle), Arg.string(text), Arg.bytes(optionsBytes), Arg.outProto()],
      TTSOutput,
    );
  }

  synthesizeStream(
    handle: number,
    text: string,
    options: ProtoTTSOptions,
  ): AsyncIterable<ProtoTTSOutput> {
    const optionsBytes = TTSOptions.encode(options).finish();
    return this.client.streamProto(
      'rac_tts_component_synthesize_stream_proto',
      [Arg.num(handle), Arg.string(text), Arg.bytes(optionsBytes), Arg.streamCb(false), Arg.num(0)],
      TTSOutput,
    );
  }
}
