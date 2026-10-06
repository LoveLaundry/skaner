import 'package:flutter/material.dart';

import '../../config/api_config.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/models/json.dart' as json;
import '../../core/models/worker.dart';
import '../../data/resource_controller.dart';
import '../../state/app_scope.dart';
import '../../ui/kit/feedback.dart';
import '../../ui/kit/inputs.dart';
import '../../ui/kit/primitives.dart';
import '../../ui/theme.dart';

/// Port of the add/edit sheet in `features/workers/pages/workers-page.tsx`.
///
/// The roster is the only record endpoint, so an edit prefills from the same
/// list the detail view resolved. Validation is hand-rolled rather than a
/// `Form`, because the kit's inputs surface errors through [AppField.error]
/// instead of `FormField` validators.
class WorkerFormPage extends StatefulWidget {
  const WorkerFormPage({super.key, this.workerId});

  /// Null creates, set edits.
  final String? workerId;

  @override
  State<WorkerFormPage> createState() => _WorkerFormPageState();
}

class _WorkerFormPageState extends State<WorkerFormPage> {
  late final ResourceController<Worker?> _existing;

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _joinedCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  String _department = 'GENERAL';
  bool _active = true;
  bool _saving = false;
  bool _prefilled = false;
  String? _nameError;
  String? _phoneError;

  bool get _isEdit => widget.workerId != null;

