import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api/api_client.dart';
import '../core/scan_access.dart' as scan;
import '../nav/access.dart' as nav;

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
    this.roleIds,
    this.platformAdmin = false,
    this.clientType,
    this.clientName,
    this.hotelId,
    this.shopId,
    this.laundryId,
    this.selectedRole,
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

  /// Every role the API supplied, plus [roleId]. Client accounts use prefixed
  /// roles such as `HOTEL_MANAGER`; staff accounts may carry several.
  final List<String>? roleIds;

  /// The API's explicit platform-admin flag, independent of the role label.
  final bool platformAdmin;

  /// Side signals carried by client and staff sessions. A client token still
  /// carries its provider's `laundry_id`, so the client type / entity id must
  /// be considered together with it rather than treating any laundry id as a
  /// laundry staff session.
  final String? clientType;
  final String? clientName;
  final String? hotelId;
  final String? shopId;
  final String? laundryId;

  /// The login screen's `selected_role` (`hotel` / `laundry`). Kept on the user
  /// so the side survives a cold start and cannot be lost between login and
  /// the first scan.
  final String? selectedRole;

  bool get isAdmin => nav.isAdminRole(roleId);
  bool get isManager => nav.normaliseRole(roleId) == nav.Roles.manager;
  bool get isStaff => nav.normaliseRole(roleId) == nav.Roles.staff;
  bool get isPlatformAdmin =>
      platformAdmin ||
      nav.isPlatformAdminRole(roleId) ||
      (roleIds?.any(nav.isPlatformAdminRole) ?? false);

  scan.ScanAccess get scanAccess => scan.scanAccessFor(
        roleId: roleId,
        roleIds: roleIds ?? const <String>[],
        clientType: clientType,
        hotelId: hotelId,
        shopId: shopId,
        laundryId: laundryId,
        selectedRole: selectedRole,
        platformAdmin: isPlatformAdmin,
      );

  Set<String> get allowedLinenScanActions => scanAccess.allowedActions;

  bool canRunLinenScanAction(String action) => scanAccess.allows(action);

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
  /// needs an explicit grant. A platform administrator is a superset admin, so
  /// it passes too (matching the web client). `*` / `all` are wildcard grants.
  bool hasPermission(String permission) {
    if (isAdmin) return true;
    final list = permissionList;
    if (list.contains('*') || list.contains('all')) return true;
    return list.contains(permission);
  }

  static String? _text(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static Map<String, dynamic>? _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : null;

  static List<String> _textList(dynamic value) {
    if (value == null) return const [];
    if (value is String) {
      return value
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    if (value is Iterable) {
      return value
          .map((e) => _text(e))
          .where((e) => e != null)
          .cast<String>()
          .toList();
    }
    return const [];
  }

  factory AppUser.fromJson(Map<String, dynamic> j) {
    final scope = _map(j['client_scope'] ?? j['clientScope']) ?? const {};
    String? field(String key, String camel) =>
        _text(j[key] ?? j[camel]) ?? _text(scope[key]);
    final roles = _textList(j['role_ids'] ?? j['roleIds'] ?? j['roles']);
    final roleId = field('role_id', 'roleId') ?? '';
    if (roleId.isNotEmpty &&
        !roles.any((r) => r.toUpperCase() == roleId.toUpperCase())) {
      roles.add(roleId);
    }
    final flag = j['platform_admin'] ?? j['platformAdmin'];
    return AppUser(
      id: '${j['id'] ?? ''}',
      userName: (j['user_name'] ?? j['userName'] ?? '') as String,
      authId: (j['auth_id'] ?? j['authId'] ?? '') as String,
      roleId: roleId,
      status: (j['status'] ?? '') as String,
      email: j['email'] as String?,
      mobileNumber: (j['mobile_number'] ?? j['mobileNumber']) as String?,
      bioData: (j['bio_data'] ?? j['bioData']) as String?,
      userDp: (j['user_dp'] ?? j['userDp']) as String?,
      employeeId: (j['employee_id'] ?? j['employeeId']) as String?,
      permissions: (j['permissions'] as String?),
      roleIds: roles.isEmpty ? null : List.unmodifiable(roles),
      platformAdmin: flag == true || '${flag ?? ''}'.toLowerCase() == 'true',
      clientType: field('client_type', 'clientType'),
      clientName: field('client_name', 'clientName'),
      hotelId: field('hotel_id', 'hotelId'),
      shopId: field('shop_id', 'shopId'),
      laundryId: field('laundry_id', 'laundryId'),
      selectedRole: _text(j['selected_role'] ?? j['selectedRole']),
    );
  }

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
        if (roleIds != null && roleIds!.isNotEmpty) 'role_ids': roleIds,
        if (platformAdmin) 'platform_admin': true,
        if (clientType != null) 'client_type': clientType,
        if (clientName != null) 'client_name': clientName,
        if (hotelId != null) 'hotel_id': hotelId,
        if (shopId != null) 'shop_id': shopId,
        if (laundryId != null) 'laundry_id': laundryId,
        if (selectedRole != null) 'selected_role': selectedRole,
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
    List<String>? roleIds,
    bool? platformAdmin,
    String? clientType,
    String? clientName,
    String? hotelId,
    String? shopId,
    String? laundryId,
    String? selectedRole,
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
        roleIds: roleIds ?? this.roleIds,
        platformAdmin: platformAdmin ?? this.platformAdmin,
        clientType: clientType ?? this.clientType,
        clientName: clientName ?? this.clientName,
        hotelId: hotelId ?? this.hotelId,
        shopId: shopId ?? this.shopId,
        laundryId: laundryId ?? this.laundryId,
        selectedRole: selectedRole ?? this.selectedRole,
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

  /// Same key the login screen has always written. Reading it here makes the
  /// choice survive a cold start, where the login radio button is gone.
  static const _selectedRoleKey = 'selected_role';
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  final ApiClient api;

  /// Installed by [AppServices] to stop replay and discard the previous
  /// session's queued writes before this state changes identity.
  Future<void> Function()? onBeforeSessionChange;

  AuthSession? _session;
  bool _restored = false;
  bool _busy = false;
  String? _error;

  AuthSession? get session => _session;
  AppUser? get user => _session?.user;
  String? get token => _session?.token;
  bool get isAuthenticated => _session != null;
  bool get isAdmin => user?.isAdmin ?? false;
  bool get isPlatformAdmin => user?.isPlatformAdmin ?? false;

  /// A platform administrator session is confined to the platform surface;
  /// there is no tenant "support mode" on mobile, so this tracks the role.
  bool get isPlatformOnly => isPlatformAdmin;

  bool get restored => _restored;
  bool get busy => _busy;
  String? get error => _error;

  bool hasPermission(String permission) =>
      user?.hasPermission(permission) ?? false;

  scan.ScanAccess get scanAccess =>
      user?.scanAccess ?? const scan.ScanAccess(scan.ScanSide.unknown);

  Set<String> get allowedLinenScanActions => scanAccess.allowedActions;

  bool canRunLinenScanAction(String action) => scanAccess.allows(action);

  /// Reads the persisted session back on cold start and hands the token to the
  /// API client. A malformed token is left in place: the API will reject it and
  /// route through [onUnauthorized], exactly like the web client.
  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final rawToken = await _secureStorage.read(key: _tokenKey);
    final rawUser = prefs.getString(_userKey);
    if (rawToken != null && rawToken.isNotEmpty && rawUser != null) {
      try {
        final decoded = jsonDecode(rawUser);
        if (decoded is Map) {
          final restoredUser = AppUser.fromJson(Map<String, dynamic>.from(decoded));
          final savedSelection = prefs.getString(_selectedRoleKey);
          final user = savedSelection != null && restoredUser.selectedRole == null
              ? restoredUser.copyWith(selectedRole: savedSelection)
              : restoredUser;
          _session = AuthSession(token: rawToken, user: user);
          api.setToken(rawToken);
        }
      } catch (_) {
        await _secureStorage.delete(key: _tokenKey);
        await prefs.remove(_userKey);
      }
    }
    _restored = true;
    notifyListeners();
  }

  /// [selectedRole] is the login screen's radio choice. It is carried on the
  /// session so a hotel selection cannot silently fall back to laundry scans
  /// before the preference is persisted (and after a cold start).
  Future<void> login(
    String token,
    AppUser user, {
    String? selectedRole,
  }) async {
    await onBeforeSessionChange?.call();
    final selection = selectedRole?.trim();
    final nextUser = selection == null || selection.isEmpty
        ? user
        : user.copyWith(selectedRole: selection);
    _session = AuthSession(token: token, user: nextUser);
    _error = null;
    api.setToken(token);
    final prefs = await SharedPreferences.getInstance();
    await _secureStorage.write(key: _tokenKey, value: token);
    await prefs.setString(_userKey, jsonEncode(nextUser.toJson()));
    if (selection != null) await prefs.setString(_selectedRoleKey, selection);
    notifyListeners();
  }

  Future<void> updateUser(AppUser user) async {
    final current = _session;
    if (current == null) return;
    final selection = user.selectedRole ?? current.user.selectedRole;
    final nextUser = selection == null
        ? user
        : user.copyWith(selectedRole: selection);
    _session = AuthSession(token: current.token, user: nextUser);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(nextUser.toJson()));
    notifyListeners();
  }

  Future<void> logout() async {
    await onBeforeSessionChange?.call();
    _session = null;
    _error = null;
    api.setToken(null);
    final prefs = await SharedPreferences.getInstance();
    await _secureStorage.delete(key: _tokenKey);
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
