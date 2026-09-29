import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';
import 'primitives.dart';

/// A toast queue the whole app can raise errors and confirmations through,
/// without any page having to own a banner.
///
/// The web app calls `toast.error(...)` from `sonner`, which mounts one global
/// overlay. This is the same idea for Flutter: [Toast] is a process-wide
/// [ChangeNotifier], and [ToastHost] — mounted once via `MaterialApp.builder` —
/// renders whatever is queued. That means a failure inside the API client or
/// the sync engine can surface, which an inline notice widget never could.
class Toast {
  Toast._();

  static final AppToasts _instance = AppToasts();
  static AppToasts get i => _instance;

  static void error(String message, {String? title}) =>
      _instance.show(message, tone: AppTone.danger, title: title);

  static void success(String message, {String? title}) =>
      _instance.show(message, tone: AppTone.success, title: title);

  static void warning(String message, {String? title}) =>
      _instance.show(message, tone: AppTone.warning, title: title);

  static void info(String message, {String? title}) =>
      _instance.show(message, tone: AppTone.info, title: title);
}

class ToastItem {
  ToastItem({
    required this.id,
    required this.message,
    required this.tone,
    this.title,
    this.duration = const Duration(seconds: 4),
    this.onTap,
  });

  final int id;
  final String message;
  final AppTone tone;
  final String? title;
  final Duration duration;
  final VoidCallback? onTap;
}

/// Queue behind [Toast]. Ids increase so a repeat of the same message still
/// animates in; the caller is expected to be on the UI isolate.
class AppToasts extends ChangeNotifier {
  /// Sonner keeps a few on screen; anything beyond this is dropped oldest-first
  /// so a burst of failures cannot bury the screen.
  static const int maxVisible = 3;

  final List<ToastItem> _items = [];
  int _nextId = 0;

  List<ToastItem> get items => List.unmodifiable(_items);

  bool get isEmpty => _items.isEmpty;

  void show(
    String message, {
    AppTone tone = AppTone.neutral,
    String? title,
    Duration? duration,
    VoidCallback? onTap,
  }) {
    final item = ToastItem(
      id: _nextId++,
      message: message,
      tone: tone,
      title: title,
      duration: duration ?? _defaultDuration(tone),
      onTap: onTap,
    );
    _items.add(item);
    while (_items.length > maxVisible) {
      _items.removeAt(0);
    }
    notifyListeners();
    if (item.duration > Duration.zero) {
      Timer(item.duration, () => dismiss(item.id));
    }
  }

  /// Errors stay up longer than confirmations: they usually carry a cause the
  /// operator has to read.
  static Duration _defaultDuration(AppTone tone) => switch (tone) {
        AppTone.danger => const Duration(seconds: 6),
        AppTone.warning => const Duration(seconds: 5),
        _ => const Duration(seconds: 3),
      };

  void dismiss(int id) {
    final before = _items.length;
    _items.removeWhere((t) => t.id == id);
    if (_items.length != before) notifyListeners();
  }

  void clear() {
    if (_items.isEmpty) return;
    _items.clear();
    notifyListeners();
  }
}

/// Renders the queue. Mount once, above the navigator, via
/// `MaterialApp(builder: (context, child) => ToastHost(child: child!))`.
class ToastHost extends StatelessWidget {
  const ToastHost({super.key, required this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (child != null) child!,
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: SafeArea(
            child: ListenableBuilder(
              listenable: Toast.i,
              builder: (context, _) => _ToastStack(items: Toast.i.items),
            ),
          ),
        ),
      ],
    );
  }
}

class _ToastStack extends StatelessWidget {
  const _ToastStack({required this.items});

  final List<ToastItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final item in items)
          Padding(
            key: ValueKey(item.id),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: _ToastCard(item: item),
          ),
      ],
    );
  }
}

class _ToastCard extends StatelessWidget {
  const _ToastCard({required this.item});

  final ToastItem item;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.texts;
    final (fg, bg, border) = item.tone.resolve(c);
    final card = Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: Border.circular(Radii.md),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(AppNotice.iconFor(item.tone), size: 17, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (item.title != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      item.title!,
                      style: t.labelLarge?.copyWith(color: fg),
                    ),
                  ),
                Text(
                  item.message,
                  style: t.bodySmall
                      ?.copyWith(color: fg.withValues(alpha: 0.95)),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 15),
            color: fg,
            tooltip: 'Dismiss',
            visualDensity: VisualDensity.compact,
            onPressed: () => Toast.i.dismiss(item.id),
          ),
        ],
      ),
    );

    return Dismissible(
      key: ValueKey('dismiss-${item.id}'),
      direction: DismissDirection.horizontal,
      onDismissed: (_) => Toast.i.dismiss(item.id),
      child: GestureDetector(
        onTap: () {
          item.onTap?.call();
          Toast.i.dismiss(item.id);
        },
        child: card,
      ),
    );
  }
}
