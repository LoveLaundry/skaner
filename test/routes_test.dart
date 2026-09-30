import 'package:flutter_test/flutter_test.dart';
import 'package:love_mobi/nav/app_route.dart';
import 'package:love_mobi/nav/route_registry.dart';
import 'package:love_mobi/ui/shell/app_shell.dart';

void main() {
  setUpAll(AppRouteRegistry.install);

  group('route table', () {
    test('registers every screen once', () {
      final keys = AppRoutes.table.keys.toList();
      expect(keys.toSet().length, keys.length);
    });

    test('every path is unique and absolute', () {
      final paths = AppRoutes.table.values.map((r) => r.path).toList();
      expect(paths.toSet().length, paths.length);
      for (final p in paths) {
        expect(p.startsWith('/'), isTrue, reason: p);
      }
    });

    test('every route has a drawer label, group and icon where required', () {
      for (final r in AppRoutes.table.values) {
        expect(r.label.trim(), isNotEmpty, reason: r.path);
        expect(r.group.trim(), isNotEmpty, reason: r.path);
        if (r.showInDrawer || r.bottomBar) {
          expect(r.icon, isNotNull, reason: r.path);
        }
      }
    });

    test('exactly five bottom-bar tabs, indexed 0..4', () {
      final tabs = AppRoutes.table.values.where((r) => r.bottomBar).toList();
      expect(tabs.length, 5);
      expect(tabs.map((t) => t.tabIndex).toSet(), {0, 1, 2, 3, 4});
    });

    test('the home destination is never a bottom-bar tab', () {
      final home = AppRoutes.lookup(AppRoutes.home);
      if (home != null) expect(home.bottomBar, isFalse);
    });
  });

  group('lookup', () {
    test('prefers a literal segment over a parameter', () {
      expect(AppRoutes.lookup('/quotations/new')!.path, '/quotations/new');
      expect(AppRoutes.lookup('/bills/new')!.path, '/bills/new');
      expect(AppRoutes.lookup('/gate-passes/new')!.path, '/gate-passes/new');
      expect(AppRoutes.lookup('/workers/new')!.path, '/workers/new');
    });

    test('matches parameterised paths', () {
      expect(AppRoutes.lookup('/quotations/abc')!.path, '/quotations/:id');
      expect(AppRoutes.lookup('/bills/9')!.path, '/bills/:id');
      expect(
        AppRoutes.lookup('/hotel-linen-flow/Cinnamon')!.path,
        '/hotel-linen-flow/:hotel',
      );
      expect(AppRoutes.lookup('/linen/garment/LL-77')!.path, '/linen/garment/:code');
    });

    test('rejects a path of the wrong depth', () {
      expect(AppRoutes.lookup('/quotations/abc/extra/extra'), isNull);
      expect(AppRoutes.lookup('/nope'), isNull);
    });

    test('never resolves a dynamic route to a literal sibling', () {
      // `/gate-passes/new` exists, so `/gate-passes/xyz` must still be the
      // detail route rather than silently becoming the create form.
      expect(AppRoutes.lookup('/gate-passes/xyz')!.path, '/gate-passes/:id');
    });
  });

  group('paramsFor', () {
    test('extracts every named parameter', () {
      expect(
        AppRoutes.paramsFor('/quotations/:id/edit', '/quotations/42/edit'),
        {'id': '42'},
      );
      expect(
        AppRoutes.paramsFor('/linen/garment/:code', '/linen/garment/LL-9'),
        {'code': 'LL-9'},
      );
      expect(
        AppRoutes.paramsFor('/gate-passes/:id/slip', '/gate-passes/7/slip'),
        {'id': '7'},
      );
      expect(AppRoutes.paramsFor('/quotations', '/quotations'), <String, String>{});
    });
  });

  group('guest access', () {
    test('only the login and guest pages are open to a signed-out visitor', () {
      final open = AppRoutes.table.values.where((r) => r.guest).map((r) => r.path);
      expect(open, containsAll(<String>[
        AppRoutes.login,
        AppRoutes.guestShop,
        AppRoutes.guestTrack,
        AppRoutes.guestQuotation,
        AppRoutes.guestPickup,
      ]));
      expect(open.length, 5);
    });
  });

  group('bottom bar selection', () {
    List<AppRoute> tabs() => AppRoutes.table.values
        .where((r) => r.bottomBar)
        .toList()
      ..sort((a, b) => (a.tabIndex ?? 99).compareTo(b.tabIndex ?? 99));

    test('every tab owns its own index', () {
      final list = tabs();
      for (var i = 0; i < list.length; i++) {
        expect(AppShell.selectedIndexFor(list, list[i].path), i,
            reason: list[i].path);
      }
    });

    test('a path outside the bar never yields a negative index', () {
      // `NavigationBar` asserts `0 <= selectedIndex < destinations.length`,
      // so the -1 that `indexWhere` returns for a non-tab path took down the
      // whole shell. The admin dashboard is the path that did it in practice.
      final list = tabs();
      for (final path in <String>[
        AppRoutes.dashboard,
        AppRoutes.home,
        AppRoutes.notifications,
        '/management/reports',
        '/gate-passes/9/slip',
        '/nonsense',
      ]) {
        final index = AppShell.selectedIndexFor(list, path);
        expect(index, greaterThanOrEqualTo(0), reason: path);
        expect(index, lessThan(list.length), reason: path);
      }
    });

    test('a detail page under a tab keeps that tab selected', () {
      final list = tabs();
      final quotations = list.firstWhere((r) => r.path == AppRoutes.quotations);
      expect(
        AppShell.selectedIndexFor(list, '${AppRoutes.quotations}/LL-9'),
        list.indexOf(quotations),
      );
    });
  });
}
