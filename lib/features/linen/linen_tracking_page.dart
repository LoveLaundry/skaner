import 'package:flutter/material.dart';

import '../../core/models/json.dart' as json;
import '../../core/models/linen.dart';
import '../../core/utils/formatting.dart';
import '../../data/resource_controller.dart';
import '../../state/app_scope.dart';
import '../../ui/kit/feedback.dart';
import '../../ui/kit/inputs.dart';
import '../../ui/kit/primitives.dart';
import '../../ui/kit/shell_parts.dart';
import '_linen_shared.dart';
import 'linen_items_page.dart';
import 'linen_tracking_detail_page.dart';
import 'scanner_page.dart';
import '../../ui/theme.dart';
import '../../ui/kit/data.dart';

/// The home of the linen module: the stock counters from `/linens` plus the two
/// ways an operator gets to a piece — scan the tag, or type the code.
///
/// The typed path is the primary one, not a fallback for a broken camera: it is
/// how a piece is looked up when the tag is damaged and it works with no signal
/// once the counters are cached.
class LinenTrackingPage extends StatefulWidget {
  const LinenTrackingPage({super.key});

  @override
  State<LinenTrackingPage> createState() => _LinenTrackingPageState();
}

class _LinenTrackingPageState extends State<LinenTrackingPage> {
  final _codeCtrl = TextEditingController();
  late final ResourceController<LinenStats> _controller;

  bool _looking = false;
  String? _lookupError;

  @override
  void initState() {
    super.initState();
    _controller = ResourceController(
      key: 'linen-stats',
      cache: AppScope.read(context).cache,
      fetcher: _fetch,
    );
    _controller.addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reload();
    });
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<LinenStats> _fetch() async {
    final payload =
        await AppScope.read(context).api.get(linenService, LinenApi.stats);
    return LinenStats.fromJson(json.asMap(payload));
  }

  Future<void> _reload() => _controller.load(force: true);

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final c = context.c;
    final stats = _controller.data ?? const LinenStats();
    final loading = _controller.isLoading && !_controller.hasData;

    return Scaffold(
      body: Column(
        children: [
          AppPageHeader(
            title: 'Linen',
            actions: [
              AppButton.icon(
                icon: Icons.qr_code_scanner,
                tooltip: 'Scan a tag',
                onPressed: _openScanner,
              ),
              AppButton.icon(
                icon: Icons.refresh,
                tooltip: 'Refresh',
                loading: _controller.isLoading,
                onPressed: _reload,
              ),
            ],
          ),
          AppSyncStatusBar(
            status: _controller.status,
            updatedAt: _controller.lastUpdated,
            label: 'Linen',
          ),
          AppOfflineSyncBar(engine: services.sync),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: AppButton(
              label: 'Open scanner',
              icon: Icons.qr_code_scanner,
              variant: AppButtonVariant.primary,
              block: true,
              onPressed: _openScanner,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: AppField(
              label: 'Linen ID',
              hint: 'e.g. LL-7K4P92',
              error: _lookupError,
              child: AppTextInput(
                controller: _codeCtrl,
                hint: 'Type or paste the code on the tag',
                icon: Icons.tag,
                mono: true,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _lookup(),
                onChanged: (_) {
                  if (_lookupError != null) {
                    setState(() => _lookupError = null);
                  }
                },
                suffix: IconButton(
                  icon: const Icon(Icons.arrow_forward, size: 18),
                  tooltip: 'Look up',
                  onPressed: _looking ? null : _lookup,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: loading
                ? const AppSkeletonList()
                : RefreshIndicator(
                    color: c.brand,
                    onRefresh: _reload,
                    child: ListView(
                      padding: const EdgeInsets.only(bottom: 24),
                      children: [
                        LinenMetrics(stats: stats),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
                          child: AppNotice(
                            message: stats.totalWashCycles > 0
                                ? '${Fmt.count(stats.totalWashCycles)} wash cycles recorded · '
                                    '${Fmt.count(stats.recentlyScanned)} scanned recently'
                                : 'No wash cycles recorded yet',
                            tone: AppTone.neutral,
                          ),
                        ),
                        if (stats.needsAttention > 0)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                            child: AppNotice(
                              title: 'Needs attention',
                              message:
                                  '${Fmt.count(stats.missing)} missing · ${Fmt.count(stats.damaged)} damaged. '
                                  'Open the item list and filter by status to review them.',
                              tone: AppTone.danger,
                            ),
                          ),
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: _Destination(
                            icon: Icons.inventory_2_outlined,
                            title: 'Linen items',
                            subtitle:
                                'Search, filter and open any tagged piece',
                            onTap: () => _open(const LinenItemsPage()),
                          ),
                        ),
                        if (_controller.phase == LoadPhase.failed &&
                            !_controller.hasData)
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: AppErrorState(
                              message: _controller.error,
                              onRetry: _reload,
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

  void _open(Widget page) {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => page))
        .then((_) {
      if (mounted) _reload();
    });
  }

  Future<void> _openScanner() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const ScannerPage()),
    );
    if (!mounted || code == null || code.isEmpty) return;
    await _openCode(code);
  }

  Future<void> _lookup() async {
    final code = parseLinenCode(_codeCtrl.text);
    if (code == null) {
      setState(() => _lookupError = 'That does not look like a linen code');
      return;
    }
    await _openCode(code);
  }

  Future<void> _openCode(String code) async {
    setState(() {
      _looking = true;
      _lookupError = null;
    });
    final api = AppScope.read(context).api;
    try {
      final payload = await api.get(linenService, LinenApi.byCode(code));
      final item = LinenItem.fromJson(json.asMap(payload));
      if (!mounted) return;
      setState(() {
        _looking = false;
        _codeCtrl.clear();
      });
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => LinenTrackingDetailPage(docId: item.id),
        ),
      );
      if (mounted) _reload();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _looking = false;
        _lookupError = 'No linen found with ID $code';
      });
    }
  }
}

class _Destination extends StatelessWidget {
  const _Destination({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: c.surface2,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: c.fg2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.texts.titleSmall),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: context.texts.bodySmall?.copyWith(color: c.fgMuted),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 18, color: c.fgFaint),
        ],
      ),
    );
  }
}
