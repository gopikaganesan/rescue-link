import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';

/// Manages user authentication state
class AuthProvider extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  UserModel? _currentUser;
  bool _isLoading = false;
  String? _error;
  bool _isAuthenticated = false;
  String? _phoneVerificationId;
  int? _forceResendingToken;

  AuthProvider() {
    _bootstrapAuthState();
  }

  // Getters
  UserModel? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _isAuthenticated;
  String? get phoneVerificationId => _phoneVerificationId;
  bool get isAnonymousUser {
    final firebaseUser = _auth.currentUser;
    if (firebaseUser != null) {
      return firebaseUser.isAnonymous;
    }
    return _currentUser?.isAnonymous ?? false;
  }

  String _mapAuthError(Object e, {required String fallback}) {
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'configuration-not-found':
          return 'Firebase Auth is not configured for this app. Enable Sign-in methods and update Android app settings in Firebase console.';
        case 'operation-not-allowed':
          return 'This sign-in method is disabled in Firebase console.';
        case 'invalid-credential':
        case 'invalid-email':
          return 'Invalid email or credential.';
        case 'wrong-password':
        case 'user-not-found':
          return 'Incorrect email or password.';
        case 'network-request-failed':
          return 'Network error. Check internet connection and try again.';
        default:
          return e.message ?? fallback;
      }
    }
    return '$fallback: ${e.toString()}';
  }

  Future<void> _bootstrapAuthState() async {
    final firebaseUser = _auth.currentUser;
    if (firebaseUser != null) {
      await _setCurrentFromFirebaseUser(firebaseUser);
      notifyListeners();
    }

    _auth.authStateChanges().listen((user) async {
      if (user == null) {
        _currentUser = null;
        _isAuthenticated = false;
        _isLoading = false;
      } else {
        await _setCurrentFromFirebaseUser(user);
      }
      notifyListeners();
    });
  }

  Future<void> _setCurrentFromFirebaseUser(User user) async {
    try {
      final doc = await _firestore
          .collection('users')
          .doc(user.uid)
          .get()
          .timeout(const Duration(seconds: 5));
      final data = doc.data();
      if (data != null) {
        _currentUser = UserModel.fromMap(<String, dynamic>{
          ...data,
          'id': user.uid,
          'email': user.email ?? (data['email'] as String? ?? ''),
          'phoneNumber': user.phoneNumber ?? (data['phoneNumber'] as String?),
          'displayName':
              user.displayName ?? (data['displayName'] as String? ?? 'RescueLink User'),
          'isAnonymous': user.isAnonymous,
          'createdAt': DateTime.now(),
        });
      } else {
        _currentUser = UserModel(
          id: user.uid,
          email: user.email ?? '',
          phoneNumber: user.phoneNumber,
          displayName: user.displayName ?? 'RescueLink User',
          isAnonymous: user.isAnonymous,
          createdAt: DateTime.now(),
        );
      }
      _isAuthenticated = true;
      _error = null;
    } catch (_) {
      _currentUser = UserModel(
        id: user.uid,
        email: user.email ?? '',
        phoneNumber: user.phoneNumber,
        displayName: user.displayName ?? 'RescueLink User',
        isAnonymous: user.isAnonymous,
        createdAt: DateTime.now(),
      );
      _isAuthenticated = true;
      _error = null;
    }
  }

  Future<bool> ensureAuthenticated() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    if (_auth.currentUser != null) {
      await _setCurrentFromFirebaseUser(_auth.currentUser!);
      _isLoading = false;
      notifyListeners();
      return true;
    }

    try {
      final credential = await _auth.signInAnonymously();
      final user = credential.user;
      if (user != null) {
        await _setCurrentFromFirebaseUser(user);
      }
      _isLoading = false;
      notifyListeners();
      return _isAuthenticated;
    } catch (e) {
      _error = _mapAuthError(e, fallback: 'Anonymous sign-in failed');
      _isAuthenticated = false;
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Login user (placeholder for Firebase Auth)
  Future<bool> login(String email, String password) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;
      if (user != null) {
        await _setCurrentFromFirebaseUser(user);
      }

      _isAuthenticated = true;
    } catch (e) {
      _error = _mapAuthError(e, fallback: 'Login failed');
      _isAuthenticated = false;
    } finally {
      _isLoading = false;
    }

    notifyListeners();
    return _isAuthenticated;
  }

  /// Register new user
  Future<bool> register(
    String email,
    String displayName,
    String password, {
    String? phoneNumber,
  }) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final current = _auth.currentUser;
      UserCredential credential;
      if (current != null && current.isAnonymous) {
        final authCredential = EmailAuthProvider.credential(
          email: email,
          password: password,
        );
        credential = await current.linkWithCredential(authCredential);
      } else {
        credential = await _auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      }

      await credential.user?.updateDisplayName(displayName);
      final user = credential.user;

      if (user != null) {
        _currentUser = UserModel(
          id: user.uid,
          email: email,
          phoneNumber: (phoneNumber?.trim().isNotEmpty ?? false)
              ? phoneNumber!.trim()
              : user.phoneNumber,
          displayName: displayName,
          isAnonymous: user.isAnonymous,
          isResponder: false,
          createdAt: DateTime.now(),
        );

        await _firestore.collection('users').doc(user.uid).set(
          _currentUser!.toMap(),
          SetOptions(merge: true),
        );
      }

      _isAuthenticated = true;
    } catch (e) {
      _error = _mapAuthError(e, fallback: 'Registration failed');
      _isAuthenticated = false;
    } finally {
      _isLoading = false;
    }

    notifyListeners();
    return _isAuthenticated;
  }

  String _normalizePhone(String input) {
    final compact = input.replaceAll(RegExp(r'\s+|-'), '');
    if (compact.startsWith('+')) {
      return compact;
    }
    return '+91$compact';
  }

  Future<bool> sendPhoneOtp(String phoneInput) async {
    final phone = _normalizePhone(phoneInput.trim());

    _isLoading = true;
    _error = null;
    notifyListeners();

    final completer = Completer<bool>();

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phone,
        forceResendingToken: _forceResendingToken,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          try {
            final current = _auth.currentUser;
            UserCredential result;
            if (current != null && current.isAnonymous) {
              result = await current.linkWithCredential(credential);
            } else {
              result = await _auth.signInWithCredential(credential);
            }
            if (result.user != null) {
              await _setCurrentFromFirebaseUser(result.user!);
            }
            if (!completer.isCompleted) {
              completer.complete(true);
            }
          } catch (e) {
            _error = _mapAuthError(e, fallback: 'Phone sign-in failed');
            if (!completer.isCompleted) {
              completer.complete(false);
            }
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          _error = _mapAuthError(e, fallback: 'Phone verification failed');
          if (!completer.isCompleted) {
            completer.complete(false);
          }
        },
        codeSent: (String verificationId, int? resendToken) {
          _phoneVerificationId = verificationId;
          _forceResendingToken = resendToken;
          if (!completer.isCompleted) {
            completer.complete(true);
          }
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _phoneVerificationId = verificationId;
        },
      );

      final sent = await completer.future;
      _isLoading = false;
      notifyListeners();
      return sent;
    } catch (e) {
      _error = _mapAuthError(e, fallback: 'Unable to send OTP');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> verifyPhoneOtp({
    required String smsCode,
    String? displayName,
  }) async {
    if ((_phoneVerificationId ?? '').isEmpty) {
      _error = 'Please request OTP first.';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _phoneVerificationId!,
        smsCode: smsCode,
      );

      final current = _auth.currentUser;
      UserCredential result;
      if (current != null && current.isAnonymous) {
        result = await current.linkWithCredential(credential);
      } else {
        result = await _auth.signInWithCredential(credential);
      }

      final user = result.user;
      if (user != null) {
        if ((displayName ?? '').trim().isNotEmpty) {
          await user.updateDisplayName(displayName!.trim());
        }

        await _setCurrentFromFirebaseUser(user);
        await _firestore.collection('users').doc(user.uid).set(
          <String, dynamic>{
            'id': user.uid,
            'email': user.email ?? '',
            'phoneNumber': user.phoneNumber ?? currentUser?.phoneNumber,
            'displayName':
                user.displayName ?? currentUser?.displayName ?? 'RescueLink User',
            'isAnonymous': user.isAnonymous,
            'createdAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }

      _isAuthenticated = true;
      _phoneVerificationId = null;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = _mapAuthError(e, fallback: 'OTP verification failed');
      _isAuthenticated = false;
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Update user location
  void updateUserLocation(double latitude, double longitude) {
    if (_currentUser != null) {
      _currentUser = _currentUser!.copyWith(
        latitude: latitude,
        longitude: longitude,
      );

      _firestore.collection('users').doc(_currentUser!.id).set(
        <String, dynamic>{
          'latitude': latitude,
          'longitude': longitude,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      notifyListeners();
    }
  }

  /// Mark user as responder
  void registerAsResponder() {
    if (_currentUser != null) {
      _currentUser = _currentUser!.copyWith(isResponder: true);

      _firestore.collection('users').doc(_currentUser!.id).set(
        <String, dynamic>{'isResponder': true},
        SetOptions(merge: true),
      );

      notifyListeners();
    }
  }

  /// Unmark user as responder
  void unregisterAsResponder() {
    if (_currentUser != null) {
      _currentUser = _currentUser!.copyWith(isResponder: false);

      _firestore.collection('users').doc(_currentUser!.id).set(
        <String, dynamic>{'isResponder': false},
        SetOptions(merge: true),
      );

      notifyListeners();
    }
  }

  /// Logout
  Future<void> logout() async {
    await _auth.signOut();
    _currentUser = null;
    _isAuthenticated = false;
    _error = null;
    notifyListeners();
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }
}
