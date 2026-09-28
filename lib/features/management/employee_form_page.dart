import 'package:flutter/material.dart';

import '../../core/utils/formatting.dart';
import '../../data/resource_controller.dart';
import '../../state/app_scope.dart';
import '../../ui/kit/feedback.dart';
import '../../ui/kit/inputs.dart';
import '../../ui/kit/primitives.dart';
import '../../ui/theme.dart';
import '_management_shared.dart';

/// Port of the employee form in `management-employees.tsx`. The field set is
/// the web app's exactly, including the pay-frequency dependent rate inputs,
/// because payroll reads all of them server-side.
class EmployeeFormPage extends StatefulWidget {
  const EmployeeFormPage({super.key, this.employee});

  /// `null` creates, non-null edits.
  final Map<String, dynamic>? employee;

  @override
  State<EmployeeFormPage> createState() => _EmployeeFormPageState();
}

class _EmployeeFormPageState extends State<EmployeeFormPage> {
  static const _departments = [
    'WASHING',
    'PRESSING',
    'FINISHING',
    'PACKING',
    'DRY_CLEANING',
    'DELIVERY',
    'GENERAL',
  ];

  static const _salaryTypes = ['MONTHLY', 'WEEKLY', 'DAILY', 'CONTRACT'];
  static const _salaryTypeLabels = {
    'MONTHLY': 'Monthly',
    'WEEKLY': 'Weekly',
    'DAILY': 'Daily',
    'CONTRACT': 'Contract',
    'FIXED_MONTHLY': 'Monthly (fixed)',
  };

  static const _allowanceTypes = [
    ('FIXED', 'Fixed (full amount every period)'),
    ('ADJUSTED', 'Adjusted (absences reduce it, paid leave counts)'),
    ('ATTENDANCE', 'Attendance (only days worked, paid leave excluded)'),
  ];

  static const _epfBases = [
    ('ADJUSTED', 'Adjusted base (period, after absences, paid leaves count)'),
    ('ATTENDANCE', 'Attendance base (only days worked, leaves excluded)'),
    ('FULL', 'Full base (basic salary, always / 30-day)'),
  ];

  final Map<String, dynamic> _values = {};
  final Map<String, String> _errors = {};
  final Map<String, TextEditingController> _numbers = {};
  bool _busy = false;
  bool _dirty = false;

  bool get _isEdit => widget.employee != null;

  @override
  void initState() {
    super.initState();
    _seed();
  }

  void _seed() {
    final e = widget.employee;
    for (final key in _numberKeys) {
      final controller = TextEditingController();
      if (e != null) {
        final v = e[key];
        if (v != null) controller.text = numOf(e, [key]).toString();
      }
      _numbers[key] = controller;
    }
    _values.addAll({
      'name': e == null ? '' : str(e, ['name', 'employee_name']),
      'position': e == null ? '' : str(e, ['position', 'designation']),
      'department': e == null || employeeDepartment(e) == '—'
          ? 'GENERAL'
          : employeeDepartment(e),
      'salary_type': e == null ? 'MONTHLY' : str(e, ['salary_type'], 'MONTHLY'),
      'allowance_type':
          e == null ? 'FIXED' : str(e, ['allowance_type'], 'FIXED'),
      'epf_base': e == null ? 'ADJUSTED' : str(e, ['epf_base'], 'ADJUSTED'),
      'attendance_required': e == null ? true : employeeAttendanceRequired(e),
      'phone': e == null ? '' : str(e, ['phone']),
      'nic': e == null ? '' : str(e, ['nic']),
      'joined_date': e == null ? null : dateOf(e, ['joined_date', 'join_date']),
      'leaving_date': e == null ? null : dateOf(e, ['leaving_date']),
      'notes': e == null ? '' : str(e, ['notes']),
      'is_active': e == null ? true : employeeIsActive(e),
    });
  }

  static const _numberKeys = [
    'basic_salary',
    'daily_rate',
    'weekly_rate',
    'contract_amount',
    'overtime_rate',
    'allowance',
    'epf_rate',
    'etf_rate',
  ];

