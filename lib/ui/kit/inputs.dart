import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'primitives.dart';

/// A stat/field caption: uppercase, letter-spaced, muted.
///
/// Replaces the hand-rolled `labelSmall.copyWith(color, fontSize: 10,
/// letterSpacing: 0.6)` that three screens duplicated. Defaults read as the
/// smallest caption on a card; pass [color] to override (e.g. an accent).
class AppFieldLabel extends StatelessWidget {
  const AppFieldLabel(this.label, {super.key, this.color, this.opaque = false});

  final String label;
  final Color? color;
  final bool opaque;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.texts;
    final base = t.labelSmall?.copyWith(
      color: color ?? (opaque ? c.fgMuted : c.fgFaint),
      fontSize: context.fs(10),
      letterSpacing: 0.6,
    );
    return Text(
      label.toUpperCase(),
      style: base,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Port of `components/ui/field.tsx`: label, control, hint, error.
/// The hint is replaced by the error so the block never grows when validation
/// fires.
class AppField extends StatelessWidget {
  const AppField({
    super.key,
    required this.label,
    required this.child,
    this.hint,
    this.error,
    this.required = false,
    this.trailing,
    this.optional = false,
  });

  final String label;
  final Widget child;
  final String? hint;
  final String? error;
  final bool required;
  final Widget? trailing;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.texts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                label,
                style: t.labelMedium?.copyWith(color: c.fg2),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (required)
              Padding(
                padding: const EdgeInsets.only(left: 3),
                child: Text('*', style: t.labelMedium?.copyWith(color: c.danger)),
              ),
            if (optional)
              Padding(
                padding: const EdgeInsets.only(left: 5),
                child: Text('optional',
                    style: t.labelSmall?.copyWith(color: c.fgFaint)),
              ),
            const Spacer(),
            if (trailing != null) trailing!,
          ],
        ),
        const SizedBox(height: 6),
        child,
        if (error != null) ...[
          const SizedBox(height: 5),
          Row(
            children: [
              Icon(Icons.error_outline, size: 13, color: c.danger),
              const SizedBox(width: 4),
              Expanded(
                child: Text(error!,
                    style: t.bodySmall?.copyWith(color: c.danger, fontSize: context.fs(11.5))),
              ),
            ],
          ),
        ] else if (hint != null) ...[
          const SizedBox(height: 5),
          Text(hint!,
              style: t.bodySmall?.copyWith(color: c.fgFaint, fontSize: context.fs(11.5))),
        ],
      ],
    );
  }
}

/// Text input with the app's border/soft-fill contract.
/// Accepts either an external [controller] or a one-shot [initialValue].
class AppTextInput extends StatefulWidget {
  const AppTextInput({
    super.key,
    this.controller,
    this.initialValue,
    this.hint,
    this.label,
    this.icon,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.enabled = true,
    this.onChanged,
    this.onSubmitted,
    this.inputFormatters,
    this.autofocus = false,
    this.suffix,
    this.onTap,
    this.filled,
    this.errorText,
    this.textAlign = TextAlign.start,
    this.mono = false,
    this.obscureText = false,
    this.autofillHints,
  }) : assert(controller == null || initialValue == null,
            'Provide either a controller or an initialValue, not both.');

  final TextEditingController? controller;
  final String? initialValue;
  final String? hint;
  final String? label;
  final IconData? icon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final int maxLines;
  final int? minLines;
  final int? maxLength;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final List<TextInputFormatter>? inputFormatters;
  final bool autofocus;
  final Widget? suffix;
  final VoidCallback? onTap;
  final bool? filled;
  final String? errorText;
  final TextAlign textAlign;
  final bool mono;
  final bool obscureText;
  final Iterable<String>? autofillHints;

  @override
  State<AppTextInput> createState() => _AppTextInputState();
}

