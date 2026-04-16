import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runanywhere_ai/core/providers/sdk_provider.dart';
import 'package:runanywhere_ai/features/intro/intro_state.dart';

final introControllerProvider =
    NotifierProvider<IntroController, IntroState>(IntroController.new);

class IntroController extends Notifier<IntroState> {
  @override
  IntroState build() {
    Future.microtask(_initialize);
    return const IntroState();
  }

  Future<void> _initialize() async {
    try {
      await initializeSDK((progress, status) {
        state = state.copyWith(progress: progress, statusText: status);
      });

      await Future<void>.delayed(const Duration(milliseconds: 400));
      state = state.copyWith(isComplete: true);
    } on Exception catch (e) {
      debugPrint('SDK init error: $e');
      state = state.copyWith(
        progress: 1.0,
        statusText: 'Setup failed',
      );
      await Future<void>.delayed(const Duration(seconds: 2));
      state = state.copyWith(isComplete: true);
    }
  }
}
