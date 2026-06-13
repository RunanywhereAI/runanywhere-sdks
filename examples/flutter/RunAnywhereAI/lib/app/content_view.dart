import 'package:flutter/material.dart';
import 'package:runanywhere_ai/core/design_system/app_colors.dart';
import 'package:runanywhere_ai/features/chat/chat_interface_view.dart';
import 'package:runanywhere_ai/features/more/more_view.dart';
import 'package:runanywhere_ai/features/settings/combined_settings_view.dart';
import 'package:runanywhere_ai/features/vision/vision_hub_view.dart';
import 'package:runanywhere_ai/features/voice/voice_assistant_view.dart';

/// ContentView (mirroring iOS ContentView.swift)
///
/// Main tab-based navigation for the app.
/// Tabs: Chat, Vision, Voice, More, Settings
class ContentView extends StatefulWidget {
  const ContentView({super.key});

  @override
  State<ContentView> createState() => _ContentViewState();
}

class _ContentViewState extends State<ContentView> {
  int _selectedTab = 0;

  // Tab pages matching iOS structure.
  final List<Widget> _pages = const [
    ChatInterfaceView(), // Tab 0: Chat (LLM)
    VisionHubView(), // Tab 1: Vision (VLM)
    VoiceAssistantView(), // Tab 2: Voice Assistant (STT + LLM + TTS)
    MoreView(), // Tab 3: More hub
    CombinedSettingsView(), // Tab 4: Settings
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedTab, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        // B-FL-14-002: explicit height + vertical padding so the
        // accessibility tap-target bounds match the visible icon centres
        // and the "Transcribe" label doesn't truncate.
        height: 80,
        indicatorColor: AppColors.primaryBlue.withValues(alpha: 0.2),
        onDestinationSelected: (index) {
          setState(() {
            _selectedTab = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Icon(Icons.chat_bubble_outline),
            ),
            selectedIcon: Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Icon(Icons.chat_bubble),
            ),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Icon(Icons.visibility_outlined),
            ),
            selectedIcon: Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Icon(Icons.visibility),
            ),
            label: 'Vision',
          ),
          NavigationDestination(
            icon: Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Icon(Icons.mic_none),
            ),
            selectedIcon: Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Icon(Icons.mic),
            ),
            label: 'Voice',
          ),
          NavigationDestination(
            icon: Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Icon(Icons.more_horiz),
            ),
            selectedIcon: Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Icon(Icons.more),
            ),
            label: 'More',
          ),
          NavigationDestination(
            icon: Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Icon(Icons.settings_outlined),
            ),
            selectedIcon: Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Icon(Icons.settings),
            ),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
