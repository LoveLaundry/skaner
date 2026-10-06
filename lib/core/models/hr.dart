import 'json.dart';

/// Employees, attendance, salary, advances, holidays, extra work, expenses,
/// items, customers, transactions, payments and company settings.
///
/// These mirror the `/api/*` namespace of the management service, which
/// paginates with `limit`/`offset` and wraps rows in `{items,total,limit,offset}`.

class Paginated<T> {
  const Paginated({
    required this.items,
    required this.total,
    this.limit = 25,
    this.offset = 0,
  });

  final List<T> items;
  final int total;
  final int limit;
  final int offset;

  int get page => limit == 0 ? 0 : (offset ~/ limit) + 1;
  int get pageCount => limit == 0 ? 1 : ((total / limit).ceil()).clamp(1, 1 << 30);
  bool get hasMore => offset + items.length < total;

  static Paginated<Map<String, dynamic>> from(Object? raw) {
    final r = unwrapList(raw);
    final m = raw is Map ? asMap(raw) : const <String, dynamic>{};
    return Paginated<Map<String, dynamic>>(
      items: r.items,
      total: r.total,
      limit: m['limit'] is num ? asInt(m['limit'], 25) : 25,
      offset: m['offset'] is num ? asInt(m['offset']) : 0,
    );
  }
}

class Customer {
  const Customer({
    required this.id,
    required this.name,
    this.contactPerson,
    this.email,
    this.phone,
    this.address,
    this.city,
    this.type = 'HOTEL',
    this.isActive = true,
    this.notes,
    this.createdAt,
    this.updatedAt,
    this.rates = const [],
  });

  final String id;
  final String name;
  final String? contactPerson;
  final String? email;
  final String? phone;
  final String? address;
  final String? city;
  final String type;
  final bool isActive;
  final String? notes;
  final String? createdAt;
  final String? updatedAt;
  final List<CustomerRate> rates;

  bool get isHotel => type.toUpperCase() == 'HOTEL';
  bool get isShop => type.toUpperCase() == 'SHOP';

  factory Customer.fromJson(Map<String, dynamic> j) => Customer(
        id: asString(j['id'] ?? j['_id']),
        name: asString(j['name'] ?? j['customer_name'] ?? j['client_name']),
        contactPerson: asStringOrNull(j['contact_person']),
        email: asStringOrNull(j['email']),
        phone: asStringOrNull(j['phone']),
        address: asStringOrNull(j['address']),
        city: asStringOrNull(j['city']),
        type: asString(j['type'], 'HOTEL'),
        isActive: asBool(j['is_active'], true),
        notes: asStringOrNull(j['notes']),
        createdAt: asStringOrNull(j['created_at']),
        updatedAt: asStringOrNull(j['updated_at']),
        rates: asMapList(j['rates']).map(CustomerRate.fromJson).toList(),
      );
}

class CustomerRate {
  const CustomerRate({
    required this.id,
    required this.itemName,
    required this.unitPrice,
    this.category,
    this.specification,
  });

  final String id;
  final String itemName;
  final String? category;
  final String? specification;
  final double unitPrice;

  String get displayName =>
      (specification == null || specification!.isEmpty) ? itemName : '$itemName · $specification';

  factory CustomerRate.fromJson(Map<String, dynamic> j) => CustomerRate(
        id: asString(j['id'] ?? j['_id']),
        itemName: asString(j['item_name']),
        category: asStringOrNull(j['category']),
        specification: asStringOrNull(j['specification']),
        unitPrice: asDouble(j['unit_price'] ?? j['rate']),
      );
}

