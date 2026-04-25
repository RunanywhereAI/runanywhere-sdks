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

enum class ElementType : uint32_t {
    Float32 = 1,
    Int64 = 7,
};

struct TensorInput {
    const char* name = nullptr;
    const void* data = nullptr;
    size_t data_bytes = 0;
    const int64_t* shape = nullptr;
    size_t rank = 0;
    ElementType type = ElementType::Float32;
};

struct FloatTensorOutput {
    std::vector<float> data;
    std::vector<int64_t> shape;
};

struct SessionOptions {
    int intra_op_threads = 4;
    bool enable_all_optimizations = true;
    const char* log_id = "RunAnywhereONNXRT";
};

class Session {
public:
    ~Session();

    Session(const Session&) = delete;
    Session& operator=(const Session&) = delete;

    static std::unique_ptr<Session> create(const std::string& model_path,
                                           const SessionOptions& options,
                                           std::string* out_error);

    rac_result_t run(const TensorInput* inputs,
                     size_t input_count,
                     const char* const* output_names,
                     size_t output_count,
                     std::vector<FloatTensorOutput>& outputs,
                     std::string* out_error);

private:
    struct Impl;
    explicit Session(std::unique_ptr<Impl> impl);

    std::unique_ptr<Impl> impl_;
};

const char* runtime_version();
const rac_runtime_vtable_t* runtime_vtable();

}  // namespace onnxrt
}  // namespace runtime
}  // namespace runanywhere
