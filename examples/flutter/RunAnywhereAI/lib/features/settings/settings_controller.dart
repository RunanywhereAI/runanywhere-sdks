import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsState {
  const SettingsState({
    this.useStreaming = true,
    this.systemPrompt = 'You are a helpful AI assistant.',
    this.temperature = 0.8,
    this.maxTokens = 512,
    this.topP = 1.0,
    this.toolCallingEnabled = false,
  });

  final bool useStreaming;
  final String systemPrompt;
  final double temperature;
  final int maxTokens;
  final double topP;
  final bool toolCallingEnabled;

  SettingsState copyWith({
    bool? useStreaming,
    String? systemPrompt,
    double? temperature,
    int? maxTokens,
    double? topP,
    bool? toolCallingEnabled,
  }) {
    return SettingsState(
      useStreaming: useStreaming ?? this.useStreaming,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      temperature: temperature ?? this.temperature,
      maxTokens: maxTokens ?? this.maxTokens,
      topP: topP ?? this.topP,
      toolCallingEnabled: toolCallingEnabled ?? this.toolCallingEnabled,
    );
  }
}

final settingsControllerProvider =
    NotifierProvider<SettingsController, SettingsState>(
  SettingsController.new,
);

class SettingsController extends Notifier<SettingsState> {
  @override
  SettingsState build() {
    _load();
    return const SettingsState();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = SettingsState(
      useStreaming: prefs.getBool('useStreaming') ?? true,
      systemPrompt:
          prefs.getString('systemPrompt') ?? 'You are a helpful AI assistant.',
      temperature: prefs.getDouble('temperature') ?? 0.8,
      maxTokens: prefs.getInt('maxTokens') ?? 512,
      topP: prefs.getDouble('topP') ?? 1.0,
      toolCallingEnabled: prefs.getBool('toolCallingEnabled') ?? false,
    );
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('useStreaming', state.useStreaming);
    await prefs.setString('systemPrompt', state.systemPrompt);
    await prefs.setDouble('temperature', state.temperature);
    await prefs.setInt('maxTokens', state.maxTokens);
    await prefs.setDouble('topP', state.topP);
    await prefs.setBool('toolCallingEnabled', state.toolCallingEnabled);
  }

  void setStreaming({required bool enabled}) {
    state = state.copyWith(useStreaming: enabled);
    _save();
  }

  void setSystemPrompt(String prompt) {
    state = state.copyWith(systemPrompt: prompt);
    _save();
  }

  void setTemperature(double temp) {
    state = state.copyWith(temperature: temp);
    _save();
  }

  void setMaxTokens(int tokens) {
    state = state.copyWith(maxTokens: tokens);
    _save();
  }

  void setTopP(double topP) {
    state = state.copyWith(topP: topP);
    _save();
  }

  void setToolCalling({required bool enabled}) {
    state = state.copyWith(toolCallingEnabled: enabled);
    _save();
  }
}
