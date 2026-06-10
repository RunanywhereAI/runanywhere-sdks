/**
 * PlatformPluginBridge.mm
 *
 * Objective-C++ wiring for the Apple "platform" engine plugin (AVSpeechSynthesizer-
 * backed System TTS). Mirrors Swift's `CppBridge+Platform.swift` so the
 * commons router can resolve `framework == .systemTts` model loads through
 * the platform vtable on iOS/macOS.
 *
 * Why this file exists:
 *   `rac_backend_platform_register()` only registers the module + built-in
 *   catalog entries; it does NOT wire the unified plugin vtable into the
 *   plugin router. Without this step the router has no `platform` engine
 *   so `loadModel` for `framework == .systemTts` returns "no backend route
 *   supports requested model for framework platform". This file:
 *     1. Implements AVSpeechSynthesizer-backed C trampolines.
 *     2. Calls `rac_platform_tts_set_callbacks(...)`.
 *     3. Calls `rac_backend_platform_register()`.
 *     4. Calls `rac_plugin_register(rac_plugin_entry_platform())` so the
 *        router can actually find the platform vtable.
 *
 * Mirrors the Swift SDK path:
 *   sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+Platform.swift
 *   sdk/runanywhere-swift/Sources/RunAnywhere/Features/TTS/System/SystemTTSService.swift
 *
 * Apple-only — Android has no commons-level platform-TTS plugin (see
 * sdk/runanywhere-commons/CMakeLists.txt:732 `if(APPLE AND RAC_BUILD_PLATFORM)`).
 */

#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>

#include <atomic>
#include <mutex>
#include <os/log.h>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/platform/rac_llm_platform.h"
#include "rac/features/platform/rac_tts_platform.h"
#include "rac/plugin/rac_plugin_entry.h"

// rac_backend_platform_register lives in rac_llm_platform.h on iOS.
extern "C" rac_result_t rac_backend_platform_register(void);

// rac_plugin_entry_platform() is defined in commons (Apple-only TU) but
// not exposed via a public header. Forward-declare here so the ObjC++
// linker resolves it from RACommons.xcframework. Signature matches the
// RAC_PLUGIN_ENTRY_DEF(platform) definition in
// sdk/runanywhere-commons/src/features/platform/rac_plugin_entry_platform.cpp.
extern "C" const rac_engine_vtable_t* rac_plugin_entry_platform(void);

// =============================================================================
// Logging — `log stream --predicate 'subsystem CONTAINS "com.runanywhere"'`
// =============================================================================
namespace {

inline os_log_t ra_platform_log() {
    static os_log_t logger = nullptr;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        logger = os_log_create("com.runanywhere", "PlatformPluginBridge");
    });
    return logger;
}

}  // namespace

#define RA_PLATFORM_LOG_INFO(fmt, ...)  os_log_info(ra_platform_log(), fmt, ##__VA_ARGS__)
#define RA_PLATFORM_LOG_DEBUG(fmt, ...) os_log_debug(ra_platform_log(), fmt, ##__VA_ARGS__)
#define RA_PLATFORM_LOG_ERROR(fmt, ...) os_log_error(ra_platform_log(), fmt, ##__VA_ARGS__)

// Upper bound for a single synthesize call. Speech finishes well inside this;
// exceeding it indicates a stall, surfaced as RAC_ERROR_TIMEOUT rather than a
// permanent hang. Matches the 120s bound in the iOS Swift SDK reference
// (CppBridge+Platform.swift `callbackTimeout`).
static constexpr int64_t kSynthesizeTimeoutSeconds = 120;

// =============================================================================
// System TTS Service — AVSpeechSynthesizer wrapper
// =============================================================================

/**
 * Drives AVSpeechSynthesizer for the platform TTS callbacks. Each
 * `rac_platform_tts_create_fn` invocation returns one of these (wrapped in
 * `rac_handle_t`). The C ABI `synthesize` callback is synchronous, so this
 * blocks the caller until playback completes — but the wait is bounded and
 * never blocks the main thread on a semaphore the main thread itself would
 * have to signal (see -speakText:). This mirrors the iOS Swift SDK reference
 * `CppBridge+Platform.swift`, which runs the work off the caller's actor via
 * `Task.detached` and waits on a bounded `DispatchSemaphore` instead of
 * `DispatchGroup.wait()` / `DispatchQueue.main.sync`.
 */
