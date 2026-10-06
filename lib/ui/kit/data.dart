import 'package:flutter/material.dart';

import '../theme.dart';
import 'feedback.dart';
import 'primitives.dart';

/// Port of `components/ui/stat-card.tsx`.
/// The tone is reserved for trend direction, never decoration.
enum StatTrend {
  up(Icons.trending_up_rounded, AppTone.success),
  down(Icons.trending_down_rounded, AppTone.danger),
  flat(Icons.trending_flat_rounded, AppTone.neutral);

  const StatTrend(this.icon, this.tone);
  final IconData icon;
  final AppTone tone;
}

class AppStatCard extends StatelessWidget {
  const AppStatCard({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.trend,
    this.trendLabel,
    this.caption,
    this.onTap,
    this.compact = false,
    this.footer,
  });

  final String label;
  final String value;
  final IconData? icon;
  final StatTrend? trend;
  final String? trendLabel;
  final String? caption;
  final VoidCallback? onTap;
  final bool compact;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.texts;
    return AppCard(
      onTap: onTap,
      padding: EdgeInsets.all(compact ? 12 : 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: t.labelSmall?.copyWith(
                      color: c.fgMuted, letterSpacing: 0.2),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (icon != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(Radii.sm),
                  ),
                  child: Icon(icon, size: 15, color: c.fg3),
                ),
              ],
            ],
          ),
          SizedBox(height: compact ? 6 : 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: (compact ? t.titleMedium : t.headlineSmall)
                  ?.copyWith(color: c.fg),
            ),
          ),
          if (trend != null || caption != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                if (trend != null) ...[
                  Icon(trend!.icon, size: 13, color: trend!.tone.resolve(c).$1),
                  const SizedBox(width: 3),
                  Text(
                    trendLabel ?? '',
                    style: t.labelSmall?.copyWith(
                        color: trend!.tone.resolve(c).$1,
                        fontWeight: FontWeight.w600),
                  ),
                ],
                if (caption != null) ...[
                  if (trend != null) const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      caption!,
                      style: t.labelSmall?.copyWith(color: c.fgFaint),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ],
          if (footer != null) ...[
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),
            footer!,
          ],
        ],
      ),
    );
  }
}

/// Port of `components/ui/page-header.tsx`.
class AppPageHeader extends StatelessWidget {
  const AppPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.breadcrumb,
    this.actions = const [],
    this.tabs,
    this.busy = false,
  });

  final String title;
  final String? subtitle;
  final Widget? breadcrumb;
  final List<Widget> actions;
  final Widget? tabs;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.texts;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (breadcrumb != null) breadcrumb!,
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: t.titleLarge),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(subtitle!,
                            style: t.bodySmall
                                ?.copyWith(color: c.fgMuted)),
                      ),
                  ],
                ),
              ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.only(right: 8, top: 4),
                  child: AppSpinner(size: 15),
                ),
              if (actions.isNotEmpty)
                Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: actions,
                ),
            ],
          ),
          if (tabs != null) ...[
            const SizedBox(height: 10),
            tabs!,
            const SizedBox(height: 1),
          ] else
            const SizedBox(height: 12),
        ],
      ),
    );
  }
}

/// Port of `components/ui/breadcrumb.tsx`.
class AppBreadcrumb extends StatelessWidget {
  const AppBreadcrumb({super.key, required this.trail});

  final List<String> trail;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.texts;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          for (var i = 0; i < trail.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.chevron_right, size: 13, color: c.fgFaint),
              ),
            Flexible(
              child: Text(
                trail[i],
                style: t.labelSmall?.copyWith(
                    color: i == trail.length - 1 ? c.fg2 : c.fgFaint),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Port of `components/ui/tabs.tsx`.
class AppTabs extends StatelessWidget {
  const AppTabs({
    super.key,
    required this.tabs,
    required this.index,
    required this.onChanged,
    this.scrollable = true,
  });

  final List<AppTabItem> tabs;
  final int index;
  final ValueChanged<int> onChanged;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.texts;
    final bar = Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
      child: scrollable
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: _items(context, t, c)),
            )
          : Row(children: _items(context, t, c)),
    );
    return bar;
  }

  List<Widget> _items(BuildContext context, TextTheme t, AppColors c) {
    final out = <Widget>[];
    for (var i = 0; i < tabs.length; i++) {
      final active = i == index;
      out.add(
        InkWell(
          onTap: () => onChanged(i),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: active ? c.brand : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (tabs[i].icon != null) ...[
                  Icon(tabs[i].icon,
                      size: 15, color: active ? c.brand : c.fgFaint),
                  const SizedBox(width: 6),
                ],
                Text(
                  tabs[i].label,
                  style: t.labelLarge?.copyWith(
                      color: active ? c.brand : c.fg3),
                ),
                if (tabs[i].count != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: active ? c.brandSoft : c.surface3,
                      borderRadius: BorderRadius.circular(Radii.pill),
                    ),
                    child: Text(
                      '${tabs[i].count}',
                      style: t.labelSmall
                          ?.copyWith(color: active ? c.brandText : c.fg3),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }
    return out;
  }
}

class AppTabItem {
  const AppTabItem(this.label, {this.icon, this.count});
  final String label;
  final IconData? icon;
  final int? count;
}

/// Port of `components/ui/toolbar.tsx` — a row of controls above a list.
class AppToolbar extends StatelessWidget {
  const AppToolbar({super.key, required this.children, this.padding});

  final List<Widget> children;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding ??
            const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: children,
        ),
      );
}

