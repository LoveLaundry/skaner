import 'package:flutter/material.dart';

import '../../config/api_config.dart';
import '../../core/models/json.dart';
import '../../data/resource_controller.dart';
import '../../ui/kit/primitives.dart';

/// The web app gates each surface behind one string; it has no finer read/write
/// split, so a whole screen hides without it. Dispatch reuses the deliveries
/// grant and returns reuses the gate-passes grant, exactly as the sidebar does.
const String quotationsReadPermission = 'view_quotations';
const String billsPermission = 'view_bills';
const String gatePassesPermission = 'view_gate_passes';
const String deliveriesPermission = 'view_deliveries';
const String clientsPermission = 'view_clients';
const String reportsPermission = 'view_reports';

class QuotationApi {
  QuotationApi._();

  static const String list = '/quotations';
  static String one(String id) => '/quotations/$id';
  static String status(String id) => '/quotations/$id/status';
  static String tags(String id) => '/quotations/$id/tags';
}

/// Every operations read in this feature lives on the bills backend; only the
/// quotation document itself is served by the quotation backend.
const String operationsService = ServiceNames.bills;

// ── Order status ─────────────────────────────────────────────────────────────

enum QuotationStatus {
  draft,
  received,
  washing,
  pressing,
  folding,
  packing,
  ready,
  outForDelivery,
  delivered,
  cancelled,
}

QuotationStatus quotationStatusFrom(String? raw) =>
    switch ((raw ?? '').toLowerCase().replaceAll('-', '_')) {
      'received' => QuotationStatus.received,
      'washing' => QuotationStatus.washing,
      'pressing' => QuotationStatus.pressing,
      'folding' => QuotationStatus.folding,
      'packing' => QuotationStatus.packing,
      'ready' => QuotationStatus.ready,
      'out_for_delivery' => QuotationStatus.outForDelivery,
      'delivered' => QuotationStatus.delivered,
      'cancelled' => QuotationStatus.cancelled,
      _ => QuotationStatus.draft,
    };

const Map<QuotationStatus, String> quotationStatusLabels = {
  QuotationStatus.draft: 'Draft',
  QuotationStatus.received: 'Received',
  QuotationStatus.washing: 'Washing',
  QuotationStatus.pressing: 'Pressing',
  QuotationStatus.folding: 'Folding',
  QuotationStatus.packing: 'Packing',
  QuotationStatus.ready: 'Ready',
  QuotationStatus.outForDelivery: 'Out for Delivery',
  QuotationStatus.delivered: 'Delivered',
  QuotationStatus.cancelled: 'Cancelled',
};

const Map<QuotationStatus, String> quotationStatusValues = {
  QuotationStatus.draft: 'draft',
  QuotationStatus.received: 'received',
  QuotationStatus.washing: 'washing',
  QuotationStatus.pressing: 'pressing',
  QuotationStatus.folding: 'folding',
  QuotationStatus.packing: 'packing',
  QuotationStatus.ready: 'ready',
  QuotationStatus.outForDelivery: 'out_for_delivery',
  QuotationStatus.delivered: 'delivered',
  QuotationStatus.cancelled: 'cancelled',
};

/// `every` step may be cancelled, and only one forward step is legal, so the
/// detail screen can never offer a move the server would reject.
const Map<QuotationStatus, List<QuotationStatus>> quotationStatusTransitions = {
  QuotationStatus.draft: [QuotationStatus.received, QuotationStatus.cancelled],
  QuotationStatus.received: [
    QuotationStatus.washing,
    QuotationStatus.cancelled
  ],
  QuotationStatus.washing: [
    QuotationStatus.pressing,
    QuotationStatus.cancelled
  ],
  QuotationStatus.pressing: [
    QuotationStatus.folding,
    QuotationStatus.cancelled
  ],
  QuotationStatus.folding: [QuotationStatus.packing, QuotationStatus.cancelled],
  QuotationStatus.packing: [QuotationStatus.ready, QuotationStatus.cancelled],
  QuotationStatus.ready: [
    QuotationStatus.outForDelivery,
    QuotationStatus.cancelled
  ],
  QuotationStatus.outForDelivery: [
    QuotationStatus.delivered,
    QuotationStatus.cancelled
  ],
  QuotationStatus.delivered: [],
  QuotationStatus.cancelled: [],
};

