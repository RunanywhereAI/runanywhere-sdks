#ifndef RUNANYWHERE_ELECTRON_DOWNLOAD_BRIDGE_H
#define RUNANYWHERE_ELECTRON_DOWNLOAD_BRIDGE_H

#include <napi.h>

namespace rac_electron {

void RegisterDownloadBridge(Napi::Env env, Napi::Object exports);

// Detach the process-wide DownloadProgress callback and release the
// ThreadSafeFunction behind it. Called from shutdown() so a teardown cannot
// leave commons holding a pointer into a finalized N-API environment.
void ShutdownDownloadBridge();

}  // namespace rac_electron

#endif  // RUNANYWHERE_ELECTRON_DOWNLOAD_BRIDGE_H
