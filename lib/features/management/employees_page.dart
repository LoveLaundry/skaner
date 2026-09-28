import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/utils/formatting.dart';
import '../../data/resource_controller.dart';
import '../../state/app_scope.dart';
import '../../ui/kit/data.dart';
import '../../ui/kit/feedback.dart';
import '../../ui/kit/inputs.dart';
import '../../ui/kit/primitives.dart';
import '../../ui/kit/shell_parts.dart';
import '../../ui/theme.dart';
import '_management_shared.dart';
import 'employee_detail_page.dart';
import 'employee_form_page.dart';

/// Port of `pages/management-employees.tsx`. The web app paginates and filters
/// on the client; the list here loads the whole collection once and filters
/// locally, which is what a phone form of the same screen can afford.
class EmployeesPage extends StatefulWidget {
  const EmployeesPage({super.key});

  @override
  State<EmployeesPage> createState() => _EmployeesPageState();
}

class _EmployeesPageState extends State<EmployeesPage> {
  late final ResourceController<List<Map<String, dynamic>>> _controller;
  final _search = TextEditingController();
  Timer? _debounce;

  String _status = '';
  String _department = '';

  @override
  void initState() {
    super.initState();
    _controller = ResourceController<List<Map<String, dynamic>>>(
      key: 'employees',
      cache: AppScope.read(context).cache,
      fetcher: _fetch,
    );
    _controller.addListener(_onLoaded);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _controller.removeListener(_onLoaded);
    _controller.dispose();
    super.dispose();
  }

  void _onLoaded() {
    if (mounted) setState(() {});
  }

  Future<List<Map<String, dynamic>>> _fetch() async {
    final services = AppScope.read(context);
    final payload = await services.api.get(
      mgmt,
      '/api/employees',
      query: {'search': _search.text.trim()},
    );
    return asRows(payload);
  }

