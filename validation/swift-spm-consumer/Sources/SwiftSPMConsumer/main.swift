// =============================================================================
// Minimal consumer to verify RunAnywhere SDK resolves and compiles via SPM.
// Imports must match: RunAnywhere, LlamaCPPRuntime, ONNXRuntime (target names).
// =============================================================================

import RunAnywhere
import LlamaCPPRuntime
import ONNXRuntime

@main
struct SwiftSPMConsumer {
    static func main() {
        print("RunAnywhere SDK SPM consumer: OK")
        print("  - RunAnywhere: resolved")
        print("  - LlamaCPPRuntime: resolved")
        print("  - ONNXRuntime: resolved")
    }
}
