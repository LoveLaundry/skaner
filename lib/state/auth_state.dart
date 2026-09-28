import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api/api_client.dart';

/// Port of `src/types/auth.ts` + `src/context/AuthContext.tsx`.
@immutable
class AppUser {
  const AppUser({
    required this.id,
    required this.userName,
    required this.authId,
    required this.roleId,
    required this.status,
    this.email,
    this.mobileNumber,
    this.bioData,
    this.userDp,
    this.employeeId,
    this.permissions,
  });

  final String id;
  final String userName;
  final String authId;
  final String roleId;
  final String status;
  final String? email;
  final String? mobileNumber;
  final String? bioData;
  final String? userDp;
  final String? employeeId;

  /// Raw value from the API: a JSON array string, a comma-separated list, or
  /// null. Parsed lazily by [permissionList].
  final String? permissions;

  bool get isAdmin => roleId.toUpperCase() == 'ADMIN';

  List<String> get permissionList {
    final raw = permissions;
    if (raw == null || raw.trim().isEmpty) return const [];
    final trimmed = raw.trim();
    if (trimmed.startsWith('[')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is List) {
          return decoded
              .map((e) => '$e'.trim())
              .where((e) => e.isNotEmpty)
              .toList();
        }
      } catch (_) {
        // Fall through to the comma-separated reading.
      }
    }
    return trimmed
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  String get displayName => userName.trim().isEmpty ? authId : userName.trim();

  String get initials {
    final parts =
        displayName.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first
          .substring(0, parts.first.length >= 2 ? 2 : 1)
          .toUpperCase();
    }
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  /// Port of `hooks/usePermissions.ts`: admins pass everything, everyone else
  /// needs an explicit grant.
  bool hasPermission(String permission) {
    if (isAdmin) return true;
    return permissionList.contains(permission);
  }

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: '${j['id'] ?? ''}',
        userName: (j['user_name'] ?? j['userName'] ?? '') as String,
        authId: (j['auth_id'] ?? j['authId'] ?? '') as String,
        roleId: (j['role_id'] ?? j['roleId'] ?? '') as String,
        status: (j['status'] ?? '') as String,
        email: j['email'] as String?,
        mobileNumber: (j['mobile_number'] ?? j['mobileNumber']) as String?,
        bioData: (j['bio_data'] ?? j['bioData']) as String?,
        userDp: (j['user_dp'] ?? j['userDp']) as String?,
        employeeId: (j['employee_id'] ?? j['employeeId']) as String?,
        permissions: (j['permissions'] as String?),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_name': userName,
        'auth_id': authId,
        'role_id': roleId,
        'status': status,
        if (email != null) 'email': email,
        if (mobileNumber != null) 'mobile_number': mobileNumber,
        if (bioData != null) 'bio_data': bioData,
        if (userDp != null) 'user_dp': userDp,
        if (employeeId != null) 'employee_id': employeeId,
        if (permissions != null) 'permissions': permissions,
      };

  AppUser copyWith({
    String? userName,
    String? roleId,
    String? status,
    String? email,
    String? mobileNumber,
    String? bioData,
    String? userDp,
    String? employeeId,
    String? permissions,
  }) =>
      AppUser(
        id: id,
        userName: userName ?? this.userName,
        authId: authId,
        roleId: roleId ?? this.roleId,
        status: status ?? this.status,
        email: email ?? this.email,
        mobileNumber: mobileNumber ?? this.mobileNumber,
        bioData: bioData ?? this.bioData,
        userDp: userDp ?? this.userDp,
        employeeId: employeeId ?? this.employeeId,
        permissions: permissions ?? this.permissions,
      );
}

/// Token + user pair, persisted under the same keys the web app uses so a
/// shared profile behaves identically on both clients.
@immutable
class AuthSession {
  const AuthSession({required this.token, required this.user});

  final String token;
  final AppUser user;

  Map<String, dynamic> toJson() => {'token': token, 'user': user.toJson()};

  factory AuthSession.fromJson(Map<String, dynamic> j) => AuthSession(
        token: j['token'] as String,
        user: AppUser.fromJson(Map<String, dynamic>.from(j['user'] as Map)),
      );
}

class AuthState extends ChangeNotifier {
  AuthState({required this.api}) {
    api.onUnauthorized = handleUnauthorized;
  }

  static const _tokenKey = 'll_token';
  static const _userKey = 'll_user';

  final ApiClient api;

  AuthSession? _session;
  bool _restored = false;
  bool _busy = false;
  String? _error;

  AuthSession? get session => _session;
  AppUser? get user => _session?.user;
  String? get token => _session?.token;
  bool get isAuthenticated => _session != null;
  bool get isAdmin => user?.isAdmin ?? false;
  bool get restored => _restored;
  bool get busy => _busy;
  String? get error => _error;

  bool hasPermission(String permission) =>
      user?.hasPermission(permission) ?? false;

  /// Reads the persisted session back on cold start and hands the token to the
  /// API client. A malformed token is left in place: the API will reject it and
  /// route through [onUnauthorized], exactly like the web client.
  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final rawToken = prefs.getString(_tokenKey);
    final rawUser = prefs.getString(_userKey);
    if (rawToken != null && rawToken.isNotEmpty && rawUser != null) {
      try {
        final decoded = jsonDecode(rawUser);
        if (decoded is Map) {
          final session = AuthSession.fromJson({
            'token': rawToken,
            'user': Map<String, dynamic>.from(decoded),
          });
          _session = session;
          api.setToken(rawToken);
        }
      } catch (_) {
        await prefs.remove(_tokenKey);
        await prefs.remove(_userKey);
      }
    }
    _restored = true;
    notifyListeners();
  }

  Future<void> login(String token, AppUser user) async {
    _session = AuthSession(token: token, user: user);
    _error = null;
    api.setToken(token);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_userKey, jsonEncode(user.toJson()));
    notifyListeners();
  }

  Future<void> updateUser(AppUser user) async {
    final current = _session;
    if (current == null) return;
    _session = AuthSession(token: current.token, user: user);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(user.toJson()));
    notifyListeners();
  }

  Future<void> logout() async {
    _session = null;
    _error = null;
    api.setToken(null);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
    notifyListeners();
  }

  void setBusy(bool value) {
    if (_busy == value) return;
    _busy = value;
    notifyListeners();
  }

  void setError(String? value) {
    if (_error == value) return;
    _error = value;
    notifyListeners();
  }

  /// The API client calls this when a request comes back 401 on an
  /// auth-protected path. The management backend has no 401 interceptor, so an
  /// expired session there surfaces as a normal error instead.
  Future<void> handleUnauthorized() async {
    if (_session == null) return;
    await logout();
  }

  @override
  void dispose() {
    if (identical(api.onUnauthorized, handleUnauthorized)) {
      api.onUnauthorized = null;
    }
    super.dispose();
  }
}
