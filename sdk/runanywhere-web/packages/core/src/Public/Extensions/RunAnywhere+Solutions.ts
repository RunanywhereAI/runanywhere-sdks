/**
 * RunAnywhere+Solutions.ts (Web)
 *
 * Public API for L5 solutions runtime (T4.7 / T4.8). A "solution" is a
 * prepackaged pipeline config — either a typed `SolutionConfig` proto,
 * raw proto bytes, or YAML sugar — that the C++ core compiles into a
 * GraphScheduler DAG and runs through the `rac_solution_*` C ABI
 * (exposed to the web as `_rac_solution_*` WASM exports).
 *
 * Surface mirrors Swift / Kotlin / Flutter / RN — `RunAnywhere.solutions
 * .run({ config | configBytes | yaml })`.
 */

import type { SolutionConfig } from '../../generated/solutions';
import {
  SolutionAdapter,
  SolutionHandle,
  type SolutionRunInput,
} from '../../Adapters/SolutionAdapter';

/**
 * `RunAnywhere.solutions` capability accessor.
 *
 * Stateless — every call to `run(...)` allocates a fresh
 * `rac_solution_handle_t`; callers own the returned [SolutionHandle].
 */
export const solutions = {
  /**
   * Construct and return a (created, not yet started) solution. Callers
   * own the returned [SolutionHandle] — invoke `.destroy()` when finished.
   */
  run(input: SolutionRunInput): SolutionHandle {
    return SolutionAdapter.run(input);
  },
};

export { SolutionHandle, SolutionAdapter };
export type { SolutionConfig, SolutionRunInput };
