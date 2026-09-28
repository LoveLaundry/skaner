import 'common.dart';
import 'json.dart';

enum GatePassStatus {
  received,
  processing,
  readyForDelivery,
  partiallyDelivered,
  delivered,
  cancelled,
}

GatePassStatus gatePassStatusFrom(String? raw) {
  switch ((raw ?? '').toUpperCase().replaceAll('-', '_')) {
    case 'PROCESSING':
      return GatePassStatus.processing;
    case 'READY_FOR_DELIVERY':
      return GatePassStatus.readyForDelivery;
    case 'PARTIALLY_DELIVERED':
      return GatePassStatus.partiallyDelivered;
    case 'DELIVERED':
      return GatePassStatus.delivered;
    case 'CANCELLED':
      return GatePassStatus.cancelled;
    default:
      return GatePassStatus.received;
  }
}

const Map<GatePassStatus, String> gatePassStatusLabels = {
  GatePassStatus.received: 'Received',
  GatePassStatus.processing: 'Processing',
  GatePassStatus.readyForDelivery: 'Ready for Delivery',
  GatePassStatus.partiallyDelivered: 'Partially Delivered',
  GatePassStatus.delivered: 'Delivered',
  GatePassStatus.cancelled: 'Cancelled',
};

/// The statuses a gate pass may be moved to by hand. Partially-delivered and
/// delivered are derived from the delivery record, not set directly.
const List<GatePassStatus> gatePassManualTransitions = [
  GatePassStatus.received,
  GatePassStatus.processing,
  GatePassStatus.readyForDelivery,
  GatePassStatus.cancelled,
];

class GatePassItem {
  const GatePassItem({
    required this.itemName,
    required this.clientQty,
    required this.receivedQty,
    this.category,
    this.specification,
    this.mismatchReason,
    this.mismatchNotes,
    this.rewashed = false,
  });

  final String itemName;
  final String? category;
  final String? specification;
  final double clientQty;
  final double receivedQty;
  final String? mismatchReason;
  final String? mismatchNotes;

  /// Flagged "rewashed, not billed" at receiving — excluded from billing.
  final bool rewashed;

  /// Client said X, laundry counted Y. Signed so the UI can show the direction.
  double get difference => receivedQty - clientQty;
  bool get hasMismatch => difference != 0;
  bool get isShort => difference < 0;
  bool get isOver => difference > 0;

  /// `name||spec` — the key the server composes balances against.
  String get itemKey => specification == null || specification!.isEmpty
      ? itemName
      : '$itemName||${specification!}';

  String get displayName =>
      (specification == null || specification!.isEmpty) ? itemName : '$itemName · $specification';

  factory GatePassItem.fromJson(Map<String, dynamic> j) => GatePassItem(
        itemName: asString(j['item_name']),
        category: asStringOrNull(j['category']),
        specification: asStringOrNull(j['specification']),
        clientQty: asDouble(j['client_qty']),
        receivedQty: asDouble(j['received_qty']),
        mismatchReason: asStringOrNull(j['mismatch_reason']),
        mismatchNotes: asStringOrNull(j['mismatch_notes']),
        rewashed: asBool(j['rewashed']),
      );

  Map<String, dynamic> toJson() => {
        'item_name': itemName,
        if (category != null) 'category': category,
        if (specification != null) 'specification': specification,
        'client_qty': clientQty,
        'received_qty': receivedQty,
        if (mismatchReason != null) 'mismatch_reason': mismatchReason,
        if (mismatchNotes != null) 'mismatch_notes': mismatchNotes,
        if (rewashed) 'rewashed': true,
      };
}

/// A legacy "closed by hand" record on a pass that has no delivery rows.
class MarkedDeliveredInfo {
  const MarkedDeliveredInfo({
    required this.note,
    this.deliveredDate,
    this.userId,
    this.at,
  });

  final String note;
  final String? deliveredDate;
  final String? userId;
  final String? at;

  factory MarkedDeliveredInfo.fromJson(Map<String, dynamic> j) =>
      MarkedDeliveredInfo(
        note: asString(j['note']),
        deliveredDate: asStringOrNull(j['delivered_date']),
        userId: asStringOrNull(j['user_id']),
        at: asStringOrNull(j['at']),
      );
}

class GatePass {
  const GatePass({
    required this.id,
    required this.gatePassNumber,
    required this.clientName,
    required this.receivingDate,
    required this.receivedBy,
    required this.items,
    required this.status,
    this.notes,
    this.quotationId,
    this.markedDelivered,
    this.createdAt,
    this.updatedAt,
    this.verification,
  });

  final String id;
  final String gatePassNumber;
  final String clientName;
  final String receivingDate;
  final String receivedBy;
  final List<GatePassItem> items;
  final GatePassStatus status;
  final String? notes;
  final String? quotationId;
  final MarkedDeliveredInfo? markedDelivered;
  final String? createdAt;
  final String? updatedAt;
  final Verification? verification;

  String get statusLabel => gatePassStatusLabels[status] ?? 'Received';

