// Text-only routing for the D1, D1 Omni, and GLiNER decision checkpoints.
// Image inputs stay out of this path.

import CoreImage
import Foundation
import MLXBackend
import MLXLLM
import MLXLMCommon
import MLXVLM

struct MLXDecisionPass {
    struct Answer {
        var optionIds: [String]
        var probabilities: [String: Float]
    }

    var answers: [Answer]
    var inputTokens: Int

    init(answers: [Answer], inputTokens: Int) {
        self.answers = answers
        self.inputTokens = inputTokens
    }

    init(_ result: ClefDecisionResult) {
        answers = result.answers.map {
            Answer(optionIds: $0.optionIds, probabilities: $0.probabilities)
        }
        inputTokens = result.inputTokens
    }
}

enum MLXTextDecisionKind {
    case jointDecider
    case decider
    case d1
    case omni
    case gliner
}

/// The few `config.json` fields that identify a checkpoint. Each field is read
/// on its own, so a value of an unexpected type drops that field instead of the file.
private struct MLXCheckpointConfig: Decodable {
    let modelType: String?
    let autoModel: String?
    let encoderMaxPositionEmbeddings: Int?

    private enum CodingKeys: String, CodingKey {
        case modelType = "model_type"
        case autoMap = "auto_map"
        case encoderConfig = "encoder_config"
    }

    private enum AutoMapKeys: String, CodingKey {
        case autoModel = "AutoModel"
    }

    private enum EncoderKeys: String, CodingKey {
        case maxPositionEmbeddings = "max_position_embeddings"
    }

    init(from decoder: Decoder) throws {
        let root = try decoder.container(keyedBy: CodingKeys.self)
        modelType = try? root.decode(String.self, forKey: .modelType)
        let autoMap = try? root.nestedContainer(keyedBy: AutoMapKeys.self, forKey: .autoMap)
        autoModel = try? autoMap?.decode(String.self, forKey: .autoModel)
        let encoder = try? root.nestedContainer(keyedBy: EncoderKeys.self, forKey: .encoderConfig)
        encoderMaxPositionEmbeddings = try? encoder?.decode(Int.self, forKey: .maxPositionEmbeddings)
    }
}

enum MLXTextDecisionCheckpoint {
    static func kind(at directory: URL) -> MLXTextDecisionKind? {
        // Joint checkpoints also carry decision_config.json, so they are checked first.
        if Qwen35JointDeciderCheckpoint.isCheckpoint(at: directory) {
            return .jointDecider
        }
        if Qwen35DeciderModel.isDeciderCheckpoint(at: directory) {
            return .decider
        }
        guard let config = config(at: directory), let modelType = config.modelType else {
            return nil
        }
        switch modelType {
        case "d1_omni":
            return .omni
        case "extractor":
            return .gliner
        case "lfm2_vl":
            return config.autoModel == "modeling_d1.D1Model" ? .d1 : nil
        default:
            return nil
        }
    }

    static func glinerMaxTokens(at directory: URL) -> Int {
        let limit = config(at: directory)?.encoderMaxPositionEmbeddings ?? 512
        return max(limit, 1)
    }

    private static func config(at directory: URL) -> MLXCheckpointConfig? {
        guard let data = try? Data(contentsOf: directory.appending(component: "config.json")) else { return nil }
        return try? JSONDecoder().decode(MLXCheckpointConfig.self, from: data)
    }
}

enum MLXTextDecisions {
    static func scoreD1(_ model: D1Model, request: ClefDecisionRequest) throws -> MLXDecisionPass {
        guard !request.questions.isEmpty else {
            throw MLXTextDecisionError("a decision needs at least one question")
        }
        var answers: [MLXDecisionPass.Answer] = []
        var inputTokens = 0
        for question in request.questions {
            let asked = try d1Question(question)
            let scored = try model.decide(state: request.state, question: asked, images: [])
            inputTokens += scored.inputTokens
            let values = scored.probabilities.map(Float.init)
            answers.append(
                MLXDecisionPass.Answer(
                    optionIds: question.options.map(\.key),
                    probabilities: try keyed(question, values: values, trueFirst: question.kind == .noul)))
        }
        return MLXDecisionPass(answers: answers, inputTokens: inputTokens)
    }

