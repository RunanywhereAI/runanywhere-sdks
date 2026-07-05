/**
 * @file rac_extraction.cpp
 * @brief Native archive extraction implementation using libarchive.
 *
 * Streaming extraction with constant memory usage regardless of archive size.
 * Supports ZIP, TAR.GZ, TAR.BZ2, TAR.XZ with auto-detection via magic bytes.
 *
 * Edge cases handled:
 *   - Magic-byte auto-detect with size guards (zip/gzip/bzip2/xz/ustar),
 *     detect_archive_kind_from_bytes; a detected-vs-hint mismatch →
 *     RAC_ERROR_UNSUPPORTED_ARCHIVE.
 *   - Zip-slip: is_path_safe rejects absolute / .. / UNC / drive-letter entry
 *     paths.
 *   - macOS resource forks: should_skip_entry skips __MACOSX/ and ._* entries.
 *   - Symlinks: skipped when skip_symlinks, else rejected if the target is
 *     absolute or contains ".."; hardlinks rewritten under the destination with
 *     the same safety check.
 *   - No-subprocess filters: only built-in zlib/bzip2/xz are registered (NOT
 *     support_filter_all) so iOS/WASM sandboxes never fork+exec /usr/bin/gzip.
 *   - Streaming, constant memory regardless of archive size; per-entry
 *     header/data errors are logged and skipped or aborted.
 *   - Missing archive / null args → RAC_ERROR_FILE_NOT_FOUND /
 *     RAC_ERROR_NULL_POINTER.
 */

#include "rac/infrastructure/extraction/rac_extraction.h"

#include <archive.h>
#include <archive_entry.h>

#include <cerrno>
#include <cstdio>
#include <cstring>
#include <string>

#include "core/internal/platform_compat.h"

#ifdef _WIN32
#include <direct.h>  // for _mkdir
#endif

#include "rac/core/rac_logger.h"

static const char* kLogTag = "Extraction";

// INTERNAL HELPERS

enum class archive_kind {
    unknown,
    zip,
    tar,
    tar_gz,
    tar_bz2,
    tar_xz,
};

static archive_kind kind_from_archive_type(rac_archive_type_t type) {
    switch (type) {
        case RAC_ARCHIVE_TYPE_ZIP:
            return archive_kind::zip;
        case RAC_ARCHIVE_TYPE_TAR_BZ2:
            return archive_kind::tar_bz2;
        case RAC_ARCHIVE_TYPE_TAR_GZ:
            return archive_kind::tar_gz;
        case RAC_ARCHIVE_TYPE_TAR_XZ:
            return archive_kind::tar_xz;
        case RAC_ARCHIVE_TYPE_NONE:
        default:
            return archive_kind::unknown;
    }
}

static bool archive_kind_to_archive_type(archive_kind kind, rac_archive_type_t* out_type) {
    if (!out_type) {
        return false;
    }
    switch (kind) {
        case archive_kind::zip:
            *out_type = RAC_ARCHIVE_TYPE_ZIP;
            return true;
        case archive_kind::tar_bz2:
            *out_type = RAC_ARCHIVE_TYPE_TAR_BZ2;
            return true;
        case archive_kind::tar_gz:
            *out_type = RAC_ARCHIVE_TYPE_TAR_GZ;
            return true;
        case archive_kind::tar_xz:
            *out_type = RAC_ARCHIVE_TYPE_TAR_XZ;
            return true;
        case archive_kind::tar:
        case archive_kind::unknown:
        default:
            return false;
    }
}

static const char* archive_kind_name(archive_kind kind) {
    switch (kind) {
        case archive_kind::zip:
            return "zip";
        case archive_kind::tar:
            return "tar";
        case archive_kind::tar_gz:
            return "tar.gz";
        case archive_kind::tar_bz2:
            return "tar.bz2";
        case archive_kind::tar_xz:
            return "tar.xz";
        case archive_kind::unknown:
        default:
            return "unknown";
    }
}

