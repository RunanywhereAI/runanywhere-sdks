//
//  PaytmMerchantDashboard.swift
//  RunAnywhereAI
//
//  Created for VSS Demo on 7/22/25.
//

import SwiftUI
import Charts

struct PaytmMerchantDashboard: View {
    @StateObject private var viewModel = MerchantDashboardViewModel()
    @State private var showingVoiceQuery = false
    @State private var selectedTimeRange = "Today"

    var body: some View {
        ZStack {
            // Background
            Color(red: 245/255, green: 247/255, blue: 250/255)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    MerchantHeaderView()

                    // Sales Summary Card
                    SalesSummaryCard(
                        todaySales: viewModel.todaySales,
                        yesterdaySales: viewModel.yesterdaySales,
                        growthPercentage: viewModel.growthPercentage
                    )
                    .padding(.horizontal)

                    // AI Voice Query Button
                    Button(action: {
                        showingVoiceQuery = true
                        viewModel.startVoiceQuery()
                    }) {
                        HStack {
                            Image(systemName: "mic.circle.fill")
                                .font(.system(size: 24))

                            VStack(alignment: .leading) {
                                Text("Ask AI Assistant")
                                    .font(PaytmTheme.bodyFont(16))
                                Text("Voice-powered business insights")
                                    .font(PaytmTheme.captionFont(12))
                                    .opacity(0.7)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 14))
                        }
                        .foregroundColor(.white)
                        .padding()
                        .background(PaytmTheme.primaryGradient)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)

                    // Transaction Analytics
                    TransactionAnalyticsCard(data: viewModel.transactionData)
                        .padding(.horizontal)

                    // Top Products
                    TopProductsCard(products: viewModel.topProducts)
                        .padding(.horizontal)

                    // Customer Insights
                    CustomerInsightsCard(
                        totalCustomers: viewModel.totalCustomers,
                        repeatRate: viewModel.repeatRate
                    )
                    .padding(.horizontal)

                    // Performance Metrics
                    HStack(spacing: 16) {
                        MetricCard(
                            icon: "speedometer",
                            title: "Latency",
                            value: "92ms",
                            subtitle: "On-device",
                            color: PaytmTheme.successGreen
                        )
                        MetricCard(
                            icon: "indianrupeesign",
                            title: "Cost",
                            value: "₹0.003",
                            subtitle: "Per query",
                            color: PaytmTheme.secondaryBlue
                        )
                        MetricCard(
                            icon: "wifi.slash",
                            title: "Mode",
                            value: "Offline",
                            subtitle: "Available",
                            color: PaytmTheme.warningOrange
                        )
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
        }
        .sheet(isPresented: $showingVoiceQuery) {
            VoiceQuerySheet(viewModel: viewModel)
        }
    }
}

struct MerchantHeaderView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Merchant Dashboard")
                        .font(PaytmTheme.headlineFont())
                        .foregroundColor(PaytmTheme.darkText)

                    Text("Raj's Tea Shop • Connaught Place")
                        .font(PaytmTheme.captionFont())
                        .foregroundColor(PaytmTheme.grayText)
                }

                Spacer()

                // Soundbox Icon
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 24))
                    .foregroundColor(PaytmTheme.primaryBlue)
                    .padding(12)
                    .background(PaytmTheme.lightBlue)
                    .clipShape(Circle())
            }

            // Quick Stats
            HStack(spacing: 16) {
                QuickStatBadge(icon: "clock", value: "9:30 AM", label: "First Sale")
                QuickStatBadge(icon: "person.2", value: "87", label: "Customers")
                QuickStatBadge(icon: "chart.line.uptrend.xyaxis", value: "+23%", label: "Growth")
            }
        }
        .padding()
        .background(Color.white)
    }
}

struct QuickStatBadge: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(PaytmTheme.secondaryBlue)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(PaytmTheme.headlineFont(14))
                    .foregroundColor(PaytmTheme.darkText)
                Text(label)
                    .font(PaytmTheme.captionFont(10))
                    .foregroundColor(PaytmTheme.grayText)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(PaytmTheme.lightBlue.opacity(0.3))
        .cornerRadius(8)
    }
}