    static func scoreOmni(
        _ model: D1Omni, tokenizer: any MLXLMCommon.Tokenizer, request: ClefDecisionRequest
    ) throws -> MLXDecisionPass {
        guard !request.questions.isEmpty else {
            throw MLXTextDecisionError("a decision needs at least one question")
        }
        let questions = try request.questions.map(omniQuestion)
        var inputTokens = 0
        for question in questions {
            let encoded = try D1OmniPrompt.encode(
                state: request.state,
                question: question,
                tokenizer: tokenizer,
                maxLength: model.config.maxLength)
            inputTokens += encoded.tokens.count
        }
        let rows = try model.probabilities(
            state: request.state, questions: questions, tokenizer: tokenizer)
        guard rows.count == request.questions.count else {
            throw MLXTextDecisionError("D1 Omni returned a different number of answers than questions")
        }
        let answers = try zip(request.questions, rows).map { question, values in
            MLXDecisionPass.Answer(
                optionIds: question.options.map(\.key),
                probabilities: try keyed(question, values: values, trueFirst: question.kind == .noul))
        }
        return MLXDecisionPass(answers: answers, inputTokens: inputTokens)
    }

    static func scoreGLiNER(
        _ model: GLiNERClassifier, request: ClefDecisionRequest, maxTokens: Int
    ) throws -> MLXDecisionPass {
        guard !request.questions.isEmpty else {
            throw MLXTextDecisionError("a decision needs at least one question")
        }
        let tasks = try glinerTasks(request.questions)
        let results = try model.classify(text: request.state, tasks: tasks, maxTokens: maxTokens)
        guard results.count == request.questions.count else {
            throw MLXTextDecisionError("GLiNER returned a different number of answers than questions")
        }
        let answers = try zip(request.questions, results).map { question, result in
            let values = result.scores.map(\.probability)
            return MLXDecisionPass.Answer(
                optionIds: question.options.map(\.key),
                probabilities: try keyed(question, values: values, trueFirst: false))
        }
        // The classifier does not report how many tokens the encoder consumed.
        return MLXDecisionPass(answers: answers, inputTokens: 0)
    }

    /// Joint inline-readout deciders (pplx-decider v1.2). Every control
    /// applies; unset ones fall back to what the checkpoint declares.
    static func scoreJoint(
        _ model: Qwen35JointDecider, request: ClefDecisionRequest, controls: MLXDecisionControls
    ) throws -> MLXDecisionPass {
        guard !request.questions.isEmpty else {
            throw MLXTextDecisionError("a decision needs at least one question")
        }
        let images = try controls.images.map { image in
            UserInput.Image.ciImage(try image.decoded())
        }
        let jointRequest = DecisionRequest(
            state: request.state,
            questions: request.questions.map(jointQuestion),
            images: images
        )
        let response = try model.decide(jointRequest, options: controls.jointOptions)
        let answers = try zip(request.questions, response.answers).map { question, answer in
            let values = answer.probabilities.map(Float.init)
            // The joint runtime orders a yes/no answer false then true.
            let ordered = question.kind == .noul ? values.reversed() : values
            return MLXDecisionPass.Answer(
                optionIds: question.options.map(\.key),
                probabilities: try keyed(question, values: ordered, trueFirst: question.kind == .noul))
        }
        return MLXDecisionPass(answers: answers, inputTokens: response.usage.inputTokens)
    }

    private static func jointQuestion(_ question: ClefDecisionQuestion) -> DecisionQuestion {
        let criteria: DecisionCriteria
        switch question.kind {
        case .noul:
            criteria = .noul(
                whenTrue: description(question, keys: ["true", "yes"]),
                whenFalse: description(question, keys: ["false", "no"]))
        case .choice:
            criteria = .choice(question.options.map { DecisionOption($0.key, description: $0.description) })
        case .score:
            criteria = .score(levels: question.options.map(levelText))
        }
        return DecisionQuestion(id: question.id, instructions: question.instructions, criteria: criteria)
    }

    private static func d1Question(_ question: ClefDecisionQuestion) throws -> D1Question {
        let instructions = question.instructions ?? question.id
        switch question.kind {
        case .noul:
            return .noul(
                instructions: instructions,
                yes: description(question, keys: ["true", "yes"]),
                no: description(question, keys: ["false", "no"]))
        case .choice:
            return .choice(
                instructions: instructions,
                options: question.options.map { D1Option($0.key, description: $0.description) })
        case .score:
            return .score(instructions: instructions, levels: question.options.map(levelText))
        }
    }

    private static func omniQuestion(_ question: ClefDecisionQuestion) throws -> D1OmniQuestion {
        let kind: D1OmniQuestion.Kind
        switch question.kind {
        case .noul: kind = .noul
        case .choice: kind = .choice
        case .score: kind = .score
        }
        return try D1OmniQuestion(
            kind: kind,
            instructions: question.instructions ?? question.id,
            options: question.options.map {
                D1OmniQuestion.Option($0.key, description: $0.description ?? "")
            })
    }

