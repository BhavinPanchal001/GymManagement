import 'dart:convert';
import 'package:flutter/material.dart';
import 'payment.dart';

enum ExpenseCategory {
  rent,
  electricity,
  equipmentMaintenance,
  trainerSalaries,
  cleaningSupplies,
  marketing,
  supplements,
  misc;

  String get label {
    switch (this) {
      case ExpenseCategory.rent:
        return 'Rent';
      case ExpenseCategory.electricity:
        return 'Electricity & Utilities';
      case ExpenseCategory.equipmentMaintenance:
        return 'Equipment & Repairs';
      case ExpenseCategory.trainerSalaries:
        return 'Staff & Trainer Salaries';
      case ExpenseCategory.cleaningSupplies:
        return 'Cleaning & Maintenance';
      case ExpenseCategory.marketing:
        return 'Marketing & Promotions';
      case ExpenseCategory.supplements:
        return 'Supplements & Inventory';
      case ExpenseCategory.misc:
        return 'Miscellaneous';
    }
  }

  IconData get icon {
    switch (this) {
      case ExpenseCategory.rent:
        return Icons.storefront_rounded;
      case ExpenseCategory.electricity:
        return Icons.bolt_rounded;
      case ExpenseCategory.equipmentMaintenance:
        return Icons.fitness_center_rounded;
      case ExpenseCategory.trainerSalaries:
        return Icons.badge_rounded;
      case ExpenseCategory.cleaningSupplies:
        return Icons.cleaning_services_rounded;
      case ExpenseCategory.marketing:
        return Icons.campaign_rounded;
      case ExpenseCategory.supplements:
        return Icons.shopping_bag_rounded;
      case ExpenseCategory.misc:
        return Icons.receipt_long_rounded;
    }
  }

  Color get color {
    switch (this) {
      case ExpenseCategory.rent:
        return const Color(0xFF6366F1); // Indigo
      case ExpenseCategory.electricity:
        return const Color(0xFFF59E0B); // Amber
      case ExpenseCategory.equipmentMaintenance:
        return const Color(0xFFEC4899); // Pink
      case ExpenseCategory.trainerSalaries:
        return const Color(0xFF10B981); // Emerald
      case ExpenseCategory.cleaningSupplies:
        return const Color(0xFF06B6D4); // Cyan
      case ExpenseCategory.marketing:
        return const Color(0xFF8B5CF6); // Purple
      case ExpenseCategory.supplements:
        return const Color(0xFFF97316); // Orange
      case ExpenseCategory.misc:
        return const Color(0xFF64748B); // Slate
    }
  }

  static ExpenseCategory fromString(String? value) {
    if (value == null) return ExpenseCategory.misc;
    for (final cat in ExpenseCategory.values) {
      if (cat.name.toLowerCase() == value.toLowerCase()) {
        return cat;
      }
    }
    return ExpenseCategory.misc;
  }
}

class ExpenseRecord {
  final String id;
  final String title;
  final ExpenseCategory category;
  final double amount;
  final DateTime date;
  final String monthYear; // "YYYY-MM"
  final PaymentMethod paymentMethod;
  final String? notes;
  final String? receiptPath;

  const ExpenseRecord({
    required this.id,
    required this.title,
    required this.category,
    required this.amount,
    required this.date,
    required this.monthYear,
    this.paymentMethod = PaymentMethod.cash,
    this.notes,
    this.receiptPath,
  });

  ExpenseRecord copyWith({
    String? id,
    String? title,
    ExpenseCategory? category,
    double? amount,
    DateTime? date,
    String? monthYear,
    PaymentMethod? paymentMethod,
    String? notes,
    String? receiptPath,
  }) {
    return ExpenseRecord(
      id: id ?? this.id,
      title: title ?? this.title,
      category: category ?? this.category,
      amount: amount ?? this.amount,
      date: date ?? this.date,
      monthYear: monthYear ?? this.monthYear,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      notes: notes ?? this.notes,
      receiptPath: receiptPath ?? this.receiptPath,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'category': category.name,
      'amount': amount,
      'date': date.toIso8601String(),
      'monthYear': monthYear,
      'paymentMethod': paymentMethod.name,
      'notes': notes,
      'receiptPath': receiptPath,
    };
  }

  factory ExpenseRecord.fromMap(Map<String, dynamic> map) {
    final parsedDate = map['date'] != null
        ? DateTime.tryParse(map['date'] as String) ?? DateTime.now()
        : DateTime.now();

    final mYear = map['monthYear'] as String? ??
        '${parsedDate.year}-${parsedDate.month.toString().padLeft(2, '0')}';

    return ExpenseRecord(
      id: map['id'] as String? ?? '',
      title: map['title'] as String? ?? '',
      category: ExpenseCategory.fromString(map['category'] as String?),
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      date: parsedDate,
      monthYear: mYear,
      paymentMethod: PaymentMethod.fromString(map['paymentMethod'] as String?),
      notes: map['notes'] as String?,
      receiptPath: map['receiptPath'] as String?,
    );
  }

  String toJson() => json.encode(toMap());

  factory ExpenseRecord.fromJson(String source) =>
      ExpenseRecord.fromMap(json.decode(source) as Map<String, dynamic>);
}
