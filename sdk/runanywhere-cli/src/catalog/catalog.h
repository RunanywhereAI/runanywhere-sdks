/**
 * @file catalog.h
 * @brief Built-in model catalog — the CLI's curated equivalent of the example
 *        apps' ModelCatalog (iOS ModelCatalogBootstrap.swift is the canonical
 *        reference; ids/URLs are copied verbatim from the app catalogs and the
 *        commons test tooling).
 *
 * Entries use the proto-generated enums (structured-types rule) and register
 * through the same single-call commons entry points the SDKs use:
 * rac_register_model_from_url_proto / rac_register_multi_file_model_proto.
 * Registration is idempotent per process (the registry is in-memory; apps
 * re-register their catalogs on every launch the same way).
 */

#ifndef RCLI_CATALOG_CATALOG_H
#define RCLI_CATALOG_CATALOG_H

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

#include "model_types.pb.h"
#include "rac/core/rac_types.h"

namespace rcli::catalog {

struct CatalogFile {
  const char *url;
  const char *filename;
  bool required;
  int64_t size_bytes = 0;
};

struct CatalogEntry {
  const char *id;
  const char *alias; // short name accepted by `pull/run/...` (nullptr = none)
  const char *name;
  runanywhere::v1::ModelCategory category;
  runanywhere::v1::InferenceFramework framework;
  runanywhere::v1::ModelFormat format;
  const char *url; // single-file / archive primary (nullptr → multi-file)
  const CatalogFile *files; // multi-file artifacts (VLM pairs, embeddings)
  size_t file_count;
  int64_t download_size_bytes; // approximate, for display/planning
  int32_t context_length;      // 0 = unknown/not applicable
  bool supports_thinking;
};

/** All built-in entries. */
const CatalogEntry *all(size_t *count);

/** Exact id or alias lookup (nullptr when unknown). */
const CatalogEntry *find(const std::string &id_or_alias);

/** Closest-match candidates for error messages (substring match, ≤ max). */
std::vector<std::string> suggestions(const std::string &input, size_t max);

/**
 * Register every entry with the global model registry. Logs (does not fail
 * on) individual rejections so one bad entry can't take the CLI down.
 */
rac_result_t register_all();

} // namespace rcli::catalog

#endif // RCLI_CATALOG_CATALOG_H
