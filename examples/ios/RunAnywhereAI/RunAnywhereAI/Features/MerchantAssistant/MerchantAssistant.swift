//
//  MerchantAssistant.swift
//  RunAnywhereAI
//
//  Merchant Assistant for instant offline payment confirmations
//

import Foundation
import AVFoundation
import os

struct PaymentEvent: Codable {
    let amount: Int
    let method: String
    let name: String
    let lang: String
    let timestamp: Date = Date()

    var id: UUID = UUID()
}

struct PaymentTemplate {
    static let templates: [String: String] = [
        "en-IN": "Received ₹{amt} via {method} from {name}. Thank you.",
        "hi-IN": "₹{amt} mil gaye, {name} ji. Dhanyavaad.",
        "ta-IN": "{name} அவரிடமிருந்து ₹{amt} வந்தது. நன்றி.",
        "bn-IN": "{name} থেকে ₹{amt} পাওয়া গেছে। ধন্যবাদ।",
        "te-IN": "{name} నుండి ₹{amt} వచ్చింది. ధన్యవాదాలు.",
        "mr-IN": "{name} यांच्याकडून ₹{amt} मिळाले. धन्यवाद.",
        "gu-IN": "{name} પાસેથી ₹{amt} મળ્યા. આભાર.",
        "kn-IN": "{name} ಅವರಿಂದ ₹{amt} ಬಂದಿದೆ. ಧನ್ಯವಾದಗಳು.",
        "ml-IN": "{name} നിന്ന് ₹{amt} ലഭിച്ചു. നന്ദി.",
        "pa-IN": "{name} ਤੋਂ ₹{amt} ਮਿਲੇ। ਧੰਨਵਾਦ।"
    ]
}

@MainActor
final class MerchantAssistant: NSObject, ObservableObject {
    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "MerchantAssistant")
    private let synthesizer = AVSpeechSynthesizer()

    @Published var lastLatencyMs: Int?
    @Published var todayTotal: Int = 0
    @Published var todayCount: Int = 0
    @Published var recentEvents: [PaymentEvent] = []
    @Published var isSpeaking: Bool = false
    @Published var lastSpokenText: String?
    @Published var availableLanguages: [(String, String)] = [
        ("English", "en-IN"),
        ("Hindi", "hi-IN"),
        ("Tamil", "ta-IN"),
        ("Bengali", "bn-IN"),
        ("Telugu", "te-IN"),
        ("Marathi", "mr-IN"),
        ("Gujarati", "gu-IN"),
        ("Kannada", "kn-IN"),
        ("Malayalam", "ml-IN"),
        ("Punjabi", "pa-IN")
    ]

    private var latencyStart: CFTimeInterval?
    private let eventQueue = DispatchQueue(label: "com.runanywhere.merchant.events", qos: .userInitiated)

    override init() {
        super.init()
        synthesizer.delegate = self
        setupAudioSession()
        loadTodayStats()
    }

    private func setupAudioSession() {
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            logger.info("✅ Audio session configured for payment announcements")
        } catch {
            logger.error("❌ Failed to configure audio session: \(error)")
        }
        #endif
    }

    func processPaymentEvent(_ event: PaymentEvent) {
        logger.info("💰 Processing payment: ₹\(event.amount) from \(event.name)")

        let startTime = CACurrentMediaTime()

        let text = renderTemplate(event)
        lastSpokenText = text

        let utterance = AVSpeechUtterance(string: text)

        if let voice = AVSpeechSynthesisVoice(language: event.lang) {
            utterance.voice = voice
        } else {
            logger.warning("⚠️ Voice not available for \(event.lang), using default")
            utterance.voice = AVSpeechSynthesisVoice(language: "en-IN")
        }

        utterance.rate = 0.52
        utterance.pitchMultiplier = 1.05
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0
        utterance.postUtteranceDelay = 0.1

        latencyStart = startTime
        isSpeaking = true
        synthesizer.speak(utterance)

        updateStats(event)

        recentEvents.insert(event, at: 0)
        if recentEvents.count > 20 {
            recentEvents.removeLast()
        }

        persistEvent(event)
    }

    private func renderTemplate(_ event: PaymentEvent) -> String {
        let template = PaymentTemplate.templates[event.lang] ?? PaymentTemplate.templates["en-IN"]!

        let amountStr = formatCurrency(event.amount, for: event.lang)

        return template
            .replacingOccurrences(of: "{amt}", with: amountStr)
            .replacingOccurrences(of: "{method}", with: event.method)
            .replacingOccurrences(of: "{name}", with: event.name)
    }

    private func formatCurrency(_ amount: Int, for locale: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: locale.replacingOccurrences(of: "-IN", with: "_IN"))
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0

        return formatter.string(from: NSNumber(value: amount)) ?? String(amount)
    }

    private func updateStats(_ event: PaymentEvent) {
        todayTotal += event.amount
        todayCount += 1
        saveTodayStats()
    }

    private func saveTodayStats() {
        UserDefaults.standard.set(todayTotal, forKey: "merchant.today.total")
        UserDefaults.standard.set(todayCount, forKey: "merchant.today.count")
        UserDefaults.standard.set(Date(), forKey: "merchant.today.date")
    }

    private func loadTodayStats() {
        let savedDate = UserDefaults.standard.object(forKey: "merchant.today.date") as? Date ?? Date()

        if Calendar.current.isDateInToday(savedDate) {
            todayTotal = UserDefaults.standard.integer(forKey: "merchant.today.total")
            todayCount = UserDefaults.standard.integer(forKey: "merchant.today.count")
        } else {
            todayTotal = 0
            todayCount = 0
            saveTodayStats()
        }
    }

    private func persistEvent(_ event: PaymentEvent) {
        eventQueue.async { [weak self] in
            guard let self = self else { return }

            do {
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                let eventsPath = documentsPath.appendingPathComponent("merchant_events")

                try FileManager.default.createDirectory(at: eventsPath, withIntermediateDirectories: true)

                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                let fileName = "events_\(dateFormatter.string(from: Date())).jsonl"
                let filePath = eventsPath.appendingPathComponent(fileName)

                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(event)

                if let fileHandle = try? FileHandle(forWritingTo: filePath) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.write("\n".data(using: .utf8)!)
                    fileHandle.closeFile()
                } else {
                    try data.write(to: filePath)
                }

                self.logger.debug("📝 Event persisted to \(fileName)")
            } catch {
                self.logger.error("❌ Failed to persist event: \(error)")
            }
        }
    }

    func stopSpeaking() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
            isSpeaking = false
        }
    }

    func getDailySummary() -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_IN")

        let totalStr = formatter.string(from: NSNumber(value: todayTotal)) ?? String(todayTotal)

        return "Today: \(todayCount) payments • ₹\(totalStr)"
    }

    func resetDailyStats() {
        todayTotal = 0
        todayCount = 0
        saveTodayStats()
        recentEvents.removeAll()
        logger.info("🔄 Daily stats reset")
    }
}

extension MerchantAssistant: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in
            if let startTime = latencyStart {
                let latency = Int(round((CACurrentMediaTime() - startTime) * 1000))
                lastLatencyMs = latency
                logger.info("⚡ TTFS: \(latency)ms")
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = false
            logger.debug("✅ Speech completed")
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = false
        }
    }
}