  @override
  void dispose() {
    for (final c in _numbers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _set(String key, dynamic value) {
    setState(() {
      _values[key] = value;
      _dirty = true;
      _errors.remove(key);
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty || _busy,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await AppConfirmDialog.show(
          context,
          title: 'Discard changes?',
          message: 'This employee has unsaved edits.',
          confirmLabel: 'Discard',
          destructive: true,
        );
        if (leave && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEdit ? 'Edit employee' : 'Add employee'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: AppButton(
                label: _isEdit ? 'Save' : 'Create',
                variant: AppButtonVariant.primary,
                size: AppButtonSize.sm,
                loading: _busy,
                onPressed: _busy ? null : _submit,
              ),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
          children: [
            AppField(
              label: 'Full name',
              required: true,
              error: _errors['name'],
              child: AppTextInput(
                initialValue: str(_values, ['name']),
                hint: 'Full name',
                textCapitalization: TextCapitalization.words,
                autofocus: !_isEdit,
                onChanged: (v) => _set('name', v),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AppField(
                    label: 'Position',
                    child: AppTextInput(
                      initialValue: str(_values, ['position']),
                      hint: 'Position',
                      textCapitalization: TextCapitalization.words,
                      onChanged: (v) => _set('position', v),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppField(
                    label: 'Department',
                    child: AppSearchableSelect<String>(
                      value: str(_values, ['department']),
                      searchable: false,
                      options: [
                        for (final d in _departments)
                          AppSelectOption(value: d, label: Fmt.humanise(d)),
                      ],
                      onChanged: (v) => _set('department', v ?? 'GENERAL'),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            AppField(
              label: 'Pay frequency',
              child: AppSearchableSelect<String>(
                value: str(_values, ['salary_type']),
                searchable: false,
                options: [
                  for (final t in _salaryTypes)
                    AppSelectOption(
                      value: t,
                      label: _salaryTypeLabels[t] ?? t,
                    ),
                ],
                onChanged: (v) => _set('salary_type', v ?? 'MONTHLY'),
              ),
            ),
            const SizedBox(height: 6),
            AppNotice(
              message:
                  'Attendance required means pay is prorated by days worked. '
                  'Turn it off for a fixed arrangement such as a contract or '
                  'water-disposal worker.',
              tone: AppTone.info,
            ),
            const SizedBox(height: 10),
            SwitchListTile.adaptive(
              value: boolOf(_values, ['attendance_required']),
              onChanged: (v) => _set('attendance_required', v),
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Attendance required for salary',
                style: context.texts.bodyMedium,
              ),
              subtitle: Text(
                'Off = fixed salary, no attendance needed',
                style:
                    context.texts.bodySmall?.copyWith(color: context.c.fgFaint),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AppField(
                    label: 'Phone',
                    child: AppTextInput(
                      initialValue: str(_values, ['phone']),
                      keyboardType: TextInputType.phone,
                      onChanged: (v) => _set('phone', v),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppField(
                    label: 'NIC',
                    child: AppTextInput(
                      initialValue: str(_values, ['nic']),
                      onChanged: (v) => _set('nic', v),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _money('basic_salary', 'Basic salary (Rs. / month)'),
            _money('daily_rate', 'Daily rate (Rs. / day)'),
            _money('weekly_rate', 'Weekly rate (Rs. / week)'),
            _money('contract_amount', 'Contract amount (Rs. / period)'),
            _money('overtime_rate', 'Overtime rate (Rs. / hr)'),
            _money('allowance', 'Allowance (Rs.)'),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _number('epf_rate', 'EPF rate %'),
                ),
                const SizedBox(width: 10),
                Expanded(child: _number('etf_rate', 'ETF rate %')),
              ],
            ),
            const SizedBox(height: 14),
            AppField(
              label: 'Allowance type',
              child: AppSearchableSelect<String>(
                value: str(_values, ['allowance_type']),
                searchable: false,
                options: [
                  for (final (value, label) in _allowanceTypes)
                    AppSelectOption(value: value, label: label),
                ],
                onChanged: (v) => _set('allowance_type', v ?? 'FIXED'),
              ),
            ),
            const SizedBox(height: 14),
            AppField(
              label: 'EPF base',
              child: AppSearchableSelect<String>(
                value: str(_values, ['epf_base']),
                searchable: false,
                options: [
                  for (final (value, label) in _epfBases)
                    AppSelectOption(value: value, label: label),
                ],
                onChanged: (v) => _set('epf_base', v ?? 'ADJUSTED'),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AppDateField(
                    label: 'Joined date',
                    value: dateOf(_values, ['joined_date']),
                    onChanged: (v) => _set('joined_date', v),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppDateField(
                    label: 'Leaving date',
                    hint: 'When they leave',
                    value: dateOf(_values, ['leaving_date']),
                    onChanged: (v) => _set('leaving_date', v),
                  ),
                ),
              ],
            ),
            if (_isEdit) ...[
              const SizedBox(height: 6),
              SwitchListTile.adaptive(
                value: boolOf(_values, ['is_active']),
                onChanged: (v) => _set('is_active', v),
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Employee is active',
                  style: context.texts.bodyMedium,
                ),
              ),
            ],
            const SizedBox(height: 8),
            AppField(
              label: 'Notes',
              child: AppTextInput(
                initialValue: str(_values, ['notes']),
                maxLines: 3,
                minLines: 2,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (v) => _set('notes', v),
              ),
            ),
            const SizedBox(height: 18),
            if (_isEdit)
              AppButton(
                label: 'Deactivate employee',
                variant: AppButtonVariant.dangerGhost,
                block: true,
                icon: Icons.person_off_outlined,
                onPressed: _busy ? null : _deactivate,
              ),
            const SizedBox(height: 10),
            AppButton(
              label: _isEdit ? 'Save changes' : 'Create employee',
              variant: AppButtonVariant.primary,
              block: true,
              loading: _busy,
              onPressed: _submit,
            ),
            const SizedBox(height: 10),
            Text(
              'Writes are queued when the device is offline and replayed in '
              'order once the connection returns.',
              style:
                  context.texts.bodySmall?.copyWith(color: context.c.fgFaint),
            ),
          ],
        ),
      ),
    );
  }

  Widget _money(String key, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: AppField(
          label: label,
          error: _errors[key],
          child: AppMoneyInput(
            controller: _numbers[key]!,
            onChanged: (_) => _dirty = true,
          ),
        ),
      );

  Widget _number(String key, String label) => AppField(
        label: label,
        error: _errors[key],
        child: AppNumberInput(
          controller: _numbers[key]!,
          allowDecimal: true,
          onChanged: (_) => _dirty = true,
        ),
      );

  Map<String, dynamic> _payload() {
    final out = <String, dynamic>{
      for (final key in _numberKeys)
        key: numOf({key: _numbers[key]!.text}, [key]),
      'salary_components': <dynamic>[],
      'salary_type': str(_values, ['salary_type'], 'MONTHLY'),
      'allowance_type': str(_values, ['allowance_type'], 'FIXED'),
      'epf_base': str(_values, ['epf_base'], 'ADJUSTED'),
      'attendance_required': boolOf(_values, ['attendance_required']),
      'department': str(_values, ['department'], 'GENERAL'),
      'name': str(_values, ['name']).trim(),
    };
    // The web app drops blank optional fields rather than sending empty
    // strings, so a partially filled form never clears a stored value.
    for (final key in const [
      'position',
      'phone',
      'nic',
      'notes',
    ]) {
      final v = str(_values, [key]).trim();
      if (v.isNotEmpty) out[key] = v;
    }
    for (final key in const ['joined_date', 'leaving_date']) {
      final d = dateOf(_values, [key]);
      if (d != null) out[key] = Fmt.isoDate(d);
    }
    if (_isEdit) out['is_active'] = boolOf(_values, ['is_active']);
    return out;
  }

  Future<void> _submit() async {
    if (str(_values, ['name']).trim().isEmpty) {
      setState(() => _errors['name'] = 'Full name is required');
      AppToast.error(context, 'Full name is required');
      return;
    }

    final services = AppScope.read(context);
    setState(() => _busy = true);
    final ok = await runMgmtWrite(
      context,
      () {
        final body = _payload();
        return services.api.write(
            mgmt,
            _isEdit ? 'PUT' : 'POST',
            _isEdit
                ? '/api/employees/${widget.employee!['id']}'
                : '/api/employees',
            body: body);
      },
      success: _isEdit ? 'Employee updated' : 'Employee added',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.of(context).pop(true);
  }

  Future<void> _deactivate() async {
    final id = '${widget.employee?['id']}';
    if (id.isEmpty || id == 'null') return;
    final confirmed = await AppConfirmDialog.show(
      context,
      title: 'Deactivate employee?',
      message: 'Their history is kept, but they stop appearing in attendance '
          'and payroll.',
      confirmLabel: 'Deactivate',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final services = AppScope.read(context);
    final ok = await runMgmtWrite(
      context,
      () => services.api.delete(mgmt, '/api/employees/$id'),
      success: 'Employee deactivated',
    );
    if (ok && mounted) Navigator.of(context).pop(true);
  }
}