  bool get isDelivered => status == GatePassStatus.delivered;
  bool get isCancelled => status == GatePassStatus.cancelled;

  /// A pass closed by hand with no delivery rows: the UI has to warn about it
  /// because no quantities were ever recorded as going out.
  bool get isLegacyClosed =>
      markedDelivered != null && status == GatePassStatus.delivered;

  /// Once anything has moved out, the received quantities are history.
  bool get hasMovement =>
      status == GatePassStatus.delivered ||
      status == GatePassStatus.partiallyDelivered;

  bool get canEdit => !isDelivered && !isCancelled && !hasMovement;

  bool get hasMismatches => items.any((i) => i.hasMismatch);

  double get totalClientQty =>
      items.fold(0.0, (a, i) => a + i.clientQty);
  double get totalReceivedQty =>
      items.fold(0.0, (a, i) => a + i.receivedQty);

  factory GatePass.fromJson(Map<String, dynamic> j) {
    final md = j['marked_delivered'];
    return GatePass(
      id: asString(j['id'] ?? j['_id']),
      gatePassNumber: asString(j['gate_pass_number']),
      clientName: asString(j['client_name']),
      receivingDate: asString(j['receiving_date']),
      receivedBy: asString(j['received_by']),
      items: asMapList(j['items']).map(GatePassItem.fromJson).toList(),
      status: gatePassStatusFrom(asStringOrNull(j['status'])),
      notes: asStringOrNull(j['notes']),
      quotationId: asStringOrNull(j['quotation_id']),
      markedDelivered: md is Map && md.isNotEmpty
          ? MarkedDeliveredInfo.fromJson(asMap(md))
          : null,
      createdAt: asStringOrNull(j['created_at']),
      updatedAt: asStringOrNull(j['updated_at']),
      verification: Verification.tryParse(j['verification']),
    );
  }
}

/// One line of a gate pass's server-computed balance.
///
/// The app never derives these numbers locally — every screen renders exactly
/// what the server returned so two screens can never disagree.
class GatePassBalanceItem {
  const GatePassBalanceItem({
    required this.itemKey,
    required this.itemName,
    required this.specification,
    required this.category,
    required this.rewashed,
    required this.expectedQty,
    required this.receivedQty,
    required this.deliveredQty,
    required this.effectiveDeliveredQty,
    required this.returnedBackQty,
    required this.outstandingDeliveryQty,
    required this.notReceivedQty,
    required this.extraReceivedQty,
    required this.clientCountedQty,
    required this.discrepancyQty,
    required this.hasCount,
    required this.flags,
  });

  final String itemKey;
  final String itemName;
  final String specification;
  final String category;
  final bool rewashed;
  final double expectedQty;
  final double receivedQty;
  final double deliveredQty;
  final double effectiveDeliveredQty;
  final double returnedBackQty;
  final double outstandingDeliveryQty;
  final double notReceivedQty;
  final double extraReceivedQty;
  final double? clientCountedQty;
  final double discrepancyQty;
  final bool hasCount;
  final List<String> flags;

  String get displayName =>
      specification.isEmpty ? itemName : '$itemName · $specification';

