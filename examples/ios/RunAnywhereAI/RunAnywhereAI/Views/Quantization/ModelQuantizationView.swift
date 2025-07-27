import SwiftUI

struct ModelQuantizationView: View {
    @StateObject private var viewModel = ModelQuantizationViewModel()
    @State private var showFilePicker = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    headerSection
                    
                    if viewModel.selectedModel != nil {
                        modelInfoSection
                        quantizationOptionsSection
                        previewSection
                        quantizeButtonSection
                    } else {
                        modelSelectionSection
                    }
                    
                    if viewModel.isQuantizing {
                        quantizationProgressSection
                    }
                    
                    if !viewModel.quantizedModels.isEmpty {
                        quantizedModelsSection
                    }
                }
                .padding()
            }
            .navigationTitle("Model Quantization")
            .alert("Quantization Status", isPresented: $showAlert) {
                Button("OK") { }
            } message: {
                Text(alertMessage)
            }
            .onReceive(viewModel.$quantizationResult) { result in
                if let result = result {
                    alertMessage = result.success ? "Model quantized successfully!" : "Quantization failed: \(result.error ?? "Unknown error")"
                    showAlert = true
                }
            }
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 50))
                .foregroundColor(.green)
            
            Text("Model Quantization")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Reduce model size and improve inference speed through quantization")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    private var modelSelectionSection: some View {
        VStack(spacing: 16) {
            Button(action: {
                showFilePicker = true
            }) {
                VStack(spacing: 12) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 40))
                        .foregroundColor(.green)
                    
                    Text("Select Model to Quantize")
                        .font(.headline)
                    
                    Text("Choose a model file for quantization")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 120)
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.data],
                allowsMultipleSelection: false
            ) { result in
                viewModel.handleModelSelection(result)
            }
            
            Text("Supported formats: GGUF, ONNX, PyTorch, TensorFlow")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var modelInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)
                Text("Model Information")
                    .font(.headline)
                Spacer()
                Button("Change Model") {
                    viewModel.clearSelection()
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            
            if let modelInfo = viewModel.modelInfo {
                VStack(alignment: .leading, spacing: 8) {
                    InfoRow(title: "Name", value: modelInfo.name)
                    InfoRow(title: "Format", value: modelInfo.format)
                    InfoRow(title: "Size", value: modelInfo.size)
                    InfoRow(title: "Parameters", value: modelInfo.parameters)
                    InfoRow(title: "Precision", value: modelInfo.precision)
                }
            }
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var quantizationOptionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quantization Settings")
                .font(.headline)
            
            VStack(spacing: 12) {
                quantizationTypeSection
                precisionSettingsSection
                advancedOptionsSection
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var quantizationTypeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quantization Type")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
                ForEach(QuantizationType.allCases, id: \.self) { type in
                    QuantizationTypeCard(
                        type: type,
                        isSelected: viewModel.selectedQuantizationType == type
                    ) {
                        viewModel.selectQuantizationType(type)
                    }
                }
            }
        }
    }
    
    private var precisionSettingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Target Precision")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            VStack(spacing: 4) {
                HStack {
                    Text("Bits")
                    Spacer()
                    Picker("Bits", selection: $viewModel.targetBits) {
                        ForEach([4, 8, 16], id: \.self) { bits in
                            Text("\(bits)-bit").tag(bits)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .frame(width: 150)
                }
                
                HStack {
                    Text("Quality vs Size")
                    Spacer()
                    Slider(value: $viewModel.qualityVsSize, in: 0...1)
                        .frame(width: 150)
                }
                
                HStack {
                    Text("Calibration Dataset")
                    Spacer()
                    Picker("Dataset", selection: $viewModel.calibrationDataset) {
                        ForEach(QuantizationCalibrationDataset.allCases, id: \.self) { dataset in
                            Text(dataset.rawValue).tag(dataset)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
            }
        }
    }
    
    private var advancedOptionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Advanced Options")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            VStack(spacing: 4) {
                Toggle("Use symmetric quantization", isOn: $viewModel.useSymmetricQuantization)
                Toggle("Preserve embeddings", isOn: $viewModel.preserveEmbeddings)
                Toggle("Optimize for inference", isOn: $viewModel.optimizeForInference)
                Toggle("Enable mixed precision", isOn: $viewModel.enableMixedPrecision)
            }
        }
    }
    
    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quantization Preview")
                .font(.headline)
            
            VStack(spacing: 8) {
                EstimateRow(
                    title: "Estimated Size",
                    original: viewModel.originalSize,
                    quantized: viewModel.estimatedSize,
                    unit: "MB"
                )
                
                EstimateRow(
                    title: "Inference Speed",
                    original: "1.0x",
                    quantized: "\(String(format: "%.1f", viewModel.estimatedSpeedup))x",
                    unit: ""
                )
                
                EstimateRow(
                    title: "Memory Usage",
                    original: viewModel.originalMemory,
                    quantized: viewModel.estimatedMemory,
                    unit: "MB"
                )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Quality Impact")
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    QualityImpactBar(impact: viewModel.estimatedQualityImpact)
                }
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var quantizeButtonSection: some View {
        Button(action: {
            viewModel.startQuantization()
        }) {
            HStack {
                if viewModel.isQuantizing {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "shippingbox.fill")
                }
                Text(viewModel.isQuantizing ? "Quantizing..." : "Start Quantization")
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(viewModel.canStartQuantization ? Color.green : Color.gray.opacity(0.3))
            .foregroundColor(.white)
            .cornerRadius(10)
        }
        .disabled(!viewModel.canStartQuantization || viewModel.isQuantizing)
    }
    
    private var quantizationProgressSection: some View {
        VStack(spacing: 12) {
            ProgressView(value: viewModel.quantizationProgress)
                .progressViewStyle(LinearProgressViewStyle())
            
            Text(viewModel.quantizationStatus)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
    
    private var quantizedModelsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quantized Models")
                .font(.headline)
            
            ForEach(viewModel.quantizedModels, id: \.id) { model in
                QuantizedModelCard(model: model) {
                    viewModel.exportModel(model)
                } onDelete: {
                    viewModel.deleteModel(model)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}

struct QuantizationTypeCard: View {
    let type: QuantizationType
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: type.iconName)
                    .font(.title2)
                    .foregroundColor(isSelected ? .white : .green)
                
                Text(type.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? .white : .primary)
                
                Text(type.description)
                    .font(.system(size: 10))
                    .foregroundColor(isSelected ? .white : .secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(height: 80)
            .frame(maxWidth: .infinity)
            .background(isSelected ? Color.green : Color.green.opacity(0.1))
            .cornerRadius(8)
        }
    }
}

struct InfoRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

struct EstimateRow: View {
    let title: String
    let original: String
    let quantized: String
    let unit: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(original)\(unit) → \(quantized)\(unit)")
                    .font(.caption)
                    .fontWeight(.medium)
            }
        }
    }
}

