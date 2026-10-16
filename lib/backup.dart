import 'dart:convert';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'data.dart';
import 'local_file_archive.dart';

String ensureBackupFileExtension(String path) {
  final extension = p.extension(path).toLowerCase();
  if (extension == '.pcktr' || extension == '.json') return path;
  return '$path.pcktr';
}

Uint8List createFullBackupBytes(
  FinanceData data,
  Iterable<ArchivedFile> files,
) {
  return createFullBackupBytesFromPayload(createFullBackupPayload(data, files));
}

Map<String, Object?> createFullBackupPayload(
  FinanceData data,
  Iterable<ArchivedFile> files,
) => {
  'data': data.toJson(includeImages: true),
  'files': files
      .map(
        (file) => <String, Object?>{
          'name': file.name,
          'extension': file.extension,
          'contentType': file.contentType,
          'source': file.source,
          'importedAt': file.importedAt,
          'sizeBytes': file.sizeBytes,
          'bytes': file.bytes,
        },
      )
      .toList(growable: false),
};

Uint8List createFullBackupBytesFromPayload(Map<String, Object?> payload) {
  final files = (payload['files'] as List)
      .map((file) {
        final serializedFile = Map<String, Object?>.from(file as Map);
        serializedFile['bytes'] = base64Encode(
          serializedFile['bytes'] as Uint8List,
        );
        return serializedFile;
      })
      .toList(growable: false);
  final backup = {
    'format': 'pocketr-backup',
    'version': 4,
    'data': payload['data'],
    'files': files,
  };
  return Uint8List.fromList(utf8.encode(jsonEncode(backup)));
}
