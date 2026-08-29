import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'firebase_options.dart';
import 'providers/dashboard_provider.dart';
import 'screens/ai/ai_page.dart';
import 'screens/alerts/alerts_page.dart';
import 'screens/auth/auth_page.dart';
import 'screens/dashboard/dashboard_page.dart';
import 'screens/history/history_page.dart';
import 'screens/recharge/recharge_page.dart';
import 'screens/settings/settings_page.dart';
import 'screens/simulations/simulations_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const SmartEnergyApp());
}

class SmartEnergyApp extends StatelessWidget {
  final bool requireAuthentication;

  const SmartEnergyApp({super.key, this.requireAuthentication = true});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AI Smart Prepaid Energy Meter',
      theme: AppTheme.darkTheme,
      builder: (context, child) => _AppAccessGate(
        requireAuthentication: requireAuthentication,
        child: child!,
      ),
      home: const DashboardPage(),
      routes: {
        '/ai': (_) => const AIPage(),
        '/history': (_) => const HistoryPage(),
        '/recharge': (_) => const RechargePage(),
        '/alerts': (_) => const AlertsPage(),
        '/simulations': (_) => const SimulationsPage(),
        '/settings': (_) => const SettingsPage(),
      },
    );
  }
}

class _AppAccessGate extends StatelessWidget {
  final bool requireAuthentication;
  final Widget child;

  const _AppAccessGate({
    required this.requireAuthentication,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (!requireAuthentication) return _dashboardProvider(child);
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.data == null) return const AuthPage();
        return _dashboardProvider(child);
      },
    );
  }

  Widget _dashboardProvider(Widget child) => ChangeNotifierProvider(
    create: (_) => DashboardProvider()
      ..loadAIOverview()
      ..loadTariffs()
      ..loadTariffMonitor()
      ..loadAlerts()
      ..loadTheftSecurity()
      ..startDevicePolling(),
    child: child,
  );
}
