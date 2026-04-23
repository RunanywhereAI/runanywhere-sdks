# IDLs and Code Generation for Multi-Language SDKs — A Primer and Assessment for RunAnywhere

> **Purpose of this document.** RunAnywhere v2 wants to collapse 5 hand-written language SDKs (Swift, Kotlin, Dart, React Native/TS, Web/TS) into **one C++ core + codegen'd thin frontends**. That requires picking an Interface Definition Language (IDL) + codegen toolchain. This document explains what IDLs *are*, how codegen *works*, which tools exist, how real products solved the same problem, and what specifically fits RunAnywhere.
>
> **Audience.** A smart engineer who has never shipped an IDL-driven SDK. No assumed knowledge.
>
> **Scope.** Explanation + comparison + recommendation. Implementation plan is a separate document.

---

## Part 1 — What is an IDL, in plain English?

### 1.1 The problem IDLs solve

When you have one piece of logic (say, "download a model and return its metadata") and you want to expose it to **N languages**, you have three choices:

1. **Write it N times.** One implementation per language. This is what RunAnywhere does today — `ModelInfo` is declared in `rac_types.h`, `ModelInfo.swift`, `ModelInfo.kt`, `model_info.dart`, `ModelInfo.ts`, each subtly different, each drifting.
2. **Write it once in a "lingua franca" language (C, C++, Rust) and hand-write bindings** in each target language. This is what SQLite, ffmpeg, LibTorch do. Every language gets a wrapper written by humans against a C ABI.
3. **Write a schema once in a language-agnostic format, and let a tool generate the N language-specific versions.** That schema language is called an **Interface Definition Language** (IDL), and the tool is called a **code generator** (codegen).

Option 3 is what gRPC, Cap'n Proto, FlatBuffers, WIT, UniFFI, and the Azure SDKs all do.

### 1.2 What an IDL actually *is*

An IDL is a **small, purpose-built language** that describes two things:

- **Data shapes** — "a `ModelInfo` has an `id: string`, a `format: enum { GGUF, ONNX, SAFETENSORS }`, a `sizeBytes: uint64`, and an optional `quantization: string`."
- **Operations** — "there is a function `downloadModel(url: string, destination: string) -> DownloadHandle` and it returns a stream of `DownloadProgress` events."

That's it. No control flow. No memory management. No threading model. Just *the shape of the interface*. The tradeoff is intentional: by giving up expressiveness, the IDL becomes **trivially translatable** into any target language.

### 1.3 Three concrete IDL examples

#### Example A: Protobuf (`proto3`)

```proto
syntax = "proto3";
package runanywhere.v1;

enum ModelFormat {
  MODEL_FORMAT_UNSPECIFIED = 0;
  MODEL_FORMAT_GGUF = 1;
  MODEL_FORMAT_ONNX = 2;
  MODEL_FORMAT_SAFETENSORS = 3;
}

message ModelInfo {
  string id = 1;
  string display_name = 2;
  ModelFormat format = 3;
  uint64 size_bytes = 4;
  optional string quantization = 5;
  repeated string capabilities = 6;  // ["chat", "embed", "vision"]
}

message GenerateRequest {
  string model_id = 1;
  string prompt = 2;
  uint32 max_tokens = 3;
}

message Token {
  string text = 1;
  uint32 token_id = 2;
  float logprob = 3;
}

service LLMService {
  rpc LoadModel(ModelInfo) returns (LoadModelResponse);
  rpc Generate(GenerateRequest) returns (stream Token);   // <-- server streaming
}
```

Run `protoc --swift_out=. --kotlin_out=. --dart_out=. --ts_out=. llm.proto` and out pops `Llm.pb.swift`, `Llm.pb.kt`, `llm.pb.dart`, `llm_pb.ts`. All with `ModelInfo` as a native struct in each language, all with `generate()` returning the language's native stream type.

#### Example B: Cap'n Proto

```capnp
@0xbf5147cbbecf40c1;

enum ModelFormat {
  gguf       @0;
  onnx       @1;
  safetensors @2;
}

struct ModelInfo {
  id          @0 :Text;
  displayName @1 :Text;
  format      @2 :ModelFormat;
  sizeBytes   @3 :UInt64;
  quantization @4 :Text;   # optional-by-default (empty string = absent)
  capabilities @5 :List(Text);
}

interface LlmService {
  loadModel @0 (info :ModelInfo) -> (handle :UInt64);
  generate  @1 (modelId :Text, prompt :Text, maxTokens :UInt32)
            -> (stream :Stream(Token));
}

struct Token {
  text    @0 :Text;
  tokenId @1 :UInt32;
  logprob @2 :Float32;
}
```

The `@0`, `@1` numbers are **field ordinals** — they pin the wire format so you can rename fields without breaking clients. Same idea as protobuf's `= 1` tags.

#### Example C: WIT (WebAssembly Interface Types)

```wit
package runanywhere:llm@0.1.0;

interface types {
  enum model-format {
    gguf,
    onnx,
    safetensors,
  }

  record model-info {
    id: string,
    display-name: string,
    format: model-format,
    size-bytes: u64,
    quantization: option<string>,
    capabilities: list<string>,
  }

  record token {
    text: string,
    token-id: u32,
    logprob: f32,
  }
}

interface llm-service {
  use types.{model-info, token};

  load-model: func(info: model-info) -> result<u64, string>;
  generate: func(model-id: string, prompt: string, max-tokens: u32)
            -> stream<token>;   // WIT streams are a real thing in the preview2 spec
}

world runanywhere-sdk {
  export llm-service;
}
```

Notice how all three say roughly the same thing: **types with fields, services with methods, streams of things**. That's the whole idea. The IDL is a shared contract; codegen writes the 5 language-specific versions.

---

## Part 2 — How codegen works mechanically

### 2.1 The flow, step by step

```
      ┌──────────────────┐
      │  llm.proto       │   (IDL source, hand-written, source of truth)
      └────────┬─────────┘
               │ protoc (the compiler/code generator)
               │ + language plugins: protoc-gen-swift, protoc-gen-kotlin, ...
               ▼
┌────────────┬────────────┬────────────┬────────────┬────────────┐
│ Llm.swift  │ Llm.kt     │ llm.dart   │ llm.ts     │ llm.py     │
│            │            │            │            │            │
│ struct     │ data class │ class      │ interface  │ class      │
│ ModelInfo  │ ModelInfo  │ ModelInfo  │ ModelInfo  │ ModelInfo  │
│ + codec    │ + codec    │ + codec    │ + codec    │ + codec    │
│ + client   │ + client   │ + client   │ + client   │ + client   │
│ stubs      │ stubs      │ stubs      │ stubs      │ stubs      │
└────────────┴────────────┴────────────┴────────────┴────────────┘
```

