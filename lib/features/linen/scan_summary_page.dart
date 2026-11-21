import 'package:flutter/material.dart';

import '../../core/models/linen.dart';
import '../../core/utils/formatting.dart';
import '../../state/app_scope.dart';
import '../../ui/kit/feedback.dart';
import '../../ui/kit/primitives.dart';
import '../../ui/theme.dart';
import '_linen_shared.dart';

/// Scan summary dashboard showing today's scanned items with real-time sync
class ScanSummaryPage extends StatefulWidget {
  const ScanSummaryPage({super.key});

  @override
  State<ScanSummaryPage> createState() => _ScanSummaryPageState();
}

class _ScanSummaryPageState extends State<ScanSummaryPage> {
  final List<ScanRecord> _todayScans = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTodayScans();
  }

  Future<void> _loadTodayScans() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Load from local storage or fetch from API
      final services = AppScope.read(context);
      final prefs = await services.storage;
      final todayScansJson = prefs.getString('today_scans');

      if (todayScansJson != null) {
        // Parse stored scans
        // In production, this would be a proper JSON parse
        setState(() {
          _loading = false;
        });
      } else {
        // Fetch from API
        final payload = await services.api.get(
          ServiceNames.bills,
          '/linens/scans/today',
        );
        // Parse response and populate _todayScans
        setState(() {
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Map<LinenStatus, int> get _statusCounts {
    final counts = <LinenStatus, int>{};
    for (final scan in _todayScans) {
      counts[scan.status] = (counts[scan.status] ?? 0) + 1;
    }
    return counts;
  }

  int get _totalScans => _todayScans.length;
  int get _syncedCount => _todayScans.where((s) => s.synced).length;
  int get _pendingCount => _totalScans - _syncedCount;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.texts;
    final statusCounts = _statusCounts;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Summary'),
        actions: [
          AppButton.icon(
            icon: Icons.refresh,
            tooltip: 'Refresh',
            loading: _loading,
            onPressed: _loadTodayScans,
          ),
        ],
      ),
      body: Column(
        children: [
          // Summary cards
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _SummaryCard(
                        label: 'Total Scans',
                        value: '$_totalScans',
                        icon: Icons.qr_code_scanner,
                        color: c.brand,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _SummaryCard(
                        label: 'Synced',
                        value: '$_syncedCount',
                        icon: Icons.cloud_done,
                        color: c.success,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _SummaryCard(
                        label: 'Pending',
                        value: '$_pendingCount',
                        icon: Icons.cloud_upload,
                        color: _pendingCount > 0 ? c.warning : c.success,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _SummaryCard(
                        label: 'In Flow',
                        value: '${statusCounts.values.where((v) => linenFlowStatuses.contains(linenStatusFrom(v.toString()))).fold<int>(0, (a, b) => a + b)}',
                        icon: Icons.local_shipping_outlined,
                        color: c.info,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Status breakdown
          if (statusCounts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'STATUS BREAKDOWN',
                    style: t.labelSmall?.copyWith(
                      color: c.fgMuted,
                      fontSize: 10.5,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final entry in statusCounts.entries)
                        _StatusChip(
                          status: entry.key,
                          count: entry.value,
                        ),
                    ],
                  ),
                ],
              ),
            ),

          const Divider(height: 24),

          // Scan list
          Expanded(
            child: _loading
                ? const AppSkeletonList()
                : _error != null
                    ? AppErrorState(
                        message: _error,
                        onRetry: _loadTodayScans,
                      )
                    : _todayScans.isEmpty
                        ? AppEmptyState(
                            title: 'No scans today',
                            message: 'Start scanning linen items to see them here.',
                            icon: Icons.qr_code_scanner,
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                            itemCount: _todayScans.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (_, i) => _ScanCard(
                              scan: _todayScans[i],
                              onTap: () => _showScanDetail(_todayScans[i]),
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  void _showScanDetail(ScanRecord scan) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(scan.linenId),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DetailRow('Item', scan.itemType),
            _DetailRow('Client', scan.clientName),
            _DetailRow('Action', scan.action),
            _DetailRow('Status', linenStatusLabels[scan.status] ?? 'Unknown'),
            _DetailRow('Time', Fmt.dateTime(scan.timestamp)),
            _DetailRow('Synced', scan.synced ? 'Yes' : 'No'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = context.texts;
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: t.labelSmall?.copyWith(color: context.c.fgMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: t.headlineSmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.status,
    required this.count,
  });

  final LinenStatus status;
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AppFilterChip(
      label: '${linenStatusLabels[status]} ($count)',
      selected: true,
      onTap: null,
      backgroundColor: linenStatusTone(status).surface(c).withOpacity(0.3),
      selectedColor: linenStatusTone(status).surface(c),
    );
  }
}

class _ScanCard extends StatelessWidget {
  const _ScanCard({
    required this.scan,
    required this.onTap,
  });

  final ScanRecord scan;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.texts;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          LinenStatusBadge(status: scan.status, compact: true),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  scan.linenId,
                  style: t.titleSmall?.copyWith(fontFamily: 'monospace'),
                ),
                const SizedBox(height: 2),
                Text(
                  '${scan.itemType} · ${scan.clientName}',
                  style: t.bodySmall?.copyWith(color: c.fgMuted),
                ),
              ],
            ),
          ),
          if (!scan.synced)
            Icon(Icons.cloud_off, size: 16, color: c.warning)
          else
            Icon(Icons.cloud_done, size: 16, color: c.success),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: context.texts.bodyMedium?.copyWith(
                color: context.c.fgMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }
}

/// Simple scan record model
class ScanRecord {
  const ScanRecord({
    required this.linenId,
    required this.itemType,
    required this.clientName,
    required this.action,
    required this.status,
    required this.timestamp,
    required this.synced,
  });

  final String linenId;
  final String itemType;
  final String clientName;
  final String action;
  final LinenStatus status;
  final String timestamp;
  final bool synced;
}
