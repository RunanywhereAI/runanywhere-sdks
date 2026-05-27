#pragma once

#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/plugin/rac_runtime_vtable.h"

namespace runanywhere {
namespace runtime {
namespace onnxrt {

/** ONNX tensor element types we can marshal in and out of ORT.
 *  Values map 1:1 to `rac_runtime_dtype_t` so the public
 * `rac_runtime_io_t::dtype` wire is lossless. RT-ONNX-02: extended from
 * {Float32, Int64} to the full set of ORT primitive dtypes the adapter can
 * actually round-trip. */
enum class ElementType : uint32_t {
  Undefined = RAC_RUNTIME_DTYPE_UNDEFINED,
  Float32 = RAC_RUNTIME_DTYPE_F32,
  Uint8 = RAC_RUNTIME_DTYPE_U8,
  Int8 = RAC_RUNTIME_DTYPE_I8,
  Uint16 = RAC_RUNTIME_DTYPE_U16,
  Int16 = RAC_RUNTIME_DTYPE_I16,
  Int32 = RAC_RUNTIME_DTYPE_I32,
  Int64 = RAC_RUNTIME_DTYPE_I64,
  Float16 = RAC_RUNTIME_DTYPE_F16,
  Float64 = RAC_RUNTIME_DTYPE_F64,
  Uint32 = RAC_RUNTIME_DTYPE_U32,
  Uint64 = RAC_RUNTIME_DTYPE_U64,
  BFloat16 = RAC_RUNTIME_DTYPE_BF16,
};

/** Return the byte width of a single element for the supported primitive
 *  types. Returns 0 for `Undefined` or any unrecognized value (packed 4-bit
 *  types and strings/bools are not currently supported on the output path). */
size_t element_size_bytes(ElementType type);

struct TensorInput {
  const char *name = nullptr;
  const void *data = nullptr;
  size_t data_bytes = 0;
  const int64_t *shape = nullptr;
  size_t rank = 0;
  ElementType type = ElementType::Float32;
};

/** Raw-bytes tensor output. RT-ONNX-02: previously a `std::vector<float>`
 *  which force-cast every output to float32 regardless of the tensor's real
 *  dtype, silently corrupting i64/f16/u8/bf16/f64 outputs. `bytes` now holds
 *  the raw element-size × count payload and `dtype` records the ORT tensor's
 *  actual element type so callers can interpret it correctly. */
struct TensorOutput {
  std::vector<uint8_t> bytes;
  std::vector<int64_t> shape;
  ElementType dtype = ElementType::Undefined;
};

struct SessionOptions {
  int intra_op_threads = 4;
  bool enable_all_optimizations = true;
  const char *log_id = "RunAnywhereONNXRT";
};

class Session {
public:
  ~Session();

  Session(const Session &) = delete;
  Session &operator=(const Session &) = delete;

  static std::unique_ptr<Session> create(const std::string &model_path,
                                         const SessionOptions &options,
                                         std::string *out_error);

  /** runtimes-004: in-memory model bytes path. The vtable contract for
   *  `rac_runtime_session_desc_t` (rac_runtime_vtable.h:303-315) declares
   *  model_blob/model_blob_bytes as a peer to model_path -- both must be
   *  honored. ORT routes blobs through CreateSessionFromArray. */
  static std::unique_ptr<Session> create_from_blob(const void *model_data,
                                                   size_t model_data_bytes,
                                                   const SessionOptions &options,
                                                   std::string *out_error);

  rac_result_t run(const TensorInput *inputs, size_t input_count,
                   const char *const *output_names, size_t output_count,
                   std::vector<TensorOutput> &outputs, std::string *out_error);

private:
  struct Impl;
  explicit Session(std::unique_ptr<Impl> impl);

  std::unique_ptr<Impl> impl_;
};

const char *runtime_version();
const rac_runtime_vtable_t *runtime_vtable();

} // namespace onnxrt
} // namespace runtime
} // namespace runanywhere
