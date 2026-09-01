import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../models/user.dart';

import 'package:flutter/material.dart';

class AuthService extends ChangeNotifier {
  static const String _tokenKey = 'jwt_token';
  static const String _userKey = 'user_data';

  String? _token;
  User? _user;

  String? get token => _token;
  User? get user => _user;
  bool get isLoggedIn => _token != null;

  Future<bool> tryAutoLogin() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey);
    final userJson = prefs.getString(_userKey);

    if (_token != null && userJson != null) {
      _user = User.fromJson(jsonDecode(userJson));
      return true;
    }
    return false;
  }

  Future<String?> login(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse(ApiConfig.loginUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _token = data['access_token'];
        _user = User.fromJson(data['user']);

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_tokenKey, _token!);
        await prefs.setString(_userKey, jsonEncode(data['user']));
        notifyListeners();
        return null; // success
      } else if (response.statusCode == 401) {
        return 'Invalid username or password';
      } else {
        final data = jsonDecode(response.body);
        return data['detail'] ?? 'Login failed (${response.statusCode})';
      }
    } catch (e) {
      return 'Connection error: $e';
    }
  }

  Future<void> logout() async {
    _token = null;
    _user = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
    notifyListeners();
  }

  Map<String, String> get authHeaders => {
        'Authorization': 'Bearer $_token',
        'Content-Type': 'application/json',
      };
}
