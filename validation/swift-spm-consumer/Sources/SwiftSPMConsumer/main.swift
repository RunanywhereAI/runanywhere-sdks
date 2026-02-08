// =============================================================================
// Minimal consumer to verify RunAnywhere SDK resolves and compiles via SPM.
// Imports must match: RunAnywhere, LlamaCPPRuntime, ONNXRuntime (target names).
// Uses top-level code as entry point (no @main) to avoid "main attribute cannot
// be used in a module that contains top-level code".
// =============================================================================

import RunAnywhere
import LlamaCPPRuntime
import ONNXRuntime

print("RunAnywhere SDK SPM consumer: OK")
print("  - RunAnywhere: resolved")
print("  - LlamaCPPRuntime: resolved")
print("  - ONNXRuntime: resolved")
