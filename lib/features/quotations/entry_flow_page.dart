import 'package:flutter/material.dart';

import '../../data/resource_controller.dart';
import '../../state/app_scope.dart';
import '../../ui/kit/primitives.dart';
import '../../ui/kit/shell_parts.dart';
import '../../ui/theme.dart';
import 'bill_form_page.dart';
import 'bill_model.dart';
import 'delivery_form_page.dart';
import 'gatepass_detail_page.dart';
import 'gatepass_form_page.dart';
import 'quotation_model.dart';
import 'return_form_page.dart';
import 'shared_widgets.dart';

/// Derived screen: the web app spreads this over the Today page — a row of
/// quick actions at the top, then the queues that say which step of the flow is
/// blocked. This screen is that same entry point as one page: the four
/// operations entries in the order the linen moves (receive → deliver → bill →
/// return), each with the pending count that says whether there is work waiting.
class EntryFlowPage extends StatefulWidget {
  const EntryFlowPage({super.key});

  @override
  State<EntryFlowPage> createState() => _EntryFlowPageState();
}

class _EntryFlowPageState extends State<EntryFlowPage> {
  late final ResourceController<List<PendingGatePass>> _pending;
  late final ResourceController<List<UnbilledGatePass>> _unbilled;
  late final ResourceController<List<ReturnRecord>> _returns;

  @override
  void initState() {
    super.initState();
    final cache = AppScope.read(context).cache;
    _pending = ResourceController(
      key: 'entry-pending-deliveries',
      cache: cache,
      fetcher: _fetchPending,
    );
    _unbilled = ResourceController(
      key: 'entry-unbilled',
      cache: cache,
      fetcher: _fetchUnbilled,
    );
    _returns = ResourceController(
      key: 'entry-returns',
      cache: cache,
      fetcher: _fetchReturns,
    );
    for (final c in [_pending, _unbilled, _returns]) {
      c.addListener(_onChanged);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void dispose() {
    for (final c in [_pending, _unbilled, _returns]) {
      c.removeListener(_onChanged);
      c.dispose();
    }
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<List<PendingGatePass>> _fetchPending() async {
    final hotel = AppScope.read(context).hotels.queryParam;
    final payload = await AppScope.read(context).api.get(
      operationsService,
      DeliveryApi.pendingGatePasses,
      query: {if (hotel != null) 'client_name': hotel},
    );
    return pendingGatePassesFrom(payload);
  }

  Future<List<UnbilledGatePass>> _fetchUnbilled() async {
    final hotel = AppScope.read(context).hotels.queryParam;
    final payload = await AppScope.read(context).api.get(
      operationsService,
      BillApi.unbilledGatePasses,
      query: {if (hotel != null) 'client_name': hotel},
    );
    return asRows(payload).map(UnbilledGatePass.fromJson).toList();
  }

  Future<List<ReturnRecord>> _fetchReturns() async {
    final hotel = AppScope.read(context).hotels.queryParam;
    final payload = await AppScope.read(context).api.get(
      operationsService,
      ReturnApi.list,
      query: {if (hotel != null) 'client_name': hotel, 'limit': 100},
    );
    return returnsFrom(payload);
  }

  Future<void> _reload() async {
    await Future.wait([
      _pending.load(force: true),
      _unbilled.load(force: true),
      _returns.load(force: true)
    ]);
  }

  /// Each queue is a soft signal: a failure on one must not hide the other two
  /// entries, so a failed read counts as no pending work rather than blocking.
  int get _pendingPieces => (_pending.data ?? const <PendingGatePass>[])
      .fold<int>(0, (s, p) => s + p.totalPending);

  int get _unbilledPieces => (_unbilled.data ?? const <UnbilledGatePass>[])
      .fold<double>(0, (s, p) => s + p.totalUnbilledQty)
      .round();

  int get _awaitingResend => (_returns.data ?? const <ReturnRecord>[])
      .fold<int>(0, (s, r) => s + r.pendingResendCount);

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    if (!canView(services, gatePassesPermission)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Entry flow')),
        body: opsNotPermitted('entry flow'),
      );
    }
    final canWrite = services.auth.hasPermission(gatePassesPermission);
    final pending = (_pending.data ?? const <PendingGatePass>[])
        .where((p) => p.totalPending > 0)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Entry flow'),
        actions: [
          AppButton.icon(
            icon: Icons.refresh,
            tooltip: 'Refresh',
            loading: _pending.isLoading || _unbilled.isLoading,
            onPressed: _reload,
          ),
        ],
      ),
      body: Column(
        children: [
          AppOfflineSyncBar(engine: services.sync),
          Expanded(
            child: RefreshIndicator(
              color: context.c.brand,
              onRefresh: _reload,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  _Step(
                    step: 1,
                    title: 'Receive',
                    hint: 'New gate pass',
                    icon: Icons.assignment_turned_in_outlined,
                    tone: AppTone.info,
                    pendingLabel: null,
                    enabled: canWrite,
                    onTap: _openGatePass,
                  ),
                  const SizedBox(height: 10),
                  _Step(
                    step: 2,
                    title: 'Deliver',
                    hint: 'Record delivery',
                    icon: Icons.local_shipping_outlined,
                    tone: AppTone.success,
                    pendingLabel: _pendingPieces == 0
                        ? null
                        : '$_pendingPieces pcs to deliver',
                    enabled: canWrite,
                    onTap: _openDelivery,
                  ),
                  const SizedBox(height: 10),
                  _Step(
                    step: 3,
                    title: 'Bill',
                    hint: 'Create bill',
                    icon: Icons.receipt_long_outlined,
                    tone: AppTone.warning,
                    pendingLabel: _unbilledPieces == 0
                        ? null
                        : '$_unbilledPieces pcs unbilled',
                    enabled: canWrite,
                    onTap: _openBill,
                  ),
                  const SizedBox(height: 10),
                  _Step(
                    step: 4,
                    title: 'Return',
                    hint: 'Record return',
                    icon: Icons.assignment_return_outlined,
                    tone: AppTone.danger,
                    pendingLabel: _awaitingResend == 0
                        ? null
                        : '$_awaitingResend to resend',
                    enabled: canWrite,
                    onTap: _openReturn,
                  ),
                  const SizedBox(height: 20),
                  if (pending.isEmpty)
                    AppCard(
                      child: Row(
                        children: [
                          const OpsIcon(Icons.check_circle_outline,
                              tone: AppTone.success),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Nothing pending. Every received item has been delivered.',
                              style: context.texts.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    Row(
                      children: [
                        Text('Pending to deliver',
                            style: context.texts.titleSmall),
                        const Spacer(),
                        if (canWrite)
                          AppButton(
                            label: 'Deliver',
                            size: AppButtonSize.xs,
                            variant: AppButtonVariant.primary,
                            icon: Icons.local_shipping_outlined,
                            onPressed: _openDelivery,
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    for (final p in pending) ...[
                      _PendingRow(
                          pass: p, onTap: () => _openPass(p.gatePassId)),
                      const SizedBox(height: 8),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openGatePass() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const GatepassFormPage()),
    );
    if (mounted) _reload();
  }

  Future<void> _openDelivery() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const DeliveryFormPage()),
    );
    if (mounted) _reload();
  }

  Future<void> _openBill() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const BillFormPage()),
    );
    if (mounted) _reload();
  }

  Future<void> _openReturn() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const ReturnFormPage()),
    );
    if (mounted) _reload();
  }

