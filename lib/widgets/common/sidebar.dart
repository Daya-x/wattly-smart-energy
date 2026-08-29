import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/dashboard_provider.dart';

class Sidebar extends StatelessWidget {
  final int selectedIndex;

  const Sidebar({super.key, this.selectedIndex = 0});

  static const _routes = [
    '/',
    '/ai',
    '/history',
    '/recharge',
    '/alerts',
    '/simulations',
    '/settings',
  ];

  void _navigate(BuildContext context, int index) {
    if (index == selectedIndex) return;
    Navigator.of(context).pushReplacementNamed(_routes[index]);
  }

  @override
  Widget build(BuildContext context) {
    final alertCount = context
        .watch<DashboardProvider>()
        .unacknowledgedAlertCount;
    final user = Firebase.apps.isEmpty
        ? null
        : FirebaseAuth.instance.currentUser;
    final email = user?.email ?? 'Device Meter';
    final initials = email.contains('@')
        ? email.substring(0, 1).toUpperCase()
        : 'DM';
    return Container(
      width: 260,
      decoration: const BoxDecoration(
        color: AppColors.cardNavy,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 28, 18, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                _Logo(),
                SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'WATTLY',
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                      ),
                    ),
                    Text(
                      'SMART ENERGY',
                      style: TextStyle(
                        color: AppColors.textGrey,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 42),
          const _Label('OVERVIEW'),
          _MenuItem(
            icon: Icons.grid_view_rounded,
            title: 'Dashboard',
            selected: selectedIndex == 0,
            onTap: () => _navigate(context, 0),
          ),
          _MenuItem(
            icon: Icons.auto_awesome_rounded,
            title: 'AI Insights',
            selected: selectedIndex == 1,
            onTap: () => _navigate(context, 1),
          ),
          _MenuItem(
            icon: Icons.query_stats_rounded,
            title: 'Usage history',
            selected: selectedIndex == 2,
            onTap: () => _navigate(context, 2),
          ),
          const SizedBox(height: 22),
          const _Label('MANAGE'),
          _MenuItem(
            icon: Icons.account_balance_wallet_outlined,
            title: 'Recharge',
            selected: selectedIndex == 3,
            onTap: () => _navigate(context, 3),
          ),
          _MenuItem(
            icon: Icons.notifications_none_rounded,
            title: 'Alerts',
            badge: alertCount == 0 ? null : '$alertCount',
            selected: selectedIndex == 4,
            onTap: () => _navigate(context, 4),
          ),
          _MenuItem(
            icon: Icons.science_outlined,
            title: 'Simulations',
            selected: selectedIndex == 5,
            onTap: () => _navigate(context, 5),
          ),
          _MenuItem(
            icon: Icons.tune_rounded,
            title: 'Settings',
            selected: selectedIndex == 6,
            onTap: () => _navigate(context, 6),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.lightCard,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppColors.neonGreen,
                  child: Text(
                    initials,
                    style: const TextStyle(
                      color: AppColors.darkNavy,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        email,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'ID • EM-2048',
                        style: TextStyle(
                          color: AppColors.textGrey,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                if (user != null)
                  IconButton(
                    tooltip: 'Sign out',
                    onPressed: () => FirebaseAuth.instance.signOut(),
                    icon: const Icon(
                      Icons.logout_rounded,
                      size: 18,
                      color: AppColors.textGrey,
                    ),
                  )
                else
                  const Icon(
                    Icons.more_horiz,
                    size: 18,
                    color: AppColors.textGrey,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 12, bottom: 10),
    child: Text(
      text,
      style: const TextStyle(
        color: AppColors.textGrey,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
      ),
    ),
  );
}

class _Logo extends StatelessWidget {
  const _Logo();
  @override
  Widget build(BuildContext context) => Container(
    width: 40,
    height: 40,
    decoration: BoxDecoration(
      color: AppColors.neonGreen,
      borderRadius: BorderRadius.circular(12),
    ),
    child: const Icon(Icons.bolt_rounded, color: AppColors.darkNavy, size: 24),
  );
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool selected;
  final String? badge;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.title,
    required this.onTap,
    this.selected = false,
    this.badge,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Material(
      color: selected
          ? AppColors.neonGreen.withValues(alpha: .10)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: selected
                ? Border.all(color: AppColors.neonGreen.withValues(alpha: .18))
                : null,
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: selected ? AppColors.neonGreen : AppColors.textGrey,
                size: 20,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: selected ? AppColors.white : AppColors.textGrey,
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
              if (badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.warningRed.withValues(alpha: .15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    badge!,
                    style: const TextStyle(
                      color: AppColors.warningRed,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
