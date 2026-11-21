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

/// There is no management departments endpoint. The department is an employee
/// field (`department` on `/api/employees`) and the web app treats it as a fixed
/// vocabulary, so this screen is the read-only rollup of that field.
class DepartmentsPage extends StatefulWidget {
  const DepartmentsPage({super.key});

  @override
  State<DepartmentsPage> createState() => _DepartmentsPageState();
}

class _DepartmentsPageState extends State<DepartmentsPage> {
  /// `DEPARTMENTS` from `features/workers/types.ts`, the same list the web
  /// app's employee form offers.
  static const _known = [
    'WASHING',
    'PRESSING',
    'FINISHING',
    'PACKING',
    'DRY_CLEANING',
    'DELIVERY',
    'GENERAL',
  ];

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

  /// Every department seen on an employee, with the headcount in each.
  List<(String, int, int)> get _rollup {
    final all = _employees.data ?? const <Map<String, dynamic>>[];
    final total = <String, int>{};
    final active = <String, int>{};
    for (final e in all) {
      final d = str(e, ['department']).toUpperCase();
      if (d.isEmpty) continue;
      total[d] = (total[d] ?? 0) + 1;
      if (employeeIsActive(e)) active[d] = (active[d] ?? 0) + 1;
    }
    final out = total.entries
        .map((e) => (e.key, e.value, active[e.key] ?? 0))
        .toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return Scaffold(
      body: Column(
        children: [
          AppPageHeader(
            title: 'Departments',
          ),
          AppSyncStatusBar(
            status: _employees.status,
            updatedAt: _employees.lastUpdated,
            label: 'Departments',
          ),
          AppOfflineSyncBar(engine: services.sync),
          Expanded(
            child: RefreshIndicator(
              color: context.c.brand,
              onRefresh: () => _employees.load(force: true),
              child: _body(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_employees.phase == LoadPhase.failed && _employees.data == null) {
      return AppErrorState(
        message: _employees.error,
        onRetry: () => _employees.load(force: true),
      );
    }
    if (_employees.isLoading && _employees.data == null) {
      return const AppSkeletonList();
    }
    final rollup = _rollup;
    final peak = rollup.fold<int>(1, (m, r) => r.$2 > m ? r.$2 : m);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
      children: [
        AppNotice(
          message: 'Departments are fixed in the employee record — the web app '
              'offers the same list in its employee form and has no department '
              'settings, so this screen is read-only.',
          tone: AppTone.info,
        ),
        const SizedBox(height: 14),
        if (rollup.isEmpty)
          const AppEmptyState(
            title: 'No staff yet',
            message: 'Departments appear once employees are added.',
            icon: Icons.apartment_outlined,
          )
        else ...[
          for (final (name, count, activeCount) in rollup)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            Fmt.humanise(name),
                            style: context.texts.titleSmall,
                          ),
                        ),
                        AppBadge(
                          '$count staff',
                          tone: AppTone.brand,
                          compact: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(Radii.pill),
                      child: LinearProgressIndicator(
                        value: count / peak,
                        minHeight: 8,
                        backgroundColor: context.c.surface3,
                        valueColor: AlwaysStoppedAnimation(context.c.brand),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$activeCount active · ${count - activeCount} inactive',
                      style: context.texts.bodySmall
                          ?.copyWith(color: context.c.fgMuted),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          AppCard(
            title: 'Unused in the roster',
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final d in _known)
                  if (!rollup.any((r) => r.$1 == d))
                    AppBadge(Fmt.humanise(d),
                        tone: AppTone.neutral, compact: true),
                if (rollup.isEmpty) Text('—', style: context.texts.bodySmall),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
