// audio_bridge.cpp — sync N-API wrappers over rac_audio_* DSP.
//
// Same shape as downloadProgressPercent: cheap, synchronous commons calls so
// the TypeScript audio helpers never re-implement PCM/WAV/resample/RMS math.

#include "audio_bridge.h"

#include "proto_bridge.h"

#include <cstdint>
#include <cstring>
#include <vector>

#include "rac/core/rac_audio_utils.h"
#include "rac/core/rac_types.h"

namespace rac_electron {
namespace {

void ThrowAudioError(Napi::Env env, rac_result_t code, const char* context) {
    ThrowProtoError(env, code, context);
}

Napi::Value Float32ToPcm16(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 1 || !info[0].IsTypedArray() ||
        info[0].As<Napi::TypedArray>().TypedArrayType() != napi_float32_array) {
        Napi::TypeError::New(env, "audioFloat32ToPcm16(Float32Array)").ThrowAsJavaScriptException();
        return env.Null();
    }
    auto in = info[0].As<Napi::Float32Array>();
    const size_t n = in.ElementLength();
    auto out = Napi::Int16Array::New(env, n);
    const rac_result_t rc = rac_audio_float32_to_pcm16(in.Data(), n, out.Data());
    if (rc != RAC_SUCCESS) {
        ThrowAudioError(env, rc, "rac_audio_float32_to_pcm16");
        return env.Null();
    }
    return out;
}

Napi::Value Pcm16ToFloat32(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 1 || !info[0].IsTypedArray() ||
        info[0].As<Napi::TypedArray>().TypedArrayType() != napi_int16_array) {
        Napi::TypeError::New(env, "audioPcm16ToFloat32(Int16Array)").ThrowAsJavaScriptException();
        return env.Null();
    }
    auto in = info[0].As<Napi::Int16Array>();
    const size_t n = in.ElementLength();
    auto out = Napi::Float32Array::New(env, n);
    const rac_result_t rc = rac_audio_pcm16_to_float32(in.Data(), n, out.Data());
    if (rc != RAC_SUCCESS) {
        ThrowAudioError(env, rc, "rac_audio_pcm16_to_float32");
        return env.Null();
    }
    return out;
}

Napi::Value ResampleF32(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 3 || !info[0].IsTypedArray() ||
        info[0].As<Napi::TypedArray>().TypedArrayType() != napi_float32_array ||
        !info[1].IsNumber() || !info[2].IsNumber()) {
        Napi::TypeError::New(env, "audioResampleF32(Float32Array, inRate, outRate)")
            .ThrowAsJavaScriptException();
        return env.Null();
    }
    auto in = info[0].As<Napi::Float32Array>();
    const int32_t in_rate = info[1].As<Napi::Number>().Int32Value();
    const int32_t out_rate = info[2].As<Napi::Number>().Int32Value();
    float* out = nullptr;
    size_t out_frames = 0;
    const rac_result_t rc =
        rac_audio_resample_f32(in.Data(), in.ElementLength(), in_rate, out_rate, &out, &out_frames);
    if (rc != RAC_SUCCESS) {
        ThrowAudioError(env, rc, "rac_audio_resample_f32");
        return env.Null();
    }
    auto arr = Napi::Float32Array::New(env, out_frames);
    if (out_frames && out) {
        std::memcpy(arr.Data(), out, out_frames * sizeof(float));
    }
    rac_free(out);
    return arr;
}

Napi::Value ComputeRms(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 1 || !info[0].IsTypedArray() ||
        info[0].As<Napi::TypedArray>().TypedArrayType() != napi_float32_array) {
        Napi::TypeError::New(env, "audioComputeRms(Float32Array)").ThrowAsJavaScriptException();
        return env.Null();
    }
    auto in = info[0].As<Napi::Float32Array>();
    float rms = 0.0f;
    const rac_result_t rc = rac_audio_compute_rms(in.Data(), in.ElementLength(), &rms);
    if (rc != RAC_SUCCESS) {
        ThrowAudioError(env, rc, "rac_audio_compute_rms");
        return env.Null();
    }
    return Napi::Number::New(env, rms);
}

