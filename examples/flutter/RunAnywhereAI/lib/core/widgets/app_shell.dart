import 'package:flutter/material.dart' hide Icon;
import 'package:go_router/go_router.dart';
import 'package:tabler_icons_next/tabler_icons_next.dart' as tabler;

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  static const _routes = [
    '/home/chat',
    '/home/vision',
    '/home/more',
    '/home/settings',
  ];

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final index = _routes.indexWhere(location.startsWith);
    return index < 0 ? 0 : index;
  }

  @override
  Widget build(BuildContext context) {
    final index = _currentIndex(context);
    final theme = Theme.of(context);
    final activeColor = theme.colorScheme.primary;
    final inactiveColor = theme.colorScheme.onSurfaceVariant;

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => context.go(_routes[i]),
        destinations: [
          _dest('Chat', tabler.MessageCircle(color: inactiveColor), tabler.MessageCircleFilled(color: activeColor)),
          _dest('Vision', tabler.Eye(color: inactiveColor), tabler.EyeFilled(color: activeColor)),
          _dest('More', tabler.LayoutGrid(color: inactiveColor), tabler.LayoutGridFilled(color: activeColor)),
          _dest('Settings', tabler.Settings(color: inactiveColor), tabler.SettingsFilled(color: activeColor)),
        ],
      ),
    );
  }

  NavigationDestination _dest(String label, Widget icon, Widget selectedIcon) {
    return NavigationDestination(
      icon: SizedBox(width: 24, height: 24, child: icon),
      selectedIcon: SizedBox(width: 24, height: 24, child: selectedIcon),
      label: label,
    );
  }
}
