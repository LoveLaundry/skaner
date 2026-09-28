import 'package:flutter/material.dart';

import '../../nav/app_route.dart';
import '../../state/app_scope.dart';
import '../../state/app_services.dart';
import '../../ui/brand/logo.dart';
import '../../ui/kit/feedback.dart';
import '../../ui/kit/shell_parts.dart';
import '../../ui/theme.dart';

/// The persistent frame: drawer navigation, hotel scope, sync state and the
/// operator identity. Every signed-in screen renders inside it.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child, required this.currentPath});

  final Widget child;
  final String currentPath;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final tabRoutes = AppRoutes.table.values
        .where((r) => r.bottomBar && r.isVisibleTo(services))
        .toList()
      ..sort((a, b) => (a.tabIndex ?? 99).compareTo(b.tabIndex ?? 99));

    return Scaffold(
      drawer: AppDrawer(currentPath: currentPath),
      body: child,
      bottomNavigationBar: tabRoutes.length < 2
          ? null
          : Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: context.c.line)),
              ),
              child: NavigationBar(
                selectedIndex: tabRoutes.indexWhere((r) =>
                    _isCurrent(r.path, currentPath)),
                onDestinationSelected: (i) {
                  final target = tabRoutes[i].path;
                  if (_isCurrent(target, currentPath)) return;
                  _go(context, target);
                },
                destinations: [
                  for (final r in tabRoutes)
                    NavigationDestination(
                      icon: Icon(r.icon ?? Icons.circle_outlined),
                      selectedIcon:
                          Icon(r.icon ?? Icons.circle, size: 22),
                      label: r.label,
                    ),
                ],
              ),
            ),
    );
  }

  static bool _isCurrent(String routePath, String current) {
    if (routePath == current) return true;
    if (AppRoutes.home == current) return routePath == AppRoutes.home;
    return current.startsWith('$routePath/');
  }

  static void _go(BuildContext context, String path) {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.popUntil((r) => r.settings.name == AppRoutes.home || r.isFirst);
    }
    if (navigator.canPop()) return;
    AppNavigatorPush.push(context, path);
  }
}

/// Thin wrapper so widgets outside the shell can navigate without importing
/// the router's internals.
class AppNavigatorPush {
  AppNavigatorPush._();

  static void push(BuildContext context, String path) {
    final delegate = RoutePushScope.of(context);
    delegate?.call(path);
  }
}

/// Exposes the shell's `push` function to the subtree.
class RoutePushScope extends InheritedWidget {
  const RoutePushScope({
    super.key,
    required this.push,
    required super.child,
  });

  final void Function(String path) push;

  static void Function(String)? of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<RoutePushScope>()
          ?.push;

  @override
  bool updateShouldNotify(RoutePushScope oldWidget) => false;
}