  @override
  void initState() {
    super.initState();
    _existing = ResourceController(
      key: 'worker-form-${widget.workerId ?? 'new'}',
      cache: AppScope.read(context).cache,
      fetcher: _fetchExisting,
    )..addListener(_onChanged);
    if (_isEdit) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _existing.load(force: true));
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _joinedCtrl.dispose();
    _notesCtrl.dispose();
    _existing.removeListener(_onChanged);
    _existing.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!mounted || _prefilled) return;
    final w = _existing.data;
    if (w == null) return;
    _prefilled = true;
    _nameCtrl.text = w.workerName;
    _phoneCtrl.text = w.phone ?? '';
    _joinedCtrl.text = w.joinedDate ?? '';
    _notesCtrl.text = w.notes ?? '';
    setState(() {
      _department = w.department;
      _active = w.isActive;
    });
  }

  /// The workers service exposes no single-worker route, so the edit form reads
  /// the roster and picks its own row out of it.
  Future<Worker?> _fetchExisting() async {
    final id = widget.workerId;
    if (id == null) return null;
    final payload =
        await AppScope.read(context).api.get(ServiceNames.workers, '/workers');
    for (final row in json.unwrapList(payload).items) {
      final w = Worker.fromJson(row);
      if (w.id == id) return w;
    }
    throw ApiException('That person is no longer on the roster.');
  }

  static final RegExp _phonePattern = RegExp(r'^[0-9+()\- ]{7,20}$');
  static final RegExp _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  bool _validate() {
    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final joined = _joinedCtrl.text.trim();
    setState(() {
      _nameError = name.isEmpty ? 'Name is required' : null;
      _phoneError = phone.isNotEmpty && !_phonePattern.hasMatch(phone)
          ? 'Enter a valid phone number'
          : null;
    });
    if (_phoneError != null) return false;
    if (joined.isNotEmpty && !_datePattern.hasMatch(joined)) {
      AppToast.error(context, 'Joined date must look like 2026-01-31');
      return false;
    }
    return _nameError == null;
  }

  Future<void> _save() async {
    if (!_validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    final services = AppScope.read(context);
    final phone = _phoneCtrl.text.trim();
    final joined = _joinedCtrl.text.trim();
    final notes = _notesCtrl.text.trim();
    final body = {
      'worker_name': _nameCtrl.text.trim(),
      'department': _department,
      'phone': phone.isEmpty ? null : phone,
      'is_active': _active,
      'joined_date': joined.isEmpty ? null : joined,
      'notes': notes.isEmpty ? null : notes,
    };
    try {
      final Object? result = _isEdit
          // The web app writes worker edits with PUT; the service only answers
          // to that verb.
          ? await services.api.put(
              ServiceNames.workers, '/workers/${widget.workerId}', body: body)
          : await services.api
              .post(ServiceNames.workers, '/workers', body: body);
      if (!mounted) return;
      if (result is QueuedResponse) {
        AppToast.info(context, 'Offline — change queued and will sync');
      } else {
        AppToast.success(context, _isEdit ? 'Staff updated' : 'Staff added');
      }
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.error(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final loading = _isEdit && _existing.isLoading && _existing.data == null;
    final failed = _isEdit &&
        _existing.phase == LoadPhase.failed &&
        _existing.data == null;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit staff' : 'Add staff'),
        actions: [
          AppButton(
            label: 'Save',
            variant: AppButtonVariant.primary,
            size: AppButtonSize.sm,
            loading: _saving,
            onPressed: loading || failed ? null : _save,
          ),
        ],
      ),
      body: loading
          ? const AppSkeletonList()
          : failed
              ? AppErrorState(message: _existing.error)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
                  children: [
                    AppCard(
                      title: 'Details',
                      child: Column(
                        children: [
                          AppField(
                            label: 'Full name',
                            required: true,
                            error: _nameError,
                            child: AppTextInput(
                              controller: _nameCtrl,
                              hint: 'e.g. Nimal Perera',
                              textCapitalization: TextCapitalization.words,
                              autofillHints: const [AutofillHints.name],
                              onChanged: (_) {
                                if (_nameError != null) {
                                  setState(() => _nameError = null);
                                }
                              },
                            ),
                          ),
                          const SizedBox(height: 12),
                          AppField(
                            label: 'Department',
                            required: true,
                            child: AppSearchableSelect<String>(
                              value: _department,
                              hint: 'Select department',
                              searchable: false,
                              onChanged: (v) =>
                                  setState(() => _department = v ?? 'GENERAL'),
                              options: [
                                for (final d in departments)
                                  AppSelectOption<String>(
                                    value: d,
                                    label: departmentLabels[d]!,
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          AppField(
                            label: 'Phone',
                            optional: true,
                            error: _phoneError,
                            child: AppTextInput(
                              controller: _phoneCtrl,
                              hint: '077 123 4567',
                              keyboardType: TextInputType.phone,
                              autofillHints: const [
                                AutofillHints.telephoneNumber
                              ],
                              onChanged: (_) {
                                if (_phoneError != null) {
                                  setState(() => _phoneError = null);
                                }
                              },
                            ),
                          ),
                          const SizedBox(height: 12),
                          AppField(
                            label: 'Joined date',
                            optional: true,
                            hint: 'YYYY-MM-DD',
                            child: AppTextInput(
                              controller: _joinedCtrl,
                              hint: '2026-01-31',
                              icon: Icons.calendar_today_outlined,
                              mono: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    AppCard(
                      title: 'Status',
                      child: SwitchListTile.adaptive(
                        value: _active,
                        onChanged: (v) => setState(() => _active = v),
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Active',
                          style:
                              context.texts.bodyMedium?.copyWith(color: c.fg),
                        ),
                        subtitle: Text(
                          _active
                              ? 'On the roster for new work'
                              : 'Hidden from the roster',
                          style: context.texts.bodySmall
                              ?.copyWith(color: c.fgMuted),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    AppCard(
                      title: 'Notes',
                      child: AppTextInput(
                        controller: _notesCtrl,
                        hint: 'Anything the supervisor should know…',
                        maxLines: 3,
                        minLines: 3,
                      ),
                    ),
                    const SizedBox(height: 14),
                    AppButton(
                      label: _isEdit ? 'Save changes' : 'Add staff',
                      icon: Icons.save_outlined,
                      variant: AppButtonVariant.primary,
                      expand: true,
                      loading: _saving,
                      onPressed: _save,
                    ),
                  ],
                ),
    );
  }
}
