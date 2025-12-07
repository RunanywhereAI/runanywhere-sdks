import 'dart:io';
import 'package:flutter/material.dart';
import 'package:runanywhere/runanywhere.dart';
// Import the backend modules for modular AI capabilities
import 'package:runanywhere/backends/onnx/onnx.dart';
import 'package:runanywhere/backends/llamacpp/llamacpp.dart';
import '../../core/design_system/app_colors.dart';
import '../../core/design_system/app_spacing.dart';
import '../../core/design_system/typography.dart';

/// Simplified Settings View
class SimplifiedSettingsView extends StatefulWidget {
  const SimplifiedSettingsView({super.key});

  @override
  State<SimplifiedSettingsView> createState() => _SimplifiedSettingsViewState();
}

class _SimplifiedSettingsViewState extends State<SimplifiedSettingsView> {
  int _maxTokens = 500;
  double _temperature = 0.7;
  bool _streamEnabled = true;

  // Native bindings test state
  String _nativeStatus = 'Not tested';
  String _nativeBackends = '';
  String _nativeVersion = '';
  bool _nativeLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.padding16),
        children: [
          _buildSection(
            title: 'Generation Settings',
            children: [
              _buildSliderSetting(
                title: 'Max Tokens',
                value: _maxTokens.toDouble(),
                min: 100,
                max: 2000,
                divisions: 19,
                onChanged: (value) {
                  setState(() {
                    _maxTokens = value.toInt();
                  });
                },
                formatValue: (value) => value.toInt().toString(),
              ),
              const SizedBox(height: AppSpacing.padding16),
              _buildSliderSetting(
                title: 'Temperature',
                value: _temperature,
                min: 0.0,
                max: 2.0,
                divisions: 20,
                onChanged: (value) {
                  setState(() {
                    _temperature = value;
                  });
                },
                formatValue: (value) => value.toStringAsFixed(2),
              ),
              const SizedBox(height: AppSpacing.padding16),
              SwitchListTile(
                title: const Text('Streaming Enabled'),
                value: _streamEnabled,
                onChanged: (value) {
                  setState(() {
                    _streamEnabled = value;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.padding32),
          _buildSection(
            title: 'SDK Information',
            children: [
              _buildInfoRow('SDK Version', RunAnywhere.getSDKVersion()),
              _buildInfoRow(
                'Environment',
                RunAnywhere.getCurrentEnvironment()?.description ?? 'Unknown',
              ),
              _buildInfoRow(
                'Initialized',
                RunAnywhere.isSDKInitialized ? 'Yes' : 'No',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.padding32),
          _buildSection(
            title: 'Memory Statistics',
            children: [
              Builder(
                builder: (context) {
                  final stats = RunAnywhere.serviceContainer.memoryService
                      .getMemoryStatistics();
                  return Column(
                    children: [
                      _buildInfoRow(
                        'Total Memory',
                        _formatBytes(stats.totalMemory),
                      ),
                      _buildInfoRow(
                        'Available Memory',
                        _formatBytes(stats.availableMemory),
                      ),
                      _buildInfoRow(
                        'Model Memory',
                        _formatBytes(stats.modelMemory),
                      ),
                      _buildInfoRow(
                        'Loaded Models',
                        stats.loadedModelCount.toString(),
                      ),
                      _buildInfoRow(
                        'Memory Pressure',
                        stats.memoryPressure ? 'Yes' : 'No',
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.padding32),
          _buildSection(
            title: 'Native FFI Bindings',
            children: [
              _buildInfoRow('Platform', Platform.operatingSystem),
              _buildInfoRow('Status', _nativeStatus),
              if (_nativeVersion.isNotEmpty)
                _buildInfoRow('Native Version', _nativeVersion),
              if (_nativeBackends.isNotEmpty)
                _buildInfoRow('Available Backends', _nativeBackends),
              const SizedBox(height: AppSpacing.padding16),
              FilledButton.icon(
                onPressed: _nativeLoading ? null : _testNativeBindings,
                icon: _nativeLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.science),
                label:
                    Text(_nativeLoading ? 'Testing...' : 'Test Native Library'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _testNativeBindings() async {
    setState(() {
      _nativeLoading = true;
      _nativeStatus = 'Loading native library...';
      _nativeBackends = '';
      _nativeVersion = '';
    });

    try {
      // Check if native library is available
      if (!OnnxBackend.isAvailable) {
        setState(() {
          _nativeStatus = '✗ Native library not available on this platform';
        });
        return;
      }

      // Initialize ONNX backend (STT, TTS, VAD)
      setState(() {
        _nativeStatus = 'Initializing ONNX backend...';
      });

      final onnxSuccess = await OnnxBackend.initialize(priority: 100);
      if (!onnxSuccess) {
        setState(() {
          _nativeStatus = '✗ Failed to initialize ONNX backend';
        });
        return;
      }

      // Initialize LlamaCpp backend (LLM)
      setState(() {
        _nativeStatus = 'Initializing LlamaCpp backend...';
      });

      final llamaSuccess = await LlamaCppBackend.initialize(priority: 90);
      // LlamaCpp init failure is non-fatal - ONNX provides LLM fallback

      setState(() {
        _nativeStatus = 'Backends initialized! Getting info...';
      });

      // Get available backends from native library
      final backends = OnnxBackend.availableBackends;

      // Get backend info and version
      final info = OnnxBackend.getBackendInfo();
      final infoName = info['name']?.toString() ?? 'ONNX';
      setState(() {
        _nativeVersion = '${OnnxBackend.version} ($infoName)';
      });

      // Show registered modules
      final modules = ModuleRegistry.shared.registeredModules;
      final backendsStr = backends.isEmpty ? 'onnx' : backends.join(', ');
      final llamaStatus = llamaSuccess ? '✓ LlamaCpp' : '○ LlamaCpp (fallback)';

      setState(() {
        _nativeBackends = 'Native: $backendsStr\n'
            '✓ ONNX (STT, TTS, VAD)\n'
            '$llamaStatus (LLM)\n'
            'Modules: ${modules.join(", ")}';
        _nativeStatus = '✓ All backends initialized!';
      });
    } catch (e) {
      setState(() {
        _nativeStatus = '✗ Error: $e';
      });
    } finally {
      setState(() {
        _nativeLoading = false;
      });
    }
  }

  Widget _buildSection({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          // style: AppTypography.headlineSemibold,
        ),
        const SizedBox(height: AppSpacing.padding16),
        ...children,
      ],
    );
  }

  Widget _buildSliderSetting({
    required String title,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    required String Function(double) formatValue,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: AppTypography.body(context)),
            Text(
              formatValue(value),
              style: AppTypography.body(context).copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.padding8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: AppTypography.body(context).copyWith(
              color: AppColors.textSecondary(context),
            ),
          ),
          Text(
            value,
            style: AppTypography.body(context),
          ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
