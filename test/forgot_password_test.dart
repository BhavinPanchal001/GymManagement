import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym/screens/auth/auth_screen.dart';
import 'package:gym/screens/auth/forgot_password_sheet.dart';
import 'package:gym/services/auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthService - Password Reset and Error Messages', () {
    test('sendPasswordResetEmail throws clean error if email is empty', () async {
      expect(
        () => AuthService().sendPasswordResetEmail(email: '   '),
        throwsA(
          isA<FirebaseAuthException>().having(
            (e) => e.code,
            'code',
            'missing-email',
          ),
        ),
      );
    });

    test('getReadableErrorMessage maps FirebaseAuthException codes properly', () {
      final auth = AuthService();

      expect(
        auth.getReadableErrorMessage(
          FirebaseAuthException(code: 'user-not-found'),
        ),
        'No account found with this email.',
      );

      expect(
        auth.getReadableErrorMessage(
          FirebaseAuthException(code: 'invalid-email'),
        ),
        'Please enter a valid email address.',
      );

      expect(
        auth.getReadableErrorMessage(
          FirebaseAuthException(code: 'missing-email'),
        ),
        'Please enter your email address.',
      );

      expect(
        auth.getReadableErrorMessage(
          FirebaseAuthException(code: 'quota-exceeded'),
        ),
        'Email quota exceeded. Please try again later.',
      );

      expect(
        auth.getReadableErrorMessage(
          FirebaseAuthException(code: 'network-request-failed'),
        ),
        'Network error. Please check your internet connection.',
      );

      expect(
        auth.getReadableErrorMessage(
          FirebaseAuthException(code: 'invalid-api-key'),
        ),
        contains('Firebase API key is not configured'),
      );
    });

    test('getReadableErrorMessage maps FirebaseException properly', () {
      final auth = AuthService();

      expect(
        auth.getReadableErrorMessage(
          FirebaseException(
            plugin: 'firebase_auth',
            message: 'Firebase has not been initialized.',
          ),
        ),
        'Firebase service is not initialized. Please ensure your project is properly configured.',
      );
    });
  });

  group('ForgotPasswordSheet UI & Interactions', () {
    testWidgets('displays with initial email if provided', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ForgotPasswordSheet(initialEmail: 'owner@fitness.com'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Reset Password'), findsOneWidget);
      expect(find.text('owner@fitness.com'), findsOneWidget);
      expect(find.byIcon(Icons.clear_rounded), findsOneWidget);
    });

    testWidgets('clear button clears text in email field', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ForgotPasswordSheet(initialEmail: 'clearme@example.com'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('clearme@example.com'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.clear_rounded));
      await tester.pumpAndSettle();

      expect(find.text('clearme@example.com'), findsNothing);
      expect(find.byIcon(Icons.clear_rounded), findsNothing);
    });

    testWidgets('validates empty email field', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ForgotPasswordSheet(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Send Reset Instructions'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter your email'), findsOneWidget);
    });

    testWidgets('validates invalid email format', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ForgotPasswordSheet(initialEmail: 'notanemail'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Send Reset Instructions'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a valid email address'), findsOneWidget);
    });

    testWidgets('accepts valid email with plus alias (e.g. user+gym@gmail.com)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ForgotPasswordSheet(initialEmail: 'user+gym@gmail.com'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Send Reset Instructions'));
      await tester.pump();

      // Form validation passed, so 'Please enter a valid email address' should NOT appear
      expect(find.text('Please enter a valid email address'), findsNothing);
    });

    testWidgets('tapping Forgot Password button in AuthScreen opens sheet and syncs back email', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AuthScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Enter an email in the sign in email field
      final signInEmailField = find.widgetWithText(TextFormField, 'Email Address');
      expect(signInEmailField, findsOneWidget);
      await tester.enterText(signInEmailField, 'gymboss@example.com');
      await tester.pumpAndSettle();

      // Tap 'Forgot Password?'
      await tester.tap(find.text('Forgot Password?'));
      await tester.pumpAndSettle();

      // Verify the ForgotPasswordSheet is displayed with the initial email
      expect(find.byType(ForgotPasswordSheet), findsOneWidget);
      expect(find.text('gymboss@example.com'), findsNWidgets(2)); // in AuthScreen behind and in sheet

      // Tap close button on sheet
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(find.byType(ForgotPasswordSheet), findsNothing);
      expect(find.byType(AuthScreen), findsOneWidget);
    });
  });
}
