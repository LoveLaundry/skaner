/// access.dart — the single source of truth for "what may this session see".
///
/// Mirrors `quotations-ui/src/lib/access.ts` so the web app and the mobile app
/// agree on who may open what. Before this module the mobile app gated only on
/// permission strings, most of which were never declared: ungated Management,
/// Payroll, Roles, Permissions and System routes were therefore reachable by
/// every role, and a `PLATFORM_ADMIN` (recognised as admin on the web) was
/// treated as a plain user here and saw almost nothing.
///
/// Two axes decide access, and nothing else:
///   · scope  — a platform session vs a tenant session
///   · grants — the role's capability, or an explicit permission string
library;

/// Role ids, upper-cased. Unknown roles fall through as tenants with no grants.
class Roles {
  Roles._();

  static const admin = 'ADMIN';
  static const manager = 'MANAGER';
  static const staff = 'STAFF';
  static const platformAdmin = 'PLATFORM_ADMIN';

  /// Roles a laundry administrator and manager run as.
  static const tenantAdmins = <String>{admin, manager};
}

/// Upper-cases a role id, or returns '' when there is none.
String normaliseRole(String? roleId) => (roleId ?? '').toUpperCase();

/// True for platform administrators.
///
/// The web client treats `platform_admin` as an authoritative flag plus a
/// `PLATFORM_ADMIN` role; the mobile API payload exposes the role, so that is
/// the signal here.
bool isPlatformAdminRole(String? roleId) =>
    normaliseRole(roleId) == Roles.platformAdmin;

/// Does an ADMIN-shaped role satisfy this session? ADMIN holds every capability
/// implicitly, and PLATFORM_ADMIN does too (it is a superset on the web).
bool isAdminRole(String? roleId) {
  final role = normaliseRole(roleId);
  return role == Roles.admin || role == Roles.platformAdmin;
}

/// Tenant administrators only (ADMIN / MANAGER), excluding platform admins.
bool isTenantAdminRole(String? roleId) =>
    Roles.tenantAdmins.contains(normaliseRole(roleId));

/// The access shape shared by every route, drawer entry and command item.
class AccessSpec {
  const AccessSpec({
    this.permissions = const [],
    this.roles,
    this.adminOnly = false,
    this.platformOnly = false,
    this.tenantOnly = false,
  });

  /// Permission strings; the session must hold every one.
  final List<String> permissions;

  /// Role ids; the session's role must be one of them (when non-null).
  final Set<String>? roles;

  /// Tenant-admin only (ADMIN / MANAGER). A platform admin does not satisfy it
  /// unless it is also listed in [roles].
  final bool adminOnly;

  /// Only platform administrators may reach this.
  final bool platformOnly;

  /// Platform administrators may NOT reach this (tenant operations).
  final bool tenantOnly;
}

/// True when a session with [roleId] and [permissionList] satisfies [spec].
///
/// [isPlatformOnly] is passed in (rather than derived) so a support session,
/// which enters a laundry as that laundry, can be excluded from the platform
/// confinement exactly as the web client does.
bool canAccess({
  required String? roleId,
  required List<String> permissionList,
  AccessSpec spec = const AccessSpec(),
  bool isPlatformOnly = false,
  bool platformAdmin = false,
}) {
  final role = normaliseRole(roleId);
  final platform = platformAdmin || isPlatformAdminRole(role);
  final admin = platform || role == Roles.admin;

  bool hasPermission(String permission) {
    if (admin) return true;
    if (permissionList.contains('*') || permissionList.contains('all')) {
      return true;
    }
    return permissionList.contains(permission);
  }

  // Scope first: a platform-only session is confined to the platform surface,
  // and a tenant-only screen is closed to a platform administrator.
  if (spec.platformOnly && !platform) return false;
  if (isPlatformOnly && !spec.platformOnly) return false;
  if (spec.tenantOnly && platform) return false;

  if (spec.adminOnly) {
    // A platform administrator is a superset admin, so it satisfies an
    // admin-only gate exactly as the web client does.
    final allowed = platform ||
        isTenantAdminRole(role) ||
        (spec.roles?.contains(role) ?? false);
    if (!allowed) return false;
  }

  if (spec.roles != null && !spec.roles!.contains(role)) return false;

  for (final permission in spec.permissions) {
    if (!hasPermission(permission)) return false;
  }

  return true;
}

/// A candidate landing destination, in preference order.
class LandingCandidate {
  const LandingCandidate(this.path, this.spec);

  final String path;
  final AccessSpec spec;
}

/// The best landing path for a session.
///
/// Mirrors the web `landingPathFor`: a platform session lands on its own
/// surface, a tenant session lands on the first candidate it may open, and
/// [fallback] is used when none match.
String landingPathFor({
  required String? roleId,
  required List<String> permissionList,
  required List<LandingCandidate> candidates,
  required String fallback,
  bool platformAdmin = false,
}) {
  for (final candidate in candidates) {
    if (canAccess(
      roleId: roleId,
      permissionList: permissionList,
      spec: candidate.spec,
      platformAdmin: platformAdmin,
    )) {
      return candidate.path;
    }
  }
  return fallback;
}
