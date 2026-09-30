import 'package:flutter/material.dart';

import '../../config/api_config.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/models/json.dart' as json;
import '../../core/models/worker.dart';
import '../../core/utils/formatting.dart';
import '../../data/resource_controller.dart';
import '../../state/app_scope.dart';
import '../../ui/kit/data.dart';
import '../../ui/kit/feedback.dart';
import '../../ui/kit/inputs.dart';
import '../../ui/kit/primitives.dart';
import '../../ui/kit/shell_parts.dart';
import '../quotations/shared_widgets.dart';
import 'worker_detail_page.dart';
import 'worker_form_page.dart';
import 'worker_payroll_page.dart';
import '../../ui/theme.dart';

/// Port of `features/workers/pages/workers-page.tsx`.
///
/// The list is small enough to hold in one payload, so search and the
/// department filter run on the rows already on screen rather than costing a
/// round trip each keystroke. Writes go through the workers service and then
/// re-read the list, so a delete queued offline still disappears from the card
/// it was removed from.
class WorkersPage extends StatefulWidget {
  const WorkersPage({super.key});

  @override
  State<WorkersPage> createState() => _WorkersPageState();
}

class _WorkersPageState extends State<WorkersPage> {
  final _searchCtrl = TextEditingController();
  late final ResourceController<List<Worker>> _controller;

  String _search = '';
  String _department = '';

