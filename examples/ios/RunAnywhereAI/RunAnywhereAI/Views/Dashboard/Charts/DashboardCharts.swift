//
//  DashboardCharts.swift
//  RunAnywhereAI
//
//  Created by Sanchit Monga on 7/27/25.
//

import SwiftUI
import Charts

// MARK: - Tokens Per Second Chart

@available(iOS 16.0, *)
struct TokensPerSecondChart: View {
    let data: [Double]
    
    var body: some View {
        Chart(Array(data.enumerated()), id: \.offset) { index, value in
            LineMark(
                x: .value("Time", index),
                y: .value("Tokens/Sec", value)
            )
            .foregroundStyle(.blue.gradient)
            .interpolationMethod(.catmullRom)
            
            AreaMark(
                x: .value("Time", index),
                y: .value("Tokens/Sec", value)
            )
            .foregroundStyle(.blue.opacity(0.1).gradient)
            .interpolationMethod(.catmullRom)
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartXAxis(.hidden)
    }
}

// MARK: - Memory Usage Chart

@available(iOS 16.0, *)
struct MemoryUsageChart: View {
    let data: [MemorySnapshot]
    
    var body: some View {
        Chart(data, id: \.timestamp) { snapshot in
            LineMark(
                x: .value("Time", snapshot.timestamp),
                y: .value("Memory", Double(snapshot.usedMemory) / 1_000_000_000) // Convert to GB
            )
            .foregroundStyle(.purple.gradient)
            .interpolationMethod(.catmullRom)
            
            AreaMark(
                x: .value("Time", snapshot.timestamp),
                y: .value("Memory", Double(snapshot.usedMemory) / 1_000_000_000)
            )
            .foregroundStyle(.purple.opacity(0.1).gradient)
            .interpolationMethod(.catmullRom)
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let doubleValue = value.as(Double.self) {
                        Text("\(String(format: "%.1f", doubleValue)) GB")
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date.formatted(date: .omitted, time: .shortened))
                    }
                }
            }
        }
    }
}

// MARK: - Framework Performance Chart

@available(iOS 16.0, *)
struct FrameworkPerformanceChart: View {
    let results: [BenchmarkSuiteResult]
    
    private var aggregatedData: [(framework: LLMFramework, speed: Double, memory: Double)] {
        let grouped = Dictionary(grouping: results) { $0.framework }
        
        return grouped.compactMap { framework, results in
            let avgSpeed = results.map { $0.avgTokensPerSecond }.reduce(0, +) / Double(results.count)
            let avgMemory = Double(results.map { $0.avgMemoryUsed }.reduce(0, +)) / Double(results.count) / 1_000_000_000
            return (framework, avgSpeed, avgMemory)
        }
        .sorted { $0.speed > $1.speed }
    }
    
    var body: some View {
        Chart(aggregatedData, id: \.framework) { data in
            BarMark(
                x: .value("Framework", data.framework.displayName),
                y: .value("Speed", data.speed)
            )
            .foregroundStyle(by: .value("Metric", "Tokens/Second"))
            .position(by: .value("Metric", "Tokens/Second"))
        }
        .chartForegroundStyleScale([
            "Tokens/Second": .blue
        ])
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let doubleValue = value.as(Double.self) {
                        Text("\(Int(doubleValue)) t/s")
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel(horizontalSpacing: 0) {
                    if let framework = value.as(String.self) {
                        Text(framework)
                            .font(.caption2)
                            .rotationEffect(.degrees(-45))
                            .offset(y: 10)
                    }
                }
            }
        }
    }
}

// MARK: - Legacy Charts (for iOS 15 and below)

struct LegacyLineChart: View {
    let data: [Double]
    let title: String
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background grid
                VStack(spacing: geometry.size.height / 4) {
                    ForEach(0..<5) { _ in
                        Rectangle()
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 1)
                    }
                }
                
                // Line chart
                if !data.isEmpty {
                    Path { path in
                        let maxValue = data.max() ?? 1
                        let xStep = geometry.size.width / CGFloat(data.count - 1)
                        
                        for (index, value) in data.enumerated() {
                            let x = CGFloat(index) * xStep
                            let y = geometry.size.height - (CGFloat(value / maxValue) * geometry.size.height)
                            
                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(Color.blue, lineWidth: 2)
                    
                    // Area fill
                    Path { path in
                        let maxValue = data.max() ?? 1
                        let xStep = geometry.size.width / CGFloat(data.count - 1)
                        
                        path.move(to: CGPoint(x: 0, y: geometry.size.height))
                        
                        for (index, value) in data.enumerated() {
                            let x = CGFloat(index) * xStep
                            let y = geometry.size.height - (CGFloat(value / maxValue) * geometry.size.height)
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                        
                        path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height))
                        path.closeSubpath()
                    }
                    .fill(Color.blue.opacity(0.1))
                }
                
                // Title
                VStack {
                    HStack {
                        Text(title)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    Spacer()
                }
                .padding(8)
            }
        }
    }
}

// MARK: - Gauge Charts

struct PerformanceGauge: View {
    let value: Double // 0.0 to 1.0
    let title: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 10)
                
                Circle()
                    .trim(from: 0, to: value)
                    .stroke(color.gradient, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(), value: value)
                
                VStack(spacing: 4) {
                    Text("\(Int(value * 100))%")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text(title)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 100, height: 100)
        }
    }
}

// MARK: - Sparkline Chart

struct SparklineChart: View {
    let data: [Double]
    let color: Color
    
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                guard !data.isEmpty else { return }
                
                let maxValue = data.max() ?? 1
                let minValue = data.min() ?? 0
                let range = maxValue - minValue
                let xStep = geometry.size.width / CGFloat(data.count - 1)
                
                for (index, value) in data.enumerated() {
                    let x = CGFloat(index) * xStep
                    let normalizedValue = range > 0 ? (value - minValue) / range : 0.5
                    let y = geometry.size.height - (normalizedValue * geometry.size.height * 0.8) - geometry.size.height * 0.1
                    
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(color, lineWidth: 2)
        }
    }
}

// MARK: - Comparison Bar Chart

struct ComparisonBarChart: View {
    let dataA: Double
    let dataB: Double
    let labelA: String
    let labelB: String
    let colorA: Color
    let colorB: Color
    
    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 12) {
                // Bar A
                HStack {
                    Text(labelA)
                        .font(.caption)
                        .frame(width: 80, alignment: .leading)
                    
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 20)
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(colorA.gradient)
                            .frame(width: barWidth(for: dataA, in: geometry.size.width - 120), height: 20)
                    }
                    
                    Text(String(format: "%.1f", dataA))
                        .font(.caption)
                        .fontWeight(.medium)
                        .frame(width: 40, alignment: .trailing)
                }
                
                // Bar B
                HStack {
                    Text(labelB)
                        .font(.caption)
                        .frame(width: 80, alignment: .leading)
                    
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 20)
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(colorB.gradient)
                            .frame(width: barWidth(for: dataB, in: geometry.size.width - 120), height: 20)
                    }
                    
                    Text(String(format: "%.1f", dataB))
                        .font(.caption)
                        .fontWeight(.medium)
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }
    }
    
    private func barWidth(for value: Double, in maxWidth: CGFloat) -> CGFloat {
        let maxValue = max(dataA, dataB, 1)
        return CGFloat(value / maxValue) * maxWidth
    }
}
