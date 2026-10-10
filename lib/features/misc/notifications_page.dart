import 'package:flutter/material.dart';

import '../../../config/api_config.dart';
import '../../../core/api/outbox_store.dart';
import '../../../core/utils/formatting.dart';
import '../../../data/resource_controller.dart';
import '../../../state/app_scope.dart';
import '../../../ui/kit/data.dart';
import '../../../ui/kit/feedback.dart';
import '../../../ui/kit/inputs.dart';
import '../../../ui/kit/primitives.dart';
import '../../../ui/shell/app_shell.dart';
import '../../../ui/theme.dart';

/// Port of `features/quotations/pages/notifications-page.tsx`.
///
/// The two real sources are the server's canonical balances
/// (`/notifications/gatepass-pending`) and delivered quotations awaiting a bill.
/// Nothing here recomputes `received - delivered + returned` in the browser —
/// the service owns those numbers, and the screen only presents them.
///
/// The third tab is the device's own outbox: work that has not reached the
/// server yet, which belongs next to "pending" in the user's mental model.
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  late final ResourceController<Map<String, dynamic>> _feed;
  List<OutboxRow> _outbox = [];
  int _tab = 0;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _feed = ResourceController<Map<String, dynamic>>(
      key: 'notifications',
      cache: AppScope.read(context).cache,
      fetcher: _load,
    )..addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _feed.load(force: true);
      _loadOutbox();
    });
  }

  @override
  void dispose() {
    _feed.removeListener(_onChanged);
    _feed.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadOutbox() async {
    try {
      final rows = await AppScope.read(context).outbox.all();
      if (!mounted) return;
      setState(() => _outbox = rows);
    } catch (_) {
      // The activity tab is supplementary; if SQLite is unavailable, say nothing.
    }
  }

  Future<Map<String, dynamic>> _load() async {
    final services = AppScope.read(context);
    // Two independent sources; one failing must not blank the other, so each is
    // allowed to degrade to an empty list.
    final results = await Future.wait([
      services.api
          .get(ServiceNames.bills, '/notifications/gatepass-pending')
          .then(asRows)
          .catchError((_) => <Map<String, dynamic>>[]),
      services.api
          .get(ServiceNames.bills, '/notifications/summary')
          .then((dynamic d) =>
              d is Map<String, dynamic> ? d : <String, dynamic>{})
          .catchError((_) => <String, dynamic>{}),
      services.api
          .get(ServiceNames.quotation, '/quotations')
          .then(asRows)
          .catchError((_) => <Map<String, dynamic>>[]),
    ]);
    return {
      'pending': results[0] as List<Map<String, dynamic>>,
      'summary': results[1] as Map<String, dynamic>,
      'quotations': results[2] as List<Map<String, dynamic>>,
    };
  }

  List<Map<String, dynamic>> get _pendingRows =>
      asRows(_feed.data?['pending']);

  List<Map<String, dynamic>> get _deliveredRows => asRows(_feed.data?['quotations'])
      .where((q) => str(q, ['status']).toLowerCase() == 'delivered')
      .toList();

  int get _pendingCount =>
      _pendingRows.fold<int>(0, (sum, e) => sum + intOf(e, ['pending']));

  int get _totalCount => _pendingCount + _deliveredRows.length;

  List<_Row> _rows() {
    final query = _search.trim().toLowerCase();
    bool matches(Iterable<String> haystack) =>
        query.isEmpty || haystack.any((h) => h.toLowerCase().contains(query));

    final rows = <_Row>[];
    if (_tab == 0 || _tab == 1) {
      for (final e in _pendingRows) {
        if (matches([
          str(e, ['client_name']),
          str(e, ['item_name']),
          str(e, ['gate_pass_number']),
        ])) {
          rows.add(_Row.gatePass(e));
        }
      }
    }
    if (_tab == 0 || _tab == 2) {
      for (final q in _deliveredRows) {
        if (matches([str(q, ['client_name']), str(q, ['quotation_title'])])) {
          rows.add(_Row.quotation(q));
        }
      }
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.texts;
    final rows = _rows();
    final loading = _feed.isLoading && _feed.data == null;

    return Column(
      children: [
        AppPageHeader(
          title: 'Notifications',
          subtitle: _totalCount > 0
              ? '$_totalCount item${_totalCount == 1 ? '' : 's'} need your attention'
              : 'Everything is up to date',
          busy: _feed.isLoading && _feed.hasData,
          actions: [
            AppButton(
              label: 'Gate Passes',
              icon: Icons.local_shipping_outlined,
              onPressed: () => AppNavigatorPush.push(context, '/gate-passes'),
            ),
            AppButton(
              label: 'Quotations',
              icon: Icons.description_outlined,
              onPressed: () => AppNavigatorPush.push(context, '/quotations'),
            ),
          ],
          tabs: AppTabs(
            index: _tab,
            onChanged: (i) => setState(() => _tab = i),
            tabs: [
              AppTabItem('All', icon: Icons.inbox_outlined, count: _totalCount),
              AppTabItem('Pending to Send',
                  icon: Icons.local_shipping_outlined, count: _pendingCount),
              AppTabItem('Ready for Billing',
                  icon: Icons.receipt_long_outlined, count: _deliveredRows.length),
              AppTabItem('Recent activity',
                  icon: Icons.cloud_sync_outlined,
                  count: _outbox.where((r) => r.isPending).length),
            ],
          ),
        ),
        if (_tab == 3)
          Expanded(child: _activity())
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: AppTextInput(
              initialValue: _search,
              hint: 'Search client, item or gate pass…',
              icon: Icons.search_rounded,
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          Expanded(
            child: loading
                ? const AppSkeletonList(count: 5, lines: 2)
                : rows.isEmpty
                    ? ListView(
                        children: [
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.55,
                            child: _feed.phase == LoadPhase.failed
                                ? AppErrorState(
                                    title: 'Notifications unavailable',
                                    message: _feed.error ??
                                        'Could not load notifications.',
                                    onRetry: () => _feed.load(force: true),
                                  )
                                : AppEmptyState(
                                    title: _search.isEmpty
                                        ? 'No notifications'
                                        : 'No results found',
                                    message: _search.isEmpty
                                        ? "You're all caught up. No gate pass items pending "
                                            'to be sent or quotations waiting to be billed.'
                                        : 'Nothing matches "$_search".',
                                  ),
                          ),
                        ],
                      )
                    : RefreshIndicator(
                        color: c.brand,
                        onRefresh: () async {
                          await _feed.load(force: true);
                          await _loadOutbox();
                        },
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                          itemCount: rows.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) =>
                              rows[i].kind == _RowKind.gatePass
                                  ? _gatePassCard(rows[i].data, t, c)
                                  : _quotationCard(rows[i].data, t, c),
                        ),
                      ),
          ),
        ],
      ],
    );
  }

  Widget _gatePassCard(Map<String, dynamic> e, TextTheme t, AppColors c) {
    final pending = intOf(e, ['pending']);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      onTap: () => _showGatePass(e),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _iconBox(Icons.local_shipping_outlined, c.danger, c.dangerSoft, c.dangerBorder),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: Text(
                        str(e, ['item_name'], 'Item'),
                        style: t.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const AppBadge('Pending to Send',
                        tone: AppTone.danger, compact: true),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${str(e, ['client_name'], '—')} · Gate Pass #${str(e, ['gate_pass_number'], '—')}',
                  style: t.bodySmall?.copyWith(color: c.fgMuted),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 12,
                  runSpacing: 2,
                  children: [
                    _stat('Received', '${intOf(e, ['received'])}', t, c),
                    _stat('Delivered', '${intOf(e, ['delivered'])}', t, c),
                    _stat('Pending', '$pending', t, c, color: c.danger),
                    if (intOf(e, ['returned']) > 0)
                      _stat('Returned', '${intOf(e, ['returned'])}', t, c),
                  ],
                ),
              ],
            ),
          ),
          AppButton(
            label: 'Open',
            size: AppButtonSize.sm,
            onPressed: () => _goGatePass(e),
          ),
        ],
      ),
    );
  }

  Widget _quotationCard(Map<String, dynamic> q, TextTheme t, AppColors c) {
    final items = asRows(q['line_items']);
    final total = items.fold<double>(0, (s, i) => s + numOf(i, ['unit_price']));
    final id = str(q, ['id'], '—');
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      onTap: () => _showQuotation(q),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _iconBox(Icons.description_outlined, c.warning, c.warningSoft, c.warningBorder),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 200),
                      child: Text(
                        str(q, ['client_name'], '—'),
                        style: t.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const AppBadge('Ready for Billing',
                        tone: AppTone.warning, compact: true),
                    if (str(q, ['tag']).isNotEmpty)
                      AppBadge(str(q, ['tag']).toUpperCase(),
                          tone: AppTone.neutral, compact: true),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${str(q, ['quotation_title'], 'General Price List')} · #${id.length > 8 ? id.substring(0, 8) : id}',
                  style: t.bodySmall?.copyWith(color: c.fgMuted),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 12,
                  runSpacing: 2,
                  children: [
                    _stat('Items', '${items.length}', t, c),
                    _stat('Total rate value', Fmt.money(total), t, c),
                  ],
                ),
              ],
            ),
          ),
          AppButton(
            label: 'Bill',
            icon: Icons.add_rounded,
            size: AppButtonSize.sm,
            variant: AppButtonVariant.primary,
            onPressed: () =>
                AppNavigatorPush.push(context, '/bills/new?quotation_id=$id'),
          ),
        ],
      ),
    );
  }

  Widget _iconBox(IconData icon, Color fg, Color bg, Color border) => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: border),
        ),
        child: Icon(icon, size: 19, color: fg),
      );

  Widget _stat(String label, String value, TextTheme t, AppColors c,
          {Color? color}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: t.labelSmall?.copyWith(color: c.fgFaint, fontSize: context.fs(10.5))),
          Text(
            value,
            style: t.labelLarge
                ?.copyWith(color: color ?? c.fg2, fontWeight: FontWeight.w600),
          ),
        ],
      );

  void _goGatePass(Map<String, dynamic> e) {
    final id = str(e, ['gate_pass_id']);
    if (id.isEmpty) {
      AppToast.error(context, 'This entry has no gate pass reference');
      return;
    }
    AppNavigatorPush.push(context, '/gate-passes/$id');
  }

  void _showGatePass(Map<String, dynamic> e) {
    final c = context.c;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _iconBox(Icons.local_shipping_outlined, c.danger, c.dangerSoft, c.dangerBorder),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Pending to send', style: sheet.texts.titleMedium),
                        Text(
                          'This item is still pending to be sent from its gate pass.',
                          style: sheet.texts.bodySmall?.copyWith(color: c.fgMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _dl(sheet, 'Client', str(e, ['client_name'], '—')),
              _dl(sheet, 'Gate pass', '#${str(e, ['gate_pass_number'], '—')}', mono: true),
              _dl(sheet, 'Item', str(e, ['item_name'], '—')),
              if (str(e, ['specification']).isNotEmpty)
                _dl(sheet, 'Specification', str(e, ['specification'])),
              if (pick(e, ['receiving_date']) != null)
                _dl(sheet, 'Received on', Fmt.date(e['receiving_date'])),
              _dl(sheet, 'Received', '${intOf(e, ['received'])}'),
              _dl(sheet, 'Delivered so far', '${intOf(e, ['delivered'])}'),
              _dl(sheet, 'Pending', '${intOf(e, ['pending'])}', color: c.danger),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      label: 'Close',
                      variant: AppButtonVariant.secondary,
                      block: true,
                      onPressed: () => Navigator.of(sheet).pop(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AppButton(
                      label: 'Open gate pass',
                      icon: Icons.local_shipping_outlined,
                      variant: AppButtonVariant.primary,
                      block: true,
                      onPressed: () {
                        Navigator.of(sheet).pop();
                        _goGatePass(e);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showQuotation(Map<String, dynamic> q) {
    final c = context.c;
    final items = asRows(q['line_items']);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.of(sheet).size.height * 0.85),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                child: Row(
                  children: [
                    _iconBox(Icons.description_outlined, c.success, c.successSoft, c.successBorder),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Ready for billing', style: sheet.texts.titleMedium),
                          Text(
                            'This order has been delivered and can be billed.',
                            style: sheet.texts.bodySmall?.copyWith(color: c.fgMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
                  children: [
                    _dl(sheet, 'Client', str(q, ['client_name'], '—')),
                    _dl(sheet, 'Title', str(q, ['quotation_title'], 'General Price List')),
                    _dl(sheet, 'Date',
                        pick(q, ['created_at']) == null ? '—' : Fmt.date(q['created_at'])),
                    _dl(sheet, 'Quotation #', str(q, ['id'], '—'), mono: true),
                    const SizedBox(height: 12),
                    Text('Items (${items.length})', style: sheet.texts.labelLarge),
                    const SizedBox(height: 6),
                    if (items.isEmpty)
                      Text('No line items on this quotation.',
                          style: sheet.texts.bodySmall?.copyWith(color: c.fgMuted))
                    else
                      for (final item in items.take(10))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  str(item, ['item_name'], 'Item'),
                                  style: sheet.texts.bodySmall?.copyWith(color: c.fg),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              SizedBox(
                                width: 90,
                                child: Text(
                                  str(item, ['category'], 'General'),
                                  style: sheet.texts.labelSmall
                                      ?.copyWith(color: c.fgFaint),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                Fmt.money(numOf(item, ['unit_price'])),
                                style: sheet.texts.bodySmall
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                    if (items.length > 10)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '+${items.length - 10} more items',
                          style: sheet.texts.labelSmall?.copyWith(color: c.fgFaint),
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        label: 'View details',
                        variant: AppButtonVariant.secondary,
                        block: true,
                        onPressed: () {
                          Navigator.of(sheet).pop();
                          final id = str(q, ['id']);
                          if (id.isNotEmpty) {
                            AppNavigatorPush.push(context, '/quotations/$id');
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AppButton(
                        label: 'Create bill',
                        icon: Icons.add_rounded,
                        variant: AppButtonVariant.primary,
                        block: true,
                        onPressed: () {
                          Navigator.of(sheet).pop();
                          final id = str(q, ['id']);
                          if (id.isNotEmpty) {
                            AppNavigatorPush
                                .push(context, '/bills/new?quotation_id=$id');
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dl(BuildContext sheet, String label, String value,
      {bool mono = false, Color? color}) {
    final c = sheet.c;
    final t = sheet.texts;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: t.labelSmall?.copyWith(
                color: c.fgFaint, fontSize: context.fs(10), letterSpacing: 0.6),
          ),
          const SizedBox(height: 1),
          Text(
            value,
            style: t.bodyMedium?.copyWith(
              color: color ?? c.fg,
              fontFamily: mono ? 'monospace' : null,
              fontWeight: mono ? FontWeight.w600 : null,
            ),
          ),
        ],
      ),
    );
  }

  /// The device's own queue: writes that have not reached the server, plus
  /// anything that failed permanently and needs a human.
  Widget _activity() {
    final c = context.c;
    final t = context.texts;
    if (_outbox.isEmpty) {
      return ListView(
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: const AppEmptyState(
              title: 'Nothing queued',
              message:
                  'Every change you have made has reached the server. Anything saved '
                  'while offline will appear here until it syncs.',
              icon: Icons.cloud_done_outlined,
            ),
          ),
        ],
      );
    }
    final sorted = [..._outbox]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return RefreshIndicator(
      color: c.brand,
      onRefresh: _loadOutbox,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        itemCount: sorted.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final row = sorted[i];
          final (tone, label) = switch (row.status) {
            OutboxStatus.pending => (AppTone.warning, 'Queued'),
            OutboxStatus.syncing => (AppTone.info, 'Syncing'),
            OutboxStatus.failed => (AppTone.danger, 'Failed'),
          };
          return AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      row.method == 'DELETE'
                          ? Icons.delete_outline_rounded
                          : row.method == 'PUT' || row.method == 'PATCH'
                              ? Icons.edit_outlined
                              : Icons.add_circle_outline_rounded,
                      size: 17,
                      color: tone.dot(c),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${row.method} ${row.url}',
                        style: t.bodySmall
                            ?.copyWith(color: c.fg2, fontFamily: 'monospace'),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    AppBadge(label, tone: tone, compact: true),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${row.service} · ${Fmt.relative(row.createdAt)}'
                  '${row.attempts > 0 ? ' · ${row.attempts} attempt${row.attempts == 1 ? '' : 's'}' : ''}',
                  style: t.labelSmall?.copyWith(color: c.fgFaint),
                ),
                if (row.lastError != null && row.lastError!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: AppNotice(
                      tone: AppTone.danger,
                      message: row.lastError!,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

enum _RowKind { gatePass, quotation }

class _Row {
  const _Row.gatePass(this.data) : kind = _RowKind.gatePass;
  const _Row.quotation(this.data) : kind = _RowKind.quotation;

  final _RowKind kind;
  final Map<String, dynamic> data;
}
