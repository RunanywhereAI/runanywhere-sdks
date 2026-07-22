// Content-addressed blob store for de-duplicating downloaded model files.
//
// Multimodal / multi-bundle models (e.g. Cosmos3-Edge = text + VLM + diffusion)
// share large weight files whose bytes are identical across bundles/repos (same
// HuggingFace LFS oid == same sha256). Storage is keyed by model_id, so without
// de-dup the shared decoder is downloaded and stored once per model.
//
// This store keeps ONE physical copy per unique content hash under
//   {base}/RunAnywhere/Models/.blobs/<sha256>
// and each per-model file becomes a relative SYMLINK into it. N models referencing
// the same content cost the bytes once, and each model still sees a normal file at
// its expected path (mmap/open follow the symlink, so the loader is unchanged — no
// engine/manifest change).
//
// Why symlinks, not hardlinks: Android denies hardlinks on app-private storage
// (f2fs + SELinux/protected_hardlinks), but permits symlinks. Symlinks carry no
// filesystem refcount, so GC is a mark-sweep: scan the model tree for symlinks that
// still target a blob, then delete any blob nobody references (see gc_orphans).
//
// Native-only: on Emscripten/OPFS symlinks don't exist, so the whole store is
// disabled (every function is a no-op / returns false) and behavior is byte-
// identical to the pre-dedup path (each model keeps its own copy).

#pragma once

#include <cstdint>
#include <string>

namespace rac::download::blob_store {

// True when the store is usable on this build/platform (native FS with
// hardlinks). Web/OPFS builds return false and all other calls are no-ops.
bool enabled();

// Absolute path of the blob for `sha256_hex` (does not create anything).
std::string blob_path(const std::string& sha256_hex);

// De-dup HIT: if a verified blob for `sha256_hex` already exists (and, when
// `expected_bytes > 0`, its size matches), hardlink it into `dest` and return
// true — the caller then SKIPS the network download entirely. Returns false when
// the store is disabled, the hash is empty, no blob exists, or the link fails
// (caller falls back to a normal download).
bool link_from_blob(const std::string& sha256_hex, int64_t expected_bytes,
                    const std::string& dest);

// PROMOTE: after `dest` has been downloaded and sha-verified, publish it into the
// store so future models de-dup against it. Best-effort: ensures `dest` ends up
// sharing the store blob's inode. No-op on empty hash / disabled store / failure
// (leaves `dest` as a valid standalone file). Safe under concurrent promotes.
void promote(const std::string& sha256_hex, const std::string& dest);

// Garbage-collect orphaned blobs: scan the model tree for symlinks still targeting
// a blob, then delete any blob nobody references (every model that used it has been
// deleted). Returns bytes reclaimed. O(total model files) mark-sweep; safe and
// cheap to call after any model deletion.
int64_t gc_orphans();

}  // namespace rac::download::blob_store
