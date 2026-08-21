class InspectionRecord {
  const InspectionRecord({
    this.id,
    required this.inspectedAt,
    required this.contractor,
    required this.area,
    required this.shift,
    required this.reportedCount,
    required this.allPresent,
    required this.absenceDescription,
    required this.improvementAction,
    required this.photoPaths,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final DateTime inspectedAt;
  final String contractor;
  final String area;
  final String shift;
  final int reportedCount;
  final bool allPresent;
  final String absenceDescription;
  final String improvementAction;
  final List<String> photoPaths;
  final DateTime createdAt;
  final DateTime updatedAt;

  InspectionRecord copyWith({int? id, List<String>? photoPaths}) =>
      InspectionRecord(
        id: id ?? this.id,
        inspectedAt: inspectedAt,
        contractor: contractor,
        area: area,
        shift: shift,
        reportedCount: reportedCount,
        allPresent: allPresent,
        absenceDescription: absenceDescription,
        improvementAction: improvementAction,
        photoPaths: photoPaths ?? this.photoPaths,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  Map<String, Object?> toRow() => {
    'inspected_at': inspectedAt.toIso8601String(),
    'contractor': contractor,
    'area': area,
    'shift': shift,
    'reported_count': reportedCount,
    'all_present': allPresent ? 1 : 0,
    'absence_description': absenceDescription,
    'improvement_action': improvementAction,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  factory InspectionRecord.fromRows(
    Map<String, Object?> row,
    List<String> photos,
  ) {
    return InspectionRecord(
      id: row['id'] as int,
      inspectedAt: DateTime.parse(row['inspected_at'] as String),
      contractor: row['contractor'] as String,
      area: row['area'] as String,
      shift: row['shift'] as String,
      reportedCount: row['reported_count'] as int,
      allPresent: (row['all_present'] as int) == 1,
      absenceDescription: row['absence_description'] as String,
      improvementAction: row['improvement_action'] as String,
      photoPaths: photos,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }
}
