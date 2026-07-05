import 'dart:convert';
import 'package:flutter/material.dart';
import '../core/database/db.dart';

class AuthProvider extends ChangeNotifier {
  Map<String, dynamic>? _user;
  Map<String, bool> _permissions = {};

  Map<String, dynamic>? get user => _user;
  bool get isLoggedIn => _user != null;
  String get userName => _user?['name'] as String? ?? '';
  String get userRole => _user?['role'] as String? ?? '';
  bool get isAdmin => userRole == 'admin';
  bool get isManager => userRole == 'admin' || userRole == 'manager';
  int? get employeeId => _user?['id'] as int?;

  bool can(String module) {
    if (isAdmin) return true;
    return _permissions[module] ?? false;
  }

  Future<bool> login(String username, String password) async {
    final u = await DB.instance.login(username, password);
    if (u != null) {
      _setUser(u);
      return true;
    }
    return false;
  }

  Future<bool> loginPin(String pin) async {
    final u = await DB.instance.loginPin(pin);
    if (u != null) {
      _setUser(u);
      return true;
    }
    return false;
  }

  void _setUser(Map<String, dynamic> u) {
    _user = u;
    try {
      final perms = jsonDecode(u['permissions'] as String? ?? '{}') as Map<String, dynamic>;
      _permissions = perms.map((k, v) => MapEntry(k, v as bool));
    } catch (_) {
      _permissions = {};
    }
    notifyListeners();
  }

  void logout() {
    _user = null;
    _permissions = {};
    notifyListeners();
  }
}