class Item {
  const Item({
    required this.id,
    required this.name,
    this.category,
    this.unit,
    this.defaultPrice = 0,
    this.isActive = true,
    this.description,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String? category;
  final String? unit;
  final double defaultPrice;
  final bool isActive;
  final String? description;
  final String? createdAt;
  final String? updatedAt;

  factory Item.fromJson(Map<String, dynamic> j) => Item(
        id: asString(j['id'] ?? j['_id']),
        name: asString(j['name'] ?? j['item_name']),
        category: asStringOrNull(j['category']),
        unit: asStringOrNull(j['unit']),
        defaultPrice: asDouble(j['default_price'] ?? j['unit_price']),
        isActive: asBool(j['is_active'], true),
        description: asStringOrNull(j['description']),
        createdAt: asStringOrNull(j['created_at']),
        updatedAt: asStringOrNull(j['updated_at']),
      );
}

class ItemCategory {
  const ItemCategory({
    required this.id,
    required this.name,
    this.description,
    this.itemCount = 0,
  });

  final String id;
  final String name;
  final String? description;
  final int itemCount;

  factory ItemCategory.fromJson(Map<String, dynamic> j) => ItemCategory(
        id: asString(j['id'] ?? j['_id']),
        name: asString(j['name'] ?? j['category']),
        description: asStringOrNull(j['description']),
        itemCount: asInt(j['item_count'] ?? j['count']),
      );
}

enum TransactionSource { manual, import, bill, shopBill, gatePass, salary, expense }

TransactionSource transactionSourceFrom(String? raw) {
  switch ((raw ?? '').toLowerCase()) {
    case 'import':
      return TransactionSource.import;
    case 'bill':
      return TransactionSource.bill;
    case 'shop_bill':
    case 'shopbill':
      return TransactionSource.shopBill;
    case 'gate_pass':
    case 'gatepass':
      return TransactionSource.gatePass;
    case 'salary':
      return TransactionSource.salary;
    case 'expense':
      return TransactionSource.expense;
    default:
      return TransactionSource.manual;
  }
}

const Map<TransactionSource, String> transactionSourceLabels = {
  TransactionSource.manual: 'Manual',
  TransactionSource.import: 'Import',
  TransactionSource.bill: 'Bill',
  TransactionSource.shopBill: 'Shop Bill',
  TransactionSource.gatePass: 'Gate Pass',
  TransactionSource.salary: 'Salary',
  TransactionSource.expense: 'Expense',
};

class Transaction {
  const Transaction({
    required this.id,
    required this.date,
    this.description,
    this.customerId,
    this.customerName,
    this.amount = 0,
    this.type = 'INCOME',
    this.source = TransactionSource.manual,
    this.reference,
    this.notes,
    this.createdAt,
  });

  final String id;
  final String date;
  final String? description;
  final String? customerId;
  final String? customerName;
  final double amount;
  final String type;
  final TransactionSource source;
  final String? reference;
  final String? notes;
  final String? createdAt;

  bool get isIncome => type.toUpperCase() == 'INCOME';
  bool get isExpense => type.toUpperCase() == 'EXPENSE';
  double get signedAmount => isIncome ? amount : -amount;

  factory Transaction.fromJson(Map<String, dynamic> j) => Transaction(
        id: asString(j['id'] ?? j['_id']),
        date: asString(j['date'] ?? j['transaction_date']),
        description: asStringOrNull(j['description']),
        customerId: asStringOrNull(j['customer_id']),
        customerName: asStringOrNull(j['customer_name']),
        amount: asDouble(j['amount']),
        type: asString(j['type'], 'INCOME'),
        source: transactionSourceFrom(asStringOrNull(j['source'])),
        reference: asStringOrNull(j['reference']),
        notes: asStringOrNull(j['notes']),
        createdAt: asStringOrNull(j['created_at']),
      );
}

class ExpenseCategory {
  const ExpenseCategory({required this.id, required this.name, this.description});

  final String id;
  final String name;
  final String? description;

  factory ExpenseCategory.fromJson(Map<String, dynamic> j) => ExpenseCategory(
        id: asString(j['id'] ?? j['_id']),
        name: asString(j['name'] ?? j['category']),
        description: asStringOrNull(j['description']),
      );
}

class Expense {
  const Expense({
    required this.id,
    required this.date,
    required this.category,
    required this.amount,
    this.description,
    this.paymentMethod,
    this.receiptNo,
    this.notes,
    this.createdAt,
  });

  final String id;
  final String date;
  final String category;
  final double amount;
  final String? description;
  final String? paymentMethod;
  final String? receiptNo;
  final String? notes;
  final String? createdAt;

  factory Expense.fromJson(Map<String, dynamic> j) => Expense(
        id: asString(j['id'] ?? j['_id']),
        date: asString(j['date'] ?? j['expense_date']),
        category: asString(j['category'] ?? j['category_name'], 'Other'),
        amount: asDouble(j['amount']),
        description: asStringOrNull(j['description']),
        paymentMethod: asStringOrNull(j['payment_method']),
        receiptNo: asStringOrNull(j['receipt_no']),
        notes: asStringOrNull(j['notes']),
        createdAt: asStringOrNull(j['created_at']),
      );
}

class Employee {
  const Employee({
    required this.id,
    required this.name,
    this.employeeCode,
    this.designation,
    this.department,
    this.phone,
    this.email,
    this.baseSalary = 0,
    this.hourlyRate,
    this.joinDate,
    this.isActive = true,
    this.bankAccount,
    this.address,
    this.notes,
    this.createdAt,
  });

  final String id;
  final String name;
  final String? employeeCode;
  final String? designation;
  final String? department;
  final String? phone;
  final String? email;
  final double baseSalary;
  final double? hourlyRate;
  final String? joinDate;
  final bool isActive;
  final String? bankAccount;
  final String? address;
  final String? notes;
  final String? createdAt;

  factory Employee.fromJson(Map<String, dynamic> j) => Employee(
        id: asString(j['id'] ?? j['_id']),
        name: asString(j['name'] ?? j['employee_name']),
        employeeCode: asStringOrNull(j['employee_code'] ?? j['code']),
        designation: asStringOrNull(j['designation'] ?? j['position']),
        department: asStringOrNull(j['department']),
        phone: asStringOrNull(j['phone'] ?? j['mobile_number']),
        email: asStringOrNull(j['email']),
        baseSalary: asDouble(j['base_salary'] ?? j['salary']),
        hourlyRate: j['hourly_rate'] == null ? null : asDouble(j['hourly_rate']),
        joinDate: asStringOrNull(j['join_date'] ?? j['joined_date']),
        isActive: asBool(j['is_active'], true),
        bankAccount: asStringOrNull(j['bank_account']),
        address: asStringOrNull(j['address']),
        notes: asStringOrNull(j['notes']),
        createdAt: asStringOrNull(j['created_at']),
      );
}

class SalaryComponent {
  const SalaryComponent({
    required this.label,
    this.hours = 0,
    this.rate = 0,
    this.amount = 0,
    this.isDeduction = false,
  });

  final String label;
  final double hours;
  final double rate;
  final double amount;
  final bool isDeduction;
}

class SalaryRecord {
  const SalaryRecord({
    required this.id,
    required this.employeeId,
    required this.month,
    required this.year,
    this.employeeName,
    this.baseSalary = 0,
    this.overtimeAmount = 0,
    this.bonus = 0,
    this.deductions = 0,
    this.advances = 0,
    this.extraWorkAmount = 0,
    this.grossSalary = 0,
    this.netSalary = 0,
    this.paidAmount = 0,
    this.status = 'PENDING',
    this.paymentDate,
    this.notes,
    this.createdAt,
  });

  final String id;
  final String employeeId;
  final String? employeeName;
  final int month;
  final int year;
  final double baseSalary;
  final double overtimeAmount;
  final double bonus;
  final double deductions;
  final double advances;
  final double extraWorkAmount;
  final double grossSalary;
  final double netSalary;
  final double paidAmount;
  final String status;
  final String? paymentDate;
  final String? notes;
  final String? createdAt;

  String get period => '$year-${month.toString().padLeft(2, '0')}';
  bool get isPaid => status.toUpperCase() == 'PAID';
  double get outstanding => netSalary - paidAmount;

  factory SalaryRecord.fromJson(Map<String, dynamic> j) => SalaryRecord(
        id: asString(j['id'] ?? j['_id']),
        employeeId: asString(j['employee_id']),
        employeeName: asStringOrNull(j['employee_name']),
        month: asInt(j['month'], asInt(asStringOrNull(j['month'])?.split('-').first)),
        year: asInt(j['year']),
        baseSalary: asDouble(j['base_salary']),
        overtimeAmount: asDouble(j['overtime_amount']),
        bonus: asDouble(j['bonus']),
        deductions: asDouble(j['deductions']),
        advances: asDouble(j['advances']),
        extraWorkAmount: asDouble(j['extra_work_amount']),
        grossSalary: asDouble(j['gross_salary']),
        netSalary: asDouble(j['net_salary']),
        paidAmount: asDouble(j['paid_amount']),
        status: asString(j['status'], 'PENDING'),
        paymentDate: asStringOrNull(j['payment_date']),
        notes: asStringOrNull(j['notes']),
        createdAt: asStringOrNull(j['created_at']),
      );
}

class AttendanceRecord {
  const AttendanceRecord({
    required this.id,
    required this.employeeId,
    required this.date,
    required this.status,
    this.employeeName,
    this.department,
    this.checkIn,
    this.checkOut,
    this.overtimeHours = 0,
    this.notes,
  });

  final String id;
  final String employeeId;
  final String? employeeName;
  final String? department;
  final String date;
  final String status;
  final String? checkIn;
  final String? checkOut;
  final double overtimeHours;
  final String? notes;

  bool get isPresent => status == 'PRESENT';
  bool get isAbsent => status == 'ABSENT';
  bool get isLeave => status == 'ON_LEAVE';
  bool get isHalfDay => status == 'HALF_DAY';

  double get workedHours {
    if (isAbsent || isLeave) return 0;
    if (isHalfDay) return 4;
    return 8 + overtimeHours;
  }

  factory AttendanceRecord.fromJson(Map<String, dynamic> j) => AttendanceRecord(
        id: asString(j['id'] ?? j['_id']),
        employeeId: asString(j['employee_id']),
        employeeName: asStringOrNull(j['employee_name']),
        department: asStringOrNull(j['department']),
        date: asString(j['date'] ?? j['attendance_date']),
        status: asString(j['status'], 'PRESENT'),
        checkIn: asStringOrNull(j['check_in'] ?? j['check_in_time']),
        checkOut: asStringOrNull(j['check_out'] ?? j['check_out_time']),
        overtimeHours: asDouble(j['overtime_hours']),
        notes: asStringOrNull(j['notes']),
      );
}

class AttendanceSummary {
  const AttendanceSummary({
    this.employeeId = '',
    this.employeeName = '',
    this.totalDays = 0,
    this.present = 0,
    this.absent = 0,
    this.onLeave = 0,
    this.halfDays = 0,
    this.totalOvertimeHours = 0,
  });

  final String employeeId;
  final String? employeeName;
  final int totalDays;
  final int present;
  final int absent;
  final int onLeave;
  final int halfDays;
  final double totalOvertimeHours;

  int get onDuty => present + halfDays;
  double get attendanceRate =>
      totalDays == 0 ? 0 : (onDuty / totalDays) * 100;

  factory AttendanceSummary.fromJson(Map<String, dynamic> j) => AttendanceSummary(
        employeeId: asString(j['employee_id']),
        employeeName: asStringOrNull(j['employee_name']),
        totalDays: asInt(j['total_days']),
        present: asInt(j['present']),
        absent: asInt(j['absent']),
        onLeave: asInt(j['on_leave']),
        halfDays: asInt(j['half_days']),
        totalOvertimeHours: asDouble(j['total_overtime_hours']),
      );
}

class Advance {
  const Advance({
    required this.id,
    required this.employeeId,
    required this.amount,
    required this.date,
    this.employeeName,
    this.status = 'PENDING',
    this.reason,
    this.notes,
    this.repaymentDate,
  });

  final String id;
  final String employeeId;
  final String? employeeName;
  final double amount;
  final String date;
  final String status;
  final String? reason;
  final String? notes;
  final String? repaymentDate;

  bool get isPending => status.toUpperCase() == 'PENDING';
  bool get isRepaid => status.toUpperCase() == 'REPAID';
  bool get isAdjusted => status.toUpperCase() == 'ADJUSTED';

  factory Advance.fromJson(Map<String, dynamic> j) => Advance(
        id: asString(j['id'] ?? j['_id']),
        employeeId: asString(j['employee_id']),
        employeeName: asStringOrNull(j['employee_name']),
        amount: asDouble(j['amount']),
        date: asString(j['date'] ?? j['advance_date']),
        status: asString(j['status'], 'PENDING'),
        reason: asStringOrNull(j['reason']),
        notes: asStringOrNull(j['notes']),
        repaymentDate: asStringOrNull(j['repayment_date']),
      );
}

class Holiday {
  const Holiday({
    required this.id,
    required this.date,
    required this.name,
    this.type = 'PUBLIC',
    this.isPaid = true,
    this.description,
    this.recurring = false,
  });

  final String id;
  final String date;
  final String name;
  final String type;
  final bool isPaid;
  final String? description;
  final bool recurring;

  factory Holiday.fromJson(Map<String, dynamic> j) => Holiday(
        id: asString(j['id'] ?? j['_id']),
        date: asString(j['date'] ?? j['holiday_date']),
        name: asString(j['name'] ?? j['title']),
        type: asString(j['type'], 'PUBLIC'),
        isPaid: asBool(j['is_paid'], true),
        description: asStringOrNull(j['description']),
        recurring: asBool(j['recurring']),
      );
}

class ExtraWorkCategory {
  const ExtraWorkCategory({
    required this.id,
    required this.name,
    this.rate = 0,
    this.unit = 'PIECES',
    this.description,
  });

  final String id;
  final String name;
  final double rate;
  final String unit;
  final String? description;

  factory ExtraWorkCategory.fromJson(Map<String, dynamic> j) => ExtraWorkCategory(
        id: asString(j['id'] ?? j['_id']),
        name: asString(j['name'] ?? j['category']),
        rate: asDouble(j['rate'] ?? j['unit_rate']),
        unit: asString(j['unit'], 'PIECES'),
        description: asStringOrNull(j['description']),
      );
}

class ExtraWorkRecord {
  const ExtraWorkRecord({
    required this.id,
    required this.date,
    required this.categoryId,
    required this.quantity,
    this.categoryName,
    this.employeeId,
    this.employeeName,
    this.rate = 0,
    this.amount = 0,
    this.notes,
    this.paid = false,
  });

  final String id;
  final String date;
  final String categoryId;
  final String? categoryName;
  final String? employeeId;
  final String? employeeName;
  final double quantity;
  final double rate;
  final double amount;
  final String? notes;
  final bool paid;

  factory ExtraWorkRecord.fromJson(Map<String, dynamic> j) => ExtraWorkRecord(
        id: asString(j['id'] ?? j['_id']),
        date: asString(j['date'] ?? j['work_date']),
        categoryId: asString(j['category_id']),
        categoryName: asStringOrNull(j['category_name']),
        employeeId: asStringOrNull(j['employee_id']),
        employeeName: asStringOrNull(j['employee_name']),
        quantity: asDouble(j['quantity']),
        rate: asDouble(j['rate'] ?? j['unit_rate']),
        amount: asDouble(j['amount'], asDouble(j['rate']) * asDouble(j['quantity'])),
        notes: asStringOrNull(j['notes']),
        paid: asBool(j['paid']),
      );
}

class ManagementPayment {
  const ManagementPayment({
    required this.id,
    required this.amount,
    required this.date,
    this.customerId,
    this.customerName,
    this.method = 'Cash',
    this.reference,
    this.notes,
    this.billId,
  });

  final String id;
  final double amount;
  final String date;
  final String? customerId;
  final String? customerName;
  final String method;
  final String? reference;
  final String? notes;
  final String? billId;

  factory ManagementPayment.fromJson(Map<String, dynamic> j) => ManagementPayment(
        id: asString(j['id'] ?? j['_id']),
        amount: asDouble(j['amount']),
        date: asString(j['date'] ?? j['payment_date']),
        customerId: asStringOrNull(j['customer_id']),
        customerName: asStringOrNull(j['customer_name']),
        method: asString(j['method'] ?? j['payment_method'], 'Cash'),
        reference: asStringOrNull(j['reference']),
        notes: asStringOrNull(j['notes']),
        billId: asStringOrNull(j['bill_id']),
      );
}

class CompanySettings {
  const CompanySettings({
    this.name = 'Love Laundry',
    this.tagline = 'and dry cleaning experts',
    this.registrationNo = '',
    this.address = '',
    this.phone = '',
    this.email = '',
    this.whatsapp = '',
    this.facebook = '',
    this.currency = 'LKR',
    this.invoicePrefix = 'INV',
    this.quotationPrefix = 'QT',
    this.defaultTaxRate = 0,
    this.defaultTransportFee = 0,
    this.bankName = '',
    this.bankAccountName = '',
    this.bankAccountNumber = '',
    this.updatedAt,
  });

  final String name;
  final String tagline;
  final String registrationNo;
  final String address;
  final String phone;
  final String email;
  final String whatsapp;
  final String facebook;
  final String currency;
  final String invoicePrefix;
  final String quotationPrefix;
  final double defaultTaxRate;
  final double defaultTransportFee;
  final String bankName;
  final String bankAccountName;
  final String bankAccountNumber;
  final String? updatedAt;

  factory CompanySettings.fromJson(Map<String, dynamic> j) => CompanySettings(
        name: asString(j['name'] ?? j['company_name'], 'Love Laundry'),
        tagline: asString(j['tagline'], 'and dry cleaning experts'),
        registrationNo: asString(j['registration_no']),
        address: asString(j['address']),
        phone: asString(j['phone']),
        email: asString(j['email']),
        whatsapp: asString(j['whatsapp']),
        facebook: asString(j['facebook']),
        currency: asString(j['currency'], 'LKR'),
        invoicePrefix: asString(j['invoice_prefix'], 'INV'),
        quotationPrefix: asString(j['quotation_prefix'], 'QT'),
        defaultTaxRate: asDouble(j['default_tax_rate']),
        defaultTransportFee: asDouble(j['default_transport_fee']),
        bankName: asString(j['bank_name']),
        bankAccountName: asString(j['bank_account_name']),
        bankAccountNumber: asString(j['bank_account_number']),
        updatedAt: asStringOrNull(j['updated_at']),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'tagline': tagline,
        'registration_no': registrationNo,
        'address': address,
        'phone': phone,
        'email': email,
        'whatsapp': whatsapp,
        'facebook': facebook,
        'currency': currency,
        'invoice_prefix': invoicePrefix,
        'quotation_prefix': quotationPrefix,
        'default_tax_rate': defaultTaxRate,
        'default_transport_fee': defaultTransportFee,
        'bank_name': bankName,
        'bank_account_name': bankAccountName,
        'bank_account_number': bankAccountNumber,
      };
}

/// A salary calculation, used by the slip screen and the payroll preview.
class SalaryCalculation {
  const SalaryCalculation({
    this.employeeId = '',
    this.employeeName = '',
    this.month = 0,
    this.year = 0,
    this.components = const [],
    this.grossSalary = 0,
    this.totalDeductions = 0,
    this.netSalary = 0,
  });

  final String employeeId;
  final String? employeeName;
  final int month;
  final int year;
  final List<SalaryComponent> components;
  final double grossSalary;
  final double totalDeductions;
  final double netSalary;

  String get period =>
      year == 0 ? '' : '$year-${month.toString().padLeft(2, '0')}';

  factory SalaryCalculation.fromJson(Map<String, dynamic> j) =>
      SalaryCalculation(
        employeeId: asString(j['employee_id']),
        employeeName: asStringOrNull(j['employee_name']),
        month: asInt(j['month']),
        year: asInt(j['year']),
        components: asMapList(j['components'])
            .map((c) => SalaryComponent(
                  label: asString(c['label'] ?? c['name']),
                  hours: asDouble(c['hours']),
                  rate: asDouble(c['rate']),
                  amount: asDouble(c['amount']),
                  isDeduction: asBool(c['is_deduction']),
                ))
            .toList(),
        grossSalary: asDouble(j['gross_salary']),
        totalDeductions: asDouble(j['total_deductions']),
        netSalary: asDouble(j['net_salary']),
      );
}