  Future<void> _reload() => _controller.load(force: true);

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) _reload();
    });
  }

  List<Map<String, dynamic>> get _rows => _controller.data ?? const [];

  List<Map<String, dynamic>> get _visible {
    final status = _status;
    final department = _department;
    return _rows.where((r) {
      if (status == 'ACTIVE' && !employeeIsActive(r)) return false;
      if (status == 'INACTIVE' && employeeIsActive(r)) return false;
      if (department.isNotEmpty &&
          employeeDepartment(r).toUpperCase() != department.toUpperCase()) {
        return false;
      }
      return true;
    }).toList();
  }

  /// Departments come from the loaded rows, not a static list: the web app
  /// hard-codes seven, but the records are the only honest source.
  List<String> get _departments {
    final set = <String>{};
    for (final r in _rows) {
      final d = employeeDepartment(r);
      if (d != '—') set.add(d);
    }
    final out = set.toList()..sort();
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final visible = _visible;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Employees'),
        actions: [
          AppButton.icon(
            icon: Icons.person_add_alt_1_outlined,
            tooltip: 'Add employee',
            variant: AppButtonVariant.primary,
            onPressed: () => _openForm(null),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          AppSyncStatusBar(
            status: _controller.status,
            updatedAt: _controller.lastUpdated,
            label: 'Employees',
          ),
          AppOfflineSyncBar(engine: services.sync),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: AppTextInput(
              controller: _search,
              hint: 'Search employees…',
              icon: Icons.search,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              suffix: _search.text.isEmpty
                  ? null
                  : AppButton.icon(
                      icon: Icons.close,
                      tooltip: 'Clear search',
                      size: AppButtonSize.iconSm,
                      onPressed: () {
                        _search.clear();
                        _reload();
                        setState(() {});
                      },
                    ),
            ),
          ),
          _filterBar(),
          Expanded(
            child: RefreshIndicator(
              color: context.c.brand,
              onRefresh: _reload,
              child: _list(visible),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterBar() {
    final departments = _departments;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            children: [
              AppFilterChip(
                label: 'All',
                count: _rows.length,
                selected: _status.isEmpty,
                onTap: () => setState(() => _status = ''),
              ),
              const SizedBox(width: 8),
              AppFilterChip(
                label: 'Active',
                selected: _status == 'ACTIVE',
                onTap: () => setState(() => _status = 'ACTIVE'),
              ),
              const SizedBox(width: 8),
              AppFilterChip(
                label: 'Inactive',
                selected: _status == 'INACTIVE',
                onTap: () => setState(() => _status = 'INACTIVE'),
              ),
              for (final d in departments) ...[
                const SizedBox(width: 8),
                AppFilterChip(
                  label: d,
                  selected: _department == d,
                  onTap: () => setState(
                    () => _department = _department == d ? '' : d,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _list(List<Map<String, dynamic>> visible) {
    if (_controller.phase == LoadPhase.failed && _rows.isEmpty) {
      return AppErrorState(
        message: _controller.error,
        onRetry: _reload,
      );
    }
    if (_controller.isLoading && _rows.isEmpty) {
      return const AppSkeletonList(count: 8);
    }
    if (visible.isEmpty) {
      return AppEmptyState(
        title: _rows.isEmpty ? 'No employees yet' : 'No matching employees',
        message: _rows.isEmpty
            ? 'Add your first employee to get started.'
            : 'Try a different search or filter.',
        icon: Icons.people_outline,
        action: _rows.isEmpty
            ? AppButton(
                label: 'Add employee',
                variant: AppButtonVariant.primary,
                icon: Icons.add,
                onPressed: () => _openForm(null),
              )
            : null,
      );
    }

    return AppDataTable<Map<String, dynamic>>(
      rows: visible,
      onRowTap: (r) => _openDetail(r),
      rowLeading: (context, r) => AppAvatar(name: employeeName(r), size: 34),
      rowTrailing: (context, r) => _rowActions(r),
      columns: [
        AppDataColumn(
          label: 'Name',
          value: employeeName,
          minWidth: 120,
        ),
        AppDataColumn(
          label: 'Code',
          value: (r) {
            final code = str(r, ['employee_code', 'code']);
            return code.isEmpty ? '—' : '#$code';
          },
        ),
        AppDataColumn(label: 'Department', value: employeeDepartment),
        AppDataColumn(
          label: 'Designation',
          value: (r) => str(r, ['designation', 'position'], '—'),
        ),
        AppDataColumn(
          label: 'Base salary',
          value: (r) => Fmt.money(numOf(r, ['base_salary', 'basic_salary'])),
        ),
        AppDataColumn(
          label: 'Status',
          value: (r) => employeeIsActive(r) ? 'Active' : 'Inactive',
        ),
      ],
    );
  }

  Widget _rowActions(Map<String, dynamic> row) {
    final id = str(row, ['id', '_id']);
    final isActive = employeeIsActive(row);
    return AppButton.icon(
      icon: isActive ? Icons.person_off_outlined : Icons.how_to_reg_outlined,
      tooltip: isActive ? 'Deactivate' : 'Activate',
      size: AppButtonSize.iconSm,
      variant:
          isActive ? AppButtonVariant.dangerGhost : AppButtonVariant.secondary,
      onPressed: id.isEmpty ? null : () => _toggleActive(row, isActive),
    );
  }

  /// The web app deactivates with `DELETE /api/employees/{id}` and reactivates
  /// with `POST /api/employees/{id}/activate`; there is no patch-based toggle.
  Future<void> _toggleActive(Map<String, dynamic> row, bool isActive) async {
    final id = str(row, ['id', '_id']);
    final name = employeeName(row);
    final confirmed = await AppConfirmDialog.show(
      context,
      title: isActive ? 'Deactivate $name?' : 'Activate $name?',
      message: isActive
          ? 'Their history is kept, but they stop appearing in attendance and payroll.'
          : 'They will start appearing in attendance and payroll again.',
      confirmLabel: isActive ? 'Deactivate' : 'Activate',
      destructive: isActive,
    );
    if (!confirmed || !mounted) return;

    final services = AppScope.read(context);
    final ok = await runMgmtWrite(
      context,
      () => isActive
          ? services.api.delete(mgmt, '/api/employees/$id')
          : services.api.post(mgmt, '/api/employees/$id/activate'),
      success: isActive ? 'Employee deactivated' : 'Employee activated',
    );
    if (ok) await _reload();
  }

  Future<void> _openForm(Map<String, dynamic>? row) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EmployeeFormPage(employee: row),
      ),
    );
    if (saved == true) await _reload();
  }

  void _openDetail(Map<String, dynamic> row) {
    final id = str(row, ['id', '_id']);
    if (id.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EmployeeDetailPage(employeeId: id),
      ),
    );
  }
}
