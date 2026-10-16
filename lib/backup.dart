import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'data.dart';
import 'finance_database.dart';
import 'local_file_archive.dart';

String ensureBackupFileExtension(String path) {
  final extension = p.extension(path).toLowerCase();
  if (extension == '.pcktr' || extension == '.db') return path;
  final withoutJsonExtension = extension == '.json'
      ? path.substring(0, path.length - p.extension(path).length)
      : path;
  return '$withoutJsonExtension.pcktr';
}

Uint8List createBackupBytes(FinanceData data) =>
    FinanceSqliteStore.createBackupBytes(data, includeFiles: false);

Uint8List createFullBackupBytes(
  FinanceData data,
  Iterable<ArchivedFile> files,
) => FinanceSqliteStore.createBackupBytes(
  data,
  files: files.toList(growable: false),
  includeFiles: true,
);

Future<File> writeOverwriteBackup(String targetPath, Uint8List bytes) async {
  final directory = Directory(p.dirname(targetPath));
  if (!await directory.exists()) {
    throw FileSystemException('Folder backup tidak ditemukan.', directory.path);
  }
  // Write to a temp file first so a failed write never corrupts the last good
  // auto-save.
  final temp = File('$targetPath.tmp');
  await temp.writeAsBytes(bytes, flush: true);
  final target = File(targetPath);
  try {
    return await temp.rename(targetPath);
  } on FileSystemException {
    if (await target.exists()) await target.delete();
    return temp.rename(targetPath);
  }
}

Future<File> writeTimestampedBackup(
  String selectedPath,
  Uint8List bytes, {
  required String prefix,
  DateTime? now,
}) async {
  final directory = Directory(p.dirname(selectedPath));
  if (!await directory.exists()) {
    throw FileSystemException('Folder backup tidak ditemukan.', directory.path);
  }
  final date = now ?? DateTime.now();
  final timestamp =
      '${date.year.toString().padLeft(4, '0')}'
      '${date.month.toString().padLeft(2, '0')}'
      '${date.day.toString().padLeft(2, '0')}-'
      '${date.hour.toString().padLeft(2, '0')}'
      '${date.minute.toString().padLeft(2, '0')}'
      '${date.second.toString().padLeft(2, '0')}-'
      '${date.millisecond.toString().padLeft(3, '0')}';
  var suffix = 0;
  var backup = File('');
  do {
    backup = File(
      p.join(
        directory.path,
        '$prefix$timestamp-${suffix.toString().padLeft(4, '0')}.pcktr',
      ),
    );
    suffix++;
  } while (await backup.exists());
  await backup.writeAsBytes(bytes, flush: true);

  final versionPattern = RegExp(
    '^${RegExp.escape(prefix)}\\d{8}-\\d{6}-\\d{3}-\\d{4}\\.pcktr\$',
  );
  final versions = <File>[];
  await for (final entry in directory.list(followLinks: false)) {
    if (entry is File && versionPattern.hasMatch(p.basename(entry.path))) {
      versions.add(entry);
    }
  }
  versions.sort(
    (first, second) =>
        p.basename(second.path).compareTo(p.basename(first.path)),
  );
  for (final oldVersion in versions.skip(7)) {
    await oldVersion.delete();
  }
  return backup;
}