@interface RAFlutterSystemTTSService : NSObject <AVSpeechSynthesizerDelegate>
@property(nonatomic, strong) AVSpeechSynthesizer* synthesizer;
@property(nonatomic, strong) dispatch_semaphore_t completionSemaphore;
@property(nonatomic, assign) BOOL cancelled;
@end

@implementation RAFlutterSystemTTSService

- (instancetype)init {
    if ((self = [super init])) {
        _synthesizer = [[AVSpeechSynthesizer alloc] init];
        _synthesizer.delegate = self;
        _completionSemaphore = nil;
        _cancelled = NO;
    }
    return self;
}

- (rac_result_t)speakText:(NSString*)text
                     rate:(float)rate
                    pitch:(float)pitch
                   volume:(float)volume
                  voiceId:(NSString*)voiceId {
    @autoreleasepool {
        // The audio session may still be in .record mode from the Voice Agent's
        // audio capture phase. Switch to .playback so AVSpeechSynthesizer can
        // actually route audio to the speaker. Matches SystemTTSService.swift.
#if TARGET_OS_IOS || TARGET_OS_TV
        AVAudioSession* session = [AVAudioSession sharedInstance];
        NSError* sessionError = nil;
        [session setCategory:AVAudioSessionCategoryPlayback
                        mode:AVAudioSessionModeDefault
                     options:AVAudioSessionCategoryOptionDuckOthers
                       error:&sessionError];
        if (sessionError == nil) {
            [session setActive:YES error:&sessionError];
        }
        if (sessionError != nil) {
            RA_PLATFORM_LOG_ERROR("Audio session config failed: %{public}@",
                                  sessionError.localizedDescription);
        }
#endif

        AVSpeechUtterance* utterance = [[AVSpeechUtterance alloc] initWithString:text];

        // Resolve voice — voiceId can be a system identifier, a language code,
        // or empty/"system"/"system-tts" (default voice).
        AVSpeechSynthesisVoice* voice = nil;
        if (voiceId.length > 0 &&
            ![voiceId isEqualToString:@"system"] &&
            ![voiceId isEqualToString:@"system-tts"]) {
            voice = [AVSpeechSynthesisVoice voiceWithIdentifier:voiceId];
            if (voice == nil) {
                voice = [AVSpeechSynthesisVoice voiceWithLanguage:voiceId];
            }
        }
        if (voice == nil) {
            voice = [AVSpeechSynthesisVoice voiceWithLanguage:@"en-US"];
        }
        utterance.voice = voice;

        // AVSpeechUtterance rate is multiplied against the default rate;
        // a SwiftUI-style `1.0` means "normal speed".
        utterance.rate = (rate > 0.0f ? rate : 1.0f) * AVSpeechUtteranceDefaultSpeechRate;
        utterance.pitchMultiplier = (pitch > 0.0f ? pitch : 1.0f);
        utterance.volume = (volume > 0.0f ? volume : 1.0f);
        utterance.preUtteranceDelay = 0.0;
        utterance.postUtteranceDelay = 0.0;

        self.cancelled = NO;
        self.completionSemaphore = dispatch_semaphore_create(0);

        // The C ABI synthesize callback is invoked synchronously on whatever
        // thread the commons router holds (which can be the main thread on
        // `tts.speak(...)` UI flows). AVSpeechSynthesizer must be driven from
        // the main queue and its delegate callbacks fire there too, so a
        // `dispatch_semaphore_wait(..., DISPATCH_TIME_FOREVER)` from the main
        // thread would block the very queue that has to signal the semaphore —
        // a permanent deadlock. Mirror the Swift reference (Task.detached +
        // bounded wait): when off the main thread, dispatch the utterance to
        // the main queue and wait once with a bounded timeout; when ON the main
        // thread, drive the synthesizer inline and pump the run loop so the
        // delegate callbacks can still fire while we wait. Both paths consume
        // the semaphore exactly once and surface RAC_ERROR_TIMEOUT on stall.
        BOOL completed = NO;

        if ([NSThread isMainThread]) {
            [self.synthesizer speakUtterance:utterance];
            const NSTimeInterval limit =
                [NSDate timeIntervalSinceReferenceDate] + (NSTimeInterval)kSynthesizeTimeoutSeconds;
            while ([NSDate timeIntervalSinceReferenceDate] < limit) {
                if (dispatch_semaphore_wait(self.completionSemaphore, DISPATCH_TIME_NOW) == 0) {
                    completed = YES;
                    break;
                }
                [[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode
                                      beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
            }
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.synthesizer speakUtterance:utterance];
            });
            const dispatch_time_t deadline =
                dispatch_time(DISPATCH_TIME_NOW, kSynthesizeTimeoutSeconds * NSEC_PER_SEC);
            completed = (dispatch_semaphore_wait(self.completionSemaphore, deadline) == 0);
        }

        self.completionSemaphore = nil;

        if (!completed) {
            RA_PLATFORM_LOG_ERROR("System TTS synthesize timed out after %lld s",
                                  (long long)kSynthesizeTimeoutSeconds);
            [self stop];
            return RAC_ERROR_TIMEOUT;
        }

        return self.cancelled ? RAC_ERROR_CANCELLED : RAC_SUCCESS;
    }
}