/// Port of `components/ui/filter-bar.tsx`.
class AppFilterBar extends StatelessWidget {
  const AppFilterBar({super.key, required this.children, this.onClear});

  final List<Widget> children;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: children,
          ),
        ),
        if (onClear != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.filter_alt_off_outlined, size: 15),
              label: const Text('Clear filters'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: c.fgMuted,
              ),
            ),
          ),
      ],
    );
  }
}

/// Port of `components/ui/pagination.tsx`.
class AppPagination extends StatelessWidget {
  const AppPagination({
    super.key,
    required this.page,
    required this.total,
    required this.onPage,
    this.label = 'rows',
  });

  final int page;
  final int total;
  final ValueChanged<int> onPage;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.texts;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Page $page of $total',
              style: t.bodySmall?.copyWith(color: c.fgMuted),
            ),
          ),
          AppButton.icon(
            icon: Icons.chevron_left,
            tooltip: 'Previous page',
            size: AppButtonSize.iconSm,
            variant: AppButtonVariant.secondary,
            onPressed: page > 1 ? () => onPage(page - 1) : null,
          ),
          const SizedBox(width: 6),
          AppButton.icon(
            icon: Icons.chevron_right,
            tooltip: 'Next page',
            size: AppButtonSize.iconSm,
            variant: AppButtonVariant.secondary,
            onPressed: page < total ? () => onPage(page + 1) : null,
          ),
        ],
      ),
    );
  }
}

/// Port of `components/ui/data-table.tsx` / `table.tsx`, adapted to a card list
/// on narrow screens so a phone operator never has to scroll a table sideways.
class AppDataColumn<T> {
  const AppDataColumn({
    required this.label,
    required this.value,
    this.minWidth = 110,
    this.align = CrossAxisAlignment.start,
    this.flexible = true,
  });

  final String label;
  final String Function(T) value;
  final double minWidth;
  final CrossAxisAlignment align;
  final bool flexible;
}

class AppDataTable<T> extends StatelessWidget {
  const AppDataTable({
    super.key,
    required this.columns,
    required this.rows,
    this.onRowTap,
    this.emptyTitle = 'Nothing here yet',
    this.emptyMessage,
    this.emptyIcon = Icons.table_rows_outlined,
    this.loading = false,
    this.loadingCount = 6,
    this.rowLeading,
    this.rowTrailing,
    this.selectedIndex,
    this.selectable = false,
  });

  final List<AppDataColumn<T>> columns;
  final List<T> rows;
  final void Function(T)? onRowTap;
  final String emptyTitle;
  final String? emptyMessage;
  final IconData emptyIcon;
  final bool loading;
  final int loadingCount;
  final Widget Function(BuildContext, T)? rowLeading;
  final Widget Function(BuildContext, T)? rowTrailing;
  final int? selectedIndex;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    if (loading) return AppSkeletonList(count: loadingCount);
    if (rows.isEmpty) {
      return AppEmptyState(
        title: emptyTitle,
        message: emptyMessage,
        icon: emptyIcon,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) => _Row<T>(
        row: rows[i],
        columns: columns,
        index: i,
        selected: selectedIndex == i,
        onTap: onRowTap == null ? null : () => onRowTap!(rows[i]),
        leading: rowLeading?.call(context, rows[i]),
        trailing: rowTrailing?.call(context, rows[i]),
      ),
    );
  }
}

