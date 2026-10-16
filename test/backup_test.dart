import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketr/backup.dart';
import 'package:pocketr/data.dart';
import 'package:pocketr/local_file_archive.dart';

void main() {
  test('backup file extension defaults to pcktr', () {
    expect(
      ensureBackupFileExtension(r'C:\backups\my-backup'),
      r'C:\backups\my-backup.pcktr',
    );
    expect(
      ensureBackupFileExtension(r'C:\backups\my-backup.pcktr'),
      r'C:\backups\my-backup.pcktr',
    );
    expect(
      ensureBackupFileExtension(r'C:\backups\my-backup.JSON'),
      r'C:\backups\my-backup.JSON',
    );
  });

  test('full backup includes all data, photos, and archived files', () async {
    final data = FinanceData(
      logo: 'data:image/png;base64,bG9nbw==',
      products: [Product(name: 'Tas', img: 'data:image/jpeg;base64,cGhvdG8=')],
      targetRevenue: 125000,
    );
    final files = [
      ArchivedFile(
        name: 'sales.csv',
        extension: 'csv',
        contentType: 'text/csv',
        source: 'sales_import',
        importedAt: '2026-10-16T00:00:00.000',
        sizeBytes: 3,
        bytes: Uint8List.fromList([65, 44, 66]),
      ),
    ];

    final backup = jsonDecode(
      utf8.decode(
        await compute(
          createFullBackupBytesFromPayload,
          createFullBackupPayload(data, files),
        ),
      ),
    ) as Map<String, dynamic>;

    expect(backup['format'], 'pocketr-backup');
    expect(backup['version'], 4);
    final restoredData = FinanceData.fromBackup(jsonEncode(backup));
    expect(restoredData.logo, data.logo);
    expect(restoredData.products.single.img, data.products.single.img);
    expect(restoredData.targetRevenue, 125000);
    final restoredFiles = (backup['files'] as List)
        .map((file) => ArchivedFile.fromJson(Map<String, dynamic>.from(file)))
        .toList();
    expect(restoredFiles.single.name, 'sales.csv');
    expect(restoredFiles.single.bytes, [65, 44, 66]);
  });
}