struct SalesSummaryCard: View {
    let todaySales: Double
    let yesterdaySales: Double
    let growthPercentage: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sales Summary")
                .font(PaytmTheme.headlineFont(18))
                .foregroundColor(PaytmTheme.darkText)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Today")
                        .font(PaytmTheme.captionFont())
                        .foregroundColor(PaytmTheme.grayText)

                    Text("₹\(Int(todaySales))")
                        .font(PaytmTheme.headlineFont(28))
                        .foregroundColor(PaytmTheme.primaryBlue)

                    HStack {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12))
                        Text("\(Int(growthPercentage))% vs yesterday")
                            .font(PaytmTheme.captionFont(12))
                    }
                    .foregroundColor(PaytmTheme.successGreen)
                }

                Spacer()

                // Mini chart
                MiniSalesChart()
            }
        }
        .padding()
        .paytmCard()
    }
}

struct MiniSalesChart: View {
    var body: some View {
        Chart {
            ForEach(0..<7, id: \.self) { index in
                LineMark(
                    x: .value("Day", index),
                    y: .value("Sales", Double.random(in: 8000...15000))
                )
                .foregroundStyle(PaytmTheme.secondaryBlue)

                AreaMark(
                    x: .value("Day", index),
                    y: .value("Sales", Double.random(in: 8000...15000))
                )
                .foregroundStyle(PaytmTheme.secondaryBlue.opacity(0.1))
            }
        }
        .frame(width: 150, height: 80)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }
}

struct TransactionAnalyticsCard: View {
    let data: [(String, Double)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hourly Transactions")
                .font(PaytmTheme.headlineFont(16))
                .foregroundColor(PaytmTheme.darkText)

            Chart(data, id: \.0) { item in
                BarMark(
                    x: .value("Hour", item.0),
                    y: .value("Amount", item.1)
                )
                .foregroundStyle(PaytmTheme.primaryGradient)
                .cornerRadius(4)
            }
            .frame(height: 150)
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisValueLabel()
                        .font(PaytmTheme.captionFont(10))
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .font(PaytmTheme.captionFont(10))
                }
            }
        }
        .padding()
        .paytmCard()
    }
}

struct TopProductsCard: View {
    let products: [(String, Int, Double)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Selling Items")
                .font(PaytmTheme.headlineFont(16))
                .foregroundColor(PaytmTheme.darkText)

            ForEach(products, id: \.0) { product in
                HStack {
                    Circle()
                        .fill(PaytmTheme.secondaryBlue.opacity(0.2))
                        .frame(width: 8, height: 8)

                    Text(product.0)
                        .font(PaytmTheme.bodyFont())
                        .foregroundColor(PaytmTheme.darkText)

                    Spacer()

                    VStack(alignment: .trailing) {
                        Text("\(product.1) sold")
                            .font(PaytmTheme.captionFont(12))
                            .foregroundColor(PaytmTheme.grayText)
                        Text("₹\(Int(product.2))")
                            .font(PaytmTheme.headlineFont(14))
                            .foregroundColor(PaytmTheme.primaryBlue)
                    }
                }

                if product.0 != products.last?.0 {
                    Divider()
                }
            }
        }
        .padding()
        .paytmCard()
    }
}

struct CustomerInsightsCard: View {
    let totalCustomers: Int
    let repeatRate: Double

    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "person.2.fill")
                        .foregroundColor(PaytmTheme.secondaryBlue)
                    Text("Customers")
                        .font(PaytmTheme.captionFont())
                        .foregroundColor(PaytmTheme.grayText)
                }

                Text("\(totalCustomers)")
                    .font(PaytmTheme.headlineFont(24))
                    .foregroundColor(PaytmTheme.darkText)
            }

            Divider()
                .frame(height: 40)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundColor(PaytmTheme.successGreen)
                    Text("Repeat Rate")
                        .font(PaytmTheme.captionFont())
                        .foregroundColor(PaytmTheme.grayText)
                }

                Text("\(Int(repeatRate))%")
                    .font(PaytmTheme.headlineFont(24))
                    .foregroundColor(PaytmTheme.darkText)
            }

            Spacer()
        }
        .padding()
        .paytmCard()
    }
}

