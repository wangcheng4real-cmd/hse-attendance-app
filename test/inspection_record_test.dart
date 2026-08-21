import 'package:flutter_test/flutter_test.dart';
import 'package:hse_attendance/models/inspection_record.dart';

void main() {
  test('record converts to and from database rows without losing fields', () {
    final time = DateTime(2026, 8, 20, 9, 30);
    final record = InspectionRecord(
      id: 7,
      inspectedAt: time,
      contractor: '测试施工单位',
      area: '一号区域',
      shift: '白班',
      reportedCount: 3,
      allPresent: false,
      absenceDescription: '缺岗1人',
      improvementAction: '立即补岗',
      photoPaths: const ['photos/2026/08/20/a.jpg'],
      createdAt: time,
      updatedAt: time,
    );
    final restored = InspectionRecord.fromRows({
      'id': 7,
      ...record.toRow(),
    }, record.photoPaths);
    expect(restored.contractor, '测试施工单位');
    expect(restored.reportedCount, 3);
    expect(restored.allPresent, isFalse);
    expect(restored.photoPaths, hasLength(1));
    expect(restored.inspectedAt, time);
  });
}
