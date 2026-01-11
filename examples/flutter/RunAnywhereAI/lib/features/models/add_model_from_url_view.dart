import 'package:flutter/material.dart';

import 'package:runanywhere_ai/core/design_system/app_colors.dart';
import 'package:runanywhere_ai/core/design_system/app_spacing.dart';
import 'package:runanywhere_ai/core/design_system/typography.dart';
import 'package:runanywhere_ai/features/models/model_types.dart';

/// AddModelFromURLView (mirroring iOS AddModelFromURLView.swift)
///
/// View for adding models from URLs.
class AddModelFromURLView extends StatefulWidget {
  final void Function(ModelInfo) onModelAdded;

  const AddModelFromURLView({
    super.key,
    required this.onModelAdded,
  });

  @override
  State<AddModelFromURLView> createState() => _AddModelFromURLViewState();
}

class _AddModelFromURLViewState extends State<AddModelFromURLView> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  final _sizeController = TextEditingController();

  LLMFramework _selectedFramework = LLMFramework.llamaCpp;
  bool _supportsThinking = false;
  bool _useCustomThinkingTags = false;
  String _thinkingOpenTag = '<thinking>';
  String _thinkingCloseTag = '</thinking>';
  bool _isAdding = false;
  String? _errorMessage;

  final List<LLMFramework> _availableFrameworks = [
    LLMFramework.llamaCpp,
    LLMFramework.mediaPipe,
    LLMFramework.onnxRuntime,
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _sizeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.backgroundPrimary(context),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppSpacing.cornerRadiusXLarge),
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(context),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.large),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildModelInfoSection(context),
                      const SizedBox(height: AppSpacing.xLarge),
                      _buildFrameworkSection(context),
                      const SizedBox(height: AppSpacing.xLarge),
                      _buildThinkingSection(context),
                      const SizedBox(height: AppSpacing.xLarge),
                      _buildAdvancedSection(context),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: AppSpacing.large),
                        _buildErrorMessage(context),
                      ],
                      const SizedBox(height: AppSpacing.xLarge),
                      _buildAddButton(context),
                      const SizedBox(height: AppSpacing.large),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.large),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppColors.separator(context),
          ),
        ),
      ),
      child: Row(
        children: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          Expanded(
            child: Text(
              'Add Model from URL',
              style: AppTypography.headline(context),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 60), // Balance the cancel button
        ],
      ),
    );
  }

  Widget _buildModelInfoSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Model Information',
          style: AppTypography.subheadlineSemibold(context),
        ),
        const SizedBox(height: AppSpacing.mediumLarge),
        TextFormField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: 'Model Name',
            hintText: 'e.g., Llama 3.2 1B',
            border: OutlineInputBorder(),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter a model name';
            }
            return null;
          },
        ),
        const SizedBox(height: AppSpacing.large),
        TextFormField(
          controller: _urlController,
          decoration: const InputDecoration(
            labelText: 'Download URL',
            hintText: 'https://example.com/model.gguf',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.url,
          autocorrect: false,
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter a URL';
            }
            final uri = Uri.tryParse(value);
            if (uri == null || !uri.hasScheme) {
              return 'Please enter a valid URL';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildFrameworkSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Framework',
          style: AppTypography.subheadlineSemibold(context),
        ),
        const SizedBox(height: AppSpacing.mediumLarge),
        DropdownButtonFormField<LLMFramework>(
          initialValue: _selectedFramework,
          decoration: const InputDecoration(
            labelText: 'Target Framework',
            border: OutlineInputBorder(),
          ),
          items: _availableFrameworks.map((framework) {
            return DropdownMenuItem(
              value: framework,
              child: Text(framework.displayName),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) {
              setState(() {
                _selectedFramework = value;
              });
            }
          },
        ),
      ],
    );
  }

  Widget _buildThinkingSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Thinking Support',
          style: AppTypography.subheadlineSemibold(context),
        ),
        const SizedBox(height: AppSpacing.mediumLarge),
        SwitchListTile(
          title: const Text('Model Supports Thinking'),
          value: _supportsThinking,
          onChanged: (value) {
            setState(() {
              _supportsThinking = value;
            });
          },
          contentPadding: EdgeInsets.zero,
        ),
        if (_supportsThinking) ...[
          SwitchListTile(
            title: const Text('Use Custom Tags'),
            value: _useCustomThinkingTags,
            onChanged: (value) {
              setState(() {
                _useCustomThinkingTags = value;
              });
            },
            contentPadding: EdgeInsets.zero,
          ),
          if (_useCustomThinkingTags) ...[
            const SizedBox(height: AppSpacing.mediumLarge),
            TextFormField(
              initialValue: _thinkingOpenTag,
              decoration: const InputDecoration(
                labelText: 'Opening Tag',
                hintText: '<thinking>',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                _thinkingOpenTag = value;
              },
            ),
            const SizedBox(height: AppSpacing.mediumLarge),
            TextFormField(
              initialValue: _thinkingCloseTag,
              decoration: const InputDecoration(
                labelText: 'Closing Tag',
                hintText: '</thinking>',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                _thinkingCloseTag = value;
              },
            ),
          ] else ...[
            const SizedBox(height: AppSpacing.smallMedium),
            Row(
              children: [
                Text(
                  'Default tags: ',
                  style: AppTypography.caption(context),
                ),
                Text(
                  '<thinking>...</thinking>',
                  style: AppTypography.monospacedCaption.copyWith(
                    color: AppColors.textSecondary(context),
                  ),
                ),
              ],
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildAdvancedSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Advanced (Optional)',
          style: AppTypography.subheadlineSemibold(context),
        ),
        const SizedBox(height: AppSpacing.mediumLarge),
        TextFormField(
          controller: _sizeController,
          decoration: const InputDecoration(
            labelText: 'Estimated Size (bytes)',
            hintText: 'e.g., 1000000000',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.number,
        ),
      ],
    );
  }

  Widget _buildErrorMessage(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.mediumLarge),
      decoration: BoxDecoration(
        color: AppColors.badgeRed,
        borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusRegular),
      ),
      child: Row(
        children: [
          const Icon(Icons.error, color: AppColors.statusRed),
          const SizedBox(width: AppSpacing.smallMedium),
          Expanded(
            child: Text(
              _errorMessage!,
              style: AppTypography.caption(context).copyWith(
                color: AppColors.statusRed,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddButton(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isAdding ? null : _addModel,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.large),
            ),
            child: _isAdding
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Add Model'),
          ),
        ),
        if (_isAdding) ...[
          const SizedBox(height: AppSpacing.mediumLarge),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: AppSpacing.smallMedium),
              Text(
                'Adding model...',
                style: AppTypography.caption(context).copyWith(
                  color: AppColors.textSecondary(context),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _addModel() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isAdding = true;
      _errorMessage = null;
    });

    try {
      final url = _urlController.text.trim();
      final name = _nameController.text.trim();
      final sizeText = _sizeController.text.trim();
      final estimatedSize = sizeText.isNotEmpty ? int.tryParse(sizeText) : null;

      // TODO: Use RunAnywhere SDK to add model
      // final modelInfo = await RunAnywhere.addModelFromURL(
      //   url,
      //   name: name,
      //   type: _selectedFramework.rawValue,
      // );

      // Create placeholder model for demo
      final modelInfo = ModelInfo(
        id: 'custom-${DateTime.now().millisecondsSinceEpoch}',
        name: name,
        category: ModelCategory.language,
        format: ModelFormat.gguf,
        downloadURL: url,
        memoryRequired: estimatedSize,
        compatibleFrameworks: [_selectedFramework],
        preferredFramework: _selectedFramework,
        supportsThinking: _supportsThinking,
      );

      widget.onModelAdded(modelInfo);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to add model: $e';
        _isAdding = false;
      });
    }
  }
}
