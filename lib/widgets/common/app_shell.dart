import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'sidebar.dart';

class AppShell extends StatelessWidget {
  final int selectedIndex;
  final String title;
  final String subtitle;
  final Widget child;
  final List<Widget> actions;

  const AppShell({
    super.key,
    required this.selectedIndex,
    required this.title,
    required this.subtitle,
    required this.child,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 1000;
        return Scaffold(
          backgroundColor: AppColors.darkNavy,
          drawer: compact
              ? Drawer(child: Sidebar(selectedIndex: selectedIndex))
              : null,
          body: Row(
            children: [
              if (!compact) Sidebar(selectedIndex: selectedIndex),
              Expanded(
                child: SafeArea(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      compact ? 16 : 30,
                      compact ? 16 : 28,
                      compact ? 16 : 30,
                      30,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (compact) ...[
                          Builder(
                            builder: (context) => Row(
                              children: [
                                IconButton(
                                  onPressed: () =>
                                      Scaffold.of(context).openDrawer(),
                                  icon: const Icon(Icons.menu_rounded),
                                ),
                                const SizedBox(width: 10),
                                const Text(
                                  'WATTLY',
                                  style: TextStyle(
                                    color: AppColors.neonGreen,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: const TextStyle(
                                      color: AppColors.white,
                                      fontSize: 30,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -.7,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    subtitle,
                                    style: const TextStyle(
                                      color: AppColors.textGrey,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!compact && actions.isNotEmpty)
                              Wrap(spacing: 10, children: actions),
                          ],
                        ),
                        if (compact && actions.isNotEmpty) ...[
                          const SizedBox(height: 18),
                          Wrap(spacing: 10, runSpacing: 10, children: actions),
                        ],
                        const SizedBox(height: 28),
                        child,
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class SurfaceCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;

  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(22),
  });

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: AppColors.cardNavy,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.border),
    ),
    child: child,
  );
}

class AppButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool primary;

  const AppButton({
    super.key,
    required this.label,
    required this.icon,
    this.onPressed,
    this.primary = true,
  });

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: onPressed,
    icon: Icon(icon, size: 18),
    label: Text(label),
    style: FilledButton.styleFrom(
      backgroundColor: primary ? AppColors.neonGreen : AppColors.lightCard,
      foregroundColor: primary ? AppColors.darkNavy : AppColors.white,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
