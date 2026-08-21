import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/inspection_record.dart';

class RecordFilter {
  const RecordFilter({
    this.start,
    this.end,
    this.contractor,
    this.area,
    this.shift,
  });
  final DateTime? start;
  final DateTime? end;
  final String? contractor;
  final String? area;
  final String? shift;
}

class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();
  Database? _database;

  Future<Database> get database async => _database ??= await _open();

  Future<Database> _open() async {
    final path = p.join(await getDatabasesPath(), 'hse_attendance.db');
    return openDatabase(
      path,
      version: 1,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, _) async {
        await db.execute('''CREATE TABLE records(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        inspected_at TEXT NOT NULL,
        contractor TEXT NOT NULL,
        area TEXT NOT NULL,
        shift TEXT NOT NULL CHECK(shift IN ('白班','夜班')),
        reported_count INTEGER NOT NULL CHECK(reported_count >= 0),
        all_present INTEGER NOT NULL CHECK(all_present IN (0,1)),
        absence_description TEXT NOT NULL DEFAULT '',
        improvement_action TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )''');
        await db.execute('''CREATE TABLE photos(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        record_id INTEGER NOT NULL,
        relative_path TEXT NOT NULL,
        sort_order INTEGER NOT NULL,
        FOREIGN KEY(record_id) REFERENCES records(id) ON DELETE CASCADE
      )''');
        await db.execute(
          'CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE suggestions(kind TEXT NOT NULL, value TEXT NOT NULL, UNIQUE(kind,value))',
        );
        await db.execute(
          'CREATE INDEX idx_records_inspected_at ON records(inspected_at)',
        );
      },
    );
  }

  Future<String?> getSetting(String key) async {
    final db = await database;
    final rows = await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert('settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<String>> suggestions(String kind) async {
    final db = await database;
    final rows = await db.query(
      'suggestions',
      columns: ['value'],
      where: 'kind = ?',
      whereArgs: [kind],
      orderBy: 'value COLLATE NOCASE',
    );
    return rows.map((e) => e['value'] as String).toList();
  }

  Future<int> save(InspectionRecord record) async {
    final db = await database;
    return db.transaction((txn) async {
      final data = record.toRow();
      late final int recordId;
      if (record.id == null) {
        recordId = await txn.insert('records', data);
      } else {
        recordId = record.id!;
        await txn.update(
          'records',
          data,
          where: 'id = ?',
          whereArgs: [recordId],
        );
      }
      await txn.delete('photos', where: 'record_id = ?', whereArgs: [recordId]);
      for (var i = 0; i < record.photoPaths.length; i++) {
        await txn.insert('photos', {
          'record_id': recordId,
          'relative_path': record.photoPaths[i],
          'sort_order': i,
        });
      }
      for (final item in [
        ('contractor', record.contractor),
        ('area', record.area),
      ]) {
        await txn.insert('suggestions', {
          'kind': item.$1,
          'value': item.$2,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      return recordId;
    });
  }

  Future<List<InspectionRecord>> records({
    RecordFilter filter = const RecordFilter(),
    bool ascending = false,
  }) async {
    final db = await database;
    final conditions = <String>[];
    final args = <Object?>[];
    if (filter.start != null) {
      conditions.add('inspected_at >= ?');
      args.add(filter.start!.toIso8601String());
    }
    if (filter.end != null) {
      conditions.add('inspected_at <= ?');
      args.add(filter.end!.toIso8601String());
    }
    if (filter.contractor?.trim().isNotEmpty == true) {
      conditions.add('contractor = ?');
      args.add(filter.contractor!.trim());
    }
    if (filter.area?.trim().isNotEmpty == true) {
      conditions.add('area = ?');
      args.add(filter.area!.trim());
    }
    if (filter.shift?.isNotEmpty == true) {
      conditions.add('shift = ?');
      args.add(filter.shift);
    }
    final rows = await db.query(
      'records',
      where: conditions.isEmpty ? null : conditions.join(' AND '),
      whereArgs: args,
      orderBy: 'inspected_at ${ascending ? 'ASC' : 'DESC'}',
    );
    final result = <InspectionRecord>[];
    for (final row in rows) {
      final photos = await db.query(
        'photos',
        columns: ['relative_path'],
        where: 'record_id = ?',
        whereArgs: [row['id']],
        orderBy: 'sort_order',
      );
      result.add(
        InspectionRecord.fromRows(
          row,
          photos.map((p) => p['relative_path'] as String).toList(),
        ),
      );
    }
    return result;
  }

  Future<void> delete(int id) async =>
      (await database).delete('records', where: 'id = ?', whereArgs: [id]);

  Future<(int total, int absent)> todaySummary() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) total, SUM(CASE WHEN all_present=0 THEN 1 ELSE 0 END) absent FROM records WHERE inspected_at >= ? AND inspected_at < ?',
      [start.toIso8601String(), end.toIso8601String()],
    );
    return (
      (rows.first['total'] as int?) ?? 0,
      (rows.first['absent'] as int?) ?? 0,
    );
  }
}