class _AppTextInputState extends State<AppTextInput> {
  late final TextEditingController _owned = TextEditingController();
  TextEditingController get _c => widget.controller ?? _owned;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null && widget.initialValue != null) {
      _owned.text = widget.initialValue!;
    }
  }

  @override
  void didUpdateWidget(AppTextInput old) {
    super.didUpdateWidget(old);
    if (widget.controller == null &&
        widget.initialValue != null &&
        widget.initialValue != old.initialValue) {
      _owned.text = widget.initialValue!;
    }
  }

  @override
  void dispose() {
    _owned.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return TextField(
      controller: _c,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      enabled: widget.enabled,
      onTap: widget.onTap,
      autofocus: widget.autofocus,
      maxLines: widget.maxLines,
      minLines: widget.minLines,
      maxLength: widget.maxLength,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      textCapitalization: widget.textCapitalization,
      inputFormatters: widget.inputFormatters,
      textAlign: widget.textAlign,
      obscureText: widget.obscureText,
      autocorrect: !widget.obscureText,
      enableSuggestions: !widget.obscureText,
      autofillHints: widget.autofillHints,
      style: context.texts.bodyMedium?.copyWith(
        color: c.fg,
        fontFamily: widget.mono ? 'monospace' : null,
      ),
      decoration: InputDecoration(
        hintText: widget.hint,
        labelText: widget.label,
        prefixIcon: widget.icon == null ? null : Icon(widget.icon, size: 17),
        suffixIcon: widget.suffix,
        errorText: widget.errorText,
        filled: widget.filled,
        counterText: '',
      ),
    );
  }
}

/// Numeric field: digits only, no decimal point, integer semantics.
class AppNumberInput extends StatelessWidget {
  const AppNumberInput({
    super.key,
    required this.controller,
    this.hint,
    this.label,
    this.icon,
    this.allowDecimal = false,
    this.suffix,
    this.onChanged,
    this.enabled = true,
    this.errorText,
    this.readOnly = false,
    this.onTap,
  });

  final TextEditingController controller;
  final String? hint;
  final String? label;
  final IconData? icon;
  final bool allowDecimal;
  final String? suffix;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final String? errorText;
  final bool readOnly;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return TextField(
      controller: controller,
      onChanged: onChanged,
      enabled: enabled,
      readOnly: readOnly,
      onTap: onTap,
      keyboardType: TextInputType.numberWithOptions(decimal: allowDecimal),
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          allowDecimal ? RegExp(r'[0-9.]') : RegExp(r'[0-9]'),
        ),
      ],
      style: context.texts.bodyMedium?.copyWith(color: c.fg),
      decoration: InputDecoration(
        hintText: hint,
        labelText: label,
        prefixIcon: icon == null ? null : Icon(icon, size: 17),
        suffixText: suffix,
        errorText: errorText,
        fillColor: readOnly ? c.surface3 : null,
      ),
    );
  }
}

/// A money field: digits + separators allowed, formatted on change.
class AppMoneyInput extends StatelessWidget {
  const AppMoneyInput({
    super.key,
    required this.controller,
    this.hint,
    this.label,
    this.currency = 'LKR',
    this.onChanged,
    this.enabled = true,
    this.errorText,
    this.readOnly = false,
  });

  final TextEditingController controller;
  final String? hint;
  final String? label;
  final String currency;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final String? errorText;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return TextField(
      controller: controller,
      enabled: enabled,
      readOnly: readOnly,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
      ],
      style: context.texts.bodyMedium?.copyWith(color: c.fg),
      decoration: InputDecoration(
        hintText: hint,
        labelText: label,
        prefixText: '$currency ',
        prefixStyle: context.texts.bodySmall?.copyWith(color: c.fgFaint),
        errorText: errorText,
        fillColor: readOnly ? c.surface3 : null,
      ),
    );
  }
}

/// Port of `components/ui/searchable-select.tsx`.
class AppSelectOption<T> {
  const AppSelectOption({
    required this.value,
    required this.label,
    this.subtitle,
    this.leading,
    this.tone,
  });

  final T value;
  final String label;
  final String? subtitle;
  final Widget? leading;
  final AppTone? tone;
}

/// Searchable single-select presented as a bottom sheet on mobile.
class AppSearchableSelect<T> extends StatelessWidget {
  const AppSearchableSelect({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.label,
    this.hint = 'Select…',
    this.searchable = true,
    this.enabled = true,
    this.errorText,
    this.clearable = false,
    this.itemBuilder,
  });