static archive_kind detect_archive_kind_from_bytes(const unsigned char* bytes, size_t size) {
    if (!bytes || size < 2) {
        return archive_kind::unknown;
    }

    // ZIP: local file header, empty archive end-of-central-directory, or
    // spanned/split archive marker.
    if (size >= 4 && bytes[0] == 0x50 && bytes[1] == 0x4B &&
        ((bytes[2] == 0x03 && bytes[3] == 0x04) || (bytes[2] == 0x05 && bytes[3] == 0x06) ||
         (bytes[2] == 0x07 && bytes[3] == 0x08))) {
        return archive_kind::zip;
    }

    // GZIP (tar.gz): \x1f\x8b
    if (bytes[0] == 0x1F && bytes[1] == 0x8B) {
        return archive_kind::tar_gz;
    }

    // BZIP2 (tar.bz2): BZh
    if (size >= 3 && bytes[0] == 0x42 && bytes[1] == 0x5A && bytes[2] == 0x68) {
        return archive_kind::tar_bz2;
    }

    // XZ (tar.xz): \xFD7zXZ\x00
    if (size >= 6 && bytes[0] == 0xFD && bytes[1] == 0x37 && bytes[2] == 0x7A && bytes[3] == 0x58 &&
        bytes[4] == 0x5A && bytes[5] == 0x00) {
        return archive_kind::tar_xz;
    }

    // POSIX tar: "ustar" at offset 257.
    if (size >= 262 && memcmp(bytes + 257, "ustar", 5) == 0) {
        return archive_kind::tar;
    }

    return archive_kind::unknown;
}

// Probe the first <=512 bytes for an archive magic signature.
//
// Intentionally uses stdio FILE here rather than the platform adapter's
// file_read slot: rac_platform_adapter_t::file_read (and the file_manager
// rac_file_callbacks_t) are WHOLE-FILE only — they have no bounded/offset
// read. Routing a 512-byte magic probe through file_read would allocate and
// copy the entire archive (multi-GB GGUF/ONNX bundles) into memory just to
// read the header, an OOM risk and a clear pessimization. Adding a bounded
// read slot would be an ABI change across all 5 SDK populators + pinned
// headers + the WASM offset table, which is not justified for a header probe.
// This is native/host-side extraction code anyway: libarchive itself opens
// the archive with raw FILE I/O immediately below (archive_read_open_filename),
// so the fopen here matches the surrounding code. fread is hard-bounded to
// sizeof(bytes) and detect_archive_kind_from_bytes re-validates size before
// every offset access, so this path is memory-safe.
static archive_kind detect_archive_kind_from_file(const char* file_path) {
    if (!file_path) {
        return archive_kind::unknown;
    }

    FILE* f = fopen(file_path, "rb");
    if (!f) {
        return archive_kind::unknown;
    }

    unsigned char bytes[512] = {0};
    size_t bytes_read = fread(bytes, 1, sizeof(bytes), f);
    fclose(f);

    return detect_archive_kind_from_bytes(bytes, bytes_read);
}

/**
 * Security: Check for path traversal (zip-slip attack).
 * Rejects absolute paths and paths containing ".." components.
 */
static bool is_path_safe(const char* pathname) {
    if (!pathname || pathname[0] == '\0')
        return false;

    // Reject absolute paths (Unix)
    if (pathname[0] == '/')
        return false;

    // Reject Windows UNC paths (\\server\share)
    if (pathname[0] == '\\' && pathname[1] == '\\')
        return false;

    // Reject Windows drive letters (C:, D:, etc.)
    if (((pathname[0] >= 'A' && pathname[0] <= 'Z') ||
         (pathname[0] >= 'a' && pathname[0] <= 'z')) &&
        pathname[1] == ':') {
        return false;
    }

    // Normalize and check for ".." components (handle both / and \ separators)
    const char* p = pathname;
    while (*p != '\0') {
        if (p[0] == '.' && p[1] == '.') {
            bool at_start = (p == pathname || *(p - 1) == '/' || *(p - 1) == '\\');
            bool at_end = (p[2] == '/' || p[2] == '\\' || p[2] == '\0');
            if (at_start && at_end) {
                return false;
            }
        }
        p++;
    }
    return true;
}

/**
 * Check if an entry should be skipped (macOS resource forks, etc.).
 */
static bool should_skip_entry(const char* pathname, rac_bool_t skip_macos) {
    if (!pathname || pathname[0] == '\0')
        return true;

    if (skip_macos == RAC_TRUE) {
        // Skip __MACOSX/ directory and its contents
        if (strstr(pathname, "__MACOSX") != nullptr)
            return true;

        // Skip ._ resource fork files
        const char* basename = strrchr(pathname, '/');
        basename = basename ? basename + 1 : pathname;
        if (basename[0] == '.' && basename[1] == '_')
            return true;
    }
    return false;
}

