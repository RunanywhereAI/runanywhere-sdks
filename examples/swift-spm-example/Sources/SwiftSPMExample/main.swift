// =============================================================================
// Swift SPM Example App
// =============================================================================
//
// Minimal executable that verifies RunAnywhere SDK resolves and compiles
// via SPM with a versioned dependency (exact: "0.17.5").
//
// Imports: RunAnywhere, LlamaCPPRuntime, ONNXRuntime (target names).
// Uses top-level code as entry point (no @main) for SPM executable compatibility.
//
// =============================================================================

import RunAnywhere
import LlamaCPPRuntime
import ONNXRuntime

print("RunAnywhere SDK SPM Example: OK")
print("  - RunAnywhere: resolved")
print("  - LlamaCPPRuntime: resolved")
print("  - ONNXRuntime: resolved")
print("")
print("SDK consumed via versioned dependency (exact: 0.17.5).")
