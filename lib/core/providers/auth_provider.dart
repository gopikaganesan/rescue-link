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

  AuthProvider() {
    _bootstrapAuthState();
  }

  // Getters
  UserModel? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _isAuthenticated;

  void _bootstrapAuthState() {
    final firebaseUser = _auth.currentUser;
    if (firebaseUser != null) {
      _setCurrentFromFirebaseUser(firebaseUser);
    }

    _auth.authStateChanges().listen((user) {
      if (user == null) {
        _currentUser = null;
        _isAuthenticated = false;
      } else {
        _setCurrentFromFirebaseUser(user);
      }
      notifyListeners();
    });
  }

  Future<void> _setCurrentFromFirebaseUser(User user) async {
    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      final data = doc.data();
      if (data != null) {
        _currentUser = UserModel.fromMap(<String, dynamic>{
          ...data,
          'id': user.uid,
          'email': user.email ?? (data['email'] as String? ?? ''),
          'displayName':
              user.displayName ?? (data['displayName'] as String? ?? 'RescueLink User'),
          'createdAt': DateTime.now(),
        });
      } else {
        _currentUser = UserModel(
          id: user.uid,
          email: user.email ?? '',
          displayName: user.displayName ?? 'RescueLink User',
          createdAt: DateTime.now(),
        );
      }
      _isAuthenticated = true;
    } catch (_) {
      _currentUser = UserModel(
        id: user.uid,
        email: user.email ?? '',
        displayName: user.displayName ?? 'RescueLink User',
        createdAt: DateTime.now(),
      );
      _isAuthenticated = true;
    }
  }

  Future<void> ensureAuthenticated() async {
    if (_auth.currentUser != null) {
      await _setCurrentFromFirebaseUser(_auth.currentUser!);
      notifyListeners();
      return;
    }

    try {
      final credential = await _auth.signInAnonymously();
      final user = credential.user;
      if (user != null) {
        await _setCurrentFromFirebaseUser(user);
      }
    } catch (e) {
      _error = 'Anonymous sign-in failed: ${e.toString()}';
      _isAuthenticated = false;
      notifyListeners();
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
      _isLoading = false;
    } catch (e) {
      _error = 'Login failed: ${e.toString()}';
      _isLoading = false;
      _isAuthenticated = false;
    }
    notifyListeners();
    return _isAuthenticated;
  }

  /// Register new user
  Future<bool> register(String email, String displayName, String password) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      await credential.user?.updateDisplayName(displayName);
      final user = credential.user;

      if (user != null) {
        _currentUser = UserModel(
          id: user.uid,
          email: email,
          displayName: displayName,
          isResponder: false,
          createdAt: DateTime.now(),
        );

        await _firestore.collection('users').doc(user.uid).set(
          _currentUser!.toMap(),
          SetOptions(merge: true),
        );
      }

      _isAuthenticated = true;
      _isLoading = false;
    } catch (e) {
      _error = 'Registration failed: ${e.toString()}';
      _isLoading = false;
      _isAuthenticated = false;
    }
    notifyListeners();
    return _isAuthenticated;
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
