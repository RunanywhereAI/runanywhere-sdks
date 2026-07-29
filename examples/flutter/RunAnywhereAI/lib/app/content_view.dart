import 'package:flutter/material.dart';
import 'package:runanywhere/runanywhere.dart';
import 'package:runanywhere_ai/core/design_system/app_colors.dart';
import 'package:runanywhere_ai/core/services/connect_service.dart';
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
  final ConnectService _connect = ConnectService.shared;

  @override
  void initState() {
    super.initState();
    _connect.addListener(_connectChanged);
  }

  @override
  void dispose() {
    _connect.removeListener(_connectChanged);
    super.dispose();
  }

  void _connectChanged() {
    if (mounted) setState(() {});
  }

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
      body: Stack(
        children: [
          IndexedStack(
            index: _selectedTab,
            children: List.generate(
              5,
              (index) => _visitedTabs.contains(index)
                  ? _buildTab(index)
                  : const SizedBox.shrink(),
            ),
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + kToolbarHeight + 8,
            left: 0,
            right: 0,
            child: _ConnectBanner(state: _connect.state),
          ),
        ],
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

class _ConnectBanner extends StatefulWidget {
  const _ConnectBanner({required this.state});

  final ConnectState state;

  @override
  State<_ConnectBanner> createState() => _ConnectBannerState();
}

class _ConnectBannerState extends State<_ConnectBanner> {
  String? _dismissedKey;
  String? _autoDismissScheduledKey;

  String? get _key => switch (widget.state.status) {
    ConnectStatus.connecting =>
      'connecting:${widget.state.connectingHost?.id}',
    ConnectStatus.connected =>
      'connected:${widget.state.activeHost?.id}:${widget.state.activeModel?.id}',
    ConnectStatus.disconnected =>
      'disconnected:${widget.state.lastDisconnectedHost?.id}:${widget.state.message}',
    ConnectStatus.failed => 'failed:${widget.state.message}',
    _ => null,
  };

  @override
  void didUpdateWidget(covariant _ConnectBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    final key = _key;
    if (key == null || key == _dismissedKey) return;
    // Schedule auto-dismiss once per banner key so reconnect churn does not
    // reset a user-dismissed or already-scheduled banner.
    if (widget.state.status == ConnectStatus.connected &&
        key != _autoDismissScheduledKey) {
      _autoDismissScheduledKey = key;
      Future<void>.delayed(const Duration(seconds: 6), () {
        if (mounted && _key == key) setState(() => _dismissedKey = key);
      });
    }
  }

  (String, String, String, Color, IconData) get _presentation {
    final state = widget.state;
    return switch (state.status) {
      ConnectStatus.connected => (
        state.activeHost?.displayName ?? 'Connected to Host',
        state.activeModel?.displayName ?? 'Hosted model ready',
        'connected',
        AppColors.statusGreen,
        Icons.check_circle,
      ),
      ConnectStatus.connecting => (
        'Connecting to ${state.connectingHost?.displayName ?? 'host'}',
        'Checking the selected model',
        'connecting',
        AppColors.primaryAccent,
        Icons.sync,
      ),
      ConnectStatus.failed => (
        'Couldn\'t connect',
        state.message ?? 'Check the host and your local network',
        'failed',
        AppColors.statusOrange,
        Icons.warning_amber_rounded,
      ),
      ConnectStatus.disconnected => (
        'Host connection lost',
        state.message ?? 'Choose a local model or reconnect',
        'disconnected',
        AppColors.statusOrange,
        Icons.warning_amber_rounded,
      ),
      _ => ('', '', 'other', AppColors.primaryAccent, Icons.desktop_windows_outlined),
    };
  }

  @override
  Widget build(BuildContext context) {
    final key = _key;
    final visible = key != null && key != _dismissedKey;
    final (title, subtitle, _, tint, icon) = _presentation;
    return AnimatedSlide(
      duration: const Duration(milliseconds: 220),
      offset: visible ? Offset.zero : const Offset(0, -1.2),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: visible ? 1 : 0,
        child: IgnorePointer(
          ignoring: !visible,
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            elevation: 8,
            child: ListTile(
              leading: Icon(icon, color: tint),
              title: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                onPressed: () => setState(() => _dismissedKey = key),
                icon: const Icon(Icons.close),
                tooltip: 'Dismiss Connect status',
              ),
            ),
          ),
        ),
      ),
    );
  }
}
