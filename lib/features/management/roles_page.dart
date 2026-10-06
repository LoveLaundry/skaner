import 'package:flutter/material.dart';

import '../../core/utils/formatting.dart';
import '../../data/resource_controller.dart';
import '../../state/app_scope.dart';
import '../../ui/kit/feedback.dart';
import '../../ui/kit/primitives.dart';
import '../../ui/kit/shell_parts.dart';
import '../../ui/theme.dart';
import '../../ui/kit/data.dart';
import '_management_shared.dart';

/// There is no management roles endpoint — the web app carries no role admin
/// screen. Roles arrive with the signed-in user, so this screen shows the
/// session's role alongside the role vocabulary the app recognises and the
/// staff counts behind each one, read from `/api/employees`.
class RolesPage extends StatefulWidget {
  const RolesPage({super.key});

  @override
  State<RolesPage> createState() => _RolesPageState();
}

class _RolesPageState extends State<RolesPage> {
  late final ResourceController<List<Map<String, dynamic>>> _employees;

  @override
  void initState() {
    super.initState();
    _employees = ResourceController<List<Map<String, dynamic>>>(
      key: 'employees',
      cache: AppScope.read(context).cache,
      fetcher: () async {
        final s = AppScope.read(context);
        return asRows(await s.api.get(mgmt, '/api/employees'));
      },
    )..addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _employees.load(force: true),
    );
  }

  @override
  void dispose() {
    _employees.removeListener(_onChanged);
    _employees.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  /// The roles `AppUser` recognises, from `core/models/common.dart`.
  static const _roles = ['ADMIN', 'MANAGER', 'STAFF'];

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final user = services.auth.user;
    final mine = user?.roleId.toUpperCase() ?? '';
    return Scaffold(
      body: Column(
        children: [
          AppPageHeader(
            title: 'Roles',
          ),
          AppSyncStatusBar(
            status: _employees.status,
            updatedAt: _employees.lastUpdated,
            label: 'Roles',
          ),
          AppOfflineSyncBar(engine: services.sync),
          Expanded(
            child: RefreshIndicator(
              color: context.c.brand,
              onRefresh: () => _employees.load(force: true),
              child: _body(mine),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(String mine) {
    final user = AppScope.read(context).auth.user;
    final staff = _employees.data ?? const <Map<String, dynamic>>[];
    if (_employees.phase == LoadPhase.failed && _employees.data == null) {
      return AppErrorState(
        message: _employees.error,
        onRetry: () => _employees.load(force: true),
      );
    }

    final positions = <String, int>{};
    for (final e in staff) {
      final p = str(e, ['position', 'designation']).trim();
      if (p.isEmpty) continue;
      positions[p] = (positions[p] ?? 0) + 1;
    }
    final top = positions.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
      children: [
        AppCard(
          title: 'Your role',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AppAvatar(name: user?.displayName, size: 40),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.displayName ?? 'Signed in',
                          style: context.texts.titleSmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          user?.authId ?? '',
                          style: context.texts.bodySmall
                              ?.copyWith(color: context.c.fgMuted),
                        ),
                      ],
                    ),
                  ),
                  AppBadge(
                    Fmt.humanise(mine.isEmpty ? 'UNKNOWN' : mine),
                    tone: (user?.isAdmin ?? false)
                        ? AppTone.brand
                        : AppTone.neutral,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                (user?.isAdmin ?? false)
                    ? 'Admins pass every permission check in the app.'
                    : '${user?.permissionList.length ?? 0} explicit permission '
                        'grant(s) on this account.',
                style:
                    context.texts.bodySmall?.copyWith(color: context.c.fgMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppNotice(
          message: 'The web app has no role management screen, so roles are '
              'shown as they arrive with your account rather than edited here.',
          tone: AppTone.info,
        ),
        const SizedBox(height: 14),
        Text('Recognised roles', style: context.texts.titleSmall),
        const SizedBox(height: 8),
        for (final r in _roles)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppCard(
              onTap: r == mine ? null : () => _explain(r),
              trailing: r == mine
                  ? const AppBadge('Yours', tone: AppTone.brand, compact: true)
                  : null,
              child: Row(
                children: [
                  Icon(_iconFor(r), size: 20, color: context.c.fgMuted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          Fmt.humanise(r),
                          style: context.texts.bodyMedium
                              ?.copyWith(color: context.c.fg),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _blurb(r),
                          style: context.texts.bodySmall
                              ?.copyWith(color: context.c.fgMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        Text('Positions on the roster', style: context.texts.titleSmall),
        const SizedBox(height: 8),
        if (top.isEmpty)
          AppCard(
            child: Text(
              'No positions recorded yet.',
              style:
                  context.texts.bodySmall?.copyWith(color: context.c.fgMuted),
            ),
          )
        else
          AppCard(
            child: Column(
              children: [
                for (final p in top.take(10))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            p.key,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.texts.bodyMedium,
                          ),
                        ),
                        Text(
                          '${p.value}',
                          style: context.texts.bodyMedium
                              ?.copyWith(color: context.c.fgMuted),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  static IconData _iconFor(String role) => switch (role) {
        'ADMIN' => Icons.shield_outlined,
        'MANAGER' => Icons.supervisor_account_outlined,
        _ => Icons.badge_outlined,
      };

  static String _blurb(String role) => switch (role) {
        'ADMIN' => 'Full access; bypasses every permission check.',
        'MANAGER' => 'Runs a department; needs explicit grants.',
        _ => 'Individual contributor; needs explicit grants.',
      };

  void _explain(String role) {
    AppToast.info(context, '${Fmt.humanise(role)}: ${_blurb(role)}');
  }
}
