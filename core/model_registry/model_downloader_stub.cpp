// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Stub ModelDownloader used when RA_BUILD_MODEL_DOWNLOADER=OFF. Returns
// nullptr from create() so callers fall through to the platform-
// adapter download path (URLSession on Apple, OkHttp on Android, etc).

#include "model_downloader.h"

namespace ra::core {

std::unique_ptr<ModelDownloader> ModelDownloader::create() {
    return nullptr;
}

}  // namespace ra::core
