// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "extraction.h"

#include <array>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <string>

#include <archive.h>
#include <archive_entry.h>

namespace ra::core::util {

namespace {

// RAII wrappers for libarchive handles so early returns don't leak.
struct ReadArchive {
    archive* h = nullptr;
    ReadArchive() : h(archive_read_new()) {
        archive_read_support_format_all(h);
        archive_read_support_filter_all(h);
    }
    ~ReadArchive() { if (h) archive_read_free(h); }
};
struct WriteArchive {
    archive* h = nullptr;
    WriteArchive() : h(archive_write_disk_new()) {
        const int flags = ARCHIVE_EXTRACT_TIME | ARCHIVE_EXTRACT_PERM |
                          ARCHIVE_EXTRACT_ACL  | ARCHIVE_EXTRACT_FFLAGS |
                          ARCHIVE_EXTRACT_SECURE_NODOTDOT |
                          ARCHIVE_EXTRACT_SECURE_SYMLINKS |
                          ARCHIVE_EXTRACT_SECURE_NOABSOLUTEPATHS;
        archive_write_disk_set_options(h, flags);
        archive_write_disk_set_standard_lookup(h);
    }
    ~WriteArchive() { if (h) archive_write_free(h); }
};

// Path-safety check. Returns true when `candidate` resolves to a
// descendant of `root` even after lexical normalization. libarchive's
// SECURE_NODOTDOT / SECURE_NOABSOLUTEPATHS flags handle most of the
// common attacks at the archive layer, but this belt-and-braces
// post-check catches edge cases (macOS resource forks, non-portable
// paths, backslash separators on zip entries written from Windows).
bool path_within_root(const std::filesystem::path& root,
                       const std::filesystem::path& candidate) {
    namespace fs = std::filesystem;
    const auto abs_root     = fs::weakly_canonical(root);
    const auto abs_candidate = fs::weakly_canonical(root / candidate);

    auto rit = abs_root.begin(),      rend = abs_root.end();
    auto cit = abs_candidate.begin(), cend = abs_candidate.end();
    while (rit != rend && cit != cend && *rit == *cit) {
        ++rit; ++cit;
    }
    return rit == rend;
}

bool skip_mac_resource_fork(std::string_view path) {
    // `._Foo` and `__MACOSX/` are macOS-specific sidecars we don't want
    // in the extracted tree.
    if (path.find("__MACOSX") != std::string_view::npos) return true;
    const auto slash = path.find_last_of('/');
    std::string_view base = (slash == std::string_view::npos)
                              ? path : path.substr(slash + 1);
    return base.size() >= 2 && base[0] == '.' && base[1] == '_';
}

}  // namespace

ExtractionResult extract_archive(std::string_view archive_path,
                                   std::string_view dest_dir,
                                   ExtractionProgressCallback on_progress) {
    ExtractionResult out;
    if (archive_path.empty() || dest_dir.empty()) {
        out.status = RA_ERR_INVALID_ARGUMENT;
        out.error_detail = "empty archive or destination path";
        return out;
    }

    namespace fs = std::filesystem;
    const fs::path dest(std::string{dest_dir});
    std::error_code ec;
    fs::create_directories(dest, ec);
    if (ec) {
        out.status = RA_ERR_IO;
        out.error_detail = "create_directories failed: " + ec.message();
        return out;
    }

    const std::string archive_s(archive_path);

    ReadArchive  reader;
    WriteArchive writer;
    if (!reader.h || !writer.h) {
        out.status = RA_ERR_OUT_OF_MEMORY;
        return out;
    }

    constexpr std::size_t kBlockSize = 64 * 1024;
    if (archive_read_open_filename(reader.h, archive_s.c_str(), kBlockSize)
            != ARCHIVE_OK) {
        out.status = RA_ERR_IO;
        out.error_detail = archive_error_string(reader.h);
        return out;
    }

    ExtractionProgress progress;
    archive_entry* entry = nullptr;
    while (true) {
        const int rc = archive_read_next_header(reader.h, &entry);
        if (rc == ARCHIVE_EOF) break;
        if (rc != ARCHIVE_OK && rc != ARCHIVE_WARN) {
            out.status = RA_ERR_IO;
            out.error_detail = archive_error_string(reader.h);
            return out;
        }

        const char* raw_path = archive_entry_pathname(entry);
        if (!raw_path) continue;
        const std::string entry_path = raw_path;

        if (skip_mac_resource_fork(entry_path)) {
            archive_read_data_skip(reader.h);
            continue;
        }
        if (!path_within_root(dest, fs::path(entry_path))) {
            out.status = RA_ERR_INTERNAL;
            out.error_detail = "zip-slip: entry escapes destination: " + entry_path;
            return out;
        }

        // Rewrite the pathname so libarchive extracts into dest_dir/<entry>.
        const fs::path full = dest / fs::path(entry_path);
        archive_entry_set_pathname(entry, full.c_str());

        if (archive_write_header(writer.h, entry) != ARCHIVE_OK) {
            out.status = RA_ERR_IO;
            out.error_detail = archive_error_string(writer.h);
            return out;
        }
        // Copy data blocks.
        const void* buff = nullptr;
        std::size_t size = 0;
        la_int64_t offset = 0;
        while (true) {
            const int r = archive_read_data_block(reader.h, &buff, &size, &offset);
            if (r == ARCHIVE_EOF) break;
            if (r != ARCHIVE_OK) {
                out.status = RA_ERR_IO;
                out.error_detail = archive_error_string(reader.h);
                return out;
            }
            if (archive_write_data_block(writer.h, buff, size, offset) != ARCHIVE_OK) {
                out.status = RA_ERR_IO;
                out.error_detail = archive_error_string(writer.h);
                return out;
            }
            progress.bytes_extracted += size;
        }
        if (archive_write_finish_entry(writer.h) != ARCHIVE_OK) {
            out.status = RA_ERR_IO;
            out.error_detail = archive_error_string(writer.h);
            return out;
        }
        ++progress.entries_done;
        if (on_progress) on_progress(progress);
    }

    out.ok            = true;
    out.status        = RA_OK;
    out.entries_total = progress.entries_done;
    out.bytes_total   = progress.bytes_extracted;
    return out;
}

ExtractionResult list_archive(std::string_view archive_path,
                                ArchiveEntryCallback on_entry) {
    ExtractionResult out;
    if (archive_path.empty() || !on_entry) {
        out.status = RA_ERR_INVALID_ARGUMENT;
        return out;
    }

    ReadArchive reader;
    if (!reader.h) {
        out.status = RA_ERR_OUT_OF_MEMORY;
        return out;
    }
    const std::string archive_s(archive_path);
    constexpr std::size_t kBlockSize = 64 * 1024;
    if (archive_read_open_filename(reader.h, archive_s.c_str(), kBlockSize)
            != ARCHIVE_OK) {
        out.status = RA_ERR_IO;
        out.error_detail = archive_error_string(reader.h);
        return out;
    }

    archive_entry* entry = nullptr;
    std::size_t n = 0, total = 0;
    while (true) {
        const int rc = archive_read_next_header(reader.h, &entry);
        if (rc == ARCHIVE_EOF) break;
        if (rc != ARCHIVE_OK && rc != ARCHIVE_WARN) {
            out.status = RA_ERR_IO;
            out.error_detail = archive_error_string(reader.h);
            return out;
        }
        ArchiveEntry e;
        {
            const char* p = archive_entry_pathname(entry);
            e.path = p ? p : "";
        }
        e.size       = static_cast<std::size_t>(archive_entry_size(entry));
        e.is_dir     = archive_entry_filetype(entry) == AE_IFDIR;
        e.is_symlink = archive_entry_filetype(entry) == AE_IFLNK;
        on_entry(e);
        ++n;
        total += e.size;
        archive_read_data_skip(reader.h);
    }

    out.ok            = true;
    out.status        = RA_OK;
    out.entries_total = n;
    out.bytes_total   = total;
    return out;
}

}  // namespace ra::core::util
