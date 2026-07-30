# RunAnywhere public API spec (v3)

The single source of truth for the public surface of all 8 SDKs. Every SDK implements exactly this: same namespaces, same verb names, same options fields, same defaults, same event grammar, same result fields. Only syntax and casing adapt to the host language.

Signatures below are written in Kotlin-ish pseudocode. `?` means optional/nullable. Defaults are shown with `=`. Anything not listed here is not public.

## Language mapping

| SDK | stream type | async | casing |
|---|---|---|---|
| Kotlin | `Flow<T>` | `suspend` | camelCase |
| Swift | `AsyncThrowingStream<T>` | `async throws` | camelCase |
| Flutter | `Stream<T>` | `Future` | camelCase |
| React Native | `AsyncIterable<T>` | `Promise` | camelCase |
| Web | `AsyncIterable<T>` | `Promise` | camelCase |
| Electron | `AsyncIterable<T>` | `Promise` | camelCase |
| Python | iterator / `async for` | sync + `a`-prefixed async twins | snake_case |
| CLI | flags and subcommands mirroring the verbs | | kebab-case |

Cancellation maps to each language's native mechanism: cancel the `Flow`/`Task`/generator, call `AbortSignal.abort()`, or break the iterator. It always cancels that one request. There are no global cancel verbs.

Errors: one-shot verbs throw a typed SDK error. Stream factories throw on preflight failure. Streams throw into the consumer on in-flight failure. Long-lived sessions additionally emit `error(recoverable)` events for per-component trouble. Nothing returns a result object with a `success` flag, and nothing puts an error message in a text field.

## Core

```
RunAnywhere.initialize(
    apiKey: String? = null,             // null = keyless local mode
    baseUrl: String? = null,            // null = default control plane for the environment
    environment: Environment = PRODUCTION,
)
```
One call. Everything the SDK needs happens inside it: platform adapters, native load, auth, device registration, model catalog, telemetry. Network work runs in the background and retries; the call returns as soon as local inference is usable. There is no second phase for callers to remember.

```
RunAnywhere.reset()                     // tear down: unload models, close sessions, clear state
RunAnywhere.isReady: Boolean            // local inference is usable
RunAnywhere.version: String
RunAnywhere.deviceId: String
RunAnywhere.events: Flow<SdkEvent>      // lifecycle, download, and error breadcrumbs
```

## llm

```
llm.generate(prompt: String, options: LlmOptions? = null): GenerationResult
llm.generate(messages: List<ChatMessage>, options: LlmOptions? = null): GenerationResult
llm.generateStream(prompt: String, options: LlmOptions? = null): Flow<GenerationEvent>
llm.generateStream(messages: List<ChatMessage>, options: LlmOptions? = null): Flow<GenerationEvent>
llm.generateStructured(prompt: String, schema: JsonSchema, options: LlmOptions? = null): StructuredResult
```
`generate` loads (and downloads, when `options.model` names a model that is absent) whatever it needs. Tool calling happens through `options.tools`; when a registered tool matches a call the SDK executes it and continues the loop, up to `options.maxToolCalls`.

```
llm.tools.register(tool: ToolDefinition, executor: suspend (Map<String, Any>) -> Map<String, Any>)
llm.tools.unregister(name: String)
llm.tools.list(): List<ToolDefinition>
```

## vlm

```
vlm.generate(image: ImageInput, prompt: String, options: LlmOptions? = null): GenerationResult
vlm.generateStream(image: ImageInput, prompt: String, options: LlmOptions? = null): Flow<GenerationEvent>
```
Same options and results as `llm`. The prompt is a parameter, never a field inside options.

## stt

```
stt.transcribe(audio: AudioInput, options: SttOptions? = null): Transcription
stt.transcribeStream(audio: Flow<AudioInput>, options: SttOptions? = null): Flow<TranscriptionEvent>
stt.state(): SttState
```

## tts

```
tts.synthesize(text: String, options: TtsOptions? = null): Audio
tts.synthesizeStream(text: String, options: TtsOptions? = null): Flow<AudioChunk>
tts.speak(text: String, options: TtsOptions? = null)     // synthesize and play through the device
tts.stop()                                               // stops playback and any in-flight synthesis
tts.voices(): List<Voice>
```

## vad

```
vad.detect(audio: AudioInput, options: VadOptions? = null): VadResult
vad.detectStream(audio: Flow<AudioInput>, options: VadOptions? = null): Flow<VadEvent>
```

## embeddings and rerank

```
embeddings.embed(texts: List<String>, options: EmbedOptions? = null): List<Embedding>
rerank.rerank(query: String, documents: List<String>, topN: Int? = null): List<RankedResult>
```
Embeddings return in input order, each carrying its `index`. Rerank returns index pointers with scores, sorted best first, matching the shape every rerank vendor uses.

## images, diarization, segmentation

