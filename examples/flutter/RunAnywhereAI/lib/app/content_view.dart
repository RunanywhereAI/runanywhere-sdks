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

  // Tabs are built lazily on first visit and kept alive afterwards. A hidden
  // tab's initState / view-model work (animations, event-bus subscriptions,
  // periodic refreshes) must not run until the user selects that tab.
  // IndexedStack still preserves each tab's state once it has been built.
  final Set<int> _visitedTabs = {0};

  Widget _buildTab(int index) {
    switch (index) {
      case 0:
        return const ChatInterfaceView(); // Chat (LLM)
      case 1:
        return const VisionHubView(); // Vision (VLM)
      case 2:
        return const VoiceAssistantView(); // Voice Assistant (STT + LLM + TTS)
      case 3:
        return const MoreView(); // More hub
      case 4:
        return const CombinedSettingsView(); // Settings
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedTab,
        children: List.generate(
          5,
          (index) => _visitedTabs.contains(index)
              ? _buildTab(index)
              : const SizedBox.shrink(),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        // B-FL-14-002: explicit height + vertical padding so the
        // accessibility tap-target bounds match the visible icon centres
        // and the "Transcribe" label doesn't truncate.
        height: 80,
        indicatorColor: AppColors.primaryAccent.withValues(alpha: 0.2),
        onDestinationSelected: (index) {
          setState(() {
            _selectedTab = index;
            _visitedTabs.add(index);
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
