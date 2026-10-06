import 'package:flutter/material.dart';

import '../../core/utils/formatting.dart';
import '../../state/app_services.dart';
import '../../ui/kit/feedback.dart';
import '../../ui/kit/inputs.dart';
import '../../ui/kit/primitives.dart';
import '../../ui/theme.dart';

/// Domain-local parallel to `ui/kit`: quotations-scoped widgets (the four
/// status badges, ops card family, print-slip helpers). Kept here rather than
/// merged into the kit on purpose — they encode quotations/status semantics
/// used across 20+ screens, and a kit merge risks silent regressions on those
/// surfaces without visual verification. All shared visuals (colors, radii,
/// shadows, text) are consumed from `ui/kit` + `ui/theme`, never re-invented.

/// The shared "you cannot see this" surface. Every screen in the feature gates
/// itself on one permission string, the way the web sidebar does.
Widget opsNotPermitted(String feature) => AppErrorState(
      title: 'Not permitted',
      message: 'You do not have access to $feature.',
      icon: Icons.lock_outline,
    );

bool canView(AppServices services, String permission) =>
    services.auth.hasPermission(permission);

/// The tinted square every operations card leads with, so the list reads as one
/// family instead of a mix of list tiles.
class OpsIcon extends StatelessWidget {
  const OpsIcon(this.icon,
      {super.key, this.tone = AppTone.info, this.size = 38});

  final IconData icon;
  final AppTone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (fg, bg, border) = tone.resolve(c);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Icon(icon, size: size * 0.45, color: fg),
    );
  }
}

/// The status colours the web app gives each gate pass, including the two it
/// paints neutral because they are terminal rather than successful.
class GatePassStatusBadge extends StatelessWidget {
  const GatePassStatusBadge({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) => AppBadge(
        humaniseStatus(status),
        tone: gatePassTone(status),
        compact: true,
      );
}

AppTone gatePassTone(String status) => switch (status) {
      'RECEIVED' => AppTone.info,
      'PROCESSING' => AppTone.warning,
      'READY_FOR_DELIVERY' => AppTone.info,
      'PARTIALLY_DELIVERED' => AppTone.warning,
      'DELIVERED' => AppTone.success,
      'CANCELLED' => AppTone.neutral,
      _ => AppTone.neutral,
    };

/// `RECEIVED` becomes `Received`, but the mixed-case values some endpoints
/// return should not show up as `Partially delivered`.
String humaniseStatus(String value) {
  final cleaned = value.replaceAll('_', ' ').trim().toLowerCase();
  if (cleaned.isEmpty) return value;
  return cleaned[0].toUpperCase() + cleaned.substring(1);
}

/// One metric tile in the horizontal summary strip the web app renders above
/// every operations list.
class OpsMetric {
  const OpsMetric({
    required this.id,
    required this.label,
    required this.value,
    this.icon,
    this.tone = AppTone.neutral,
    this.money = false,
  });

  final String id;
  final String label;
  final String value;
  final IconData? icon;
  final AppTone tone;
  final bool money;
}

class CompactMetrics extends StatelessWidget {
  const CompactMetrics({super.key, required this.items, this.placeholder = 4});

