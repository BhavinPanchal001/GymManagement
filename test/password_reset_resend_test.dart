import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym/screens/auth/forgot_password_sheet.dart';

class ResetAuthPlatform extends FirebaseAuthPlatform {
  final sentTo = <String>[];
  bool fail = false;
  @override
  FirebaseAuthPlatform delegateFor({required FirebaseApp app}) => this;
  @override
  FirebaseAuthPlatform setInitialValues({
    PigeonUserDetails? currentUser,
    String? languageCode,
  }) => this;
  @override
  Future<void> sendPasswordResetEmail(
    String email, [
    ActionCodeSettings? actionCodeSettings,
  ]) async {
    sentTo.add(email);
    if (fail) throw FirebaseAuthException(code: 'network-request-failed');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final auth = ResetAuthPlatform();
  setUpAll(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
    FirebaseAuthPlatform.instance = auth;
  });
  setUp(() {
    auth.sentTo.clear();
    auth.fail = false;
  });

  testWidgets(
    'successful reset can resend after cooldown without a mounted form',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ForgotPasswordSheet(initialEmail: ' owner@example.com '),
          ),
        ),
      );
      await tester.tap(find.text('Send Reset Instructions'));
      await tester.pumpAndSettle();
      expect(find.text('Reset Link Sent!'), findsOneWidget);
      expect(auth.sentTo, ['owner@example.com']);
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Resend email'));
      await tester.pumpAndSettle();
      expect(auth.sentTo, ['owner@example.com', 'owner@example.com']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('resend failure shows error and allows retry', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ForgotPasswordSheet(initialEmail: 'owner@example.com'),
        ),
      ),
    );
    await tester.tap(find.text('Send Reset Instructions'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
    auth.fail = true;
    await tester.tap(find.text('Resend email'));
    await tester.pumpAndSettle();
    expect(
      find.text('Network error. Please check your internet connection.'),
      findsOneWidget,
    );
    auth.fail = false;
    await tester.tap(find.text('Send Reset Instructions'));
    await tester.pumpAndSettle();
    expect(find.text('Reset Link Sent!'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
