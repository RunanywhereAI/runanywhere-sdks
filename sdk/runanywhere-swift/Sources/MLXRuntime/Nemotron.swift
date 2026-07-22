//
//  Nemotron.swift
//  MLXRuntime Module
//

import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import MLXNN

/// Registers NVIDIA's original Nemotron decoder architecture with the standard
/// MLXLLM factory used by the RunAnywhere MLX provider. Upstream mlx-swift-lm
/// supports `nemotron_h`, which is a different hybrid architecture; treating
/// the original `nemotron` checkpoint as that model would silently load the
/// wrong graph.
func registerRunAnywhereNemotronModelType() async {
    guard !(await LLMTypeRegistry.shared.contains("nemotron")) else { return }
    await LLMTypeRegistry.shared.registerModelType("nemotron") { data in
        let configuration = try JSONDecoder.json5().decode(
            RunAnywhereNemotronConfiguration.self,
            from: data
        )
        try configuration.validateModelConfiguration()
        return RunAnywhereNemotronModel(configuration)
    }
}

private final class RunAnywhereNemotronLayerNorm1P: LayerNorm {
    init(dimensions: Int, eps: Float) {
        super.init(dimensions: dimensions, eps: eps, affine: true, bias: true)
    }

    override func callAsFunction(_ input: MLXArray) -> MLXArray {
        MLXFast.layerNorm(
            input,
            weight: weight.map { $0 + 1 },
            bias: bias,
            eps: eps
        )
    }
}

private final class RunAnywhereNemotronAttention: Module {
    private let configuration: RunAnywhereNemotronConfiguration
    private let scale: Float

    @ModuleInfo(key: "q_proj")
    private var queryProjection: Linear
    @ModuleInfo(key: "k_proj")
    private var keyProjection: Linear
    @ModuleInfo(key: "v_proj")
    private var valueProjection: Linear
    @ModuleInfo(key: "o_proj")
    private var outputProjection: Linear

    private let rope: RoPELayer

    init(_ configuration: RunAnywhereNemotronConfiguration) {
        self.configuration = configuration
        let headDimension = configuration.resolvedHeadDimension
        scale = pow(Float(headDimension), -0.5)
        _queryProjection.wrappedValue = Linear(
            configuration.hiddenSize,
            configuration.attentionHeads * headDimension,
            bias: configuration.attentionBias
        )
        _keyProjection.wrappedValue = Linear(
            configuration.hiddenSize,
            configuration.keyValueHeads * headDimension,
            bias: configuration.attentionBias
        )
        _valueProjection.wrappedValue = Linear(
            configuration.hiddenSize,
            configuration.keyValueHeads * headDimension,
            bias: configuration.attentionBias
        )
        _outputProjection.wrappedValue = Linear(
            configuration.attentionHeads * headDimension,
            configuration.hiddenSize,
            bias: configuration.attentionBias
        )
        rope = initializeRope(
            dims: Int(configuration.partialRotaryFactor * Float(headDimension)),
            base: configuration.ropeTheta,
            traditional: configuration.ropeTraditional,
            scalingConfig: configuration.ropeScaling,
            maxPositionEmbeddings: configuration.maxPositionEmbeddings
        )
    }

    func callAsFunction(
        _ input: MLXArray,
        mask: MLXFast.ScaledDotProductAttentionMaskMode,
        cache: KVCache?
    ) -> MLXArray {
        let batchSize = input.dim(0)
        let sequenceLength = input.dim(1)

        var queries = queryProjection(input)
            .reshaped(batchSize, sequenceLength, configuration.attentionHeads, -1)
            .transposed(0, 2, 1, 3)
        var keys = keyProjection(input)
            .reshaped(batchSize, sequenceLength, configuration.keyValueHeads, -1)
            .transposed(0, 2, 1, 3)
        let values = valueProjection(input)
            .reshaped(batchSize, sequenceLength, configuration.keyValueHeads, -1)
            .transposed(0, 2, 1, 3)

        let offset = cache?.ropeOffset
        queries = applyRotaryPosition(rope, to: queries, offset: offset)
        keys = applyRotaryPosition(rope, to: keys, offset: offset)

        return outputProjection(
            attentionWithCacheUpdate(
                queries: queries,
                keys: keys,
                values: values,
                cache: cache,
                scale: scale,
                mask: mask
            )
            .transposed(0, 2, 1, 3)
            .reshaped(batchSize, sequenceLength, -1)
        )
    }
}

private final class RunAnywhereNemotronMLP: Module, UnaryLayer {
    @ModuleInfo(key: "down_proj")
    private var downProjection: Linear
    @ModuleInfo(key: "up_proj")
    private var upProjection: Linear

    init(_ configuration: RunAnywhereNemotronConfiguration) {
        _downProjection.wrappedValue = Linear(
            configuration.intermediateSize,
            configuration.hiddenSize,
            bias: configuration.mlpBias
        )
        _upProjection.wrappedValue = Linear(
            configuration.hiddenSize,
            configuration.intermediateSize,
            bias: configuration.mlpBias
        )
    }

