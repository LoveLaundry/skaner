import 'package:flutter/material.dart';

import '../../../config/api_config.dart';
import '../../../config/app_config.dart';
import '../../../core/utils/formatting.dart';
import '../../../data/resource_controller.dart';
import '../../../state/app_scope.dart';
import '../../../ui/brand/logo.dart';
import '../../../ui/kit/feedback.dart';
import '../../../ui/kit/primitives.dart';
import '../../../ui/theme.dart';

/// Port of `features/quotations/pages/guest-quotations-page.tsx`.
///
/// The shop's shopfront, so it carries no application chrome: a masthead, the
/// price list, and the legal registration number in the footer. No scope
/// selector, no sign-in prompt, and no session — the request goes out without an
/// Authorization header so the screen is identical signed in or not.
class GuestShopPage extends StatefulWidget {
  const GuestShopPage({super.key});

  @override
  State<GuestShopPage> createState() => _GuestShopPageState();
}

class _GuestShopPageState extends State<GuestShopPage> {
  late final ResourceController<List<Map<String, dynamic>>> _priceList;

  @override
  void initState() {
    super.initState();
    _priceList = ResourceController<List<Map<String, dynamic>>>(
      key: 'guest-shop',
      cache: AppScope.read(context).cache,
      fetcher: () async {
        final api = AppScope.read(context).api;
        return asRows(
          await api.get(
            ServiceNames.quotation,
            GuestRoute.shopPriceList,
            includeAuth: false,
          ),
        );
      },
    )..addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _priceList.load(force: true),
    );
  }

  @override
  void dispose() {
    _priceList.removeListener(_onChanged);
    _priceList.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  double _total(Map<String, dynamic> row) {
    final items = asRows(pick(row, ['line_items']));
    return items.fold<double>(0, (sum, i) => sum + numOf(i, ['unit_price']));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.texts;
    return Scaffold(
      backgroundColor: c.canvas,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: c.surface,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  const Expanded(child: AppLogo(size: 32)),
                  const SizedBox(width: 10),
                  AppBadge(
                    'Public price list',
                    icon: Icons.storefront_outlined,
                    tone: AppTone.neutral,
                    compact: true,
                  ),
                ],
              ),
              // A hairline keeps the masthead legible over a scrolling list.
            ),
            Container(height: 1, color: c.line),
            Expanded(
              child: RefreshIndicator(
                color: c.brand,
                onRefresh: () => _priceList.load(force: true),
                child: _body(),
              ),
            ),
            Container(
              width: double.infinity,
              color: c.surface,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '© ${DateTime.now().year} ${CompanyInfo.name} · Reg. No. '
                    '${CompanyInfo.registrationNo}',
                    style: t.bodySmall?.copyWith(color: c.fgMuted),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Laundry and linen services for hotels, hospitals and institutions.',
                    style: t.bodySmall?.copyWith(color: c.fgFaint),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    final c = context.c;
    final t = context.texts;
    final rows = _priceList.data ?? const <Map<String, dynamic>>[];

    if (_priceList.phase == LoadPhase.failed && rows.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: AppErrorState(
              title: 'Price list unavailable',
              message: 'Could not load the price list. Please try again.',
              onRetry: () => _priceList.load(force: true),
            ),
          ),
        ],
      );
    }

    if (_priceList.isLoading && rows.isEmpty) {
      return const AppSkeletonList(count: 3, lines: 2);
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
      children: [
        Text(
          '${CompanyInfo.name.toUpperCase()} · REG. NO. ${CompanyInfo.registrationNo}',
          style: t.labelSmall?.copyWith(
            color: c.fgFaint,
            fontSize: 10.5,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 4),
        Text('Shop services and pricing', style: t.titleLarge),
        const SizedBox(height: 4),
        Text(
          'Prices below are indicative. Final cost depends on fabric, quantity '
          'and turnaround — contact us to confirm a booking.',
          style: t.bodySmall?.copyWith(color: c.fgMuted),
        ),
        const SizedBox(height: 14),
        if (rows.isEmpty)
          const AppEmptyState(
            title: 'No services listed yet',
            message: 'The price list has not been published. Please check back shortly.',
            icon: Icons.description_outlined,
          )
        else
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                onTap: () => _showPackage(row),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            str(row, ['quotation_title'], 'Service package'),
                            style: t.titleSmall,
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              AppBadge(
                                str(row, ['status'], 'draft').toLowerCase(),
                                tone: _statusTone(str(row, ['status'])),
                                compact: true,
                              ),
                              Text(
                                str(row, ['client_name'], '—'),
                                style: t.labelSmall?.copyWith(color: c.fgFaint),
                              ),
                              if (pick(row, ['created_at']) != null)
                                Text(
                                  Fmt.date(row['created_at']),
                                  style:
                                      t.labelSmall?.copyWith(color: c.fgFaint),
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
                          '${asRows(pick(row, ['line_items'])).length} items',
                          style: t.labelSmall?.copyWith(color: c.fgFaint),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          Fmt.money(_total(row)),
                          style: t.titleSmall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  static AppTone _statusTone(String raw) => switch (raw.toLowerCase()) {
        'sent' => AppTone.info,
        'accepted' => AppTone.success,
        _ => AppTone.neutral,
      };

  void _showPackage(Map<String, dynamic> row) {
    final items = asRows(pick(row, ['line_items']));
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheet).size.height * 0.8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      str(row, ['quotation_title'], 'Service package'),
                      style: sheet.texts.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      str(row, ['client_name'], '—'),
                      style:
                          sheet.texts.bodySmall?.copyWith(color: sheet.c.fgMuted),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: items.isEmpty
                    ? const AppEmptyState(
                        title: 'No items on this package',
                        icon: Icons.inbox_outlined,
                        compact: true,
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final item = items[i];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        str(item, ['item_name'], 'Item'),
                                        style: sheet.texts.bodyMedium,
                                      ),
                                      if (str(item, ['category']).isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 2),
                                          child: Text(
                                            str(item, ['category']),
                                            style: sheet.texts.labelSmall
                                                ?.copyWith(color: sheet.c.fgFaint),
                                          ),
                                        ),
                                      if (str(item, ['notes']).isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 2),
                                          child: Text(
                                            str(item, ['notes']),
                                            style: sheet.texts.labelSmall
                                                ?.copyWith(color: sheet.c.fgMuted),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  Fmt.money(numOf(item, ['unit_price'])),
                                  style: sheet.texts.bodyMedium,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('Estimated total',
                              style: sheet.texts.titleSmall),
                        ),
                        Text(
                          Fmt.money(_total(row)),
                          style: sheet.texts.titleMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(Icons.phone_outlined,
                            size: 14, color: sheet.c.fgMuted),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'To confirm a booking, call ${CompanyInfo.phonePrimary}.',
                            style: sheet.texts.labelSmall
                                ?.copyWith(color: sheet.c.fgMuted),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    AppButton(
                      label: 'Close',
                      variant: AppButtonVariant.secondary,
                      block: true,
                      onPressed: () => Navigator.of(sheet).pop(),
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
}