struct VoiceQuerySheet: View {
    @ObservedObject var viewModel: MerchantDashboardViewModel
    @Environment(\.dismiss) var dismiss
    @State private var isListening = false

    var body: some View {
        VStack(spacing: 24) {
            Text("Ask About Your Business")
                .font(PaytmTheme.headlineFont())
                .foregroundColor(PaytmTheme.darkText)

            // Voice Animation
            ZStack {
                ForEach(0..<3) { index in
                    Circle()
                        .stroke(PaytmTheme.secondaryBlue.opacity(0.3 - Double(index) * 0.1), lineWidth: 2)
                        .frame(width: 100 + CGFloat(index * 30), height: 100 + CGFloat(index * 30))
                        .scaleEffect(isListening ? 1.1 : 1.0)
                        .animation(
                            .easeInOut(duration: 1.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.2),
                            value: isListening
                        )
                }

                Image(systemName: "mic.fill")
                    .font(.system(size: 40))
                    .foregroundColor(PaytmTheme.primaryBlue)
            }
            .onAppear { isListening = true }

            // Query Text
            if !viewModel.currentQuery.isEmpty {
                Text(viewModel.currentQuery)
                    .font(PaytmTheme.bodyFont(18))
                    .foregroundColor(PaytmTheme.darkText)
                    .padding()
                    .background(PaytmTheme.lightBlue.opacity(0.3))
                    .cornerRadius(12)
            }

            // Response
            if !viewModel.aiResponse.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "sparkle")
                            .foregroundColor(PaytmTheme.secondaryBlue)
                        Text("AI Insights")
                            .font(PaytmTheme.headlineFont(14))
                            .foregroundColor(PaytmTheme.darkText)
                    }

                    Text(viewModel.aiResponse)
                        .font(PaytmTheme.bodyFont())
                        .foregroundColor(PaytmTheme.grayText)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.white)
                .cornerRadius(12)
            }

            // Example Queries
            VStack(alignment: .leading, spacing: 8) {
                Text("Try asking:")
                    .font(PaytmTheme.captionFont())
                    .foregroundColor(PaytmTheme.grayText)

                ForEach(viewModel.exampleQueries, id: \.self) { query in
                    Text("• \(query)")
                        .font(PaytmTheme.bodyFont(14))
                        .foregroundColor(PaytmTheme.darkText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            Button(action: { dismiss() }) {
                Text("Done")
                    .font(PaytmTheme.bodyFont(18))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(PaytmTheme.primaryGradient)
                    .cornerRadius(12)
            }
        }
        .padding()
        .presentationDetents([.height(500)])
    }
}

class MerchantDashboardViewModel: ObservableObject {
    @Published var todaySales: Double = 12450
    @Published var yesterdaySales: Double = 10100
    @Published var growthPercentage: Double = 23
    @Published var totalCustomers = 87
    @Published var repeatRate: Double = 68

    @Published var currentQuery = ""
    @Published var aiResponse = ""

    let transactionData = [
        ("9AM", 1200.0),
        ("10AM", 2800.0),
        ("11AM", 3400.0),
        ("12PM", 4200.0),
        ("1PM", 3900.0),
        ("2PM", 2100.0),
        ("3PM", 1850.0)
    ]

    let topProducts = [
        ("Masala Tea", 145, 2900.0),
        ("Samosa", 89, 1780.0),
        ("Coffee", 67, 2010.0),
        ("Biscuits", 45, 450.0)
    ]

    let exampleQueries = [
        "What's my best selling item today?",
        "இன்றைய விற்பனை எவ்வளவு?",
        "Show peak hours analysis"
    ]

    func startVoiceQuery() {
        // Simulate voice query
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.currentQuery = "What's my best selling item today?"

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                self.aiResponse = "Your best selling item today is Masala Tea with 145 units sold, generating ₹2,900 in revenue. This is 18% higher than your daily average for this item."
            }
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

#Preview {
    PaytmMerchantDashboard()
}
