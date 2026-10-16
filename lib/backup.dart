import 'dart:convert';
import 'dart:typed_data';

import 'data.dart';
import 'local_file_archive.dart';

Uint8List createFullBackupBytes(
  FinanceData data,
  Iterable<ArchivedFile> files,
) {
  final backup = {
    'format': 'pocketr-backup',
    'version': 4,
    'data': data.toJson(includeImages: true),
    'files': files.map((file) => file.toJson()).toList(),
  };
  return Uint8List.fromList(utf8.encode(jsonEncode(backup)));
}
