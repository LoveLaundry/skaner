import 'package:flutter/material.dart';

import '../../config/api_config.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/models/linen.dart';
import '../../core/utils/formatting.dart';
import '../../state/app_scope.dart';
import '../../ui/kit/feedback.dart';
import '../../ui/kit/primitives.dart';
import '../../ui/theme.dart';

/// The linen module lives on the bills service, exactly as `billsApi` does in
/// `linen.service.ts`.
const String linenService = ServiceNames.bills;

class LinenApi {
  LinenApi._();

  static const String list = '/linens';
  static const String stats = '/linens/stats/summary';
  static const String flow = '/dashboard/linen-flow';

  static String one(String docId) => '/linens/$docId';

  static String events(String docId) => '/linens/$docId/events';

  static String scan(String docId) => '/linens/$docId/scan';

  static String byCode(String code) =>
      '/linens/by-code/${Uri.encodeComponent(code)}';
}

/// The wire values behind [linenStatusLabels] — the model decodes them but never
/// spells them out, and a status filter has to send one.
const Map<LinenStatus, String> linenStatusValues = {
  LinenStatus.inStock: 'IN_STOCK',
  LinenStatus.atClient: 'AT_CLIENT',
  LinenStatus.collected: 'COLLECTED',
  LinenStatus.atLaundry: 'AT_LAUNDRY',
  LinenStatus.washing: 'WASHING',
  LinenStatus.drying: 'DRYING',
  LinenStatus.pressing: 'PRESSING',
  LinenStatus.ready: 'READY',
  LinenStatus.delivered: 'DELIVERED',
  LinenStatus.missing: 'MISSING',
  LinenStatus.damaged: 'DAMAGED',
  LinenStatus.retired: 'RETIRED',
};

/// `LINEN_STATUS_CONFIG` in `types/linen.ts` translated to the app's tones.
/// The purple and cyan of the web palette have no kit equivalent, so
/// `collected`/`pressing` fall back to the brand and info slots.
AppTone linenStatusTone(LinenStatus status) => switch (status) {
      LinenStatus.inStock ||
      LinenStatus.ready ||
      LinenStatus.delivered =>
        AppTone.success,
      LinenStatus.atClient || LinenStatus.washing => AppTone.info,
      LinenStatus.collected || LinenStatus.pressing => AppTone.brand,
      LinenStatus.atLaundry || LinenStatus.drying => AppTone.warning,
      LinenStatus.missing || LinenStatus.damaged => AppTone.danger,
      LinenStatus.retired => AppTone.neutral,
    };

IconData linenStatusIcon(LinenStatus status) => switch (status) {
      LinenStatus.inStock => Icons.inventory_2_outlined,
      LinenStatus.atClient => Icons.business_outlined,
      LinenStatus.collected => Icons.local_shipping_outlined,
      LinenStatus.atLaundry => Icons.storefront_outlined,
      LinenStatus.washing => Icons.local_laundry_service_outlined,
      LinenStatus.drying => Icons.dry_cleaning_outlined,
      LinenStatus.pressing => Icons.iron_outlined,
      LinenStatus.ready => Icons.task_alt_outlined,
      LinenStatus.delivered => Icons.done_all_outlined,
      LinenStatus.missing => Icons.help_outline,
      LinenStatus.damaged => Icons.report_gmailerrorred_outlined,
      LinenStatus.retired => Icons.archive_outlined,
    };

class LinenStatusBadge extends StatelessWidget {
  const LinenStatusBadge(
      {super.key, required this.status, this.compact = true});

  final LinenStatus status;
  final bool compact;

  @override
  Widget build(BuildContext context) => AppBadge(
        linenStatusLabels[status] ?? 'In Stock',
        tone: linenStatusTone(status),
        icon: linenStatusIcon(status),
        compact: compact,
      );
}

/// Terminal and problem states get pulled out of the flow, as the web app's
/// attention tiles do.
class LinenMetrics extends StatelessWidget {
  const LinenMetrics({super.key, required this.stats, this.compact = true});