Concretely, given `llm.proto` with `message ModelInfo { string id = 1; ... }`, a single `protoc` invocation produces:

- **`Llm.pb.swift`** — a Swift `struct ModelInfo: Sendable, Hashable` with `var id: String`, plus `init(serializedBytes:)` and `func serializedBytes() -> Data`.
- **`LlmOuterClass.java`** / **`Llm.kt`** — a Kotlin `data class ModelInfo(val id: String, ...)` with `toByteArray()` / `parseFrom()`.
- **`llm.pb.dart`** — a Dart `class ModelInfo extends GeneratedMessage` with `writeToBuffer()` / `fromBuffer()`.
- **`llm_pb.ts`** — a TypeScript class with `toBinary()` / `fromBinary()`.

### 2.2 What's generated

For a typical protobuf-style IDL, the codegen emits four buckets of code in each target language:

| Bucket | What it is | Example |
|---|---|---|
| **Types** | Native structs/classes/data-classes for every `message`/`record`/`struct`. | `struct ModelInfo` in Swift, `data class ModelInfo` in Kotlin |
| **Serialization** | Encode/decode to a wire format (binary protobuf, Cap'n Proto arena, etc.). | `modelInfo.toByteArray()` ↔ `ModelInfo.parseFrom(bytes)` |
| **Client stubs** | Function-call surface you invoke from application code. | `llmClient.generate(req).collect { token -> ... }` |
| **Server stubs** | Abstract base class or interface you implement on the producer side. | `abstract class LLMServiceImplBase { fun generate(req, observer) }` |

For a function-binding-style IDL (UniFFI, WIT), client + server stubs collapse into **FFI glue** — code that marshals arguments across a language boundary and invokes the native implementation.

### 2.3 What's NOT generated

This is the part developers always underestimate. Codegen gives you a **correct, ugly, literal** API. It does *not* give you:

1. **Idiomatic wrappers.** Generated Swift from protobuf looks like Java-in-Swift: `var modelId: String` with PascalCase method names, not Swift's value semantics and `AsyncSequence` conventions. You still hand-write a thin layer on top that makes it feel native.
2. **Async/ergonomic streaming in every language.** Plain protobuf messages are sync; streaming requires a service framework (gRPC) *and* additional glue to map the framework's stream type onto each language's idiom (Swift `AsyncSequence`, Kotlin `Flow`, Dart `Stream`, RxJS `Observable`). More on this in Part 4.
3. **Error types.** Most IDLs have weak error modeling. You define error *data*, but how errors *propagate* (Swift `throws`, Kotlin exceptions, Dart `Future` rejects, TS `Promise` rejects) is codegen-specific and often lossy.
4. **Platform-specific stuff.** File paths, threading, lifecycles, keychain access, Android `Context`, iOS `AVAudioSession` — none of this is in the IDL. It lives in hand-written platform adapters.
5. **Memory management nuances.** Who owns a buffer? When is it freed? Most IDLs paper over this with copies. Cap'n Proto and FlatBuffers expose zero-copy but require you to understand arenas. UniFFI uses Rust's ownership rules + refcounting.
6. **Dependency injection, config, DI containers, logging, telemetry.** Not IDL concerns. Hand-written.

**Rule of thumb:** even the best codegen generates 60–80% of an SDK's surface. The remaining 20–40% is the hand-written idiomatic layer that makes it *feel* native.

---

## Part 3 — The major IDL options, compared

We'll evaluate seven options against criteria that matter for RunAnywhere:
maturity, language coverage, streaming support, rich object graphs, and real-world usage in "C/C++ core + multi-language SDK" shape.

### 3.1 Quick comparison table

| Tech | Maturity | Core Languages Supported | Streaming? | Rich objects? | Real user at scale |
|---|---|---|---|---|---|
| **Protobuf** | Bulletproof. Google since 2001, open-source since 2008. | C++, Java, Kotlin, Swift, Python, Go, Dart, TS, Rust, C#, Ruby, PHP, Objective-C, + 20 third-party | Only through gRPC or hand-rolled | Excellent — nested messages, maps, oneofs | Google everything; Kubernetes; Envoy; Istio; Cloudflare; every cloud API |
| **Cap'n Proto** | Mature but niche. Sandstorm, Cloudflare Workers since 2017. | C++, Rust, Python, Go, JS/TS, Java, C#, Erlang, OCaml | **Yes, first-class** — `Stream<T>` + RPC "promise pipelining" | Excellent, zero-copy | **Cloudflare Workers' entire runtime**. Sandstorm. Some game studios. |
| **FlatBuffers** | Very mature. Google (games, Android Neural Networks, TensorFlow Lite). | C++, Java, Kotlin, Swift, Go, Rust, Python, TS, Dart, C#, PHP, Lua | No built-in streaming | Good, but clunky — no maps, no recursion in some langs | TensorFlow Lite model format; Android NN; Facebook Messenger |
| **WIT / Component Model** | Emerging (preview2 stabilizing 2024-2025). | Rust, C, C++, Go (TinyGo), JS, Python, .NET — all via wasm | Yes, `stream<T>` in preview2 | Yes — records, variants, flags, resources | Fermyon, Cosmonic, Microsoft Hyperlight; WASI SDK |
| **UniFFI** | Mature for Rust-centric stacks. Mozilla since 2020. | Rust (required) → Swift, Kotlin, Python, Ruby, Go, C# (community) | **Yes, via Rust `Stream`-like callbacks** — async support added 2023+ | Good for records; limited for cyclic graphs | Mozilla Application Services (Firefox sync, autofill, Nimbus). Used in Firefox iOS + Android. |
| **gRPC** | Bulletproof for networked RPC. | C++, Java, Kotlin, Swift, Python, Go, Dart, TS, Rust, C#, Ruby, PHP, Objective-C | **Yes — server, client, and bidi streaming** | Via protobuf | Google; Netflix; Square; Dropbox; most post-2017 microservice stacks |
| **Azure SDK codegen (AutoRest / TypeSpec)** | Mature for Azure-specific workflow. | C#, Java, Python, JS/TS, Go, Swift, C++ | HTTP streaming only (SSE/chunked) | Via OpenAPI/TypeSpec | All 150+ Azure SDKs. Only really usable if your API is HTTP+JSON. |

### 3.2 Detailed option-by-option

#### 3.2.1 Protocol Buffers (protobuf)

- **What it is.** Google's flagship IDL, now on `proto3`. Compiles `.proto` files to native types + binary serialization in dozens of languages.
- **Maturity.** As battle-tested as it gets. The wire format is frozen. `protoc` has been in production at Google since ~2001, public since 2008.
- **Languages supported in-tree.** C++, Java, Python, Go, C#, Objective-C, Ruby, PHP, Dart, JS. **Swift, Kotlin, TS, Rust are first-class via official plugins** (`protoc-gen-swift`, `protoc-gen-kotlin`, `protoc-gen-ts`, `prost` / `protobuf-rust`).
- **Strengths.** Huge ecosystem. Excellent for rich object graphs: nested messages, `repeated`, `map<K,V>`, `oneof`, `Any`, `google.protobuf.Timestamp`. Wire format is compact and versionable (you can add/remove fields without breaking clients).
- **Weaknesses.** Plain protobuf has **no RPC / no streaming / no function calls** — it's purely data. You need gRPC (or a custom transport) to get "call a function that returns a stream." Generated code can be verbose and unidiomatic; in Swift/Kotlin especially, people hand-write wrappers on top.
- **Streaming?** Only via gRPC or by manually embedding a length-prefixed message loop.
- **Rich objects?** Best-in-class — in fact the Google Cloud SDK's tens of thousands of types are all protobuf messages.
- **Product using it at multi-SDK scale.** **Google Cloud SDKs** (Go, Java, Python, Node, Ruby, PHP, C#, C++ — all codegen'd from the same protos). **Kubernetes** (Go-native but all its types are protos). **Envoy / Istio xDS**. **Cloudflare public APIs**.

#### 3.2.2 Cap'n Proto

- **What it is.** "Protobuf done right" by Kenton Varda, the ex-Googler who wrote most of `protoc`. Key insight: **zero-copy reads**. The in-memory layout *is* the wire format, so decoding is free.
- **Maturity.** Mature (10+ years), niche (dwarfed by protobuf adoption). But the niche it does occupy is serious: Cloudflare Workers uses it for everything.
- **Languages.** C++ (flagship), Rust (`capnp-rs`), Go, Python, JS/TS, Java, C#, plus community ports.
- **Strengths.**
  - **Zero-copy**: you `mmap` a Cap'n Proto file and access fields directly — no parse step. Massive win for local IPC and large payloads.
  - **RPC with promise pipelining** — you can chain calls without round-trips. `a.foo().bar().baz()` sends one message even when each call is "remote."
  - First-class `Stream<T>` interfaces.
- **Weaknesses.**
  - Smaller ecosystem — fewer libraries, fewer Stack Overflow answers.
  - Swift support is **third-party and patchy** (`SwiftCapnp` exists but isn't production-scale).
  - Dart support is essentially nonexistent.
  - Mental model is harder — you deal with "builders" and "readers" and arena allocation.
- **Streaming?** Yes, natively — `interface Foo { stream: () -> Stream(T) }`.
- **Rich objects?** Yes, with unusual constraints: fields are numbered, struct layout is fixed.
- **Product using it.** **Cloudflare Workers runtime (`workerd`)**. **Sandstorm**. Internally in some game engines. Not used at the "C++ core + 5 mobile SDKs" scale anywhere public.

#### 3.2.3 FlatBuffers

- **What it is.** Google's other serialization library, optimized for games: zero-copy like Cap'n Proto, but with different tradeoffs (buffer traversal rather than direct pointer access in some languages).
- **Maturity.** Very mature. Powers the `.tflite` model format — every TensorFlow Lite model on every Android phone is a FlatBuffer.
- **Languages.** C++, Java, Kotlin, C#, Go, Python, JS/TS, PHP, Dart, Lua, Rust, Swift.
- **Strengths.** Zero-copy. Small runtime. Extremely fast decode. Works well for "large read-mostly payloads" like model weights or game assets.
- **Weaknesses.** No RPC framework, no streaming. API is awkward in most languages (tagged accessors, no native-feeling structs). Rich objects are possible but ugly. No `map<K,V>`. Schema evolution is supported but constrained.
- **Streaming?** No.
- **Rich objects?** Workable but clunky.
- **Product using it.** **TensorFlow Lite model files**. **Android Neural Networks API**. **Facebook Messenger** (messaging protocol). **Cocos2d-x / some Unity games**.

#### 3.2.4 WIT (WebAssembly Interface Types) + Component Model

- **What it is.** The Bytecode Alliance's IDL for **WebAssembly components**. Intended to solve exactly our problem: let a Rust/C++ implementation expose a typed interface to Python, JS, Go, etc. via a shared `.wasm` component.
- **Maturity.** *Emerging*. Preview 1 shipped in wasmtime; Preview 2 stabilized in 2024; widespread tooling is arriving but still rough edges.
- **Languages.** Rust (best-in-class), C/C++ (via `wit-bindgen`), Go (TinyGo + wasm), JS/TS (via `jco`), Python (via `componentize-py`), .NET.
- **Strengths.**
  - **Designed for our exact use case** — "write core once, expose to many languages via codegen."
  - Has **first-class `resource`** types (opaque handles to native objects — exactly what we need for engines, sessions, models).
  - `stream<T>` and `future<T>` types in preview2.
  - No wire format concerns — everything is in-process once the wasm runs.
- **Weaknesses.**
  - Implies shipping **WebAssembly** on every platform. For Web, this is natural. For iOS/Android, it means bundling a wasm runtime (wasmtime, wasmer, wasmedge) and paying the interpreter/JIT overhead. On iOS JIT is forbidden — you'd use the interpreter or AOT.
  - iOS/Android wasm story is less mature than the desktop/server story.
  - Swift bindings and Kotlin bindings for WIT components are **experimental** (mostly community-driven).
  - Does not do "direct call into a .so" — you can't easily replace JNI with WIT.
- **Streaming?** Yes (preview2).
- **Rich objects?** Yes, plus `resource` for opaque handles.
- **Product using it.** **Fermyon Spin** (cloud platform). **Cosmonic**. **Microsoft Hyperlight**. **Shopify's Function SDK**. Not yet used for a "mobile SDK in 5 languages" product.

#### 3.2.5 UniFFI

- **What it is.** Mozilla's tool. You **write a Rust crate**, annotate its public API with `#[uniffi::export]` (or describe it in a `.udl` file), and it generates **Swift, Kotlin, Python, Ruby, Go, and C# bindings** that call into the Rust library via C ABI.
- **Maturity.** Production-grade for Mozilla's use case. Powers Firefox's sync, passwords, autofill, and the Nimbus experimentation SDK on both iOS and Android. 5+ years old.
- **Languages.** Rust is **required** on the producer side. Consumer bindings: Swift, Kotlin/JVM, Python, Ruby, Go, C# (community). **No Dart, no TS/JS/WASM** out of the box (community ports for Dart exist but aren't production-ready).
- **Strengths.**
  - Closest thing to "write once in a systems language, get idiomatic bindings in mobile languages" that exists in production today.
  - Async/await support since 2023 — generates `suspend fun` in Kotlin, `async throws` in Swift.
  - Generates **real idiomatic types**: Kotlin `data class`, Swift `struct`, Python `@dataclass`.
  - Callback interfaces work both ways — you pass a Swift closure into Rust, Rust can call it.
- **Weaknesses.**
  - **Rust-only producer.** This is the deal-breaker for RunAnywhere today: the core is C++, not Rust. You'd have to either rewrite in Rust, or write a Rust shim over your C++ core (doable but adds a layer).
  - No Dart, no TS, no Web. These are precisely 2 of the 5 languages RunAnywhere needs.
  - Limited to a function-call model — not great for truly graph-shaped APIs.
- **Streaming?** Yes, via async + callback interfaces. Kotlin gets `Flow<T>`-friendly patterns; Swift `AsyncSequence` is doable with wrappers.
- **Rich objects?** Good for records; weak for cyclic graphs.
- **Product using it.** **Firefox iOS + Android** (sync, logins, Nimbus, suggest, autofill, etc. — all `application-services` Rust components bound to both mobile OSes via UniFFI). **Matrix SDK (element-x)**. **Signal's newer components**.

#### 3.2.6 gRPC

- **What it is.** The service framework built on protobuf. Adds RPC semantics: `rpc Generate(Request) returns (stream Token)` — request/response, server streaming, client streaming, bidirectional streaming — over HTTP/2 (and now HTTP/3).
- **Maturity.** Bulletproof for **networked** RPC. Literally the default microservices framework since 2017.
- **Languages.** Same as protobuf + service stubs in each. **gRPC-Swift** (Apple-maintained), **grpc-kotlin** (Google + Square), **grpc-dart** (Dart team), **@grpc/grpc-js** (Node). All production-grade.
- **Strengths.**
  - **The best streaming story of any IDL, hands down.** Server streaming, client streaming, and bidi streaming all work identically across languages. In Kotlin you get `Flow<Token>`. In Swift you get `AsyncThrowingStream<Token>`. In Dart you get `Stream<Token>`. In TS you get an async iterator or RxJS observable. *This is exactly what we need for audio frames and LLM tokens.*
  - Enormous ecosystem — interceptors, auth, retries, load balancing, tracing.
- **Weaknesses.**
  - **Designed for processes talking over a network**, not for **in-process calls**. "gRPC in-process" (`InProcessChannel`) exists but adds serialization overhead you'd rather not pay for something like a 48kHz audio frame every 10ms.
  - Pulls in HTTP/2 + TLS + a huge runtime on mobile. On iOS, `gRPC-Swift` v2 is ~1MB; on Android, grpc-java is ~2MB.
  - Browser support is via **gRPC-Web** (a separate protocol, requires a proxy). Native HTTP/2 isn't usable from browsers directly.
- **Streaming?** **The gold standard.**
- **Rich objects?** Via protobuf — best-in-class.
- **Product using it.** **Google Cloud SDKs** (all of them). **Dropbox Courier**. **Netflix** (inter-service). **Square** (Register SDK). **Tesla**. *But note:* all of these are **service-to-service**, not "C++ core talking to a Swift app on the same device."

#### 3.2.7 AutoRest / TypeSpec (Azure SDK codegen)

- **What it is.** Microsoft's codegen stack. You describe a REST API in TypeSpec (née Cadl) or OpenAPI, and AutoRest emits SDKs in **C#, Java, Python, JS/TS, Go, Swift, C++**, all following carefully designed per-language guidelines.
- **Maturity.** Mature, powering all 150+ Azure SDK packages.
- **Languages.** C#, Java, Python, JS/TS, Go, Swift, C++.
- **Strengths.**
  - **Best idiomatic output of any codegen.** Generated Swift *looks like* Swift (not Java-in-Swift). Generated Kotlin *looks like* Kotlin. This is because Microsoft invests heavily in per-language SDK guidelines (the "Azure SDK Guidelines").
  - Handles pagination, retries, long-running operations, SSE, auth.
- **Weaknesses.**
  - **Assumes HTTP + JSON.** Not designed for "call a C++ function in the same process." You'd need to shim your C++ core behind an HTTP server, which is what RunAnywhere already does for cloud but is completely wrong for on-device inference.
  - Not open source in the same way — the plugins are hard to retarget.
- **Streaming?** HTTP-level only (Server-Sent Events, chunked responses). Not suitable for "push me an audio frame every 10ms."
- **Rich objects?** Great via TypeSpec.
- **Product using it.** **All Azure SDKs**. **Some OpenAI SDKs** use a similar (Stainless-based) codegen. **Kiota** from Microsoft Graph.

### 3.3 Honorable mentions (won't go deep)

- **Thrift (Apache, ex-Facebook).** Like protobuf + RPC + more languages, but fading. Meta still uses internally.
- **Avro (Apache).** JSON-in-JSON for Hadoop world. Not relevant here.
- **MessagePack / MsgPack-RPC.** Dynamic like JSON. Not schema-first.
- **Smithy (AWS).** Like TypeSpec, for AWS SDKs. Same HTTP limitation as AutoRest.
- **Diplomat.** Rust's equivalent of UniFFI from the Unicode ICU4X project — generates C++, Swift, Kotlin, JS bindings from Rust. Promising but very new.
- **CXX / crubit.** Rust ↔ C++ specifically. Not IDL-based.
- **SWIG.** The granddaddy (1995). Parses C/C++ headers directly and generates bindings for 20+ languages. Still works. Output quality is "ugly but functional." Used by PyTorch (historically), GDAL, OpenCV, and many scientific-computing libraries.
- **Pigeon (Flutter).** Flutter-team's IDL — generates Dart ↔ Swift/Kotlin bindings. Single-use; perfect for its niche.
- **Nitro Modules (React Native).** Codegens TS ↔ Swift/Kotlin/C++ bindings using TypeScript interfaces as the IDL. **RunAnywhere already uses this for the React Native SDK.**

---

## Part 4 — Streaming across language boundaries (the hard part)

This section matters most for RunAnywhere because every headline feature — voice agent, LLM generation, audio capture, wake-word detection, download progress — is fundamentally a **stream of events from C++ to the application**.

### 4.1 The core problem

C++ produces events:

```cpp
// rac_llm.h
typedef void (*rac_token_callback)(const char* text, uint32_t token_id, void* userdata);
RAC_API rac_result rac_llm_generate(rac_llm_t engine,
                                    const char* prompt,
                                    rac_token_callback cb,
                                    void* userdata);
```

The callback fires on a C++ thread, potentially thousands of times per second. The application wants to *consume* this as:

- **Swift**: `AsyncThrowingStream<Token, Error>` or `AsyncSequence` — `for try await token in llm.generate(prompt) { ... }`
- **Kotlin**: `Flow<Token>` — `llm.generate(prompt).collect { token -> ... }`
- **Dart**: `Stream<Token>` — `await for (final token in llm.generate(prompt)) { ... }`
- **TypeScript/JS**: `AsyncIterable<Token>` or `Observable<Token>` — `for await (const token of llm.generate(prompt)) { ... }`
- **Python** (future): `Iterator[Token]` or `AsyncIterator[Token]`

The question is: **how do we do this automatically from an IDL, instead of hand-writing 5 adapters?**

### 4.2 How gRPC does it

gRPC is the best case study. Given:

```proto
service LLM {
  rpc Generate(GenerateRequest) returns (stream Token);
}
```

Each language's gRPC plugin generates:

| Language | Generated signature |
|---|---|
| Swift | `func generate(_ request: GenerateRequest) -> AsyncThrowingStream<Token, Error>` (gRPC-Swift v2) |
| Kotlin | `fun generate(request: GenerateRequest): Flow<Token>` (grpc-kotlin coroutines) |
| Dart | `ResponseStream<Token> generate(GenerateRequest request)` (dart-grpc) — `.stream` is a `Stream<Token>` |
| TS (Node) | `generate(request: GenerateRequest): AsyncIterable<Token>` (connect-es or grpc-js) |
| TS (browser) | Same via gRPC-Web / Connect-Web |
| Python | `def generate(request) -> Iterator[Token]` or `async def generate(request) -> AsyncIterator[Token]` |

**Key insight:** the gRPC plugin authors did the hard work of **mapping "stream of messages" to each language's native async-iteration idiom**. That's exactly what a good codegen has to do.

Under the hood, the transport is HTTP/2 framed messages; each message is a protobuf. The plugin handles: thread-pool → event-loop handoff, back-pressure, cancellation, error propagation. This is thousands of engineer-hours per language.

### 4.3 Callback-style native events (the on-device case)

gRPC assumes a network socket. For on-device SDKs, your C++ core is in the *same process* — there's no HTTP/2, just function pointers. How do you make the same "stream native to each language" feel work?

Three established patterns:

#### Pattern A: Shared queue + pump thread

The C++ side pushes events onto a lock-free ring buffer. Each language binding runs a "pump" that pulls from the queue and emits into the native stream type.

```
C++ producer thread ─── push ──▶ ringbuf ──── pump ────▶ Swift AsyncStream.Continuation.yield(token)
                                               pump ────▶ Kotlin SendChannel.trySend(token)
                                               pump ────▶ Dart StreamController.add(token)
                                               pump ────▶ JS controller.enqueue(token)
```

This is how **Flutter's dart:ffi + event channels** work, and how **gRPC-Swift v2** adapts its internal Netty-style async I/O into `AsyncSequence`.

#### Pattern B: Language-specific callback interfaces generated by the IDL

UniFFI does this. You define a `callback interface` in the IDL:

```udl
callback interface TokenSink {
  void on_token(Token token);
  void on_finished();
  void on_error(string message);
};

interface LLM {
  void generate(string prompt, TokenSink sink);
};
```

UniFFI generates the Swift/Kotlin/Python code that lets you pass a **native closure or interface** as the `sink`, and handles marshaling the callback across the FFI boundary. The application wraps that in an `AsyncStream` / `Flow` / `asyncio.Queue` in ~10 lines of hand-written code per language.

**This is the pragmatic answer for on-device IDLs.** It acknowledges that streams-as-first-class is complicated and punts to "callbacks + a thin adapter."

#### Pattern C: IDL with first-class `stream<T>`

Cap'n Proto and WIT preview2 both have `stream<T>` as a native IDL type. The codegen is supposed to map it to each language's native stream idiom. **This works well for Cap'n Proto in C++/Rust/JS, but Swift/Kotlin/Dart support is weak.**

### 4.4 The recommended pattern for RunAnywhere

Given the languages we need (Swift, Kotlin, Dart, TS), the realistic answer is a **hybrid**:

1. **IDL defines streams as callback interfaces** (Pattern B) — maximally portable.
2. **Codegen generates a "raw" callback-based API** in each language.
3. **A thin hand-written per-language adapter (50–200 lines)** wraps the raw callback API into the native stream type:
   - Swift: `AsyncThrowingStream` with a `Continuation` wired to the callback.
   - Kotlin: `callbackFlow { ... }`.
   - Dart: `StreamController<T>` broadcast to a `Stream<T>`.
   - TS: `ReadableStream<T>` or `AsyncGenerator<T>`.

Each of those adapters is ~50 lines per language per stream *type* (token stream, audio frame stream, event stream) — so maybe 4 stream types × 5 languages × 60 lines = **~1,200 lines of hand-written adapter code total**, which you write once and maintain indefinitely.

---

## Part 5 — Real-world precedent: who has done "C/C++ core + multi-language SDKs" at scale?

### 5.1 gRPC itself

- **Architecture.** A C++ core (`grpc/src/core/`) wrapped by per-language bindings.
- **Binding mechanism.** **Hand-written per-language wrappers** around the C core. `gRPC-Swift` v2 is *not* a wrapper around `grpc_core` — it's a full Swift reimplementation on SwiftNIO, because Apple wanted pure Swift. But Ruby, Python, PHP, Objective-C, and Node.js all ship as **language-specific wrappers over the C core library**.
- **IDL used for surface API.** The API *surface* is generated from `.proto` → `.pb.swift` etc. via `protoc` plugins. The *transport* is hand-written per language.
- **Lesson.** Even Google, with infinite engineering resources, **hand-writes the transport layer per language** and only uses IDL codegen for the typed API surface.

### 5.2 SQLite

- **Architecture.** ~150K lines of C with a rigid C ABI (`sqlite3_open`, `sqlite3_prepare_v2`, `sqlite3_step`, …).
- **Binding mechanism.** **Every single binding is hand-written.** `sqlite-jdbc`, `sqlite-swift` (GRDB), `sqflite` (Dart), `better-sqlite3` (Node), `sqlite3` (Python stdlib), `rusqlite` (Rust) — all hand-maintained, none use an IDL.
- **Why it works.** The C API is narrow (~250 functions), extremely stable (decades of compatibility), and the binding authors take care to expose **idiomatic** wrappers.
- **Lesson.** If your C ABI is narrow and stable, hand-written bindings are tractable. **RunAnywhere has 850 C API declarations** — not narrow.

### 5.3 Flutter

- **Architecture.** A C++ engine (~1M lines of C++, Skia + Impeller + Dart VM + platform channels) with a Dart surface.
- **Binding mechanism.**
  - **Dart ↔ engine:** C++ exposes a small FFI surface (`dart:ui` bindings). Flutter team hand-writes these.
  - **Plugin ecosystem:** uses **Pigeon** (a small IDL that generates Dart ↔ Swift/Kotlin/C++ code) for platform channel plugins.
- **Lesson.** For the *core* engine, one language (Dart) wraps one engine. For the *plugin* ecosystem, they invented their own mini-IDL. **The IDL only appears once they needed multi-language on the platform side.**

### 5.4 WebKit / Blink

- **Architecture.** C++ core (Blink is ~3M lines), JavaScript surface.
- **Binding mechanism.** **WebIDL**, a W3C-standard IDL. Every DOM interface (`HTMLElement`, `Window`, `Document`) is defined in a `.idl` file. Blink has a `bindings/` codegen that produces C++ glue to expose WebIDL interfaces to V8.
- **Scale.** ~1400 `.idl` files in Chromium.
- **Why it's interesting.** Only **one target language** (JS via V8), but extremely rich object graphs, events, streams, Promise-returning methods. The codegen handles all of it.
- **Lesson.** Proof that IDL codegen scales to massive, graph-shaped APIs — but only when you can invest Chromium-level effort in the codegen.

### 5.5 ONNX Runtime

- **Architecture.** C++ core (`onnxruntime/core/`), with Python, Java, C#, JavaScript (WebAssembly + ORT-Web), Rust, Objective-C, Swift bindings.
- **Binding mechanism.** **Hand-written per language, over a stable C API.** The C API (`onnxruntime_c_api.h`) has ~300 functions. Each binding is a hand-written wrapper.
- **IDL usage.** None for the API surface. ONNX Runtime *consumes* the ONNX protobuf model format but doesn't use an IDL for its SDK.
- **Lesson.** 300 C functions × 7 languages = a lot of hand-written code, but Microsoft does it. Each binding has ~5K LOC of glue. Most of the cost is in keeping them in sync on releases.

### 5.6 LibTorch / PyTorch

- **Architecture.** C++ core (ATen/c10, ~500K LOC), Python surface (eager mode) + TorchScript.
- **Binding mechanism.**
  - **Historical:** SWIG-generated bindings.
  - **Modern:** `pybind11` for Python + **Native generation from `native_functions.yaml`**. This YAML file declares every PyTorch operator (thousands of them) as a tiny schema, and a Python codegen script emits C++ dispatch code, Python bindings, and autograd wiring. **It's an internal, purpose-built IDL.**
  - Java / C# bindings are via **JavaCPP** (hand-written mappings).
- **Lesson.** At PyTorch's scale, they built their own IDL specifically for their operator catalog because no off-the-shelf IDL fit. RunAnywhere is smaller but has a similar shape.

### 5.7 ffmpeg

- **Architecture.** C core (~1M LOC), every language has a wrapper.
- **Binding mechanism.** **100% hand-written**. `libav-sys` (Rust), `ffmpeg-python`, `Xabe.FFmpeg` (C#), `fluent-ffmpeg` (Node), etc. Many bindings just shell out to the `ffmpeg` CLI instead of linking.
- **Lesson.** An ancient, gnarly C API that still gets wrapped everywhere, by hand. Works because the C API is stable.

### 5.8 TensorFlow Lite / TFLite Micro

- **Architecture.** C++ core, C API, bindings for Java/Kotlin (Android), Swift/Objective-C (iOS), Python, JavaScript.
- **Binding mechanism.** Hand-written per language over a **deliberately minimal C API** (`TfLiteInterpreter`, `TfLiteTensor` — about 40 functions). All the richness is in the FlatBuffer model file format, not in the API.
- **Lesson.** If you push all the richness into **data** (models, configs) and keep the **API** small, hand-writing 5 bindings is very tractable.

### 5.9 Firefox Sync / Application Services (the closest analogue)

- **Architecture.** Rust core (~100K LOC across multiple components: `logins`, `places`, `sync15`, `nimbus`, `autofill`), Swift bindings (iOS), Kotlin bindings (Android), Python bindings (test).
- **Binding mechanism.** **UniFFI**. This is the canonical production usage of UniFFI. It's shipping on every Firefox iOS and Android install.
- **Lesson.** UniFFI *works* at scale, but (a) the core must be Rust, and (b) only Swift+Kotlin are fully first-class. For RunAnywhere's Dart + Web targets, UniFFI doesn't help.

### 5.10 Summary table of precedents

| Product | Core lang | Target langs | IDL/codegen used? | Binding style |
|---|---|---|---|---|
| gRPC | C++ | 10+ | Protobuf for API, hand-written transport | Mixed |
| SQLite | C | All | None | Hand-written |
| Flutter engine | C++ | Dart | Pigeon for plugins only | Hand-written core + IDL plugins |
| Blink / WebKit | C++ | JS | **WebIDL** (internal) | Codegen |
| ONNX Runtime | C++ | 7 | None | Hand-written over stable C API |
| PyTorch | C++ | Python, Java, C# | Internal YAML IDL for operators | Mixed |
| ffmpeg | C | All | None | Hand-written |
| TFLite | C++ | Java, Swift, Py, JS | FlatBuffers for models only | Hand-written over small C API |
| Firefox app-services | **Rust** | Swift, Kotlin | **UniFFI** | Fully codegen |
| Cloudflare Workers | C++/Rust | JS/TS, Rust, Python | **Cap'n Proto** | Codegen |

**Observations:**
- Nobody has successfully codegen'd a **C++ core → 5 mobile languages** SDK with an off-the-shelf IDL. The closest is Firefox with UniFFI (but it's Rust).
- The industry's proven patterns are: **(a) stable minimal C API + hand-written bindings** (SQLite, ONNX, ffmpeg, TFLite), or **(b) invent your own mini-IDL for the parts that matter** (PyTorch, Chromium WebIDL, Flutter Pigeon).
- Protobuf/gRPC are for **networked** systems, not on-device FFI.

---

## Part 6 — Assessment for RunAnywhere specifically

### 6.1 The constraints, stated precisely

From `V2_MIGRATION_BEFORE_AFTER.md` and the current main repo:

- **Core:** C++20, ~54K LOC, 850 `RAC_API` C-linkage functions across 105 headers.
- **Target languages (today):** Swift, Kotlin, Dart, TypeScript (React Native), TypeScript (Web via WASM).
- **Target languages (future):** Python, Rust, Go.
- **Target platforms:** iOS, Android, macOS, Linux, Web. (JIT-forbidden on iOS; Android has NDK; Web is WASM.)
- **Stream-shaped APIs:**
  - Audio frames from microphone (16kHz or 48kHz float32 PCM, chunked every 10–20ms).
  - LLM token stream (delta text + logprobs, ~10–100Hz).
  - STT partial/final results.
  - Download progress events.
  - Voice-agent lifecycle events (speech-start, barge-in, etc.).
- **Graph-shaped objects:** `ModelInfo`, `GenerationConfig`, `VoiceAgentConfig` with nested enums, optionals, lists, and discriminated unions.
- **Performance budget:** sub-millisecond FFI call overhead for hot paths (audio frames); zero-copy preferred for buffers.

### 6.2 Eliminating options that don't fit

| Option | Why not |
|---|---|
| **UniFFI** | Producer must be Rust. We have C++. Porting 54K LOC of C++ to Rust is a multi-year project. Also: no Dart, no TS out of box. |
| **Azure AutoRest / TypeSpec** | Assumes HTTP + JSON. On-device inference isn't HTTP. |
| **gRPC (full)** | On-device in-process doesn't need HTTP/2 + TLS. Latency/binary-size cost is unjustified. gRPC-Web requires a proxy. |
| **FlatBuffers** | No streaming, no service/RPC layer. Fine for model files, not for APIs. |
| **WIT / Component Model** | Best-in-class design, but Swift/Kotlin bindings aren't production-grade in 2026. Also requires shipping a wasm runtime on iOS/Android, which is a big bet. |
| **Cap'n Proto** | Excellent tech, but Swift support is third-party and Dart support is essentially nonexistent. |
| **Pure SWIG** | Generated code quality is poor for mobile. Nobody uses it for modern Swift/Kotlin SDKs. |

### 6.3 What remains: the realistic shortlist

Three viable paths, in order of increasing ambition:

#### Path A — Hand-written bindings over a narrowed C API (the "SQLite approach")

- **What.** Shrink the current 850-function C API to ~150–250 stable functions. Hand-write Swift/Kotlin/Dart/TS bindings over it. Define data types in a **small protobuf `.proto` file** used *only for serializing complex structs* (ModelInfo, GenerationConfig, enums). Streams are callback-based in C, wrapped manually per language.
- **Pros.** Proven at scale (SQLite, ONNX, ffmpeg, TFLite). No exotic toolchain. Full control over binding ergonomics.
- **Cons.** 5 languages × 150 functions = ~750 binding-function pairs to maintain by hand. Drift risk.
- **Automation level.** ~20% auto-generated (types via protobuf), ~80% hand-written.

#### Path B — IDL-first with a custom minimal codegen (the "WebIDL / PyTorch approach")

- **What.** Define a RunAnywhere-specific IDL (either protobuf messages + a tiny service-like extension, or a YAML schema like `rac.yaml`). Write a small custom codegen (in Python or Rust, ~2K LOC) that emits:
  - C header (single source of truth — replaces today's 105 hand-written headers).
  - Swift structs + callback-based raw API + hand-written ~200-line `AsyncSequence` adapter.
  - Kotlin data classes + raw JNI API + hand-written ~200-line `Flow` adapter.
  - Dart classes + dart:ffi raw API + hand-written ~200-line `Stream` adapter.
  - TS types + WASM bindings + hand-written ~200-line `AsyncIterable` adapter.
- **Pros.** Single source of truth for all types and the API surface. Scales to 10+ languages over time. The codegen is small and focused — not Chromium-scale.
- **Cons.** Building and maintaining the codegen itself is an ongoing cost (1-2 engineer-weeks initial, ~10% of one engineer's time ongoing). Onboarding new engineers is steeper.
- **Automation level.** ~70–80% auto-generated (types, raw API, FFI glue), ~20–30% hand-written (idiomatic adapters, platform-specific code).

#### Path C — Full IDL with an off-the-shelf tool (protobuf + custom streaming layer)

- **What.** Define everything as protobuf messages. Use `protoc` for types. Build a small custom in-process transport (no HTTP/2) that carries length-prefixed protobuf messages across the FFI boundary, with a minimal service + streaming protocol you specify. Each language's protobuf plugin gives you the types; you hand-write one "dispatcher" per language that knows how to call into C++.
- **Pros.** Leverages protobuf's mature type codegen. No custom codegen required.
- **Cons.** Every API call pays a protobuf encode/decode cost. For 48kHz audio frames that's unacceptable — you'd end up with a carve-out that skips protobuf for hot paths, which is the same mess we have today. Also protobuf-generated Swift is not idiomatic.
- **Automation level.** ~60%, but with a painful hot-path carve-out.

### 6.4 The recommendation

**Path B — IDL-first with a custom minimal codegen — is the best fit for RunAnywhere.**

Reasons:

1. **The C++ core and C API are the most expensive assets.** They should not be re-declared by hand in 5 languages. A single IDL that generates the C header + every language's raw bindings eliminates the drift that plagues the current repo (`AudioFormat` declared in 5 places).
2. **A custom codegen is smaller than it sounds.** PyTorch's operator codegen, Chromium's WebIDL, and Flutter's Pigeon are all "one or two engineers maintain it." Starting with a ~1,500-line Python script covers 80% of the value.
3. **Streams can be handled via callback-interface codegen + thin per-language adapters.** This is exactly the hybrid pattern that every real production SDK (UniFFI, Firefox, gRPC-Swift) ends up using. Don't try to make streams "just work" from the IDL; do generate the callback plumbing, and hand-write the `AsyncSequence` / `Flow` / `Stream` / `AsyncIterable` adapter once per language.
4. **It composes with existing tools.** The codegen can emit **protobuf `.proto` files** for complex data types (reusing protobuf's types codegen), a **Nitro `.nitro.ts` file** for React Native (reusing Nitrogen), a **`.udl`-style file** if you ever add a Rust engine (reusing UniFFI), and plain C ABI otherwise. You get the best of each world without marrying any one tool.
5. **It's the only path that accommodates adding Python, Rust, Go later** without retrofitting the core.

### 6.5 Realistic outcome: what gets generated vs hand-written

Given Path B, here's the honest breakdown:

| Layer | Auto-generated | Hand-written |
|---|---|---|
| C API header (`rac_*.h`) | **100%** from IDL | 0% |
| C++ dispatch code (routes C calls to C++ implementations) | **~80%** (boilerplate) | ~20% (engine-specific glue) |
| Swift raw types + raw API + codec | **~95%** | ~5% |
| Swift idiomatic layer (`AsyncSequence`, property wrappers, platform-specific init) | ~10% | **~90%** |
| Kotlin raw types + JNI bindings + codec | **~95%** | ~5% |
| Kotlin idiomatic layer (`Flow`, Android lifecycle, coroutines) | ~10% | **~90%** |
| Dart raw types + dart:ffi bindings + codec | **~90%** | ~10% |
| Dart idiomatic layer (`Stream`, Flutter plugin lifecycle) | ~10% | **~90%** |
| TS raw types + WASM exports + codec | **~90%** | ~10% |
| TS idiomatic layer (`AsyncIterable`, React hooks, RN Nitro) | ~10% | **~90%** |
| Platform adapters (iOS `AVAudioSession`, Android `AudioRecord`, Web `AudioWorklet`) | 0% | **100%** |
| Engine implementations (`llama.cpp`, `whisper.cpp`, `onnxruntime` wrappers) | 0% | **100%** |

**Rolled up across the whole SDK**, the realistic split is **roughly 65% auto-generated, 35% hand-written**. The hand-written 35% is concentrated in:

- The **idiomatic facade** per language (~20%) — the part that makes the SDK *feel* native. This is exactly where you want human taste.
- **Platform adapters** (~10%) — audio capture, permissions, lifecycle. Can't be codegen'd.
- **Engine implementations** (~5%) — `llama.cpp`, `onnxruntime`, etc. wrappers. C++-side, not language-side.

Compared to today's ~0% auto-generated / 100% hand-written (with the associated 5× duplication of every type), **65/35 is a 3-5× reduction in hand-written code and effectively eliminates cross-language drift.**

### 6.6 Real limitations you will hit

Be honest up front. Path B does not eliminate pain; it shifts it.

1. **The codegen becomes a first-class subsystem.** It needs tests, versioning, and a team member who owns it. Treat it like the C++ core — not like a script.
2. **Idiomatic adapters are per-language engineering.** A great Swift engineer's taste for `AsyncSequence` is not transferable to a great Kotlin engineer's taste for `Flow`. You still need fluent speakers of each language.
3. **Streaming is still the hardest part.** Even with callback-interface codegen, back-pressure, cancellation, and error propagation have to be thought through per language. Budget time for this.
4. **Web/WASM is an outlier.** Running a C++ core in a browser via Emscripten has its own rules — no threads without COOP/COEP, limited Worker integration, different memory model. Your IDL-generated C bindings won't "just work" on Web; you'll need a WASM-specific adapter layer.
5. **Versioning.** If the IDL is the source of truth, every schema change becomes a coordination event. Use protobuf-style numbered fields and tolerate unknowns — don't let breaking changes leak.
6. **Build complexity.** You go from "each SDK has its own build" to "one codegen step must run before any SDK builds." This requires a clean top-level orchestrator (Bazel, `just`, or a well-factored Gradle+Make setup).

### 6.7 Summary recommendation in one paragraph

Adopt **a custom minimal IDL + codegen, emitting protobuf messages for data types and callback-interface APIs for services**. Start with a single `rac.proto` + a small Python codegen that produces the C header and raw-bindings for Swift, Kotlin, Dart, and TS. Reuse protobuf's native type codegen where possible. Generate callback-based raw streaming APIs; **hand-write thin idiomatic stream adapters** (`AsyncSequence`, `Flow`, `Stream`, `AsyncIterable`) once per language. Expect ~65% of the SDK to be auto-generated and ~35% to be hand-written idiomatic facades + platform adapters. This is the pattern that PyTorch, Chromium, Flutter, and Firefox have all converged on for "one core, many language frontends"; none of them use a single off-the-shelf tool — each built a purpose-fit codegen because every large cross-language SDK eventually does.

---

## Appendix A — Further reading

- **Protocol Buffers language guide.** https://protobuf.dev/programming-guides/proto3/
- **Cap'n Proto RPC spec.** https://capnproto.org/rpc.html — see "promise pipelining."
- **WIT format.** https://component-model.bytecodealliance.org/design/wit.html
- **UniFFI book.** https://mozilla.github.io/uniffi-rs/ — how `Firefox` does Rust-to-Swift/Kotlin.
- **gRPC-Swift v2.** https://github.com/grpc/grpc-swift — the reference for making async streaming feel Swift-native.
- **Flutter Pigeon.** https://pub.dev/packages/pigeon — small, focused, exactly the shape we want.
- **Chromium WebIDL bindings.** https://www.chromium.org/developers/web-idl-interfaces/ — the proof-of-concept for large-scale IDL codegen.
- **PyTorch native_functions.yaml.** `aten/src/ATen/native/native_functions.yaml` in the PyTorch repo — an internal IDL that generates thousands of operators across C++, Python, and autograd.
- **Kenton Varda on why Cap'n Proto.** https://capnproto.org/news/2014-06-17-capnproto-flatbuffers-sbe.html