    func callAsFunction(_ input: MLXArray) -> MLXArray {
        downProjection(relu(upProjection(input)).square())
    }
}

private final class RunAnywhereNemotronTransformerBlock: Module {
    @ModuleInfo(key: "self_attn")
    private var attention: RunAnywhereNemotronAttention
    @ModuleInfo(key: "mlp")
    private var mlp: RunAnywhereNemotronMLP
    @ModuleInfo(key: "input_layernorm")
    private var inputLayerNorm: RunAnywhereNemotronLayerNorm1P
    @ModuleInfo(key: "post_attention_layernorm")
    private var postAttentionLayerNorm: RunAnywhereNemotronLayerNorm1P

    init(_ configuration: RunAnywhereNemotronConfiguration) {
        _attention.wrappedValue = RunAnywhereNemotronAttention(configuration)
        _mlp.wrappedValue = RunAnywhereNemotronMLP(configuration)
        _inputLayerNorm.wrappedValue = RunAnywhereNemotronLayerNorm1P(
            dimensions: configuration.hiddenSize,
            eps: configuration.normEpsilon
        )
        _postAttentionLayerNorm.wrappedValue = RunAnywhereNemotronLayerNorm1P(
            dimensions: configuration.hiddenSize,
            eps: configuration.normEpsilon
        )
    }

    func callAsFunction(
        _ input: MLXArray,
        mask: MLXFast.ScaledDotProductAttentionMaskMode,
        cache: KVCache?
    ) -> MLXArray {
        let attentionOutput = input + attention(inputLayerNorm(input), mask: mask, cache: cache)
        return attentionOutput + mlp(postAttentionLayerNorm(attentionOutput))
    }
}

private final class RunAnywhereNemotronModelInner: Module {
    @ModuleInfo(key: "embed_tokens")
    var tokenEmbedding: Embedding

    let layers: [RunAnywhereNemotronTransformerBlock]
    let norm: RunAnywhereNemotronLayerNorm1P

    init(_ configuration: RunAnywhereNemotronConfiguration) {
        precondition(configuration.vocabularySize > 0)
        _tokenEmbedding.wrappedValue = Embedding(
            embeddingCount: configuration.vocabularySize,
            dimensions: configuration.hiddenSize
        )
        layers = (0 ..< configuration.hiddenLayers).map { _ in
            RunAnywhereNemotronTransformerBlock(configuration)
        }
        norm = RunAnywhereNemotronLayerNorm1P(
            dimensions: configuration.hiddenSize,
            eps: configuration.normEpsilon
        )
    }

    func callAsFunction(_ input: MLXArray, cache: [KVCache]? = nil) -> MLXArray {
        var hiddenStates = tokenEmbedding(input)
        let mask = createAttentionMask(h: hiddenStates, cache: cache?.first)
        for (index, layer) in layers.enumerated() {
            hiddenStates = layer(hiddenStates, mask: mask, cache: cache?[index])
        }
        return norm(hiddenStates)
    }
}

private final class RunAnywhereNemotronModel: Module, LLMModel, KVCacheDimensionProvider {
    let vocabularySize: Int
    let kvHeads: [Int]
    let model: RunAnywhereNemotronModelInner

    @ModuleInfo(key: "lm_head")
    private var languageModelHead: Linear?

    init(_ configuration: RunAnywhereNemotronConfiguration) {
        vocabularySize = configuration.vocabularySize
        kvHeads = (0 ..< configuration.hiddenLayers).map { _ in
            configuration.keyValueHeads
        }
        model = RunAnywhereNemotronModelInner(configuration)
        if !configuration.tieWordEmbeddings {
            _languageModelHead.wrappedValue = Linear(
                configuration.hiddenSize,
                configuration.vocabularySize,
                bias: false
            )
        }
    }

    func callAsFunction(_ input: MLXArray, cache: [KVCache]?) -> MLXArray {
        let hiddenStates = model(input, cache: cache)
        if let languageModelHead {
            return languageModelHead(hiddenStates)
        }
        return model.tokenEmbedding.asLinear(hiddenStates)
    }

    func sanitize(weights: [String: MLXArray]) -> [String: MLXArray] {
        weights.filter { !$0.key.contains("self_attn.rotary_emb.inv_freq") }
    }

    func messageGenerator(tokenizer: any Tokenizer) -> any MessageGenerator {
        do {
            _ = try tokenizer.applyChatTemplate(messages: [["role": "system", "content": "test"]])
            return DefaultMessageGenerator()
        } catch {
            return NoSystemMessageGenerator()
        }
    }
}

extension RunAnywhereNemotronModel: LoRAModel {
    var loraLayers: [Module] {
        model.layers
    }
}

