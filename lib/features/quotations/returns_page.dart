import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/sync_engine.dart';
import '../../data/resource_controller.dart';
import '../../state/app_scope.dart';
import '../../ui/kit/feedback.dart';
import '../../ui/kit/inputs.dart';
import '../../ui/kit/primitives.dart';
import '../../ui/kit/shell_parts.dart';
import '../../ui/theme.dart';
import '../../ui/kit/data.dart';
import 'bill_model.dart';
import 'quotation_model.dart';
import 'return_detail_page.dart';
import 'return_form_page.dart';
import 'shared_widgets.dart';

/// Port of `pages/returns-page.tsx`.
///
/// The web page sends the typed client name to the server rather than filtering
/// the loaded page, so this list does the same and debounces the keystrokes.
class ReturnsPage extends StatefulWidget {
  const ReturnsPage({super.key});

  @override
  State<ReturnsPage> createState() => _ReturnsPageState();
}

class _ReturnsPageState extends State<ReturnsPage> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  late final ResourceController<List<ReturnRecord>> _returns;

  String _search = '';

  @override
  void initState() {
    super.initState();
    _returns = ResourceController(
      key: 'returns',
      cache: AppScope.read(context).cache,
      fetcher: _fetch,
    );
    _returns.addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _returns.removeListener(_onChanged);
    _returns.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<List<ReturnRecord>> _fetch() async {
    final hotel = AppScope.read(context).hotels.queryParam;
    final payload = await AppScope.read(context).api.get(
      operationsService,
      ReturnApi.list,
      query: {
        if (hotel != null) 'client_name': hotel,
        if (_search.isNotEmpty) 'client_name': _search,
        'limit': 200,
      },
    );
    return returnsFrom(payload);
  }

  Future<void> _reload() => _returns.load(force: true);

  void _onSearch(String value) {
    final trimmed = value.trim();
    setState(() => _search = trimmed);
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () {
        if (mounted) _reload();
      },
    );
  }

  void _clearSearch() {
    _searchCtrl.clear();
    _onSearch('');
  }

  List<OpsMetric> get _metrics {
    final all = _returns.data ?? const <ReturnRecord>[];
    return [
      OpsMetric(
        id: 'total',
        label: 'Records',
        value: '${all.length}',
        icon: Icons.assignment_return_outlined,
        tone: AppTone.neutral,
      ),
      for (final entry in {
        'PENDING': ('Pending', AppTone.warning, Icons.schedule),
        'RECEIVED': ('Received', AppTone.info, Icons.move_to_inbox_outlined),
        'PROCESSED': ('Processed', AppTone.success, Icons.task_alt),
      }.entries)
        OpsMetric(
          id: entry.key,
          label: entry.value.$1,
          value: '${all.where((r) => r.status == entry.key).length}',
          icon: entry.value.$3,
          tone: entry.value.$2,
        ),
      OpsMetric(
        id: 'resend',
        label: 'Awaiting resend',
        value: '${all.fold<int>(0, (sum, r) => sum + r.pendingResendCount)}',
        icon: Icons.send_outlined,
        tone: AppTone.danger,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    if (!canView(services, gatePassesPermission)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Returns')),
        body: opsNotPermitted('returns'),
      );
    }
    final canWrite = services.auth.hasPermission(gatePassesPermission);
    final all = _returns.data ?? const <ReturnRecord>[];
    final loading = _returns.isLoading && all.isEmpty;

    return Scaffold(
      body: Column(
        children: [
          AppPageHeader(
            title: 'Returns',
            actions: [
              AppButton.icon(
                icon: Icons.refresh,
                tooltip: 'Refresh',
                loading: _returns.isLoading,
                onPressed: _reload,
              ),
            ],
          ),
          AppSyncStatusBar(
            status: _returns.status,
            updatedAt: _returns.lastUpdated,
            label: 'Returns',
          ),
          AppOfflineSyncBar(engine: services.sync),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: AppTextInput(
              controller: _searchCtrl,
              hint: 'Search by client name…',
              icon: Icons.search,
              textInputAction: TextInputAction.search,
              onChanged: _onSearch,
              suffix: _search.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      tooltip: 'Clear search',
                      onPressed: _clearSearch,
                    ),
            ),
          ),
          CompactMetrics(items: _metrics),
          Expanded(
            child: RefreshIndicator(
              color: context.c.brand,
              onRefresh: _reload,
              child: _returns.phase == LoadPhase.failed && all.isEmpty
                  ? AppErrorState(message: _returns.error, onRetry: _reload)
                  : loading
                      ? const AppSkeletonList()
                      : all.isEmpty
                          ? _empty(canWrite, filtered: false)
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                              itemCount: all.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, i) => _ReturnCard(
                                record: all[i],
                                canWrite: canWrite,
                                onOpen: () => _openDetail(all[i].key),
                                onMarkResent: (line) =>
                                    _markResent(all[i], line),
                              ),
                            ),
            ),
          ),
        ],
      ),
      floatingActionButton: canWrite
          ? FloatingActionButton.extended(
              onPressed: _openCreate,
              backgroundColor: context.c.brand,
              foregroundColor: context.c.onBrand,
              icon: const Icon(Icons.add),
              label: const Text('Record return'),
            )
          : null,
    );
  }

  Widget _empty(bool canWrite, {required bool filtered}) => ListView(
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.4,
            child: AppEmptyState(
              title: filtered ? 'No returns found' : 'No returns recorded',
              message: filtered
                  ? 'No returns found for "$_search".'
                  : 'Record a return when garments come back from a client.',
              icon: Icons.assignment_return_outlined,
              action: filtered
                  ? AppButton(
                      label: 'Clear search',
                      variant: AppButtonVariant.secondary,
                      onPressed: _clearSearch,
                    )
                  : canWrite
                      ? AppButton(
                          label: 'Record return',
                          variant: AppButtonVariant.primary,
                          icon: Icons.add,
                          onPressed: _openCreate,
                        )
                      : null,
            ),
          ),
        ],
      );

  /// Only the two actions that mean "send it back" are eligible; a discarded or
  /// compensated line has nothing left to resend.
  Future<void> _markResent(ReturnRecord record, ReturnLine line) async {
    try {
      final result = await AppScope.read(context).api.post(
        operationsService,
        ReturnApi.resent(record.key),
        body: null,
        query: {
          'item_name': line.itemName,
          'specification': line.specification,
        },
      );
      if (!mounted) return;
      QueryCacheInvalidator.instance.invalidate('returns');
      await _reload();
      if (!mounted) return;
      AppToast.success(
        context,
        result is QueuedResponse
            ? 'Marked as sent — will sync when back online'
            : 'Marked as sent',
      );
    } on ApiException catch (e) {
      if (mounted) AppToast.error(context, e.message);
    }
  }

  Future<void> _openCreate() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ReturnFormPage()),
    );
    if (created == true && mounted) _reload();
  }

  Future<void> _openDetail(String id) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => ReturnDetailPage(returnId: id)),
    );
    if (mounted) _reload();
  }
}

