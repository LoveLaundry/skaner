import 'package:flutter/material.dart';
import '../models/garment_tag.dart';

class GarmentDetailScreen extends StatelessWidget {
  final GarmentTag tag;

  const GarmentDetailScreen({super.key, required this.tag});

  Color _statusColor(String status) {
    switch (status) {
      case 'washing':
        return Colors.blue;
      case 'pressing':
        return Colors.orange;
      case 'folding':
        return Colors.purple;
      case 'packing':
        return Colors.indigo;
      case 'ready':
        return Colors.green;
      case 'out_for_delivery':
        return Colors.teal;
      case 'delivered':
        return Colors.green[700]!;
      default:
        return Colors.grey[600]!;
    }
  }

  int _statusIndex(String status) {
    const order = [
      'draft', 'received', 'washing', 'pressing',
      'folding', 'packing', 'ready', 'out_for_delivery', 'delivered'
    ];
    return order.indexOf(status);
  }

  @override
  Widget build(BuildContext context) {
    final currentIdx = _statusIndex(tag.status);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Garment Tag',
          style: TextStyle(color: Colors.black87, fontSize: 16),
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
                color: _statusColor(tag.status).withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                tag.statusLabel,
                style: TextStyle(
                  color: _statusColor(tag.status),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Info card
            _buildInfoCard([
              _Row('Tag Code', tag.code),
              if (tag.label != null) _Row('Label', tag.label!),
              if (tag.quotationTitle != null) _Row('Order', tag.quotationTitle!),
              if (tag.clientFirstName != null) _Row('Client', tag.clientFirstName!),
            ]),
            const SizedBox(height: 16),

            // Progress tracker
            const Text(
              'Order Progress',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            _buildProgressTracker(currentIdx),
            const SizedBox(height: 16),

            // Timeline
            if (tag.statusHistory.isNotEmpty) ...[
              const Text(
                'Status History',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 10),
              ...tag.statusHistory.reversed.map((entry) => _buildTimelineItem(entry)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProgressTracker(int currentIdx) {
    const steps = [
      'Draft', 'Received', 'Washing', 'Pressing',
      'Folding', 'Packing', 'Ready', 'Delivery', 'Done'
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        children: [
          Row(
            children: List.generate(steps.length, (i) {
              final isDone = i <= currentIdx;
              final isCurrent = i == currentIdx;
              return Expanded(
                child: Column(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isDone ? Colors.grey[900] : Colors.grey[200],
                        border: isCurrent
                            ? Border.all(color: Colors.grey[900]!, width: 2)
                            : null,
                      ),
                      child: isDone
                          ? const Icon(Icons.check, color: Colors.white, size: 12)
                          : null,
                    ),
                    if (i < steps.length - 1)
                      Expanded(
                        child: Container(
                          width: 2,
                          color: i < currentIdx ? Colors.grey[900] : Colors.grey[200],
                        ),
                      ),
                  ],
                ),
              );
            }),
          ),
          const SizedBox(height: 6),
          Row(
            children: List.generate(steps.length, (i) {
              return Expanded(
                child: Text(
                  steps[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 8,
                    color: i <= currentIdx ? Colors.grey[800] : Colors.grey[400],
                    fontWeight: i == currentIdx ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineItem(StatusHistoryEntry entry) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[100]!),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _statusColor(entry.status),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    GarmentTag.statusLabels[entry.status] ?? entry.status,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (entry.timestamp != null)
                    Text(
                      _formatDate(entry.timestamp!),
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(List<_Row> rows) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        children: rows
            .map((r) => Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Colors.grey[100]!, width: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 100,
                        child: Text(
                          r.label,
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[500]),
                        ),
                      ),
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
                ))
            .toList(),
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

class _Row {
  final String label;
  final String value;
  _Row(this.label, this.value);
}
