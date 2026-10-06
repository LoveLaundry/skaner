import 'json.dart';

const List<String> taskTypes = [
  'WASHING',
  'PRESSING',
  'FOLDING',
  'PACKING',
  'DRY_CLEANING',
  'STAIN_TREATMENT',
  'MACHINE_CLEANING',
  'SORTING_TAGGING',
  'DELIVERY_SUPPORT',
  'MAINTENANCE',
  'OTHER',
];

const List<String> taskUnits = ['PIECES', 'KG', 'LOADS', 'HOURS'];

const List<String> departments = [
  'WASHING',
  'PRESSING',
  'FINISHING',
  'PACKING',
  'DRY_CLEANING',
  'DELIVERY',
  'GENERAL',
];

const List<String> shifts = ['MORNING', 'EVENING', 'NIGHT', 'FULL_DAY'];

const List<String> attendanceStatuses = [
  'PRESENT',
  'HALF_DAY',
  'ABSENT',
  'ON_LEAVE',
];

const Map<String, String> taskTypeLabels = {
  'WASHING': 'Washing',
  'PRESSING': 'Pressing',
  'FOLDING': 'Folding',
  'PACKING': 'Packing',
  'DRY_CLEANING': 'Dry Cleaning',
  'STAIN_TREATMENT': 'Stain Treatment',
  'MACHINE_CLEANING': 'Machine Cleaning',
  'SORTING_TAGGING': 'Sorting & Tagging',
  'DELIVERY_SUPPORT': 'Delivery Support',
  'MAINTENANCE': 'Maintenance',
  'OTHER': 'Other',
};

const Map<String, String> departmentLabels = {
  'WASHING': 'Washing',
  'PRESSING': 'Pressing',
  'FINISHING': 'Finishing',
  'PACKING': 'Packing',
  'DRY_CLEANING': 'Dry Cleaning',
  'DELIVERY': 'Delivery',
  'GENERAL': 'General',
};

const Map<String, String> shiftLabels = {
  'MORNING': 'Morning',
  'EVENING': 'Evening',
  'NIGHT': 'Night',
  'FULL_DAY': 'Full Day',
};

const Map<String, String> attendanceStatusLabels = {
  'PRESENT': 'Present',
  'HALF_DAY': 'Half Day',
  'ABSENT': 'Absent',
  'ON_LEAVE': 'On Leave',
};

class TaskEntry {
  TaskEntry({
    required this.taskType,
    required this.quantity,
    required this.unit,
    this.description,
    this.hoursSpent,
    this.gatePassId,
    this.gatePassNumber,
    this.remark,
  });

  final String taskType;
  final String? description;
  final double quantity;
  final String unit;
  final double? hoursSpent;
  final String? gatePassId;
  final String? gatePassNumber;
  final String? remark;

  String get typeLabel => taskTypeLabels[taskType] ?? taskType;

  factory TaskEntry.fromJson(Map<String, dynamic> j) => TaskEntry(
        taskType: asString(j['task_type'], 'OTHER'),
        description: asStringOrNull(j['description']),
        quantity: asDouble(j['quantity']),
        unit: asString(j['unit'], 'PIECES'),
        hoursSpent: j['hours_spent'] == null ? null : asDouble(j['hours_spent']),
        gatePassId: asStringOrNull(j['gate_pass_id']),
        gatePassNumber: asStringOrNull(j['gate_pass_number']),
        remark: asStringOrNull(j['remark']),
      );

  Map<String, dynamic> toJson() => {
        'task_type': taskType,
        if (description != null && description!.isNotEmpty) 'description': description,
        'quantity': quantity,
        'unit': unit,
        if (hoursSpent != null) 'hours_spent': hoursSpent,
        if (gatePassId != null) 'gate_pass_id': gatePassId,
        if (gatePassNumber != null) 'gate_pass_number': gatePassNumber,
        if (remark != null && remark!.isNotEmpty) 'remark': remark,
      };
}

