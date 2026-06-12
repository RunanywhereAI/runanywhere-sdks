#ifndef RUNANYWHERE_ENGINES_COMMON_DEVICE_TYPE_H
#define RUNANYWHERE_ENGINES_COMMON_DEVICE_TYPE_H

/**
 * Shared internal device-type tag for engine backends.
 *
 * Returned by each backend's `get_device_type()` method to report which
 * compute unit the backend is currently running on. Union of values needed
 * across active engines (llamacpp, sherpa) — NEURAL_ENGINE is reserved for
 * Sherpa-style Apple/NPU integrations; METAL/CUDA/WEBGPU are llamacpp's
 * GGML backend build flavors.
 *
 * Internal to the engines/ tree. Not part of the stable rac_* C ABI.
 */
namespace runanywhere {

enum class DeviceType {
    CPU = 0,
    GPU = 1,
    NEURAL_ENGINE = 2,
    METAL = 3,
    CUDA = 4,
    WEBGPU = 5,
};

}  // namespace runanywhere

#endif  // RUNANYWHERE_ENGINES_COMMON_DEVICE_TYPE_H