/**
 * Create a directory and all intermediate directories.
 * Equivalent to `mkdir -p`.
 */
static rac_result_t create_directories(const std::string& path) {
    if (path.empty())
        return RAC_SUCCESS;

    std::string current;
    for (size_t i = 0; i < path.size(); i++) {
        current += path[i];
        if (path[i] == '/' || i == path.size() - 1) {
            if (current == "/")
                continue;
#ifdef _WIN32
            int ret = _mkdir(current.c_str());
#else
            int ret = mkdir(current.c_str(), 0755);
#endif
            if (ret != 0 && errno != EEXIST) {
                // Check if it already exists as a directory
                struct stat st;
                if (stat(current.c_str(), &st) != 0 || !S_ISDIR(st.st_mode)) {
                    return RAC_ERROR_EXTRACTION_FAILED;
                }
            }
        }
    }
    return RAC_SUCCESS;
}

/**
 * Ensure trailing slash on directory path.
 */
static std::string ensure_trailing_slash(const std::string& path) {
    if (path.empty() || path.back() == '/')
        return path;
    return path + '/';
}

// PUBLIC API - rac_extract_archive_native

rac_result_t rac_extract_archive_native(const char* archive_path, const char* destination_dir,
                                        const rac_extraction_options_t* options,
                                        rac_extraction_progress_fn progress_callback,
                                        void* user_data, rac_extraction_result_t* out_result) {
    if (!archive_path || !destination_dir) {
        return RAC_ERROR_NULL_POINTER;
    }

    // Check archive file exists
    struct stat archive_stat;
    if (stat(archive_path, &archive_stat) != 0) {
        RAC_LOG_ERROR(kLogTag, "Archive file not found: %s", archive_path);
        return RAC_ERROR_FILE_NOT_FOUND;
    }

    // Use defaults if no options provided
    rac_extraction_options_t opts = options ? *options : RAC_EXTRACTION_OPTIONS_DEFAULT;

    archive_kind detected_kind = detect_archive_kind_from_file(archive_path);
    archive_kind explicit_hint_kind = kind_from_archive_type(opts.archive_type_hint);
    if (detected_kind != archive_kind::unknown && explicit_hint_kind != archive_kind::unknown &&
        detected_kind != explicit_hint_kind) {
        RAC_LOG_ERROR(kLogTag, "Archive type mismatch for %s: detected %s, expected %s",
                      archive_path, archive_kind_name(detected_kind),
                      archive_kind_name(explicit_hint_kind));
        return RAC_ERROR_UNSUPPORTED_ARCHIVE;
    }

    // Create destination directory
    rac_result_t dir_result = create_directories(destination_dir);
    if (RAC_FAILED(dir_result)) {
        RAC_LOG_ERROR(kLogTag, "Failed to create destination directory: %s", destination_dir);
        return RAC_ERROR_EXTRACTION_FAILED;
    }

    std::string dest_dir = ensure_trailing_slash(destination_dir);

    RAC_LOG_INFO(kLogTag, "Extracting archive: %s -> %s", archive_path, destination_dir);

    // Open archive for reading (streaming)
    struct archive* a = archive_read_new();
    if (!a) {
        RAC_LOG_ERROR(kLogTag, "Failed to allocate archive reader");
        return RAC_ERROR_EXTRACTION_FAILED;
    }

    // Enable all supported formats for auto-detection.
    archive_read_support_format_all(a);
    // Register ONLY the built-in
    // decompression filters that link against statically-bundled libraries
    // (zlib, bzip2, xz). DO NOT call archive_read_support_filter_all() — that
    // registers libarchive's `program("gzip -d" / "bzip2 -d" / "xz -d")`
    // external-program fallbacks whenever the matching built-in symbol is
    // missing at link time. iOS (Swift + Flutter) sandboxes block
    // `fork+exec(/usr/bin/gzip)`, so any tar.gz extraction (Sherpa Whisper Tiny,
    // SmolVLM, Piper TTS) silently failed with an obscure errno=1 from the
    // child shell. Emscripten / WASM likewise has no subprocess primitive.
    //
    // Keeping the registration explicit also makes the failure mode loud and
    // testable: if zlib is somehow not linked, archive_read_open_filename will
    // surface a clear "gzip: unsupported compression" error instead of trying
    // (and failing) to fork a non-existent /usr/bin/gzip.
    archive_read_support_filter_none(a);
    archive_read_support_filter_gzip(a);
    archive_read_support_filter_bzip2(a);
    archive_read_support_filter_xz(a);

    // Open the archive file with 10KB block size (streaming)
    int r = archive_read_open_filename(a, archive_path, 10240);
    if (r != ARCHIVE_OK) {
        const char* err = archive_error_string(a);
        RAC_LOG_ERROR(kLogTag, "Failed to open archive: %s (%s)", archive_path,
                      err ? err : "unknown error");
        archive_read_free(a);
        return RAC_ERROR_UNSUPPORTED_ARCHIVE;
    }

    // Prepare disk writer for extraction
    struct archive* ext = archive_write_disk_new();
    if (!ext) {
        RAC_LOG_ERROR(kLogTag, "Failed to allocate disk writer");
        archive_read_free(a);
        return RAC_ERROR_EXTRACTION_FAILED;
    }

    // Set extraction flags: preserve timestamps and permissions
    int flags = ARCHIVE_EXTRACT_TIME | ARCHIVE_EXTRACT_PERM;
    archive_write_disk_set_options(ext, flags);
    archive_write_disk_set_standard_lookup(ext);

    // Extract entries (streaming loop)
    rac_extraction_result_t result = {0, 0, 0, 0};
    struct archive_entry* entry;
    rac_result_t status = RAC_SUCCESS;

    while (true) {
        r = archive_read_next_header(a, &entry);
        if (r == ARCHIVE_EOF)
            break;

        if (r != ARCHIVE_OK && r != ARCHIVE_WARN) {
            const char* err = archive_error_string(a);
            RAC_LOG_ERROR(kLogTag, "Error reading archive entry: %s", err ? err : "unknown");
            status = RAC_ERROR_EXTRACTION_FAILED;
            break;
        }

        const char* pathname = archive_entry_pathname(entry);
        if (!pathname) {
            archive_read_data_skip(a);
            continue;
        }

        // Security: zip-slip protection
        if (!is_path_safe(pathname)) {
            RAC_LOG_WARNING(kLogTag, "Skipping unsafe path: %s", pathname);
            result.entries_skipped++;
            archive_read_data_skip(a);
            continue;
        }

        // Skip macOS resource forks
        if (should_skip_entry(pathname, opts.skip_macos_resources)) {
            result.entries_skipped++;
            archive_read_data_skip(a);
            continue;
        }

        // Handle symbolic links
        unsigned int entry_type = archive_entry_filetype(entry);
        if (entry_type == AE_IFLNK) {
            if (opts.skip_symlinks == RAC_TRUE) {
                result.entries_skipped++;
                archive_read_data_skip(a);
                continue;
            }
            // Safety: reject symlinks pointing outside destination
            const char* link_target = archive_entry_symlink(entry);
            if (link_target && (link_target[0] == '/' || strstr(link_target, "..") != nullptr)) {
                RAC_LOG_WARNING(kLogTag, "Skipping unsafe symlink: %s -> %s", pathname,
                                link_target);
                result.entries_skipped++;
                archive_read_data_skip(a);
                continue;
            }
        }

        // Rewrite path to be under destination directory
        std::string full_path = dest_dir + pathname;
        archive_entry_set_pathname(entry, full_path.c_str());

        // Also rewrite hardlink paths if present (with safety check)
        const char* hardlink = archive_entry_hardlink(entry);
        if (hardlink && hardlink[0] != '\0') {
            if (!is_path_safe(hardlink)) {
                RAC_LOG_WARNING(kLogTag, "Skipping unsafe hardlink target: %s -> %s", pathname,
                                hardlink);
                result.entries_skipped++;
                archive_read_data_skip(a);
                continue;
            }
            std::string full_hardlink = dest_dir + hardlink;
            archive_entry_set_hardlink(entry, full_hardlink.c_str());
        }

        // Write entry header (creates file/directory on disk)
        r = archive_write_header(ext, entry);
        if (r != ARCHIVE_OK) {
            const char* err = archive_error_string(ext);
            RAC_LOG_WARNING(kLogTag, "Failed to write header for: %s (%s)", pathname,
                            err ? err : "unknown");
            archive_read_data_skip(a);
            continue;
        }

        // Copy file data (streaming, constant memory)
        if (archive_entry_size(entry) > 0 && entry_type == AE_IFREG) {
            const void* buff;
            size_t size;
            la_int64_t offset;

            bool data_error = false;
            while (true) {
                r = archive_read_data_block(a, &buff, &size, &offset);
                if (r == ARCHIVE_EOF)
                    break;
                if (r != ARCHIVE_OK) {
                    const char* err = archive_error_string(a);
                    RAC_LOG_ERROR(kLogTag, "Error reading data for: %s (%s)", pathname,
                                  err ? err : "unknown");
                    data_error = true;
                    break;
                }
                r = archive_write_data_block(ext, buff, size, offset);
                if (r != ARCHIVE_OK) {
                    const char* err = archive_error_string(ext);
                    RAC_LOG_ERROR(kLogTag, "Error writing data for: %s (%s)", pathname,
                                  err ? err : "unknown");
                    data_error = true;
                    break;
                }
                result.bytes_extracted += static_cast<int64_t>(size);
            }
            if (data_error) {
                status = RAC_ERROR_EXTRACTION_FAILED;
                break;
            }
        }

        // Finish entry (sets permissions, timestamps)
        archive_write_finish_entry(ext);

        // Track statistics
        if (entry_type == AE_IFDIR) {
            result.directories_created++;
        } else if (entry_type == AE_IFREG) {
            result.files_extracted++;
        }

        // Progress callback
        if (progress_callback) {
            progress_callback(result.files_extracted, 0 /* total unknown in streaming */,
                              result.bytes_extracted, user_data);
        }
    }

    // Cleanup
    archive_read_free(a);
    archive_write_free(ext);

    // Output result
    if (out_result) {
        *out_result = result;
    }

    if (RAC_SUCCEEDED(status)) {
        RAC_LOG_INFO(kLogTag, "Extraction complete: %d files, %d dirs, %lld bytes, %d skipped",
                     result.files_extracted, result.directories_created,
                     static_cast<long long>(result.bytes_extracted), result.entries_skipped);
    }

    return status;
}

