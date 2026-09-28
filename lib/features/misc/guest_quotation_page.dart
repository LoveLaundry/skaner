import 'package:flutter/material.dart';

import '../../../config/api_config.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/utils/formatting.dart';
import '../../../data/resource_controller.dart';
import '../../../state/app_scope.dart';
import '../../../ui/brand/logo.dart';
import '../../../ui/kit/feedback.dart';
import '../../../ui/kit/inputs.dart';
import '../../../ui/kit/primitives.dart';
import '../../../ui/shell/app_shell.dart';
import '../../../ui/theme.dart';

/// Public order lookup by quotation reference.
///
/// `GET /quotations/{id}/tracking` is unauthenticated and returns status plus
/// history with no PII, which is exactly what a customer holding a reference
/// number needs. Guests who hold a garment tag rather than a reference should use
/// the tag screen, so the two are linked rather than merged.
class GuestQuotationPage extends StatefulWidget {
  const GuestQuotationPage({super.key, this.initialReference});

  final String? initialReference;

  @override
  State<GuestQuotationPage> createState() => _GuestQuotationPageState();
}

class _GuestQuotationPageState extends State<GuestQuotationPage> {
  late final TextEditingController _reference = TextEditingController(
    text: widget.initialReference ?? '',
  );

  Map<String, dynamic>? _order;
  String? _message;
  bool _notFound = false;
  bool _busy = false;

  @override
  void dispose() {
    _reference.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    final raw = _reference.text.trim();
    if (raw.isEmpty) {
      setState(() => _message = 'Enter the reference on your quotation.');
      return;
    }
    final id = raw.split('?').first.split('/').where((s) => s.isNotEmpty).last;
    setState(() {
      _busy = true;
      _message = null;
      _notFound = false;
    });
    try {
      final data = await AppScope.read(context).api.get(
        ServiceNames.quotation,
        '/quotations/$id/tracking',
        includeAuth: false,
      );
      if (!mounted) return;
      setState(() {
        _order = data is Map<String, dynamic> ? data : null;
        if (_order == null) _message = 'That reference returned no order.';
        _busy = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (e.isNotFound) {
          _notFound = true;
        } else {
          _message = e.message;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = 'Could not reach the service. Check your connection and retry.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.texts;
    final history = asRows(_order?['status_history']);
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
                  AppButton.icon(
                    icon: Icons.local_offer_outlined,
                    tooltip: 'Price list',
                    onPressed: () => AppNavigatorPush.push(context, '/guest/shop'),
                  ),
                ],
              ),
            ),
            Container(height: 1, color: c.line),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
                children: [
                  Text('Track a quotation', style: t.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    'Enter the reference number printed on your quotation to see '
                    'its current status.',
                    style: t.bodySmall?.copyWith(color: c.fgMuted),
                  ),
                  const SizedBox(height: 14),
                  AppTextInput(
                    controller: _reference,
                    label: 'Quotation reference',
                    hint: 'e.g. 1042',
                    icon: Icons.numbers_rounded,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.search,
                    enabled: !_busy,
                    errorText: _message,
                    onSubmitted: (_) => _lookup(),
                  ),
                  const SizedBox(height: 12),
                  AppButton(
                    label: 'Check status',
                    icon: Icons.search_rounded,
                    variant: AppButtonVariant.primary,
                    block: true,
                    loading: _busy,
                    onPressed: _lookup,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.qr_code_2_rounded, size: 15, color: c.fgFaint),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Have a garment tag code instead?',
                          style: t.labelSmall?.copyWith(color: c.fgFaint),
                        ),
                      ),
                      AppButton(
                        label: 'Track a tag',
                        variant: AppButtonVariant.ghost,
                        size: AppButtonSize.sm,
                        onPressed: () =>
                            AppNavigatorPush.push(context, '/guest/track'),
                      ),
                    ],
                  ),
                  if (_notFound) ...[
                    const SizedBox(height: 14),
                    const AppNotice(
                      tone: AppTone.warning,
                      title: 'No such quotation',
                      message:
                          'We could not find that reference. Double-check the number '
                          'on your quotation, or call us and we will look it up.',
                    ),
                  ],
                  if (_busy) ...[
                    const SizedBox(height: 18),
                    const AppSkeletonList(count: 1, lines: 3),
                  ],
                  if (_order != null) ...[
                    const SizedBox(height: 18),
                    AppCard(
                      accent: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  str(_order!, ['quotation_title'], 'Order'),
                                  style: t.titleSmall,
                                ),
                              ),
                              AppBadge(
                                _label(str(_order!, ['status'])),
                                tone: _tone(str(_order!, ['status'])),
                                compact: true,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              _meta('Reference',
                                  str(_order!, ['id'], '—').toString()),
                              _meta('Placed', Fmt.date(_order!['created_at'])),
                              _meta('Updated', Fmt.date(_order!['updated_at'])),
                            ],
                          ),
                          const Divider(height: 24),
                          Text('History', style: t.labelLarge),
                          const SizedBox(height: 10),
                          if (history.isEmpty)
                            Text(
                              'No status changes recorded yet.',
                              style: t.bodySmall?.copyWith(color: c.fgMuted),
                            )
                          else
                            for (var i = 0; i < history.length; i++)
                              _step(history[i], last: i == history.length - 1),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _meta(String label, String value) {
    final c = context.c;
    final t = context.texts;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: t.labelSmall?.copyWith(color: c.fgFaint)),
          const SizedBox(height: 2),
          Text(value, style: t.bodySmall?.copyWith(color: c.fg2)),
        ],
      ),
    );
  }

  Widget _step(Map<String, dynamic> entry, {required bool last}) {
    final c = context.c;
    final t = context.texts;
    final status = str(entry, ['status']);
    final note = str(entry, ['note']);
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Icon(
              last ? Icons.flag_rounded : Icons.check_circle_rounded,
              size: 15,
              color: last ? _tone(status).dot(c) : c.fgFaint,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _label(status),
                        style: t.bodySmall?.copyWith(
                          color: c.fg,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      Fmt.dateTime(entry['changed_at']),
                      style: t.labelSmall?.copyWith(color: c.fgFaint),
                    ),
                  ],
                ),
                if (note.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      note,
                      style: t.labelSmall?.copyWith(color: c.fgMuted),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static AppTone _tone(String raw) => switch (raw.toLowerCase()) {
        'sent' => AppTone.info,
        'accepted' => AppTone.brand,
        'in_progress' || 'processing' => AppTone.warning,
        'ready' || 'ready_for_delivery' => AppTone.success,
        'delivered' || 'completed' => AppTone.success,
        'rejected' || 'cancelled' => AppTone.danger,
        _ => AppTone.neutral,
      };

  static String _label(String raw) => switch (raw.toLowerCase()) {
        'draft' => 'Received',
        'sent' => 'Sent for approval',
        'accepted' => 'Approved',
        'in_progress' || 'processing' => 'Being processed',
        'ready' || 'ready_for_delivery' => 'Ready for collection',
        'delivered' || 'completed' => 'Completed',
        'rejected' => 'Declined',
        'cancelled' || 'canceled' => 'Cancelled',
        _ => raw.replaceAll('_', ' '),
      };
}
