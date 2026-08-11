#ifndef RUNANYWHERE_ELECTRON_AUDIO_BRIDGE_H
#define RUNANYWHERE_ELECTRON_AUDIO_BRIDGE_H

#include <napi.h>

namespace rac_electron {

void RegisterAudioBridge(Napi::Env env, Napi::Object exports);

}  // namespace rac_electron

#endif  // RUNANYWHERE_ELECTRON_AUDIO_BRIDGE_H
