/*
 * Regression coverage for the sherpa STT language policy.
 *
 * Two rules are locked down here:
 *
 *   1. An UNSET public language (which the proto adapter turns into
 *      detect_language=true) must resolve to the recognizer's loaded language
 *      on every non-Whisper model. This is the Canary fix: `stt.transcribe(pcm)`
 *      used to return LanguageNotSupported (-236) after a SUCCESSFUL load
 *      because auto-detect is Whisper-only.
 *
 *   2. An EXPLICIT language override must be refused on any path whose
 *      recognizer decodes with the language it was built with — an offline
 *      recognizer inherits its language into every SherpaOnnxCreateOfflineStream
 *      and has no per-stream language option. Accepting the override there means
 *      a caller who asked for French silently gets English.
 *
 * The two rules pull in opposite directions, so the last block asserts them
 * together: unset stays accepted while an explicit mismatch is refused.
 *
 * Header-only: the policy lives in sherpa_backend.h precisely so it can be
 * exercised without a loaded recognizer or the Sherpa-ONNX runtime.
 */

#include "sherpa_backend.h"

#include <iostream>
#include <string>

namespace {

using runanywhere::sherpa_fixed_language_request_is_honored;
using runanywhere::sherpa_resolve_request_language;
using runanywhere::STTModelType;

// The token that means "auto-detect" differs per call site: an offline Whisper
// recognizer reads an empty language as auto, the online stream option wants
// the literal "auto". Both are exercised below.
constexpr const char* kOfflineAuto = "";
constexpr const char* kOnlineAuto = "auto";

int g_failures = 0;

void expect_eq(const std::string& actual, const std::string& expected, const char* what) {
    if (actual != expected) {
        std::cerr << "FAIL: " << what << " — expected \"" << expected << "\", got \"" << actual
                  << "\"\n";
        ++g_failures;
    }
}

void expect(bool condition, const char* what) {
    if (!condition) {
        std::cerr << "FAIL: " << what << '\n';
        ++g_failures;
    }
}

// --- Rule 1: unset language resolves, never fails -------------------------

void test_unset_language_uses_loaded_language() {
    // THE Canary regression. detect_language=true + no requested language is
    // exactly what `stt.transcribe(pcm)` sends; Canary must transcribe in the
    // language it was loaded with instead of being rejected.
    expect_eq(sherpa_resolve_request_language(STTModelType::CANARY, "en", true, "", kOfflineAuto),
              "en", "Canary + unset language falls back to the loaded language");
    expect_eq(sherpa_resolve_request_language(STTModelType::CANARY, "fr", true, "", kOfflineAuto),
              "fr", "Canary honors a non-default loaded language on the unset path");

    // A Canary recognizer that somehow carries no loaded language still has to
    // produce one — Canary rejects an empty source/target language outright.
    expect_eq(sherpa_resolve_request_language(STTModelType::CANARY, "", true, "", kOfflineAuto),
              "en", "Canary with no loaded language falls back to en, not empty");

    // Same contract for every other non-Whisper recognizer.
    expect_eq(
        sherpa_resolve_request_language(STTModelType::TRANSDUCER, "de", true, "", kOnlineAuto),
        "de", "transducer + unset language falls back to the loaded language");

    // Whisper is the one model that can actually auto-detect.
    expect_eq(sherpa_resolve_request_language(STTModelType::WHISPER, "en", true, "", kOfflineAuto),
              "", "Whisper + unset language auto-detects (empty offline token)");
    expect_eq(sherpa_resolve_request_language(STTModelType::WHISPER, "en", true, "", kOnlineAuto),
              "auto", "Whisper + unset language auto-detects (online \"auto\" token)");
}

void test_explicit_language_wins_when_not_detecting() {
    expect_eq(
        sherpa_resolve_request_language(STTModelType::CANARY, "en", false, "fr", kOfflineAuto),
        "fr", "an explicit language is used verbatim when detect is off");
    expect_eq(sherpa_resolve_request_language(STTModelType::CANARY, "en", false, "", kOfflineAuto),
              "en", "no explicit language falls back to the loaded language");
    expect_eq(sherpa_resolve_request_language(STTModelType::WHISPER, "", false, "", kOnlineAuto),
              "auto", "Whisper with nothing loaded and nothing requested auto-detects");
    expect_eq(sherpa_resolve_request_language(STTModelType::NEMO_CTC, "", false, "", kOfflineAuto),
              "en", "non-Whisper with nothing loaded and nothing requested defaults to en");
}

// --- Rule 2: an unhonorable override is refused, not ignored --------------

void test_fixed_language_recognizer_refuses_mismatched_override() {
    expect(!sherpa_fixed_language_request_is_honored("en", "fr"),
           "an override that disagrees with the loaded language is NOT honorable");
    expect(!sherpa_fixed_language_request_is_honored("", "fr"),
           "an override against an auto-detect recognizer is NOT honorable");
    expect(sherpa_fixed_language_request_is_honored("en", "en"),
           "an override that matches the loaded language is honorable");
    expect(sherpa_fixed_language_request_is_honored("en", ""),
           "an UNSET language is not an override and stays honorable");
    expect(sherpa_fixed_language_request_is_honored("", ""),
           "unset against an auto-detect recognizer stays honorable");
}

// --- Both rules together --------------------------------------------------

void test_canary_stream_accepts_unset_but_refuses_wrong_language() {
    // A Canary recognizer loaded as "en" backing an offline stream.
    const std::string loaded = "en";

    // (a) The public unset-language path: create_stream() passes no "language"
    //     key at all, so the honor check sees an empty override and accepts.
    expect(sherpa_fixed_language_request_is_honored(loaded, ""),
           "Canary offline stream still accepts an unset language (PR regression)");
    expect_eq(sherpa_resolve_request_language(STTModelType::CANARY, loaded, true, "", kOfflineAuto),
              loaded, "and decodes it with the loaded language");

    // (b) An explicit "fr" on the same stream cannot be honored — the offline
    //     recognizer would still decode English — so it must be refused.
    expect(!sherpa_fixed_language_request_is_honored(loaded, "fr"),
           "Canary offline stream refuses an explicit language it cannot decode");

    // (c) Pinning the language the recognizer already has is a no-op, not an
    //     error: the app-facing "always send the session language" pattern must
    //     keep working.
    expect(sherpa_fixed_language_request_is_honored(loaded, "en"),
           "pinning the already-loaded language is accepted");
}

}  // namespace

int main() {
    test_unset_language_uses_loaded_language();
    test_explicit_language_wins_when_not_detecting();
    test_fixed_language_recognizer_refuses_mismatched_override();
    test_canary_stream_accepts_unset_but_refuses_wrong_language();

    if (g_failures == 0) {
        std::cout << "Sherpa language policy tests passed\n";
        return 0;
    }
    std::cerr << g_failures << " sherpa language policy assertion(s) failed\n";
    return 1;
}
