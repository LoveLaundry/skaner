import 'package:flutter/material.dart';

import '../../core/utils/formatting.dart';
import '../../data/resource_controller.dart';
import '../../state/app_scope.dart';
import '../../ui/kit/feedback.dart';
import '../../ui/kit/inputs.dart';
import '../../ui/kit/primitives.dart';
import '../../ui/kit/shell_parts.dart';
import '../../ui/theme.dart';
import '_management_shared.dart';

/// There is no announcements endpoint in the management API. The company's
/// notice board is the holiday calendar — every entry is a date the whole
/// staff are meant to know about — so this screen reads and edits that, and
/// lists it newest first.
class AnnouncementsPage extends StatefulWidget {
  const AnnouncementsPage({super.key});

  @override
  State<AnnouncementsPage> createState() => _AnnouncementsPageState();
}

class _AnnouncementsPageState extends State<AnnouncementsPage> {
  late final ResourceController<List<Map<String, dynamic>>> _holidays;
  late int _year;
  bool _upcomingOnly = true;

  @override
  void initState() {
    super.initState();
    _year = Fmt.lktNow().year;
    _holidays = ResourceController<List<Map<String, dynamic>>>(
      key: 'management.announcements',
      cache: AppScope.read(context).cache,
      fetcher: () async {
        final s = AppScope.read(context);
        return asRows(
            await s.api.get(mgmt, '/api/holidays', query: {'year': _year}));
      },
    )..addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _holidays.load(force: true),
    );
  }

  @override
  void dispose() {
    _holidays.removeListener(_onChanged);
    _holidays.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  List<Map<String, dynamic>> get _rows {
    var rows = _holidays.data ?? const <Map<String, dynamic>>[];
    if (_upcomingOnly) {
      final today = Fmt.lktNow();
      rows = rows
          .where((r) => (dateOf(r, ['date']) ?? DateTime(2000)).isAfter(today))
          .toList();
    }
    return [...rows]..sort((a, b) => (dateOf(a, ['date']) ?? DateTime(0))
        .compareTo(dateOf(b, ['date']) ?? DateTime(0)));
  }

  int _daysAway(Map<String, dynamic> row) {
    final d = dateOf(row, ['date']);
    if (d == null) return 0;
    final today = Fmt.lktNow();
    return d.difference(DateTime(today.year, today.month, today.day)).inDays;
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Announcements')),
      body: Column(
        children: [
          AppSyncStatusBar(
            status: _holidays.status,
            updatedAt: _holidays.lastUpdated,
            label: 'Announcements',
          ),
          AppOfflineSyncBar(engine: services.sync),
          Expanded(
            child: RefreshIndicator(
              color: context.c.brand,
              onRefresh: () => _holidays.load(force: true),
              child: _body(),
            ),
          ),
        ],
      ),
      floatingActionButton: AppButton(
        label: 'Post',
        icon: Icons.campaign_outlined,
        variant: AppButtonVariant.primary,
        onPressed: () => _edit(),
      ),
    );
  }

  Widget _body() {
    if (_holidays.phase == LoadPhase.failed && _holidays.data == null) {
      return AppErrorState(
        message: _holidays.error,
        onRetry: () => _holidays.load(force: true),
      );
    }
    if (_holidays.isLoading && _holidays.data == null) {
      return const AppSkeletonList();
    }
    final rows = _rows;

    return ListView(
      padding: const EdgeInsets.only(bottom: 92),
      children: [
        Container(
          color: context.c.surface,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: AppNumberInput(
                  controller: TextEditingController(text: '$_year'),
                  label: 'Year',
                  allowDecimal: false,
                  onChanged: (v) {
                    final y = int.tryParse(v);
                    if (y == null || y < 2000) return;
                    setState(() => _year = y);
                    _holidays.load(force: true);
                  },
                ),
              ),
              const SizedBox(width: 10),
              AppButton(
                label: _upcomingOnly ? 'Showing upcoming' : 'Showing all',
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.sm,
                icon: _upcomingOnly
                    ? Icons.filter_alt_outlined
                    : Icons.filter_alt_off_outlined,
                onPressed: () => setState(() => _upcomingOnly = !_upcomingOnly),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (rows.isEmpty)
          const AppEmptyState(
            title: 'Nothing posted',
            message: 'Add a date the whole floor should know about.',
            icon: Icons.campaign_outlined,
          )
        else
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: AppCard(
                onTap: () => _edit(r),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 52,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: context.c.brandSoft,
                        borderRadius: BorderRadius.circular(Radii.md),
                        border: Border.all(color: context.c.brandBorder),
                      ),
                      child: Column(
                        children: [
                          Text(
                            Fmt.date(dateOf(r, ['date'])).split(' ').first,
                            style: context.texts.titleSmall
                                ?.copyWith(color: context.c.brandText),
                          ),
                          Text(
                            Fmt.date(dateOf(r, ['date'])).split(' ').last,
                            style: context.texts.labelSmall
                                ?.copyWith(color: context.c.brandText),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            str(r, ['name'], '—'),
                            style: context.texts.titleSmall,
                          ),
                          if (str(r, ['description']).isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              str(r, ['description']),
                              style: context.texts.bodySmall
                                  ?.copyWith(color: context.c.fgMuted),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              if (boolOf(r, ['is_recurring']))
                                const AppBadge(
                                  'Recurring',
                                  tone: AppTone.info,
                                  compact: true,
                                ),
                              if (_daysAway(r) >= 0)
                                AppBadge(
                                  'in ${_daysAway(r)} day(s)',
                                  tone: _daysAway(r) <= 7
                                      ? AppTone.warning
                                      : AppTone.neutral,
                                  compact: true,
                                )
                              else
                                const AppBadge(
                                  'Past',
                                  tone: AppTone.neutral,
                                  compact: true,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    AppButton.icon(
                      icon: Icons.delete_outline,
                      tooltip: 'Delete',
                      size: AppButtonSize.iconSm,
                      variant: AppButtonVariant.ghost,
                      onPressed: () => _delete(r),
                    ),
                  ],
                ),
              ),
            ),
        const SizedBox(height: 12),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: AppNotice(
            message: 'The management API has no announcements endpoint. This '
                'board carries the company holiday calendar, the one set of '
                'notices the web app actually broadcasts to staff.',
            tone: AppTone.neutral,
          ),
        ),
      ],
    );
  }

  Future<void> _edit([Map<String, dynamic>? row]) async {
    final isEdit = row != null;
    final name = TextEditingController(text: str(row ?? {}, ['name']));
    final description =
        TextEditingController(text: str(row ?? {}, ['description']));
    var date = dateOf(row ?? {}, ['date']) ?? Fmt.lktNow();
    var recurring = boolOf(row ?? {}, ['is_recurring']);
    var error = false;
    StateSetter? inner;

    final saved = await AppDialog.show<bool>(
      context,
      title: isEdit ? 'Edit notice' : 'Post a notice',
      body: StatefulBuilder(
        builder: (context, setInner) {
          inner = setInner;
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppTextInput(
                  controller: name,
                  label: 'Title',
                  textCapitalization: TextCapitalization.words,
                  errorText: error && name.text.trim().isEmpty
                      ? 'Title is required'
                      : null,
                ),
                const SizedBox(height: 10),
                AppDateField(
                  label: 'Date',
                  value: date,
                  onChanged: (v) => setInner(() => date = v ?? date),
                ),
                const SizedBox(height: 6),
                SwitchListTile.adaptive(
                  value: recurring,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (v) => setInner(() => recurring = v),
                  title: Text('Repeats every year',
                      style: context.texts.bodyMedium),
                ),
                const SizedBox(height: 6),
                AppTextInput(
                  controller: description,
                  label: 'Details',
                  maxLines: 3,
                  minLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                ),
              ],
            ),
          );
        },
      ),
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppButton(
          label: isEdit ? 'Save' : 'Post',
          variant: AppButtonVariant.primary,
          onPressed: () {
            if (name.text.trim().isEmpty) {
              inner?.call(() => error = true);
              return;
            }
            Navigator.of(context).pop(true);
          },
        ),
      ],
    );

    for (final c in [name, description]) {
      c.dispose();
    }
    if (saved != true || !mounted) return;

    final services = AppScope.read(context);
    final body = {
      'name': name.text.trim(),
      'date': Fmt.isoDate(date),
      'description': description.text.trim(),
      'is_recurring': recurring,
    };
    final ok = await runMgmtWrite(
      context,
      () => (isEdit
          ? services.api.put(mgmt, '/api/holidays/${row['id']}', body: body)
          : services.api.post(mgmt, '/api/holidays', body: body)),
      success: isEdit ? 'Notice updated' : 'Notice posted',
    );
    if (ok) _holidays.load(force: true);
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final confirm = await AppConfirmDialog.show(
      context,
      title: 'Delete this notice?',
      message: str(row, ['name'], 'This entry'),
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirm || !mounted) return;
    final services = AppScope.read(context);
    final ok = await runMgmtWrite(
      context,
      () => services.api.delete(mgmt, '/api/holidays/${row['id']}'),
      success: 'Notice deleted',
    );
    if (ok) _holidays.load(force: true);
  }
}
