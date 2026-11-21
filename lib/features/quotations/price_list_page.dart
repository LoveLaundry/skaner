import 'package:flutter/material.dart';

import '../../core/utils/formatting.dart';
import '../../config/api_config.dart';
import '../../data/resource_controller.dart';
import '../../state/app_scope.dart';
import '../../ui/kit/feedback.dart';
import '../../ui/kit/primitives.dart';
import '../../ui/kit/shell_parts.dart';
import '../../ui/theme.dart';
import 'quotation_model.dart';
import 'shared_widgets.dart';

/// Derived screen: the web app publishes this list as
/// `pages/guest-quotations-page.tsx`, an unauthenticated shopfront route rather
/// than an app screen. The mobile port keeps the same source — the public
/// `/quotations/guest/shop` documents, the indicative-total framing, and the
/// registration footer — and drops only the "no sign-in chrome" rule, which
/// cannot hold inside the app shell.
class PriceListPage extends StatefulWidget {
  const PriceListPage({super.key});

  @override
  State<PriceListPage> createState() => _PriceListPageState();
}

class _PriceListPageState extends State<PriceListPage> {
  late final ResourceController<List<Quotation>> _packages;

  @override
  void initState() {
    super.initState();
    _packages = ResourceController(
      key: 'price-list',
      cache: AppScope.read(context).cache,
      fetcher: _fetch,
    );
    _packages.addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void dispose() {
    _packages.removeListener(_onChanged);
    _packages.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<List<Quotation>> _fetch() async {
    final payload = await AppScope.read(context)
        .api
        .get(ServiceNames.quotation, '/quotations/guest/shop');
    return quotationsFrom(payload);
  }

  Future<void> _reload() => _packages.load(force: true);

  @override
  Widget build(BuildContext context) {
    final all = _packages.data ?? const <Quotation>[];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Price list'),
        actions: [
          AppButton.icon(
            icon: Icons.refresh,
            tooltip: 'Refresh',
            loading: _packages.isLoading,
            onPressed: _reload,
          ),
        ],
      ),
      body: Column(
        children: [
          AppSyncStatusBar(
            status: _packages.status,
            updatedAt: _packages.lastUpdated,
            label: 'Price list',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LOVE LAUNDRY · REG. NO. 40-3064',
                  style: context.texts.bodySmall?.copyWith(
                    color: context.c.fgFaint,
                    fontSize: 10,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text('Shop services and pricing',
                    style: context.texts.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Prices below are indicative. Final cost depends on fabric, '
                  'quantity and turnaround — contact us to confirm a booking.',
                  style: context.texts.bodySmall
                      ?.copyWith(color: context.c.fgMuted),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              color: context.c.brand,
              onRefresh: _reload,
              child: _packages.phase == LoadPhase.failed && all.isEmpty
                  ? AppErrorState(
                      message: _packages.error ??
                          'Could not load the price list. Please try again.',
                      onRetry: _reload,
                    )
                  : _packages.isLoading && all.isEmpty
                      ? const AppSkeletonList(count: 4)
                      : all.isEmpty
                          ? ListView(
                              children: [
                                SizedBox(
                                  height:
                                      MediaQuery.of(context).size.height * 0.4,
                                  child: const AppEmptyState(
                                    title: 'No services listed yet',
                                    message:
                                        'The price list has not been published. '
                                        'Please check back shortly.',
                                    icon: Icons.description_outlined,
                                  ),
                                ),
                              ],
                            )
                          : ListView.separated(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 12, 16, 24),
                              itemCount: all.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, i) => _PackageRow(
                                quotation: all[i],
                                onTap: () => _openPackage(all[i]),
                              ),
                            ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('© 2026 Love Laundry · Reg. No. 40-3064',
                    style: context.texts.bodySmall
                        ?.copyWith(color: context.c.fgMuted)),
                const SizedBox(height: 2),
                Text(
                  'Laundry and linen services for hotels, hospitals and institutions.',
                  style: context.texts.bodySmall
                      ?.copyWith(color: context.c.fgFaint),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openPackage(Quotation q) async {
    await showDialog<void>(
      context: context,
      builder: (_) => AppDialog(
        title: q.displayTitle,
        body: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              q.clientName,
              style:
                  context.texts.bodySmall?.copyWith(color: context.c.fgMuted),
            ),
            const SizedBox(height: 12),
            for (final item in q.lineItems)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.itemName, style: context.texts.bodyMedium),
                          if (item.category.trim().isNotEmpty)
                            Text(
                              item.category,
                              style: context.texts.bodySmall
                                  ?.copyWith(color: context.c.fgFaint),
                            ),
                          if (item.notes.trim().isNotEmpty)
                            Text(
                              item.notes,
                              style: context.texts.bodySmall?.copyWith(
                                color: context.c.fgMuted,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      Fmt.money(item.effectiveRate),
                      style: context.texts.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            const Divider(height: 16),
            OpsTotalRow(
              label: 'Estimated total',
              value: Fmt.money(q.rateTotal),
              strong: true,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.phone_outlined, size: 13),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    'To confirm a booking, call the shop.',
                    style: context.texts.bodySmall
                        ?.copyWith(color: context.c.fgMuted),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          AppButton(
            label: 'Close',
            variant: AppButtonVariant.secondary,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _PackageRow extends StatelessWidget {
  const _PackageRow({required this.quotation, required this.onTap});

  final Quotation quotation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  quotation.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    AppBadge(
                      humaniseStatus(quotation.status.name),
                      tone: AppTone.neutral,
                      compact: true,
                    ),
                    if (quotation.createdAt != null)
                      Text(
                        Fmt.date(quotation.createdAt),
                        style: context.texts.bodySmall
                            ?.copyWith(color: context.c.fgFaint),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${quotation.itemCount} items',
                style:
                    context.texts.bodySmall?.copyWith(color: context.c.fgFaint),
              ),
              const SizedBox(height: 2),
              Text(
                Fmt.money(quotation.rateTotal),
                style: context.texts.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
