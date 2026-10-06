import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../config/api_config.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/utils/formatting.dart';
import '../../../core/utils/idempotency.dart';
import '../../../data/resource_controller.dart';
import '../../../state/app_scope.dart';
import '../../../ui/brand/logo.dart';
import '../../../ui/kit/feedback.dart';
import '../../../ui/kit/inputs.dart';
import '../../../ui/kit/primitives.dart';
import '../../../ui/theme.dart';

/// Pickup desk for walk-in customers.
///
/// The service exposes the live-chat endpoints without a session, so this is the
/// same thread the operator sees in the admin console — a guest asks about
/// collecting an order and an operator takes it over (the bot stops replying the
/// moment the conversation is assigned, which the server enforces).
///
/// The conversation id is generated on the device and shown to the guest, since
/// an unauthenticated guest has no account to look the thread up from later.
class GuestPickupPage extends StatefulWidget {
  const GuestPickupPage({super.key, this.initialConversationId});

  final String? initialConversationId;

  @override
  State<GuestPickupPage> createState() => _GuestPickupPageState();
}

class _GuestPickupPageState extends State<GuestPickupPage> {
  static const _quickAsks = <String>[
    'I would like to collect my order today',
    'Is my order ready for collection?',
    'What time do you close today?',
    'Where is your collection point?',
  ];

