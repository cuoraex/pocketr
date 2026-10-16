import 'dart:convert';

import 'package:archive/archive.dart' as archive;
import 'package:excel/excel.dart' as xlsx;

import 'data.dart';

class ManualSaleImportRow {
  const ManualSaleImportRow({
    required this.date,
    required this.platform,
    required this.productName,
    required this.variant,
    required this.qty,
    required this.orderNo,
    required this.amountReceived,
    required this.hppPerUnit,
  });

  final String date;
  final String platform;
  final String productName;
  final String variant;
  final double qty;
  final String orderNo;
  final double amountReceived;
  final double? hppPerUnit;
}

List<ManualSaleImportRow> parseManualSalesWorkbook(List<int> bytes) {
  final workbook = xlsx.Excel.decodeBytes(_removeEmptyFormattedRows(bytes));
  final sheet = workbook.tables['Penjualan'] ?? workbook.tables['Sales'];
  if (sheet == null) {
    throw const FormatException(
      'Lembar Penjualan tidak ditemukan. Gunakan template impor manual PocketR.',
    );
  }

  String normalize(String value) => value
      .replaceAll('\ufeff', '')
      .trim()
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9]'), '');

  final headerIndex = sheet.rows.indexWhere((row) {
    final headers = row.map((cell) => normalize(cell?.value?.toString() ?? ''));
    return headers.contains('tanggal') || headers.contains('date');
  });
  if (headerIndex < 0) {
    throw const FormatException('Baris judul kolom template tidak ditemukan.');
  }

  final headers = sheet.rows[headerIndex]
      .map((cell) => normalize(cell?.value?.toString() ?? ''))
      .toList();
  final columns = <String, int>{};
  const aliases = {
    'date': ['tanggal', 'date'],
    'platform': ['platform'],
    'product': ['produk', 'product'],
    'variant': ['varian', 'variant'],
    'qty': ['qty'],
    'order': ['nopesanan', 'orderno'],
    'amount': ['uangditerima', 'amountreceived'],
    'hpp': ['hpppcs', 'cogsunit'],
  };
  for (final entry in aliases.entries) {
    final index = headers.indexWhere(entry.value.contains);
    if (index >= 0) columns[entry.key] = index;
  }
  for (final required in ['date', 'platform', 'product', 'qty', 'amount']) {
    if (!columns.containsKey(required)) {
      throw FormatException(
        'Kolom wajib "${_columnLabel(required)}" tidak ditemukan.',
      );
    }
  }

  String cell(List<xlsx.Data?> row, String key) {
    final index = columns[key];
    if (index == null || index >= row.length) return '';
    return row[index]?.value?.toString().trim() ?? '';
  }

  String? dateValue(xlsx.Data? cell) {
    final value = cell?.value;
    DateTime? date;
    DateTime? validDate(int year, int month, int day) {
      final parsed = DateTime(year, month, day);
      return parsed.year == year && parsed.month == month && parsed.day == day
          ? parsed
          : null;
    }

    if (value is xlsx.DateCellValue) {
      date = validDate(value.year, value.month, value.day);
    } else if (value is xlsx.DateTimeCellValue) {
      date = validDate(value.year, value.month, value.day);
    } else if (value is xlsx.IntCellValue || value is xlsx.DoubleCellValue) {
      final serial = value is xlsx.IntCellValue
          ? value.value.toDouble()
          : (value as xlsx.DoubleCellValue).value;
      if (serial.isFinite && serial >= 0 && serial <= 2958465) {
        date = DateTime(1899, 12, 30).add(Duration(days: serial.floor()));
      }
    } else {
      final input = value?.toString().trim() ?? '';
      final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(input);
      final local = RegExp(r'^(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})$')
          .firstMatch(input);
      if (iso != null) {
        date = validDate(
          int.parse(iso[1]!),
          int.parse(iso[2]!),
          int.parse(iso[3]!),
        );
      } else if (local != null) {
        date = validDate(
          int.parse(local[3]!),
          int.parse(local[2]!),
          int.parse(local[1]!),
        );
      }
    }
    if (date == null) return null;
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  double? numberValue(xlsx.Data? cell) {
    final value = cell?.value;
    if (value is xlsx.IntCellValue) return value.value.toDouble();
    if (value is xlsx.DoubleCellValue) return value.value;
    var input = value?.toString().trim().replaceAll(RegExp(r'[^0-9,.\-]'), '');
    if (input == null || input.isEmpty || input == '-') return null;
    final comma = input.lastIndexOf(',');
    final dot = input.lastIndexOf('.');
    if (comma >= 0 && dot >= 0) {
      input = comma > dot
          ? input.replaceAll('.', '').replaceFirst(',', '.')
          : input.replaceAll(',', '');
    } else if (comma >= 0) {
      final decimals = input.length - comma - 1;
      input = decimals == 1 || decimals == 2
          ? input.replaceFirst(',', '.')
          : input.replaceAll(',', '');
    } else if (dot >= 0) {
      final decimals = input.length - dot - 1;
      if (decimals != 1 && decimals != 2) input = input.replaceAll('.', '');
    }
    return double.tryParse(input);
  }

  final rows = <ManualSaleImportRow>[];
  for (var index = headerIndex + 1; index < sheet.rows.length; index++) {
    final row = sheet.rows[index];
    if (row.every(
      (cell) => cell?.value == null || cell!.value.toString().trim().isEmpty,
    )) {
      continue;
    }
    final rowNumber = index + 1;
    final date = dateValue(
      columns['date']! < row.length ? row[columns['date']!] : null,
    );
    if (date == null) {
      throw FormatException('Tanggal tidak valid pada baris $rowNumber.');
    }
    final platformInput = cell(row, 'platform').toLowerCase();
    final platform = marketplaceNames.entries
        .where(
          (entry) =>
              entry.key == platformInput ||
              (entry.key == 'lainnya' && platformInput == 'other') ||
              entry.value.toLowerCase() == platformInput,
        )
        .firstOrNull
        ?.key;
    if (platform == null) {
      throw FormatException('Platform tidak valid pada baris $rowNumber.');
    }
    final productName = cell(row, 'product');
    if (productName.isEmpty) {
      throw FormatException('Produk wajib diisi pada baris $rowNumber.');
    }
    final qty = numberValue(
      columns['qty']! < row.length ? row[columns['qty']!] : null,
    );
    if (qty == null || !qty.isFinite || qty <= 0) {
      throw FormatException('Qty harus lebih dari 0 pada baris $rowNumber.');
    }
    final amount = numberValue(
      columns['amount']! < row.length ? row[columns['amount']!] : null,
    );
    if (amount == null || !amount.isFinite || amount < 0) {
      throw FormatException('Uang diterima tidak valid pada baris $rowNumber.');
    }
    final hpp = numberValue(
      columns['hpp'] == null || columns['hpp']! >= row.length
          ? null
          : row[columns['hpp']!],
    );
    if (hpp != null && (!hpp.isFinite || hpp < 0)) {
      throw FormatException('HPP/Pcs tidak valid pada baris $rowNumber.');
    }
    rows.add(
      ManualSaleImportRow(
        date: date,
        platform: platform,
        productName: productName,
        variant: cell(row, 'variant'),
        qty: qty,
        orderNo: cell(row, 'order'),
        amountReceived: amount,
        hppPerUnit: hpp,
      ),
    );
  }
  if (rows.isEmpty) {
    throw const FormatException('Tidak ada baris penjualan untuk diimpor.');
  }
  return rows;
}

