#ifndef RA_CORE_H
#define RA_CORE_H

/**
 * RunAnywhereCore - Unified ML Inference Library
 *
 * This umbrella header includes all available backend APIs.
 * Each backend provides the same capability-based C API.
 */

// Shared types used across all backends
#include "ra_types.h"

// Backend-specific APIs (same interface, different implementations)
#include "ra_onnx_bridge.h"
#include "ra_llamacpp_bridge.h"

#endif // RA_CORE_H