/// Mirrors `ORDER_STATUS_STYLE` in `types/quotation.ts`: grey while nothing has
/// happened, blue while the order is queued, amber through the wet-processing
/// stages, green once it can go out, red when it was cancelled.
AppTone quotationStatusTone(QuotationStatus status) => switch (status) {
      QuotationStatus.draft => AppTone.neutral,
      QuotationStatus.received || QuotationStatus.washing => AppTone.info,
      QuotationStatus.pressing ||
      QuotationStatus.folding ||
      QuotationStatus.packing =>
        AppTone.warning,
      QuotationStatus.ready ||
      QuotationStatus.outForDelivery ||
      QuotationStatus.delivered =>
        AppTone.success,
      QuotationStatus.cancelled => AppTone.danger,
    };

class QuotationStatusBadge extends StatelessWidget {
  const QuotationStatusBadge({super.key, required this.status});

  final QuotationStatus status;

  @override
  Widget build(BuildContext context) => AppBadge(
        quotationStatusLabels[status] ?? 'Draft',
        tone: quotationStatusTone(status),
        compact: true,
      );
}

// ── Line items ───────────────────────────────────────────────────────────────

class QuotationSpecification {
  const QuotationSpecification({
    this.specification = '',
    this.unitPrice = 0,
  });

  final String specification;
  final double unitPrice;

  factory QuotationSpecification.fromJson(Map<String, dynamic> j) =>
      QuotationSpecification(
        specification: str(j, const ['specification', 'spec']),
        unitPrice: numOf(j, const ['unit_price', 'price', 'rate']),
      );

  Map<String, dynamic> toJson() => {
        'specification': specification.trim(),
        'unit_price': unitPrice,
      };
}

class QuotationLineItem {
  const QuotationLineItem({
    this.id = '',
    this.itemName = '',
    this.category = '',
    this.unitPrice = 0,
    this.notes = '',
    this.specifications = const [],
  });

  final String id;
  final String itemName;
  final String category;
  final double unitPrice;
  final String notes;
  final List<QuotationSpecification> specifications;

  bool get isUsable => itemName.trim().isNotEmpty && unitPrice > 0;

  String get displayName => category.trim().isEmpty
      ? itemName.trim()
      : '${itemName.trim()} · $category';

  /// The cheapest rate across the item and its variants; a bill is priced off
  /// one number, so a specification list is summarised rather than expanded.
  double get effectiveRate {
    var best = unitPrice;
    for (final spec in specifications) {
      if (spec.unitPrice > 0 && spec.unitPrice < best) best = spec.unitPrice;
    }
    return best;
  }

  QuotationLineItem copyWith({
    String? id,
    String? itemName,
    String? category,
    double? unitPrice,
    String? notes,
    List<QuotationSpecification>? specifications,
  }) =>
      QuotationLineItem(
        id: id ?? this.id,
        itemName: itemName ?? this.itemName,
        category: category ?? this.category,
        unitPrice: unitPrice ?? this.unitPrice,
        notes: notes ?? this.notes,
        specifications: specifications ?? this.specifications,
      );

  factory QuotationLineItem.fromJson(Map<String, dynamic> j) =>
      QuotationLineItem(
        id: str(j, const ['id', '_id']),
        itemName: str(j, const ['item_name', 'name']),
        category: str(j, const ['category']),
        unitPrice: numOf(j, const ['unit_price', 'price', 'rate']),
        notes: str(j, const ['notes']),
        specifications: asMapList(j['specifications'])
            .map(QuotationSpecification.fromJson)
            .toList(),
      );