```
images.generate(prompt: String, options: ImageOptions? = null): ImageResult
images.generateStream(prompt: String, options: ImageOptions? = null): Flow<ImageEvent>
diarization.diarize(audio: AudioInput, options: DiarizationOptions? = null): DiarizationResult
segmentation.segment(image: ImageInput, options: SegmentationOptions? = null): SegmentationResult
```
Inpainting is `ImageOptions.mode = INPAINT(input, mask)`, not a separate verb.

## voice

```
voice.createSession(
    stt: ModelRef,
    llm: ModelRef,
    tts: ModelRef,                                  // ModelRef carries a model id and, for TTS, an optional voice
    vad: VadOptions? = null,                        // null = default Silero VAD, ensured automatically
    turnHandling: TurnHandlingOptions? = null,
    generation: LlmOptions? = null,
    downloadIfNeeded: Boolean = true,
): VoiceSession
```
The session owns its prerequisites. It downloads and loads the models it was given, ensures a VAD is resident, and wires the pipeline. Callers do not pre-load anything.

```
VoiceSession.events: Flow<VoiceEvent>
VoiceSession.start()                                // starts audio capture
VoiceSession.say(text: String)                      // speak this now, outside the turn loop
VoiceSession.interrupt()                            // stop the agent mid-utterance
VoiceSession.close()
```
Nothing starts the microphone as a side effect of subscribing to events. `start()` is the only thing that opens the mic.

## rag

```
rag.open(
    embeddingModel: ModelRef,
    llmModel: ModelRef? = null,                     // null = retrieval only
    config: RagConfig? = null,
): RagSession

RagSession.ingest(document: RagDocument)
RagSession.ingest(documents: List<RagDocument>)
RagSession.search(query: String, topK: Int? = null): List<Match>      // retrieval, no generation
RagSession.query(question: String, options: LlmOptions? = null): RagResult
RagSession.queryStream(question: String, options: LlmOptions? = null): Flow<RagEvent>
RagSession.stats(): RagStats
RagSession.clear()
RagSession.close()
```
Sessions are independent. Two sessions with different corpora can exist at once.

## models

```
models.list(filter: ModelFilter? = null): List<ModelInfo>
models.get(id: String): ModelInfo?
models.register(model: ModelRegistration): ModelInfo     // url, archive, or multi-file through one builder
models.download(id: String): Flow<DownloadEvent>         // progress and completion in one verb
models.delete(id: String)
models.load(id: String, options: LoadOptions? = null)    // placement knobs live here, not on requests
models.unload(category: ModelCategory? = null)           // null = everything
models.state(): ModelsState
```
Generation verbs auto-load, so `load` is for callers who want to control when the cost is paid.

## lora

```
lora.apply(adapterId: String, scale: Float? = null)
lora.remove(adapterId: String? = null)                   // null = remove all
lora.list(): LoraState
```
Adapters register through `models.register`, like any other artifact.

## Options

Every field is optional. Defaults are the same in every SDK and come from the `rac_default` annotations in the IDL, never hand-copied per language. A caller who passes nothing gets the same value commons applies to an unset wire field.

```
LlmOptions:
    model: String? = null                  // slug; absent model auto-loads, downloading if needed
    maxOutputTokens: Int = 512
    temperature: Float = 0.7
    topP: Float = 1.0
    topK: Int? = null
    minP: Float? = null
    frequencyPenalty: Float? = null
    presencePenalty: Float? = null
    repetitionPenalty: Float? = null
    seed: Int? = null
    stopSequences: List<String> = []
    systemPrompt: String? = null
    reasoning: ReasoningOptions? = null
    structuredOutput: StructuredOutput? = null
    tools: List<ToolDefinition> = []        // empty = use the registry
    toolChoice: ToolChoice = AUTO           // AUTO | NONE | REQUIRED | forced(name)
    maxToolCalls: Int = 5

ReasoningOptions:
    mode: ReasoningMode = ON                // ON | OFF; OFF suppresses thinking entirely
    includeInOutput: Boolean = false        // true streams thought tokens to the caller
    pattern: String? = null                 // null uses the model's own thinking tags

SttOptions:
    language: String? = null                // BCP-47; null auto-detects
    punctuation: Boolean = true
    wordTimestamps: Boolean = true
    diarization: Boolean = false
    maxSpeakers: Int? = null
    translateToEnglish: Boolean = false

TtsOptions:
    voice: String? = null
    language: String = "en-US"
    speed: Float = 1.0
    pitch: Float = 1.0
    format: AudioFormat = PCM
    sampleRate: Int = 22050

VadOptions:
    activationThreshold: Float? = null      // null uses the model's calibrated default
    minSpeechMs: Int = 100
    minSilenceMs: Int = 300
    prefixPaddingMs: Int = 0

EmbedOptions:
    normalize: NormalizeMode = L2
    pooling: PoolingMode = MEAN

ImageOptions:
    negativePrompt: String? = null
    width: Int? = null
    height: Int? = null
    steps: Int? = null
    guidanceScale: Float? = null
    seed: Int? = null
    mode: ImageMode = GENERATE              // GENERATE | INPAINT(input, mask)
    reportPartials: Boolean = false

DiarizationOptions:
    threshold: Float? = null
    minimumDurationMs: Int? = null
    mergeGapMs: Int? = null

SegmentationOptions:
    includeDiagnosticImage: Boolean = false

StructuredOutput:
    schema: JsonSchema
    strict: Boolean = true

TurnHandlingOptions:
    endpointing: Endpointing = Endpointing(minDelayMs = 500, maxDelayMs = 3000)
    interruption: Interruption = Interruption(enabled = true, minDurationMs = 500)

RagConfig:
    topK: Int = 5
    chunkSize: Int = 512
    chunkOverlap: Int = 64
    similarityThreshold: Float? = null
    persistPath: String? = null

LoadOptions:
    framework: InferenceFramework? = null   // engine pin, load time only
    contextLength: Int? = null
    threads: Int? = null
    useGpu: Boolean? = null
```