List<int> _removeEmptyFormattedRows(List<int> bytes) {
  final zippedWorkbook = archive.ZipDecoder().decodeBytes(bytes);
  final rowElement = RegExp(r'<row\b[^>]*>.*?</row>', dotAll: true);
  final valueElement = RegExp(r'<(?:v|f|t)\b[^>]*>\s*[^<\s]', dotAll: true);
  var changed = false;

  for (final file in zippedWorkbook.files) {
    if (!file.isFile ||
        !RegExp(r'^xl/worksheets/[^/]+\.xml$').hasMatch(file.name)) {
      continue;
    }
    final content = file.content;
    if (content is! List<int>) continue;
    final source = utf8.decode(content, allowMalformed: false);
    final compacted = source.replaceAllMapped(rowElement, (match) {
      final row = match.group(0)!;
      if (valueElement.hasMatch(row)) return row;
      changed = true;
      return '';
    });
    if (compacted != source) {
      final compactedBytes = utf8.encode(compacted);
      zippedWorkbook.addFile(
        archive.ArchiveFile(file.name, compactedBytes.length, compactedBytes),
      );
    }
  }
  if (!changed) return bytes;
  final compactedWorkbook = archive.ZipEncoder().encode(zippedWorkbook);
  if (compactedWorkbook == null) {
    throw const FormatException('Berkas Excel gagal diproses.');
  }
  return compactedWorkbook;
}

String _columnLabel(String key) => switch (key) {
  'date' => 'Tanggal / Date',
  'platform' => 'Platform',
  'product' => 'Produk / Product',
  'qty' => 'Qty',
  'amount' => 'Uang Diterima / Amount Received',
  _ => key,
};
