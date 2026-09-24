// No weights, downloads, or network: exercise the pinned MLX generation loop
// with deterministic tokens and a tiny synthetic tensor model.
import Foundation
import MLX
import MLXLMCommon
import MLXNN

private struct DeterministicTokenizer: Tokenizer {
  var bosToken: String? { nil }
  var eosToken: String? { nil }
  var unknownToken: String? { nil }
  func encode(text: String, addSpecialTokens: Bool) -> [Int] { [] }
  func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
    tokenIds.map { UnicodeScalar($0).map(String.init) ?? "\u{FFFD}" }.joined()
  }
  func convertTokenToId(_ token: String) -> Int? { nil }
  func convertIdToToken(_ id: Int) -> String? { nil }
  func applyChatTemplate(
    messages: [[String: any Sendable]],
    tools: [[String: any Sendable]]?,
    additionalContext: [String: any Sendable]?
  ) throws -> [Int] { [] }
}
private struct DelayedTokens: TokenIteratorProtocol {
  let maxTokens: Int? = 1000
  var tokenCount = 0
  let promptPrefillTime: TimeInterval = 0
  mutating func next() -> Int? {
    guard tokenCount < 1000 else { return nil }
    Thread.sleep(forTimeInterval: 0.005)
    tokenCount += 1
    return 120
  }
}
private final class ScriptedModel: Module, LanguageModel, KVCacheDimensionProvider {
  var kvHeads: [Int] { [] }
  func prepare(
    _ input: LMInput, cache: [KVCache], state: LMOutput.State?, prefill: PrefillParameters
  ) throws -> PrepareResult {
    .tokens(input.text)
  }
  func callAsFunction(_ inputs: MLXArray, cache: [KVCache]?) -> MLXArray {
    Thread.sleep(forTimeInterval: 0.005)
    let tokens = inputs.asArray(Int.self)
    var logits = [Float](repeating: -100, count: tokens.count * 128)
    let next: [Int: Int] = [
      1: 97, 97: 98, 98: 60, 60: 69, 69: 78, 78: 68, 68: 62, 62: 120, 120: 120
    ]
    for (index, token) in tokens.enumerated() { logits[index * 128 + (next[token] ?? 120)] = 100 }
    return MLXArray(logits, [1, tokens.count, 128])
  }
}
@main
struct CancellationUsageRegression {
  static func main() async throws {
    try await Device.withDefaultDevice(.cpu) {
      let (events, producer) = generateTask(
        promptTokenCount: 37,
        modelConfiguration: ModelConfiguration(id: "hermetic/cancellation"),
        tokenizer: DeterministicTokenizer(),
        iterator: DelayedTokens()
      )
      var chunks = 0
      var info: GenerateCompletionInfo?
      for await event in events {
        switch event {
        case .chunk:
          chunks += 1
          producer.cancel()
        case .info(let completion): info = completion
        default: preconditionFailure("unexpected tool event")
        }
      }
      await producer.value
      precondition(chunks > 0 && chunks < 1000)
      precondition(info?.promptTokenCount == 37)
      precondition(info?.generationTokenCount == chunks)
      guard case .cancelled = info?.stopReason else {
        fatalError("missing cancellation terminal info")
      }
      let cancellationResult =
        "Pinned MLX generateLoopTask: cancellation retained prompt=37 completion=\(chunks), final info received\n"
      FileHandle.standardOutput.write(Data(cancellationResult.utf8))

      let iterator = try TokenIterator(
        input: LMInput(tokens: MLXArray([Int](repeating: 1, count: 37))),
        model: ScriptedModel(),
        parameters: GenerateParameters(maxTokens: 1000, temperature: 0)
      )
      let (rawEvents, rawProducer) = generateTokenTask(
        promptTokenCount: 37,
        modelConfiguration: ModelConfiguration(id: "hermetic/raw-cancellation"),
        tokenizer: DeterministicTokenizer(),
        iterator: iterator
      )
      var stopFilter = MLXTextStopFilter(stopStrings: ["<END>"])
      var output = ""
      var rawTokenCount = 0
      var rawInfo: GenerateCompletionInfo?
      for await event in rawEvents {
        switch event {
        case .token(let token):
          rawTokenCount += 1
          guard !stopFilter.stopped else { continue }
          output += stopFilter.process(UnicodeScalar(token).map(String.init) ?? "\u{FFFD}")
          if stopFilter.stopped { rawProducer.cancel() }
        case .info(let completion): rawInfo = completion
        }
      }
      await rawProducer.value
      precondition(output == "ab")
      precondition(stopFilter.stopped)
      precondition(rawInfo?.promptTokenCount == 37)
      precondition(rawInfo?.generationTokenCount == rawTokenCount)
      precondition(rawTokenCount >= 7 && rawTokenCount < 1000)
      guard case .cancelled = rawInfo?.stopReason else { fatalError("missing raw terminal info") }
      let stopResult =
        "Pinned MLX raw generation: textual stop retained prompt=37 completion=\(rawTokenCount), output=ab, no tail\n"
      FileHandle.standardOutput.write(Data(stopResult.utf8))
    }
  }
}
