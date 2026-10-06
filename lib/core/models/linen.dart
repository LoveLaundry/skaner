import 'json.dart';

enum LinenStatus {
  inStock,
  atClient,
  collected,
  atLaundry,
  washing,
  drying,
  pressing,
  ready,
  delivered,
  missing,
  damaged,
  retired,
}

LinenStatus linenStatusFrom(String? raw) {
  switch ((raw ?? '').toUpperCase()) {
    case 'AT_CLIENT':
      return LinenStatus.atClient;
    case 'COLLECTED':
      return LinenStatus.collected;
    case 'AT_LAUNDRY':
      return LinenStatus.atLaundry;
    case 'WASHING':
      return LinenStatus.washing;
    case 'DRYING':
      return LinenStatus.drying;
    case 'PRESSING':
      return LinenStatus.pressing;
    case 'READY':
      return LinenStatus.ready;
    case 'DELIVERED':
      return LinenStatus.delivered;
    case 'MISSING':
      return LinenStatus.missing;
    case 'DAMAGED':
      return LinenStatus.damaged;
    case 'RETIRED':
      return LinenStatus.retired;
    default:
      return LinenStatus.inStock;
  }
}

const Map<LinenStatus, String> linenStatusLabels = {
  LinenStatus.inStock: 'In Stock',
  LinenStatus.atClient: 'At Client',
  LinenStatus.collected: 'Collected',
  LinenStatus.atLaundry: 'At Laundry',
  LinenStatus.washing: 'Washing',
  LinenStatus.drying: 'Drying',
  LinenStatus.pressing: 'Pressing',
  LinenStatus.ready: 'Ready',
  LinenStatus.delivered: 'Delivered',
  LinenStatus.missing: 'Missing',
  LinenStatus.damaged: 'Damaged',
  LinenStatus.retired: 'Retired',
};

/// Terminal and problem states are pulled out of the normal flow.
const List<LinenStatus> linenFlowStatuses = [
  LinenStatus.collected,
  LinenStatus.atLaundry,
  LinenStatus.washing,
  LinenStatus.drying,
  LinenStatus.pressing,
  LinenStatus.ready,
  LinenStatus.delivered,
];

const List<LinenStatus> linenAttentionStatuses = [
  LinenStatus.missing,
  LinenStatus.damaged,
  LinenStatus.retired,
];

class LinenCategory {
  const LinenCategory(this.value, this.label);
  final String value;
  final String label;

  static const List<LinenCategory> all = [
    LinenCategory('BEDSHEET', 'Bedsheet'),
    LinenCategory('PILLOWCASE', 'Pillowcase'),
    LinenCategory('TOWEL', 'Towel'),
    LinenCategory('DUVET_COVER', 'Duvet Cover'),
    LinenCategory('BATH_MAT', 'Bath Mat'),
    LinenCategory('UNIFORM', 'Uniform'),
    LinenCategory('TABLECLOTH', 'Tablecloth'),
    LinenCategory('NAPKIN', 'Napkin'),
    LinenCategory('ROBE', 'Robe'),
    LinenCategory('SLIPPER', 'Slipper'),
    LinenCategory('OTHER', 'Other'),
  ];

  static String labelOf(String? value) =>
      all.firstWhere((c) => c.value == value, orElse: () => all.last).label;
}

class LinenCondition {
  const LinenCondition(this.value, this.label);
  final String value;
  final String label;

  static const List<LinenCondition> all = [
    LinenCondition('NEW', 'New'),
    LinenCondition('GOOD', 'Good'),
    LinenCondition('FAIR', 'Fair'),
    LinenCondition('WORN', 'Worn'),
    LinenCondition('DAMAGED', 'Damaged'),
  ];

  static String labelOf(String? value) =>
      all.firstWhere((c) => c.value == value, orElse: () => all[1]).label;
}

class LinenScanAction {
  const LinenScanAction(this.value, this.label, this.targetStatus);
  final String value;
  final String label;

  /// The status a successful scan moves the piece into.
  final LinenStatus targetStatus;