struct QualityImpactBar: View {
    let impact: Double // 0.0 = no impact, 1.0 = high impact
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 6)
                
                Rectangle()
                    .fill(impactColor)
                    .frame(width: geometry.size.width * impact, height: 6)
            }
        }
        .frame(height: 6)
        .overlay(
            HStack {
                Text("Low")
                    .font(.system(size: 10))
                    .foregroundColor(.green)
                Spacer()
                Text("High")
                    .font(.system(size: 10))
                    .foregroundColor(.red)
            }
        )
    }
    
    private var impactColor: Color {
        if impact < 0.3 {
            return .green
        } else if impact < 0.7 {
            return .orange
        } else {
            return .red
        }
    }
}

struct QuantizedModelCard: View {
    let model: QuantizedModelInfo
    let onExport: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                HStack {
                    Text("\(model.quantizationType.rawValue)")
                    Text("•")
                    Text("\(model.size) MB")
                    Text("•")
                    Text("\(model.targetBits)-bit")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                Button("Export") { onExport() }
                    .font(.caption)
                    .foregroundColor(.blue)
                
                Button("Delete") { onDelete() }
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(8)
        .shadow(radius: 1)
    }
}


enum QuantizationCalibrationDataset: String, CaseIterable {
    case none = "None"
    case small = "Small (1K samples)"
    case medium = "Medium (10K samples)"
    case large = "Large (100K samples)"
}

#Preview {
    ModelQuantizationView()
}
