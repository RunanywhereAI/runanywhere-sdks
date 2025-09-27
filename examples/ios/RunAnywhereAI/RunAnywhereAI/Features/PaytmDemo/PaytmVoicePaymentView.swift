//
//  PaytmVoicePaymentView.swift
//  RunAnywhereAI
//
//  Created for VSS Demo on 7/22/25.
//  Conversational Voice Payment Interface with Paytm Branding
//

import SwiftUI
import RunAnywhereSDK
import AVFoundation

struct PaytmVoicePaymentView: View {
    @StateObject private var voiceModel = PaytmVoiceAssistantViewModel()
    @State private var pulseAnimation = false

    var body: some View {
        ZStack {
            // Paytm gradient background
            LinearGradient(
                gradient: Gradient(colors: [
                    PaytmTheme.lightBlue.opacity(0.1),
                    Color.white
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Paytm Header with dynamic balance
                PaytmHeaderBar(balance: voiceModel.currentBalance)

                // Conversation Area
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            // Welcome message
                            if voiceModel.currentTranscript.isEmpty &&
                               voiceModel.assistantResponse.isEmpty &&
                               voiceModel.transactionHistory.isEmpty {
                                WelcomeCard()
                                    .padding(.horizontal, 20)
                                    .padding(.top, 20)
                            }

                            // Transaction History
                            if !voiceModel.transactionHistory.isEmpty {
                                TransactionHistorySection(transactions: voiceModel.transactionHistory)
                                    .padding(.horizontal, 20)
                                    .padding(.top, 20)
                            }

                            // User message
                            if !voiceModel.currentTranscript.isEmpty {
                                PaytmChatBubble(
                                    message: voiceModel.currentTranscript,
                                    isUser: true
                                )
                                .id("user")
                                .padding(.horizontal, 20)
                            }

                            // Assistant response
                            if !voiceModel.assistantResponse.isEmpty {
                                PaytmChatBubble(
                                    message: voiceModel.assistantResponse,
                                    isUser: false
                                )
                                .id("assistant")
                                .padding(.horizontal, 20)
                            }

                            // Processing indicator
                            if voiceModel.isProcessing && voiceModel.assistantResponse.isEmpty {
                                ProcessingIndicator()
                                    .padding(.horizontal, 20)
                            }
                        }
                        .padding(.vertical, 20)
                    }
                    .onChange(of: voiceModel.assistantResponse) { _ in
                        withAnimation {
                            proxy.scrollTo("assistant", anchor: .bottom)
                        }
                    }
                }

                Spacer()

                // Voice Control Area - Simplified
                VStack(spacing: 16) {
                    // Status text
                    Text(statusText)
                        .font(PaytmTheme.captionFont())
                        .foregroundColor(PaytmTheme.grayText)

                    // Mic Button
                    Button(action: {
                        Task {
                            if voiceModel.sessionState == .listening ||
                               voiceModel.sessionState == .speaking ||
                               voiceModel.sessionState == .processing ||
                               voiceModel.sessionState == .connecting {
                                await voiceModel.stopConversation()
                            } else {
                                await voiceModel.startConversation()
                            }
                        }
                    }) {
                        ZStack {
                            // Outer pulsing circle
                            if voiceModel.isSpeechDetected {
                                Circle()
                                    .stroke(PaytmTheme.primaryBlue.opacity(0.3), lineWidth: 2)
                                    .scaleEffect(pulseAnimation ? 1.5 : 1.0)
                                    .opacity(pulseAnimation ? 0 : 1)
                                    .animation(
                                        .easeOut(duration: 1.5).repeatForever(autoreverses: false),
                                        value: pulseAnimation
                                    )
                            }

                            // Main button
                            Circle()
                                .fill(micButtonGradient)
                                .frame(width: 80, height: 80)
                                .shadow(color: PaytmTheme.primaryBlue.opacity(0.3), radius: 10)

                            // Icon or spinner
                            if voiceModel.sessionState == .connecting ||
                               (voiceModel.isProcessing && !voiceModel.isListening) {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(1.2)
                            } else {
                                Image(systemName: micIcon)
                                    .font(.system(size: 32))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            Task {
                await voiceModel.initialize()
            }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                pulseAnimation = true
            }
        }
    }

    private var statusText: String {
        switch voiceModel.sessionState {
        case .listening:
            return "Listening... Say 'Send money to...' or ask a question"
        case .processing:
            return "Processing your request..."
        case .speaking:
            return "Assistant is responding..."
        case .connecting:
            return "Connecting..."
        default:
            return "Tap to speak"
        }
    }

    private var micIcon: String {
        switch voiceModel.sessionState {
        case .listening: return "mic.fill"
        case .speaking: return "speaker.wave.2.fill"
        case .processing: return "waveform"
        default: return "mic"
        }
    }

    private var micButtonGradient: LinearGradient {
        let colors: [Color] = switch voiceModel.sessionState {
        case .listening: [PaytmTheme.secondaryBlue, PaytmTheme.primaryBlue]
        case .speaking: [PaytmTheme.successGreen, PaytmTheme.successGreen.opacity(0.8)]
        case .processing: [PaytmTheme.primaryBlue, PaytmTheme.secondaryBlue]
        default: [PaytmTheme.primaryBlue, PaytmTheme.primaryBlue.opacity(0.9)]
        }

        return LinearGradient(
            gradient: Gradient(colors: colors),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct PaytmHeaderBar: View {
    let balance: Double

    var body: some View {
        HStack {
            // Paytm Logo
            HStack(spacing: 0) {
                Text("pay")
                    .font(PaytmTheme.headlineFont(24))
                    .foregroundColor(PaytmTheme.primaryBlue)
                Text("tm")
                    .font(PaytmTheme.headlineFont(24))
                    .foregroundColor(PaytmTheme.secondaryBlue)
            }

            Text("Voice Pay")
                .font(PaytmTheme.bodyFont())
                .foregroundColor(PaytmTheme.grayText)

            Spacer()

            // Balance indicator - Dynamic
            VStack(alignment: .trailing, spacing: 2) {
                Text("Balance")
                    .font(PaytmTheme.captionFont(10))
                    .foregroundColor(PaytmTheme.grayText)
                Text("₹\(Int(balance))")
                    .font(PaytmTheme.headlineFont(16))
                    .foregroundColor(PaytmTheme.primaryBlue)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.white)
        .shadow(color: Color.black.opacity(0.05), radius: 2, y: 2)
    }
}

struct WelcomeCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "hand.wave.fill")
                    .font(.title2)
                    .foregroundColor(PaytmTheme.primaryBlue)
                Text("Welcome to Voice Pay!")
                    .font(PaytmTheme.headlineFont(18))
                    .foregroundColor(PaytmTheme.darkText)
            }

            Text("Try saying commands like:")
                .font(PaytmTheme.bodyFont())
                .foregroundColor(PaytmTheme.grayText)

            VStack(alignment: .leading, spacing: 8) {
                CommandExample(icon: "indianrupeesign.circle", text: "Send ₹500 to Vijay")
                CommandExample(icon: "globe", text: "पांच सौ रुपये विजय को भेजो")
                CommandExample(icon: "chart.line.uptrend.xyaxis", text: "What's my balance?")
                CommandExample(icon: "clock", text: "Show recent transactions")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(PaytmTheme.lightBlue.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(PaytmTheme.primaryBlue.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

struct TransactionHistorySection: View {
    let transactions: [PaytmVoiceAssistantViewModel.Transaction]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Transactions")
                .font(PaytmTheme.headlineFont(14))
                .foregroundColor(PaytmTheme.darkText)

            ForEach(transactions.prefix(3)) { transaction in
                HStack {
                    Image(systemName: transaction.type == .sent ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                        .foregroundColor(transaction.type == .sent ? PaytmTheme.secondaryBlue : PaytmTheme.successGreen)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(transaction.type == .sent ? "Sent to" : "Received from") \(transaction.recipient)")
                            .font(PaytmTheme.bodyFont(13))
                            .foregroundColor(PaytmTheme.darkText)
                        Text(transaction.timestamp, style: .time)
                            .font(PaytmTheme.captionFont(11))
                            .foregroundColor(PaytmTheme.grayText)
                    }

                    Spacer()

                    Text("₹\(Int(transaction.amount))")
                        .font(PaytmTheme.headlineFont(14))
                        .foregroundColor(transaction.type == .sent ? PaytmTheme.secondaryBlue : PaytmTheme.successGreen)
                }
                .padding(.vertical, 6)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 3)
        )
    }
}

struct CommandExample: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(PaytmTheme.secondaryBlue)
                .frame(width: 20)
            Text(text)
                .font(PaytmTheme.bodyFont(14))
                .foregroundColor(PaytmTheme.darkText)
        }
    }
}

struct PaytmChatBubble: View {
    let message: String
    let isUser: Bool

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(isUser ? "You" : "Assistant")
                    .font(PaytmTheme.captionFont(11))
                    .foregroundColor(PaytmTheme.grayText)

                Text(message)
                    .font(PaytmTheme.bodyFont())
                    .foregroundColor(isUser ? .white : PaytmTheme.darkText)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isUser ? AnyShapeStyle(PaytmTheme.primaryGradient) : AnyShapeStyle(Color.white))
                            .shadow(color: Color.black.opacity(0.05), radius: 3, y: 2)
                    )
            }

            if !isUser { Spacer(minLength: 60) }
        }
    }
}

struct ProcessingIndicator: View {
    @State private var dotScale: [CGFloat] = [1, 1, 1]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(PaytmTheme.primaryBlue)
                    .frame(width: 8, height: 8)
                    .scaleEffect(dotScale[index])
            }
        }
        .onAppear {
            animateDots()
        }
    }

    func animateDots() {
        for index in 0..<3 {
            withAnimation(.easeInOut(duration: 0.6).repeatForever().delay(Double(index) * 0.2)) {
                dotScale[index] = 1.5
            }
        }
    }
}

#Preview {
    PaytmVoicePaymentView()
}
