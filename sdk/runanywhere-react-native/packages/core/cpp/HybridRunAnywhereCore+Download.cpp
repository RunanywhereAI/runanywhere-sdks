/**
 * HybridRunAnywhereCore+Download.cpp
 *
 * Domain implementation for HybridRunAnywhereCore.
 *
 * Download requests, results, progress, cancel, and resume are transported as
 * serialized runanywhere.v1 proto bytes. HTTP byte execution remains owned by
 * the registered platform transport (OkHttp on Android, URLSession on iOS).
 */
#include "HybridRunAnywhereCore+Common.hpp"
#include "HybridRunAnywhereCore+ProtoCompat.hpp"

#include <cstring>

#include "rac/infrastructure/download/rac_download_orchestrator.h"

namespace margelo::nitro::runanywhere {

using namespace ::runanywhere::bridges;

namespace {

std::mutex g_downloadProtoCallbackMutex;
std::function<void(const std::shared_ptr<ArrayBuffer>&)> g_downloadProtoCallback;

std::vector<uint8_t> copyDownloadArrayBufferBytes(const std::shared_ptr<ArrayBuffer>& buffer) {
    std::vector<uint8_t> bytes;
    if (!buffer) {
        return bytes;
    }

    uint8_t* data = buffer->data();
    size_t size = buffer->size();
    if (!data || size == 0) {
        return bytes;
    }

    bytes.assign(data, data + size);
    return bytes;
}

std::shared_ptr<ArrayBuffer> emptyDownloadProtoBuffer() {
    return ArrayBuffer::allocate(0);
}

proto_compat::ProtoBufferCallFn downloadProtoSymbol(const char* symbolName) {
    if (std::strcmp(symbolName, "rac_download_plan_proto") == 0) {
        return &rac_download_plan_proto;
    }
    if (std::strcmp(symbolName, "rac_download_start_proto") == 0) {
        return &rac_download_start_proto;
    }
    if (std::strcmp(symbolName, "rac_download_cancel_proto") == 0) {
        return &rac_download_cancel_proto;
    }
    if (std::strcmp(symbolName, "rac_download_resume_proto") == 0) {
        return &rac_download_resume_proto;
    }
    if (std::strcmp(symbolName, "rac_download_progress_poll_proto") == 0) {
        return &rac_download_progress_poll_proto;
    }
    return proto_compat::symbol<proto_compat::ProtoBufferCallFn>(symbolName);
}

std::shared_ptr<ArrayBuffer> copyDownloadProtoBuffer(rac_proto_buffer_t& protoBuffer) {
    if (protoBuffer.status != RAC_SUCCESS) {
        if (protoBuffer.error_message) {
            LOGE("download proto error: %s", protoBuffer.error_message);
        }
        proto_compat::freeBuffer(&protoBuffer);
        return emptyDownloadProtoBuffer();
    }

    if (!protoBuffer.data || protoBuffer.size == 0) {
        proto_compat::freeBuffer(&protoBuffer);
        return emptyDownloadProtoBuffer();
    }

    auto buffer = ArrayBuffer::copy(protoBuffer.data, protoBuffer.size);
    proto_compat::freeBuffer(&protoBuffer);
    return buffer;
}

std::shared_ptr<ArrayBuffer> callDownloadProto(const std::vector<uint8_t>& requestBytes,
                                               const char* symbolName,
                                               const char* operation) {
    auto fn = downloadProtoSymbol(symbolName);
    if (!fn) {
        LOGE("%s: %s unavailable", operation, symbolName);
        return emptyDownloadProtoBuffer();
    }

    rac_proto_buffer_t out;
    proto_compat::initBuffer(&out);
    const uint8_t* requestData = requestBytes.empty() ? nullptr : requestBytes.data();
    rac_result_t rc = fn(requestData, requestBytes.size(), &out);
    if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) {
        LOGE("%s: rc=%d", operation, rc);
        proto_compat::freeBuffer(&out);
        return emptyDownloadProtoBuffer();
    }
    return copyDownloadProtoBuffer(out);
}

void downloadProtoProgressTrampoline(const uint8_t* protoBytes,
                                     size_t protoSize,
                                     void* userData) {
    if (!protoBytes || protoSize == 0) {
        return;
    }

    std::function<void(const std::shared_ptr<ArrayBuffer>&)> callback;
    {
        std::lock_guard<std::mutex> lock(g_downloadProtoCallbackMutex);
        callback = g_downloadProtoCallback;
    }

    if (!callback) {
        return;
    }

    auto buffer = ArrayBuffer::copy(protoBytes, protoSize);
    try {
        callback(buffer);
    } catch (...) {
    }
}

}  // namespace

