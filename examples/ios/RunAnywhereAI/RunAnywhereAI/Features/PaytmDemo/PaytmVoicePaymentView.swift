//
//  PaytmVoicePaymentView.swift
//  RunAnywhereAI
//
//  Created for VSS Demo on 7/22/25.
//

import SwiftUI
import RunAnywhere

struct PaytmVoicePaymentView: View {
    @StateObject private var viewModel = PaytmVoicePaymentViewModel()
    @State private var isListening = false
    @State private var showingSuccess = false
    @State private var pulseAnimation = false

    var body: some View {
        ZStack {
            // Background gradient
            PaytmTheme.primaryGradient
                .ignoresSafeArea()

            VStack(spacing: 20) {
                // Header
                PaytmHeaderView()

                // Balance Card
                PaytmBalanceCard(balance: "₹24,567")
                    .padding(.horizontal)

                // Voice Command Section
                VStack(spacing: 16) {
                    Text("Say a command")
                        .font(PaytmTheme.captionFont())
                        .foregroundColor(.white.opacity(0.8))

                    // Voice Button
                    Button(action: {
                        isListening.toggle()
                        if isListening {
                            viewModel.startListening()
                        } else {
                            viewModel.stopListening()
                        }
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 120, height: 120)
                                .shadow(color: PaytmTheme.primaryBlue.opacity(0.3), radius: 20)
                                .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                                .opacity(pulseAnimation ? 0.7 : 1.0)

                            Circle()
                                .fill(isListening ? PaytmTheme.secondaryBlue : PaytmTheme.primaryBlue)
                                .frame(width: 100, height: 100)

                            Image(systemName: isListening ? "mic.fill" : "mic")
                                .font(.system(size: 40))
                                .foregroundColor(.white)
                        }
                    }
                    .animation(.easeInOut(duration: 0.3), value: isListening)

                    if !viewModel.transcribedText.isEmpty {
                        Text(viewModel.transcribedText)
                            .font(PaytmTheme.bodyFont(18))
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.white.opacity(0.2))
                            .cornerRadius(12)
                            .padding(.horizontal)
                    }

                    // Example commands
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Try saying:")
                            .font(PaytmTheme.captionFont(12))
                            .foregroundColor(.white.opacity(0.6))

                        ForEach(viewModel.exampleCommands, id: \.self) { command in
                            HStack {
                                Image(systemName: "mic.circle.fill")
                                    .foregroundColor(PaytmTheme.secondaryBlue)
                                    .font(.system(size: 16))
                                Text(command)
                                    .font(PaytmTheme.bodyFont(14))
                                    .foregroundColor(.white.opacity(0.9))
                            }
                        }
                    }
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }

                Spacer()

                // Performance Metrics
                PaytmMetricsView(
                    latency: viewModel.latency,
                    cost: viewModel.cost,
                    isOffline: viewModel.isOffline
                )
                .padding()
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulseAnimation = true
            }
        }
        .sheet(isPresented: $showingSuccess) {
            PaytmSuccessView(
                amount: viewModel.lastTransactionAmount,
                recipient: viewModel.lastRecipient
            )
        }
    }
}

struct PaytmHeaderView: View {
    var body: some View {
        HStack {
            // Paytm Logo
            HStack(spacing: 0) {
                Text("pay")
                    .font(PaytmTheme.headlineFont(28))
                    .foregroundColor(PaytmTheme.primaryBlue)
                Text("tm")
                    .font(PaytmTheme.headlineFont(28))
                    .foregroundColor(PaytmTheme.secondaryBlue)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.white)
            .cornerRadius(8)

            Spacer()

            // QR Scanner Icon
            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 24))
                .foregroundColor(.white)
                .padding()
        }
        .padding(.horizontal)
    }
}

struct PaytmBalanceCard: View {
    let balance: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Wallet Balance")
                .font(PaytmTheme.captionFont())
                .foregroundColor(PaytmTheme.grayText)

            Text(balance)
                .font(PaytmTheme.headlineFont(32))
                .foregroundColor(PaytmTheme.primaryBlue)

            HStack {
                Label("UPI ID: yourname@paytm", systemImage: "at")
                    .font(PaytmTheme.captionFont(12))
                    .foregroundColor(PaytmTheme.grayText)

                Spacer()

                Image(systemName: "indianrupeesign.circle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(PaytmTheme.secondaryBlue)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .paytmCard()
    }
}

struct PaytmMetricsView: View {
    let latency: Int
    let cost: Double
    let isOffline: Bool

    var body: some View {
        HStack(spacing: 16) {
            // Latency
            MetricCard(
                icon: "speedometer",
                title: "Latency",
                value: "\(latency)ms",
                subtitle: "vs Cloud: 450ms",
                color: PaytmTheme.successGreen
            )

            // Cost
            MetricCard(
                icon: "indianrupeesign.circle",
                title: "Cost",
                value: "₹\(String(format: "%.3f", cost))",
                subtitle: "vs Cloud: ₹0.15",
                color: PaytmTheme.secondaryBlue
            )

            // Status
            MetricCard(
                icon: isOffline ? "wifi.slash" : "wifi",
                title: "Mode",
                value: isOffline ? "Offline" : "Online",
                subtitle: "On-device AI",
                color: isOffline ? PaytmTheme.warningOrange : PaytmTheme.successGreen
            )
        }
    }
}

struct MetricCard: View {
    let icon: String
    let title: String
    let value: String
    let subtitle: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)

            Text(title)
                .font(PaytmTheme.captionFont(10))
                .foregroundColor(PaytmTheme.grayText)

            Text(value)
                .font(PaytmTheme.headlineFont(16))
                .foregroundColor(PaytmTheme.darkText)

            Text(subtitle)
                .font(PaytmTheme.captionFont(9))
                .foregroundColor(PaytmTheme.grayText.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.white)
        .cornerRadius(12)
    }
}

struct PaytmSuccessView: View {
    let amount: String
    let recipient: String
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(PaytmTheme.successGreen)

            Text("Payment Successful!")
                .font(PaytmTheme.headlineFont())
                .foregroundColor(PaytmTheme.darkText)

            VStack(spacing: 8) {
                Text(amount)
                    .font(PaytmTheme.headlineFont(36))
                    .foregroundColor(PaytmTheme.primaryBlue)

                Text("sent to \(recipient)")
                    .font(PaytmTheme.bodyFont())
                    .foregroundColor(PaytmTheme.grayText)
            }

            Button(action: { dismiss() }) {
                Text("Done")
                    .font(PaytmTheme.bodyFont(18))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(PaytmTheme.primaryGradient)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
        }
        .padding()
        .presentationDetents([.height(400)])
    }
}

class PaytmVoicePaymentViewModel: ObservableObject {
    @Published var transcribedText = ""
    @Published var isProcessing = false
    @Published var latency = 87
    @Published var cost = 0.002
    @Published var isOffline = true
    @Published var lastTransactionAmount = ""
    @Published var lastRecipient = ""

    let exampleCommands = [
        "Send ₹500 to Raj",
        "पांच सौ रुपये राज को भेजो",
        "Pay ₹200 for tea"
    ]

    func startListening() {
        // Simulate voice recognition
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.transcribedText = "Send ₹500 to Raj"
            self.processCommand()
        }
    }

    func stopListening() {
        // Stop voice recognition
    }

    private func processCommand() {
        isProcessing = true

        // Simulate processing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.lastTransactionAmount = "₹500"
            self.lastRecipient = "Raj"
            self.isProcessing = false
        }
    }
}

#Preview {
    PaytmVoicePaymentView()
}