  @override
  void initState() {
    super.initState();
    _controller = ResourceController(
      key: 'workers',
      cache: AppScope.read(context).cache,
      fetcher: _fetch,
    );
    _controller.addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reload();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<List<Worker>> _fetch() async {
    final payload =
        await AppScope.read(context).api.get(ServiceNames.workers, '/workers');
    return json.unwrapList(payload).items.map(Worker.fromJson).toList();
  }

  Future<void> _reload() => _controller.load(force: true);

  List<Worker> get _all => _controller.data ?? const [];

  List<Worker> get _rows {
    final q = _search.trim().toLowerCase();
    return _all.where((w) {
      final matchesSearch = q.isEmpty ||
          w.workerName.toLowerCase().contains(q) ||
          w.departmentLabel.toLowerCase().contains(q) ||
          (w.phone ?? '').toLowerCase().contains(q);
      final matchesDepartment =
          _department.isEmpty || w.department == _department;
      return matchesSearch && matchesDepartment;
    }).toList();
  }

  bool get _hasFilters => _search.trim().isNotEmpty || _department.isNotEmpty;

  List<OpsMetric> get _metrics {
    final all = _all;
    final active = all.where((w) => w.isActive).length;
    return [
      OpsMetric(
        id: 'total',
        label: 'Total staff',
        value: '${all.length}',
        icon: Icons.groups_outlined,
        tone: AppTone.info,
      ),
      OpsMetric(
        id: 'active',
        label: 'Active now',
        value: '$active',
        icon: Icons.person_outline,
        tone: AppTone.success,
      ),
      OpsMetric(
        id: 'inactive',
        label: 'Inactive',
        value: '${all.length - active}',
        icon: Icons.person_off_outlined,
        tone: AppTone.neutral,
      ),
      OpsMetric(
        id: 'depts',
        label: 'Departments',
        value: '${all.map((w) => w.department).toSet().length}',
        icon: Icons.apartment_outlined,
        tone: AppTone.brand,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final c = context.c;
    final rows = _rows;
    final loading = _controller.isLoading && _all.isEmpty;

    return Scaffold(
      body: Column(
        children: [
          AppPageHeader(
            title: 'Staff',
            actions: [
              AppButton.icon(
                icon: Icons.payments_outlined,
                tooltip: 'Payroll',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => const WorkerPayrollPage()),
                ),
              ),
              AppButton.icon(
                icon: Icons.refresh,
                tooltip: 'Refresh',
                loading: _controller.isLoading,
                onPressed: _reload,
              ),
            ],
          ),
          AppSyncStatusBar(
            status: _controller.status,
            updatedAt: _controller.lastUpdated,
            label: 'Staff',
          ),
          AppOfflineSyncBar(engine: services.sync),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: AppTextInput(
              controller: _searchCtrl,
              hint: 'Search name, department or phone…',
              icon: Icons.search,
              onChanged: (v) => setState(() => _search = v),
              suffix: _search.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      tooltip: 'Clear search',
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _search = '');
                      },
                    ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                AppFilterChip(
                  label: 'All departments',
                  selected: _department.isEmpty,
                  count: _all.length,
                  onTap: () => setState(() => _department = ''),
                ),
                for (final d in departments) ...[
                  const SizedBox(width: 8),
                  AppFilterChip(
                    label: departmentLabels[d]!,
                    selected: _department == d,
                    count: _all.where((w) => w.department == d).length,
                    onTap: () =>
                        setState(() => _department = _department == d ? '' : d),
                  ),
                ],
              ],
            ),
          ),
          CompactMetrics(items: _metrics),
          if (_hasFilters)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
              child: Row(
                children: [
                  Text(
                    '${Fmt.count(rows.length)} of ${Fmt.count(_all.length)} shown',
                    style: context.texts.labelSmall?.copyWith(color: c.fgMuted),
                  ),
                  const Spacer(),
                  AppButton(
                    label: 'Reset',
                    variant: AppButtonVariant.ghost,
                    size: AppButtonSize.xs,
                    icon: Icons.filter_alt_off_outlined,
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() {
                        _search = '';
                        _department = '';
                      });
                    },
                  ),
                ],
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              color: c.brand,
              onRefresh: _reload,
              child: _controller.phase == LoadPhase.failed && _all.isEmpty
                  ? AppErrorState(message: _controller.error, onRetry: _reload)
                  : loading
                      ? const AppSkeletonList()
                      : rows.isEmpty
                          ? ListView(
                              children: [
                                SizedBox(
                                  height:
                                      MediaQuery.of(context).size.height * 0.4,
                                  child: AppEmptyState(
                                    title: _hasFilters
                                        ? 'No staff match your filters'
                                        : 'No staff yet',
                                    message: _hasFilters
                                        ? 'Try a different search or department.'
                                        : 'Add your first team member to get started.',
                                    icon: Icons.groups_outlined,
                                    action: _hasFilters
                                        ? AppButton(
                                            label: 'Clear filters',
                                            variant: AppButtonVariant.secondary,
                                            onPressed: () {
                                              _searchCtrl.clear();
                                              setState(() {
                                                _search = '';
                                                _department = '';
                                              });
                                            },
                                          )
                                        : AppButton(
                                            label: 'Add staff',
                                            variant: AppButtonVariant.primary,
                                            icon: Icons.add,
                                            onPressed: _openCreate,
                                          ),
                                  ),
                                ),
                              ],
                            )
                          : AppDataTable<Worker>(
                              columns: const [
                                AppDataColumn<Worker>(
                                  label: 'Department',
                                  value: _departmentLabel,
                                ),
                                AppDataColumn<Worker>(
                                  label: 'Phone',
                                  value: _phone,
                                ),
                                AppDataColumn<Worker>(
                                  label: 'Joined',
                                  value: _joined,
                                ),
                              ],
                              rows: rows,
                              onRowTap: _openDetail,
                              rowLeading: (_, w) => AppAvatar(
                                name: w.workerName,
                                size: 34,
                                icon: Icons.person_outline,
                              ),
                              rowTrailing: (_, w) => AppBadge(
                                w.isActive ? 'Active' : 'Inactive',
                                tone: w.isActive
                                    ? AppTone.success
                                    : AppTone.neutral,
                                compact: true,
                              ),
                            ),
            ),
          ),
        ],
      ),
    );
  }

  static String _departmentLabel(Worker w) => w.departmentLabel;

  static String _phone(Worker w) => w.phone ?? '—';

  static String _joined(Worker w) => Fmt.date(w.joinedDate);

  Future<void> _openCreate() async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const WorkerFormPage()));
    if (mounted) _reload();
  }

  void _openDetail(Worker worker) {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(
      builder: (_) => WorkerDetailPage(workerId: worker.id),
    ))
        .then((_) {
      if (mounted) _reload();
    });
  }
}

/// Shared by the list and the detail screen so both drop a worker the same
/// way: confirm, delete, re-read.
Future<bool> deleteWorker(BuildContext context, Worker worker) async {
  final ok = await AppConfirmDialog.show(
    context,
    title: 'Delete ${worker.workerName}?',
    message:
        'This removes the worker from the roster. Their daily logs are kept.',
    confirmLabel: 'Delete',
    destructive: true,
  );
  if (!ok || !context.mounted) return false;
  try {
    final result = await AppScope.read(context)
        .api
        .delete(ServiceNames.workers, '/workers/${worker.id}');
    if (context.mounted) {
      if (result is QueuedResponse) {
        AppToast.info(context, 'Offline — removal queued and will sync');
      } else {
        AppToast.success(context, 'Deleted ${worker.workerName}');
      }
    }
    return true;
  } on ApiException catch (e) {
    if (context.mounted) AppToast.error(context, e.message);
    return false;
  }
}
