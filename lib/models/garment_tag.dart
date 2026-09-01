class GarmentTag {
  final String code;
  final String quotationId;
  final String? label;
  final String? clientFirstName;
  final String? quotationTitle;
  final String status;
  final List<StatusHistoryEntry> statusHistory;
  final String trackingUrl;

  GarmentTag({
    required this.code,
    required this.quotationId,
    this.label,
    this.clientFirstName,
    this.quotationTitle,
    required this.status,
    required this.statusHistory,
    required this.trackingUrl,
  });

  factory GarmentTag.fromJson(Map<String, dynamic> json) {
    return GarmentTag(
      code: json['code'] ?? '',
      quotationId: json['quotation_id'] ?? '',
      label: json['label'],
      clientFirstName: json['client_first_name'],
      quotationTitle: json['quotation_title'],
      status: json['status'] ?? '',
      statusHistory: (json['status_history'] as List<dynamic>?)
              ?.map((e) => StatusHistoryEntry.fromJson(e))
              .toList() ??
          [],
      trackingUrl: json['tracking_url'] ?? '',
    );
  }

  static const Map<String, String> statusLabels = {
    'draft': 'Draft',
    'received': 'Received',
    'washing': 'Washing',
    'pressing': 'Pressing',
    'folding': 'Folding',
    'packing': 'Packing',
    'ready': 'Ready',
    'out_for_delivery': 'Out for Delivery',
    'delivered': 'Delivered',
  };

  String get statusLabel => statusLabels[status] ?? status;
}

class StatusHistoryEntry {
  final String status;
  final String? timestamp;
  final String? note;

  StatusHistoryEntry({
    required this.status,
    this.timestamp,
    this.note,
  });

  factory StatusHistoryEntry.fromJson(Map<String, dynamic> json) {
    return StatusHistoryEntry(
      status: json['status'] ?? '',
      timestamp: json['timestamp'],
      note: json['note'],
    );
  }
}