## Inputs

```
AudioInput: bytes + AudioFormatSpec(encoding, sampleRate, channels)
    Constructors per SDK: pcm16(bytes, sampleRate, channels), float32(samples, sampleRate), wav(bytes), file(path)
ImageInput:
    Constructors per SDK: file(path), bytes(data), rawRgb(data, width, height), plus the platform image type
    (UIImage/CGImage on Apple, Bitmap on Android, HTMLImageElement/Blob on Web)
ChatMessage(role: SYSTEM | USER | ASSISTANT | TOOL, content: String, toolCallId: String? = null)
ModelRef(id: String, voice: String? = null)
RagDocument(text: String, metadata: Map<String, String>? = null) or RagDocument.file(path)
```

## Results

Every generation result carries the same metrics block, so no caller has to compute throughput itself.

```
GenerationResult:
    text: String
    thinkingText: String?
    toolCalls: List<ToolCall>
    finishReason: STOP | LENGTH | TOOL_CALLS | CANCELLED
    inputTokens: Int
    outputTokens: Int
    timeToFirstTokenMs: Long
    tokensPerSecond: Float
    requestId: String
    model: String

StructuredResult:   value (parsed), raw: String, valid: Boolean, plus the GenerationResult metrics
Transcription:      text, language?, confidence, words: List<Word(text, startMs, endMs, confidence, speakerId?)>, durationMs
Audio:              data, sampleRate, format, durationMs
AudioChunk:         data, index, isFinal
VadResult:          isSpeech, probability, segments: List<Segment(startMs, endMs)>
Embedding:          index, vector: FloatArray
RankedResult:       index, relevanceScore
ImageResult:        images: List<ImageData>, seed, steps
DiarizationResult:  segments: List<SpeakerSegment(speakerId, startMs, endMs)>, speakerCount
SegmentationResult: classMask, width, height, classes: List<ClassInfo>
RagResult:          answer, sources: List<Match(text, score, metadata)>, plus the GenerationResult metrics
Match:              text, score, metadata
SttState:           isReady, modelId?, supportsStreaming, languages: List<String>
ModelsState:        loaded: Map<ModelCategory, ModelInfo>, storageUsedBytes, storageFreeBytes
LoraState:          applied: List<AppliedAdapter(id, scale)>
RagStats:           documentCount, chunkCount, indexSizeBytes
```

## Events

One grammar: `started`, then deltas, then `completed` or a thrown error.

```
GenerationEvent:
    started(requestId)
    token(text, kind: TEXT | THOUGHT)
    toolCall(ToolCall)
    completed(GenerationResult)

TranscriptionEvent:
    started
    partial(text)
    final(Transcription)

VoiceEvent:
    userTranscribed(text, isFinal)
    agentStateChanged(LISTENING | THINKING | SPEAKING)
    agentResponse(text)
    speechStarted
    speechEnded
    error(message, recoverable)

RagEvent:
    retrieved(List<Match>)
    token(text, kind)
    completed(RagResult)

ImageEvent:
    started
    progress(step, totalSteps, partialImage?)
    completed(ImageResult)

DownloadEvent:
    progress(bytesDone, bytesTotal, percent)
    extracting
    completed(ModelInfo)

SdkEvent:
    ready
    modelLoaded(id, category)
    modelUnloaded(id)
    error(message, recoverable)
```

## Doc comment rules

Every public symbol gets a doc comment in the host language's convention (KDoc, Swift markup, dartdoc, TSDoc, Python docstrings). Keep them short:

- One sentence saying what the call does, in the imperative.
- Params and return only when the name does not already say it.
- One `@throws`/`Raises` line naming the realistic failure.
- A two-line usage example on namespace entry points (`llm.generate`, `voice.createSession`, `rag.open`) and nowhere else.
- No restating the signature, no banners, no changelog narration.

## Deprecation

Old verbs remain for one release as thin deprecated forwarders pointing at the new name, then get deleted. Nothing is silently rerouted: a deprecated call does exactly what it used to do.