class Worker {
  const Worker({
    required this.id,
    required this.workerName,
    required this.department,
    required this.isActive,
    this.phone,
    this.joinedDate,
    this.notes,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String workerName;
  final String department;
  final String? phone;
  final bool isActive;
  final String? joinedDate;
  final String? notes;
  final String? createdAt;
  final String? updatedAt;

  String get departmentLabel => departmentLabels[department] ?? department;

  factory Worker.fromJson(Map<String, dynamic> j) => Worker(
        id: asString(j['id'] ?? j['_id']),
        workerName: asString(j['worker_name']),
        department: asString(j['department'], 'GENERAL'),
        phone: asStringOrNull(j['phone']),
        isActive: asBool(j['is_active'], true),
        joinedDate: asStringOrNull(j['joined_date']),
        notes: asStringOrNull(j['notes']),
        createdAt: asStringOrNull(j['created_at']),
        updatedAt: asStringOrNull(j['updated_at']),
      );
}

class DailyLog {
  const DailyLog({
    required this.id,
    required this.workDate,
    required this.workerName,
    required this.department,
    required this.shift,
    required this.attendanceStatus,
    required this.overtimeHours,
    required this.washedCount,
    required this.pressedCount,
    required this.foldedCount,
    required this.packedCount,
    required this.otherCount,
    required this.totalWeightKg,
    required this.tasks,
    required this.rewashCount,
    required this.damagedItems,
    required this.complaints,
    this.checkInTime,
    this.checkOutTime,
    this.qualityNotes,
    this.machinesUsed,
    this.chemicalsUsed,
    this.notes,
    this.performanceRating,
    this.isGroupWork = false,
    this.teamMembers = const [],
    this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String workDate;
  final String workerName;
  final String department;
  final String shift;
  final String attendanceStatus;
  final String? checkInTime;
  final String? checkOutTime;
  final double overtimeHours;
  final double washedCount;
  final double pressedCount;
  final double foldedCount;
  final double packedCount;
  final double otherCount;
  final double totalWeightKg;
  final List<TaskEntry> tasks;
  final double rewashCount;
  final double damagedItems;
  final double complaints;
  final String? qualityNotes;
  final String? machinesUsed;
  final String? chemicalsUsed;
  final String? notes;
  final double? performanceRating;
  final bool isGroupWork;
  final List<String> teamMembers;
  final String? createdBy;
  final String? createdAt;
  final String? updatedAt;

  String get attendanceLabel =>
      attendanceStatusLabels[attendanceStatus] ?? attendanceStatus;
  String get shiftLabel => shiftLabels[shift] ?? shift;
  String get departmentLabel => departmentLabels[department] ?? department;
  bool get isAbsent =>
      attendanceStatus == 'ABSENT' || attendanceStatus == 'ON_LEAVE';
  bool get isGroup => isGroupWork || teamMembers.isNotEmpty;

  double get totalCounted =>
      washedCount + pressedCount + foldedCount + packedCount + otherCount;

  factory DailyLog.fromJson(Map<String, dynamic> j) => DailyLog(
        id: asString(j['id'] ?? j['_id']),
        workDate: asString(j['work_date']),
        workerName: asString(j['worker_name']),
        department: asString(j['department'], 'GENERAL'),
        shift: asString(j['shift'], 'FULL_DAY'),
        attendanceStatus: asString(j['attendance_status'], 'PRESENT'),
        checkInTime: asStringOrNull(j['check_in_time']),
        checkOutTime: asStringOrNull(j['check_out_time']),
        overtimeHours: asDouble(j['overtime_hours']),
        washedCount: asDouble(j['washed_count']),
        pressedCount: asDouble(j['pressed_count']),
        foldedCount: asDouble(j['folded_count']),
        packedCount: asDouble(j['packed_count']),
        otherCount: asDouble(j['other_count']),
        totalWeightKg: asDouble(j['total_weight_kg']),
        tasks: asMapList(j['tasks']).map(TaskEntry.fromJson).toList(),
        rewashCount: asDouble(j['rewash_count']),
        damagedItems: asDouble(j['damaged_items']),
        complaints: asDouble(j['complaints']),
        qualityNotes: asStringOrNull(j['quality_notes']),
        machinesUsed: asStringOrNull(j['machines_used']),
        chemicalsUsed: asStringOrNull(j['chemicals_used']),
        notes: asStringOrNull(j['notes']),
        performanceRating: j['performance_rating'] == null
            ? null
            : asDouble(j['performance_rating']),
        isGroupWork: asBool(j['is_group_work']),
        teamMembers:
            (j['team_members'] as List?)?.map((e) => e.toString()).toList() ??
                const [],
        createdBy: asStringOrNull(j['created_by']),
        createdAt: asStringOrNull(j['created_at']),
        updatedAt: asStringOrNull(j['updated_at']),
      );
}

class DailySummary {
  const DailySummary({
    required this.date,
    this.workersLogged = 0,
    this.present = 0,
    this.absent = 0,
    this.onLeave = 0,
    this.halfDay = 0,
    this.totalWashed = 0,
    this.totalPressed = 0,
    this.totalFolded = 0,
    this.totalPacked = 0,
    this.totalOther = 0,
    this.totalWeightKg = 0,
    this.totalOvertimeHours = 0,
    this.totalRewash = 0,
    this.totalDamaged = 0,
    this.totalComplaints = 0,
  });

  final String date;
  final int workersLogged;
  final int present;
  final int absent;
  final int onLeave;
  final int halfDay;
  final double totalWashed;
  final double totalPressed;
  final double totalFolded;
  final double totalPacked;
  final double totalOther;
  final double totalWeightKg;
  final double totalOvertimeHours;
  final double totalRewash;
  final double totalDamaged;
  final double totalComplaints;

  double get totalCounted =>
      totalWashed + totalPressed + totalFolded + totalPacked + totalOther;

  /// Present + half day — the people actually on the floor.
  int get onDuty => present + halfDay;

  factory DailySummary.fromJson(Map<String, dynamic> j) => DailySummary(
        date: asString(j['date']),
        workersLogged: asInt(j['workers_logged']),
        present: asInt(j['present']),
        absent: asInt(j['absent']),
        onLeave: asInt(j['on_leave']),
        halfDay: asInt(j['half_day']),
        totalWashed: asDouble(j['total_washed']),
        totalPressed: asDouble(j['total_pressed']),
        totalFolded: asDouble(j['total_folded']),
        totalPacked: asDouble(j['total_packed']),
        totalOther: asDouble(j['total_other']),
        totalWeightKg: asDouble(j['total_weight_kg']),
        totalOvertimeHours: asDouble(j['total_overtime_hours']),
        totalRewash: asDouble(j['total_rewash']),
        totalDamaged: asDouble(j['total_damaged']),
        totalComplaints: asDouble(j['total_complaints']),
      );
}
