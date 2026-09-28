import 'package:flutter/material.dart';

import '../../core/utils/formatting.dart';
import '../../state/app_scope.dart';
import '../../ui/kit/feedback.dart';
import '../../ui/kit/inputs.dart';
import '../../ui/kit/primitives.dart';
import '../../ui/kit/shell_parts.dart';
import '../../ui/theme.dart';

/// There is no management permissions endpoint and no permission editor in the
/// web app. Permissions arrive as a grant list on the signed-in user, so this
/// screen is the read-only view of exactly what this account holds, grouped by
/// the module they belong to.
class PermissionsPage extends StatefulWidget {
  const PermissionsPage({super.key});

  @override
  State<PermissionsPage> createState() => _PermissionsPageState();
}

class _PermissionsPageState extends State<PermissionsPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final user = services.auth.user;
    final isAdmin = user?.isAdmin ?? false;
    final granted = user?.permissionList ?? const <String>[];
    final visible = granted
        .where((p) => _query.isEmpty || p.toLowerCase().contains(_query))
        .toList()
      ..sort();

    return Scaffold(
      appBar: AppBar(title: const Text('Permissions')),
      body: Column(
        children: [
          AppOfflineSyncBar(engine: services.sync),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
              children: [
                AppCard(
                  title: 'Effective access',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              user?.displayName ?? 'Signed in',
                              style: context.texts.titleSmall,
                            ),
                          ),
                          AppBadge(
                            Fmt.humanise(user?.roleId ?? 'Unknown'),
                            tone: isAdmin ? AppTone.brand : AppTone.neutral,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (isAdmin)
                        const AppNotice(
                          message:
                              'Admin accounts pass every permission check, '
                              'so the grant list below is not what limits them.',
                          tone: AppTone.brand,
                        )
                      else
                        AppNotice(
                          message: '${granted.length} explicit grant(s). A '
                              'permission missing from this list is denied.',
                          tone: granted.isEmpty
                              ? AppTone.warning
                              : AppTone.neutral,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                AppTextInput(
                  hint: 'Filter permissions',
                  icon: Icons.search,
                  onChanged: (v) =>
                      setState(() => _query = v.trim().toLowerCase()),
                ),
                const SizedBox(height: 12),
                if (visible.isEmpty)
                  AppEmptyState(
                    title: isAdmin ? 'Nothing to list' : 'No grants',
                    message: isAdmin
                        ? 'Admins hold every permission implicitly.'
                        : _query.isEmpty
                            ? 'This account has no explicit grants.'
                            : 'No grant matches "$_query".',
                    icon: Icons.lock_person_outlined,
                  )
                else
                  AppCard(
                    title: '${visible.length} permission(s)',
                    child: Column(
                      children: [
                        for (final group in _grouped(visible))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  group.module,
                                  style: context.texts.labelMedium
                                      ?.copyWith(color: context.c.fgMuted),
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    for (final p in group.permissions)
                                      AppBadge(
                                        p,
                                        tone: AppTone.success,
                                        icon: Icons.check,
                                        compact: true,
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                AppNotice(
                  message: 'Grants come from your account in the login '
                      'response; the web app edits them on the user record, not '
                      'here.',
                  tone: AppTone.neutral,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Permission strings are dotted and module-first, e.g. `bills.approve`.
  static List<({String module, List<String> permissions})> _grouped(
    List<String> permissions,
  ) {
    final byModule = <String, List<String>>{};
    for (final p in permissions) {
      final module = p.contains('.') ? p.split('.').first : 'general';
      byModule.putIfAbsent(module, () => []).add(p);
    }
    final keys = byModule.keys.toList()..sort();
    return [
      for (final k in keys)
        (module: Fmt.humanise(k), permissions: byModule[k]!),
    ];
  }
}