private struct RunAnywhereNemotronConfiguration: Codable, Sendable,
    ModelConfigurationValidating {
    let modelType: String
    let hiddenSize: Int
    let hiddenActivation: String
    let hiddenLayers: Int
    let intermediateSize: Int
    let attentionHeads: Int
    let normEpsilon: Float
    let vocabularySize: Int
    let keyValueHeads: Int
    let headDimension: Int?
    let keyValueChannels: Int?
    let maxPositionEmbeddings: Int?
    let attentionBias: Bool
    let mlpBias: Bool
    let partialRotaryFactor: Float
    let ropeTheta: Float
    let ropeTraditional: Bool
    let ropeScaling: [String: StringOrNumber]?
    let tieWordEmbeddings: Bool

    var resolvedHeadDimension: Int {
        headDimension ?? keyValueChannels ?? (hiddenSize / attentionHeads)
    }

    enum CodingKeys: String, CodingKey {
        case modelType = "model_type"
        case hiddenSize = "hidden_size"
        case hiddenActivation = "hidden_act"
        case hiddenLayers = "num_hidden_layers"
        case intermediateSize = "intermediate_size"
        case attentionHeads = "num_attention_heads"
        case normEpsilon = "norm_eps"
        case vocabularySize = "vocab_size"
        case keyValueHeads = "num_key_value_heads"
        case headDimension = "head_dim"
        case keyValueChannels = "kv_channels"
        case maxPositionEmbeddings = "max_position_embeddings"
        case attentionBias = "attention_bias"
        case mlpBias = "mlp_bias"
        case partialRotaryFactor = "partial_rotary_factor"
        case ropeTheta = "rope_theta"
        case ropeTraditional = "rope_traditional"
        case ropeScaling = "rope_scaling"
        case tieWordEmbeddings = "tie_word_embeddings"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        modelType = try container.decode(String.self, forKey: .modelType)
        hiddenSize = try container.decode(Int.self, forKey: .hiddenSize)
        hiddenActivation = try container.decode(String.self, forKey: .hiddenActivation)
        hiddenLayers = try container.decode(Int.self, forKey: .hiddenLayers)
        intermediateSize = try container.decode(Int.self, forKey: .intermediateSize)
        attentionHeads = try container.decode(Int.self, forKey: .attentionHeads)
        normEpsilon = try container.decode(Float.self, forKey: .normEpsilon)
        vocabularySize = try container.decode(Int.self, forKey: .vocabularySize)
        keyValueHeads = try container.decodeIfPresent(Int.self, forKey: .keyValueHeads)
            ?? attentionHeads
        headDimension = try container.decodeIfPresent(Int.self, forKey: .headDimension)
        keyValueChannels = try container.decodeIfPresent(Int.self, forKey: .keyValueChannels)
        maxPositionEmbeddings = try container.decodeIfPresent(
            Int.self,
            forKey: .maxPositionEmbeddings
        )
        attentionBias = try container.decodeIfPresent(Bool.self, forKey: .attentionBias) ?? false
        mlpBias = try container.decodeIfPresent(Bool.self, forKey: .mlpBias) ?? false
        partialRotaryFactor = try container.decodeIfPresent(
            Float.self,
            forKey: .partialRotaryFactor
        ) ?? 0.5
        ropeTheta = try container.decodeIfPresent(Float.self, forKey: .ropeTheta) ?? 10_000
        ropeTraditional = try container.decodeIfPresent(Bool.self, forKey: .ropeTraditional)
            ?? false
        ropeScaling = try container.decodeIfPresent(
            [String: StringOrNumber].self,
            forKey: .ropeScaling
        )
        tieWordEmbeddings = try container.decodeIfPresent(
            Bool.self,
            forKey: .tieWordEmbeddings
        ) ?? false
    }

    func validateModelConfiguration() throws {
        guard modelType == "nemotron" else {
            throw ModelFactoryError.invalidConfiguration(
                "Expected model_type 'nemotron', got '\(modelType)'"
            )
        }
        guard hiddenActivation == "relu2" else {
            throw ModelFactoryError.invalidConfiguration(
                "Nemotron hidden_act '\(hiddenActivation)' is unsupported"
            )
        }
        guard attentionHeads > 0, keyValueHeads > 0,
              hiddenSize.isMultiple(of: attentionHeads),
              attentionHeads.isMultiple(of: keyValueHeads) else {
            throw ModelFactoryError.invalidConfiguration(
                "Nemotron attention dimensions are inconsistent"
            )
        }
        if let headDimension, headDimension != resolvedHeadDimension {
            throw ModelFactoryError.invalidConfiguration(
                "Nemotron head_dim conflicts with the resolved attention head dimension"
            )
        }
        if let keyValueChannels, keyValueChannels != resolvedHeadDimension {
            throw ModelFactoryError.invalidConfiguration(
                "Nemotron kv_channels conflicts with the resolved attention head dimension"
            )
        }
        let rotaryDimensions = partialRotaryFactor * Float(resolvedHeadDimension)
        guard rotaryDimensions > 0,
              rotaryDimensions.rounded() == rotaryDimensions,
              Int(rotaryDimensions).isMultiple(of: 2) else {
            throw ModelFactoryError.invalidConfiguration(
                "Nemotron partial_rotary_factor must produce an even positive dimension"
            )
        }
    }
}
