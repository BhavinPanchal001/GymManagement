import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'gym_service.dart';

class AuthService {
  AuthService._internal();
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;

  static const String _keyProfilePhoto = 'gym_auth_profile_photo';
  static const String _keyProfileDisplayName = 'gym_auth_profile_display_name';
  static const String _keyProfilePhone = 'gym_auth_profile_phone';
  static const String _keyRememberMe = 'gym_auth_remember_me';
  static const String _keySavedEmail = 'gym_auth_saved_email';
  static const String _keySavedPassword = 'gym_auth_saved_password';

  String _photoKey(String? uid) => (uid != null && uid.isNotEmpty) ? 'gym_${uid}_profile_photo' : _keyProfilePhoto;
  String _nameKey(String? uid) => (uid != null && uid.isNotEmpty) ? 'gym_${uid}_profile_display_name' : _keyProfileDisplayName;
  String _phoneKey(String? uid) => (uid != null && uid.isNotEmpty) ? 'gym_${uid}_profile_phone' : _keyProfilePhone;

  final ValueNotifier<int> profileNotifier = ValueNotifier<int>(0);

  String? _cachedPhotoPath;
  String? _cachedDisplayName;
  String? _cachedPhone;
  bool _isInitialized = false;

  FirebaseAuth? get _auth {
    try {
      return FirebaseAuth.instance;
    } catch (_) {
      return null;
    }
  }

  /// Initialize and load cached profile
  Future<void> init() async {
    if (_isInitialized) return;
    try {
      final user = _auth?.currentUser;
      if (user != null) {
        final prefs = await SharedPreferences.getInstance();
        _cachedDisplayName = user.displayName ?? prefs.getString(_nameKey(user.uid));
        _cachedPhotoPath = user.photoURL ?? prefs.getString(_photoKey(user.uid));
        _cachedPhone = user.phoneNumber ?? prefs.getString(_phoneKey(user.uid));
      } else {
        _cachedDisplayName = null;
        _cachedPhotoPath = null;
        _cachedPhone = null;
      }

      // Listen to auth user profile changes from Firebase
      _auth?.userChanges().listen((user) async {
        if (user != null) {
          final prefs = await SharedPreferences.getInstance();
          _cachedDisplayName = user.displayName ?? prefs.getString(_nameKey(user.uid));
          _cachedPhotoPath = user.photoURL ?? prefs.getString(_photoKey(user.uid));
          _cachedPhone = user.phoneNumber ?? prefs.getString(_phoneKey(user.uid));
        } else {
          _cachedDisplayName = null;
          _cachedPhotoPath = null;
          _cachedPhone = null;
        }
        _notifyProfileChanged();
      });

      _isInitialized = true;
      _notifyProfileChanged();
    } catch (e) {
      debugPrint('AuthService.init error: $e');
    }
  }

  void _notifyProfileChanged() {
    profileNotifier.value++;
  }

  /// Stream of authentication state changes (logged in / logged out).
  Stream<User?> get authStateChanges => _auth?.authStateChanges() ?? const Stream.empty();

  /// Stream of user profile changes (display name, email updates, reloads).
  Stream<User?> get userChanges => _auth?.userChanges() ?? const Stream.empty();

  /// Current authenticated Firebase user.
  User? get currentUser => _auth?.currentUser;

  /// Current profile display name
  String get displayName {
    final firebaseName = currentUser?.displayName;
    if (firebaseName != null && firebaseName.trim().isNotEmpty) {
      return firebaseName.trim();
    }
    if (_cachedDisplayName != null && _cachedDisplayName!.trim().isNotEmpty) {
      return _cachedDisplayName!.trim();
    }
    return 'Gym Owner';
  }

  /// Current profile photo path or URL (or fitness avatar preset)
  String? get profilePhotoPath {
    final firebasePhoto = currentUser?.photoURL;
    if (firebasePhoto != null && firebasePhoto.trim().isNotEmpty) {
      return firebasePhoto.trim();
    }
    if (_cachedPhotoPath != null && _cachedPhotoPath!.trim().isNotEmpty) {
      return _cachedPhotoPath!.trim();
    }
    return null;
  }

  /// Current profile phone number
  String? get phoneNumber {
    final firebasePhone = currentUser?.phoneNumber;
    if (firebasePhone != null && firebasePhone.trim().isNotEmpty) {
      return firebasePhone.trim();
    }
    if (_cachedPhone != null && _cachedPhone!.trim().isNotEmpty) {
      return _cachedPhone!.trim();
    }
    return null;
  }

