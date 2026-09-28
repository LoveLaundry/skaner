/// Company identity used on every printed document, receipt and share sheet.
class CompanyInfo {
  CompanyInfo._();

  static const String name = 'Love Laundry';
  static const String tagline = 'and dry cleaning experts';
  static const String registrationNo = '40-3064';

  static const String addressLine1 = 'Medagama, Panirendawa';
  static const String addressLine2 = 'Chilaw, Puttalam, Sri Lanka';
  static const String addressBlock = '$addressLine1\n$addressLine2';

  static const String phonePrimary = '+94 77 4200 919';
  static const String phoneSecondary = '+94 70 243 3566';
  static const String email = 'lovelaundry01@gmail.com';
  static const String whatsappUrl = 'https://wa.me/94774200919';
  static const String facebookUrl = 'https://www.facebook.com/lovelaundrylk';
  static const String mapsUrl = 'https://maps.app.goo.gl/LoveLaundryLocation';
}

/// Terms printed on quotation documents.
class QuotationConditions {
  QuotationConditions._();

  static const List<String> all = [
    'Prices are valid for 30 days from the date of quotation.',
    'Quotation is subject to change without prior notice.',
    'All items are subject to availability at time of order.',
    'Payment terms: 50% advance, balance on delivery.',
    'Any disputes are subject to Colombo jurisdiction.',
  ];
}

/// Payment methods accepted across bills and shop bills.
class PaymentMethods {
  PaymentMethods._();

  static const List<String> all = ['Cash', 'Bank Transfer', 'Cheque', 'Card'];
}

/// Why a receiving/delivery date may be corrected after the fact.
class DateCorrectionReasons {
  DateCorrectionReasons._();

  static const List<String> all = [
    'Data entry error',
    'Client reported wrong date',
    'Receiving happened earlier',
    'Document was filed late',
    'System migration',
    'Other',
  ];
}

/// Reasons an inline quantity adjustment needs another user's approval.
class AdjustmentReasons {
  AdjustmentReasons._();

  static const List<String> all = [
    'Counted wrong at receiving',
    'Client short-shipped',
    'Damaged in transit',
    'Rewashed, not billed',
    'Duplicate entry',
    'Other',
  ];
}

/// Public price-list page for walk-in customers.
class GuestRoute {
  GuestRoute._();

  static const String shopPriceList = '/quotations/guest/shop';
  static const String trackTag = '/tags/';
}
