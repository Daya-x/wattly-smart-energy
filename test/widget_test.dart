// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:smart_energy_dashboard/main.dart';
import 'package:smart_energy_dashboard/providers/dashboard_provider.dart';
import 'package:smart_energy_dashboard/screens/ai/ai_page.dart';

void main() {
  testWidgets('dashboard renders core energy information', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const SmartEnergyApp(requireAuthentication: false));
    await tester.pumpAndSettle();

    expect(find.text('Energy overview'), findsOneWidget);
    expect(find.text('Available balance'), findsOneWidget);
    expect(find.text('Voltage'), findsOneWidget);
  });

  testWidgets('sidebar navigates to AI insights', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const SmartEnergyApp(requireAuthentication: false));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AI Insights'));
    await tester.pumpAndSettle();

    expect(find.text('AI forecast sample'), findsOneWidget);
    expect(find.text('Smart safety prediction'), findsOneWidget);
    expect(find.text('Appliance detection'), findsOneWidget);
    expect(find.text('AI detection history'), findsOneWidget);
  });

  test('sensor balance can be updated', () {
    final provider = DashboardProvider();
    provider.updateSensor(provider.sensor.copyWith(balance: 1350));
    expect(provider.sensor.balance, 1350);
  });

  testWidgets('AI features render on mobile without overflow', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => DashboardProvider(),
        child: const MaterialApp(home: AIPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Smart safety prediction'), findsOneWidget);
    expect(find.text('Appliance detection'), findsOneWidget);
  });
}