  static const List<LinenScanAction> all = [
    LinenScanAction('collect', 'Collect', LinenStatus.collected),
    LinenScanAction('receive', 'Receive', LinenStatus.atLaundry),
    LinenScanAction('start_wash', 'Start Wash', LinenStatus.washing),
    LinenScanAction('complete_wash', 'Complete Wash', LinenStatus.drying),
    LinenScanAction('press', 'Press', LinenStatus.pressing),
    LinenScanAction('ready', 'Ready', LinenStatus.ready),
    LinenScanAction('deliver', 'Deliver', LinenStatus.delivered),
    LinenScanAction('mark_missing', 'Mark Missing', LinenStatus.missing),
    LinenScanAction('mark_damaged', 'Mark Damaged', LinenStatus.damaged),
    LinenScanAction('retire', 'Retire', LinenStatus.retired),
  ];

  static LinenScanAction? byValue(String? value) {
    for (final a in all) {
      if (a.value == value) return a;
    }
    return null;
  }
}

class LinenItem {
  const LinenItem({
    required this.id,
    required this.linenId,
    required this.category,
    required this.itemType,
    required this.clientName,
    required this.status,
    required this.condition,
    required this.washCount,
    this.description,
    this.size,
    this.color,
    this.department,
    this.location,
    this.lastWashedDate,
    this.lastScannedDate,
    this.retirementDate,
    this.notes,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String linenId;
  final String category;
  final String itemType;
  final String? description;
  final String? size;
  final String? color;
  final String clientName;
  final String? department;
  final LinenStatus status;
  final String condition;
  final String? location;
  final int washCount;
  final String? lastWashedDate;
  final String? lastScannedDate;
  final String? retirementDate;
  final String? notes;
  final String? createdAt;
  final String? updatedAt;

  String get statusLabel => linenStatusLabels[status] ?? 'In Stock';
  String get conditionLabel => LinenCondition.labelOf(condition);
  String get categoryLabel => LinenCategory.labelOf(category);

  bool get needsAttention =>
      status == LinenStatus.missing || status == LinenStatus.damaged;
  bool get isRetired => status == LinenStatus.retired;

  /// What a scan is allowed to do next, based on where the piece is now.
  List<LinenScanAction> get allowedActions {
    switch (status) {
      case LinenStatus.inStock:
      case LinenStatus.atClient:
        return const [
          LinenScanAction('collect', 'Collect', LinenStatus.collected),
          LinenScanAction('mark_missing', 'Mark Missing', LinenStatus.missing),
          LinenScanAction('retire', 'Retire', LinenStatus.retired),
        ];
      case LinenStatus.collected:
        return const [
          LinenScanAction('receive', 'Receive', LinenStatus.atLaundry),
          LinenScanAction('mark_missing', 'Mark Missing', LinenStatus.missing),
        ];
      case LinenStatus.atLaundry:
        return const [
          LinenScanAction('start_wash', 'Start Wash', LinenStatus.washing),
          LinenScanAction('mark_damaged', 'Mark Damaged', LinenStatus.damaged),
        ];
      case LinenStatus.washing:
        return const [
          LinenScanAction('complete_wash', 'Complete Wash', LinenStatus.drying),
          LinenScanAction('mark_damaged', 'Mark Damaged', LinenStatus.damaged),
        ];
      case LinenStatus.drying:
        return const [
          LinenScanAction('press', 'Press', LinenStatus.pressing),
          LinenScanAction('mark_damaged', 'Mark Damaged', LinenStatus.damaged),
        ];
      case LinenStatus.pressing:
        return const [
          LinenScanAction('ready', 'Ready', LinenStatus.ready),
          LinenScanAction('mark_damaged', 'Mark Damaged', LinenStatus.damaged),
        ];
      case LinenStatus.ready:
        return const [
          LinenScanAction('deliver', 'Deliver', LinenStatus.delivered),
          LinenScanAction('mark_damaged', 'Mark Damaged', LinenStatus.damaged),
        ];
      case LinenStatus.delivered:
        return const [
          LinenScanAction('collect', 'Collect', LinenStatus.collected),
        ];
      case LinenStatus.missing:
        return const [
          LinenScanAction('collect', 'Collect', LinenStatus.collected),
          LinenScanAction('receive', 'Receive', LinenStatus.atLaundry),
        ];
      case LinenStatus.damaged:
        return const [
          LinenScanAction('start_wash', 'Re-wash', LinenStatus.washing),
          LinenScanAction('retire', 'Retire', LinenStatus.retired),
        ];
      case LinenStatus.retired:
        return const [];
    }
  }

  factory LinenItem.fromJson(Map<String, dynamic> j) => LinenItem(
        id: asString(j['id'] ?? j['_id'] ?? j['linen_id']),
        linenId: asString(j['linen_id']),
        category: asString(j['category'], 'OTHER'),
        itemType: asString(j['item_type']),
        description: asStringOrNull(j['description']),
        size: asStringOrNull(j['size']),
        color: asStringOrNull(j['color']),
        clientName: asString(j['client_name']),
        department: asStringOrNull(j['department']),
        status: linenStatusFrom(asStringOrNull(j['status'])),
        condition: asString(j['condition'], 'GOOD'),
        location: asStringOrNull(j['location']),
        washCount: asInt(j['wash_count']),
        lastWashedDate: asStringOrNull(j['last_washed_date']),
        lastScannedDate: asStringOrNull(j['last_scanned_date']),
        retirementDate: asStringOrNull(j['retirement_date']),
        notes: asStringOrNull(j['notes']),
        createdAt: asStringOrNull(j['created_at']),
        updatedAt: asStringOrNull(j['updated_at']),
      );
}

class LinenEvent {
  const LinenEvent({
    required this.id,
    required this.linenId,
    required this.action,
    required this.toStatus,
    required this.timestamp,
    this.fromStatus,
    this.location,
    this.user,
    this.relatedOrder,
    this.notes,
  });

  final String id;
  final String linenId;
  final String action;
  final String? fromStatus;
  final String toStatus;
  final String? location;
  final String? user;
  final String? relatedOrder;
  final String? notes;
  final String timestamp;

  String get fromLabel => linenStatusLabels[linenStatusFrom(fromStatus)] ?? '—';
  String get toLabel => linenStatusLabels[linenStatusFrom(toStatus)] ?? toStatus;

  factory LinenEvent.fromJson(Map<String, dynamic> j) => LinenEvent(
        id: asString(j['id'] ?? j['_id']),
        linenId: asString(j['linen_id']),
        action: asString(j['action']),
        fromStatus: asStringOrNull(j['from_status']),
        toStatus: asString(j['to_status']),
        location: asStringOrNull(j['location']),
        user: asStringOrNull(j['user']),
        relatedOrder: asStringOrNull(j['related_order']),
        notes: asStringOrNull(j['notes']),
        timestamp: asString(j['timestamp'] ?? j['created_at']),
      );
}

class LinenStats {
  const LinenStats({
    this.total = 0,
    this.inStock = 0,
    this.atClient = 0,
    this.collected = 0,
    this.atLaundry = 0,
    this.washing = 0,
    this.drying = 0,
    this.pressing = 0,
    this.ready = 0,
    this.delivered = 0,
    this.missing = 0,
    this.damaged = 0,
    this.retired = 0,
    this.totalWashCycles = 0,
    this.recentlyScanned = 0,
  });

  final int total;
  final int inStock;
  final int atClient;
  final int collected;
  final int atLaundry;
  final int washing;
  final int drying;
  final int pressing;
  final int ready;
  final int delivered;
  final int missing;
  final int damaged;
  final int retired;
  final int totalWashCycles;
  final int recentlyScanned;

  /// Everything a piece can be in, in workflow order.
  Map<LinenStatus, int> get byStatus => {
        LinenStatus.inStock: inStock,
        LinenStatus.atClient: atClient,
        LinenStatus.collected: collected,
        LinenStatus.atLaundry: atLaundry,
        LinenStatus.washing: washing,
        LinenStatus.drying: drying,
        LinenStatus.pressing: pressing,
        LinenStatus.ready: ready,
        LinenStatus.delivered: delivered,
        LinenStatus.missing: missing,
        LinenStatus.damaged: damaged,
        LinenStatus.retired: retired,
      };

  int get inFlow =>
      collected + atLaundry + washing + drying + pressing + ready;
  int get needsAttention => missing + damaged;

  factory LinenStats.fromJson(Map<String, dynamic> j) => LinenStats(
        total: asInt(j['total']),
        inStock: asInt(j['in_stock']),
        atClient: asInt(j['at_client']),
        collected: asInt(j['collected']),
        atLaundry: asInt(j['at_laundry']),
        washing: asInt(j['washing']),
        drying: asInt(j['drying']),
        pressing: asInt(j['pressing']),
        ready: asInt(j['ready']),
        delivered: asInt(j['delivered']),
        missing: asInt(j['missing']),
        damaged: asInt(j['damaged']),
        retired: asInt(j['retired']),
        totalWashCycles: asInt(j['total_wash_cycles']),
        recentlyScanned: asInt(j['recently_scanned']),
      );
}
