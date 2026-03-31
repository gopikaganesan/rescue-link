import 'package:flutter/foundation.dart';
import '../models/user_model.dart';

/// Manages user authentication state
class AuthProvider extends ChangeNotifier {
  UserModel? _currentUser;
  bool _isLoading = false;
  String? _error;
  bool _isAuthenticated = false;

  // Getters
  UserModel? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _isAuthenticated;

  /// Login user (placeholder for Firebase Auth)
  Future<bool> login(String email, String password) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      // TODO: Replace with actual Firebase Auth
      // Simulating login delay
      await Future.delayed(const Duration(seconds: 1));

      _currentUser = UserModel(
        id: 'user_${DateTime.now().millisecondsSinceEpoch}',
        email: email,
        displayName: email.split('@')[0],
        isResponder: false,
        createdAt: DateTime.now(),
      );

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

      // TODO: Replace with actual Firebase Auth
      await Future.delayed(const Duration(seconds: 1));

      _currentUser = UserModel(
        id: 'user_${DateTime.now().millisecondsSinceEpoch}',
        email: email,
        displayName: displayName,
        isResponder: false,
        createdAt: DateTime.now(),
      );

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
      notifyListeners();
    }
  }

  /// Mark user as responder
  void registerAsResponder() {
    if (_currentUser != null) {
      _currentUser = _currentUser!.copyWith(isResponder: true);
      notifyListeners();
    }
  }

  /// Logout
  void logout() {
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