  late String _conversationId;
  final String _guestId = 'guest-${randomIdempotencyKey('g').substring(2, 12)}';
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  List<Map<String, dynamic>> _messages = [];
  String? _guestName;
  String? _handler;
  String? _error;
  bool _sending = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _conversationId = (widget.initialConversationId ?? '').trim().isEmpty
        ? 'pickup-${randomIdempotencyKey('c').substring(2, 14)}'
        : widget.initialConversationId!.trim();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startPolling());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _startPolling() {
    _refresh();
    _poll?.cancel();
    // The public history poll is the only way a guest learns about an admin
    // reply, so keep it running while the screen is open.
    _poll = Timer.periodic(const Duration(seconds: 8), (_) => _refresh());
  }

  Future<void> _refresh({bool silent = true}) async {
    try {
      final data = await AppScope.read(context).api.get(
        ServiceNames.quotation,
        '/chat/conversations/$_conversationId',
        query: {'guest_id': _guestId},
        includeAuth: false,
      );
      if (!mounted || data is! Map<String, dynamic>) return;
      final next = asRows(data['messages']);
      final handler = (data['assigned_admin_name'] as String?)?.trim();
      setState(() {
        _error = null;
        _messages = next;
        if (handler != null && handler.isNotEmpty) _handler = handler;
      });
      _toBottom();
    } on ApiException catch (e) {
      if (!mounted || silent) return;
      setState(() => _error = e.message);
    } catch (_) {
      // A poll failure is not worth interrupting the guest for; the next tick
      // retries and the banner only appears when they act.
    }
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _sending) return;
    final name = _guestName;
    setState(() {
      _sending = true;
      _error = null;
      if (preset == null) _input.clear();
    });
    // Echo locally first so the guest sees their message immediately; the poll
    // reconciles it with the server copy (same id, same text).
    setState(() => _messages = [
          ..._messages,
          {
            'id': 'local-${DateTime.now().microsecondsSinceEpoch}',
            'sender': 'guest',
            'sender_name': name,
            'text': text,
            'timestamp': DateTime.now().toIso8601String(),
            'pending': true,
          },
        ]);
    _toBottom();
    try {
      final data = await AppScope.read(context).api.write(
        ServiceNames.quotation,
        'POST',
        '/chat/conversations/$_conversationId/messages',
        body: {
          'message': text,
          'guest_id': _guestId,
          if (name != null && name.isNotEmpty) 'name': name,
          'lang': 'en',
          'title': 'Pickup — ${name ?? 'guest'}',
        },
        includeAuth: false,
      );
      if (!mounted) return;
      if (data is QueuedResponse) {
        setState(() {
          _sending = false;
          _markLastPending('Queued — will send when you are back online');
        });
        return;
      }
      final handler = data is Map<String, dynamic>
          ? (data['assigned_admin_name'] as String?)?.trim()
          : null;
      setState(() {
        _sending = false;
        if (data is Map<String, dynamic>) {
          _messages = asRows(data['messages']);
          if (handler != null && handler.isNotEmpty) _handler = handler;
        }
      });
      _toBottom();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = e.message;
        _dropLastPending();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = 'Message not sent. Check your connection and try again.';
        _dropLastPending();
      });
    }
  }

  void _markLastPending(String note) {
    if (_messages.isEmpty) return;
    _messages = [
      ..._messages.take(_messages.length - 1),
      {..._messages.last, 'pending': false, 'queued_note': note},
    ];
  }

  void _dropLastPending() {
    if (_messages.isEmpty) return;
    if (_messages.last['pending'] != true) return;
    _messages = _messages.sublist(0, _messages.length - 1);
  }

  Future<void> _askName() async {
    final controller = TextEditingController(text: _guestName ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (dialog) => AppDialog(
        title: 'Your name',
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'So the counter knows who is collecting.',
              style: dialog.texts.bodySmall?.copyWith(color: dialog.c.fgMuted),
            ),
            const SizedBox(height: 12),
            AppTextInput(
              controller: controller,
              hint: 'e.g. Nimal',
              autofocus: true,
              textCapitalization: TextCapitalization.words,
            ),
          ],
        ),
        actions: [
          AppButton(
            label: 'Cancel',
            onPressed: () => Navigator.of(dialog).pop(),
          ),
          AppButton(
            label: 'Continue',
            variant: AppButtonVariant.primary,
            onPressed: () {
              final value = controller.text.trim();
              Navigator.of(dialog).pop(value.isEmpty ? null : value);
            },
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || !mounted) return;
    setState(() => _guestName = name);
    await _send('I would like to collect my order');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      backgroundColor: c.canvas,
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            Container(height: 1, color: c.line),
            Expanded(child: _thread()),
            if (_error != null)
              Container(
                width: double.infinity,
                color: c.surface,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: AppNotice(
                  tone: AppTone.danger,
                  message: _error!,
                  onClose: () => setState(() => _error = null),
                ),
              ),
            _composer(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    final c = context.c;
    return Container(
      width: double.infinity,
      color: c.surface,
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        children: [
          const Expanded(child: AppLogo(size: 30)),
          AppBadge(
            _handler == null ? 'Pickup desk' : 'With $_handler',
            icon: _handler == null ? Icons.support_agent : Icons.person_pin,
            tone: _handler == null ? AppTone.neutral : AppTone.success,
            compact: true,
          ),
          AppMenuButton(
            label: 'More',
            items: [
              AppMenuItem(
                label: 'Copy pickup reference',
                icon: Icons.copy_rounded,
                subtitle: _conversationId,
                onTap: () async {
                  await Clipboard.setData(
                      ClipboardData(text: _conversationId));
                  if (!mounted) return;
                  AppToast.info(context, 'Pickup reference copied');
                },
              ),
              AppMenuItem(
                label: 'Start a new conversation',
                icon: Icons.add_comment_outlined,
                onTap: () => setState(() {
                  _conversationId =
                      'pickup-${randomIdempotencyKey('c').substring(2, 14)}';
                  _messages = [];
                  _handler = null;
                  _refresh(silent: false);
                }),
              ),
              AppMenuItem(
                label: 'Track an order instead',
                icon: Icons.qr_code_2_rounded,
                onTap: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _thread() {
    final c = context.c;
    final t = context.texts;
    if (_messages.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
        children: [
          Text('Collect an order', style: t.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Ask us to have your order ready. A member of the counter picks this '
            'up and replies here.',
            style: t.bodySmall?.copyWith(color: c.fgMuted),
          ),
          const SizedBox(height: 14),
          AppButton(
            label: _guestName == null
                ? 'Tell us your name and start'
                : 'Ask to collect my order',
            icon: Icons.support_agent,
            variant: AppButtonVariant.primary,
            block: true,
            onPressed: _sending ? null : _askName,
          ),
          const SizedBox(height: 10),
          for (final ask in _quickAsks)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                onTap: _sending ? null : () => _send(ask),
                child: Row(
                  children: [
                    Icon(Icons.arrow_outward_rounded, size: 15, color: c.brand),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(ask, style: t.bodySmall?.copyWith(color: c.fg2)),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 6),
          AppNotice(
            tone: AppTone.info,
            message:
                'Quote your tag code or reference number in the message so we can '
                'find the order quickly.',
          ),
        ],
      );
    }

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
      itemCount: _messages.length,
      itemBuilder: (_, i) => _bubble(_messages[i]),
    );
  }

  Widget _bubble(Map<String, dynamic> message) {
    final c = context.c;
    final t = context.texts;
    final sender = str(message, ['sender'], 'guest');
    final mine = sender == 'guest';
    final text = str(message, ['text']);
    final at = message['timestamp'];
    final pending = message['pending'] == true;
    final queued = str(message, ['queued_note']);
    final who = switch (sender) {
      'bot' => 'Assistant',
      'admin' => str(message, ['sender_name'], _handler ?? 'Counter'),
      _ => _guestName ?? 'You',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!mine)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 3),
              child: Text(
                who,
                style: t.labelSmall?.copyWith(color: c.fgFaint),
              ),
            ),
          Container(
            constraints: const BoxConstraints(maxWidth: 320),
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 8),
            decoration: BoxDecoration(
              color: mine ? c.brandSoft : c.surface,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(Radii.lg),
                topRight: const Radius.circular(Radii.lg),
                bottomLeft: Radius.circular(mine ? Radii.lg : Radii.xs),
                bottomRight: Radius.circular(mine ? Radii.xs : Radii.lg),
              ),
              border: Border.all(color: mine ? c.brandBorder : c.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: t.bodySmall?.copyWith(color: mine ? c.brandText : c.fg),
                ),
                const SizedBox(height: 3),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (at != null)
                      Text(
                        Fmt.time(at),
                        style: t.labelSmall
                            ?.copyWith(color: c.fgFaint, fontSize: 10.5),
                      ),
                    if (pending) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.schedule_rounded, size: 11, color: c.fgFaint),
                      const SizedBox(width: 2),
                      Text('Sending',
                          style: t.labelSmall
                              ?.copyWith(color: c.fgFaint, fontSize: 10.5)),
                    ],
                    if (queued.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.cloud_upload_outlined,
                          size: 11, color: c.warning),
                      const SizedBox(width: 2),
                      Flexible(
                        child: Text(
                          queued,
                          style: t.labelSmall
                              ?.copyWith(color: c.warning, fontSize: 10.5),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _composer() {
    final c = context.c;
    return Container(
      width: double.infinity,
      color: c.surface,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: AppTextInput(
                controller: _input,
                hint: 'Message the counter…',
                maxLines: 4,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                enabled: !_sending,
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            AppButton.icon(
              icon: Icons.send_rounded,
              tooltip: 'Send',
              variant: AppButtonVariant.primary,
              size: AppButtonSize.md,
              onPressed: _sending ? null : _send,
            ),
          ],
        ),
      ),
    );
  }
}
