/**
 * HybridRunAnywhereCore+Download.cpp
 *
 * Domain implementation for HybridRunAnywhereCore.
 *
 * M5 rework — now routes downloads through the commons HTTP download facade
 * `rac_http_download_execute`, which in turn uses the registered platform
 * HTTP transport (OkHttp on Android, URLSession on iOS — wired via M1.2).
 * Progress is delivered to JS as a JSON-encoded
 * `runanywhere.v1.DownloadProgress` message with all 10 fields so the JS
 * side can decode via `DownloadProgress.fromJSON(JSON.parse(progressJson))`
 * from `@runanywhere/proto-ts/download_service`.
 *
 * Removed in this revision: the B-RN-3-001 / G-A6 `SyncHttpDownload`
 * platform-adapter workaround (see `bridges/PlatformDownloadBridge.h`).
 */
#include "HybridRunAnywhereCore+Common.hpp"
#include "HybridRunAnywhereCore+ProtoCompat.hpp"

#include <chrono>
#include <cstdio>
#include <sstream>

#include "rac/infrastructure/download/rac_download.h"
#include "rac/infrastructure/download/rac_download_orchestrator.h"
#include "rac/infrastructure/http/rac_http_download.h"

namespace margelo::nitro::runanywhere {

using namespace ::runanywhere::bridges;

namespace {

// -----------------------------------------------------------------------------
// JSON escaping for proto-ts DownloadProgress.fromJSON compatibility. The
// proto-ts accepts stringified enum names (e.g. "DOWNLOAD_STAGE_DOWNLOADING")
// or integer values — we emit integers here because they're bit-exact to the
// C enum and require no tables.
// -----------------------------------------------------------------------------

std::string escapeJsonString(const std::string& in) {
    std::string out;
    out.reserve(in.size() + 2);
    for (char c : in) {
        switch (c) {
            case '"':  out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\n': out += "\\n";  break;
            case '\r': out += "\\r";  break;
            case '\t': out += "\\t";  break;
            default:
                if (static_cast<unsigned char>(c) < 0x20) {
                    char buf[8];
                    std::snprintf(buf, sizeof(buf), "\\u%04x", static_cast<unsigned>(c));
                    out += buf;
                } else {
                    out += c;
                }
                break;
        }
    }
    return out;
}

/**
 * Map the C `rac_download_stage_t` enum to the proto
 * `runanywhere.v1.DownloadStage` enum values. The C enum starts at
 * DOWNLOADING=0 while proto reserves 0 for UNSPECIFIED — shift by +1.
 */
int protoStageFromRac(rac_download_stage_t stage) {
    switch (stage) {
        case RAC_DOWNLOAD_STAGE_DOWNLOADING: return 1;  // DOWNLOAD_STAGE_DOWNLOADING
        case RAC_DOWNLOAD_STAGE_EXTRACTING:  return 2;  // DOWNLOAD_STAGE_EXTRACTING
        case RAC_DOWNLOAD_STAGE_VALIDATING:  return 3;  // DOWNLOAD_STAGE_VALIDATING
        case RAC_DOWNLOAD_STAGE_COMPLETED:   return 4;  // DOWNLOAD_STAGE_COMPLETED
        default:                             return 0;  // DOWNLOAD_STAGE_UNSPECIFIED
    }
}

/**
 * Map the C `rac_download_state_t` enum to the proto
 * `runanywhere.v1.DownloadState` enum values. The C enum starts at
 * PENDING=0 while proto reserves 0 for UNSPECIFIED — shift by +1.
 */
int protoStateFromRac(rac_download_state_t state) {
    switch (state) {
        case RAC_DOWNLOAD_STATE_PENDING:     return 1;  // DOWNLOAD_STATE_PENDING
        case RAC_DOWNLOAD_STATE_DOWNLOADING: return 2;  // DOWNLOAD_STATE_DOWNLOADING
        case RAC_DOWNLOAD_STATE_EXTRACTING:  return 3;  // DOWNLOAD_STATE_EXTRACTING
        case RAC_DOWNLOAD_STATE_RETRYING:    return 4;  // DOWNLOAD_STATE_RETRYING
        case RAC_DOWNLOAD_STATE_COMPLETED:   return 5;  // DOWNLOAD_STATE_COMPLETED
        case RAC_DOWNLOAD_STATE_FAILED:      return 6;  // DOWNLOAD_STATE_FAILED
        case RAC_DOWNLOAD_STATE_CANCELLED:   return 7;  // DOWNLOAD_STATE_CANCELLED
        default:                             return 0;  // DOWNLOAD_STATE_UNSPECIFIED
    }
}

/**
 * Serialize the full 10-field `runanywhere.v1.DownloadProgress` message as
 * JSON. Field names match the proto-ts camelCase spelling so JS can call
 * `DownloadProgress.fromJSON(JSON.parse(json))` in one step.
 */
std::string buildProgressJson(const std::string& modelId,
                              rac_download_stage_t stage,
                              int64_t bytesDownloaded,
                              int64_t totalBytes,
                              double stageProgress,
                              double overallSpeedBps,
                              int64_t etaSeconds,
                              rac_download_state_t state,
                              int32_t retryAttempt,
                              const std::string& errorMessage) {
    std::ostringstream os;
    os << "{"
       << "\"modelId\":\""         << escapeJsonString(modelId)       << "\","
       << "\"stage\":"             << protoStageFromRac(stage)        << ","
       << "\"bytesDownloaded\":"   << bytesDownloaded                 << ","
       << "\"totalBytes\":"        << totalBytes                      << ","
       << "\"stageProgress\":"     << stageProgress                   << ","
       << "\"overallSpeedBps\":"   << overallSpeedBps                 << ","
       << "\"etaSeconds\":"        << etaSeconds                      << ","
       << "\"state\":"             << protoStateFromRac(state)        << ","
       << "\"retryAttempt\":"      << retryAttempt                    << ","
       << "\"errorMessage\":\""    << escapeJsonString(errorMessage)  << "\""
       << "}";
    return os.str();
}

/**
 * Per-download progress context — owns the JS callback plus the cancel flag
 * and last-seen byte counter used for rolling speed / ETA estimates.
 */
struct DownloadProgressContext {
    std::function<void(const std::string&)> onProgress;
    std::shared_ptr<std::atomic<bool>> cancelFlag;
    std::string modelHint;  // Best-effort model identifier derived from destPath.
    std::chrono::steady_clock::time_point startTime;
    std::chrono::steady_clock::time_point lastUpdate;
    int64_t lastBytes = 0;
};

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
    auto fn = proto_compat::symbol<proto_compat::ProtoBufferCallFn>(symbolName);
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

/**
 * Derive a best-effort model identifier from the destination path. The JS
 * layer passes paths like `.../Models/{framework}/{modelId}/{file}` — taking
 * the directory name just above the file is a reasonable hint. Falls back
 * to the filename stem when the shape isn't recognised.
 */
std::string deriveModelHint(const std::string& destPath) {
    // Strip trailing file name.
    size_t slash = destPath.find_last_of('/');
    if (slash == std::string::npos) return destPath;
    std::string parent = destPath.substr(0, slash);
    size_t parentSlash = parent.find_last_of('/');
    if (parentSlash == std::string::npos) return parent;
    return parent.substr(parentSlash + 1);
}

/**
 * C-style progress callback passed to `rac_http_download_execute`. Returns
 * RAC_FALSE to abort the download when the cancel flag flips.
 */
rac_bool_t httpDownloadProgressShim(uint64_t bytesWritten, uint64_t totalBytes, void* userData) {
    auto* ctx = static_cast<DownloadProgressContext*>(userData);
    if (!ctx) return RAC_TRUE;

    if (ctx->cancelFlag && ctx->cancelFlag->load()) {
        return RAC_FALSE;
    }

    auto now = std::chrono::steady_clock::now();
    double elapsedSinceLast = std::chrono::duration<double>(now - ctx->lastUpdate).count();
    double elapsedTotal = std::chrono::duration<double>(now - ctx->startTime).count();

    double instantSpeed = 0.0;
    if (elapsedSinceLast > 0.0) {
        instantSpeed = static_cast<double>(static_cast<int64_t>(bytesWritten) - ctx->lastBytes) /
                       elapsedSinceLast;
        if (instantSpeed < 0.0) instantSpeed = 0.0;
    }
    double avgSpeed = elapsedTotal > 0.0
                          ? static_cast<double>(bytesWritten) / elapsedTotal
                          : 0.0;
    // Weighted blend — favour the recent sample for responsiveness.
    double speed = (elapsedSinceLast > 0.0) ? (0.7 * instantSpeed + 0.3 * avgSpeed) : avgSpeed;

    int64_t eta = -1;
    if (speed > 0.0 && totalBytes > 0 && totalBytes >= bytesWritten) {
        eta = static_cast<int64_t>(
            static_cast<double>(totalBytes - bytesWritten) / speed);
    }

    double stageProgress = 0.0;
    if (totalBytes > 0) {
        stageProgress = static_cast<double>(bytesWritten) / static_cast<double>(totalBytes);
        if (stageProgress > 1.0) stageProgress = 1.0;
    }

    ctx->lastUpdate = now;
    ctx->lastBytes = static_cast<int64_t>(bytesWritten);

    if (ctx->onProgress) {
        std::string json = buildProgressJson(
            ctx->modelHint,
            RAC_DOWNLOAD_STAGE_DOWNLOADING,
            static_cast<int64_t>(bytesWritten),
            static_cast<int64_t>(totalBytes),
            stageProgress,
            speed,
            eta,
            RAC_DOWNLOAD_STATE_DOWNLOADING,
            0,
            "");
        try {
            ctx->onProgress(json);
        } catch (...) {
            // Isolate native dispatch from JS exceptions.
        }
    }
    return RAC_TRUE;
}

/**
 * Emit a final progress event (completion or failure) so consumers see a
 * terminal state without having to rely on the Promise's resolution alone.
 */
void emitTerminalProgress(DownloadProgressContext& ctx,
                          rac_download_state_t state,
                          const std::string& errorMessage,
                          int64_t bytesWritten,
                          int64_t totalBytes) {
    if (!ctx.onProgress) return;
    double stageProgress = 1.0;
    if (state != RAC_DOWNLOAD_STATE_COMPLETED) {
        stageProgress = (totalBytes > 0)
                            ? static_cast<double>(bytesWritten) / static_cast<double>(totalBytes)
                            : 0.0;
    }
    rac_download_stage_t stage = (state == RAC_DOWNLOAD_STATE_COMPLETED)
                                     ? RAC_DOWNLOAD_STAGE_COMPLETED
                                     : RAC_DOWNLOAD_STAGE_DOWNLOADING;
    std::string json = buildProgressJson(
        ctx.modelHint, stage, bytesWritten, totalBytes, stageProgress,
        0.0, -1, state, 0, errorMessage);
    try {
        ctx.onProgress(json);
    } catch (...) {
    }
}

}  // namespace

// =============================================================================
// Download Service
// =============================================================================
// M5: routes through `rac_http_download_execute` (commons HTTP download
// facade) which uses the registered platform HTTP transport (OkHttp on
// Android, URLSession on iOS). No more platform-adapter `SyncHttpDownload`
// workaround — Stage 5 + H4 OkHttp make it obsolete.
// =============================================================================

std::shared_ptr<Promise<void>> HybridRunAnywhereCore::downloadModel(
    const std::string& url,
    const std::string& destPath,
    const std::string& cancelToken,
    const std::function<void(const std::string&)>& onProgress,
    const std::optional<std::string>& expectedSha256Hex) {
    return Promise<void>::async([this, url, destPath, cancelToken, onProgress, expectedSha256Hex]() -> void {
        LOGI("Starting native download: %s -> %s", url.c_str(), destPath.c_str());

        auto cancelFlag = downloadCancelRegistry().registerToken(cancelToken);

        DownloadProgressContext ctx;
        ctx.onProgress = onProgress;
        ctx.cancelFlag = cancelFlag;
        ctx.modelHint = deriveModelHint(destPath);
        ctx.startTime = std::chrono::steady_clock::now();
        ctx.lastUpdate = ctx.startTime;
        ctx.lastBytes = 0;

        rac_http_download_request_t req{};
        req.url = url.c_str();
        req.destination_path = destPath.c_str();
        req.headers = nullptr;
        req.header_count = 0;
        req.timeout_ms = 0;              // library default
        req.follow_redirects = RAC_TRUE;
        req.resume_from_byte = 0;
        // Forward caller-supplied SHA-256 (if any) so libcurl's write path
        // verifies integrity inline and returns RAC_HTTP_DL_CHECKSUM_FAILED
        // on mismatch — matches Swift/Kotlin/Flutter wiring.
        req.expected_sha256_hex = (expectedSha256Hex.has_value() && !expectedSha256Hex->empty())
            ? expectedSha256Hex->c_str()
            : nullptr;

        int32_t httpStatus = 0;
        rac_http_download_status_t status = rac_http_download_execute(
            &req, httpDownloadProgressShim, &ctx, &httpStatus);

        downloadCancelRegistry().release(cancelToken);

        if (status == RAC_HTTP_DL_OK) {
            emitTerminalProgress(ctx, RAC_DOWNLOAD_STATE_COMPLETED, "",
                                 ctx.lastBytes, ctx.lastBytes);
            LOGI("Download complete: %s", destPath.c_str());
            return;
        }

        std::string reason;
        rac_download_state_t terminalState = RAC_DOWNLOAD_STATE_FAILED;
        switch (status) {
            case RAC_HTTP_DL_CANCELLED:
                reason = "cancelled";
                terminalState = RAC_DOWNLOAD_STATE_CANCELLED;
                break;
            case RAC_HTTP_DL_TIMEOUT:             reason = "timeout"; break;
            case RAC_HTTP_DL_NETWORK_ERROR:       reason = "network_error"; break;
            case RAC_HTTP_DL_NETWORK_UNAVAILABLE: reason = "network_unavailable"; break;
            case RAC_HTTP_DL_DNS_ERROR:           reason = "dns_error"; break;
            case RAC_HTTP_DL_SSL_ERROR:           reason = "ssl_error"; break;
            case RAC_HTTP_DL_SERVER_ERROR:        reason = "server_error"; break;
            case RAC_HTTP_DL_FILE_ERROR:          reason = "file_error"; break;
            case RAC_HTTP_DL_INVALID_URL:         reason = "invalid_url"; break;
            case RAC_HTTP_DL_INSUFFICIENT_STORAGE:reason = "insufficient_storage"; break;
            case RAC_HTTP_DL_CHECKSUM_FAILED:     reason = "checksum_failed"; break;
            default:                              reason = "unknown"; break;
        }
        std::string msg = "download failed: " + reason + " (status=" +
                          std::to_string(static_cast<int>(status)) +
                          ", http=" + std::to_string(httpStatus) + ")";

        emitTerminalProgress(ctx, terminalState, msg, ctx.lastBytes, ctx.lastBytes);

        LOGE("%s", msg.c_str());
        setLastError(msg);
        throw std::runtime_error(msg);
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::cancelDownload(
    const std::string& cancelToken) {
    return Promise<bool>::async([cancelToken]() -> bool {
        bool cancelled = downloadCancelRegistry().cancel(cancelToken);
        if (cancelled) {
            LOGI("Cancelled download: %s", cancelToken.c_str());
        }
        return cancelled;
    });
}

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

        auto setCallback =
            proto_compat::symbol<proto_compat::DownloadSetProgressProtoCallbackFn>(
                "rac_download_set_progress_proto_callback");
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

        auto setCallback =
            proto_compat::symbol<proto_compat::DownloadSetProgressProtoCallbackFn>(
                "rac_download_set_progress_proto_callback");
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