  Future<void> _openPass(String id) async {
    if (id.isEmpty) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => GatepassDetailPage(gatepassId: id)),
    );
    if (mounted) _reload();
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.step,
    required this.title,
    required this.hint,
    required this.icon,
    required this.tone,
    required this.enabled,
    required this.onTap,
    this.pendingLabel,
  });

  final int step;
  final String title;
  final String hint;
  final IconData icon;
  final AppTone tone;
  final bool enabled;
  final VoidCallback onTap;
  final String? pendingLabel;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: enabled ? onTap : null,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Row(
        children: [
          OpsIcon(icon, tone: tone),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: context.texts.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  hint,
                  style: context.texts.bodySmall
                      ?.copyWith(color: context.c.fgMuted),
                ),
              ],
            ),
          ),
          if (pendingLabel != null) ...[
            AppBadge(pendingLabel!, tone: tone, compact: true),
            const SizedBox(width: 8),
          ],
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.c.surfaceSunken,
              shape: BoxShape.circle,
              border: Border.all(color: context.c.line),
            ),
            child: Text(
              '$step',
              style:
                  context.texts.bodySmall?.copyWith(color: context.c.fgMuted),
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right, size: 18, color: context.c.fgFaint),
        ],
      ),
    );
  }
}

class _PendingRow extends StatelessWidget {
  const _PendingRow({required this.pass, required this.onTap});

  final PendingGatePass pass;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pass.gatePassNumber.isEmpty ? '—' : pass.gatePassNumber,
                  style: context.texts.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  pass.items
                      .map((i) => '${i.itemName} ×${i.pendingQty}')
                      .join(', '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.bodySmall
                      ?.copyWith(color: context.c.fgMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                pass.clientName.isEmpty ? '—' : pass.clientName,
                style: context.texts.bodySmall,
              ),
              Text(
                '${pass.totalPending} pcs',
                style:
                    context.texts.bodySmall?.copyWith(color: context.c.success),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
