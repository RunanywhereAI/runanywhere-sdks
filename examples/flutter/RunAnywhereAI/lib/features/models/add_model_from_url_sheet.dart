import 'package:flutter/material.dart';
import 'package:runanywhere/runanywhere.dart' as sdk;

import 'package:runanywhere_ai/core/design_system/app_colors.dart';
import 'package:runanywhere_ai/core/design_system/app_spacing.dart';
import 'package:runanywhere_ai/core/design_system/typography.dart';
import 'package:runanywhere_ai/features/models/model_list_view_model.dart';
import 'package:runanywhere_ai/features/models/model_types.dart';

/// Sheet for registering a custom GGUF/ONNX model from a remote URL.
///
/// Mirrors iOS `AddModelFromURLView.swift` — text fields for name/URL/size,
/// a framework picker, and a thinking-support toggle. Calls
/// `RunAnywhere.models.register(...)` on submit.
class AddModelFromUrlSheet extends StatefulWidget {
  final void Function(ModelInfo) onModelAdded;

  const AddModelFromUrlSheet({super.key, required this.onModelAdded});

  @override
  State<AddModelFromUrlSheet> createState() => _AddModelFromUrlSheetState();
}

class _AddModelFromUrlSheetState extends State<AddModelFromUrlSheet> {
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  final _sizeController = TextEditingController();

  LLMFramework _selectedFramework =
      sdk.InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP;
  bool _supportsThinking = false;
  bool _isAdding = false;
  String? _errorMessage;

  List<LLMFramework> get _availableFrameworks {
    final vm = ModelListViewModel.shared;
    if (vm.availableFrameworks.isNotEmpty) {
      return vm.availableFrameworks
          .where(
            (f) =>
                f !=
                    sdk.InferenceFramework
                        .INFERENCE_FRAMEWORK_FOUNDATION_MODELS &&
                f != sdk.InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS &&
                f != sdk.InferenceFramework.INFERENCE_FRAMEWORK_UNKNOWN,
          )
          .toList();
    }
    return [
      sdk.InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      sdk.InferenceFramework.INFERENCE_FRAMEWORK_ONNX,
    ];
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _sizeController.dispose();
    super.dispose();
  }

  Future<void> _addModel() async {
    final name = _nameController.text.trim();
    final url = _urlController.text.trim();

    if (name.isEmpty || url.isEmpty) return;

    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasAbsolutePath) {
      setState(() => _errorMessage = 'Invalid URL format');
      return;
    }

    setState(() {
      _isAdding = true;
      _errorMessage = null;
    });

    try {
      final sizeText = _sizeController.text.trim();
      final memoryRequirement =
          sizeText.isNotEmpty ? int.tryParse(sizeText) : null;

      final model = await sdk.RunAnywhere.models.register(
        name: name,
        url: url,
        framework: _selectedFramework,
        memoryRequirement: memoryRequirement,
        supportsThinking: _supportsThinking,
      );

      await ModelListViewModel.shared.loadModels();

      widget.onModelAdded(model);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isAdding = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: AppColors.backgroundPrimary(context),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppSpacing.cornerRadiusXLarge),
        ),
      ),
      child: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.large),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSection(
                    context,
                    'Model Information',
                    [
                      TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Model Name',
                          border: OutlineInputBorder(),
                        ),
                        textCapitalization: TextCapitalization.none,
                        autocorrect: false,
                        enabled: !_isAdding,
                      ),
                      const SizedBox(height: AppSpacing.mediumLarge),
                      TextField(
                        controller: _urlController,
                        decoration: const InputDecoration(
                          labelText: 'Download URL',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.url,
                        textCapitalization: TextCapitalization.none,
                        autocorrect: false,
                        enabled: !_isAdding,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xLarge),
                  _buildSection(
                    context,
                    'Framework',
                    [
                      DropdownButtonFormField<LLMFramework>(
                        initialValue: _selectedFramework,
                        decoration: const InputDecoration(
                          labelText: 'Target Framework',
                          border: OutlineInputBorder(),
                        ),
                        items: _availableFrameworks
                            .map(
                              (f) => DropdownMenuItem(
                                value: f,
                                child: Text(f.displayName),
                              ),
                            )
                            .toList(),
                        onChanged: _isAdding
                            ? null
                            : (f) {
                                if (f != null) {
                                  setState(() => _selectedFramework = f);
                                }
                              },
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xLarge),
                  _buildSection(
                    context,
                    'Thinking Support',
                    [
                      SwitchListTile(
                        title: Text(
                          'Model Supports Thinking',
                          style: AppTypography.body(context),
                        ),
                        value: _supportsThinking,
                        onChanged: _isAdding
                            ? null
                            : (v) => setState(() => _supportsThinking = v),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xLarge),
                  _buildSection(
                    context,
                    'Advanced (Optional)',
                    [
                      TextField(
                        controller: _sizeController,
                        decoration: const InputDecoration(
                          labelText: 'Estimated Size (bytes)',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        enabled: !_isAdding,
                      ),
                    ],
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: AppSpacing.mediumLarge),
                    Text(
                      _errorMessage!,
                      style: AppTypography.caption(context)
                          .copyWith(color: AppColors.primaryRed),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xLarge),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed:
                          _isAdding ||
                                  _nameController.text.trim().isEmpty ||
                                  _urlController.text.trim().isEmpty
                              ? null
                              : _addModel,
                      child: _isAdding
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Add Model'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.large),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.separator(context)),
        ),
      ),
      child: Row(
        children: [
          TextButton(
            onPressed: _isAdding ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          Expanded(
            child: Text(
              'Add Model from URL',
              style: AppTypography.headline(context),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 70),
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context,
    String title,
    List<Widget> children,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTypography.caption(context).copyWith(
            color: AppColors.textSecondary(context),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.smallMedium),
        ...children,
      ],
    );
  }
}
