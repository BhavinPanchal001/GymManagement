import 'customer.dart';
import 'payment.dart';

class MemberImportData {
  final int rowNumber;
  final String name;
  final String phone;
  final String cardNumber;
  final DateTime joinDate;
  final String planType;
  final int durationMonths;
  final DateTime membershipStartDate;
  final DateTime membershipEndDate;
  final double membershipFee;
  final double amountPaid;
  final PaymentMethod paymentMethod;
  final DateTime? paidAt;
  final String address;
  final String notes;

  const MemberImportData({
    required this.rowNumber,
    required this.name,
    required this.phone,
    required this.cardNumber,
    required this.joinDate,
    required this.planType,
    required this.durationMonths,
    required this.membershipStartDate,
    required this.membershipEndDate,
    required this.membershipFee,
    required this.amountPaid,
    required this.paymentMethod,
    this.paidAt,
    required this.address,
    required this.notes,
  });
}

class MemberImportRow {
  final int rowNumber;
  final MemberImportData? data;
  final String displayName;
  final String displayPhone;
  final String displayCardNumber;
  final List<String> errors;
  final List<String> warnings;

  const MemberImportRow({
    required this.rowNumber,
    required this.data,
    required this.displayName,
    required this.displayPhone,
    required this.displayCardNumber,
    this.errors = const [],
    this.warnings = const [],
  });

  bool get canImport => data != null && errors.isEmpty;
}

class MemberImportPreview {
  final List<MemberImportRow> rows;

  const MemberImportPreview(this.rows);

  List<MemberImportData> get importableRows => rows
      .where((row) => row.canImport)
      .map((row) => row.data!)
      .toList(growable: false);

  int get errorCount => rows.where((row) => !row.canImport).length;
  int get warningCount => rows.where((row) => row.warnings.isNotEmpty).length;
}

String normalizePlanType(String value) {
  final normalized = value.trim().toLowerCase().replaceAll(
    RegExp(r'[^a-z0-9]+'),
    '',
  );
  switch (normalized) {
    case 'pt':
    case 'personaltraining':
    case 'personaltrainer':
      return CustomerPlan.personalTraining;
    case 'ptdiet':
    case 'personaltrainingdiet':
    case 'personaltrainerdiet':
      return CustomerPlan.personalTrainingDiet;
    case 'normal':
    case 'regular':
    case 'standard':
    case '':
      return CustomerPlan.normal;
    default:
      return '';
  }
}
