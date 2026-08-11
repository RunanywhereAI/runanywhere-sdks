/**
 * @file progress_bar.h
 * @brief Renders runanywhere.v1.DownloadProgress updates on stderr.
 *
 * TTY: single re-drawn line — stage, bar, bytes, speed, ETA.
 * Non-TTY / --no-progress: one plain line per 10% step (and per stage change)
 * so CI logs stay readable.
 */

#ifndef RCLI_PROGRESS_PROGRESS_BAR_H
#define RCLI_PROGRESS_PROGRESS_BAR_H

#include <mutex>
#include <string>

#include "download_service.pb.h"

namespace rcli::progress {

class ProgressRenderer {
   public:
    /** interactive=false forces plain-line mode. */
    explicit ProgressRenderer(bool interactive);

    void update(const runanywhere::v1::DownloadProgress& progress);

    /** Erase/terminate the in-place line (call before printing results). */
    void finish();

   private:
    std::string render_bar(float fraction, int width) const;

    bool interactive_;
    bool line_open_ = false;
    int last_step_ = -1;
    std::string last_stage_;
};

/**
 * RAII wrapper: registers the process-wide download progress callback and
 * renders updates for one model while alive (used by commands whose commons
 * call may auto-download, e.g. lifecycle load in `rcli run`). Only one scope
 * may be active per process at a time. Thread-safe — events arrive on
 * orchestrator worker threads.
 */
class DownloadProgressScope {
   public:
    DownloadProgressScope(std::string model_id, bool interactive);
    ~DownloadProgressScope();

   private:
    static void callback(const uint8_t* proto_bytes, size_t proto_size, void* user_data);

    std::mutex mutex_;
    ProgressRenderer renderer_;
    std::string model_id_;
};

}  // namespace rcli::progress

#endif  // RCLI_PROGRESS_PROGRESS_BAR_H