Napi::Value Float32ToWav(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 2 || !info[0].IsTypedArray() ||
        info[0].As<Napi::TypedArray>().TypedArrayType() != napi_float32_array ||
        !info[1].IsNumber()) {
        Napi::TypeError::New(env, "audioFloat32ToWav(Float32Array, sampleRate)")
            .ThrowAsJavaScriptException();
        return env.Null();
    }
    auto in = info[0].As<Napi::Float32Array>();
    const int32_t sample_rate = info[1].As<Napi::Number>().Int32Value();
    void* wav = nullptr;
    size_t wav_size = 0;
    const rac_result_t rc = rac_audio_float32_to_wav(in.Data(), in.ByteLength(), sample_rate, &wav,
                                                    &wav_size);
    if (rc != RAC_SUCCESS) {
        ThrowAudioError(env, rc, "rac_audio_float32_to_wav");
        return env.Null();
    }
    auto buf = Napi::Buffer<uint8_t>::Copy(env, static_cast<const uint8_t*>(wav), wav_size);
    rac_free(wav);
    return buf;
}

Napi::Value PcmBytesToMs(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 2 || !info[0].IsNumber() || !info[1].IsObject()) {
        Napi::TypeError::New(env, "audioPcmBytesToMs(byteCount, { sampleRate, channels?, bitsPerSample? })")
            .ThrowAsJavaScriptException();
        return env.Null();
    }
    const size_t byte_count = static_cast<size_t>(info[0].As<Napi::Number>().Int64Value());
    Napi::Object fmt_obj = info[1].As<Napi::Object>();
    rac_audio_format_t format{};
    format.sample_rate =
        fmt_obj.Has("sampleRate") ? fmt_obj.Get("sampleRate").ToNumber().Int32Value() : 0;
    format.channels =
        fmt_obj.Has("channels") ? fmt_obj.Get("channels").ToNumber().Int32Value() : 1;
    format.bits_per_sample =
        fmt_obj.Has("bitsPerSample") ? fmt_obj.Get("bitsPerSample").ToNumber().Int32Value() : 32;
    int64_t out_ms = 0;
    const rac_result_t rc = rac_audio_pcm_bytes_to_ms(byte_count, &format, &out_ms);
    if (rc != RAC_SUCCESS) {
        // Missing / invalid format → 0 (commons owns the policy; SDKs must not invent).
        return Napi::Number::New(env, 0);
    }
    return Napi::Number::New(env, static_cast<double>(out_ms));
}

Napi::Value WavToFloat32(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 1 || !(info[0].IsBuffer() || info[0].IsTypedArray())) {
        Napi::TypeError::New(env, "audioWavToFloat32(Buffer|Uint8Array)")
            .ThrowAsJavaScriptException();
        return env.Null();
    }

    const uint8_t* data = nullptr;
    size_t size = 0;
    if (info[0].IsBuffer()) {
        auto buf = info[0].As<Napi::Buffer<uint8_t>>();
        data = buf.Data();
        size = buf.Length();
    } else {
        auto ta = info[0].As<Napi::TypedArray>();
        if (ta.TypedArrayType() != napi_uint8_array) {
            Napi::TypeError::New(env, "audioWavToFloat32(Buffer|Uint8Array)")
                .ThrowAsJavaScriptException();
            return env.Null();
        }
        auto u8 = info[0].As<Napi::Uint8Array>();
        data = u8.Data();
        size = u8.ByteLength();
    }

    float* samples = nullptr;
    size_t n_samples = 0;
    int32_t sample_rate = 0;
    const rac_result_t rc =
        rac_audio_wav_to_float32(data, size, &samples, &n_samples, &sample_rate);
    if (rc != RAC_SUCCESS) {
        ThrowAudioError(env, rc, "rac_audio_wav_to_float32");
        return env.Null();
    }

    auto arr = Napi::Float32Array::New(env, n_samples);
    if (n_samples && samples) {
        std::memcpy(arr.Data(), samples, n_samples * sizeof(float));
    }
    rac_free(samples);

    Napi::Object out = Napi::Object::New(env);
    out.Set("sampleRate", Napi::Number::New(env, sample_rate));
    out.Set("samples", arr);
    return out;
}

}  // namespace

void RegisterAudioBridge(Napi::Env env, Napi::Object exports) {
    exports.Set("audioFloat32ToPcm16", Napi::Function::New(env, Float32ToPcm16));
    exports.Set("audioPcm16ToFloat32", Napi::Function::New(env, Pcm16ToFloat32));
    exports.Set("audioResampleF32", Napi::Function::New(env, ResampleF32));
    exports.Set("audioComputeRms", Napi::Function::New(env, ComputeRms));
    exports.Set("audioFloat32ToWav", Napi::Function::New(env, Float32ToWav));
    exports.Set("audioWavToFloat32", Napi::Function::New(env, WavToFloat32));
    exports.Set("audioPcmBytesToMs", Napi::Function::New(env, PcmBytesToMs));
}

}  // namespace rac_electron
