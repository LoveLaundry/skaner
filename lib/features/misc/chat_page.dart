import 'dart:async';

import 'package:flutter/material.dart';

import '../../../config/api_config.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/utils/formatting.dart';
import '../../../data/resource_controller.dart';
import '../../../state/app_scope.dart';
import '../../../ui/kit/feedback.dart';
import '../../../ui/kit/inputs.dart';
import '../../../ui/kit/primitives.dart';
import '../../../ui/theme.dart';

/// Port of `features/quotations/pages/live-chat-page.tsx`.
///
/// The operator's side of the same public chat the guest pickup desk opens.
/// The list polls every 5s and the open thread every 3s, matching the web app;
/// a reply from the counter also assigns the conversation to that operator,
/// which is what silences the bot server-side.
class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  static const _listPath = '/chat/admin/conversations';

  late final ResourceController<List<Map<String, dynamic>>> _conversations;
  final TextEditingController _draft = TextEditingController();
  final ScrollController _thread = ScrollController();

  Map<String, dynamic>? _detail;
  String? _selectedId;
  String? _error;
  bool _sending = false;
  Timer? _listPoll;
  Timer? _detailPoll;

  @override
  void initState() {
    super.initState();
    _conversations = ResourceController<List<Map<String, dynamic>>>(
      key: 'chat-conversations',
      cache: AppScope.read(context).cache,
      fetcher: () async {
        final data = await AppScope.read(context).api
            .get(ServiceNames.quotation, _listPath);
        return asRows(data);
      },
    )..addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _conversations.load(force: true);
      _listPoll = Timer.periodic(
          const Duration(seconds: 5), (_) => _conversations.load());
    });
  }

  @override
  void dispose() {
    _listPoll?.cancel();
    _detailPoll?.cancel();
    _conversations.removeListener(_onChanged);
    _conversations.dispose();
    _draft.dispose();
    _thread.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _select(String id) {
    if (_selectedId == id) return;
    setState(() {
      _selectedId = id;
      _detail = null;
      _error = null;
    });
    _loadDetail();
    _detailPoll?.cancel();
    _detailPoll = Timer.periodic(const Duration(seconds: 3), (_) => _loadDetail());
  }

  Future<void> _loadDetail({bool quiet = false}) async {
    final id = _selectedId;
    if (id == null) return;
    try {
      final data =
          await AppScope.read(context).api.get(ServiceNames.quotation,
              '/chat/admin/conversations/$id');
      if (!mounted || _selectedId != id) return;
      setState(() {
        _detail = data is Map<String, dynamic> ? data : null;
        _error = null;
      });
      _toBottom();
    } on ApiException catch (e) {
      if (!mounted || _selectedId != id || quiet) return;
      setState(() => _error = e.message);
    } catch (_) {
      // A missed poll is not worth surfacing; the next tick retries.
    }
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_thread.hasClients) return;
      _thread.animateTo(
        _thread.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final text = _draft.text.trim();
    final id = _selectedId;
    if (text.isEmpty || id == null || _sending) return;
    setState(() {
      _sending = true;
      _draft.clear();
    });
    final before = asRows(_detail?['messages']).length;
    try {
      final data = await AppScope.read(context).api.write(
        ServiceNames.quotation,
        'POST',
        '/chat/admin/conversations/$id/messages',
        body: {'text': text},
      );
      if (!mounted) return;
      if (data is QueuedResponse) {
        setState(() => _sending = false);
        AppToast.warning(context, 'Reply queued — it will send when online');
        return;
      }
      setState(() {
        _sending = false;
        if (data is Map<String, dynamic>) _detail = data;
      });
      _toBottom();
      // Replying reassigns the conversation to this operator; refresh the list so
      // the sidebar shows who is handling it.
      if (asRows(_detail?['messages']).length == before) _conversations.load();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _draft.text = text;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _draft.text = text;
        _error = 'Reply not sent. Check your connection and try again.';
      });
    }
  }

  Future<void> _setStatus(String status) async {
    final id = _selectedId;
    if (id == null) return;
    try {
      final data = await AppScope.read(context).api.patch(
        ServiceNames.quotation,
        '/chat/admin/conversations/$id',
        body: {'status': status},
      );
      if (!mounted) return;
      setState(() {
        if (data is Map<String, dynamic>) _detail = data;
        _error = null;
      });
      _conversations.load();
      AppToast.success(
          context, status == 'closed' ? 'Conversation closed' : 'Conversation reopened');
    } on ApiException catch (e) {
      if (!mounted) return;
      AppToast.error(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.texts;
    final rows = _conversations.data ?? const <Map<String, dynamic>>[];

    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: c.surface,
            border: Border(bottom: BorderSide(color: c.line)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.forum_outlined, size: 18, color: c.brand),
                        const SizedBox(width: 8),
                        Text('Live Chat', style: t.titleLarge),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Public website conversations. Take over a chat to answer as '
                      'yourself — the bot stays silent once you join.',
                      style: t.bodySmall?.copyWith(color: c.fgMuted),
                    ),
                  ],
                ),
              ),
              AppButton.icon(
                icon: Icons.refresh,
                tooltip: 'Refresh',
                onPressed: () => _conversations.load(force: true),
              ),
            ],
          ),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 300, child: _sidebar(rows, t, c)),
              Container(width: 1, color: c.line),
              Expanded(child: _pane(t, c)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sidebar(List<Map<String, dynamic>> rows, TextTheme t, AppColors c) {
    if (_conversations.isLoading && rows.isEmpty) {
      return const AppSkeletonList(count: 6, lines: 2);
    }
    if (rows.isEmpty) {
      return Center(
        child: _conversations.phase == LoadPhase.failed
            ? AppErrorState(
                message: _conversations.error ?? 'Could not load conversations.',
                onRetry: () => _conversations.load(force: true),
              )
            : const AppEmptyState(
                title: 'No conversations yet',
                message: 'Chats started from the website land here.',
                icon: Icons.forum_outlined,
                compact: true,
              ),
      );
    }
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, __) => Container(height: 1, color: c.line),
      itemBuilder: (_, i) {
        final row = rows[i];
        final id = str(row, ['conversation_id'], '—');
        final active = id == _selectedId;
        final status = str(row, ['status'], 'open');
        final last = asRows(pick(row, ['last_message'])).firstOrNull;
        return InkWell(
          onTap: () => _select(id),
          child: Container(
            color: active ? c.brandSoft : null,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        str(row, ['guest_name']).isEmpty
                            ? 'Website visitor'
                            : str(row, ['guest_name']),
                        style: t.bodyMedium?.copyWith(
                          color: c.fg,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    AppBadge(
                      status,
                      tone: status == 'closed' ? AppTone.neutral : AppTone.success,
                      compact: true,
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  last == null
                      ? 'No messages'
                      : str(last, ['text'], 'No messages'),
                  style: t.bodySmall?.copyWith(color: c.fgMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Text(
                      Fmt.dateTime(pick(row, ['updated_at'])),
                      style: t.labelSmall?.copyWith(color: c.fgFaint, fontSize: 10.5),
                    ),
                    if (str(row, ['assigned_admin_name']).isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.person_rounded, size: 11, color: c.brand),
                      const SizedBox(width: 2),
                      Flexible(
                        child: Text(
                          str(row, ['assigned_admin_name']),
                          style: t.labelSmall
                              ?.copyWith(color: c.brandText, fontSize: 10.5),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                    const Spacer(),
                    if (intOf(row, ['message_count']) > 0)
                      Text(
                        '${intOf(row, ['message_count'])}',
                        style: t.labelSmall?.copyWith(color: c.fgFaint, fontSize: 10.5),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _pane(TextTheme t, AppColors c) {
    if (_selectedId == null) {
      return const AppEmptyState(
        title: 'Select a conversation',
        message: 'Pick a conversation on the left to read and reply.',
        icon: Icons.forum_outlined,
      );
    }
    final detail = _detail;
    final messages = asRows(detail?['messages']);
    final handler = str(detail ?? {}, ['assigned_admin_name']);
    final status = str(detail ?? {}, ['status'], 'open');

    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: c.surface,
            border: Border(bottom: BorderSide(color: c.line)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      str(detail ?? {}, ['guest_name']).isEmpty
                          ? 'Website visitor'
                          : str(detail ?? {}, ['guest_name']),
                      style: t.titleSmall,
                    ),
                    Text(
                      handler.isNotEmpty
                          ? 'Handled by $handler'
                          : 'Bot is answering',
                      style: t.labelSmall?.copyWith(color: c.fgFaint),
                    ),
                  ],
                ),
              ),
              AppButton(
                label: status == 'closed' ? 'Reopen' : 'Close',
                icon: status == 'closed'
                    ? Icons.check_circle_outline
                    : Icons.cancel_outlined,
                size: AppButtonSize.sm,
                onPressed: () =>
                    _setStatus(status == 'closed' ? 'open' : 'closed'),
              ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: AppNotice(
              tone: AppTone.danger,
              message: _error!,
              onClose: () => setState(() => _error = null),
            ),
          ),
        Expanded(
          child: detail == null
              ? const AppSkeletonList(count: 4, lines: 1)
              : Container(
                  color: c.surfaceSunken,
                  child: ListView.builder(
                    controller: _thread,
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    itemCount: messages.length,
                    itemBuilder: (_, i) => _bubble(messages[i], t, c),
                  ),
                ),
        ),
        Container(
          decoration: BoxDecoration(
            color: c.surface,
            border: Border(top: BorderSide(color: c.line)),
          ),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: AppTextInput(
                  controller: _draft,
                  hint: 'Reply as yourself… (Enter to send)',
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
      ],
    );
  }

  Widget _bubble(Map<String, dynamic> message, TextTheme t, AppColors c) {
    final sender = str(message, ['sender'], 'guest');
    final mine = sender == 'admin';
    final who = switch (sender) {
      'admin' => 'You (${str(message, ['sender_name'], 'Admin')})',
      'bot' => 'Bot',
      _ => str(message, ['sender_name'], 'Guest'),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
            mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!mine) ...[
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: c.dangerSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(
                sender == 'bot' ? Icons.smart_toy_outlined : Icons.person_outline,
                size: 14,
                color: c.danger,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420),
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 7),
              decoration: BoxDecoration(
                color: mine ? c.brand : c.surface2,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(Radii.lg),
                  topRight: const Radius.circular(Radii.lg),
                  bottomLeft: Radius.circular(mine ? Radii.lg : Radii.xs),
                  bottomRight: Radius.circular(mine ? Radii.xs : Radii.lg),
                ),
                border: Border.all(color: mine ? c.brand : c.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    who,
                    style: t.labelSmall?.copyWith(
                      color: mine ? c.brandText : c.fgMuted,
                      fontSize: 10.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    str(message, ['text']),
                    style: t.bodySmall?.copyWith(color: mine ? c.brandText : c.fg),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    Fmt.dateTime(message['timestamp']),
                    style: t.labelSmall?.copyWith(
                      color: mine ? c.brandText : c.fgFaint,
                      fontSize: 10.5,
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
}