class _Row<T> extends StatelessWidget {
  const _Row({
    required this.row,
    required this.columns,
    required this.index,
    required this.selected,
    this.onTap,
    this.leading,
    this.trailing,
  });

  final T row;
  final List<AppDataColumn<T>> columns;
  final int index;
  final bool selected;
  final VoidCallback? onTap;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.texts;
    final primary = columns.isEmpty ? '' : columns.first.value(row);
    final rest = columns.length > 1 ? columns.sublist(1) : <AppDataColumn<T>>[];

    return AppCard(
      onTap: onTap,
      selected: selected,
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 10)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  primary,
                  style: t.titleSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (rest.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 14,
                    runSpacing: 4,
                    children: [
                      for (final col in rest)
                        ConstrainedBox(
                          constraints:
                              const BoxConstraints(minWidth: 84, maxWidth: 190),
                          child: Column(
                            crossAxisAlignment: col.align,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                col.label,
                                style: t.labelSmall
                                    ?.copyWith(color: c.fgFaint, fontSize: 10.5),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                col.value(row),
                                style: t.bodySmall
                                    ?.copyWith(color: c.fg2, fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ] else if (onTap != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(Icons.chevron_right, size: 18, color: c.fgFaint),
            ),
        ],
      ),
    );
  }
}

/// Port of `components/ui/bill-status-badge.tsx`.
class BillStatusBadge extends StatelessWidget {
  const BillStatusBadge({super.key, required this.status, this.showDot = true});

  final String? status;
  final bool showDot;

  static const billPaymentStatuses = [
    'PAID',
    'PARTIALLY_PAID',
    'PENDING',
    'ISSUED',
    'DRAFT',
    'CANCELLED',
  ];

  static const billStatusFilters = [
    (value: '', label: 'All'),
    (value: 'PAID', label: 'Paid'),
    (value: 'PARTIALLY_PAID', label: 'Partial'),
    (value: 'PENDING', label: 'Pending'),
    (value: 'DRAFT', label: 'Draft'),
    (value: 'CANCELLED', label: 'Cancelled'),
  ];

  static (String, AppTone) config(String? raw) => switch (raw) {
        'PAID' => ('Paid', AppTone.success),
        'PARTIALLY_PAID' => ('Partial', AppTone.warning),
        'PENDING' => ('Pending', AppTone.danger),
        'ISSUED' => ('Issued', AppTone.warning),
        'DRAFT' => ('Draft', AppTone.neutral),
        'CANCELLED' => ('Cancelled', AppTone.neutral),
        _ => (raw ?? '', AppTone.neutral),
      };

  @override
  Widget build(BuildContext context) {
    if (status == null || status!.isEmpty) {
      return const SizedBox.shrink();
    }
    final (label, tone) = config(status);
    return AppBadge(label, tone: tone, compact: true, icon: showDot ? null : null);
  }
}

/// Port of `components/ui/verification-status.tsx` — the offline outbox state of
/// a single record.
class VerificationStatusBadge extends StatelessWidget {
  const VerificationStatusBadge({
    super.key,
    required this.status,
    this.showLabel = true,
  });

  final String? status;
  final bool showLabel;

  static (String, AppTone, IconData) config(String? raw) =>
      switch ((raw ?? 'PENDING').toUpperCase()) {
        'VERIFIED' => ('Verified', AppTone.success, Icons.check_circle_outline),
        'SYNCING' => ('Syncing', AppTone.info, Icons.sync),
        'PENDING' => ('Pending', AppTone.warning, Icons.schedule),
        'FAILED' => ('Sync failed', AppTone.danger, Icons.error_outline),
        _ => ('Pending', AppTone.warning, Icons.schedule),
      };

  @override
  Widget build(BuildContext context) {
    final (label, tone, icon) = config(status);
    return Tooltip(
      message: '$label — main/secondary sync state',
      child: AppBadge(
        showLabel ? label : '',
        tone: tone,
        icon: icon,
        compact: true,
      ),
    );
  }
}

/// Port of `components/ui/export-button.tsx`.
class AppExportButton extends StatelessWidget {
  const AppExportButton({
    super.key,
    required this.onExport,
    this.label = 'Export',
    this.format = 'CSV',
    this.busy = false,
  });

  final VoidCallback onExport;
  final String label;
  final String format;
  final bool busy;

  @override
  Widget build(BuildContext context) => AppButton(
        label: label,
        icon: Icons.download_outlined,
        variant: AppButtonVariant.secondary,
        size: AppButtonSize.sm,
        loading: busy,
        onPressed: onExport,
      );
}
