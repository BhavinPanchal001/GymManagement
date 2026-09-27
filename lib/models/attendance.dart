import 'dart:convert';

enum AttendanceStatus {
  present,
  absent,
  rest;

  String get label {
    switch (this) {
      case AttendanceStatus.present:
        return 'Present';
      case AttendanceStatus.absent:
        return 'Absent';
      case AttendanceStatus.rest:
        return 'Rest Day';
    }
  }

  static AttendanceStatus fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'present':
        return AttendanceStatus.present;
      case 'absent':
        return AttendanceStatus.absent;
      case 'rest':
      case 'restday':
        return AttendanceStatus.rest;
      default:
        return AttendanceStatus.present;
    }
  }
}

class AttendanceRecord {
  final String id;
  final String customerId;
  /// Format: "YYYY-MM-DD" for unambiguous day indexing
  final String dateKey;
  final AttendanceStatus status;
  final DateTime recordedAt;

  const AttendanceRecord({
    required this.id,
    required this.customerId,
    required this.dateKey,
    required this.status,
    required this.recordedAt,
  });

  AttendanceRecord copyWith({
    String? id,
    String? customerId,
    String? dateKey,
    AttendanceStatus? status,
    DateTime? recordedAt,
  }) {
    return AttendanceRecord(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      dateKey: dateKey ?? this.dateKey,
      status: status ?? this.status,
      recordedAt: recordedAt ?? this.recordedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'customerId': customerId,
      'dateKey': dateKey,
      'status': status.name,
      'recordedAt': recordedAt.toIso8601String(),
    };
  }

  factory AttendanceRecord.fromMap(Map<String, dynamic> map) {
    return AttendanceRecord(
      id: map['id'] as String? ?? '',
      customerId: map['customerId'] as String? ?? '',
      dateKey: map['dateKey'] as String? ?? '',
      status: AttendanceStatus.fromString(map['status'] as String?),
      recordedAt: map['recordedAt'] != null
          ? DateTime.tryParse(map['recordedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  String toJson() => json.encode(toMap());

  factory AttendanceRecord.fromJson(String source) =>
      AttendanceRecord.fromMap(json.decode(source) as Map<String, dynamic>);
}
