#include "progress/progress_bar.h"

#include <algorithm>
#include <cstdio>

#include "rac/infrastructure/download/rac_download_orchestrator.h"

#include "io/output.h"
#include "util/term.h"

namespace rcli::progress {

namespace {

const char* stage_label(runanywhere::v1::DownloadStage stage) {
    switch (stage) {
        case runanywhere::v1::DOWNLOAD_STAGE_DOWNLOADING:
            return "pulling";
        case runanywhere::v1::DOWNLOAD_STAGE_EXTRACTING:
            return "extracting";
        case runanywhere::v1::DOWNLOAD_STAGE_VALIDATING:
            return "verifying";
        case runanywhere::v1::DOWNLOAD_STAGE_COMPLETED:
            return "done";
        default:
            return "preparing";
    }
}

std::string speed_text(float bps) {
    if (bps <= 0) {
        return "";
    }
    return out::human_bytes(static_cast<uint64_t>(bps)) + "/s";
}

std::string eta_text(int64_t eta_seconds) {
    if (eta_seconds < 0) {
        return "";
    }
    char buf[32];
    if (eta_seconds >= 3600) {
        std::snprintf(buf, sizeof(buf), "%lldh%lldm", static_cast<long long>(eta_seconds / 3600),
                      static_cast<long long>((eta_seconds % 3600) / 60));
    } else if (eta_seconds >= 60) {
        std::snprintf(buf, sizeof(buf), "%lldm%llds", static_cast<long long>(eta_seconds / 60),
                      static_cast<long long>(eta_seconds % 60));
    } else {
        std::snprintf(buf, sizeof(buf), "%llds", static_cast<long long>(eta_seconds));
    }
    return buf;
}

float fraction_of(const runanywhere::v1::DownloadProgress& p) {
    if (p.overall_progress() > 0.0f) {
        return std::min(1.0f, p.overall_progress());
    }
    if (p.total_bytes() > 0) {
        return std::min(1.0f, static_cast<float>(p.bytes_downloaded()) /
                                  static_cast<float>(p.total_bytes()));
    }
    return 0.0f;
}

}  // namespace

ProgressRenderer::ProgressRenderer(bool interactive)
    : interactive_(interactive && term::stderr_is_tty()) {}

std::string ProgressRenderer::render_bar(float fraction, int width) const {
    const int filled = static_cast<int>(fraction * static_cast<float>(width));
    std::string bar = "▕";
    for (int i = 0; i < width; ++i) {
        bar += (i < filled) ? "█" : " ";
    }
    bar += "▏";
    return bar;
}

void ProgressRenderer::update(const runanywhere::v1::DownloadProgress& progress) {
    const float fraction = fraction_of(progress);
    const int percent = static_cast<int>(fraction * 100.0f);
    const std::string stage = stage_label(progress.stage());

    if (!interactive_) {
        // Plain mode: line per stage change or 10%-step.
        const int step = percent / 10;
        if (stage != last_stage_ || step != last_step_) {
            last_stage_ = stage;
            last_step_ = step;
            std::string line = stage + " " + progress.model_id() + " " +
                               std::to_string(percent) + "%";
            // bytes_downloaded is cumulative across a multi-file plan while
            // total_bytes is per-file — only show the pair when coherent.
            if (progress.total_bytes() > 0 &&
                progress.bytes_downloaded() <= progress.total_bytes()) {
                line += " (" + out::human_bytes(progress.bytes_downloaded()) + "/" +
                        out::human_bytes(progress.total_bytes()) + ")";
            }
            out::status_line(line);
        }
        return;
    }

    // Interactive: redraw one line.
    std::string line = stage + " " + progress.model_id() + " ";
    const int width = term::terminal_width();
    const int bar_width = std::clamp(width - static_cast<int>(line.size()) - 40, 10, 40);
    line += render_bar(fraction, bar_width);
    char pct[8];
    std::snprintf(pct, sizeof(pct), " %3d%%", percent);
    line += pct;
    if (progress.total_bytes() > 0 && progress.bytes_downloaded() <= progress.total_bytes()) {
        line += "  " + out::human_bytes(progress.bytes_downloaded()) + "/" +
                out::human_bytes(progress.total_bytes());
    }
    const std::string speed = speed_text(progress.overall_speed_bps());
    if (!speed.empty()) {
        line += "  " + speed;
    }
    const std::string eta = eta_text(progress.eta_seconds());
    if (!eta.empty()) {
        line += "  ETA " + eta;
    }
    if (progress.total_files() > 1) {
        line += "  [" + std::to_string(progress.current_file_index() + 1) + "/" +
                std::to_string(progress.total_files()) + "]";
    }

    std::fprintf(stderr, "\r\033[2K%s", line.c_str());
    std::fflush(stderr);
    line_open_ = true;
}

void ProgressRenderer::finish() {
    if (line_open_) {
        std::fprintf(stderr, "\n");
        std::fflush(stderr);
        line_open_ = false;
    }
}

// DownloadProgressScope

namespace {
DownloadProgressScope* g_active_scope = nullptr;
}

DownloadProgressScope::DownloadProgressScope(std::string model_id, bool interactive)
    : renderer_(interactive), model_id_(std::move(model_id)) {
    g_active_scope = this;
    rac_download_set_progress_proto_callback(&DownloadProgressScope::callback, nullptr);
}

DownloadProgressScope::~DownloadProgressScope() {
    rac_download_set_progress_proto_callback(nullptr, nullptr);
    g_active_scope = nullptr;
    std::lock_guard<std::mutex> lock(mutex_);
    renderer_.finish();
}

void DownloadProgressScope::callback(const uint8_t* proto_bytes, size_t proto_size,
                                     void* /*user_data*/) {
    DownloadProgressScope* scope = g_active_scope;
    if (!scope) {
        return;
    }
    runanywhere::v1::DownloadProgress progress;
    if (!progress.ParseFromArray(proto_bytes, static_cast<int>(proto_size))) {
        return;
    }
    std::lock_guard<std::mutex> lock(scope->mutex_);
    if (!scope->model_id_.empty() && progress.model_id() != scope->model_id_) {
        return;
    }
    scope->renderer_.update(progress);
    if (progress.state() == runanywhere::v1::DOWNLOAD_STATE_COMPLETED ||
        progress.state() == runanywhere::v1::DOWNLOAD_STATE_FAILED ||
        progress.state() == runanywhere::v1::DOWNLOAD_STATE_CANCELLED) {
        scope->renderer_.finish();
    }
}

}  // namespace rcli::progress