  /// Current email address
  String get email {
    return currentUser?.email ?? 'owner@gym.com';
  }

  FirebaseAuth get _requireAuth {
    final auth = _auth;
    if (auth == null) {
      throw FirebaseException(
        plugin: 'firebase_auth',
        message: 'Firebase has not been initialized.',
      );
    }
    return auth;
  }

  /// Whether a user is currently signed in.
  bool get isAuthenticated => _auth?.currentUser != null;

  /// Sign in with email and password.
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _requireAuth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      return credential;
    } catch (e) {
      debugPrint('AuthService.signIn error: $e');
      rethrow;
    }
  }

  /// Whether "Remember Me" is enabled
  Future<bool> getRememberMe() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_keyRememberMe) ?? false;
    } catch (e) {
      debugPrint('AuthService.getRememberMe error: $e');
      return false;
    }
  }

  /// Retrieve saved credentials if Remember Me is active
  Future<Map<String, String>> getSavedCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rememberMe = prefs.getBool(_keyRememberMe) ?? false;
      if (!rememberMe) {
        return {'email': '', 'password': ''};
      }
      return {
        'email': prefs.getString(_keySavedEmail) ?? '',
        'password': prefs.getString(_keySavedPassword) ?? '',
      };
    } catch (e) {
      debugPrint('AuthService.getSavedCredentials error: $e');
      return {'email': '', 'password': ''};
    }
  }

  /// Save or clear credentials based on Remember Me preference
  Future<void> saveCredentials({
    required bool rememberMe,
    String? email,
    String? password,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyRememberMe, rememberMe);
      if (rememberMe) {
        if (email != null && email.trim().isNotEmpty) {
          await prefs.setString(_keySavedEmail, email.trim());
        }
        if (password != null && password.isNotEmpty) {
          await prefs.setString(_keySavedPassword, password);
        }
      } else {
        await prefs.remove(_keySavedEmail);
        await prefs.remove(_keySavedPassword);
      }
    } catch (e) {
      debugPrint('AuthService.saveCredentials error: $e');
    }
  }

  /// Clear saved credentials
  Future<void> clearSavedCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyRememberMe);
      await prefs.remove(_keySavedEmail);
      await prefs.remove(_keySavedPassword);
    } catch (e) {
      debugPrint('AuthService.clearSavedCredentials error: $e');
    }
  }

  /// Create a new account with email, password, display name, and optional photo.
  Future<UserCredential> signUpWithEmailAndPassword({
    required String email,
    required String password,
    required String displayName,
    String? photoPath,
    String? phone,
  }) async {
    try {
      final credential = await _requireAuth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final user = credential.user;
      if (user != null) {
        if (displayName.trim().isNotEmpty) {
          await user.updateDisplayName(displayName.trim());
        }
        if (photoPath != null && photoPath.trim().isNotEmpty) {
          try {
            await user.updatePhotoURL(photoPath.trim());
          } catch (e) {
            debugPrint('Firebase updatePhotoURL warning: $e');
          }
        }
        await user.reload();
      }

      await _saveProfileLocally(
        displayName: displayName.trim(),
        photoPath: photoPath?.trim(),
        phone: phone?.trim(),
      );

      return credential;
    } catch (e) {
      debugPrint('AuthService.signUp error: $e');
      rethrow;
    }
  }

  /// Update the current user's profile details
  Future<void> updateProfile({
    String? displayName,
    String? photoPath,
    String? phone,
  }) async {
    try {
      final user = currentUser;
      if (user != null) {
        if (displayName != null && displayName.trim().isNotEmpty) {
          await user.updateDisplayName(displayName.trim());
        }
        if (photoPath != null) {
          try {
            await user.updatePhotoURL(photoPath.trim().isNotEmpty ? photoPath.trim() : null);
          } catch (e) {
            debugPrint('Firebase updatePhotoURL warning: $e');
          }
        }
        await user.reload();
      }

      await _saveProfileLocally(
        displayName: displayName,
        photoPath: photoPath,
        phone: phone,
      );
    } catch (e) {
      debugPrint('AuthService.updateProfile error: $e');
      rethrow;
    }
  }

  Future<void> _saveProfileLocally({
    String? displayName,
    String? photoPath,
    String? phone,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = currentUser?.uid;

      if (displayName != null) {
        _cachedDisplayName = displayName.trim();
        await prefs.setString(_nameKey(uid), _cachedDisplayName!);
      }

      if (photoPath != null) {
        if (photoPath.trim().isEmpty) {
          _cachedPhotoPath = null;
          await prefs.remove(_photoKey(uid));
        } else {
          _cachedPhotoPath = photoPath.trim();
          await prefs.setString(_photoKey(uid), _cachedPhotoPath!);
        }
      }

      if (phone != null) {
        if (phone.trim().isEmpty) {
          _cachedPhone = null;
          await prefs.remove(_phoneKey(uid));
        } else {
          _cachedPhone = phone.trim();
          await prefs.setString(_phoneKey(uid), _cachedPhone!);
        }
      }

      _notifyProfileChanged();
    } catch (e) {
      debugPrint('AuthService._saveProfileLocally error: $e');
    }
  }

  /// Send password reset link to user's email.
  Future<void> sendPasswordResetEmail({required String email}) async {
    final cleanEmail = email.trim();
    if (cleanEmail.isEmpty) {
      throw FirebaseAuthException(
        code: 'missing-email',
        message: 'Please enter your email address.',
      );
    }
    try {
      await _requireAuth.sendPasswordResetEmail(email: cleanEmail);
    } catch (e) {
      debugPrint('AuthService.sendPasswordResetEmail error: $e');
      rethrow;
    }
  }

  /// Sign out the current user.
  Future<void> signOut() async {
    try {
      final uid = currentUser?.uid;
      await _requireAuth.signOut();
      final prefs = await SharedPreferences.getInstance();
      if (uid != null) {
        await prefs.remove(_photoKey(uid));
        await prefs.remove(_nameKey(uid));
        await prefs.remove(_phoneKey(uid));
      }
      await prefs.remove(_keyProfilePhoto);
      await prefs.remove(_keyProfileDisplayName);
      await prefs.remove(_keyProfilePhone);
      _cachedPhotoPath = null;
      _cachedDisplayName = null;
      _cachedPhone = null;
      _notifyProfileChanged();
      await GymService().detachUser(clearMemory: true);
    } catch (e) {
      debugPrint('AuthService.signOut error: $e');
      rethrow;
    }
  }

  /// Reload current user profile.
  Future<void> reloadUser() async {
    try {
      await _auth?.currentUser?.reload();
      _notifyProfileChanged();
    } catch (e) {
      debugPrint('AuthService.reloadUser error: $e');
    }
  }

  /// Converts Firebase authentication errors into clear, human-readable messages.
  String getReadableErrorMessage(dynamic error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'user-not-found':
          return 'No account found with this email.';
        case 'wrong-password':
          return 'Incorrect password. Please try again.';
        case 'invalid-credential':
          return 'Invalid email or password. Please verify and try again.';
        case 'email-already-in-use':
          return 'An account already exists for this email address.';
        case 'invalid-email':
          return 'Please enter a valid email address.';
        case 'missing-email':
          return 'Please enter your email address.';
        case 'weak-password':
          return 'The password is too weak. Please use at least 6 characters.';
        case 'user-disabled':
          return 'This account has been disabled. Please contact support.';
        case 'too-many-requests':
          return 'Too many attempts. Please wait a moment and try again.';
        case 'operation-not-allowed':
          return 'Password reset or email sign-in is disabled in Firebase Console.';
        case 'network-request-failed':
          return 'Network error. Please check your internet connection.';
        case 'quota-exceeded':
          return 'Email quota exceeded. Please try again later.';
        case 'invalid-continue-uri':
        case 'unauthorized-continue-uri':
          return 'Password reset service configuration error. Please contact support.';
        case 'invalid-api-key':
          return 'Firebase API key is not configured. Please use "Continue in Offline Mode" below, or provide your Firebase project keys in firebase_options.dart.';
        default:
          final msg = error.message ?? '';
          if (msg.toLowerCase().contains('api key') || msg.toLowerCase().contains('api-key')) {
            return 'Firebase API key is not configured. Please use "Continue in Offline Mode" below, or provide your Firebase project keys in firebase_options.dart.';
          }
          return msg.isNotEmpty ? msg : 'Authentication failed. Please try again.';
      }
    } else if (error is FirebaseException) {
      final msg = error.message ?? '';
      if (msg.toLowerCase().contains('not been initialized') || error.code == 'no-app') {
        return 'Firebase service is not initialized. Please ensure your project is properly configured.';
      }
      return msg.isNotEmpty ? msg : 'A service error occurred. Please try again.';
    }
    final str = error?.toString() ?? '';
    if (str.contains('SocketException') || str.contains('Failed host lookup') || str.contains('NetworkImageLoadException')) {
      return 'Network connection error. Please check your internet connection.';
    }
    return str.isNotEmpty ? str : 'An unexpected error occurred.';
  }
}
