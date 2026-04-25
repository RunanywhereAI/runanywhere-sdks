#ifndef RUNANYWHERE_ONNX_BACKEND_H
#define RUNANYWHERE_ONNX_BACKEND_H

/**
 * @file onnx_backend.h
 * @brief Generic ONNX Runtime backend internals.
 *
 * The ONNX backend now owns generic ONNX Runtime services such as embeddings,
 * plus temporary legacy C shims in rac_onnx.cpp for downstream callers still
 * using rac_*_onnx_* names.
 */

namespace runanywhere {

class ONNXBackendNew final {};

}  // namespace runanywhere

#endif  // RUNANYWHERE_ONNX_BACKEND_H