  factory GatePassBalanceItem.fromJson(Map<String, dynamic> j) =>
      GatePassBalanceItem(
        itemKey: asString(j['item_key']),
        itemName: asString(j['item_name']),
        specification: asString(j['specification']),
        category: asString(j['category']),
        rewashed: asBool(j['rewashed']),
        expectedQty: asDouble(j['expected_qty']),
        receivedQty: asDouble(j['received_qty']),
        deliveredQty: asDouble(j['delivered_qty']),
        effectiveDeliveredQty: asDouble(j['effective_delivered_qty']),
        returnedBackQty: asDouble(j['returned_back_qty']),
        outstandingDeliveryQty: asDouble(j['outstanding_delivery_qty']),
        notReceivedQty: asDouble(j['not_received_qty']),
        extraReceivedQty: asDouble(j['extra_received_qty']),
        clientCountedQty: j['client_counted_qty'] == null
            ? null
            : asDouble(j['client_counted_qty']),
        discrepancyQty: asDouble(j['discrepancy_qty']),
        hasCount: asBool(j['has_count']),
        flags: (j['flags'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      );
}

class BalanceTotals {
  const BalanceTotals({
    this.expectedQty = 0,
    this.receivedQty = 0,
    this.deliveredQty = 0,
    this.effectiveDeliveredQty = 0,
    this.returnedBackQty = 0,
    this.outstandingDeliveryQty = 0,
    this.notReceivedQty = 0,
    this.clientCountedQty = 0,
    this.discrepancyQty = 0,
  });

  final double expectedQty;
  final double receivedQty;
  final double deliveredQty;
  final double effectiveDeliveredQty;
  final double returnedBackQty;
  final double outstandingDeliveryQty;
  final double notReceivedQty;
  final double clientCountedQty;
  final double discrepancyQty;

  factory BalanceTotals.fromJson(Map<String, dynamic> j) => BalanceTotals(
        expectedQty: asDouble(j['expected_qty']),
        receivedQty: asDouble(j['received_qty']),
        deliveredQty: asDouble(j['delivered_qty']),
        effectiveDeliveredQty: asDouble(j['effective_delivered_qty']),
        returnedBackQty: asDouble(j['returned_back_qty']),
        outstandingDeliveryQty: asDouble(j['outstanding_delivery_qty']),
        notReceivedQty: asDouble(j['not_received_qty']),
        clientCountedQty: asDouble(j['client_counted_qty']),
        discrepancyQty: asDouble(j['discrepancy_qty']),
      );

  static const empty = BalanceTotals();
}

class GatePassBalance {
  const GatePassBalance({
    required this.gatePassId,
    required this.items,
    required this.totals,
    this.gatePassNumber,
    this.clientName,
    this.receivingDate,
    this.status,
    this.derivedStatus,
    this.statusStale = false,
    this.markedDelivered = false,
    this.flags = const [],
  });

  final String gatePassId;
  final String? gatePassNumber;
  final String? clientName;
  final String? receivingDate;
  final String? status;
  final String? derivedStatus;
  final bool statusStale;
  final bool markedDelivered;
  final List<GatePassBalanceItem> items;
  final BalanceTotals totals;
  final List<String> flags;

  factory GatePassBalance.fromJson(Map<String, dynamic> j) => GatePassBalance(
        gatePassId: asString(j['gate_pass_id']),
        gatePassNumber: asStringOrNull(j['gate_pass_number']),
        clientName: asStringOrNull(j['client_name']),
        receivingDate: asStringOrNull(j['receiving_date']),
        status: asStringOrNull(j['status']),
        derivedStatus: asStringOrNull(j['derived_status']),
        statusStale: asBool(j['status_stale']),
        markedDelivered: asBool(j['marked_delivered']),
        items: asMapList(j['items']).map(GatePassBalanceItem.fromJson).toList(),
        totals: BalanceTotals.fromJson(asMap(j['totals'])),
        flags:
            (j['flags'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      );
}

class DeliveryItem {
  const DeliveryItem({
    required this.itemName,
    required this.quantity,
    this.specification,
    this.gatePassId,
    this.clientCountedQty,
    this.discrepancy,
    this.mismatchReason,
    this.mismatchNotes,
  });

  final String itemName;
  final String? specification;
  final double quantity;

  /// Required on a write: a delivery may draw from several gate passes, so the
  /// source of every line has to be explicit.
  final String? gatePassId;
  final double? clientCountedQty;
  final double? discrepancy;
  final String? mismatchReason;
  final String? mismatchNotes;

  String get displayName =>
      (specification == null || specification!.isEmpty) ? itemName : '$itemName · $specification';

  factory DeliveryItem.fromJson(Map<String, dynamic> j) => DeliveryItem(
        itemName: asString(j['item_name']),
        specification: asStringOrNull(j['specification']),
        quantity: asDouble(j['quantity']),
        gatePassId: asStringOrNull(j['gate_pass_id']),
        clientCountedQty: j['client_counted_qty'] == null
            ? null
            : asDouble(j['client_counted_qty']),
        discrepancy: j['discrepancy'] == null ? null : asDouble(j['discrepancy']),
        mismatchReason: asStringOrNull(j['mismatch_reason']),
        mismatchNotes: asStringOrNull(j['mismatch_notes']),
      );

  Map<String, dynamic> toJson() => {
        'item_name': itemName,
        if (specification != null) 'specification': specification,
        'quantity': quantity,
        if (gatePassId != null) 'gate_pass_id': gatePassId,
        if (clientCountedQty != null) 'client_counted_qty': clientCountedQty,
        if (mismatchReason != null) 'mismatch_reason': mismatchReason,
        if (mismatchNotes != null) 'mismatch_notes': mismatchNotes,
      };
}

class DeliveryCorrectionChange {
  const DeliveryCorrectionChange({
    required this.gatePassId,
    required this.itemName,
    required this.specification,
    required this.originalQuantity,
    required this.correctedQuantity,
    required this.delta,
  });

  final String gatePassId;
  final String itemName;
  final String specification;
  final double originalQuantity;
  final double correctedQuantity;
  final double delta;

  factory DeliveryCorrectionChange.fromJson(Map<String, dynamic> j) =>
      DeliveryCorrectionChange(
        gatePassId: asString(j['gate_pass_id']),
        itemName: asString(j['item_name']),
        specification: asString(j['specification']),
        originalQuantity: asDouble(j['original_quantity']),
        correctedQuantity: asDouble(j['corrected_quantity']),
        delta: asDouble(j['delta']),
      );
}

class DeliveryCorrectionRecord {
  const DeliveryCorrectionRecord({
    required this.correctedAt,
    required this.correctedBy,
    required this.reason,
    required this.changes,
    this.correctedById,
    this.notes,
  });

  final String correctedAt;
  final String correctedBy;
  final String? correctedById;
  final String reason;
  final String? notes;
  final List<DeliveryCorrectionChange> changes;

  factory DeliveryCorrectionRecord.fromJson(Map<String, dynamic> j) =>
      DeliveryCorrectionRecord(
        correctedAt: asString(j['corrected_at']),
        correctedBy: asString(j['corrected_by']),
        correctedById: asStringOrNull(j['corrected_by_id']),
        reason: asString(j['reason']),
        notes: asStringOrNull(j['notes']),
        changes: asMapList(j['changes'])
            .map(DeliveryCorrectionChange.fromJson)
            .toList(),
      );
}

/// A gate pass a delivery touched, with the resulting balance.
class SourceGatePass {
  const SourceGatePass({
    required this.gatePassId,
    required this.totals,
    this.gatePassNumber,
    this.clientName,
    this.status,
    this.derivedStatus,
    this.items = const [],
    this.flags = const [],
  });

  final String gatePassId;
  final String? gatePassNumber;
  final String? clientName;
  final String? status;
  final String? derivedStatus;
  final List<GatePassBalanceItem> items;
  final BalanceTotals totals;
  final List<String> flags;

  factory SourceGatePass.fromJson(Map<String, dynamic> j) => SourceGatePass(
        gatePassId: asString(j['gate_pass_id']),
        gatePassNumber: asStringOrNull(j['gate_pass_number']),
        clientName: asStringOrNull(j['client_name']),
        status: asStringOrNull(j['status']),
        derivedStatus: asStringOrNull(j['derived_status']),
        items: asMapList(j['items']).map(GatePassBalanceItem.fromJson).toList(),
        totals: BalanceTotals.fromJson(asMap(j['totals'])),
        flags: (j['flags'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      );
}

class Delivery {
  const Delivery({
    required this.id,
    required this.clientName,
    required this.deliveryDate,
    required this.deliveredBy,
    required this.receivedBy,
    required this.items,
    required this.status,
    this.gatePassId = '',
    this.sourceGatePassIds = const [],
    this.notes,
    this.corrections = const [],
    this.sourceGatePasses = const [],
    this.cancelledAt,
    this.cancelledBy,
    this.cancelledReason,
    this.createdAt,
    this.updatedAt,
    this.verification,
  });

  final String id;

  /// Legacy single source; prefer [sourceGatePassIds] or a line's own gate pass.
  final String gatePassId;
  final List<String> sourceGatePassIds;
  final String clientName;
  final String deliveryDate;
  final String deliveredBy;
  final String receivedBy;
  final List<DeliveryItem> items;
  final String status;
  final String? notes;
  final List<DeliveryCorrectionRecord> corrections;
  final List<SourceGatePass> sourceGatePasses;
  final String? cancelledAt;
  final String? cancelledBy;
  final String? cancelledReason;
  final String? createdAt;
  final String? updatedAt;
  final Verification? verification;

  bool get isCancelled => status.toUpperCase() == 'CANCELLED';
  bool get isDelivered => status.toUpperCase() == 'DELIVERED';
  bool get hasCorrections => corrections.isNotEmpty;
  double get totalPieces => items.fold(0.0, (a, i) => a + i.quantity);

  /// A delivery may never span two hotels — the server rejects it, so the
  /// client blocks it before the round trip.
  bool get spansMultipleHotels => sourceGatePassIds.length > 1 &&
      sourceGatePasses.map((s) => s.clientName).whereType<String>().toSet().length > 1;

  factory Delivery.fromJson(Map<String, dynamic> j) => Delivery(
        id: asString(j['id'] ?? j['_id']),
        gatePassId: asString(j['gate_pass_id']),
        sourceGatePassIds: (j['source_gate_pass_ids'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        clientName: asString(j['client_name']),
        deliveryDate: asString(j['delivery_date']),
        deliveredBy: asString(j['delivered_by']),
        receivedBy: asString(j['received_by']),
        items: asMapList(j['items']).map(DeliveryItem.fromJson).toList(),
        status: asString(j['status'], 'RECORDED'),
        notes: asStringOrNull(j['notes']),
        corrections: asMapList(j['corrections'])
            .map(DeliveryCorrectionRecord.fromJson)
            .toList(),
        sourceGatePasses:
            asMapList(j['source_gate_passes']).map(SourceGatePass.fromJson).toList(),
        cancelledAt: asStringOrNull(j['cancelled_at']),
        cancelledBy: asStringOrNull(j['cancelled_by']),
        cancelledReason: asStringOrNull(j['cancelled_reason']),
        createdAt: asStringOrNull(j['created_at']),
        updatedAt: asStringOrNull(j['updated_at']),
        verification: Verification.tryParse(j['verification']),
      );
}

class DeliveryBalance {
  const DeliveryBalance({
    required this.delivery,
    required this.originalItems,
    required this.corrections,
    required this.sourceGatePasses,
  });

  final Delivery delivery;
  final List<DeliveryItem> originalItems;
  final List<DeliveryCorrectionRecord> corrections;
  final List<SourceGatePass> sourceGatePasses;

  factory DeliveryBalance.fromJson(Map<String, dynamic> j) => DeliveryBalance(
        delivery: Delivery.fromJson(asMap(j['delivery'])),
        originalItems: asMapList(j['original_items']).map(DeliveryItem.fromJson).toList(),
        corrections: asMapList(j['corrections'])
            .map(DeliveryCorrectionRecord.fromJson)
            .toList(),
        sourceGatePasses:
            asMapList(j['source_gate_passes']).map(SourceGatePass.fromJson).toList(),
      );
}

class AvailabilityItem {
  const AvailabilityItem({
    required this.itemName,
    required this.specification,
    required this.expectedQty,
    required this.receivedQty,
    required this.deliveredQty,
    required this.returnedQty,
    required this.availableQty,
    this.category,
    this.rewashed = false,
    this.flags = const [],
  });

  final String itemName;
  final String specification;
  final String? category;
  final double expectedQty;
  final double receivedQty;
  final double deliveredQty;
  final double returnedQty;
  final double availableQty;
  final bool rewashed;
  final List<String> flags;

  String get displayName =>
      specification.isEmpty ? itemName : '$itemName · $specification';

  factory AvailabilityItem.fromJson(Map<String, dynamic> j) => AvailabilityItem(
        itemName: asString(j['item_name']),
        specification: asString(j['specification']),
        category: asStringOrNull(j['category']),
        expectedQty: asDouble(j['expected_qty']),
        receivedQty: asDouble(j['received_qty']),
        deliveredQty: asDouble(j['delivered_qty']),
        returnedQty: asDouble(j['returned_qty']),
        availableQty: asDouble(j['available_qty']),
        rewashed: asBool(j['rewashed']),
        flags: (j['flags'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      );
}

class AvailabilityGatePass {
  const AvailabilityGatePass({
    required this.gatePassId,
    required this.gatePassNumber,
    required this.clientName,
    required this.receivingDate,
    required this.status,
    required this.derivedStatus,
    required this.totalReceivedQty,
    required this.totalDeliveredQty,
    required this.totalAvailableQty,
    required this.items,
    required this.deliverableItems,
  });

  final String gatePassId;
  final String gatePassNumber;
  final String clientName;
  final String receivingDate;
  final String status;
  final String derivedStatus;
  final double totalReceivedQty;
  final double totalDeliveredQty;
  final double totalAvailableQty;
  final List<AvailabilityItem> items;
  final List<AvailabilityItem> deliverableItems;

  factory AvailabilityGatePass.fromJson(Map<String, dynamic> j) =>
      AvailabilityGatePass(
        gatePassId: asString(j['gate_pass_id']),
        gatePassNumber: asString(j['gate_pass_number']),
        clientName: asString(j['client_name']),
        receivingDate: asString(j['receiving_date']),
        status: asString(j['status']),
        derivedStatus: asString(j['derived_status']),
        totalReceivedQty: asDouble(j['total_received_qty']),
        totalDeliveredQty: asDouble(j['total_delivered_qty']),
        totalAvailableQty: asDouble(j['total_available_qty']),
        items: asMapList(j['items']).map(AvailabilityItem.fromJson).toList(),
        deliverableItems:
            asMapList(j['deliverable_items']).map(AvailabilityItem.fromJson).toList(),
      );
}

class AvailabilityResponse {
  const AvailabilityResponse({
    required this.gatePasses,
    required this.totalAvailableQty,
    this.clientName,
  });

  final String? clientName;
  final List<AvailabilityGatePass> gatePasses;
  final double totalAvailableQty;

  factory AvailabilityResponse.fromJson(Map<String, dynamic> j) =>
      AvailabilityResponse(
        clientName: asStringOrNull(j['client_name']),
        gatePasses: asMapList(j['gate_passes'])
            .map(AvailabilityGatePass.fromJson)
            .toList(),
        totalAvailableQty: asDouble(j['total_available_qty']),
      );
}

class GatePassDeliveryRef {
  const GatePassDeliveryRef({
    required this.id,
    required this.items,
    this.deliveryDate,
    this.status,
    this.deliveredBy,
  });

  final String id;
  final String? deliveryDate;
  final String? status;
  final String? deliveredBy;
  final List<DeliveryItem> items;

  factory GatePassDeliveryRef.fromJson(Map<String, dynamic> j) =>
      GatePassDeliveryRef(
        id: asString(j['id']),
        deliveryDate: asStringOrNull(j['delivery_date']),
        status: asStringOrNull(j['status']),
        deliveredBy: asStringOrNull(j['delivered_by']),
        items: asMapList(j['items']).map(DeliveryItem.fromJson).toList(),
      );
}

class GatePassDeliveries {
  const GatePassDeliveries({
    required this.gatePassId,
    required this.deliveries,
    this.gatePassNumber,
    this.perGatePass = const [],
  });

  final String gatePassId;
  final String? gatePassNumber;
  final List<Delivery> deliveries;
  final List<SourceGatePass> perGatePass;

  factory GatePassDeliveries.fromJson(Map<String, dynamic> j) =>
      GatePassDeliveries(
        gatePassId: asString(j['gate_pass_id']),
        gatePassNumber: asStringOrNull(j['gate_pass_number']),
        deliveries:
            asMapList(j['deliveries']).map(Delivery.fromJson).toList(),
        perGatePass: asMapList(j['per_gate_pass']).map(SourceGatePass.fromJson).toList(),
      );
}

enum DispatchStatus { scheduled, assigned, enRoute, completed, cancelled }

DispatchStatus dispatchStatusFrom(String? raw) {
  switch ((raw ?? '').toUpperCase()) {
    case 'ASSIGNED':
      return DispatchStatus.assigned;
    case 'EN_ROUTE':
      return DispatchStatus.enRoute;
    case 'COMPLETED':
      return DispatchStatus.completed;
    case 'CANCELLED':
      return DispatchStatus.cancelled;
    default:
      return DispatchStatus.scheduled;
  }
}

const Map<DispatchStatus, String> dispatchStatusLabels = {
  DispatchStatus.scheduled: 'Scheduled',
  DispatchStatus.assigned: 'Assigned',
  DispatchStatus.enRoute: 'En Route',
  DispatchStatus.completed: 'Completed',
  DispatchStatus.cancelled: 'Cancelled',
};

class DispatchJob {
  const DispatchJob({
    required this.id,
    required this.jobType,
    required this.clientName,
    required this.status,
    this.orderId,
    this.address,
    this.contactName,
    this.contactPhone,
    this.scheduledAt,
    this.assignedTo,
    this.latitude,
    this.longitude,
    this.notes,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String jobType;
  final String? orderId;
  final String clientName;
  final String? address;
  final String? contactName;
  final String? contactPhone;
  final String? scheduledAt;
  final DispatchStatus status;
  final String? assignedTo;
  final double? latitude;
  final double? longitude;
  final String? notes;
  final String? createdAt;
  final String? updatedAt;

  String get statusLabel => dispatchStatusLabels[status] ?? 'Scheduled';
  String get typeLabel => jobType.toLowerCase() == 'pickup' ? 'Pickup' : 'Delivery';
  bool get isPickup => jobType.toLowerCase() == 'pickup';

  factory DispatchJob.fromJson(Map<String, dynamic> j) => DispatchJob(
        id: asString(j['id'] ?? j['_id']),
        jobType: asString(j['job_type'], 'delivery'),
        orderId: asStringOrNull(j['order_id']),
        clientName: asString(j['client_name']),
        address: asStringOrNull(j['address']),
        contactName: asStringOrNull(j['contact_name']),
        contactPhone: asStringOrNull(j['contact_phone']),
        scheduledAt: asStringOrNull(j['scheduled_at']),
        status: dispatchStatusFrom(asStringOrNull(j['status'])),
        assignedTo: asStringOrNull(j['assigned_to']),
        latitude: j['latitude'] == null ? null : asDouble(j['latitude']),
        longitude: j['longitude'] == null ? null : asDouble(j['longitude']),
        notes: asStringOrNull(j['notes']),
        createdAt: asStringOrNull(j['created_at']),
        updatedAt: asStringOrNull(j['updated_at']),
      );
}

class RoutePlan {
  const RoutePlan({required this.order, required this.stops});

  final List<String> order;
  final List<DispatchJob> stops;

  factory RoutePlan.fromJson(Map<String, dynamic> j) => RoutePlan(
        order: (j['order'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        stops: asMapList(j['stops']).map(DispatchJob.fromJson).toList(),
      );
}

enum ReturnStatus { pending, received, processed }

ReturnStatus returnStatusFrom(String? raw) {
  switch ((raw ?? '').toUpperCase()) {
    case 'RECEIVED':
      return ReturnStatus.received;
    case 'PROCESSED':
      return ReturnStatus.processed;
    default:
      return ReturnStatus.pending;
  }
}

const Map<ReturnStatus, String> returnStatusLabels = {
  ReturnStatus.pending: 'Pending',
  ReturnStatus.received: 'Received',
  ReturnStatus.processed: 'Processed',
};

const List<String> returnReasons = [
  'WRONG_ITEM',
  'DAMAGED',
  'MISSING',
  'OTHER',
];

const List<String> returnConditions = ['GOOD', 'DAMAGED', 'STAINED', 'LOST'];

const List<String> returnActions = [
  'RECEIVE_BACK',
  'RE_WASH',
  'DISCARD',
  'COMPENSATE',
];

const List<String> billAdjustmentTypes = [
  'NONE',
  'QUANTITY_REDUCE',
  'AMOUNT_REDUCE',
  'COMPENSATE',
];

class ReturnItem {
  const ReturnItem({
    required this.itemName,
    required this.returnedQty,
    required this.reason,
    required this.condition,
    required this.action,
    this.specification,
    this.notes,
    this.resendStatus,
    this.resentAt,
  });

  final String itemName;
  final String? specification;
  final double returnedQty;
  final String reason;
  final String condition;
  final String action;
  final String? notes;
  final String? resendStatus;
  final String? resentAt;

  bool get isResent => resendStatus?.toUpperCase() == 'SENT';

  String get displayName =>
      (specification == null || specification!.isEmpty) ? itemName : '$itemName · $specification';

  factory ReturnItem.fromJson(Map<String, dynamic> j) => ReturnItem(
        itemName: asString(j['item_name']),
        specification: asStringOrNull(j['specification']),
        returnedQty: asDouble(j['returned_qty']),
        reason: asString(j['reason'], 'OTHER'),
        condition: asString(j['condition'], 'GOOD'),
        action: asString(j['action'], 'RECEIVE_BACK'),
        notes: asStringOrNull(j['notes']),
        resendStatus: asStringOrNull(j['resend_status']),
        resentAt: asStringOrNull(j['resent_at']),
      );

  Map<String, dynamic> toJson() => {
        'item_name': itemName,
        if (specification != null) 'specification': specification,
        'returned_qty': returnedQty,
        'reason': reason,
        'condition': condition,
        'action': action,
        if (notes != null && notes!.isNotEmpty) 'notes': notes,
      };
}

class BillAdjustment {
  const BillAdjustment({
    this.adjustmentType = 'NONE',
    this.amount = 0,
    this.notes,
  });

  final String adjustmentType;
  final double amount;
  final String? notes;

  bool get applies => adjustmentType != 'NONE';

  factory BillAdjustment.fromJson(Map<String, dynamic> j) => BillAdjustment(
        adjustmentType: asString(j['adjustment_type'], 'NONE'),
        amount: asDouble(j['amount']),
        notes: asStringOrNull(j['notes']),
      );

  Map<String, dynamic> toJson() => {
        'adjustment_type': adjustmentType,
        'amount': amount,
        if (notes != null && notes!.isNotEmpty) 'notes': notes,
      };

  static const none = BillAdjustment();
}

class ReturnRecord {
  const ReturnRecord({
    required this.id,
    required this.returnId,
    required this.gatePassId,
    required this.clientName,
    required this.items,
    required this.status,
    this.deliveryId,
    this.billAdjustment,
    this.recordedBy,
    this.notes,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String returnId;
  final String gatePassId;
  final String? deliveryId;
  final String clientName;
  final List<ReturnItem> items;
  final ReturnStatus status;
  final BillAdjustment? billAdjustment;
  final String? recordedBy;
  final String? notes;
  final String? createdAt;
  final String? updatedAt;

  String get statusLabel => returnStatusLabels[status] ?? 'Pending';
  double get totalPieces => items.fold(0.0, (a, i) => a + i.returnedQty);

  factory ReturnRecord.fromJson(Map<String, dynamic> j) => ReturnRecord(
        id: asString(j['id'] ?? j['_id']),
        returnId: asString(j['return_id']),
        gatePassId: asString(j['gate_pass_id']),
        deliveryId: asStringOrNull(j['delivery_id']),
        clientName: asString(j['client_name']),
        items: asMapList(j['items']).map(ReturnItem.fromJson).toList(),
        status: returnStatusFrom(asStringOrNull(j['status'])),
        billAdjustment: j['bill_adjustment'] == null
            ? null
            : BillAdjustment.fromJson(asMap(j['bill_adjustment'])),
        recordedBy: asStringOrNull(j['recorded_by']),
        notes: asStringOrNull(j['notes']),
        createdAt: asStringOrNull(j['created_at']),
        updatedAt: asStringOrNull(j['updated_at']),
      );
}

class Payment {
  const Payment({
    required this.id,
    required this.billId,
    required this.clientName,
    required this.amount,
    required this.paymentMethod,
    required this.paymentDate,
    this.reference,
    this.notes,
    this.createdAt,
    this.verification,
  });

  final String id;
  final String billId;
  final String clientName;
  final double amount;
  final String paymentMethod;
  final String paymentDate;
  final String? reference;
  final String? notes;
  final String? createdAt;
  final Verification? verification;

  factory Payment.fromJson(Map<String, dynamic> j) => Payment(
        id: asString(j['id'] ?? j['_id']),
        billId: asString(j['bill_id']),
        clientName: asString(j['client_name']),
        amount: asDouble(j['amount']),
        paymentMethod: asString(j['payment_method'], 'Cash'),
        paymentDate: asString(j['payment_date']),
        reference: asStringOrNull(j['reference']),
        notes: asStringOrNull(j['notes']),
        createdAt: asStringOrNull(j['created_at']),
        verification: Verification.tryParse(j['verification']),
      );
}

class LoyaltyAccount {
  const LoyaltyAccount({
    required this.id,
    required this.clientName,
    required this.points,
    required this.tier,
    required this.visits,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String clientName;
  final int points;
  final String tier;
  final int visits;
  final String? createdAt;
  final String? updatedAt;

  factory LoyaltyAccount.fromJson(Map<String, dynamic> j) => LoyaltyAccount(
        id: asString(j['id'] ?? j['_id']),
        clientName: asString(j['client_name']),
        points: asInt(j['points']),
        tier: asString(j['tier'], 'BRONZE'),
        visits: asInt(j['visits']),
        createdAt: asStringOrNull(j['created_at']),
        updatedAt: asStringOrNull(j['updated_at']),
      );
}

/// Per-hotel linen flow. Every quantity is computed server-side.
class LinenFlowTotals {
  const LinenFlowTotals({
    this.receivedQty = 0,
    this.deliveredQty = 0,
    this.outstandingDeliveryQty = 0,
  });

  final double receivedQty;
  final double deliveredQty;
  final double outstandingDeliveryQty;

  factory LinenFlowTotals.fromJson(Map<String, dynamic> j) => LinenFlowTotals(
        receivedQty: asDouble(j['received_qty']),
        deliveredQty: asDouble(j['delivered_qty']),
        outstandingDeliveryQty: asDouble(j['outstanding_delivery_qty']),
      );

  static const empty = LinenFlowTotals();
}

class LinenFlowOutstandingItem {
  const LinenFlowOutstandingItem({
    required this.itemKey,
    required this.itemName,
    required this.receivedQty,
    required this.deliveredQty,
    required this.returnedBackQty,
    required this.outstandingDeliveryQty,
    this.specification,
  });

  final String itemKey;
  final String itemName;
  final String? specification;
  final double receivedQty;
  final double deliveredQty;
  final double returnedBackQty;
  final double outstandingDeliveryQty;

  String get displayName =>
      (specification == null || specification!.isEmpty) ? itemName : '$itemName · $specification';

  factory LinenFlowOutstandingItem.fromJson(Map<String, dynamic> j) =>
      LinenFlowOutstandingItem(
        itemKey: asString(j['item_key']),
        itemName: asString(j['item_name']),
        specification: asStringOrNull(j['specification']),
        receivedQty: asDouble(j['received_qty']),
        deliveredQty: asDouble(j['delivered_qty']),
        returnedBackQty: asDouble(j['returned_back_qty']),
        outstandingDeliveryQty: asDouble(j['outstanding_delivery_qty']),
      );
}

class LinenFlowGatePass {
  const LinenFlowGatePass({
    required this.gatePassId,
    required this.totals,
    this.gatePassNumber,
    this.receivingDate,
    this.status,
    this.derivedStatus,
    this.markedDelivered = false,
    this.outstandingItems = const [],
  });

  final String gatePassId;
  final String? gatePassNumber;
  final String? receivingDate;
  final String? status;
  final String? derivedStatus;
  final bool markedDelivered;
  final LinenFlowTotals totals;
  final List<LinenFlowOutstandingItem> outstandingItems;

  factory LinenFlowGatePass.fromJson(Map<String, dynamic> j) => LinenFlowGatePass(
        gatePassId: asString(j['gate_pass_id']),
        gatePassNumber: asStringOrNull(j['gate_pass_number']),
        receivingDate: asStringOrNull(j['receiving_date']),
        status: asStringOrNull(j['status']),
        derivedStatus: asStringOrNull(j['derived_status']),
        markedDelivered: asBool(j['marked_delivered']),
        totals: LinenFlowTotals.fromJson(asMap(j['totals'])),
        outstandingItems: asMapList(j['outstanding_items'])
            .map(LinenFlowOutstandingItem.fromJson)
            .toList(),
      );
}

class UnlinkedDelivery {
  const UnlinkedDelivery({
    required this.deliveryId,
    required this.pieces,
    this.deliveryDate,
  });

  final String deliveryId;
  final String? deliveryDate;
  final double pieces;

  factory UnlinkedDelivery.fromJson(Map<String, dynamic> j) => UnlinkedDelivery(
        deliveryId: asString(j['delivery_id']),
        deliveryDate: asStringOrNull(j['delivery_date']),
        pieces: asDouble(j['pieces']),
      );
}

class LinenFlowHotel {
  const LinenFlowHotel({
    required this.clientName,
    required this.totals,
    this.gatePasses = const [],
    this.unlinkedDeliveries = const [],
  });

  final String clientName;
  final LinenFlowTotals totals;
  final List<LinenFlowGatePass> gatePasses;
  final List<UnlinkedDelivery> unlinkedDeliveries;

  double get unlinkedPieces =>
      unlinkedDeliveries.fold<double>(0, (a, d) => a + d.pieces);

  factory LinenFlowHotel.fromJson(Map<String, dynamic> j) => LinenFlowHotel(
        clientName: asString(j['client_name']),
        totals: LinenFlowTotals.fromJson(asMap(j['totals'])),
        gatePasses: asMapList(j['gate_passes']).map(LinenFlowGatePass.fromJson).toList(),
        unlinkedDeliveries:
            asMapList(j['unlinked_deliveries']).map(UnlinkedDelivery.fromJson).toList(),
      );
}

class LinenFlow {
  const LinenFlow({
    required this.period,
    required this.hotels,
    required this.totals,
  });

  final String period;
  final List<LinenFlowHotel> hotels;
  final LinenFlowTotals totals;

  factory LinenFlow.fromJson(Map<String, dynamic> j) => LinenFlow(
        period: asString(j['period']),
        hotels: asMapList(j['hotels']).map(LinenFlowHotel.fromJson).toList(),
        totals: LinenFlowTotals.fromJson(asMap(j['totals'])),
      );
}
