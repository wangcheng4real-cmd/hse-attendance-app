import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hse_attendance/models/inspection_record.dart';
import 'package:hse_attendance/services/excel_exporter.dart';
import 'package:hse_attendance/services/photo_store.dart';

void main() {
  test('xlsx contains the required title, headers and record data', () {
    final time = DateTime(2026, 8, 20, 21, 15);
    final record = InspectionRecord(
      inspectedAt: time,
      contractor: '核建单位',
      area: '反应堆厂房',
      shift: '夜班',
      reportedCount: 4,
      allPresent: true,
      absenceDescription: '',
      improvementAction: '',
      photoPaths: const [],
      createdAt: time,
      updatedAt: time,
    );
    final bytes = ExcelExporter(PhotoStore()).buildWorkbookForTesting([record]);
    final archive = ZipDecoder().decodeBytes(bytes);
    final sheet = archive.findFile('xl/worksheets/sheet1.xml');
    expect(sheet, isNotNull);
    final xml = utf8.decode(sheet!.content as List<int>);
    expect(xml, contains('施工单位现场安全人员在岗验证检查表'));
    expect(xml, contains('报送安全人员数量'));
    expect(xml, contains('核建单位'));
    expect(xml, contains('反应堆厂房'));
    expect(xml, contains('2026-08-20 21:15'));
    expect(archive.findFile('[Content_Types].xml'), isNotNull);
  });
}