  /// The quotation contract carries no quantity: rates are agreed here and the
  /// quantity is entered on the bill, exactly as the web app does it.
  Map<String, dynamic> toJson() => {
        'item_name': itemName.trim(),
        if (category.trim().isNotEmpty) 'category': category.trim(),
        'unit_price': unitPrice,
        if (notes.trim().isNotEmpty) 'notes': notes.trim(),
        if (specifications.isNotEmpty)
          'specifications': [
            for (final spec in specifications)
              if (spec.specification.trim().isNotEmpty) spec.toJson(),
          ],
      };
}

class QuotationStatusEntry {
  const QuotationStatusEntry({
    required this.status,
    this.changedAt,
    this.changedBy,
    this.note,
  });

  final String status;
  final String? changedAt;
  final String? changedBy;
  final String? note;

  factory QuotationStatusEntry.fromJson(Map<String, dynamic> j) =>
      QuotationStatusEntry(
        status: str(j, const ['status']),
        changedAt: str(j, const ['changed_at', 'at']),
        changedBy: str(j, const ['changed_by', 'user_id', 'user_name']),
        note: str(j, const ['note']),
      );
}

class GarmentTag {
  const GarmentTag({
    required this.code,
    required this.trackingUrl,
    this.id = '',
    this.label,
    this.createdAt,
  });

  final String id;
  final String code;
  final String? label;
  final String? createdAt;
  final String trackingUrl;

  factory GarmentTag.fromJson(Map<String, dynamic> j) => GarmentTag(
        id: str(j, const ['id', '_id']),
        code: str(j, const ['code']),
        label: str(j, const ['label']),
        createdAt: str(j, const ['created_at']),
        trackingUrl: str(j, const ['tracking_url']),
      );
}

class Quotation {
  const Quotation({
    required this.id,
    required this.clientName,
    required this.lineItems,
    this.title,
    this.status = QuotationStatus.draft,
    this.tag,
    this.statusHistory = const [],
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String clientName;
  final String? title;
  final List<QuotationLineItem> lineItems;
  final QuotationStatus status;
  final String? tag;
  final List<QuotationStatusEntry> statusHistory;
  final String? createdAt;
  final String? updatedAt;

  bool get isShop => tag?.toLowerCase() == 'shop';
  bool get isClosed =>
      status == QuotationStatus.delivered ||
      status == QuotationStatus.cancelled;
  bool get canEdit => !isClosed;
  String get displayTitle =>
      (title ?? '').trim().isEmpty ? 'Price List' : title!.trim();
  int get itemCount => lineItems.length;
  double get rateTotal =>
      lineItems.fold<double>(0, (sum, item) => sum + item.effectiveRate);

  List<QuotationStatus> get nextStatuses =>
      quotationStatusTransitions[status] ?? const [];

  factory Quotation.fromJson(Map<String, dynamic> j) {
    final title = str(j, const ['quotation_title', 'title']).trim();
    final tag = str(j, const ['tag']).trim().toLowerCase();
    return Quotation(
      id: str(j, const ['id', '_id']),
      clientName: str(j, const ['client_name', 'client', 'hotel']),
      title: title.isEmpty ? null : title,
      lineItems: asMapList(pick(j, const ['line_items', 'items', 'lines']))
          .map(QuotationLineItem.fromJson)
          .toList(),
      status: quotationStatusFrom(str(j, const ['status'])),
      tag: tag.isEmpty ? null : tag,
      statusHistory: asMapList(j['status_history'])
          .map(QuotationStatusEntry.fromJson)
          .toList(),
      createdAt: str(j, const ['created_at']),
      updatedAt: str(j, const ['updated_at']),
    );
  }

  /// The POST/PATCH body, exactly `QuotationPayload` in `types/quotation.ts`.
  Map<String, dynamic> toJson() => {
        'client_name': clientName.trim(),
        'quotation_title': displayTitle,
        'line_items': [for (final item in lineItems) item.toJson()],
        'status': quotationStatusValues[status]!,
        if (tag != null && tag!.isNotEmpty) 'tag': tag,
      };
}

List<Quotation> quotationsFrom(dynamic payload) =>
    asRows(payload).map(Quotation.fromJson).toList();

/// The three operations backends reject a bare date, so every write that
/// carries a date sends it as an ISO datetime like the web client does.
String isoDateTime(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}'
    'T00:00:00';
