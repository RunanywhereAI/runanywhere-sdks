//
//  MemoryMonitorView.swift
//  RunAnywhereAI
//

import SwiftUI
import Charts

struct MemoryMonitorView: View {
    @StateObject private var memoryManager = MemoryManager.shared
    @State private var memoryHistory: [MemoryDataPoint] = []
    @State private var timer: Timer?
    
    var body: some View {
        NavigationView {
            List {
                // Current Memory Stats
                Section("Current Memory Usage") {
                    VStack(alignment: .leading, spacing: 12) {
                        // Memory Pressure Indicator
                        HStack {
                            Circle()
                                .fill(pressureColor)
                                .frame(width: 12, height: 12)
                            Text(memoryManager.memoryPressure.description)
                                .font(.headline)
                            Spacer()
                        }
                        
                        // Memory Bar
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(height: 30)
                                
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(pressureGradient)
                                    .frame(
                                        width: geometry.size.width *
                                               (Double(memoryManager.usedMemory) / Double(memoryManager.totalMemory)),
                                        height: 30
                                    )
                                
                                Text("\(Int(memoryStats.usedPercentage))%")
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                            }
                        }
                        .frame(height: 30)
                        
                        // Memory Details
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Total:")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(memoryManager.formatBytes(memoryManager.totalMemory))
                                    .fontWeight(.medium)
                            }
                            
                            HStack {
                                Text("Used:")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(memoryManager.formatBytes(memoryManager.usedMemory))
                                    .fontWeight(.medium)
                                    .foregroundColor(pressureColor)
                            }
                            
                            HStack {
                                Text("Available:")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(memoryManager.formatBytes(memoryManager.availableMemory))
                                    .fontWeight(.medium)
                                    .foregroundColor(.green)
                            }
                        }
                        .font(.callout)
                    }
                    .padding(.vertical, 8)
                }
                
                // Memory History Chart
                if #available(iOS 16.0, *) {
                    Section("Memory Usage History") {
                        Chart(memoryHistory) { dataPoint in
                            LineMark(
                                x: .value("Time", dataPoint.timestamp),
                                y: .value("Used %", dataPoint.usedPercentage)
                            )
                            .foregroundStyle(Color.blue)
                            .interpolationMethod(.catmullRom)
                            
                            AreaMark(
                                x: .value("Time", dataPoint.timestamp),
                                y: .value("Used %", dataPoint.usedPercentage)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.blue.opacity(0.3), Color.blue.opacity(0.1)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        }
                        .frame(height: 200)
                        .chartYScale(domain: 0...100)
                        .chartXAxis {
                            AxisMarks(preset: .automatic) { _ in
                                AxisValueLabel(format: .dateTime.hour().minute())
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading) { value in
                                AxisValueLabel {
                                    if let percent = value.as(Double.self) {
                                        Text("\(Int(percent))%")
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Memory Tips
                Section("Memory Management Tips") {
                    Label("Close unused apps to free memory", systemImage: "xmark.app")
                    Label("Use smaller quantized models", systemImage: "square.compress")
                    Label("Reduce context length for lower memory", systemImage: "text.alignleft")
                    Label("Restart device if memory issues persist", systemImage: "arrow.clockwise")
                }
                .font(.callout)
            }
            .navigationTitle("Memory Monitor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Clear Cache") {
                        clearCache()
                    }
                }
            }
        }
        .onAppear {
            startMonitoring()
        }
        .onDisappear {
            stopMonitoring()
        }
    }
    
    // MARK: - Computed Properties
    
    private var memoryStats: MemoryStats {
        memoryManager.getMemoryStats()
    }
    
    private var pressureColor: Color {
        switch memoryManager.memoryPressure {
        case .normal:
            return .green
        case .warning:
            return .orange
        case .critical:
            return .red
        }
    }
    
    private var pressureGradient: LinearGradient {
        let colors: [Color] = switch memoryManager.memoryPressure {
        case .normal:
            [.green, .green.opacity(0.8)]
        case .warning:
            [.orange, .orange.opacity(0.8)]
        case .critical:
            [.red, .red.opacity(0.8)]
        }
        
        return LinearGradient(
            colors: colors,
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    
    // MARK: - Methods
    
    private func startMonitoring() {
        // Add initial data point
        addMemoryDataPoint()
        
        // Start timer for updates
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            addMemoryDataPoint()
        }
    }
    
    private func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    private func addMemoryDataPoint() {
        let stats = memoryStats
        let dataPoint = MemoryDataPoint(
            timestamp: Date(),
            usedPercentage: stats.usedPercentage,
            pressure: stats.pressure
        )
        
        memoryHistory.append(dataPoint)
        
        // Keep only last 50 data points (about 4 minutes of data)
        if memoryHistory.count > 50 {
            memoryHistory.removeFirst()
        }
    }
    
    private func clearCache() {
        // Clear URL cache
        URLCache.shared.removeAllCachedResponses()
        
        // Clear image cache if any
        if let imageCache = URLCache.shared as? URLCache {
            imageCache.removeAllCachedResponses()
        }
        
        // Force memory cleanup
        autoreleasepool {
            // This helps release autoreleased objects
        }
        
        // Show confirmation
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            let alert = UIAlertController(
                title: "Cache Cleared",
                message: "Application caches have been cleared.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            window.rootViewController?.present(alert, animated: true)
        }
    }
}

// MARK: - Data Model

struct MemoryDataPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let usedPercentage: Double
    let pressure: MemoryManager.MemoryPressureLevel
}

// MARK: - Preview

struct MemoryMonitorView_Previews: PreviewProvider {
    static var previews: some View {
        MemoryMonitorView()
    }
}
