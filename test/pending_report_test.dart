import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gym/services/gym_service.dart';
import 'package:gym/models/payment.dart';
import 'package:gym/screens/reports/pending_payments_report_screen.dart';
import 'package:gym/screens/reports/export_report_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await GymService().resetToDemoData(force: true);
  });

  test('GymService pending dues range operations test', () {
    final gym = GymService();

    final now = DateTime.now();
    final start = DateTime(now.year, now.month - 2, 1);
    final end = DateTime(now.year, now.month + 1, 0);
    final monthKeys = gym.getMonthKeysInRange(start, end);

    expect(monthKeys.first, startsWith(start.year.toString()));
    expect(monthKeys.last, startsWith(end.year.toString()));
    expect(monthKeys.length, 3);

    final memberPending = gym.getPendingDuesByMember(start, end);
    expect(memberPending, isA<List<MemberPendingSummary>>());
    expect(memberPending.isNotEmpty, true);

    for (final summary in memberPending) {
      expect(summary.totalPendingAmount, greaterThan(0));
      expect(summary.pendingRecords.isNotEmpty, true);
    }

    final monthGroups = gym.getPendingDuesByMonth(start, end);
    expect(monthGroups, isA<List<MonthPendingGroup>>());
    expect(monthGroups.isNotEmpty, true);
  });

  testWidgets('PendingPaymentsReportScreen renders preset chips, KPIs and views', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PendingPaymentsReportScreen()));
    await tester.pumpAndSettle();

    // Verify Title and AppBar
    expect(find.text('Pending Dues Report'), findsWidgets);
    expect(find.byIcon(Icons.share_outlined), findsOneWidget);

    // Verify Preset Chips
    expect(find.text('This Month'), findsOneWidget);
    expect(find.text('Last 3 Months'), findsOneWidget);
    expect(find.text('Last 6 Months'), findsOneWidget);
    expect(find.text('This Year'), findsOneWidget);
    expect(find.text('Custom'), findsOneWidget);

    // Verify KPI Card
    expect(find.text('TOTAL PENDING'), findsOneWidget);
    expect(find.text('MEMBERS'), findsOneWidget);
    expect(find.text('MONTHS DUE'), findsOneWidget);

    // Verify View Switcher
    expect(find.text('By Member'), findsOneWidget);
    expect(find.text('By Month'), findsOneWidget);

    // Tap 'By Month' toggle
    await tester.tap(find.text('By Month'));
    await tester.pumpAndSettle();

    // Verify Search Bar is present
    expect(find.byType(TextField), findsOneWidget);

    // Enter search query
    await tester.enterText(find.byType(TextField), 'NonExistentMemberXYZ');
    await tester.pumpAndSettle();

    // Verify empty state appears
    expect(find.text('No Matching Members'), findsOneWidget);
  });

  testWidgets('ExportReportDialog shows CSV and Text options', (tester) async {
    final gym = GymService();
    final start = DateTime(2026, 7, 1);
    final end = DateTime(2026, 9, 30);
    final summaries = gym.getPendingDuesByMember(start, end);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                ExportReportDialog.show(
                  context,
                  startDate: start,
                  endDate: end,
                  memberSummaries: summaries,
                  totalPending: 3600,
                );
              },
              child: const Text('Open Export'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Export'));
    await tester.pumpAndSettle();

    expect(find.text('Export Pending Report'), findsOneWidget);
    expect(find.text('CSV Format'), findsOneWidget);
    expect(find.text('Text Summary'), findsOneWidget);
    expect(find.text('Copy CSV'), findsOneWidget);
    expect(find.text('Copy Text'), findsOneWidget);
  });
}
