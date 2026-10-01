import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import 'gym_service.dart';

/// Outcome of a Razorpay Checkout attempt.
class RazorpayPaymentResult {
  final bool success;
  final bool cancelled;
  final String? paymentId;
  final String? orderId;
  final String? signature;
  final String? errorMessage;

  const RazorpayPaymentResult._({
    required this.success,
    this.cancelled = false,
    this.paymentId,
    this.orderId,
    this.signature,
    this.errorMessage,
  });

  factory RazorpayPaymentResult.paid({
    String? paymentId,
    String? orderId,
    String? signature,
  }) =>
      RazorpayPaymentResult._(
        success: true,
        paymentId: paymentId,
        orderId: orderId,
        signature: signature,
      );

  factory RazorpayPaymentResult.failed(String message) =>
      RazorpayPaymentResult._(success: false, errorMessage: message);

  factory RazorpayPaymentResult.userCancelled() =>
      const RazorpayPaymentResult._(success: false, cancelled: true);
}

/// Wraps the Razorpay Checkout SDK to collect membership fees online.
///
/// The plugin only supports Android and iOS; on other platforms every call
/// fails fast with a readable error instead of a MissingPluginException.
/// The Key ID is configured by the owner in Settings. This app has no server,
/// so payments are collected without a server-created order and the payment id
/// returned by Checkout is stored on the payment record as the transaction ref.
class RazorpayService {
  RazorpayService._();
  static final RazorpayService _instance = RazorpayService._();
  factory RazorpayService() => _instance;

  Razorpay? _razorpay;
  Completer<RazorpayPaymentResult>? _pending;

  /// Checkout only runs on Android/iOS.
  bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// A Key ID has been saved in Settings.
  bool get isConfigured => GymService().settings.hasRazorpayKey;

  /// Ready to collect: supported platform + configured key.
  bool get isAvailable => isSupported && isConfigured;

  /// Opens Razorpay Checkout for [amountInr] (in rupees) and resolves once the
  /// member pays, fails, or dismisses checkout.
  Future<RazorpayPaymentResult> collectPayment({
    required double amountInr,
    required String description,
    String? memberName,
    String? contact,
    String? email,
  }) async {
    if (!isSupported) {
      return RazorpayPaymentResult.failed(
        'Online payments are only available on Android and iOS.',
      );
    }
    final keyId = GymService().settings.razorpayKeyId.trim();
    if (keyId.isEmpty) {
      return RazorpayPaymentResult.failed(
        'Add your Razorpay Key ID in Settings to collect payments online.',
      );
    }
    if (!amountInr.isFinite || amountInr <= 0) {
      return RazorpayPaymentResult.failed('Enter a positive amount to collect.');
    }
    if (_pending != null) {
      return RazorpayPaymentResult.failed('A payment is already in progress.');
    }

    final completer = Completer<RazorpayPaymentResult>();
    _pending = completer;
    final razorpay = Razorpay();
    _razorpay = razorpay;

    razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handleSuccess);
    razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handleError);
    razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);

    final gymName = GymService().settings.gymName;
    final options = <String, dynamic>{
      'key': keyId,
      // Amount is in paise (INR subunits).
      'amount': (amountInr * 100).round(),
      'currency': 'INR',
      'name': gymName,
      'description': description,
      'send_sms_hash': true,
      'retry': {'enabled': true, 'max_count': 4},
      'theme': {'color': '#16A34A'},
      'prefill': {
        if (contact != null && contact.isNotEmpty) 'contact': contact,
        if (email != null && email.isNotEmpty) 'email': email,
        if (memberName != null && memberName.isNotEmpty) 'name': memberName,
      },
    };

    try {
      razorpay.open(options);
    } on MissingPluginException {
      _finish(RazorpayPaymentResult.failed(
        'Online payments are not supported on this device.',
      ));
    } catch (_) {
      _finish(RazorpayPaymentResult.failed(
        'Could not open the payment page. Please try again.',
      ));
    }
    return completer.future;
  }

  void _handleSuccess(PaymentSuccessResponse response) {
    _finish(RazorpayPaymentResult.paid(
      paymentId: response.paymentId,
      orderId: response.orderId,
      signature: response.signature,
    ));
  }

  void _handleError(PaymentFailureResponse response) {
    if (response.code == Razorpay.PAYMENT_CANCELLED) {
      _finish(RazorpayPaymentResult.userCancelled());
      return;
    }
    final message = response.message?.trim();
    _finish(RazorpayPaymentResult.failed(
      message != null && message.isNotEmpty
          ? message
          : 'The online payment failed. Please try again.',
    ));
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    final wallet = response.walletName ?? 'the selected wallet';
    _finish(RazorpayPaymentResult.failed(
      'External wallet payments ($wallet) are not supported. Pay by UPI, card, or net banking instead.',
    ));
  }

  void _finish(RazorpayPaymentResult result) {
    final pending = _pending;
    _pending = null;
    _razorpay?.clear();
    _razorpay = null;
    if (pending != null && !pending.isCompleted) {
      pending.complete(result);
    }
  }

  /// Tears down listeners; safe to call when disposing a screen mid-checkout.
  void cancelActiveCheckout() {
    if (_pending != null) {
      _finish(RazorpayPaymentResult.userCancelled());
    }
  }
}
