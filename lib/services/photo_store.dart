import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

class PhotoStore {
  Future<Directory> get _root async =>
      Directory(p.join(await getDatabasesPath(), 'hse_files'));

  Future<String> importPhoto(String sourcePath, DateTime inspectedAt) async {
    final root = await _root;
    final relative = p.join(
      'photos',
      inspectedAt.year.toString().padLeft(4, '0'),
      inspectedAt.month.toString().padLeft(2, '0'),
      inspectedAt.day.toString().padLeft(2, '0'),
      '${const Uuid().v4()}.jpg',
    );
    final destination = File(p.join(root.path, relative));
    await destination.parent.create(recursive: true);
    await File(sourcePath).copy(destination.path);
    return relative;
  }

  Future<File> resolve(String relativePath) async =>
      File(p.join((await _root).path, relativePath));

  Future<void> deleteAll(Iterable<String> relativePaths) async {
    for (final path in relativePaths) {
      final file = await resolve(path);
      if (await file.exists()) await file.delete();
    }
  }
}
