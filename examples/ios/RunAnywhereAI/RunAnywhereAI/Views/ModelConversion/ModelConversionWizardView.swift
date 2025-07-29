import SwiftUI

struct ModelConversionWizardView: View {
    @StateObject private var viewModel = ModelConversionWizardViewModel()
    @State private var showFilePicker = false
    @State private var showAlert = false
    @State private var alertMessage = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                headerSection

                if viewModel.selectedModelFile != nil {
                    selectedModelSection
                    formatSelectionSection
                    conversionOptionsSection
                    conversionButtonSection
                } else {
                    fileSelectionSection
                }

                if viewModel.isConverting {
                    conversionProgressSection
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Model Conversion")
            .alert("Conversion Status", isPresented: $showAlert) {
                Button("OK") { }
            } message: {
                Text(alertMessage)
            }
            .onReceive(viewModel.$conversionResult) { result in
                if let result = result {
                    alertMessage = result.success ? "Conversion completed successfully!" : "Conversion failed: \(result.error ?? "Unknown error")"
                    showAlert = true
                }
            }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 50))
                .foregroundColor(.blue)

            Text("Model Format Converter")
                .font(.title)
                .fontWeight(.bold)

            Text("Convert models between different LLM framework formats")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var fileSelectionSection: some View {
        VStack(spacing: 16) {
            Button(action: {
                showFilePicker = true
            }) {
                VStack(spacing: 12) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 40))
                        .foregroundColor(.blue)

                    Text("Select Model File")
                        .font(.headline)

                    Text("Choose a model file to convert")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 120)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.data],
                allowsMultipleSelection: false
            ) { result in
                viewModel.handleFileSelection(result)
            }
        }
    }

    private var selectedModelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "doc.fill")
                    .foregroundColor(.green)
                Text("Selected Model")
                    .font(.headline)
                Spacer()
                Button("Change") {
                    viewModel.clearSelection()
                }
                .font(.caption)
                .foregroundColor(.blue)
            }

            if let file = viewModel.selectedModelFile {
                VStack(alignment: .leading, spacing: 4) {
                    Text(file.lastPathComponent)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    HStack {
                        Text("Format: \(viewModel.detectedFormat?.rawValue ?? "Unknown")")
                        Spacer()
                        Text("Size: \(viewModel.formattedFileSize)")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }

    private var formatSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Target Format")
                .font(.headline)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                ForEach(ConversionFormat.allCases, id: \.self) { format in
                    FormatCard(
                        format: format,
                        isSelected: viewModel.targetFormat == format,
                        isEnabled: viewModel.canConvertTo(format)
                    ) {
                        viewModel.selectTargetFormat(format)
                    }
                }
            }
        }
    }

    private var conversionOptionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Conversion Options")
                .font(.headline)

            VStack(spacing: 8) {
                HStack {
                    Text("Quantization")
                    Spacer()
                    Picker("Quantization", selection: $viewModel.quantizationLevel) {
                        ForEach(QuantizationLevel.allCases, id: \.self) { level in
                            Text(level.rawValue).tag(level)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }

                HStack {
                    Text("Optimize for")
                    Spacer()
                    Picker("Optimization", selection: $viewModel.optimizationTarget) {
                        ForEach(ConversionOptimizationTarget.allCases, id: \.self) { target in
                            Text(target.rawValue).tag(target)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }

                Toggle("Preserve metadata", isOn: $viewModel.preserveMetadata)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
    }

    private var conversionButtonSection: some View {
        Button(action: {
            viewModel.startConversion()
        }) {
            HStack {
                if viewModel.isConverting {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                Text(viewModel.isConverting ? "Converting..." : "Start Conversion")
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(viewModel.canStartConversion ? Color.blue : Color.gray.opacity(0.3))
            .foregroundColor(.white)
            .cornerRadius(10)
        }
        .disabled(!viewModel.canStartConversion || viewModel.isConverting)
    }

    private var conversionProgressSection: some View {
        VStack(spacing: 12) {
            ProgressView(value: viewModel.conversionProgress)
                .progressViewStyle(LinearProgressViewStyle())

            Text(viewModel.conversionStatus)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}

struct FormatCard: View {
    let format: ConversionFormat
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: format.iconName)
                    .font(.system(size: 24))
                    .foregroundColor(isSelected ? .white : (isEnabled ? .blue : .gray))

                Text(format.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? .white : (isEnabled ? .primary : .gray))
            }
            .frame(height: 60)
            .frame(maxWidth: .infinity)
            .background(isSelected ? Color.blue : (isEnabled ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1)))
            .cornerRadius(8)
        }
        .disabled(!isEnabled)
    }
}


#Preview {
    ModelConversionWizardView()
}