  final List<OpsMetric> items;
  final int placeholder;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return SizedBox(
        height: 74,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          itemCount: placeholder,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, __) => const SizedBox(
            width: 150,
            child: AppCard(child: AppSkeleton(height: 46)),
          ),
        ),
      );
    }
    return SizedBox(
      height: 74,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final m = items[i];
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
                      if (m.icon != null) ...[
                        Icon(m.icon, size: 13, color: m.tone.dot(context.c)),
                        const SizedBox(width: 5),
                      ],
                      Expanded(
                        child: Text(
                          m.label,
                          style: context.texts.labelSmall
                              ?.copyWith(color: context.c.fgMuted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      m.money ? Fmt.money(num.tryParse(m.value) ?? 0) : m.value,
                      style: context.texts.titleMedium
                          ?.copyWith(color: m.tone.dot(context.c)),
                    ),
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

/// A group of rows under one status heading — the `StatusSectionList` port.
class OpsSection<T> {
  const OpsSection({
    required this.key,
    required this.label,
    required this.items,
    this.icon,
    this.tone = AppTone.neutral,
  });

  final String key;
  final String label;
  final List<T> items;
  final IconData? icon;
  final AppTone tone;
}

class OpsSectionList<T> extends StatelessWidget {
  const OpsSectionList({
    super.key,
    required this.sections,
    required this.itemBuilder,
  });

  final List<OpsSection<T>> sections;
  final Widget Function(BuildContext, T) itemBuilder;

  @override
  Widget build(BuildContext context) {
    final visible = sections.where((s) => s.items.isNotEmpty).toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      children: [
        for (final section in visible) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
            child: Row(
              children: [
                if (section.icon != null) ...[
                  Icon(section.icon,
                      size: 13, color: section.tone.dot(context.c)),
                  const SizedBox(width: 6),
                ],
                AppFieldLabel(section.label, opaque: true),
                const SizedBox(width: 7),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: context.c.surface3,
                    borderRadius: BorderRadius.circular(Radii.pill),
                  ),
                  child: Text(
                    '${section.items.length}',
                    style: context.texts.labelSmall
                        ?.copyWith(color: context.c.fg3, fontSize: 10),
                  ),
                ),
              ],
            ),
          ),
          for (final item in section.items) ...[
            itemBuilder(context, item),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }
}

/// The hotel name is only worth a chip when the operator is looking at every
/// hotel at once; in a single-hotel scope the heading already says it.
class HotelBadge extends StatelessWidget {
  const HotelBadge({super.key, required this.name, this.showAllHotels = false});

  final String name;
  final bool showAllHotels;

  @override
  Widget build(BuildContext context) {
    if (!showAllHotels || name.trim().isEmpty) return const SizedBox.shrink();
    return AppBadge(Fmt.truncate(name, 22), tone: AppTone.info, compact: true);
  }
}

/// Open / edit / print / delete, resolved against the module's write grant.
class EntityCardActions extends StatelessWidget {
  const EntityCardActions({
    super.key,
    this.onOpen,
    this.onEdit,
    this.onDelete,
    this.onPrint,
    this.canWrite = true,
    this.openLabel = 'Open',
  });

  final VoidCallback? onOpen;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onPrint;
  final bool canWrite;
  final String openLabel;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onPrint != null)
            AppButton.icon(
              icon: Icons.print_outlined,
              tooltip: 'Print',
              size: AppButtonSize.iconSm,
              onPressed: onPrint,
            ),
          if (onOpen != null)
            AppButton(
              label: openLabel,
              size: AppButtonSize.xs,
              variant: AppButtonVariant.ghost,
              onPressed: onOpen,
            ),
          if (canWrite && onEdit != null)
            AppButton.icon(
              icon: Icons.edit_outlined,
              tooltip: 'Edit',
              size: AppButtonSize.iconSm,
              onPressed: onEdit,
            ),
          if (canWrite && onDelete != null)
            AppButton.icon(
              icon: Icons.delete_outline,
              tooltip: 'Delete',
              size: AppButtonSize.iconSm,
              variant: AppButtonVariant.dangerGhost,
              onPressed: onDelete,
            ),
        ],
      );
}

/// A money line in a running total, on screen. The print pages have their own
/// ink-on-paper equivalent in `PaperTotal`.
class OpsTotalRow extends StatelessWidget {
  const OpsTotalRow({
    super.key,
    required this.label,
    required this.value,
    this.strong = false,
    this.tone,
  });

  final String label;
  final String value;
  final bool strong;
  final AppTone? tone;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fg = tone?.dot(c) ?? (strong ? c.fg : c.fgMuted);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(
            label,
            style: strong
                ? context.texts.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w700)
                : context.texts.bodySmall?.copyWith(color: c.fgMuted),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: strong ? 15 : 13,
              fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

/// A hotel picker for the forms. The list comes from the operations the app has
/// already loaded, so the operator can never submit a name the backend has
/// never seen.
class HotelPicker extends StatelessWidget {
  const HotelPicker({
    super.key,
    required this.hotels,
    required this.value,
    required this.onChanged,
    this.label = 'Client',
    this.hint = 'Select or type a client',
    this.errorText,
  });

  final List<String> hotels;
  final String? value;
  final ValueChanged<String?> onChanged;
  final String label;
  final String hint;
  final String? errorText;

  @override
  Widget build(BuildContext context) => AppField(
        label: label,
        required: true,
        error: errorText,
        child: AppSearchableSelect<String>(
          value: value,
          hint: hint,
          errorText: errorText,
          clearable: true,
          options: [
            for (final name in hotels)
              AppSelectOption<String>(value: name, label: name),
          ],
          onChanged: onChanged,
        ),
      );
}

/// One label/value row used across the detail screens.
class OpsKeyValue extends StatelessWidget {
  const OpsKeyValue({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.mono = false,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool mono;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 132,
              child: Text(
                label,
                style:
                    context.texts.bodySmall?.copyWith(color: context.c.fgMuted),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                value,
                style: context.texts.bodyMedium?.copyWith(
                  color: valueColor ?? context.c.fg,
                  fontFamily: mono ? 'monospace' : null,
                ),
              ),
            ),
          ],
        ),
      );
}

/// A horizontal quantity stepper, gloved-hand sized.
class QtyStepper extends StatefulWidget {
  const QtyStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.allowDecimal = true,
    this.width = 92,
    this.max,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final bool allowDecimal;
  final double width;

  /// An upper bound the operator cannot step past. The delivery form uses it so
  /// a line can never be filled above what the server says is available.
  final double? max;

  @override
  State<QtyStepper> createState() => _QtyStepperState();
}

