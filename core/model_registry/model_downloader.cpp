// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Default model downloader implementation.
//
// For the MVP this is a stub that returns RA_ERR_RUNTIME_UNAVAILABLE. The
// real implementations go in model_downloader_apple.mm (NSURLSession),
// model_downloader_android.cpp (HttpURLConnection via JNI), and
// model_downloader_curl.cpp (libcurl, used on Linux and WASM with
// emscripten-fetch). Each is selected by CMake based on RA_PLATFORM.

#include "model_downloader.h"

#include <memory>

namespace ra::core {

namespace {

class StubDownloader : public ModelDownloader {
public:
    ra_status_t fetch(std::string_view, std::string_view,
                      std::string_view, ProgressCallback) override {
        return RA_ERR_RUNTIME_UNAVAILABLE;
    }
};

}  // namespace

std::unique_ptr<ModelDownloader> ModelDownloader::create() {
    return std::make_unique<StubDownloader>();
}

}  // namespace ra::core