/// Port of the web sidebar: grouped destinations, permission-filtered, with the
/// operator card and the offline indicator at the foot.
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key, required this.currentPath});

  final String currentPath;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final c = context.c;
    final t = context.texts;
    final auth = services.auth;
    final hotels = services.hotels;

    final visible = AppRoutes.table.values
        .where((r) => r.showInDrawer && r.isVisibleTo(services))
        .toList();

    final groups = <String, List<AppRoute>>{};
    for (final r in visible) {
      groups.putIfAbsent(r.group, () => []).add(r);
    }

    return Drawer(
      backgroundColor: c.sidebarBg,
      child: SafeArea(
        child: Column(
          children: [
            // Identity + hotel scope
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                children: [
                  const AppLogo(size: 34, showWordmark: false),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Love Laundry',
                          style: t.titleSmall
                              ?.copyWith(color: c.sidebarActive),
                        ),
                        Text(
                          auth.user?.displayName ?? 'Guest',
                          style: t.labelSmall
                              ?.copyWith(color: c.sidebarLabel),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (auth.user != null)
                    PopupMenuButton<String>(
                      color: c.surface,
                      icon: Icon(Icons.more_vert,
                          size: 18, color: c.sidebarText),
                      onSelected: (v) {
                        if (v == 'logout') _logout(context);
                        if (v == 'profile') AppNavigatorPush.push(context, AppRoutes.profile);
                        if (v == 'settings') AppNavigatorPush.push(context, AppRoutes.settings);
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'profile', child: Text('Profile')),
                        const PopupMenuItem(value: 'settings', child: Text('Settings')),
                        const PopupMenuDivider(),
                        const PopupMenuItem(value: 'logout', child: Text('Sign out')),
                      ],
                    ),
                ],
              ),
            ),
            if (hotels.hotels.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: _HotelScopePicker(
                  hotels: hotels.hotels,
                  selected: hotels.selectedHotel,
                  isAdmin: hotels.isAdmin,
                ),
              ),
            Divider(height: 1, color: c.sidebarBorder),
            // Search
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Material(
                color: c.sidebarHoverBg,
                borderRadius: BorderRadius.circular(Radii.md),
                child: InkWell(
                  borderRadius: BorderRadius.circular(Radii.md),
                  onTap: () => _openCommand(context, services),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        Icon(Icons.search, size: 16, color: c.sidebarLabel),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Search screens…',
                            style: t.bodySmall
                                ?.copyWith(color: c.sidebarLabel),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 12),
                children: [
                  for (final entry in groups.entries) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 14, 16, 6),
                      child: Text(
                        entry.key.toUpperCase(),
                        style: t.labelSmall?.copyWith(
                          color: c.sidebarLabel,
                          fontSize: 10,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    for (final r in entry.value)
                      _DrawerItem(
                        route: r,
                        active: _isActive(r.path, currentPath),
                        onTap: () {
                          Navigator.of(context).pop();
                          AppNavigatorPush.push(context, r.path);
                        },
                      ),
                  ],
                ],
              ),
            ),
            // Sync foot
            StreamBuilder<bool>(
              stream: services.connectivity.onOnlineChange,
              initialData: services.connectivity.isOnline,
              builder: (context, snap) {
                final online = snap.data ?? true;
                return Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: c.sidebarBorder)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: online ? c.success : c.warning,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        online ? 'Online' : 'Offline — changes queue',
                        style: t.labelSmall?.copyWith(color: c.sidebarLabel),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  static bool _isActive(String routePath, String current) {
    if (routePath == current) return true;
    return current.startsWith('$routePath/');
  }

  Future<void> _openCommand(
      BuildContext context, AppServices services) async {
    final items = AppRoutes.table.values
        .where((r) => r.showInCommand && r.isVisibleTo(services))
        .map((r) => AppCommandItem(
              label: r.label,
              route: r.path,
              icon: r.icon,
              group: r.group,
              keywords: r.keywords,
            ))
        .toList();
    await AppCommandSearch.show(
      context,
      items: items,
      onNavigate: (path) => AppNavigatorPush.push(context, path),
    );
  }

  Future<void> _logout(BuildContext context) async {
    final ok = await AppConfirmDialog.show(
      context,
      title: 'Sign out?',
      message: 'Queued offline changes for this account are discarded. '
          'Anything already synced stays on the server.',
      confirmLabel: 'Sign out',
      icon: Icons.logout,
    );
    if (!ok || !context.mounted) return;
    final services = AppScope.read(context);
    await services.outbox.clearAll();
    await services.auth.logout();
  }

}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.route,
    required this.active,
    required this.onTap,
  });

  final AppRoute route;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.texts;
    return Stack(
      children: [
        if (active)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(width: 3, color: c.sidebarIndicator),
          ),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: active ? c.sidebarHoverBg : Colors.transparent,
              child: Row(
                children: [
                  Icon(
                    route.icon ?? Icons.chevron_right,
                    size: 17,
                    color: active ? c.sidebarIndicator : c.sidebarText,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      route.label,
                      style: t.bodyMedium?.copyWith(
                        color: active ? c.sidebarActive : c.sidebarText,
                        fontWeight:
                            active ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HotelScopePicker extends StatelessWidget {
  const _HotelScopePicker({
    required this.hotels,
    required this.selected,
    required this.isAdmin,
  });

  final List<String> hotels;
  final String selected;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.texts;
    return Container(
      decoration: BoxDecoration(
        color: c.sidebarHoverBg,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: c.sidebarBorder),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Row(
        children: [
          Icon(Icons.apartment_outlined, size: 15, color: c.sidebarLabel),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: selected.isEmpty && isAdmin ? '' : selected,
                isExpanded: true,
                isDense: true,
                dropdownColor: c.surface,
                hint: Text('Select hotel',
                    style: t.labelSmall?.copyWith(color: c.sidebarLabel)),
                style: t.labelMedium?.copyWith(color: c.sidebarActive),
                items: [
                  if (isAdmin)
                    DropdownMenuItem(
                      value: '',
                      child: Text('All hotels',
                          style: t.labelMedium
                              ?.copyWith(color: c.sidebarActive)),
                    ),
                  for (final h in hotels)
                    DropdownMenuItem(
                      value: h,
                      child: Text(h,
                          overflow: TextOverflow.ellipsis,
                          style: t.labelMedium
                              ?.copyWith(color: c.sidebarActive)),
                    ),
                ],
                onChanged: (v) =>
                    AppScope.read(context).hotels.setSelectedHotel(v ?? ''),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