class _QtyStepperState extends State<QtyStepper> {
  late final TextEditingController _ctrl =
      TextEditingController(text: Fmt.qty(widget.value));

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(QtyStepper old) {
    super.didUpdateWidget(old);
    // The field owns its own controller, so a value that changed elsewhere —
    // "fill all", a reload, a correction applied from the server — has to be
    // pushed in rather than left showing the previous number.
    if (widget.value != old.value && !_isFocused) {
      _ctrl.text = Fmt.qty(widget.value);
    }
  }

  bool _isFocused = false;

  void _set(double next) {
    final ceiling = widget.max;
    var v = next < 0 ? 0.0 : next;
    if (ceiling != null && v > ceiling) v = ceiling;
    setState(() {
      _ctrl.text = Fmt.qty(v);
      _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
    });
    widget.onChanged(v);
  }

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppButton.icon(
            icon: Icons.remove,
            tooltip: 'Decrease',
            size: AppButtonSize.iconSm,
            variant: AppButtonVariant.secondary,
            onPressed: () => _set(widget.value - 1),
          ),
          SizedBox(
            width: widget.width,
            child: Focus(
              onFocusChange: (has) => _isFocused = has,
              child: AppNumberInput(
                controller: _ctrl,
                allowDecimal: widget.allowDecimal,
                onChanged: (raw) {
                  final parsed = double.tryParse(raw);
                  if (parsed == null) return;
                  final ceiling = widget.max;
                  var v = parsed < 0 ? 0.0 : parsed;
                  if (ceiling != null && v > ceiling) v = ceiling;
                  widget.onChanged(v);
                },
              ),
            ),
          ),
          AppButton.icon(
            icon: Icons.add,
            tooltip: 'Increase',
            size: AppButtonSize.iconSm,
            variant: AppButtonVariant.secondary,
            onPressed: () => _set(widget.value + 1),
          ),
        ],
      );
}

/// Deliveries have no fixed enum on the server, so the tone comes from the
/// words the status actually uses rather than from a lookup table.
class DeliveryStatusBadge extends StatelessWidget {
  const DeliveryStatusBadge({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) => AppBadge(
        humaniseStatus(status),
        tone: deliveryTone(status),
        compact: true,
      );
}

AppTone deliveryTone(String status) {
  final s = status.toUpperCase();
  if (s.contains('CANCEL')) return AppTone.danger;
  if (s.contains('DELIVERED') || s.contains('COMPLETE')) {
    return AppTone.success;
  }
  if (s.contains('PENDING') || s.contains('SCHEDULED')) {
    return AppTone.warning;
  }
  if (s.contains('PARTIAL')) return AppTone.warning;
  return AppTone.info;
}

class ReturnStatusBadge extends StatelessWidget {
  const ReturnStatusBadge({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) => AppBadge(
        humaniseStatus(status),
        tone: switch (status.toUpperCase()) {
          'PENDING' => AppTone.warning,
          'RECEIVED' => AppTone.info,
          'PROCESSED' => AppTone.success,
          _ => AppTone.neutral,
        },
        compact: true,
      );
}

class DispatchStatusBadge extends StatelessWidget {
  const DispatchStatusBadge({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) => AppBadge(
        humaniseStatus(status),
        tone: switch (status.toUpperCase()) {
          'SCHEDULED' => AppTone.neutral,
          'ASSIGNED' => AppTone.info,
          'EN_ROUTE' => AppTone.warning,
          'COMPLETED' => AppTone.success,
          'CANCELLED' => AppTone.danger,
          _ => AppTone.neutral,
        },
        compact: true,
      );
}

/// Display copy for the return pickers, matching the labels the web form shows
/// rather than the raw enum values.
const List<AppSelectOption<String>> returnReasonOptions = [
  AppSelectOption(value: 'WRONG_ITEM', label: 'Wrong item sent'),
  AppSelectOption(value: 'DAMAGED', label: 'Damaged / stained'),
  AppSelectOption(value: 'MISSING', label: 'Missing items'),
  AppSelectOption(value: 'OTHER', label: 'Other'),
];

const List<AppSelectOption<String>> returnConditionOptions = [
  AppSelectOption(value: 'GOOD', label: 'Good (re-usable)'),
  AppSelectOption(value: 'DAMAGED', label: 'Damaged'),
  AppSelectOption(value: 'STAINED', label: 'Stained'),
  AppSelectOption(value: 'LOST', label: 'Lost (not returned)'),
];

const List<AppSelectOption<String>> returnActionOptions = [
  AppSelectOption(value: 'RECEIVE_BACK', label: 'Receive back'),
  AppSelectOption(value: 'RE_WASH', label: 'Re-wash cycle'),
  AppSelectOption(value: 'DISCARD', label: 'Discard'),
  AppSelectOption(value: 'COMPENSATE', label: 'Compensate client'),
];

const List<AppSelectOption<String>> returnAdjustmentOptions = [
  AppSelectOption(value: 'NONE', label: 'No adjustment'),
  AppSelectOption(value: 'QUANTITY_REDUCE', label: 'Reduce bill quantity'),
  AppSelectOption(value: 'AMOUNT_REDUCE', label: 'Reduce bill amount'),
  AppSelectOption(value: 'COMPENSATE', label: 'Compensation'),
];
