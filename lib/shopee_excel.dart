import 'dart:convert';

import 'package:archive/archive.dart' as archive;
import 'package:excel/excel.dart' as xlsx;
import 'package:flutter/foundation.dart';

xlsx.Excel _decodeShopeeWorkbookBytes(Uint8List bytes) {
  final zippedWorkbook = archive.ZipDecoder().decodeBytes(bytes);
  final relationships = zippedWorkbook.findFile('xl/_rels/workbook.xml.rels');
  if (relationships == null) {
    throw const FormatException(
      'Berkas Excel tidak memiliki struktur buku kerja.',
    );
  }

  final relationshipContent = relationships.content;
  if (relationshipContent is! List<int>) {
    throw const FormatException(
      'Keterkaitan antarlembar kerja tidak dapat dibaca.',
    );
  }

  final originalXml = utf8.decode(relationshipContent, allowMalformed: false);
  final normalizedXml = originalXml.replaceAllMapped(
    RegExp(r'''(Target\s*=\s*["'])/xl/'''),
    (match) => '${match[1]}',
  );
  if (normalizedXml == originalXml) {
    return xlsx.Excel.decodeBytes(bytes);
  }

  final normalizedBytes = Uint8List.fromList(utf8.encode(normalizedXml));
  zippedWorkbook.addFile(
    archive.ArchiveFile(
      relationships.name,
      normalizedBytes.length,
      normalizedBytes,
    ),
  );
  final encodedWorkbook = archive.ZipEncoder().encode(zippedWorkbook);
  if (encodedWorkbook == null) {
    throw const FormatException('Berkas Excel Shopee gagal diproses.');
  }
  return xlsx.Excel.decodeBytes(encodedWorkbook);
}

Future<List<List<List<String>>>> decodeShopeeWorkbookRows(Uint8List bytes) =>
    compute(_decodeShopeeWorkbookRows, bytes);

int? findShopeeOrderDateColumnIndex(List<String> headers) {
  final normalizedHeaders = headers
      .map((header) => header.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), ''))
      .toList();
  for (final alias in ['waktupesanandibuat', 'waktupembayarandilakukan']) {
    final index = normalizedHeaders.indexOf(alias);
    if (index >= 0) return index;
  }
  return null;
}

List<List<List<String>>> _decodeShopeeWorkbookRows(Uint8List bytes) {
  final workbook = _decodeShopeeWorkbookBytes(bytes);
  return workbook.tables.values
      .map(
        (sheet) => sheet.rows
            .map(
              (row) => row.map((cell) {
                final value = cell?.value;
                return switch (value) {
                  null => '',
                  xlsx.TextCellValue() => value.value.text ?? '',
                  _ => value.toString(),
                }.trim();
              }).toList(),
            )
            .toList(),
      )
      .toList();
}
