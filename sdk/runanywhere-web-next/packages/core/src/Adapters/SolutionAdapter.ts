import { SolutionConfig } from '@runanywhere/proto-ts/solutions';
import { SDKException } from '../Foundation/SDKException';
import { RAC_OK, RAC_ERROR_FEATURE_NOT_AVAILABLE } from '../Foundation/RACErrors';
import { clientFor } from '../runtime/HostRegistry';
import { Arg, type WorkerProtoClient } from '../runtime/WorkerProtoClient';

function assertOk(op: string, rc: number): void {
  if (rc === RAC_ERROR_FEATURE_NOT_AVAILABLE) {
    throw SDKException.backendNotAvailable(
      `Solution.${op}`,
      `Native solution runtime returned RAC_ERROR_FEATURE_NOT_AVAILABLE (rc=${rc}). ` +
      'This Web WASM build does not include the requested solution capability.',
    );
  }
  if (rc !== RAC_OK) throw new Error(`rac_solution_${op} failed (rc=${rc})`);
}

export class SolutionHandle {
  private handle: number | null;

  constructor(private readonly client: WorkerProtoClient, handle: number) {
    if (!handle) throw new Error('Cannot wrap a null rac_solution_handle_t');
    this.handle = handle;
  }

  get isAlive(): boolean {
    return this.handle !== null && this.handle !== 0;
  }

  async start(): Promise<void> {
    assertOk('start', await this.client.callRc('rac_solution_start', [Arg.num(this.require())]));
  }

  async stop(): Promise<void> {
    assertOk('stop', await this.client.callRc('rac_solution_stop', [Arg.num(this.require())]));
  }

  async cancel(): Promise<void> {
    assertOk('cancel', await this.client.callRc('rac_solution_cancel', [Arg.num(this.require())]));
  }

  async feed(item: string): Promise<void> {
    assertOk('feed', await this.client.callRc('rac_solution_feed', [Arg.num(this.require()), Arg.string(item)]));
  }

  async closeInput(): Promise<void> {
    assertOk('close_input', await this.client.callRc('rac_solution_close_input', [Arg.num(this.require())]));
  }

  async destroy(): Promise<void> {
    if (this.handle === null || this.handle === 0) return;
    const handle = this.handle;
    this.handle = null;
    await this.client.callRc('rac_solution_destroy', [Arg.num(handle)]);
  }

  async close(): Promise<void> {
    await this.destroy();
  }

  private require(): number {
    if (this.handle === null || this.handle === 0) throw new Error('SolutionHandle has already been destroyed');
    return this.handle;
  }
}

export interface SolutionRunInput {
  config?: SolutionConfig;
  configBytes?: Uint8Array;
  yaml?: string;
}

export const SolutionAdapter = {
  async run(input: SolutionRunInput): Promise<SolutionHandle> {
    const client = clientFor('commons');
    if (!client) throw SDKException.backendNotAvailable('Solution.run', 'no commons worker registered');

    if (input.yaml !== undefined) {
      const { rc, outValues } = await client.call('rac_solution_create_from_yaml', [Arg.string(input.yaml), Arg.outU32()]);
      assertOk('create_from_yaml', rc);
      const handle = outValues?.[0] ?? 0;
      if (!handle) throw new Error('rac_solution_create_from_yaml returned RAC_SUCCESS with a null handle');
      return new SolutionHandle(client, handle);
    }

    const bytes = input.configBytes ?? (input.config ? SolutionConfig.encode(input.config).finish() : undefined);
    if (!bytes) throw new Error('SolutionAdapter.run requires exactly one of config / configBytes / yaml');
    if (bytes.length === 0) throw new Error('Solution config bytes are empty');

    const { rc, outValues } = await client.call('rac_solution_create_from_proto', [Arg.bytes(bytes), Arg.outU32()]);
    assertOk('create_from_proto', rc);
    const handle = outValues?.[0] ?? 0;
    if (!handle) throw new Error('rac_solution_create_from_proto returned RAC_SUCCESS with a null handle');
    return new SolutionHandle(client, handle);
  },
};