rac_result_t rac_extract_model_archive_native(const char* archive_path, const char* destination_dir,
                                              const rac_model_info_t* model_info,
                                              const char* expected_primary_sha256,
                                              const rac_extraction_options_t* options,
                                              rac_extraction_progress_fn progress_callback,
                                              void* user_data,
                                              rac_model_extraction_result_t* out_result) {
    if (!archive_path || !destination_dir || !model_info || !out_result) {
        return RAC_ERROR_NULL_POINTER;
    }

    memset(out_result, 0, sizeof(*out_result));
    out_result->archive_type = RAC_ARCHIVE_TYPE_NONE;
    rac_archive_type_t detected_type = RAC_ARCHIVE_TYPE_NONE;
    archive_kind detected_kind = detect_archive_kind_from_file(archive_path);
    if (archive_kind_to_archive_type(detected_kind, &detected_type)) {
        out_result->archive_type = detected_type;
    } else if (options && options->archive_type_hint != RAC_ARCHIVE_TYPE_NONE) {
        out_result->archive_type = options->archive_type_hint;
    } else if (model_info->artifact_info.kind == RAC_ARTIFACT_KIND_ARCHIVE) {
        out_result->archive_type = model_info->artifact_info.archive_type;
    }

    rac_result_t rc =
        rac_extract_archive_native(archive_path, destination_dir, options, progress_callback,
                                   user_data, &out_result->extraction);
    if (RAC_FAILED(rc)) {
        return rc;
    }

    return rac_model_paths_resolve_artifact(model_info, destination_dir, expected_primary_sha256,
                                            &out_result->resolution);
}

void rac_model_extraction_result_free(rac_model_extraction_result_t* result) {
    if (!result)
        return;
    rac_model_path_resolution_free(&result->resolution);
    memset(&result->extraction, 0, sizeof(result->extraction));
    result->archive_type = RAC_ARCHIVE_TYPE_NONE;
}

// PUBLIC API - rac_detect_archive_type

rac_bool_t rac_detect_archive_type(const char* file_path, rac_archive_type_t* out_type) {
    if (!file_path || !out_type)
        return RAC_FALSE;

    return archive_kind_to_archive_type(detect_archive_kind_from_file(file_path), out_type)
               ? RAC_TRUE
               : RAC_FALSE;
}
