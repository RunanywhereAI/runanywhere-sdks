import 'package:flutter/material.dart';

import '../core/design_system/app_colors.dart';
import '../features/chat/chat_interface_view.dart';
import '../features/quiz/quiz_view.dart';
import '../features/settings/combined_settings_view.dart';
import '../features/storage/storage_view.dart';
import '../features/voice/speech_to_text_view.dart';
import '../features/voice/text_to_speech_view.dart';
import '../features/voice/voice_assistant_view.dart';

/// ContentView (mirroring iOS ContentView.swift)
///
/// Main tab-based navigation for the app.
/// iOS tabs: Chat, STT, TTS, Voice, Settings
class ContentView extends StatefulWidget {
  const ContentView({super.key});

  @override
  State<ContentView> createState() => _ContentViewState();
}

class _ContentViewState extends State<ContentView> {
  int _selectedTab = 0;

  // Tab pages matching iOS structure
  final List<Widget> _pages = const [
    ChatInterfaceView(),
    SpeechToTextView(),
    TextToSpeechView(),
    VoiceAssistantView(),
    CombinedSettingsView(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedTab,
        children: _pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (index) {
          setState(() {
            _selectedTab = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.graphic_eq_outlined),
            selectedIcon: Icon(Icons.graphic_eq),
            label: 'STT',
          ),
          NavigationDestination(
            icon: Icon(Icons.volume_up_outlined),
            selectedIcon: Icon(Icons.volume_up),
            label: 'TTS',
          ),
          NavigationDestination(
            icon: Icon(Icons.mic_none),
            selectedIcon: Icon(Icons.mic),
            label: 'Voice',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

/// Alternative content view with additional tabs (Quiz, Storage)
/// Use this if you want to include all features like the previous version
class ContentViewExtended extends StatefulWidget {
  const ContentViewExtended({super.key});

  @override
  State<ContentViewExtended> createState() => _ContentViewExtendedState();
}

class _ContentViewExtendedState extends State<ContentViewExtended> {
  int _selectedTab = 0;

  final List<Widget> _pages = const [
    ChatInterfaceView(),
    StorageView(),
    QuizView(),
    VoiceAssistantView(),
    CombinedSettingsView(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedTab,
        children: _pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (index) {
          setState(() {
            _selectedTab = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.storage_outlined),
            selectedIcon: Icon(Icons.storage),
            label: 'Models',
          ),
          NavigationDestination(
            icon: Icon(Icons.quiz_outlined),
            selectedIcon: Icon(Icons.quiz),
            label: 'Quiz',
          ),
          NavigationDestination(
            icon: Icon(Icons.mic_none),
            selectedIcon: Icon(Icons.mic),
            label: 'Voice',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
