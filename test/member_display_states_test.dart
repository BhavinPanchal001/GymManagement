import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym/models/payment.dart';
import 'package:gym/screens/customers/customer_detail_screen.dart';
import 'package:gym/services/gym_service.dart';
import 'package:gym/widgets/dashboard_metrics_grid.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final gym = GymService();
  setUpAll(() async {
    var directory = File(Platform.resolvedExecutable).parent;
    while (!Directory('${directory.path}/material_fonts').existsSync() &&
        directory.parent.path != directory.path) {
      directory = directory.parent;
    }
    final loader = FontLoader('Roboto');
    for (final weight in ['Regular', 'Bold']) {
      final bytes = await File(
        '${directory.path}/material_fonts/Roboto-$weight.ttf',
      ).readAsBytes();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  });
  setUp(() async {
    await gym.detachUser();
    SharedPreferences.setMockInitialValues({});
    await gym.init();
    await gym.clearAllGymData();
  });
  tearDown(() => gym.detachUser());

  testWidgets('overview starts collapsed and resets when leaving Members', (
    tester,
  ) async {
    Future<void> show(bool active) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DashboardMetricsGrid(isActive: active)),
        ),
      );
      await tester.pumpAndSettle();
    }

    await show(true);
    expect(find.text('Live members'), findsNothing);
    await tester.tap(find.byIcon(Icons.keyboard_arrow_up_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Live members'), findsOneWidget);
    await show(false);
    await show(true);
    expect(find.text('Live members'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('future month payment card says Upcoming instead of Due', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final member = await gym.addCustomer(
      name: 'Future month member',
      phone: '9876543210',
    );
    await tester.pumpWidget(
      MaterialApp(home: CustomerDetailScreen(customerId: member.id)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Next Month'));
    await tester.pumpAndSettle();
    expect(find.text('UPCOMING'), findsOneWidget);
    expect(find.text('DUE'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('payment history displays the gap between settled cycles', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final member = await gym.addCustomer(
      name: 'Break member',
      phone: '9876543210',
      joinDate: DateTime(2020, 8, 5),
    );
    for (final period in [
      (DateTime(2020, 8, 5), DateTime(2020, 9, 4)),
      (DateTime(2020, 9, 20), DateTime(2020, 10, 19)),
    ]) {
      await gym.markPaymentAsPaid(
        customerId: member.id,
        monthYear:
            '${period.$1.year}-${period.$1.month.toString().padLeft(2, '0')}',
        method: PaymentMethod.cash,
        amount: 600,
        totalDue: 600,
        startDate: period.$1,
        endDate: period.$2,
      );
    }
    await tester.pumpWidget(
      MaterialApp(home: CustomerDetailScreen(customerId: member.id)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Membership gap ? 15 days'), findsOneWidget);
    expect(
      find.text('No attendance recorded between paid cycles'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
