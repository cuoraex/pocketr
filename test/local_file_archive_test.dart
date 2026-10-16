import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pocketr/local_file_archive.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory directory;
  late LocalFileArchive archive;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pocketr-file-archive-');
    archive = LocalFileArchive.withDirectory(directory);
  });

  tearDown(() async {
    await archive.close();
    await directory.delete(recursive: true);
  });

  test('stores original bytes and metadata in SQLite', () async {
    final bytes = Uint8List.fromList([0, 12, 127, 200, 255]);
    final id = await archive.saveFile(
      name: 'product photo.JPG',
      bytes: bytes,
      source: 'profile_photo',
    );

    final files = await archive.listFiles();
    expect(files, hasLength(1));
    expect(files.single.id, id);
    expect(files.single.name, 'product photo.JPG');
    expect(files.single.extension, 'jpg');
    expect(files.single.contentType, 'image/jpeg');
    expect(files.single.source, 'profile_photo');
    expect(files.single.sizeBytes, bytes.length);
    expect(files.single.bytes, bytes);
  });

  test(
    'stores application images by key and replaces them on update',
    () async {
      await archive.saveApplicationImage(
        key: 'product:1',
        mime: 'image/png',
        bytes: Uint8List.fromList([1, 2, 3]),
      );
      await archive.saveApplicationImage(
        key: 'product:1',
        mime: 'image/jpeg',
        bytes: Uint8List.fromList([4, 5]),
      );

      final image = await archive.applicationImage('product:1');

      expect(image?.mime, 'image/jpeg');
      expect(image?.bytes, [4, 5]);
      await archive.deleteApplicationImage('product:1');
      expect(await archive.applicationImage('product:1'), isNull);
    },
  );

  test(
    'migrates existing archived files to the PocketR database name',
    () async {
      final legacyPath = p.join(directory.path, 'rochinku_files.db');
      final legacyDatabase = sqlite3.open(legacyPath);
      legacyDatabase.execute('''
      CREATE TABLE imported_files (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        extension TEXT NOT NULL,
        content_type TEXT NOT NULL,
        source TEXT NOT NULL,
        imported_at TEXT NOT NULL,
        size_bytes INTEGER NOT NULL,
        bytes BLOB NOT NULL
      )
      ''');
      legacyDatabase.execute('''
      INSERT INTO imported_files
        (name, extension, content_type, source, imported_at, size_bytes, bytes)
      VALUES ('photo.png', 'png', 'image/png', 'profile_photo',
        '2026-10-13T00:00:00.000', 2, X'0102')
      ''');
      legacyDatabase.close();

      final files = await archive.listFiles();

      expect(files.single.name, 'photo.png');
      expect(files.single.bytes, [1, 2]);
      expect(File(legacyPath).existsSync(), isFalse);
      expect(
        File(p.join(directory.path, 'pocketr_files.db')).existsSync(),
        isTrue,
      );
    },
  );

  test('restores archived file records from JSON data', () async {
    final original = ArchivedFile(
      name: 'sales.csv',
      extension: 'csv',
      contentType: 'text/csv',
      source: 'sales_csv',
      importedAt: '2026-10-13T00:00:00.000',
      sizeBytes: 3,
      bytes: Uint8List.fromList([65, 44, 66]),
    );

    await archive.addRestoredFiles([ArchivedFile.fromJson(original.toJson())]);

    final files = await archive.listFiles();
    expect(files, hasLength(1));
    expect(files.single.name, 'sales.csv');
    expect(files.single.source, 'restored_backup');
    expect(files.single.bytes, [65, 44, 66]);
  });

  test('can exclude imported backup files from later exports', () async {
    await archive.saveFile(
      name: 'old-backup.json',
      bytes: Uint8List.fromList([1]),
      source: 'backup_restore',
    );
    await archive.saveFile(
      name: 'report.csv',
      bytes: Uint8List.fromList([2]),
      source: 'sales_csv',
    );

    final exportable = await archive.listFiles(includeRestoredBackups: false);
    expect(exportable.map((file) => file.name), ['report.csv']);
    expect(await archive.listFiles(), hasLength(2));
  });
}
