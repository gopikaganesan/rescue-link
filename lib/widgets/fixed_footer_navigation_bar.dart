import 'package:animated_bottom_navigation_bar/animated_bottom_navigation_bar.dart';
import 'package:flutter/material.dart';

class FixedFooterNavigationBar extends StatelessWidget {
  final int activeIndex;
  final bool showPeople;
  final VoidCallback onSosTap;
  final VoidCallback onPeopleTap;
  final VoidCallback onChatsTap;
  final VoidCallback onMapTap;
  final VoidCallback onProfileTap;

  const FixedFooterNavigationBar({
    super.key,
    required this.activeIndex,
    this.showPeople = true,
    required this.onSosTap,
    required this.onPeopleTap,
    required this.onChatsTap,
    required this.onMapTap,
    required this.onProfileTap,
  });

  @override
  Widget build(BuildContext context) {
    final icons = showPeople
        ? const [
            Icons.sos,
            Icons.support_agent,
            Icons.chat,
            Icons.map,
            Icons.account_circle,
          ]
        : const [
            Icons.sos,
            Icons.chat,
            Icons.map,
            Icons.account_circle,
          ];

    return AnimatedBottomNavigationBar(
      icons: icons,
      activeIndex: activeIndex,
      gapLocation: GapLocation.none,
      notchSmoothness: NotchSmoothness.verySmoothEdge,
      backgroundColor: Colors.red.shade700,
      activeColor: Colors.white,
      inactiveColor: Colors.white70,
      onTap: (index) {
        if (index == activeIndex) {
          return;
        }

        if (index == 0) {
          onSosTap();
          return;
        }

        if (showPeople) {
          if (index == 1) {
            onPeopleTap();
            return;
          }

          if (index == 2) {
            onChatsTap();
            return;
          }

          if (index == 3) {
            onMapTap();
            return;
          }

          onProfileTap();
          return;
        }

        if (index == 1) {
          onChatsTap();
          return;
        }

        if (index == 2) {
          onMapTap();
          return;
        }

        onProfileTap();
      },
    );
  }
}
