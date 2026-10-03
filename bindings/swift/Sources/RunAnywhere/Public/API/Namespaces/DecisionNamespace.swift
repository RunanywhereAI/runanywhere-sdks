//
//  DecisionNamespace.swift
//  RunAnywhere SDK
//
//  `RunAnywhere.decision` — joint decision scoring. One state plus typed
//  questions in, calibrated answers (choice / noul / score) out. No streaming:
//  a decision model scores every option in one forward pass.
//

import Foundation

/// The kind of answer a decision question expects. Selects both the shape of
/// the answer and the calibration formula used for its confidence.
public enum DecisionQuestionKind: Sendable {
    /// Pick one of the listed options; the answer carries per-option probabilities.
    case choice
    /// Yes / no / unknown; the answer carries the probability of the "true" option.
    case noul
    /// A level on an ordered scale; the answer carries the expected level index.
    case score
}

public extension RunAnywhere {

    /// Joint decision scoring.
    static var decision: Decision { Decision() }

    /// One typed question about a state.
    struct DecisionQuestion: Sendable {
        public let id: String
        public let type: DecisionQuestionKind
        public let instructions: String
        public let options: [DecisionOption]

        public init(id: String, type: DecisionQuestionKind, instructions: String, options: [DecisionOption]) {
            self.id = id
            self.type = type
            self.instructions = instructions
            self.options = options
        }
    }

    /// One candidate answer.
    struct DecisionOption: Sendable {
        public let key: String
        public let description: String

        public init(key: String, description: String) {
            self.key = key
            self.description = description
        }
    }

    /// The model's answer to one question.
    struct DecisionAnswer: Sendable {
        public let id: String
        public let type: DecisionQuestionKind
        /// CHOICE: the winning option key.
        public let choice: String?
        /// NOUL: probability of the "true" option.
        public let noul: Float?
        /// SCORE: expected level index over the ordered options.
        public let score: Float?
        /// Probability of each option, keyed by the request option key.
        public let probabilities: [String: Float]
        /// Calibrated confidence in [0, 1].
        public let confidence: Float
        /// SCORE only: level key -> description.
        public let legend: [String: String]
    }

    /// One decision pass: the answers plus the wording version that produced them.
    struct DecisionRun: Sendable {
        /// One answer per request question, in request order.
        public let answers: [DecisionAnswer]
        /// The prompt-wording version the model served; 0 when it reports none.
        /// Pinning this on a later request makes a wording change explicit.
        public let promptFormatVersion: UInt32
        /// Tokens of the jointly-evaluated prompt.
        public let inputTokens: Int64
    }

    /// Score `state` with the loaded decision model.
    struct Decision: Sendable {

        /// Answer every question jointly in one pass.
        ///
        /// ```swift
        /// let answers = try await RunAnywhere.decision.decide(
        ///     state: "I was charged twice.",
        ///     questions: [
        ///         .init(id: "team", type: .choice, instructions: "Which team?",
        ///               options: [.init(key: "billing", description: "Payments"),
        ///                         .init(key: "technical", description: "Bugs")])
        ///     ])
        /// print(answers[0].choice ?? "")
        /// ```
        ///
        /// - Parameters:
        ///   - state: The text every question is asked about.
        ///   - questions: The questions to answer, evaluated jointly.
        ///   - temperature: Per-request calibration override; nil = the model's
        ///     own per-type value.
        ///   - promptFormatVersion: Requires a specific prompt-wording version.
        ///     nil = whatever this model serves. A model serving a different
        ///     version throws `SDKException` rather than scoring with wording
        ///     the caller did not expect.
        ///
        /// - Throws: `SDKException` when no decision model is loaded, the
        ///   prompt-format pin does not match, or scoring fails.
        public func decide(
            state: String,
            questions: [DecisionQuestion],
            temperature: Float? = nil,
            promptFormatVersion: UInt32? = nil
        ) async throws -> [DecisionAnswer] {
            try await decideResult(
                state: state, questions: questions, temperature: temperature,
                promptFormatVersion: promptFormatVersion
            ).answers
        }

        /// Like `decide`, but also returns the wording version the model served
        /// and the prompt token count.
        public func decideResult(
            state: String,
            questions: [DecisionQuestion],
            temperature: Float? = nil,
            promptFormatVersion: UInt32? = nil
        ) async throws -> DecisionRun {
            guard !questions.isEmpty else {
                return DecisionRun(answers: [], promptFormatVersion: 0, inputTokens: 0)
            }

            var request = RADecisionRequest()
            request.state = state
            request.questions = questions.map { question in
                var proto = RADecisionQuestion()
                proto.id = question.id
                proto.type = Self.protoType(question.type)
                proto.instructions = question.instructions
                proto.options = question.options.map { option in
                    var protoOption = RADecisionOption()
                    protoOption.key = option.key
                    protoOption.description_p = option.description
                    return protoOption
                }
                return proto
            }
            if temperature != nil || promptFormatVersion != nil {
                var options = RADecisionOptions()
                if let temperature {
                    options.temperature = max(0, temperature)
                }
                if let promptFormatVersion {
                    options.promptFormatVersion = promptFormatVersion
                }
                request.options = options
            }

            let result = try await RunAnywhere.decideProto(request)
            return DecisionRun(
                answers: result.answers.map(DecisionAnswer.init(proto:)),
                promptFormatVersion: result.promptFormatVersion,
                inputTokens: Int64(result.usage.inputTokens)
            )
        }

        private static func protoType(_ type: DecisionQuestionKind) -> RADecisionQuestionType {
            switch type {
            case .choice: return .choice
            case .noul: return .noul
            case .score: return .score
            }
        }
    }
}

// MARK: - Proto decoding

private extension RunAnywhere.DecisionAnswer {
    init(proto: RADecisionAnswer) {
        let type: DecisionQuestionKind
        let choice: String?
        let noul: Float?
        let score: Float?
        switch proto.answer {
        case .choice(let value):
            type = .choice
            choice = value
            noul = nil
            score = nil
        case .noul(let value):
            type = .noul
            choice = nil
            noul = value
            score = nil
        case .score(let value):
            type = .score
            choice = nil
            noul = nil
            score = value
        case nil:
            // No oneof value: fall back to the answer's own `type` field
            // rather than assuming CHOICE, which would mislabel a noul/score
            // answer whose value happens to be zero/empty. The value fields
            // stay nil for that kind.
            switch proto.type {
            case .noul: type = .noul
            case .score: type = .score
            default: type = .choice
            }
            choice = nil
            noul = nil
            score = nil
        }
        self.init(
            id: proto.id,
            type: type,
            choice: choice,
            noul: noul,
            score: score,
            probabilities: proto.probabilities,
            confidence: proto.confidence,
            legend: proto.legend
        )
    }
}

// MARK: - Internal proto-level helper

extension RunAnywhere {

    internal static func decideProto(_ request: RADecisionRequest) async throws -> RADecisionResult {
        guard isReady else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        try await ensureServicesReady()
        // A decision model has no auto-load path through `ModelCategory`; the
        // model must already be resident under the decision component.
        guard let snapshot = componentLifecycleSnapshot(.decision),
              !(snapshot.modelID.isEmpty && snapshot.model.id.isEmpty) else {
            throw SDKException(
                code: .modelNotLoaded,
                message: "Decision model not loaded",
                category: .component
            )
        }
        return try await CppBridge.Decision.shared.decide(request, loadedModel: snapshot)
    }
}
