import 'package:flutter/material.dart' hide Icon;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runanywhere_ai/core/theme/app_spacing.dart';
import 'package:runanywhere_ai/core/theme/app_typography.dart';
import 'package:runanywhere_ai/features/settings/settings_controller.dart';
import 'package:tabler_icons_next/tabler_icons_next.dart' as tabler;

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: AppSpacing.pagePadding,
        children: [
          _SectionTitle('Generation', theme),
          const SizedBox(height: AppSpacing.sm),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Streaming'),
                  subtitle: const Text('Stream tokens as they generate'),
                  value: settings.useStreaming,
                  onChanged: (v) => controller.setStreaming(enabled: v),
                ),
                const Divider(),
                ListTile(
                  title: const Text('Temperature'),
                  subtitle: Slider(
                    value: settings.temperature,
                    min: 0.0,
                    max: 2.0,
                    divisions: 20,
                    label: settings.temperature.toStringAsFixed(1),
                    onChanged: controller.setTemperature,
                  ),
                  trailing: Text(
                    settings.temperature.toStringAsFixed(1),
                    style: AppTypography.mono,
                  ),
                ),
                const Divider(),
                ListTile(
                  title: const Text('Max Tokens'),
                  subtitle: Slider(
                    value: settings.maxTokens.toDouble(),
                    min: 64,
                    max: 4096,
                    divisions: 63,
                    label: settings.maxTokens.toString(),
                    onChanged: (v) => controller.setMaxTokens(v.round()),
                  ),
                  trailing: Text(
                    '${settings.maxTokens}',
                    style: AppTypography.mono,
                  ),
                ),
                const Divider(),
                ListTile(
                  title: const Text('Top P'),
                  subtitle: Slider(
                    value: settings.topP,
                    min: 0.0,
                    max: 1.0,
                    divisions: 20,
                    label: settings.topP.toStringAsFixed(2),
                    onChanged: controller.setTopP,
                  ),
                  trailing: Text(
                    settings.topP.toStringAsFixed(2),
                    style: AppTypography.mono,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          _SectionTitle('System Prompt', theme),
          const SizedBox(height: AppSpacing.sm),
          Card(
            child: Padding(
              padding: AppSpacing.cardPadding,
              child: TextField(
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Enter system prompt...',
                  border: InputBorder.none,
                ),
                controller:
                    TextEditingController(text: settings.systemPrompt),
                onChanged: controller.setSystemPrompt,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          _SectionTitle('Tools', theme),
          const SizedBox(height: AppSpacing.sm),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Tool Calling'),
                  subtitle: const Text(
                    'Enable function calling for weather, calculator, and time',
                  ),
                  value: settings.toolCallingEnabled,
                  onChanged: (v) => controller.setToolCalling(enabled: v),
                ),
                if (settings.toolCallingEnabled) ...[
                  const Divider(),
                  _ToolItem(
                    icon: tabler.Cloud(color: theme.colorScheme.primary),
                    name: 'get_weather',
                    description: 'Fetch current weather for a location',
                  ),
                  _ToolItem(
                    icon: tabler.Calculator(color: theme.colorScheme.tertiary),
                    name: 'calculate',
                    description: 'Basic arithmetic operations',
                  ),
                  _ToolItem(
                    icon: tabler.Clock(color: theme.colorScheme.secondary),
                    name: 'get_current_time',
                    description: 'Returns current date and time',
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          _SectionTitle('About', theme),
          const SizedBox(height: AppSpacing.sm),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: SizedBox(
                    width: 24,
                    height: 24,
                    child: tabler.InfoCircle(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  title: const Text('RunAnywhere AI'),
                  subtitle: const Text('v1.0.0'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, this.theme);

  final String title;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: AppTypography.labelLarge.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _ToolItem extends StatelessWidget {
  const _ToolItem({
    required this.icon,
    required this.name,
    required this.description,
  });

  final Widget icon;
  final String name;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      leading: SizedBox(width: 24, height: 24, child: icon),
      title: Text(name, style: AppTypography.mono),
      subtitle: Text(
        description,
        style: AppTypography.bodySmall.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      dense: true,
    );
  }
}