- (void)stop {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.synthesizer stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
    });
}

#pragma mark - AVSpeechSynthesizerDelegate

- (void)speechSynthesizer:(AVSpeechSynthesizer*)synthesizer
   didFinishSpeechUtterance:(AVSpeechUtterance*)utterance {
    (void)synthesizer;
    (void)utterance;
    RA_PLATFORM_LOG_DEBUG("System TTS finished");
    if (self.completionSemaphore != nil) {
        dispatch_semaphore_signal(self.completionSemaphore);
    }
}

- (void)speechSynthesizer:(AVSpeechSynthesizer*)synthesizer
   didCancelSpeechUtterance:(AVSpeechUtterance*)utterance {
    (void)synthesizer;
    (void)utterance;
    RA_PLATFORM_LOG_DEBUG("System TTS cancelled");
    self.cancelled = YES;
    if (self.completionSemaphore != nil) {
        dispatch_semaphore_signal(self.completionSemaphore);
    }
}

@end

// =============================================================================
// C trampolines wired into rac_platform_tts_callbacks_t
// =============================================================================
namespace {

static std::atomic<bool> sRegistered{false};
static std::mutex sRegistrationMutex;

// All RAFlutterSystemTTSService instances are retained in a thread-safe
// registry keyed by the raw pointer we hand back as rac_handle_t. The C++
// destroy trampoline pulls them out and releases the strong reference,
// allowing ARC to clean up.
struct ServiceRegistry {
    std::mutex mutex;
    NSMutableDictionary<NSValue*, RAFlutterSystemTTSService*>* services = nil;
};

static ServiceRegistry& serviceRegistry() {
    static ServiceRegistry reg;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        reg.services = [NSMutableDictionary new];
    });
    return reg;
}

static void retainService(void* handle, RAFlutterSystemTTSService* service) {
    auto& reg = serviceRegistry();
    std::lock_guard<std::mutex> lock(reg.mutex);
    [reg.services setObject:service forKey:[NSValue valueWithPointer:handle]];
}

static RAFlutterSystemTTSService* findService(void* handle) {
    auto& reg = serviceRegistry();
    std::lock_guard<std::mutex> lock(reg.mutex);
    return [reg.services objectForKey:[NSValue valueWithPointer:handle]];
}

static void releaseService(void* handle) {
    auto& reg = serviceRegistry();
    std::lock_guard<std::mutex> lock(reg.mutex);
    [reg.services removeObjectForKey:[NSValue valueWithPointer:handle]];
}

// MARK: - can_handle
static rac_bool_t platform_tts_can_handle(const char* voice_id, void* /*user_data*/) {
    if (voice_id == nullptr) {
        // System TTS is a sensible fallback when no voice is specified.
        return RAC_TRUE;
    }
    NSString* s = [[NSString stringWithUTF8String:voice_id] lowercaseString];
    if ([s containsString:@"system-tts"] ||
        [s containsString:@"system_tts"] ||
        [s isEqualToString:@"system"]) {
        return RAC_TRUE;
    }
    return RAC_FALSE;
}

// MARK: - create
static rac_handle_t platform_tts_create(const rac_tts_platform_config_t* /*config*/,
                                        void* /*user_data*/) {
    RAFlutterSystemTTSService* service = [[RAFlutterSystemTTSService alloc] init];
    if (service == nil) {
        RA_PLATFORM_LOG_ERROR("Failed to allocate System TTS service");
        return nullptr;
    }
    // The raw __bridge_retained pointer is what we hand back to commons. We
    // also keep a strong reference in the registry so callers don't have to
    // worry about ownership semantics — destroy() drops both.
    void* handle = (__bridge_retained void*)service;
    retainService(handle, service);
    RA_PLATFORM_LOG_INFO("System TTS service created");
    return handle;
}

