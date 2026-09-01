import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/linen.dart';
import '../services/auth_service.dart';
import '../services/linen_service.dart';

class LinenDetailScreen extends StatefulWidget {
  final LinenItem linen;

  const LinenDetailScreen({super.key, required this.linen});

  @override
  State<LinenDetailScreen> createState() => _LinenDetailScreenState();
}

class _LinenDetailScreenState extends State<LinenDetailScreen> {
  bool _acting = false;
  String? _actionResult;

  LinenItem get linen => widget.linen;

  Future<void> _performAction(String action) async {
    final auth = context.read<AuthService>();
    final token = auth.token!;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Confirm $action'),
        content: Text('Change status to "${LinenItem.statusLabels[_toUpperCase(action)] ?? action}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _acting = true;
      _actionResult = null;
    });

    final service = LinenService(token: token);
    final error = await service.performScanAction(
      docId: linen.id,
      action: _toUpperCase(action),
    );

    if (!mounted) return;

    setState(() => _acting = false);

    if (error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Status changed to ${LinenItem.statusLabels[_toUpperCase(action)]}'),
          backgroundColor: Colors.green[700],
        ),
      );
      Navigator.pop(context, true); // refresh
    } else {
      setState(() => _actionResult = error);
    }
  }

  String _toUpperCase(String s) => s.toUpperCase().replaceAll(' ', '_');

  List<_QuickAction> _getAvailableActions() {
    final status = linen.status;
    switch (status) {
      case 'COLLECTED':
        return [_QuickAction('Receive', Icons.inbox, 'receive')];
      case 'AT_LAUNDRY':
        return [_QuickAction('Start Wash', Icons.water_drop, 'start_wash')];
      case 'WASHING':
        return [_QuickAction('Complete Wash', Icons.check_circle, 'complete_wash')];
      case 'DRYING':
        return [_QuickAction('Press', Icons.iron, 'press')];
      case 'PRESSING':
        return [_QuickAction('Ready', Icons.check, 'ready')];
      case 'READY':
        return [_QuickAction('Deliver', Icons.local_shipping, 'deliver')];
      default:
        return [];
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'WASHING':
        return Colors.blue;
      case 'DRYING':
        return Colors.orange;
      case 'PRESSING':
        return Colors.purple;
      case 'READY':
        return Colors.green;
      case 'DELIVERED':
        return Colors.teal;
      case 'MISSING':
        return Colors.red;
      case 'DAMAGED':
        return Colors.red[800]!;
      case 'RETIRED':
        return Colors.grey;
      default:
        return Colors.grey[600]!;
    }
  }

  @override
  Widget build(BuildContext context) {
    final actions = _getAvailableActions();

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          linen.linenId,
          style: const TextStyle(color: Colors.black87, fontSize: 16),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _statusColor(linen.status).withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                linen.statusLabel,
                style: TextStyle(
                  color: _statusColor(linen.status),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Info card
            _InfoCard(
              title: 'Item Details',
              rows: [
                _InfoRow('Category', linen.category),
                _InfoRow('Item Type', linen.itemType),
                if (linen.size != null && linen.size!.isNotEmpty)
                  _InfoRow('Size', linen.size!),
                if (linen.color != null && linen.color!.isNotEmpty)
                  _InfoRow('Color', linen.color!),
                _InfoRow('Client', linen.clientName),
                if (linen.department != null && linen.department!.isNotEmpty)
                  _InfoRow('Department', linen.department!),
              ],
            ),
            const SizedBox(height: 12),

            // Status card
            _InfoCard(
              title: 'Status & Condition',
              rows: [
                _InfoRow('Status', linen.statusLabel),
                _InfoRow('Condition', linen.conditionLabel),
                if (linen.location != null && linen.location!.isNotEmpty)
                  _InfoRow('Location', linen.location!),
                _InfoRow('Wash Count', linen.washCount.toString()),
                if (linen.lastWashedDate != null)
                  _InfoRow('Last Washed', _formatDate(linen.lastWashedDate!)),
                if (linen.lastScannedDate != null)
                  _InfoRow('Last Scanned', _formatDate(linen.lastScannedDate!)),
              ],
            ),

            // Notes
            if (linen.notes != null && linen.notes!.isNotEmpty) ...[
              const SizedBox(height: 12),
              _InfoCard(
                title: 'Notes',
                rows: [_InfoRow('', linen.notes!)],
              ),
            ],

            // Action result
            if (_actionResult != null)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_actionResult!,
                    style: const TextStyle(color: Colors.red, fontSize: 13)),
              ),

            // Quick actions
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text(
                'Quick Actions',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 10),
              ...actions.map((a) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: ElevatedButton.icon(
                        onPressed: _acting ? null : () => _performAction(a.action),
                        icon: _acting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : Icon(a.icon, size: 18),
                        label: Text(a.label),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[900],
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}

class _QuickAction {
  final String label;
  final IconData icon;
  final String action;
  _QuickAction(this.label, this.icon, this.action);
}

class _InfoCard extends StatelessWidget {
  final String title;
  final List<_InfoRow> rows;

  const _InfoCard({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
          const Divider(height: 1),
          ...rows.map((r) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Colors.grey[100]!, width: 0.5),
                  ),
                ),
                child: Row(
                  crossAxisAlignment:
                      r.label.isEmpty ? CrossAxisAlignment.start : CrossAxisAlignment.center,
                  children: [
                    if (r.label.isNotEmpty) ...[
                      SizedBox(
                        width: 110,
                        child: Text(
                          r.label,
                          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        r.value,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

class _InfoRow {
  final String label;
  final String value;
  _InfoRow(this.label, this.value);
}
