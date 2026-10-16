import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

class ArchivedFile {
  const ArchivedFile({
    this.id,
    required this.name,
    required this.extension,
    required this.contentType,
    required this.source,
    required this.importedAt,
    required this.sizeBytes,
    required this.bytes,
  });

  final int? id;
  final String name;
  final String extension;
  final String contentType;
  final String source;
  final String importedAt;
  final int sizeBytes;
  final Uint8List bytes;

  Map<String, Object> toJson() => {
    'name': name,
    'extension': extension,
    'contentType': contentType,
    'source': source,
    'importedAt': importedAt,
    'sizeBytes': sizeBytes,
    'bytes': base64Encode(bytes),
  };

  factory ArchivedFile.fromJson(Map<String, dynamic> json) {
    final bytes = Uint8List.fromList(base64Decode('${json['bytes'] ?? ''}'));
    final name = '${json['name'] ?? ''}';
    if (name.isEmpty) {
      throw const FormatException('Data berkas arsip tidak valid.');
    }
    return ArchivedFile(
      name: name,
      extension: '${json['extension'] ?? ''}',
      contentType: '${json['contentType'] ?? 'application/octet-stream'}',
      source: '${json['source'] ?? 'restored_backup'}',
      importedAt: '${json['importedAt'] ?? DateTime.now().toIso8601String()}',
      sizeBytes: bytes.length,
      bytes: bytes,
    );
  }
}

class ApplicationImage {
  const ApplicationImage({required this.mime, required this.bytes});

  final String mime;
  final Uint8List bytes;
}

class LocalFileArchive {
  LocalFileArchive() : _directory = null;

  LocalFileArchive.withDirectory(Directory directory) : _directory = directory;

  static final instance = LocalFileArchive();

  final Directory? _directory;
  Future<Database>? _opening;

  Future<int> saveFile({
    required String name,
    required Uint8List bytes,
    required String source,
  }) async {
    if (name.trim().isEmpty) {
      throw ArgumentError.value(
        name,
        'name',
        'Nama berkas tidak boleh kosong.',
      );
    }
    final extension = _extensionOf(name);
    final database = await _open();
    database.execute(
      '''
      INSERT INTO imported_files
        (name, extension, content_type, source, imported_at, size_bytes, bytes)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        name,
        extension,
        _contentTypeOf(extension),
        source,
        DateTime.now().toIso8601String(),
        bytes.length,
        bytes,
      ],
    );
    return database.lastInsertRowId;
  }

  Future<void> saveApplicationImage({
    required String key,
    required String mime,
    required Uint8List bytes,
  }) async {
    final database = await _open();
    _ensureApplicationImagesTable(database);
    database.execute(
      '''
      INSERT INTO application_images (image_key, mime, bytes)
      VALUES (?, ?, ?)
      ON CONFLICT(image_key) DO UPDATE SET mime = excluded.mime, bytes = excluded.bytes
      ''',
      [key, mime, bytes],
    );
  }

  Future<ApplicationImage?> applicationImage(String key) async {
    final database = await _open();
    _ensureApplicationImagesTable(database);
    final rows = database.select(
      'SELECT mime, bytes FROM application_images WHERE image_key = ?',
      [key],
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    return ApplicationImage(
      mime: row['mime'] as String,
      bytes: Uint8List.fromList(row['bytes'] as List<int>),
    );
  }

  Future<void> deleteApplicationImage(String key) async {
    final database = await _open();
    _ensureApplicationImagesTable(database);
    database.execute('DELETE FROM application_images WHERE image_key = ?', [
      key,
    ]);
  }

  Future<List<ArchivedFile>> listFiles({
    bool includeRestoredBackups = true,
  }) async {
    final database = await _open();
    final rows = database.select('''
      SELECT id, name, extension, content_type, source, imported_at, size_bytes, bytes
      FROM imported_files
      ${includeRestoredBackups ? '' : "WHERE source != 'backup_restore'"}
      ORDER BY id
      ''');
    return [
      for (final row in rows)
        ArchivedFile(
          id: row['id'] as int,
          name: row['name'] as String,
          extension: row['extension'] as String,
          contentType: row['content_type'] as String,
          source: row['source'] as String,
          importedAt: row['imported_at'] as String,
          sizeBytes: row['size_bytes'] as int,
          bytes: Uint8List.fromList(row['bytes'] as List<int>),
        ),
    ];
  }

  Future<void> addRestoredFiles(List<ArchivedFile> files) async {
    if (files.isEmpty) return;
    final database = await _open();
    database.execute('BEGIN IMMEDIATE');
    final statement = database.prepare('''
      INSERT INTO imported_files
        (name, extension, content_type, source, imported_at, size_bytes, bytes)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      ''');
    try {
      for (final file in files) {
        statement.execute([
          file.name,
          file.extension,
          file.contentType,
          'restored_backup',
          file.importedAt,
          file.bytes.length,
          file.bytes,
        ]);
      }
      database.execute('COMMIT');
    } catch (_) {
      database.execute('ROLLBACK');
      rethrow;
    } finally {
      statement.close();
    }
  }

  Future<void> close() async {
    final opening = _opening;
    if (opening == null) return;
    (await opening).close();
    _opening = null;
  }

  Future<Database> _open() => _opening ??= _openDatabase();

  Future<Database> _openDatabase() async {
    final directory = _directory ?? await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    final databasePath = p.join(directory.path, 'pocketr_files.db');
    final legacyDatabase = File(p.join(directory.path, 'rochinku_files.db'));
    if (await legacyDatabase.exists() && !await File(databasePath).exists()) {
      await legacyDatabase.rename(databasePath);
    }
    final database = sqlite3.open(databasePath);
    database.execute('''
      CREATE TABLE IF NOT EXISTS imported_files (
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
    _ensureApplicationImagesTable(database);
    return database;
  }

  void _ensureApplicationImagesTable(Database database) {
    database.execute('''
      CREATE TABLE IF NOT EXISTS application_images (
        image_key TEXT PRIMARY KEY,
        mime TEXT NOT NULL,
        bytes BLOB NOT NULL
      )
      ''');
  }

  static String _extensionOf(String name) {
    final basename = p.basename(name);
    final separator = basename.lastIndexOf('.');
    return separator < 0 ? '' : basename.substring(separator + 1).toLowerCase();
  }

  static String _contentTypeOf(String extension) => switch (extension) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    'gif' => 'image/gif',
    'pdf' => 'application/pdf',
    'json' => 'application/json',
    'csv' => 'text/csv',
    'txt' => 'text/plain',
    'xlsx' =>
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    _ => 'application/octet-stream',
  };
}