// MARK: - synthesize
static rac_result_t platform_tts_synthesize(rac_handle_t handle,
                                            const char* text,
                                            const rac_tts_platform_options_t* options,
                                            void* /*user_data*/) {
    if (handle == nullptr || text == nullptr) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    RAFlutterSystemTTSService* service = findService(handle);
    if (service == nil) {
        RA_PLATFORM_LOG_ERROR("synthesize: unknown service handle");
        return RAC_ERROR_NOT_INITIALIZED;
    }

    NSString* textStr = [NSString stringWithUTF8String:text];
    if (textStr == nil) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    float rate = 1.0f, pitch = 1.0f, volume = 1.0f;
    NSString* voiceId = @"";
    if (options != nullptr) {
        if (options->rate > 0.0f)   rate   = options->rate;
        if (options->pitch > 0.0f)  pitch  = options->pitch;
        if (options->volume > 0.0f) volume = options->volume;
        if (options->voice_id != nullptr) {
            NSString* v = [NSString stringWithUTF8String:options->voice_id];
            if (v != nil) {
                voiceId = v;
            }
        }
    }

    return [service speakText:textStr rate:rate pitch:pitch volume:volume voiceId:voiceId];
}

// MARK: - stop
static void platform_tts_stop(rac_handle_t handle, void* /*user_data*/) {
    if (handle == nullptr) return;
    RAFlutterSystemTTSService* service = findService(handle);
    if (service != nil) {
        [service stop];
    }
}

// MARK: - destroy
static void platform_tts_destroy(rac_handle_t handle, void* /*user_data*/) {
    if (handle == nullptr) return;
    RAFlutterSystemTTSService* service = findService(handle);
    if (service != nil) {
        [service stop];
    }
    releaseService(handle);
    // Pair the __bridge_retained in `create`. ARC releases the underlying
    // service once both this transfer and the registry strong-ref are gone.
    CFTypeRef cf = (CFTypeRef)handle;
    if (cf != nullptr) {
        CFRelease(cf);
    }
    RA_PLATFORM_LOG_DEBUG("System TTS service destroyed");
}

}  // namespace

// =============================================================================
// Platform LLM (Apple Foundation Models) callback bridge
// =============================================================================
//
// Mirrors the Swift SDK's `CppBridge+Platform.swift` LLM callback set so the
// commons router has a real `platform` LLM vtable when it routes
// `foundation-models-default` (and any other `framework == .foundationModels`
// model). Without these callbacks, `rac_platform_llm_is_available()` returns
// false and the router rejects every Apple FM load with
// "Feature/operation is not supported" (FLUTTER-IOS-004).
//
// FoundationModels is a Swift-only framework that ships with iOS 26 / macOS 26.
// Since the Flutter plugin pod does not ship a `CRACommons` module map (so we
// cannot import the C ABI from Swift directly), we register C trampolines
// here. The trampolines correctly report unavailability on every runtime
// that does NOT have Foundation Models support (i.e. every shipping iOS /
// macOS until 26.x). When Flutter targets a 26.x device the bridge still
// returns `RAC_ERROR_NOT_SUPPORTED` from `generate` until a Swift FM service
// is wired in; the important difference vs. "no callbacks registered" is
// that the router actually has a route and surfaces a deterministic
// availability error instead of "Swift callbacks not registered".
namespace {

inline bool foundationModelsRuntimeAvailable() {
    if (@available(iOS 26.0, macOS 26.0, *)) {
#if TARGET_OS_SIMULATOR
        // FoundationModels is gated to physical devices on shipping iOS;
        // the simulator does not expose a usable runtime.
        return false;
#else
        return true;
#endif
    }
    return false;
}

static rac_bool_t platform_llm_can_handle(const char* model_id, void* /*user_data*/) {
    if (!foundationModelsRuntimeAvailable()) {
        return RAC_FALSE;
    }
    if (model_id == nullptr) {
        return RAC_FALSE;
    }
    NSString* s = [[NSString stringWithUTF8String:model_id] lowercaseString];
    if ([s containsString:@"foundation-models"] ||
        [s containsString:@"foundation_models"] ||
        [s containsString:@"foundation"] ||
        [s containsString:@"apple-intelligence"] ||
        [s isEqualToString:@"system-llm"]) {
        return RAC_TRUE;
    }
    return RAC_FALSE;
}

static rac_handle_t platform_llm_create(const char* /*model_path*/,
                                        const rac_llm_platform_config_t* /*config*/,
                                        void* /*user_data*/) {
    // Until a Swift FoundationModels service is wired into the Flutter pod we
    // fail-fast here so the router falls back to the next compatible plugin.
    // Logging at warning so the gap is visible without spamming on every
    // can_handle probe.
    RA_PLATFORM_LOG_INFO(
        "Foundation Models create() not implemented in Flutter pod yet; "
        "router will retry with the next compatible backend");
    return nullptr;
}

static rac_result_t platform_llm_generate(rac_handle_t /*handle*/,
                                          const char* /*prompt*/,
                                          const rac_llm_platform_options_t* /*options*/,
                                          char** /*out_response*/,
                                          void* /*user_data*/) {
    return RAC_ERROR_NOT_SUPPORTED;
}

static void platform_llm_destroy(rac_handle_t /*handle*/, void* /*user_data*/) {
    // No retained Swift state yet; nothing to release.
}

}  // namespace