// Download Service
// Requests/results/progress are serialized `runanywhere.v1` proto messages.

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::downloadPlanProto(const std::shared_ptr<ArrayBuffer>& requestBytes) {
    auto bytes = copyDownloadArrayBufferBytes(requestBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        return callDownloadProto(
            bytes,
            "rac_download_plan_proto",
            "downloadPlanProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::downloadStartProto(const std::shared_ptr<ArrayBuffer>& requestBytes) {
    auto bytes = copyDownloadArrayBufferBytes(requestBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        return callDownloadProto(
            bytes,
            "rac_download_start_proto",
            "downloadStartProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::downloadCancelProto(const std::shared_ptr<ArrayBuffer>& requestBytes) {
    auto bytes = copyDownloadArrayBufferBytes(requestBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        return callDownloadProto(
            bytes,
            "rac_download_cancel_proto",
            "downloadCancelProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::downloadResumeProto(const std::shared_ptr<ArrayBuffer>& requestBytes) {
    auto bytes = copyDownloadArrayBufferBytes(requestBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        return callDownloadProto(
            bytes,
            "rac_download_resume_proto",
            "downloadResumeProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::downloadProgressPollProto(const std::shared_ptr<ArrayBuffer>& requestBytes) {
    auto bytes = copyDownloadArrayBufferBytes(requestBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        return callDownloadProto(
            bytes,
            "rac_download_progress_poll_proto",
            "downloadProgressPollProto");
    });
}

std::shared_ptr<Promise<bool>>
HybridRunAnywhereCore::setDownloadProgressCallbackProto(
    const std::function<void(const std::shared_ptr<ArrayBuffer>&)>& onProgressBytes) {
    return Promise<bool>::async([onProgressBytes]() -> bool {
        {
            std::lock_guard<std::mutex> lock(g_downloadProtoCallbackMutex);
            g_downloadProtoCallback = onProgressBytes;
        }

        auto setCallback = &rac_download_set_progress_proto_callback;
        if (!setCallback) {
            std::lock_guard<std::mutex> lock(g_downloadProtoCallbackMutex);
            g_downloadProtoCallback = nullptr;
            LOGE("setDownloadProgressCallbackProto: rac_download_set_progress_proto_callback unavailable");
            return false;
        }

        rac_result_t rc = setCallback(
            &downloadProtoProgressTrampoline,
            nullptr);
        if (rc != RAC_SUCCESS) {
            std::lock_guard<std::mutex> lock(g_downloadProtoCallbackMutex);
            g_downloadProtoCallback = nullptr;
            LOGE("setDownloadProgressCallbackProto: rc=%d", rc);
            return false;
        }

        return true;
    });
}

std::shared_ptr<Promise<bool>>
HybridRunAnywhereCore::clearDownloadProgressCallbackProto() {
    return Promise<bool>::async([]() -> bool {
        {
            std::lock_guard<std::mutex> lock(g_downloadProtoCallbackMutex);
            g_downloadProtoCallback = nullptr;
        }

        auto setCallback = &rac_download_set_progress_proto_callback;
        if (!setCallback) {
            LOGE("clearDownloadProgressCallbackProto: rac_download_set_progress_proto_callback unavailable");
            return false;
        }

        rac_result_t rc = setCallback(nullptr, nullptr);
        if (rc != RAC_SUCCESS) {
            LOGE("clearDownloadProgressCallbackProto: rc=%d", rc);
            return false;
        }
        return true;
    });
}

} // namespace margelo::nitro::runanywhere
