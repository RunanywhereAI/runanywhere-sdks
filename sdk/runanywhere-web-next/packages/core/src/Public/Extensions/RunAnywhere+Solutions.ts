import { SolutionAdapter, type SolutionHandle, type SolutionRunInput } from '../../Adapters/SolutionAdapter';
import { RunAnywhereSDK } from '../RunAnywhere';

declare module '../RunAnywhere' {
  interface RunAnywhereSDK {
    runSolution(input: SolutionRunInput): Promise<SolutionHandle>;
  }
}

RunAnywhereSDK.prototype.runSolution = function (this: RunAnywhereSDK, input) {
  this.ensureInitialized();
  return SolutionAdapter.run(input);
};
