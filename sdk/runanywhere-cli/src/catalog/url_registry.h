/**
 * @file url_registry.h
 * @brief Persistence for user-registered (non-catalog) models.
 *
 * The commons model registry is in-memory; every SDK re-registers its catalog
 * each launch and owns persistence for user-added models. rcli's catalog
 * entries re-register from the built-in table, and models pulled from raw
 * URLs / hf.co refs are persisted here as serialized ModelInfo sidecars under
 * <storage root>/Registry/<id>.binpb, then re-registered on every bootstrap —
 * so `rcli pull <url>` survives across invocations like `ollama pull` does.
 */

#ifndef RCLI_CATALOG_URL_REGISTRY_H
#define RCLI_CATALOG_URL_REGISTRY_H

#include <string>

namespace rcli::url_registry {

/** Re-register every persisted sidecar with the in-memory registry. */
void register_all_persisted();

/** Persist a saved ModelInfo (serialized bytes) for re-registration. */
void persist(const std::string& model_id, const std::string& model_info_bytes);

/** Drop the sidecar for a model id (no-op when absent). */
void forget(const std::string& model_id);

}  // namespace rcli::url_registry

#endif  // RCLI_CATALOG_URL_REGISTRY_H