    private static func glinerTasks(_ questions: [ClefDecisionQuestion]) throws -> [GLiNERClassificationTask] {
        var seen = Set<String>()
        return try questions.enumerated().map { index, question in
            let name = question.id.isEmpty ? "field-\(index)" : question.id
            guard seen.insert(name).inserted else {
                throw MLXTextDecisionError("GLiNER questions need unique ids")
            }
            return GLiNERClassificationTask(
                name: name,
                labels: question.options.map { GLiNERClassLabel($0.key, description: $0.description) },
                prompt: question.instructions)
        }
    }

    /// D1 and D1 Omni report a yes/no field as true then false, whatever order
    /// the caller listed the options. Choice and score stay in request order.
    private static func keyed(
        _ question: ClefDecisionQuestion, values: [Float], trueFirst: Bool
    ) throws -> [String: Float] {
        let keys = question.options.map(\.key)
        if trueFirst {
            guard values.count == 2 else {
                throw MLXTextDecisionError("a yes/no decision needs two scores")
            }
            if keys.isEmpty {
                return [:]
            }
            var mapped: [String: Float] = [:]
            for key in keys {
                switch key.lowercased() {
                case "true", "yes":
                    mapped[key] = values[0]
                case "false", "no":
                    mapped[key] = values[1]
                default:
                    throw MLXTextDecisionError("yes/no options must be true/false or yes/no")
                }
            }
            guard mapped.count == keys.count else {
                throw MLXTextDecisionError("yes/no options must name both sides once")
            }
            return mapped
        }
        guard keys.count == values.count, Set(keys).count == keys.count else {
            throw MLXTextDecisionError("option scores do not match the question")
        }
        return Dictionary(uniqueKeysWithValues: zip(keys, values))
    }

    private static func description(_ question: ClefDecisionQuestion, keys: [String]) -> String? {
        question.options.first { keys.contains($0.key.lowercased()) }?.description
    }

    private static func levelText(_ option: ClefDecisionOption) -> String {
        let text = option.description?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let text, !text.isEmpty { return text }
        return option.key
    }
}

struct MLXTextDecisionError: Error, LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

/// The caller's per-request controls, copied out of the borrowed
/// `rac_decision_options_t` so they outlive the C callback.
struct MLXDecisionControls: Sendable {
    struct Image: Sendable {
        let data: Data
        let mimeType: String?

        func decoded() throws -> CIImage {
            guard let image = CIImage(data: data) else {
                throw ImageError("image \(mimeType ?? "of unknown type") could not be decoded")
            }
            return image
        }
    }

    struct ImageError: Error, LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    /// `nil` = the model's calibrated value.
    var temperature: Float?
    var grouping: rac_decision_grouping_t = RAC_DECISION_GROUPING_UNSPECIFIED
    var maxLength: Int?
    var maxPixels: Int?
    var minPixels: Int?
    var images: [Image] = []

    init(_ options: rac_decision_options_t?) {
        guard let options else { return }
        temperature = options.temperature > 0 ? options.temperature : nil
        grouping = options.grouping
        maxLength = options.max_length > 0 ? Int(options.max_length) : nil
        maxPixels = options.max_pixels > 0 ? Int(options.max_pixels) : nil
        minPixels = options.min_pixels > 0 ? Int(options.min_pixels) : nil
        if let pointer = options.images {
            images = (0 ..< options.image_count).map { index in
                let image = pointer[index]
                return Image(
                    data: image.data.map { Data(bytes: $0, count: image.size) } ?? Data(),
                    mimeType: image.mime_type.map { String(cString: $0) })
            }
        }
    }

    /// Settings for the joint decider; unset values defer to the checkpoint.
    var jointOptions: Qwen35JointDeciderOptions {
        var options = Qwen35JointDeciderOptions(
            temperature: temperature.map(Double.init),
            maxLength: maxLength,
            maxPixels: maxPixels,
            minPixels: minPixels
        )
        switch grouping {
        case RAC_DECISION_GROUPING_JOINT: options.grouping = .joint
        case RAC_DECISION_GROUPING_PER_QUESTION: options.grouping = .perQuestion
        default: break
        }
        return options
    }

    /// Checkpoints with one fixed layout and no image input accept only the
    /// temperature and prompt version. Anything else is refused by name.
    func requireBasic() throws {
        var asked: [String] = []
        if grouping != RAC_DECISION_GROUPING_UNSPECIFIED { asked.append("grouping") }
        if maxLength != nil { asked.append("max_length") }
        if maxPixels != nil { asked.append("max_pixels") }
        if minPixels != nil { asked.append("min_pixels") }
        if !images.isEmpty { asked.append("images") }
        guard asked.isEmpty else {
            throw MLXDecisionUnsupported(
                "this decision model does not take \(asked.joined(separator: ", "))")
        }
    }
}

/// A control the loaded decision model cannot honour.
struct MLXDecisionUnsupported: Error, LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
