#ifndef RAC_INFRASTRUCTURE_DOWNLOAD_PARTIAL_DOWNLOAD_INTERNAL_H
#define RAC_INFRASTRUCTURE_DOWNLOAD_PARTIAL_DOWNLOAD_INTERNAL_H

// Internal (not installed): the in-flight-partial filename convention.
//
// rac_http_download streams a transfer into "<destination>.part" and promotes it
// to "<destination>" with a single atomic rename only after size/checksum
// validation. So a ".part" file is the one thing on disk that proves a download
// did NOT finish — the final path is written exactly once, by that rename.
//
// Four call sites depend on that: the writer that creates it, the orchestrator
// that measures it for resume offsets, the folder deleter that reclaims it, and
// the registry rescan that must NOT mistake it for a finished artifact. It lived
// as a bare ".part" literal in each, which is how a folder holding only a
// half-written partial came to be relinked as a downloaded model. One definition
// here so "is this file a finished artifact?" has one answer.

#include <string_view>

namespace rac::download {

inline constexpr std::string_view kPartialSuffix = ".part";

// True when `filename` is an in-flight partial rather than a finished artifact.
// Suffix-exact: this process is the only producer, and it always writes the
// lowercase suffix above.
inline bool is_partial_download_filename(std::string_view filename) {
    return filename.size() > kPartialSuffix.size() && filename.ends_with(kPartialSuffix);
}

}  // namespace rac::download

#endif  // RAC_INFRASTRUCTURE_DOWNLOAD_PARTIAL_DOWNLOAD_INTERNAL_H
