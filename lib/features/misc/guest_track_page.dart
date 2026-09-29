import 'package:flutter/material.dart';

import '../../../config/api_config.dart';
import '../../../config/app_config.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/utils/formatting.dart';
import '../../../data/resource_controller.dart';
import '../../../state/app_scope.dart';
import '../../../ui/brand/logo.dart';
import '../../../ui/kit/feedback.dart';
import '../../../ui/kit/inputs.dart';
import '../../../ui/kit/primitives.dart';
import '../../../ui/theme.dart';
import 'guest_tag.dart';

/// Public garment-tag tracking.
///
/// Backed by `GET /tags/{code}`, which the service exposes without a session and
/// deliberately narrows to a first name — there is nothing here a signed-in
/// scope could unlock, and nothing to sign into. [initialCode] lets a deep link
/// from a printed QR tag open the screen already filled in.
class GuestTrackPage extends StatefulWidget {
  const GuestTrackPage({super.key, this.initialCode});

  final String? initialCode;

  @override
  State<GuestTrackPage> createState() => _GuestTrackPageState();
}

class _GuestTrackPageState extends State<GuestTrackPage> {
  late final TextEditingController _code = TextEditingController(
    text: widget.initialCode ?? '',
  );

  Map<String, dynamic>? _tag;
  String? _error;
  String? _notFound;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _track() async {
    final code = _code.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Enter the code printed on your garment tag.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _notFound = null;
    });
    try {
      // A scanned tag arrives as a full URL, so accept the last path segment.
      final slug = code.split('?').first.split('/').where((s) => s.isNotEmpty).last;
      final data = await AppScope.read(context).api.get(
        ServiceNames.quotation,
        '${GuestRoute.trackTag}$slug',
        includeAuth: false,
      );
      if (!mounted) return;
      setState(() {
        _tag = data is Map<String, dynamic> ? data : null;
        if (_tag == null) _error = 'That tag returned no details.';
        _busy = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (e.isNotFound) {
          _notFound = 'We could not find that tag. Check the code and try again.';
        } else {
          _error = e.message;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not reach the service. Check your connection and retry.';
      });
    }
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
                  AppBadge(
                    'No sign-in needed',
                    icon: Icons.lock_open_rounded,
                    tone: AppTone.neutral,
                    compact: true,
                  ),
                ],
              ),
            ),
            Container(height: 1, color: c.line),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
                children: [
                  Text('Track your order', style: t.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    'Enter the code printed on your garment tag to see where your '
                    'order is in the process.',
                    style: t.bodySmall?.copyWith(color: c.fgMuted),
                  ),
                  const SizedBox(height: 14),
                  AppTextInput(
                    controller: _code,
                    label: 'Tag code',
                    hint: 'e.g. LL-000123',
                    icon: Icons.qr_code_2_rounded,
                    mono: true,
                    textCapitalization: TextCapitalization.characters,
                    textInputAction: TextInputAction.search,
                    enabled: !_busy,
                    errorText: _error,
                    onSubmitted: (_) => _track(),
                  ),
                  const SizedBox(height: 12),
                  AppButton(
                    label: 'Track order',
                    icon: Icons.search_rounded,
                    variant: AppButtonVariant.primary,
                    block: true,
                    loading: _busy,
                    onPressed: _track,
                  ),
                  if (_notFound != null) ...[
                    const SizedBox(height: 14),
                    AppNotice(
                      tone: AppTone.warning,
                      title: 'Tag not found',
                      message: _notFound!,
                    ),
                  ],
                  if (_tag != null) ...[
                    const SizedBox(height: 18),
                    _summary(_tag!),
                    const SizedBox(height: 12),
                    _timeline(_tag!),
                  ] else if (_busy) ...[
                    const SizedBox(height: 18),
                    const AppSkeletonList(count: 2, lines: 2),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summary(Map<String, dynamic> tag) {
    final c = context.c;
    final t = context.texts;
    final firstName = str(tag, ['client_first_name']);
    final status = str(tag, ['status'], 'draft');
    return AppCard(
      accent: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (firstName.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          'Hello, $firstName',
                          style: t.labelSmall?.copyWith(color: c.fgFaint),
                        ),
                      ),
                    Text(
                      str(tag, ['quotation_title'], 'Your order'),
                      style: t.titleSmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              AppBadge(
                _statusLabel(status),
                tone: _statusTone(status),
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _kv('Tag code', str(tag, ['code'], '—'), mono: true),
          if (str(tag, ['label']).isNotEmpty)
            _kv('Garment', str(tag, ['label'])),
          _kv('Order reference', str(tag, ['quotation_id'], '—'), mono: true),
        ],
      ),
    );
  }

  Widget _kv(String label, String value, {bool mono = false}) {
    final c = context.c;
    final t = context.texts;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(label, style: t.labelSmall?.copyWith(color: c.fgFaint)),
          ),
          Expanded(
            child: Text(
              value,
              style: t.bodySmall?.copyWith(
                color: c.fg2,
                fontFamily: mono ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _timeline(Map<String, dynamic> tag) {
    final c = context.c;
    final t = context.texts;
    final entries = asRows(tag['status_history']);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Progress', style: t.titleSmall),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            Text(
              'No updates recorded yet. Your order is registered and will appear '
              'here as it moves through the process.',
              style: t.bodySmall?.copyWith(color: c.fgMuted),
            )
          else
            for (var i = 0; i < entries.length; i++)
              _step(entries[i], last: i == entries.length - 1),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(Icons.call_outlined, size: 14, color: c.fgFaint),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Questions? Call ${CompanyInfo.phonePrimary} · ${CompanyInfo.phoneSecondary}',
                  style: t.labelSmall?.copyWith(color: c.fgMuted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _step(Map<String, dynamic> entry, {required bool last}) {
    final c = context.c;
    final t = context.texts;
    final status = str(entry, ['status'], 'draft');
    final at = entry['changed_at'];
    final note = str(entry, ['note']);
    final tone = _statusTone(status);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 11,
                height: 11,
                margin: const EdgeInsets.only(top: 3),
                decoration: BoxDecoration(
                  color: tone.dot(c),
                  shape: BoxShape.circle,
                ),
              ),
              if (!last)
                Expanded(
                  child: Container(width: 1.5, color: c.line2),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _statusLabel(status),
                          style: t.bodyMedium?.copyWith(color: c.fg),
                        ),
                      ),
                      if (at != null)
                        Text(
                          Fmt.dateTime(at),
                          style: t.labelSmall?.copyWith(color: c.fgFaint),
                        ),
                    ],
                  ),
                  if (note.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        note,
                        style: t.labelSmall?.copyWith(color: c.fgMuted),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static AppTone _statusTone(String raw) => switch (raw.toLowerCase()) {
        'sent' => AppTone.info,
        'accepted' => AppTone.brand,
        'in_progress' || 'processing' => AppTone.warning,
        'ready' || 'ready_for_delivery' => AppTone.success,
        'delivered' || 'completed' => AppTone.success,
        'rejected' || 'cancelled' => AppTone.danger,
        _ => AppTone.neutral,
      };

  /// Order statuses are underscored codes in the database; the guest should never
  /// see them raw.
  static String _statusLabel(String raw) => switch (raw.toLowerCase()) {
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
