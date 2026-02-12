#pragma once

#include <onnxruntime_c_api.h>

namespace runanywhere {
namespace rag {

// RAII guard for OrtStatus - automatically releases status on scope exit
class OrtStatusGuard {
public:
    explicit OrtStatusGuard(const OrtApi* api) : api_(api), status_(nullptr) {}
    
    ~OrtStatusGuard() {
        if (status_ && api_) {
            api_->ReleaseStatus(status_);
        }
    }
    
    OrtStatusGuard(const OrtStatusGuard&) = delete;
    OrtStatusGuard& operator=(const OrtStatusGuard&) = delete;

    // Get address for new status assignment
    // IMPORTANT: Only call this once per ORT API call, or use reset() to properly clean up first
    OrtStatus** get_address() { 
        return &status_; 
    }
    
    OrtStatus* get() const { return status_; }
    bool is_error() const { return status_ != nullptr; }
    const char* error_message() const {
        return (status_ && api_) ? api_->GetErrorMessage(status_) : "Unknown error";
    }
    
    // Reset to new status (releases old status first if present)
    // Use this for sequential ORT calls: status_guard.reset(api->Function(...))
    void reset(OrtStatus* new_status = nullptr) {
        if (status_ && api_) {
            api_->ReleaseStatus(status_);
        }
        status_ = new_status;
    }
    
private:
    const OrtApi* api_;
    OrtStatus* status_;
};

// RAII guard for OrtValue - automatically releases tensor on scope exit
class OrtValueGuard {
public:
    explicit OrtValueGuard(const OrtApi* api) : api_(api), value_(nullptr) {}
    
    ~OrtValueGuard() {
        if (value_ && api_) {
            api_->ReleaseValue(value_);
        }
    }
    
    // Non-copyable
    OrtValueGuard(const OrtValueGuard&) = delete;
    OrtValueGuard& operator=(const OrtValueGuard&) = delete;
    
    // Movable (for storing in containers)
    OrtValueGuard(OrtValueGuard&& other) noexcept 
        : api_(other.api_), value_(other.value_) {
        other.value_ = nullptr;
    }
    
    OrtValueGuard& operator=(OrtValueGuard&& other) noexcept {
        if (this != &other) {
            if (value_ && api_) {
                api_->ReleaseValue(value_);
            }
            api_ = other.api_;
            value_ = other.value_;
            other.value_ = nullptr;
        }
        return *this;
    }
    
    OrtValue** ptr() { return &value_; }
    OrtValue* get() const { return value_; }
    OrtValue* release() {
        OrtValue* tmp = value_;
        value_ = nullptr;
        return tmp;
    }
    
private:
    const OrtApi* api_;
    OrtValue* value_;
};

// RAII guard for OrtMemoryInfo - automatically releases memory info on scope exit
class OrtMemoryInfoGuard {
public:
    explicit OrtMemoryInfoGuard(const OrtApi* api) : api_(api), memory_info_(nullptr) {}
    
    ~OrtMemoryInfoGuard() {
        if (memory_info_ && api_) {
            api_->ReleaseMemoryInfo(memory_info_);
        }
    }
    
    // Non-copyable
    OrtMemoryInfoGuard(const OrtMemoryInfoGuard&) = delete;
    OrtMemoryInfoGuard& operator=(const OrtMemoryInfoGuard&) = delete;
    
    OrtMemoryInfo** ptr() { return &memory_info_; }
    OrtMemoryInfo* get() const { return memory_info_; }
    
private:
    const OrtApi* api_;
    OrtMemoryInfo* memory_info_;
};

} // namespace rag
} // namespace runanywhere
