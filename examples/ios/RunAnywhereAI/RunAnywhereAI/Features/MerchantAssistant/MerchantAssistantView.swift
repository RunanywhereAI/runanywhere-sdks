//
//  MerchantAssistantView.swift
//  RunAnywhereAI
//
//  Merchant Assistant UI for payment confirmations demo
//

import SwiftUI
import AVFoundation

struct MerchantAssistantView: View {
    @StateObject private var assistant = MerchantAssistant()
    @State private var amount = "150"
    @State private var payerName = "Rahul"
    @State private var method = "UPI"
    @State private var selectedLanguage = "hi-IN"
    @State private var showingRecentEvents = false
    @State private var animatePayment = false

    let paymentMethods = ["UPI", "Card", "Wallet", "NetBanking", "Cash"]

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection

                    statsCard

                    paymentInputSection

                    languageSelector

                    simulateButton

                    if let latency = assistant.lastLatencyMs {
                        latencyBadge(latency)
                    }

                    if assistant.isSpeaking, let text = assistant.lastSpokenText {
                        speakingIndicator(text: text)
                    }

                    recentEventsSection
                }
                .padding()
            }
            .navigationTitle("Merchant Assistant")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(action: { showingRecentEvents.toggle() }) {
                            Label("Recent Events", systemImage: "clock")
                        }

                        Button(action: { testOfflineMode() }) {
                            Label("Test Offline Mode", systemImage: "airplane")
                        }

                        Button(role: .destructive, action: { assistant.resetDailyStats() }) {
                            Label("Reset Daily Stats", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "indianrupeesign.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)
                .symbolEffect(.pulse, value: animatePayment)

            Text("Paytm-Style Payment Confirmation")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Instant, offline, multi-lingual voice confirmations")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical)
    }

    private var statsCard: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today's Total")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("₹\(formatAmount(assistant.todayTotal))")
                        .font(.title2)
                        .fontWeight(.bold)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Payments")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(assistant.todayCount)")
                        .font(.title2)
                        .fontWeight(.bold)
                }
            }

            if assistant.todayCount > 0 {
                HStack {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .foregroundColor(.green)
                    Text("Avg: ₹\(assistant.todayTotal / max(assistant.todayCount, 1))")
                        .font(.caption)
                    Spacer()
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private var paymentInputSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Payment Details")
                .font(.headline)

            VStack(spacing: 12) {
                HStack {
                    Label("Amount", systemImage: "indianrupeesign")
                        .frame(width: 100, alignment: .leading)

                    TextField("150", text: $amount)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    Label("Name", systemImage: "person")
                        .frame(width: 100, alignment: .leading)

                    TextField("Rahul", text: $payerName)
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    Label("Method", systemImage: "creditcard")
                        .frame(width: 100, alignment: .leading)

                    Picker("Method", selection: $method) {
                        ForEach(paymentMethods, id: \.self) { method in
                            Text(method).tag(method)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private var languageSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select Language")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(assistant.availableLanguages, id: \.1) { name, code in
                        LanguageChip(
                            name: name,
                            code: code,
                            isSelected: selectedLanguage == code
                        ) {
                            selectedLanguage = code
                        }
                    }
                }
            }
        }
    }

    private var simulateButton: some View {
        Button(action: simulatePayment) {
            HStack {
                Image(systemName: "play.circle.fill")
                Text("Simulate Payment")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.green)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    private func latencyBadge(_ latency: Int) -> some View {
        HStack {
            Image(systemName: "speedometer")
                .foregroundColor(.orange)
            Text("TTFS: \(latency)ms")
                .font(.caption)
                .fontWeight(.medium)

            if latency < 100 {
                Text("FAST!")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.green)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(20)
    }

    private func speakingIndicator(text: String) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.green)
                        .frame(width: 3, height: 20)
                        .scaleEffect(y: assistant.isSpeaking ? [0.5, 1.0, 0.7][index] : 0.3)
                        .animation(
                            assistant.isSpeaking ?
                                Animation.easeInOut(duration: 0.3)
                                    .repeatForever()
                                    .delay(Double(index) * 0.1) :
                                .default,
                            value: assistant.isSpeaking
                        )
                }
            }

            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private var recentEventsSection: some View {
        Group {
            if !assistant.recentEvents.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Recent Events")
                            .font(.headline)
                        Spacer()
                        Text("\(assistant.recentEvents.count)")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color(.tertiarySystemBackground))
                            .cornerRadius(8)
                    }

                    ForEach(assistant.recentEvents.prefix(5), id: \.id) { event in
                        RecentEventRow(event: event)
                    }
                }
            }
        }
    }

    private func simulatePayment() {
        guard let amountInt = Int(amount), !payerName.isEmpty else { return }

        let event = PaymentEvent(
            amount: amountInt,
            method: method,
            name: payerName,
            lang: selectedLanguage
        )

        withAnimation(.spring()) {
            animatePayment.toggle()
        }

        assistant.processPaymentEvent(event)

        #if os(iOS)
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        #endif
    }

    private func testOfflineMode() {
        #if os(iOS)
        let alert = UIAlertController(
            title: "Test Offline Mode",
            message: "1. Turn on Airplane Mode\n2. Tap 'Simulate Payment'\n3. Voice still works instantly!",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Got it", style: .default))

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController?.present(alert, animated: true)
        }
        #endif
    }

    private func formatAmount(_ amount: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_IN")
        return formatter.string(from: NSNumber(value: amount)) ?? String(amount)
    }
}

struct LanguageChip: View {
    let name: String
    let code: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(languageEmoji)
                    .font(.title2)
                Text(name)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(isSelected ? Color.blue : Color(.secondarySystemBackground))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    private var languageEmoji: String {
        switch code {
        case "hi-IN": return "🇮🇳"
        case "ta-IN": return "தமிழ்"
        case "bn-IN": return "বাংলা"
        case "te-IN": return "తెలుగు"
        case "mr-IN": return "मराठी"
        case "gu-IN": return "ગુજરાતી"
        case "kn-IN": return "ಕನ್ನಡ"
        case "ml-IN": return "മലയാളം"
        case "pa-IN": return "ਪੰਜਾਬੀ"
        default: return "🇬🇧"
        }
    }
}

struct RecentEventRow: View {
    let event: PaymentEvent

    var body: some View {
        HStack {
            Image(systemName: iconForMethod(event.method))
                .foregroundColor(.green)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text("₹\(event.amount) from \(event.name)")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("\(event.method) • \(timeAgo(event.timestamp))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(8)
    }

    private func iconForMethod(_ method: String) -> String {
        switch method {
        case "UPI": return "qrcode"
        case "Card": return "creditcard"
        case "Wallet": return "wallet.pass"
        case "NetBanking": return "building.columns"
        case "Cash": return "indianrupeesign"
        default: return "banknote"
        }
    }

    private func timeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            return "\(Int(interval / 60))m ago"
        } else {
            return "\(Int(interval / 3600))h ago"
        }
    }
}

#Preview {
    MerchantAssistantView()
}
