import {
  DiffusionGenerationOptions,
  DiffusionResult,
  type DiffusionGenerationOptions as ProtoDiffusionGenerationOptions,
  type DiffusionResult as ProtoDiffusionResult,
} from '@runanywhere/proto-ts/diffusion_options';
import { clientFor } from '../runtime/HostRegistry';
import { Arg, type WorkerProtoClient } from '../runtime/WorkerProtoClient';

export class DiffusionProtoAdapter {
  static tryDefault(): DiffusionProtoAdapter | null {
    const client = clientFor('diffusion');
    return client ? new DiffusionProtoAdapter(client) : null;
  }

  constructor(private readonly client: WorkerProtoClient) {}

  generate(
    handle: number,
    options: ProtoDiffusionGenerationOptions,
  ): Promise<ProtoDiffusionResult | null> {
    const bytes = DiffusionGenerationOptions.encode(options).finish();
    return this.client.callProto(
      'rac_diffusion_generate_proto',
      [Arg.num(handle), Arg.bytes(bytes), Arg.outProto()],
      DiffusionResult,
    );
  }

  async cancel(handle: number): Promise<boolean> {
    return (await this.client.callRc('rac_diffusion_cancel_proto', [Arg.num(handle)])) === 0;
  }
}
