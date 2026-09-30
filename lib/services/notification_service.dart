import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/reports/pending_payments_report_screen.dart';
import '../utils/date_utils.dart';
import '../utils/nav_keys.dart';
import 'auth_service.dart';
import 'gym_service.dart';

/// Top-level background message handler required by FirebaseMessaging
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (_) {}
}

class NotificationService {
  NotificationService._internal();
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  String? _fcmToken;
  String? get fcmToken => _fcmToken;

  static const String channelId = 'gym_payment_reminders';
  static const String channelName = 'Pending Payment Reminders';
  static const String channelDescription =
      'Alerts gym owners when members have outstanding payments.';

  static const String _keyLastNotifiedDate = 'last_pending_notification_date';
  static const String _keyLastNotifiedCount = 'last_pending_notification_count';

  /// Initializes local notifications and Firebase Cloud Messaging
  Future<void> init() async {
    if (_isInitialized) return;

    // 1. Initialize local notifications
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings darwinSettings =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        _handlePayload(response.payload);
      },
    );

    // Create notification channel for Android 8.0+
    final androidImplementation = _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidImplementation != null) {
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        channelId,
        channelName,
        description: channelDescription,
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      );
      await androidImplementation.createNotificationChannel(channel);
      await androidImplementation.requestNotificationsPermission();
    }

    // 2. Initialize Firebase Cloud Messaging
    if (Firebase.apps.isNotEmpty) {
      try {
        final messaging = FirebaseMessaging.instance;

        // Request permissions for iOS and Android 13+
        final NotificationSettings settings = await messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        );
        debugPrint('FCM Authorization status: ${settings.authorizationStatus}');

        // iOS foreground presentation
        await messaging.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );

        // Fetch initial token
        try {
          _fcmToken = await messaging.getToken();
          debugPrint('FCM Registration Token: $_fcmToken');
          await _syncTokenToFirestore(_fcmToken);
        } catch (e) {
          debugPrint('Could not retrieve FCM token: $e');
        }

        // Listen for token rotations
        messaging.onTokenRefresh.listen((newToken) {
          _fcmToken = newToken;
          _syncTokenToFirestore(newToken);
        });

        // Set background FCM message handler
        FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

        // Handle foreground push messages
        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          final notification = message.notification;
          if (notification != null) {
            showNotification(
              title: notification.title ?? 'Gym Alert',
              body: notification.body ?? '',
              payload: message.data['route'] ?? 'pending_payments',
            );
          }
        });

        // Handle notification tap when app opened from background
        FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
          _handlePayload(message.data['route'] ?? 'pending_payments');
        });

        // Handle cold boot from terminated state via FCM notification
        final initialMessage = await messaging.getInitialMessage();
        if (initialMessage != null) {
          _handlePayload(initialMessage.data['route'] ?? 'pending_payments');
        }
      } catch (e) {
        debugPrint('FirebaseMessaging setup error: $e');
      }
    }

    _isInitialized = true;
  }

  /// Sync device FCM token to gym owner's document in Firestore
  Future<void> _syncTokenToFirestore(String? token) async {
    if (token == null || token.isEmpty) return;
    final user = AuthService().currentUser;
    if (user != null) {
      try {
        await FirebaseFirestore.instance.collection('gyms').doc(user.uid).set(
          {
            'fcmToken': token,
            'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
            'platform': defaultTargetPlatform.name,
          },
          SetOptions(merge: true),
        );
        debugPrint('FCM token synchronized for owner uid: ${user.uid}');
      } catch (e) {
        debugPrint('Error saving FCM token to Firestore: $e');
      }
    }
  }

  /// Re-sync token when an owner authenticates
  Future<void> onUserAuthenticated(String uid) async {
    if (_fcmToken != null && _fcmToken!.isNotEmpty) {
      await _syncTokenToFirestore(_fcmToken);
    } else {
      try {
        if (Firebase.apps.isNotEmpty) {
          _fcmToken = await FirebaseMessaging.instance.getToken();
          await _syncTokenToFirestore(_fcmToken);
        }
      } catch (_) {}
    }
  }

  /// Displays a local system notification
  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      showWhen: true,
      color: Color(0xFF00E676),
    );

    const DarwinNotificationDetails darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    await _localNotifications.show(
      1001,
      title,
      body,
      notificationDetails,
      payload: payload ?? 'pending_payments',
    );
  }

  /// Checks for pending dues and triggers the notification if needed.
  /// Throttled to once per day, or immediately if new pending dues arise.
  Future<void> checkAndNotifyPendingPayments({bool force = false}) async {
    final gym = GymService();

    // Respect gym owner toggle preference
    if (!gym.settings.isPaymentDueNotificationEnabled) {
      return;
    }

    final now = DateTime.now();
    // Scan up to current month (last 3 months range)
    final summaries = gym.getPendingDuesByMember(
      DateTime(now.year, now.month - 2, 1),
      now,
    );

    if (summaries.isEmpty) {
      return;
    }

    final pendingCount = summaries.length;
    final totalAmount =
        summaries.fold<double>(0.0, (total, s) => total + s.totalPendingAmount);

    final prefs = await SharedPreferences.getInstance();
    final todayKey = GymDateUtils.toDateKey(now);
    final lastNotifiedDate = prefs.getString(_keyLastNotifiedDate);
    final lastNotifiedCount = prefs.getInt(_keyLastNotifiedCount) ?? -1;

    // Throttle: notify once per day unless pending count changed or forced
    if (!force &&
        lastNotifiedDate == todayKey &&
        lastNotifiedCount == pendingCount) {
      return;
    }

    final currency = gym.settings.currencySymbol;
    final formattedAmount =
        GymDateUtils.formatCurrency(totalAmount, symbol: currency);
    final memberPhrase =
        pendingCount == 1 ? '1 Member Has' : '$pendingCount Members Have';

    final title = '⚠️ $memberPhrase Pending Dues';
    final body =
        '$pendingCount ${pendingCount == 1 ? 'member owes' : 'members owe'} a total of $formattedAmount. Tap to review and send reminders.';

    await showNotification(
      title: title,
      body: body,
      payload: 'pending_payments',
    );

    // Save dispatch record
    await prefs.setString(_keyLastNotifiedDate, todayKey);
    await prefs.setInt(_keyLastNotifiedCount, pendingCount);
  }

  /// Handles deep link when notification is tapped
  void _handlePayload(String? payload) {
    if (payload == 'pending_payments') {
      Future.delayed(const Duration(milliseconds: 350), () {
        final nav = rootNavigatorKey.currentState;
        if (nav != null) {
          nav.push(
            MaterialPageRoute(
              builder: (_) => const PendingPaymentsReportScreen(),
            ),
          );
        }
      });
    }
  }
}
