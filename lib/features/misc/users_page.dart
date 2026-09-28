import 'package:flutter/material.dart';

import '../../../config/api_config.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/utils/formatting.dart';
import '../../../data/resource_controller.dart';
import '../../../state/app_scope.dart';
import '../../../ui/kit/data.dart';
import '../../../ui/kit/feedback.dart';
import '../../../ui/kit/inputs.dart';
import '../../../ui/kit/primitives.dart';
import '../../../ui/theme.dart';

/// Port of `features/quotations/pages/users-page.tsx`.
///
/// Admin-only (`/users` requires the ADMIN role on the user service), so the
/// screen hides its write affordances from anyone without the permission rather
/// than letting them submit into a 403.
///
/// A user's role and profile live on `PUT /users/{id}`, while the password is a
/// separate `PATCH /users/{id}/password` — the form saves them in that order and
/// only when the admin actually typed a new password.
class UsersPage extends StatefulWidget {
  const UsersPage({super.key});

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  static const _roles = ['ADMIN', 'MANAGER', 'STAFF'];
  static const _statuses = ['active', 'inactive', 'unset'];

  late final ResourceController<List<Map<String, dynamic>>> _users;

  @override
  void initState() {
    super.initState();
    _users = ResourceController<List<Map<String, dynamic>>>(
      key: 'users',
      cache: AppScope.read(context).cache,
      fetcher: () async {
        final data =
            await AppScope.read(context).api.get(ServiceNames.users, '/users');
        return asRows(data);
      },
    )..addListener(_onChanged);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _users.load(force: true));
  }

  @override
  void dispose() {
    _users.removeListener(_onChanged);
    _users.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  /// Headline count tile. Colour carries the meaning (green = active, amber =
  /// admin), matching the status colours used on the cards below.
  Widget _count(String label, String value, Color valueColor) {
    final c = context.c;
    final t = context.texts;
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: t.headlineSmall?.copyWith(color: valueColor),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: t.bodySmall?.copyWith(color: c.fgMuted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.texts;
    final rows = _users.data ?? const <Map<String, dynamic>>[];
    final writable = AppScope.read(context).auth.hasPermission('users.write');
    final active = rows.where((u) => str(u, ['status']).toLowerCase() == 'active').length;
    final admins = rows
        .where((u) => str(u, ['role_id']).toUpperCase() == 'ADMIN')
        .length;

    return Column(
      children: [
        AppPageHeader(
          breadcrumb: const AppBreadcrumb(trail: ['Dashboard', 'Users']),
          title: 'User Management',
          subtitle: 'Create and manage system users',
          busy: _users.isLoading && rows.isNotEmpty,
          actions: [
            AppButton.icon(
              icon: Icons.refresh,
              tooltip: 'Refresh',
              onPressed: () => _users.load(force: true),
            ),
            if (writable)
              AppButton(
                label: 'Create User',
                icon: Icons.person_add_alt,
                variant: AppButtonVariant.primary,
                onPressed: _openCreate,
              ),
          ],
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: _count(
                        'Total Users',
                        _users.isLoading && rows.isEmpty ? '—' : '${rows.length}',
                        c.fg),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _count(
                        'Active',
                        _users.isLoading && rows.isEmpty ? '—' : '$active',
                        c.success),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _count(
                        'Admins',
                        _users.isLoading && rows.isEmpty ? '—' : '$admins',
                        c.warning),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (_users.isLoading && rows.isEmpty)
                const AppSkeletonList(count: 3, lines: 2)
              else if (rows.isEmpty && _users.phase == LoadPhase.failed)
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.5,
                  child: AppErrorState(
                    message: _users.error ?? 'Could not load users.',
                    onRetry: () => _users.load(force: true),
                  ),
                )
              else if (rows.isEmpty)
                AppEmptyState(
                  title: 'No users found',
                  message: 'Create the first user to get started',
                  icon: Icons.person_outline,
                  action: writable
                      ? AppButton(
                          label: 'Create First User',
                          icon: Icons.person_add_alt,
                          variant: AppButtonVariant.primary,
                          onPressed: _openCreate,
                        )
                      : null,
                )
              else
                LayoutBuilder(
                  builder: (context, box) {
                    final columns = box.maxWidth > 900
                        ? 3
                        : box.maxWidth > 580
                            ? 2
                            : 1;
                    final width =
                        (box.maxWidth - (columns - 1) * 10) / columns;
                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final u in rows)
                          SizedBox(width: width, child: _userCard(u, t, c, writable)),
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _userCard(Map<String, dynamic> u, TextTheme t, AppColors c,
      bool writable) {
    final name = str(u, ['user_name'], 'Unnamed user');
    final role = str(u, ['role_id'], 'STAFF').toUpperCase();
    final status = str(u, ['status'], 'unset').toLowerCase();
    return AppCard(
      onTap: () => _showDetail(u),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [c.fg, c.fg2],
              ),
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: Text(
              name.isEmpty ? '?' : name[0].toUpperCase(),
              style: t.titleSmall?.copyWith(color: Colors.white),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: t.titleSmall, overflow: TextOverflow.ellipsis),
                Text(
                  str(u, ['email']).isNotEmpty
                      ? str(u, ['email'])
                      : str(u, ['auth_id'], '—'),
                  style: t.bodySmall?.copyWith(color: c.fgMuted),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: [
                    AppBadge(role, tone: _roleTone(role), compact: true),
                    AppBadge(status, tone: _statusTone(status), compact: true),
                    if (str(u, ['employee_id']).isNotEmpty)
                      AppBadge('#${str(u, ['employee_id'])}',
                          tone: AppTone.neutral, compact: true),
                  ],
                ),
              ],
            ),
          ),
          if (writable)
            AppButton.icon(
              icon: Icons.edit_outlined,
              tooltip: 'Edit user',
              onPressed: () => _openEdit(u),
            ),
        ],
      ),
    );
  }

  static AppTone _roleTone(String role) => switch (role) {
        'ADMIN' => AppTone.warning,
        'MANAGER' => AppTone.brand,
        _ => AppTone.success,
      };

  static AppTone _statusTone(String status) => switch (status) {
        'active' => AppTone.success,
        'inactive' => AppTone.danger,
        _ => AppTone.neutral,
      };

  void _showDetail(Map<String, dynamic> u) {
    final c = context.c;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(str(u, ['user_name'], 'Unnamed user'),
                  style: sheet.texts.titleMedium),
              const SizedBox(height: 2),
              Text(
                '@${str(u, ['auth_id'], '—')} · ${str(u, ['role_id']).toUpperCase()}',
                style: sheet.texts.bodySmall?.copyWith(color: c.fgMuted),
              ),
              const SizedBox(height: 16),
              _row(sheet, 'Email', str(u, ['email'], '—')),
              _row(sheet, 'Mobile', str(u, ['mobile_number'], '—')),
              _row(sheet, 'Employee ID', str(u, ['employee_id'], '—')),
              _row(sheet, 'Status', str(u, ['status'], '—')),
              _row(sheet, 'Created',
                  pick(u, ['created_at']) == null ? '—' : Fmt.dateTime(u['created_at'])),
              if (str(u, ['bio_data']).isNotEmpty)
                _row(sheet, 'Bio', str(u, ['bio_data'])),
              const SizedBox(height: 16),
              AppButton(
                label: 'Close',
                variant: AppButtonVariant.secondary,
                block: true,
                onPressed: () => Navigator.of(sheet).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext sheet, String label, String value) {
    final c = sheet.c;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: sheet.texts.labelSmall
                  ?.copyWith(color: c.fgFaint, fontSize: 10, letterSpacing: 0.6)),
          const SizedBox(height: 1),
          Text(value, style: sheet.texts.bodyMedium),
        ],
      ),
    );
  }

  void _openCreate() => _openForm(null);

  void _openEdit(Map<String, dynamic> u) => _openForm(u);

  Future<void> _openForm(Map<String, dynamic>? user) async {
    final editing = user != null;
    final name = TextEditingController(text: str(user ?? {}, ['user_name']));
    final authId = TextEditingController(text: str(user ?? {}, ['auth_id']));
    final password = TextEditingController();
    final email = TextEditingController(text: str(user ?? {}, ['email']));
    final mobile = TextEditingController(text: str(user ?? {}, ['mobile_number']));
    final employee = TextEditingController(text: str(user ?? {}, ['employee_id']));
    var role = str(user ?? {}, ['role_id'], 'STAFF').toUpperCase();
    var status = str(user ?? {}, ['status'], 'active').toLowerCase();
    var reveal = false;
    String? error;

    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, setSheet) => AppDialog(
          title: editing ? 'Edit User' : 'Create User',
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  editing
                      ? 'Update this system user'
                      : 'Add a new system user. They can sign in immediately with '
                          'the username and password you set.',
                  style: dialog.texts.bodySmall?.copyWith(color: dialog.c.fgMuted),
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  AppNotice(tone: AppTone.danger, message: error!),
                ],
                const SizedBox(height: 14),
                AppField(
                  label: 'Full name *',
                  child: AppTextInput(
                    controller: name,
                    hint: 'John Silva',
                    textCapitalization: TextCapitalization.words,
                  ),
                ),
                const SizedBox(height: 10),
                AppField(
                  label: 'Username *',
                  child: AppTextInput(
                    controller: authId,
                    hint: 'john.silva',
                    textCapitalization: TextCapitalization.none,
                  ),
                ),
                const SizedBox(height: 10),
                AppField(
                  label: editing ? 'New password' : 'Password *',
                  child: AppTextInput(
                    controller: password,
                    hint: editing
                        ? 'Leave blank to keep current'
                        : 'Secure password',
                    obscureText: !reveal,
                    suffix: AppButton.icon(
                      icon: reveal
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      tooltip: reveal ? 'Hide' : 'Show',
                      onPressed: () => setSheet(() => reveal = !reveal),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: AppField(
                        label: 'Role',
                        child: _rolePicker(
                          role,
                          (v) => setSheet(() => role = v),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AppField(
                        label: 'Status',
                        child: _statusPicker(
                          status,
                          (v) => setSheet(() => status = v),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                AppField(
                  label: 'Email',
                  child: AppTextInput(
                    controller: email,
                    hint: 'john@lovelaundry.lk',
                    keyboardType: TextInputType.emailAddress,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: AppField(
                        label: 'Mobile',
                        child: AppTextInput(
                          controller: mobile,
                          hint: '+94 77 123 4567',
                          keyboardType: TextInputType.phone,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AppField(
                        label: 'Employee ID',
                        child: AppTextInput(
                          controller: employee,
                          hint: 'EMP-001',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            AppButton(
              label: 'Cancel',
              onPressed: () => Navigator.of(dialog).pop(false),
            ),
            AppButton(
              label: editing ? 'Save changes' : 'Create user',
              variant: AppButtonVariant.primary,
              onPressed: () {
                if (name.text.trim().isEmpty || authId.text.trim().isEmpty) {
                  setSheet(() => error = 'Full name and username are required');
                  return;
                }
                if (!editing && password.text.isEmpty) {
                  setSheet(() => error = 'Password is required for new users');
                  return;
                }
                Navigator.of(dialog).pop(true);
              },
            ),
          ],
        ),
      ),
    );

    if (submitted != true || !mounted) {
      name.dispose();
      authId.dispose();
      password.dispose();
      email.dispose();
      mobile.dispose();
      employee.dispose();
      return;
    }

    final payload = <String, dynamic>{
      'user_name': name.text.trim(),
      'auth_id': authId.text.trim(),
      'role_id': role,
      'status': status,
      if (email.text.trim().isNotEmpty) 'email': email.text.trim(),
      if (mobile.text.trim().isNotEmpty) 'mobile_number': mobile.text.trim(),
      if (employee.text.trim().isNotEmpty)
        'employee_id': employee.text.trim(),
    };
    final id = str(user ?? {}, ['id']);
    final newPassword = password.text;
    final userName = name.text.trim();
    // Resolved before the first await so no BuildContext is used across a gap.
    final api = AppScope.read(context).api;

    try {
      // The user service is never queued, so this is always a real round trip.
      // Kept honest anyway: if a write ever does return the queued marker, the
      // operator must not be told the account reached the server.
      final Object? result;
      if (editing) {
        result = await api.put(ServiceNames.users, '/users/$id', body: payload);
        if (newPassword.isNotEmpty) {
          await api.patch(
            ServiceNames.users,
            '/users/$id/password',
            body: {'password': newPassword},
          );
        }
      } else {
        result = await api.post(
          ServiceNames.users,
          '/users',
          body: {...payload, 'password': newPassword},
        );
      }
      if (!mounted) return;
      if (result is QueuedResponse) {
        AppToast.warning(
            context, 'Saved locally — it will reach the server when online');
      } else {
        AppToast.success(
            context, editing ? 'User "$userName" updated' : 'User "$userName" created');
      }
    } on ApiException catch (e) {
      if (mounted) AppToast.error(context, e.message);
    } catch (_) {
      if (mounted) AppToast.error(context, 'Could not save the user');
    } finally {
      name.dispose();
      authId.dispose();
      password.dispose();
      email.dispose();
      mobile.dispose();
      employee.dispose();
      _users.load(force: true);
    }
  }

  Widget _rolePicker(String value, ValueChanged<String> onChanged) =>
      _pillPicker(_roles, value, onChanged);

  Widget _statusPicker(String value, ValueChanged<String> onChanged) =>
      _pillPicker(_statuses, value, onChanged);

  Widget _pillPicker(List<String> options, String value,
      ValueChanged<String> onChanged) {
    final c = context.c;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final o in options)
          InkWell(
            onTap: () => onChanged(o),
            borderRadius: BorderRadius.circular(Radii.pill),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: o == value ? c.brandSoft : c.surface,
                borderRadius: BorderRadius.circular(Radii.pill),
                border: Border.all(color: o == value ? c.brandBorder : c.line),
              ),
              child: Text(
                o,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: o == value ? FontWeight.w600 : FontWeight.w500,
                  color: o == value ? c.brandText : c.fg3,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
