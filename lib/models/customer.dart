import 'dart:convert';

class CustomerPlan {
  static const String normal = 'normal';
  static const String personalTraining = 'personal_training';
  static const String personalTrainingDiet = 'personal_training_diet';

  static const List<String> allPlans = [
    normal,
    personalTraining,
    personalTrainingDiet,
  ];

  static String getLabel(String? plan) {
    switch (plan) {
      case personalTraining:
        return 'Plan with Personal Training';
      case personalTrainingDiet:
        return 'Plan with Personal Training + Diet';
      case normal:
      default:
        return 'Normal Plan';
    }
  }

  static String getShortLabel(String? plan) {
    switch (plan) {
      case personalTraining:
        return 'PT Plan';
      case personalTrainingDiet:
        return 'PT + Diet';
      case normal:
      default:
        return 'Normal';
    }
  }
}

class Customer {
  final String id;
  final String name;
  final String phone;
  final String? imagePath;
  final String? imageBase64;
  final DateTime joinDate;
  final bool isActive;
  final String notes;
  final String planType;
  final int planDurationMonths;
  final String cardNumber;
  final String address;
  final String weight;
  final String chest;
  final String bicep;
  final String waist;
  final String leg;

  const Customer({
    required this.id,
    required this.name,
    required this.phone,
    this.imagePath,
    this.imageBase64,
    required this.joinDate,
    this.isActive = true,
    this.notes = '',
    this.planType = CustomerPlan.normal,
    this.planDurationMonths = 1,
    this.cardNumber = '',
    this.address = '',
    this.weight = '',
    this.chest = '',
    this.bicep = '',
    this.waist = '',
    this.leg = '',
  });

  String get durationLabel =>
      '$planDurationMonths ${planDurationMonths == 1 ? "Month" : "Months"}';

  Customer copyWith({
    String? id,
    String? name,
    String? phone,
    String? imagePath,
    String? imageBase64,
    bool clearImagePath = false,
    bool clearImageBase64 = false,
    DateTime? joinDate,
    bool? isActive,
    String? notes,
    String? planType,
    int? planDurationMonths,
    String? cardNumber,
    String? address,
    String? weight,
    String? chest,
    String? bicep,
    String? waist,
    String? leg,
  }) {
    return Customer(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      imagePath: clearImagePath ? null : (imagePath ?? this.imagePath),
      imageBase64:
          clearImageBase64 ? null : (imageBase64 ?? this.imageBase64),
      joinDate: joinDate ?? this.joinDate,
      isActive: isActive ?? this.isActive,
      notes: notes ?? this.notes,
      planType: planType ?? this.planType,
      planDurationMonths: planDurationMonths ?? this.planDurationMonths,
      cardNumber: cardNumber ?? this.cardNumber,
      address: address ?? this.address,
      weight: weight ?? this.weight,
      chest: chest ?? this.chest,
      bicep: bicep ?? this.bicep,
      waist: waist ?? this.waist,
      leg: leg ?? this.leg,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'imagePath': imagePath,
      'imageBase64': imageBase64,
      'joinDate': joinDate.toIso8601String(),
      'isActive': isActive,
      'notes': notes,
      'planType': planType,
      'planDurationMonths': planDurationMonths,
      'cardNumber': cardNumber,
      'address': address,
      'weight': weight,
      'chest': chest,
      'bicep': bicep,
      'waist': waist,
      'leg': leg,
    };
  }

  factory Customer.fromMap(Map<String, dynamic> map) {
    return Customer(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
      imagePath: map['imagePath'] as String?,
      imageBase64: map['imageBase64'] as String?,
      joinDate: map['joinDate'] != null
          ? DateTime.tryParse(map['joinDate'] as String) ?? DateTime.now()
          : DateTime.now(),
      isActive: map['isActive'] as bool? ?? true,
      notes: map['notes'] as String? ?? '',
      planType: map['planType'] as String? ?? CustomerPlan.normal,
      planDurationMonths: (map['planDurationMonths'] as num?)?.toInt() ?? 1,
      cardNumber: map['cardNumber'] as String? ?? '',
      address: map['address'] as String? ?? '',
      weight: map['weight'] as String? ?? '',
      chest: map['chest'] as String? ?? '',
      bicep: map['bicep'] as String? ?? '',
      waist: map['waist'] as String? ?? '',
      leg: map['leg'] as String? ?? '',
    );
  }

  String toJson() => json.encode(toMap());

  factory Customer.fromJson(String source) =>
      Customer.fromMap(json.decode(source) as Map<String, dynamic>);
}
