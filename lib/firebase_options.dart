// File generated or configured for Firebase.
// To regenerate with your actual Firebase project credentials, run:
//   flutterfire configure
// Or replace the placeholder values below with your Firebase project keys.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Example:
/// ```dart
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  // NOTE: Replace these placeholder credentials with your Firebase project keys,
  // or run `flutterfire configure` to generate them automatically.
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyA31ouvcxJUGwB0mhdWEntfxKAbc7itUVo',
    appId: '1:646775679663:web:3d99a55fc8868a17e8825a',
    messagingSenderId: '646775679663',
    projectId: 'gym-manager-e2002',
    authDomain: 'gym-manager-e2002.firebaseapp.com',
    storageBucket: 'gym-manager-e2002.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyA31ouvcxJUGwB0mhdWEntfxKAbc7itUVo',
    appId: '1:646775679663:android:3d99a55fc8868a17e8825a',
    messagingSenderId: '646775679663',
    projectId: 'gym-manager-e2002',
    storageBucket: 'gym-manager-e2002.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyPlaceholderIosApiKeyForGymApp',
    appId: '1:1234567890:ios:abcdef123456',
    messagingSenderId: '1234567890',
    projectId: 'gym-manager-app',
    storageBucket: 'gym-manager-app.appspot.com',
    iosBundleId: 'com.example.gym',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyPlaceholderMacosApiKeyForGymApp',
    appId: '1:1234567890:ios:abcdef123456',
    messagingSenderId: '1234567890',
    projectId: 'gym-manager-app',
    storageBucket: 'gym-manager-app.appspot.com',
    iosBundleId: 'com.example.gym',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyA31ouvcxJUGwB0mhdWEntfxKAbc7itUVo',
    appId: '1:646775679663:web:3d99a55fc8868a17e8825a',
    messagingSenderId: '646775679663',
    projectId: 'gym-manager-e2002',
    authDomain: 'gym-manager-e2002.firebaseapp.com',
    storageBucket: 'gym-manager-e2002.firebasestorage.app',
  );
}
