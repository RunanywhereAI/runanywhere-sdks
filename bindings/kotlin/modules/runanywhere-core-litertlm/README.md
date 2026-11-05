# runanywhere-litertlm-android

**Optional LiteRT-LM backend for the RunAnywhere Kotlin SDK**: on-device LLM generation with `.litertlm` models on CPU, GPU or the Google Tensor NPU. Android `arm64-v8a` only.

## Build from source

LiteRT-LM releases no C API binary for Android, so the native payload is built from the tag pinned in `core/VERSIONS`. From the repository root:

```bash
export ANDROID_HOME=~/Library/Android/sdk
export ANDROID_NDK_HOME=$ANDROID_HOME/ndk/<r28b or newer>
./scripts/build/build-litertlm-android.sh

export ANDROID_NDK_HOME=$ANDROID_HOME/ndk/27.3.13750724
./scripts/build/build-core-android.sh arm64-v8a
```

`build-core-android.sh` turns the engine on when `engines/litertlm/prebuilt/current` holds the library, and stages the libraries into this module. Without it the module has no native payload and `LiteRTLM.register()` logs a failure.

## Usage

```kotlin
LiteRTLM.register()
RunAnywhere.initialize(context = context)

RunAnywhere.models.register(
    ModelRegistration.url(
        name = "SmolLM2 135M",
        url = "https://huggingface.co/litert-community/SmolLM2-135M-Instruct/resolve/main/SmolLM2_135M_Instruct.litertlm",
        framework = InferenceFramework.INFERENCE_FRAMEWORK_LITERT_LM,
        id = "smollm2-135m-litertlm",
    ),
)

RunAnywhere.llm
    .generateStream("Name three colours.", LlmOptions(model = "smollm2-135m-litertlm"))
    .collect { event -> if (event is GenerationEvent.TextDelta) print(event.text) }
```

The SDK downloads the model on first use, as with any other framework.

## Chats

Pass the prior turns with `generateStream(messages, options)`. When they are what the last request left, the backend goes on with the same conversation and does not process the history again, so the first token of a later turn takes about as long as the first turn's. A different history, system prompt, sampler or thinking setting, a stopped request, or a `seed` starts a new conversation from the full history. So does every turn of a model whose chat template renders earlier turns differently once another follows, as the standard Qwen 3 template does, and its first token takes longer as the chat grows.

A thinking model spends tokens on reasoning first, and the SDK does not stream reasoning by default, so the first text can take a while. `LlmOptions(reasoning = ReasoningOptions(mode = ReasoningMode.OFF))` turns it off and `includeInOutput = true` streams it.

## Accelerators

`LoadOptions(accelerator = AcceleratorPolicy.CPU)` or `GPU` selects one. The default tries GPU and falls back to CPU.

A bundle compiled for an NPU, such as `gemma-4-E2B-it_Google_Tensor_G6.litertlm` on a Pixel with Tensor G6, runs on the NPU by default and with `AcceleratorPolicy.NPU`. It does not load on another chip, nor with `CPU` or `GPU`, and `NPU` refuses a bundle that is not compiled for one. This module carries the dispatch library for Google Tensor only. LiteRT finds that library by listing a directory, so the app has to extract its native libraries:

```kotlin
android {
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }
}
```

The module's manifest declares `libvndksupport.so`, `libOpenCL.so`, `libedgetpu_util.so` and `libedgetpu_litert.so` as optional native libraries, which the GPU accelerators and the Tensor NPU need on API 31 and above. It also declares the optional `android.hardware.npu` feature, without which Android 17 denies the NPU to an app that targets API 37.

## Limits

- Constrained generation returns `RAC_ERROR_NOT_SUPPORTED`, as the structured-output contract asks of an engine that cannot enforce a schema or grammar. That includes `llm.generateStructured`, whose request carries the schema in every mode. Tool calling works.
- LoRA adapters, the context-injection ops and image input are not implemented.
- A bundle whose chat template takes content only as a string (older exports such as `qwen3_0_6b_mixed_int4.litertlm`) would drop the user's message on LiteRT-LM 0.18 and newer. The backend adapts the template at load, and refuses a bundle whose template still leaves the message out with `RAC_ERROR_INVALID_MODEL_FORMAT`.
- A model too big for the device can get the app killed by Android's low-memory killer while it loads on the GPU, with no error to catch. Pass `memoryBytes` to `ModelRegistration.url` and the SDK refuses the model first.
- The library writes its caches next to the model, and they can take more space than the model itself. Deleting the model removes them.
