import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:runanywhere_ai/core/widgets/app_shell.dart';
import 'package:runanywhere_ai/features/chat/chat_screen.dart';
import 'package:runanywhere_ai/features/intro/intro_screen.dart';
import 'package:runanywhere_ai/features/models/models_screen.dart';
import 'package:runanywhere_ai/features/more/more_screen.dart';
import 'package:runanywhere_ai/features/rag/rag_screen.dart';
import 'package:runanywhere_ai/features/settings/settings_screen.dart';
import 'package:runanywhere_ai/features/structured_output/structured_output_screen.dart';
import 'package:runanywhere_ai/features/vision/vision_screen.dart';
import 'package:runanywhere_ai/features/voice/stt_screen.dart';
import 'package:runanywhere_ai/features/voice/tts_screen.dart';
import 'package:runanywhere_ai/features/voice/voice_assistant_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/intro',
    routes: [
      GoRoute(
        path: '/intro',
        builder: (context, state) => const IntroScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/home/chat',
            builder: (context, state) => const ChatScreen(),
            routes: [
              GoRoute(
                path: 'structured-output',
                builder: (context, state) => const StructuredOutputScreen(),
              ),
            ],
          ),
          GoRoute(
            path: '/home/vision',
            builder: (context, state) => const VisionScreen(),
          ),
          GoRoute(
            path: '/home/more',
            builder: (context, state) => const MoreScreen(),
            routes: [
              GoRoute(
                path: 'stt',
                builder: (context, state) => const SttScreen(),
              ),
              GoRoute(
                path: 'tts',
                builder: (context, state) => const TtsScreen(),
              ),
              GoRoute(
                path: 'voice',
                builder: (context, state) => const VoiceAssistantScreen(),
              ),
              GoRoute(
                path: 'rag',
                builder: (context, state) => const RagScreen(),
              ),
              GoRoute(
                path: 'models',
                builder: (context, state) => const ModelsScreen(),
              ),
            ],
          ),
          GoRoute(
            path: '/home/settings',
            builder: (context, state) => const SettingsScreen(),
          ),
        ],
      ),
    ],
  );
});
