/**
 * Regression gate for the production init hang where backend registration
 * awaited Phase 2 cloud services and never settled (`backend=pending`).
 *
 * Backend packages must register inference only; the example app / SDK facade
 * owns Phase 2 via `RunAnywhere.completeServicesInitialization()`.
 */
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const here = dirname(fileURLToPath(import.meta.url));
const webRoot = resolve(here, '../../../../..');

function readSource(relativePath: string): string {
  return readFileSync(resolve(webRoot, relativePath), 'utf8');
}

describe('backend registration Phase 2 isolation', () => {
  it('does not await deferred services inside LlamaCPP.register()', () => {
    const source = readSource('packages/llamacpp/src/LlamaCPP.ts');
    expect(source).not.toMatch(/completeDeferredServicesInitialization/);
    expect(source).toMatch(/async register\(/);
  });

  it('does not await deferred services inside SherpaONNXBridge._doLoad()', () => {
    const source = readSource('packages/onnx/src/Foundation/SherpaONNXBridge.ts');
    expect(source).not.toMatch(/completeDeferredServicesInitialization/);
    expect(source).toMatch(/rac_backend_sherpa_register/);
  });

  it('keeps deferred Phase 2 ownership on the core facade export', () => {
    const source = readSource('packages/core/src/Public/RunAnywhere.ts');
    expect(source).toMatch(/export async function completeDeferredServicesInitialization/);
    expect(source).toMatch(/async completeServicesInitialization\(/);
  });
});
