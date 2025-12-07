import 'dart:async';
import '../../core/module_registry.dart';
import 'vad_configuration.dart';
import 'simple_energy_vad.dart';

/// Default VAD adapter using SimpleEnergyVAD
class DefaultVADProvider implements VADServiceProvider {
  @override
  String get name => 'SimpleEnergyVAD';

  @override
  bool canHandle({String? modelId}) {
    // SimpleEnergyVAD is the default and handles all requests
    return true;
  }

  @override
  Future<VADService> createVADService(dynamic configuration) async {
    final vadConfig = configuration as VADConfiguration;

    final vad = SimpleEnergyVAD(
      sampleRate: vadConfig.sampleRate,
      frameLength: vadConfig.frameLength,
      energyThreshold: vadConfig.energyThreshold,
    );

    await vad.initialize();
    return vad;
  }
}
