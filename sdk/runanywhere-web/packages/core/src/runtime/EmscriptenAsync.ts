/**
 * Numeric Emscripten calls that may unwind through Asyncify.
 *
 * A direct `_rac_*` export is safe only while native execution is entirely
 * synchronous. WebGPU inference reaches asynchronous browser imports, so the
 * entrypoint must be invoked through `ccall(..., { async: true })`. CPU and
 * ONNX builds remain compatible: their generated `ccall` returns a number and
 * `await` normalizes it without changing the public asynchronous contract.
 */

export interface AsyncCcallModule {
  ccall?(
    functionName: string,
    returnType: string | null,
    argumentTypes: string[],
    arguments_: unknown[],
    options?: { async?: boolean },
  ): unknown;
}

/**
 * Invoke a numeric C export with Asyncify enabled and validate its result.
 *
 * `fallback` keeps hermetic CPU/test modules that expose only direct exports
 * working. Production Emscripten artifacts export `ccall`, so WebGPU always
 * takes the async-aware path.
 */
export async function callEmscriptenAsyncNumber(
  module: AsyncCcallModule,
  functionName: string,
  argumentTypes: readonly string[],
  arguments_: readonly number[],
  fallback: () => number | Promise<number>,
): Promise<number> {
  const rawResult = typeof module.ccall === 'function'
    ? module.ccall(
      functionName,
      'number',
      [...argumentTypes],
      [...arguments_],
      { async: true },
    )
    : fallback();
  const result = Number(await rawResult);
  if (!Number.isFinite(result)) {
    throw new TypeError(`${functionName} returned a non-numeric result`);
  }
  return result;
}
