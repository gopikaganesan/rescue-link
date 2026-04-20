import 'package:flutter/foundation.dart';

class SosStatusProvider extends ChangeNotifier {
  String? _activeSosId;
  DateTime? _activatedAt;

  String? get activeSosId => _activeSosId;
  DateTime? get activatedAt => _activatedAt;
  bool get hasActiveSos => _activeSosId != null;

  void setActiveSos(String sosId) {
    _activeSosId = sosId.trim().isEmpty ? null : sosId.trim();
    _activatedAt = _activeSosId != null ? DateTime.now() : null;
    notifyListeners();
  }

  void clearActiveSos() {
    _activeSosId = null;
    _activatedAt = null;
    notifyListeners();
  }
}
