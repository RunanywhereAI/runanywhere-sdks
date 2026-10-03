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
        /// - Throws: `SDKException` when no decision model is loaded or scoring
        ///   fails.
        public func decide(
            state: String,
            questions: [DecisionQuestion],
            temperature: Float? = nil
        ) async throws -> [DecisionAnswer] {
            guard !questions.isEmpty else { return [] }

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
            if let temperature {
                var options = RADecisionOptions()
                options.temperature = max(0, temperature)
                request.options = options
            }

            let result = try await RunAnywhere.decideProto(request)
            return result.answers.map(DecisionAnswer.init(proto:))
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
            type = .choice
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
