class LinenItem {
  final String id;
  final String linenId;
  final String category;
  final String itemType;
  final String? description;
  final String? size;
  final String? color;
  final String clientName;
  final String? department;
  final String status;
  final String condition;
  final String? location;
  final int washCount;
  final String? lastWashedDate;
  final String? lastScannedDate;
  final String? retirementDate;
  final String? notes;
  final String createdAt;
  final String updatedAt;

  LinenItem({
    required this.id,
    required this.linenId,
    required this.category,
    required this.itemType,
    this.description,
    this.size,
    this.color,
    required this.clientName,
    this.department,
    required this.status,
    required this.condition,
    this.location,
    required this.washCount,
    this.lastWashedDate,
    this.lastScannedDate,
    this.retirementDate,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory LinenItem.fromJson(Map<String, dynamic> json) {
    return LinenItem(
      id: json['_id'] ?? json['id'] ?? '',
      linenId: json['linen_id'] ?? '',
      category: json['category'] ?? '',
      itemType: json['item_type'] ?? '',
      description: json['description'],
      size: json['size'],
      color: json['color'],
      clientName: json['client_name'] ?? '',
      department: json['department'],
      status: json['status'] ?? '',
      condition: json['condition'] ?? '',
      location: json['location'],
      washCount: json['wash_count'] ?? 0,
      lastWashedDate: json['last_washed_date'],
      lastScannedDate: json['last_scanned_date'],
      retirementDate: json['retirement_date'],
      notes: json['notes'],
      createdAt: json['created_at'] ?? '',
      updatedAt: json['updated_at'] ?? '',
    );
  }

  static const Map<String, String> statusLabels = {
    'COLLECTED': 'Collected',
    'AT_LAUNDRY': 'At Laundry',
    'WASHING': 'Washing',
    'DRYING': 'Drying',
    'PRESSING': 'Pressing',
    'READY': 'Ready',
    'DELIVERED': 'Delivered',
    'MISSING': 'Missing',
    'DAMAGED': 'Damaged',
    'RETIRED': 'Retired',
  };

  static const Map<String, String> conditionLabels = {
    'NEW': 'New',
    'GOOD': 'Good',
    'FAIR': 'Fair',
    'POOR': 'Poor',
    'DAMAGED': 'Damaged',
    'RETIRED': 'Retired',
  };

  String get statusLabel => statusLabels[status] ?? status;
  String get conditionLabel => conditionLabels[condition] ?? condition;
}
