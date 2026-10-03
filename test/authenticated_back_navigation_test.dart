import 'dart:async';
import 'dart:io';

import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym/screens/auth/auth_gate.dart';
import 'package:gym/screens/auth/auth_screen.dart';
import 'package:gym/screens/billing/expense_tab.dart';
import 'package:gym/screens/home_screen.dart';
import 'package:gym/services/gym_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _AuthPlatform extends FirebaseAuthPlatform {
  final events = StreamController<UserPlatform?>.broadcast(sync: true);
  UserPlatform? user;

  void changeUser(String? uid) {
    user = uid == null ? null : _User(this, uid);
    events.add(user);
  }

  @override
  FirebaseAuthPlatform delegateFor({required FirebaseApp app}) => this;

  @override
  FirebaseAuthPlatform setInitialValues({
    PigeonUserDetails? currentUser,
    String? languageCode,
  }) => this;

  @override
  UserPlatform? get currentUser => user;

  @override
  Stream<UserPlatform?> authStateChanges() async* {
    // Each request returns a new stream, just like FirebaseAuth does.
    yield user;
    yield* events.stream;
  }
}

class _MultiFactor extends MultiFactorPlatform {
  _MultiFactor(super.auth);
}

class _User extends UserPlatform {
  _User(FirebaseAuthPlatform auth, String uid)
    : super(
        auth,
        _MultiFactor(auth),
        PigeonUserDetails(
          userInfo: PigeonUserInfo(
            uid: uid,
            displayName: 'Test Owner',
            isAnonymous: false,
            isEmailVerified: true,
          ),
          providerData: [],
        ),
      );
}

Future<void> _selectTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

int _selectedTab(WidgetTester tester) =>
    tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final auth = _AuthPlatform();
  final gym = GymService();

  setUpAll(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
    FirebaseAuthPlatform.instance = auth;
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
    SharedPreferences.setMockInitialValues({});
    await gym.detachUser();
    await gym.init();
    auth.changeUser('navigation-test-owner');
  });

  tearDown(() => gym.detachUser());
  tearDownAll(() => auth.events.close());

  Future<ValueNotifier<int>> openApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final rebuild = ValueNotifier<int>(0);
    addTearDown(rebuild.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<int>(
          valueListenable: rebuild,
          builder: (_, value, child) => AuthGate(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    return rebuild;
  }

  testWidgets('signed-in rebuild preserves selected tab and back history', (
    tester,
  ) async {
    final rebuild = await openApp(tester);
    final home = tester.state(find.byType(HomeScreen));
    await _selectTab(tester, 'Attendance');
    await _selectTab(tester, 'Payments');
    await _selectTab(tester, 'Settings');
    rebuild.value++;
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(HomeScreen)), same(home));
    expect(_selectedTab(tester), 3);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_selectedTab(tester), 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('report back restores Payments after signed-in parent rebuild', (
    tester,
  ) async {
    final rebuild = await openApp(tester);
    await _selectTab(tester, 'Attendance');
    await _selectTab(tester, 'Payments');
    await tester.tap(find.byTooltip('Pending Dues Report'));
    await tester.pumpAndSettle();
    rebuild.value++;
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_selectedTab(tester), 2);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_selectedTab(tester), 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('same-user auth events retain Payments section history', (
    tester,
  ) async {
    final rebuild = await openApp(tester);
    await _selectTab(tester, 'Payments');
    await tester.tap(find.text('Expenses'));
    await tester.pumpAndSettle();
    auth.changeUser('navigation-test-owner');
    rebuild.value++;
    await tester.pumpAndSettle();
    expect(find.byType(ExpenseTab), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_selectedTab(tester), 2);
    expect(find.byType(ExpenseTab), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('real sign out still replaces the signed-in screen', (
    tester,
  ) async {
    await openApp(tester);
    await _selectTab(tester, 'Settings');
    auth.changeUser(null);
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsNothing);
    expect(find.byType(AuthScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