// =============================================================================
// Public C entry point — called from Swift façade during plugin registration.
// =============================================================================

extern "C" void ra_flutter_register_platform_tts(void) {
    std::lock_guard<std::mutex> lock(sRegistrationMutex);
    if (sRegistered.load()) {
        RA_PLATFORM_LOG_DEBUG("Platform TTS plugin already registered");
        return;
    }

    rac_platform_tts_callbacks_t callbacks = {};
    callbacks.can_handle = &platform_tts_can_handle;
    callbacks.create     = &platform_tts_create;
    callbacks.synthesize = &platform_tts_synthesize;
    callbacks.stop       = &platform_tts_stop;
    callbacks.destroy    = &platform_tts_destroy;
    callbacks.user_data  = nullptr;

    rac_result_t setCbRc = rac_platform_tts_set_callbacks(&callbacks);
    if (setCbRc != RAC_SUCCESS) {
        RA_PLATFORM_LOG_ERROR("rac_platform_tts_set_callbacks failed: %d", (int)setCbRc);
        return;
    }

    // FLUTTER-IOS-004 fix: register Apple Foundation Models LLM callbacks so
    // the router has a real `platform` LLM route. Without this the load path
    // for `foundation-models-default` fails with "Swift callbacks not
    // registered" instead of a deterministic
    // RAC_ERROR_CAPABILITY_UNSUPPORTED / RAC_ERROR_NOT_SUPPORTED. Mirrors
    // CppBridge+Platform.swift `registerLLMCallbacks()`.
    rac_platform_llm_callbacks_t llmCallbacks = {};
    llmCallbacks.can_handle = &platform_llm_can_handle;
    llmCallbacks.create     = &platform_llm_create;
    llmCallbacks.generate   = &platform_llm_generate;
    llmCallbacks.destroy    = &platform_llm_destroy;
    llmCallbacks.user_data  = nullptr;

    rac_result_t llmSetCbRc = rac_platform_llm_set_callbacks(&llmCallbacks);
    if (llmSetCbRc != RAC_SUCCESS) {
        RA_PLATFORM_LOG_ERROR(
            "rac_platform_llm_set_callbacks failed: %d", (int)llmSetCbRc);
        // Non-fatal: TTS half can still register.
    }

    rac_result_t backendRc = rac_backend_platform_register();
    if (backendRc != RAC_SUCCESS && backendRc != RAC_ERROR_MODULE_ALREADY_REGISTERED) {
        RA_PLATFORM_LOG_ERROR("rac_backend_platform_register failed: %d", (int)backendRc);
        return;
    }

    // Register the unified-plugin vtable so the router actually has a route
    // for framework == .systemTts. Matches Swift's
    // CppBridge.Platform.registerPlatformPlugin().
    const rac_engine_vtable_t* vtable = rac_plugin_entry_platform();
    if (vtable == nullptr) {
        RA_PLATFORM_LOG_ERROR("rac_plugin_entry_platform() returned null");
        return;
    }
    rac_result_t pluginRc = rac_plugin_register(vtable);
    if (pluginRc != RAC_SUCCESS && pluginRc != RAC_ERROR_MODULE_ALREADY_REGISTERED) {
        RA_PLATFORM_LOG_ERROR("rac_plugin_register(platform) failed: %d", (int)pluginRc);
        return;
    }

    sRegistered.store(true);
    RA_PLATFORM_LOG_INFO(
        "Platform plugin registered (AVSpeechSynthesizer TTS + Foundation Models LLM stub)");
}