  final LinenStats stats;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.texts;
    final tiles = <(String, String, IconData, Color)>[
      (
        'Total pieces',
        Fmt.count(stats.total),
        Icons.inventory_2_outlined,
        c.info
      ),
      (
        'In flow',
        Fmt.count(stats.inFlow),
        Icons.local_shipping_outlined,
        c.brand
      ),
      (
        'At laundry',
        Fmt.count(stats.atLaundry + stats.washing),
        Icons.local_laundry_service_outlined,
        c.warning
      ),
      ('Ready', Fmt.count(stats.ready), Icons.task_alt_outlined, c.success),
      (
        'Needs attention',
        Fmt.count(stats.needsAttention),
        Icons.report_gmailerrorred_outlined,
        stats.needsAttention > 0 ? c.danger : c.fg3
      ),
    ];
    return SizedBox(
      height: compact ? 74 : 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        itemCount: tiles.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final (label, value, icon, color) = tiles[i];
          return SizedBox(
            width: 150,
            child: AppCard(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 13, color: color),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(label,
                            style: t.labelSmall?.copyWith(color: c.fgMuted),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(value,
                        style: t.titleMedium?.copyWith(color: color)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

final RegExp _codeParam = RegExp(
  r'[?&#](?:code|linen_id|linen|tag|id)=([^&#\s]+)',
  caseSensitive: false,
);
final RegExp _llToken = RegExp(r'\bLL-[A-Za-z0-9][A-Za-z0-9._-]*');
final RegExp _codeShape = RegExp(r'^[A-Z0-9][A-Z0-9._-]{1,63}$');
final RegExp _wrappers = RegExp(r'''^[\s"'`<([{]+|[\s"'`>)\]}]+$''');

/// Turns whatever a printed tag carries into the identifier
/// `/linens/by-code/{code}` expects, or `null` when the text is not a code.
///
/// `linen-tag-generator.tsx` prints the bare `linen_id` (`LL-7K4P92`) and
/// `linen-scanner.tsx` only trims and upper-cases what jsQR decodes, so a bare
/// code is the canonical shape. Two others show up in the field as well — a
/// deep link (`/scan?code=…`, or the code as a path segment) and a label read
/// only in part — and a partly-read tag must not stop the operator, so those
/// are extracted rather than rejected.
String? parseLinenCode(String? raw) {
  var s = (raw ?? '').replaceAll(_wrappers, '').trim();
  if (s.isEmpty) return null;

  final param = _codeParam.firstMatch(s);
  if (param != null) {
    s = _percentDecode(param.group(1)!);
  } else if (s.contains('://') || s.toLowerCase().startsWith('www.')) {
    final segments =
        s.split(RegExp(r'[/?#]')).where((p) => p.isNotEmpty).toList();
    if (segments.isNotEmpty) s = _percentDecode(segments.last);
  }

  s = s.replaceAll(_wrappers, '').trim().toUpperCase();
  if (_codeShape.hasMatch(s)) return s;

  final embedded = _llToken.firstMatch(s);
  if (embedded != null) {
    final candidate = embedded.group(0)!.toUpperCase();
    if (_codeShape.hasMatch(candidate)) return candidate;
  }
  return null;
}

String _percentDecode(String value) {
  try {
    return Uri.decodeQueryComponent(value);
  } on FormatException {
    return value;
  }
}

/// Posts one scan event. Shared by the tracking detail and the scanner so both
/// post the same payload and report the same outcomes.
Future<bool> postLinenScan(
  BuildContext context,
  String docId,
  LinenScanAction action, {
  String? location,
  String? notes,
}) async {
  final api = AppScope.read(context).api;
  try {
    final result = await api.post(
      linenService,
      LinenApi.scan(docId),
      body: {
        'action': action.value,
        if (location != null && location.isNotEmpty) 'location': location,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      },
    );
    if (context.mounted) {
      if (result is QueuedResponse) {
        AppToast.info(context, 'Offline — action queued and will sync');
      } else {
        AppToast.success(context, '${action.label} recorded');
      }
    }
    return true;
  } on ApiException catch (e) {
    if (context.mounted) AppToast.error(context, e.message);
    return false;
  }
}

/// The `Quick Actions` grid: every entry in `SCAN_ACTIONS`, laid out two per
/// row so a gloved hand still finds the control.
class LinenQuickActions extends StatelessWidget {
  const LinenQuickActions({
    super.key,
    required this.actions,
    required this.onAction,
    this.pendingValue,
  });

  final List<LinenScanAction> actions;
  final ValueChanged<LinenScanAction> onAction;
  final String? pendingValue;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel('Quick actions'),
          LayoutBuilder(
            builder: (context, box) {
              final width = (box.maxWidth - 8) / 2;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final a in actions)
                    SizedBox(
                      width: width,
                      child: AppButton(
                        label: a.label,
                        size: AppButtonSize.sm,
                        variant: AppButtonVariant.outline,
                        icon: linenStatusIcon(a.targetStatus),
                        loading: pendingValue == a.value,
                        onPressed:
                            pendingValue == null ? () => onAction(a) : null,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          text.toUpperCase(),
          style: context.texts.labelSmall?.copyWith(
            color: context.c.fgMuted,
            fontSize: 10.5,
            letterSpacing: 0.6,
          ),
        ),
      );
}

/// Field blocks on the detail screens read better as a two-column grid on a
/// tablet than as a stack of full-width rows on a phone.
class LinenDetailGrid extends StatelessWidget {
  const LinenDetailGrid({super.key, required this.entries});

  final List<(String, String)> entries;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.texts;
    final visible = entries.where((e) => e.$2.trim().isNotEmpty).toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, box) {
        final columns = box.maxWidth > 520 ? 3 : 2;
        return Wrap(
          spacing: 14,
          runSpacing: 12,
          children: [
            for (final (label, value) in visible)
              SizedBox(
                width: (box.maxWidth - 14 * (columns - 1)) / columns,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label.toUpperCase(),
                      style: t.labelSmall
                          ?.copyWith(color: c.fgFaint, fontSize: 10.5),
                    ),
                    const SizedBox(height: 2),
                    Text(value, style: t.bodyMedium?.copyWith(color: c.fg)),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The movement history timeline from `linen-profile.tsx`, oldest last.
class LinenTimeline extends StatelessWidget {
  const LinenTimeline({super.key, required this.events});

  final List<LinenEvent> events;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return Text('No history yet',
          style: context.texts.bodySmall?.copyWith(color: context.c.fgMuted));
    }
    final c = context.c;
    final t = context.texts;
    return Column(
      children: [
        for (var i = 0; i < events.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Container(
                      width: 13,
                      height: 13,
                      margin: const EdgeInsets.only(top: 3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == 0
                            ? linenStatusTone(
                                    linenStatusFrom(events[i].toStatus))
                                .dot(c)
                            : Colors.transparent,
                        border: Border.all(
                          color: linenStatusTone(
                                  linenStatusFrom(events[i].toStatus))
                              .dot(c),
                          width: 2,
                        ),
                      ),
                    ),
                    if (i < events.length - 1)
                      Expanded(
                        child: Container(width: 1, color: c.line),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding:
                        EdgeInsets.only(bottom: i < events.length - 1 ? 16 : 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (events[i].fromStatus != null)
                              Text(
                                events[i].fromLabel,
                                style: t.bodySmall?.copyWith(color: c.fgMuted),
                              ),
                            LinenStatusBadge(
                                status: linenStatusFrom(events[i].toStatus)),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          [
                            Fmt.dateTime(events[i].timestamp),
                            if (events[i].user != null) events[i].user!,
                            if (events[i].location != null) events[i].location!,
                          ].join(' · '),
                          style: t.bodySmall
                              ?.copyWith(color: c.fgMuted, fontSize: 11.5),
                        ),
                        if (events[i].notes != null &&
                            events[i].notes!.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              events[i].notes!,
                              style: t.bodySmall?.copyWith(
                                  color: c.fg2, fontStyle: FontStyle.italic),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
