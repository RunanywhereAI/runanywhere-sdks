// Text-only routing for the D1, D1 Omni, and GLiNER decision checkpoints.
// Image inputs stay out of this path.

import Foundation
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
    case decider
    case d1
    case omni
    case gliner
}

enum MLXTextDecisionCheckpoint {
    static func kind(at directory: URL) -> MLXTextDecisionKind? {
        if Qwen35DeciderModel.isDeciderCheckpoint(at: directory) {
            return .decider
        }
        guard let modelType = string(json(at: directory.appending(component: "config.json")), key: "model_type") else {
            return nil
        }
        switch modelType {
        case "d1_omni":
            return .omni
        case "extractor":
            return .gliner
        case "lfm2_vl":
            let autoMap = json(at: directory.appending(component: "config.json"))?["auto_map"] as? [String: Any]
            return autoMap?["AutoModel"] as? String == "modeling_d1.D1Model" ? .d1 : nil
        default:
            return nil
        }
    }

    static func glinerMaxTokens(at directory: URL) -> Int {
        let encoder = json(at: directory.appending(component: "config.json"))?["encoder_config"] as? [String: Any]
        let limit = (encoder?["max_position_embeddings"] as? NSNumber)?.intValue ?? 512
        return max(limit, 1)
    }

    private static func json(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func string(_ object: [String: Any]?, key: String) -> String? {
        object?[key] as? String
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
                state: request.state, question: question, tokenizer: tokenizer,
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
