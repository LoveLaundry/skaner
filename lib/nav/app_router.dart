import 'package:flutter/material.dart';

import '../state/app_scope.dart';
import '../state/app_services.dart';
import '../ui/shell/app_shell.dart';
import 'app_route.dart';
import 'route_registry.dart';

/// Root navigation.
///
/// Owns the auth gate, the current path the shell highlights, and the
/// push/replace behaviour every screen relies on through [RoutePushScope].
class AppRouter extends StatefulWidget {
  const AppRouter({super.key, required this.services});

  final AppServices services;

  @override
  State<AppRouter> createState() => _AppRouterState();
}

class _AppRouterState extends State<AppRouter> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  late final SyncController _sync = SyncController(
    widget.services.sync,
    widget.services.connectivity,
  );

  String _home = AppRoutes.today;
  bool _restored = false;

  @override
  void initState() {
    super.initState();
    widget.services.auth.addListener(_onAuthChanged);
    _boot();
  }

  @override
  void dispose() {
    widget.services.auth.removeListener(_onAuthChanged);
    _sync.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    final services = widget.services;
    await services.restore();
    if (!mounted) return;
    if (services.auth.isAuthenticated) await services.loadHotels();
    if (!mounted) return;
    setState(() {
      _restored = true;
      _home = _homeFor(services);
    });
  }

  /// The hotel list is derived from the signed-in user's records, so it is
  /// rebuilt whenever the session changes rather than only at boot.
  void _onAuthChanged() {
    if (!_restored) return;
    widget.services.loadHotels();
  }

  String _homeFor(AppServices services) {
    if (!services.auth.isAuthenticated) return AppRoutes.login;
    return services.auth.isAdmin ? AppRoutes.dashboard : AppRoutes.today;
  }

  /// Whether [path] resolves to a destination a signed-out visitor may open.
  bool _isGuestPath(String path) => AppRoutes.lookup(path)?.guest ?? false;

  Widget _buildScreen(String path, AppRoute route, Map<String, String> params) {
    final page = Builder(
      builder: (context) {
        RouteParams.bind(params);
        try {
          return route.builder(context);
        } finally {
          RouteParams.unbind();
        }
      },
    );

    if (_isGuestPath(path)) {
      return AppScope(
        services: widget.services,
        sync: _sync,
        child: page,
      );
    }
    return AppScope(
      services: widget.services,
      sync: _sync,
      child: RoutePushScope(
        push: _push,
        child: AppShell(currentPath: path, child: page),
      ),
    );
  }

  void _push(String path) {
    final route = AppRoutes.lookup(path);
    if (route == null) {
      _push(_home);
      return;
    }
    if (!route.guest && !widget.services.auth.isAuthenticated) {
      _replace(AppRoutes.login);
      return;
    }
    if (!route.isVisibleTo(widget.services)) {
      _push(_home);
      return;
    }
    final params = AppRoutes.paramsFor(route.path, path);
    _navigatorKey.currentState?.push(
      MaterialPageRoute<void>(
        settings: RouteSettings(name: path),
        builder: (context) => _buildScreen(path, route, params),
      ),
    );
  }

  /// Replaces the whole stack — used for the auth gate only.
  void _replace(String path) {
    final route = AppRoutes.lookup(path);
    if (route == null) return;
    final params = AppRoutes.paramsFor(route.path, path);
    _navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute<void>(
        settings: RouteSettings(name: path),
        builder: (context) => _buildScreen(path, route, params),
      ),
      (r) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final services = widget.services;
    return ListenableBuilder(
      listenable: Listenable.merge([services.auth, services.theme]),
      builder: (context, _) {
        if (!_restored) return const _BootSplash();

        if (!services.auth.isAuthenticated) return _signedOutNavigator();
        // Never mutate state from a builder-phase listener. A leftover `/login`
        // home simply means the session changed while the app was backgrounded;
        // deriving the destination here keeps the two in step without setState.
        final home = _home == AppRoutes.login ? _homeFor(services) : _home;
        if (home != _home) _home = home;
        return _signedInNavigator();
      },
    );
  }

  /// Signed out: a single stack whose only destination is the login screen. The
  /// shell is not mounted here, so no drawer or bottom bar can be reached.
  Widget _signedOutNavigator() {
    return Navigator(
      key: _navigatorKey,
      onGenerateRoute: (settings) {
        final route = AppRoutes.lookup(settings.name ?? '');
        if (route == null || !route.guest) {
          // A signed-out visitor reaching for a protected path lands on login.
          return MaterialPageRoute<void>(
            settings: const RouteSettings(name: AppRoutes.login),
            builder: (_) => _buildScreen(
              AppRoutes.login,
              AppRoutes.lookup(AppRoutes.login)!,
              const {},
            ),
          );
        }
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => _buildScreen(settings.name!, route, const {}),
        );
      },
    );
  }

  /// Signed in: the home destination plus whatever the operator pushed on top.
  /// Routes are generated from their path, so a deep link resolves to the same
  /// screen the web app would show.
  Widget _signedInNavigator() {
    final home = AppRoutes.lookup(_home)!;
    return Navigator(
      key: _navigatorKey,
      onGenerateInitialRoutes: (navigator, initial) => [
        MaterialPageRoute<void>(
          settings: RouteSettings(name: _home),
          builder: (context) => _buildScreen(_home, home, const {}),
        ),
      ],
      onGenerateRoute: (settings) {
        final name = settings.name ?? '';
        final route = AppRoutes.lookup(name);
        if (route == null) {
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => _buildScreen(_home, home, const {}),
          );
        }
        if (!route.guest && !route.isVisibleTo(widget.services)) {
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => _buildScreen(_home, home, const {}),
          );
        }
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (context) =>
              _buildScreen(name, route, AppRoutes.paramsFor(route.path, name)),
        );
      },
    );
  }
}

class _BootSplash extends StatelessWidget {
  const _BootSplash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
