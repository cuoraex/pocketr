import 'package:excel/excel.dart' as xlsx;

import 'data.dart';
import 'excel_formula.dart';

class HppImportRow {
  const HppImportRow({
    required this.productName,
    required this.itemName,
    required this.category,
    required this.qty,
    required this.unit,
    required this.price,
  });

  final String productName;
  final String itemName;
  final MaterialCategory category;
  final double qty;
  final String unit;
  final double price;
}

List<HppImportRow> parseHppWorkbook(List<int> bytes) {
  final workbook = xlsx.Excel.decodeBytes(bytes);
  final sheet = workbook.tables['HPP'];
  if (sheet == null) {
    throw const FormatException(
      'Lembar HPP tidak ditemukan. Gunakan template impor HPP PocketR.',
    );
  }

  String normalize(String value) => value
      .replaceAll('\ufeff', '')
      .trim()
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9]'), '');

  final headerIndex = sheet.rows.indexWhere((row) {
    final headers = row.map((cell) => normalize(cell?.value?.toString() ?? ''));
    return headers.contains('namaproduk') || headers.contains('productname');
  });
  if (headerIndex < 0) {
    throw const FormatException('Baris judul kolom HPP tidak ditemukan.');
  }

  final headers = sheet.rows[headerIndex]
      .map((cell) => normalize(cell?.value?.toString() ?? ''))
      .toList();
  final columns = <String, int>{};
  const aliases = {
    'product': ['namaproduk', 'productname', 'produk', 'product'],
    'category': ['jenis', 'jenisbiaya', 'category', 'type'],
    'item': ['namabahanbakuongkos', 'namabahanbaku', 'namaongkos', 'itemname'],
    'qty': ['qty', 'jumlah', 'kuantitas'],
    'unit': ['satuan', 'unit'],
    'price': [
      'harga',
      'hargasatuan',
      'hargasatuanrp',
      'pricesatuan',
      'unitprice',
    ],
  };
  for (final entry in aliases.entries) {
    final index = headers.indexWhere(entry.value.contains);
    if (index >= 0) columns[entry.key] = index;
  }
  for (final required in [
    'product',
    'category',
    'item',
    'qty',
    'unit',
    'price',
  ]) {
    if (!columns.containsKey(required)) {
      throw FormatException(
        'Kolom wajib "${_hppColumnLabel(required)}" tidak ditemukan.',
      );
    }
  }

  String cell(List<xlsx.Data?> row, String key) {
    final index = columns[key]!;
    if (index >= row.length) return '';
    return row[index]?.value?.toString().trim() ?? '';
  }

  double? numberValue(xlsx.Data? cell, [Set<String>? evaluating]) {
    if (cell == null) return null;
    final value = cell.value;
    if (value is xlsx.IntCellValue) return value.value.toDouble();
    if (value is xlsx.DoubleCellValue) return value.value;
    if (value is xlsx.FormulaCellValue) {
      final coordinate = '${cell.rowIndex}:${cell.columnIndex}';
      final path = evaluating ?? <String>{};
      if (!path.add(coordinate)) {
        throw const FormatException('Rumus Excel memiliki referensi berulang.');
      }
      try {
        return evaluateExcelFormula(
          value.formula,
          (columnIndex, rowIndex) {
            final referenced =
                sheet.cell(
                  xlsx.CellIndex.indexByColumnRow(
                    columnIndex: columnIndex,
                    rowIndex: rowIndex,
                  ),
                );
            final referencedValue = numberValue(referenced, path);
            if (referencedValue == null) {
              throw FormatException(
                'Rumus merujuk ke sel kosong atau non-angka '
                '(${columnIndex + 1},${rowIndex + 1}).',
              );
            }
            return referencedValue;
          },
        );
      } finally {
        path.remove(coordinate);
      }
    }
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

  double? rowNumberValue(
    List<xlsx.Data?> row,
    String key,
    int rowNumber,
  ) {
    final columnIndex = columns[key]!;
    try {
      return numberValue(columnIndex < row.length ? row[columnIndex] : null);
    } on FormatException catch (error) {
      throw FormatException(
        '${_hppColumnLabel(key)} tidak valid pada baris $rowNumber: ${error.message}',
      );
    }
  }

  MaterialCategory? parseCategory(String value) => switch (normalize(value)) {
    'bahanbaku' || 'material' || 'rawmaterial' => MaterialCategory.bahanBaku,
    'ongkos' ||
    'sewing' ||
    'sewingcost' ||
    'ongkosjahit' => MaterialCategory.ongkosJahit,
    _ => null,
  };

  final rows = <HppImportRow>[];
  for (var index = headerIndex + 1; index < sheet.rows.length; index++) {
    final row = sheet.rows[index];
    if (row.every(
      (cell) => cell?.value == null || cell!.value.toString().trim().isEmpty,
    )) {
      continue;
    }
    final rowNumber = index + 1;
    final productName = cell(row, 'product');
    if (productName.isEmpty) {
      throw FormatException('Nama produk wajib diisi pada baris $rowNumber.');
    }
    final itemName = cell(row, 'item');
    if (itemName.isEmpty) {
      throw FormatException(
        'Nama bahan baku/ongkos wajib diisi pada baris $rowNumber.',
      );
    }
    final category = parseCategory(cell(row, 'category'));
    if (category == null) {
      throw FormatException(
        'Jenis biaya harus "Bahan baku" atau "Ongkos" pada baris $rowNumber.',
      );
    }
    final qty = rowNumberValue(row, 'qty', rowNumber);
    if (qty == null || !qty.isFinite || qty <= 0) {
      throw FormatException('Qty harus lebih dari 0 pada baris $rowNumber.');
    }
    final unit = cell(row, 'unit');
    if (unit.isEmpty) {
      throw FormatException('Satuan wajib diisi pada baris $rowNumber.');
    }
    final price = rowNumberValue(row, 'price', rowNumber);
    if (price == null || !price.isFinite || price < 0) {
      throw FormatException('Harga tidak valid pada baris $rowNumber.');
    }
    rows.add(
      HppImportRow(
        productName: productName,
        itemName: itemName,
        category: category,
        qty: qty,
        unit: unit,
        price: price,
      ),
    );
  }
  if (rows.isEmpty) {
    throw const FormatException('Tidak ada rincian HPP untuk diimpor.');
  }
  return rows;
}

String _hppColumnLabel(String key) => switch (key) {
  'product' => 'Nama produk',
  'category' => 'Jenis biaya',
  'item' => 'Nama bahan baku/ongkos',
  'qty' => 'Qty',
  'unit' => 'Satuan',
  'price' => 'Harga satuan',
  _ => key,
};