class _ReturnCard extends StatelessWidget {
  const _ReturnCard({
    required this.record,
    required this.canWrite,
    required this.onOpen,
    required this.onMarkResent,
  });

  final ReturnRecord record;
  final bool canWrite;
  final VoidCallback onOpen;
  final ValueChanged<ReturnLine> onMarkResent;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final pending = record.items
        .where(
            (i) => returnResendActions.contains(i.action) && i.isPendingResend)
        .toList();
    return AppCard(
      onTap: onOpen,
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const OpsIcon(Icons.assignment_return_outlined,
                  tone: AppTone.warning),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.clientName.isEmpty ? '—' : record.clientName,
                      style: context.texts.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      record.returnId.isEmpty ? '—' : record.returnId,
                      style:
                          context.texts.bodySmall?.copyWith(color: c.fgFaint),
                    ),
                  ],
                ),
              ),
              ReturnStatusBadge(status: record.status),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final line in record.items)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: c.surfaceSunken,
                    border: Border.all(color: c.line),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        line.itemName,
                        style: context.texts.bodySmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      if (line.specification.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: c.surface3,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            line.specification,
                            style: context.texts.bodySmall?.copyWith(
                                fontSize: 9, color: c.fg2),
                          ),
                        ),
                      ],
                      const SizedBox(width: 4),
                      Text(
                        '×${line.returnedQty}',
                        style:
                            context.texts.bodySmall?.copyWith(color: c.fgFaint),
                      ),
                      if (line.resendStatus == 'SENT') ...[
                        const SizedBox(width: 4),
                        Icon(Icons.check, size: 11, color: c.success),
                      ],
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '${record.totalPieces} items returned',
                style: context.texts.bodySmall?.copyWith(color: c.fgMuted),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  _reasons(record),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: context.texts.bodySmall?.copyWith(color: c.fgMuted),
                ),
              ),
            ],
          ),
          if (pending.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              decoration: BoxDecoration(
                color: c.warningSoft,
                border: Border.all(color: c.warningBorder),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < pending.length; i++) ...[
                    if (i > 0) const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${pending[i].itemName}'
                            '${pending[i].specification.isEmpty ? '' : ' (${pending[i].specification})'}'
                            ' ×${pending[i].returnedQty}',
                            style: context.texts.bodySmall
                                ?.copyWith(color: c.warning),
                          ),
                        ),
                        if (canWrite)
                          AppButton(
                            label: 'Sent',
                            size: AppButtonSize.xs,
                            variant: AppButtonVariant.secondary,
                            icon: Icons.send_outlined,
                            onPressed: () => onMarkResent(pending[i]),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// The web card joins the distinct reasons in item order; duplicates would
  /// otherwise read as noise on a wide return.
  static String _reasons(ReturnRecord record) {
    final seen = <String>{};
    for (final line in record.items) {
      seen.add(line.reason);
    }
    return seen.join(', ');
  }
}
