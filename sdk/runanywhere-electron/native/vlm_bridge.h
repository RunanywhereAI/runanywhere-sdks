#ifndef RUNANYWHERE_ELECTRON_VLM_BRIDGE_H
#define RUNANYWHERE_ELECTRON_VLM_BRIDGE_H

#include <napi.h>

namespace rac_electron {

void RegisterVlmBridge(Napi::Env env, Napi::Object exports);

}  // namespace rac_electron

#endif  // RUNANYWHERE_ELECTRON_VLM_BRIDGE_H
