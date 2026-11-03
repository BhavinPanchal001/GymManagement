import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gym/services/gym_service.dart';
import 'package:gym/screens/billing/pending_members_screen.dart';
import 'package:gym/screens/customers/customers_tab.dart';
import 'package:gym/widgets/pending_member_cards.dart';
import 'package:gym/widgets/pending_member_detail_card.dart';
import 'package:gym/models/attendance.dart';
import 'package:gym/models/payment.dart';
import 'package:gym/theme/app_theme.dart';
import 'package:gym/services/theme_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final gym = GymService();

  setUp(() async {
    await gym.detachUser();
    SharedPreferences.setMockInitialValues({});
    await gym.init();
    await gym.clearAllGymData();
    for (final day in [5, 15, 25]) {
      await gym.addCustomer(
        name: 'Member $day',
        phone: '98765432$day',
        joinDate: DateTime(2026, 9, day),
        membershipStartDate: DateTime(2026, 9, day),
        membershipFee: day * 100,
      );
    }
  });
  tearDown(() => gym.detachUser());

  test(
    'exact-date dues refresh after a partial and final collection',
    () async {
      final member = gym.customers.singleWhere((c) => c.name == 'Member 15');
      final date = DateTime(2026, 9, 15);
      expect(
        gym
            .getPendingDuesByMember(date, date, exactDates: true)
            .single
            .totalPendingAmount,
        1500,
      );
      final bill = await gym.markPaymentAsPaid(
        customerId: member.id,
        monthYear: '2026-09',
        method: PaymentMethod.cash,
        amount: 500,
        totalDue: 1500,
        startDate: date,
        agreementId: gym.getCustomerPaymentHistory(member.id).single.id,
      );
      expect(
        gym
            .getPendingDuesByMember(date, date, exactDates: true)
            .single
            .totalPendingAmount,
        1000,
      );
      expect(
        gym
            .getPendingDuesByMonth(date, date, exactDates: true)
            .single
            .totalAmount,
        1000,
      );
      await gym.collectBalance(
        paymentId: bill.paymentId,
        amount: 1000,
        method: PaymentMethod.cash,
      );
      expect(gym.getPendingDuesByMember(date, date, exactDates: true), isEmpty);
      expect(gym.getPendingDuesByMonth(date, date, exactDates: true), isEmpty);
    },
  );

  testWidgets('balance breakdown includes credit as well as cash received', (
    tester,
  ) async {
    final member = gym.customers.singleWhere((c) => c.name == 'Member 15');
    final record = gym
        .getCustomerPaymentHistory(member.id)
        .single
        .copyWith(status: PaymentStatus.paid, amount: 500, creditApplied: 200);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PendingMemberDetailCard(
            summary: MemberPendingSummary(
              customer: member,
              pendingRecords: [record],
              totalPendingAmount: record.balanceDue,
            ),
            startDate: DateTime(2026, 9, 1),
            endDate: DateTime(2026, 9, 30),
            currency: '₹',
            onCall: () {},
            onReminder: () {},
            onCollect: () {},
            onOpenMember: () {},
          ),
        ),
      ),
    );
    expect(find.text('Billed ₹1,500'), findsOneWidget);
    expect(find.text('Received ₹500'), findsOneWidget);
    expect(find.text('Credit ₹200'), findsOneWidget);
    expect(find.text('₹800'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing dues order does not skip unseen members', (
    tester,
  ) async {
    var ids = ['a', 'b', 'c'];
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return PendingMemberCards(
                memberIds: ids,
                cardBuilder: (_, index) => Text('Member ${ids[index]}'),
              );
            },
          ),
        ),
      ),
    );
    // A partial payment moves the current member below two unseen members.
    update(() => ids = ['b', 'c', 'a']);
    await tester.pumpAndSettle();
    final front = find.byKey(const ValueKey('pending-card-drag'));
    expect(
      find.descendant(of: front, matching: find.text('Member a')),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Next member'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: front, matching: find.text('Member b')),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Next member'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: front, matching: find.text('Member c')),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Bring back previous card'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: front, matching: find.text('Member b')),
      findsOneWidget,
    );
  });

  testWidgets('refresh preserves completion and new members enter the deck', (
    tester,
  ) async {
    var ids = ['a'];
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return PendingMemberCards(
                memberIds: ids,
                cardBuilder: (_, index) => Text('Member ${ids[index]}'),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Next member'));
    await tester.pumpAndSettle();
    update(() {});
    await tester.pumpAndSettle();
    expect(find.text('You’ve viewed all pending members'), findsOneWidget);
    update(() => ids = ['b', 'a']);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pending-card-drag')),
        matching: find.text('Member b'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'left arrow restores swiped cards in order and after the last card',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PendingMemberCards(
              memberIds: const ['a', 'b', 'c'],
              cardBuilder: (_, index) =>
                  Text('Member ${['a', 'b', 'c'][index]}'),
            ),
          ),
        ),
      );
      final restore = find.byTooltip('Bring back previous card');
      IconButton button() => tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.arrow_back_rounded),
      );
      expect(button().onPressed, isNull);
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byTooltip('Next member'));
        await tester.pumpAndSettle();
      }
      expect(find.text('3 of 3 · Swipe to browse'), findsOneWidget);
      for (final expected in [2, 1]) {
        await tester.tap(restore);
        await tester.pumpAndSettle();
        expect(find.text('$expected of 3 · Swipe to browse'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('pending-card-drag')),
            matching: find.text('Member ${expected == 1 ? 'a' : 'b'}'),
          ),
          findsOneWidget,
        );
      }
      expect(button().onPressed, isNull);
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byTooltip('Next member'));
        await tester.pumpAndSettle();
      }
      expect(find.text('You’ve viewed all pending members'), findsOneWidget);
      await tester.tap(restore);
      await tester.pumpAndSettle();
      expect(find.text('3 of 3 · Swipe to browse'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cleared bills are removed from swipe history', (tester) async {
    var ids = ['a', 'b', 'c'];
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return PendingMemberCards(
                memberIds: ids,
                cardBuilder: (_, index) => Text(ids[index]),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Next member'));
    await tester.pumpAndSettle();
    update(() => ids = ['b', 'c']);
    await tester.pumpAndSettle();
    final button = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.arrow_back_rounded),
    );
    expect(button.onPressed, isNull);
    expect(find.text('1 of 2 · Swipe to browse'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'member app bar opens cards and back returns to the member list',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: CustomersTab()));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Pending member cards'));
      await tester.pumpAndSettle();
      expect(find.byType(PendingMembersScreen), findsOneWidget);
      expect(find.byType(PendingMemberCards), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(PendingMembersScreen), findsNothing);
      expect(find.text('Gym Members'), findsOneWidget);
      expect(find.byTooltip('Pending member cards'), findsOneWidget);
    },
  );

  testWidgets('empty date ranges keep the picker available', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PendingMembersScreen(
          initialRange: DateTimeRange(
            start: DateTime(2020, 1, 1),
            end: DateTime(2020, 1, 31),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No pending bills'), findsOneWidget);
    expect(find.byType(PendingMemberCards), findsNothing);
    await tester.tap(find.byTooltip('Select date range'));
    await tester.pumpAndSettle();
    expect(find.byType(DateRangePickerDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('focused page fits a small phone in $mode', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await ThemeService().setThemeMode(mode);
      addTearDown(() => ThemeService().setThemeMode(ThemeMode.light));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: mode,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: const PendingMembersScreen(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PendingMemberCards), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'detail card shows range attendance and partial payment amounts',
    (tester) async {
      final member = gym.customers.singleWhere((c) => c.name == 'Member 15');
      await gym.markPaymentAsPaid(
        customerId: member.id,
        monthYear: '2026-09',
        method: PaymentMethod.cash,
        amount: 500,
        totalDue: 1500,
        startDate: DateTime(2026, 9, 15),
        agreementId: gym.getCustomerPaymentHistory(member.id).single.id,
      );
      await gym.toggleAttendance(
        member.id,
        '2026-09-15',
        AttendanceStatus.present,
      );
      await gym.toggleAttendance(
        member.id,
        '2026-09-16',
        AttendanceStatus.absent,
      );
      await gym.toggleAttendance(
        member.id,
        '2026-09-17',
        AttendanceStatus.rest,
      );
      await gym.toggleAttendance(
        member.id,
        '2026-09-18',
        AttendanceStatus.present,
      );
      final start = DateTime(2026, 9, 15);
      final end = DateTime(2026, 9, 17);
      final summary = gym
          .getPendingDuesByMember(start, end, exactDates: true)
          .single;
      var collected = false;
      var called = false;
      var reminded = false;
      var opened = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PendingMemberDetailCard(
                summary: summary,
                startDate: start,
                endDate: end,
                currency: '₹',
                onCollect: () => collected = true,
                onReminder: () => reminded = true,
                onCall: () => called = true,
                onOpenMember: () => opened = true,
              ),
            ),
          ),
        ),
      );
      for (final label in ['Total present', 'Absent', 'Rest days']) {
        expect(
          find.descendant(
            of: find.byKey(ValueKey('attendance-$label')),
            matching: find.text('1'),
          ),
          findsOneWidget,
        );
      }
      expect(find.text('₹1,000'), findsOneWidget);
      expect(find.text('Received ₹500'), findsOneWidget);
      expect(find.text('Billed ₹1,500'), findsOneWidget);
      expect(find.text('Full profile'), findsNothing);
      await tester.tap(find.byTooltip('View member details'));
      expect(opened, isTrue);
      await tester.ensureVisible(find.text('Collect balance'));
      await tester.tap(find.text('Collect balance'));
      await tester.tap(find.text('Call'));
      await tester.tap(find.text('Remind'));
      expect(collected && called && reminded, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'exact range includes both boundary days and separates cached ranges',
    () {
      final start = DateTime(2026, 9, 5);
      final end = DateTime(2026, 9, 15);
      final dues = gym.getPendingDuesByMember(start, end, exactDates: true);
      expect(
        dues.map((m) => m.customer.name),
        unorderedEquals(['Member 5', 'Member 15']),
      );
      expect(
        dues.fold<double>(0, (sum, m) => sum + m.totalPendingAmount),
        2000,
      );
      expect(gym.getPendingDuesByMember(start, end).length, 3);
      final oneDay = gym.getPendingDuesByMember(end, end, exactDates: true);
      expect(oneDay.single.customer.name, 'Member 15');
      final groups = gym.getPendingDuesByMonth(start, end, exactDates: true);
      expect(groups.single.items.length, 2);
      expect(groups.single.totalAmount, 2000);
    },
  );

  testWidgets('dedicated page has only a date selector and swipe cards', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: PendingMembersScreen()));
    await tester.pumpAndSettle();
    expect(find.byType(PendingMemberCards), findsOneWidget);
    expect(find.text('1 of 3 · Swipe to browse'), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('pending-card-drag')),
      const Offset(-600, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 of 3 · Swipe to browse'), findsOneWidget);
    await tester.tap(find.byTooltip('Next member'));
    await tester.pumpAndSettle();
    expect(find.text('3 of 3 · Swipe to browse'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('By Member'), findsNothing);
    expect(find.byIcon(Icons.share_outlined), findsNothing);
    await tester.tap(find.byTooltip('Select date range'));
    await tester.pumpAndSettle();
    expect(find.byType(DateRangePickerDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'clearing the last current bill finishes an already reviewed deck',
    (tester) async {
      var ids = ['a', 'b', 'c'];
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return PendingMemberCards(
                  memberIds: ids,
                  cardBuilder: (_, index) => Text('Member ${ids[index]}'),
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Next member'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Next member'));
      await tester.pumpAndSettle();
      update(() => ids = ['a', 'b']);
      await tester.pumpAndSettle();
      expect(find.text('You’ve viewed all pending members'), findsOneWidget);
      await tester.tap(find.byTooltip('Bring back previous card'));
      await tester.pumpAndSettle();
      expect(find.text('2 of 2 · Swipe to browse'), findsOneWidget);
      expect(find.text('Member b'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('applying picker dates filters the cards within a single month', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: PendingMembersScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Select date range'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Switch to input'));
    await tester.pumpAndSettle();
    final dateFields = find.descendant(
      of: find.byType(DateRangePickerDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(dateFields.at(0), '09/05/2026');
    await tester.enterText(dateFields.at(1), '09/15/2026');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byType(DateRangePickerDialog), findsNothing);
    expect(find.text('1 of 2 · Swipe to browse'), findsOneWidget);
    final cards = tester.widget<PendingMemberCards>(
      find.byType(PendingMemberCards),
    );
    final expected = gym.customers
        .where((c) => c.name != 'Member 25')
        .map((c) => c.id);
    expect(cards.memberIds, unorderedEquals(expected));
    expect(tester.takeException(), isNull);
  });

  testWidgets('deck snaps back, swipes either way, and can be reviewed again', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PendingMemberCards(
            memberIds: const ['a', 'b'],
            cardBuilder: (_, index) =>
                SizedBox(height: 1000, child: Text('Card $index')),
          ),
        ),
      ),
    );
    final front = find.byKey(const ValueKey('pending-card-drag'));
    final start = tester.getCenter(front);
    final gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(80, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    expect(tester.getCenter(front).dx, greaterThan(start.dx));
    await tester.pump(const Duration(seconds: 1));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.getCenter(front).dx, closeTo(start.dx, 1));
    expect(find.text('1 of 2 · Swipe to browse'), findsOneWidget);

    // The deck has no internal vertical scrolling.
    expect(
      find.descendant(of: front, matching: find.byType(Scrollable)),
      findsNothing,
    );
    await tester.drag(front, const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(find.text('1 of 2 · Swipe to browse'), findsOneWidget);
    await tester.drag(front, const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(find.text('2 of 2 · Swipe to browse'), findsOneWidget);
    await tester.drag(front, const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('You’ve viewed all pending members'), findsOneWidget);
    await tester.tap(find.text('Review again'));
    await tester.pumpAndSettle();
    expect(find.text('1 of 2 · Swipe to browse'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