  final T? value;
  final List<AppSelectOption<T>> options;
  final ValueChanged<T?> onChanged;
  final String? label;
  final String? hint;
  final bool searchable;
  final bool enabled;
  final String? errorText;
  final bool clearable;
  final Widget Function(BuildContext, AppSelectOption<T>)? itemBuilder;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.texts;
    AppSelectOption<T>? selected;
    for (final o in options) {
      if (o.value == value) {
        selected = o;
        break;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(label!, style: t.labelMedium?.copyWith(color: c.fg2)),
          const SizedBox(height: 6),
        ],
        InkWell(
          borderRadius: BorderRadius.circular(Radii.md),
          onTap: enabled
              ? () async {
                  final picked = await _pick(context);
                  if (picked != null || clearable) onChanged(picked);
                }
              : null,
          child: InputDecorator(
            decoration: InputDecoration(
              errorText: errorText,
              fillColor: enabled ? null : c.surface3,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              suffixIcon: Icon(
                Icons.expand_more,
                size: 18,
                color: c.fgFaint,
              ),
            ),
            child: Row(
              children: [
                if (selected?.leading != null) ...[
                  selected!.leading!,
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    selected?.label ?? hint ?? '',
                    style: selected == null
                        ? t.bodyMedium?.copyWith(color: c.fgPlaceholder)
                        : t.bodyMedium?.copyWith(color: c.fg),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (clearable && selected != null)
                  GestureDetector(
                    onTap: () => onChanged(null),
                    child: Icon(Icons.close, size: 15, color: c.fgFaint),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<T?> _pick(BuildContext context) => showModalBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _SelectSheet<T>(
          title: label ?? hint ?? '',
          options: options,
          searchable: searchable,
          itemBuilder: itemBuilder,
        ),
      );
}

class _SelectSheet<T> extends StatefulWidget {
  const _SelectSheet({
    required this.title,
    required this.options,
    required this.searchable,
    this.itemBuilder,
  });

  final String title;
  final List<AppSelectOption<T>> options;
  final bool searchable;
  final Widget Function(BuildContext, AppSelectOption<T>)? itemBuilder;

  @override
  State<_SelectSheet<T>> createState() => _SelectSheetState<T>();
}

class _SelectSheetState<T> extends State<_SelectSheet<T>> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.texts;
    final q = _q.text.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.options
        : widget.options
            .where((o) =>
                o.label.toLowerCase().contains(q) ||
                (o.subtitle ?? '').toLowerCase().contains(q))
            .toList();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title, style: t.titleSmall),
                    if (widget.searchable) ...[
                      const SizedBox(height: 10),
                      AppTextInput(
                        controller: _q,
                        hint: 'Search…',
                        icon: Icons.search,
                        autofocus: true,
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                  ],
                ),
              ),
              Divider(color: c.line, height: 1),
              Expanded(
                child: filtered.isEmpty
                    ? const AppEmptySelect()
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final o = filtered[i];
                          final custom = widget.itemBuilder?.call(context, o);
                          if (custom != null) return custom;
                          return ListTile(
                            leading: o.leading,
                            title: Text(o.label),
                            subtitle:
                                o.subtitle == null ? null : Text(o.subtitle!),
                            onTap: () => Navigator.of(context).pop(o.value),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AppEmptySelect extends StatelessWidget {
  const AppEmptySelect({super.key});

  @override
  Widget build(BuildContext context) => Center(
        child: Text('No matches',
            style: context.texts.bodySmall?.copyWith(color: context.c.fgFaint)),
      );
}

/// Date field using the platform picker, formatted `dd MMM yyyy`.
class AppDateField extends StatelessWidget {
  const AppDateField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.hint = 'Select date',
    this.firstDate,
    this.lastDate,
    this.enabled = true,
    this.errorText,
    this.clearable = true,
  });

  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final String? label;
  final String hint;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final bool enabled;
  final String? errorText;
  final bool clearable;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(label!, style: context.texts.labelMedium?.copyWith(color: c.fg2)),
          const SizedBox(height: 6),
        ],
        InkWell(
          borderRadius: BorderRadius.circular(Radii.md),
          onTap: enabled
              ? () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: value ?? DateTime.now(),
                    firstDate: firstDate ?? DateTime(2000),
                    lastDate: lastDate ?? DateTime(DateTime.now().year + 5),
                  );
                  if (picked != null) onChanged(picked);
                }
              : null,
          child: InputDecorator(
            decoration: InputDecoration(
              errorText: errorText,
              fillColor: enabled ? null : c.surface3,
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (clearable && value != null)
                    IconButton(
                      icon: const Icon(Icons.close, size: 15),
                      onPressed: () => onChanged(null),
                      visualDensity: VisualDensity.compact,
                      color: c.fgFaint,
                    ),
                  Icon(Icons.calendar_today_outlined,
                      size: 16, color: c.fgFaint),
                  const SizedBox(width: 10),
                ],
              ),
            ),
            child: Text(
              value == null ? hint : formatDate(value!),
              style: value == null
                  ? context.texts.bodyMedium?.copyWith(color: c.fgPlaceholder)
                  : context.texts.bodyMedium?.copyWith(color: c.fg),
            ),
          ),
        ),
      ],
    );
  }
}

String formatDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')} ${_months[d.month - 1]} ${d.year}';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Date + time field for delivery slots and log timestamps.
class AppDateTimeField extends StatelessWidget {
  const AppDateTimeField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.errorText,
  });

  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final String? label;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.texts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(label!, style: t.labelMedium?.copyWith(color: c.fg2)),
          const SizedBox(height: 6),
        ],
        Row(
          children: [
            Expanded(
              flex: 3,
              child: AppDateField(
                value: value,
                errorText: errorText,
                onChanged: (d) => onChanged(
                    d == null ? null : DateTime(d.year, d.month, d.day, 12)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: _TimeField(
                value: value,
                onChanged: (h, m) {
                  final base = value ?? DateTime.now();
                  onChanged(DateTime(base.year, base.month, base.day, h, m));
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField({required this.value, required this.onChanged});

  final DateTime? value;
  final void Function(int hour, int minute) onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final h = value?.hour ?? 12;
    final m = value?.minute ?? 0;
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.md),
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: TimeOfDay(hour: h, minute: m),
        );
        if (picked != null) onChanged(picked.hour, picked.minute);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          suffixIcon: Icon(Icons.schedule,
              size: 15, color: c.fgFaint),
        ),
        child: Text(
          '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}',
          style: context.texts.bodyMedium?.copyWith(color: c.fg),
        ),
      ),
    );
  }
}

/// Port of `components/ui/signature-upload-dialog.tsx` — a drawing surface
/// persisted as a PNG data string.
class AppSignaturePad extends StatefulWidget {
  const AppSignaturePad({
    super.key,
    this.initialData,
    this.onChanged,
    this.height = 180,
  });

  final String? initialData;
  final ValueChanged<String?>? onChanged;
  final double height;

  @override
  State<AppSignaturePad> createState() => _AppSignaturePadState();
}

class _AppSignaturePadState extends State<AppSignaturePad> {
  final List<List<Offset>> _strokes = [];
  List<Offset>? _current;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        SizedBox(
          height: widget.height,
          width: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(Radii.md),
              border: Border.all(color: c.line2),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Radii.md),
              child: CustomPaint(
                painter: _SignaturePainter(
                  strokes: _strokes,
                  current: _current,
                  color: c.fg,
                ),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (d) => setState(() => _current = [d.localPosition]),
                  onPanUpdate: (d) => setState(() {
                    _current?.add(d.localPosition);
                  }),
                  onPanEnd: (_) {
                    if (_current != null && _current!.length > 1) {
                      _strokes.add(_current!);
                    }
                    setState(() => _current = null);
                    _emit();
                  },
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppButton(
              label: 'Clear',
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.sm,
              onPressed: _strokes.isEmpty
                  ? null
                  : () {
                      setState(_strokes.clear);
                      _emit();
                    },
            ),
            const SizedBox(width: 6),
            AppButton(
              label: 'Save signature',
              size: AppButtonSize.sm,
              variant: AppButtonVariant.primary,
              icon: Icons.draw_outlined,
              onPressed: _strokes.isEmpty ? null : () => _emit(),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _emit() async {
    if (widget.onChanged == null) return;
    widget.onChanged!(_strokes.isEmpty ? null : await _renderPng());
  }

  Future<String> _renderPng() async {
    const scale = 2.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(scale);
    final paint = Paint()
      ..color = const Color(0xFF0F172A)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final s in _strokes) {
      final path = Path()..moveTo(s.first.dx, s.first.dy);
      for (final p in s.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
    final image = await recorder.endRecording().toImage(
      (360 * scale).round(),
      (180 * scale).round(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return 'data:image/png;base64,${base64Encode(bytes!.buffer.asUint8List())}';
  }
}

class _SignaturePainter extends CustomPainter {
  _SignaturePainter({
    required this.strokes,
    required this.current,
    required this.color,
  });

  final List<List<Offset>> strokes;
  final List<Offset>? current;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    void draw(List<Offset> s) {
      if (s.length < 2) return;
      final path = Path()..moveTo(s.first.dx, s.first.dy);
      for (final p in s.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }

    for (final s in strokes) {
      draw(s);
    }
    if (current != null) draw(current!);
  }

  @override
  bool shouldRepaint(_SignaturePainter old) => true;
}
