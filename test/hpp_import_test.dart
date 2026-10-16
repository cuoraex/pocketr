import 'dart:convert';

import 'package:archive/archive.dart' as archive;
import 'package:excel/excel.dart' as xlsx;
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketr/data.dart';
import 'package:pocketr/hpp_import.dart';
import 'package:pocketr/hpp_template.dart';

void main() {
  test('template workbook contains HPP and guide sheets', () {
    final bytes = createHppTemplateBytes();
    final workbook = xlsx.Excel.decodeBytes(bytes);

    expect(workbook.tables.keys, containsAll(['HPP', 'Panduan']));
    expect(
      workbook.tables['HPP']!.rows.first
          .map((cell) => cell?.value.toString())
          .toList(),
      [
        'Nama produk',
        'Jenis biaya',
        'Nama bahan baku/ongkos',
        'Qty',
        'Satuan',
        'Harga satuan (Rp)',
      ],
    );
    final zip = archive.ZipDecoder().decodeBytes(bytes);
    final hppXml = utf8.decode(
      zip.findFile('xl/worksheets/sheet1.xml')!.content as List<int>,
    );
    expect(hppXml, contains('sqref="B2:B1000"'));
    expect(hppXml, contains('"Bahan baku,Ongkos"'));
  });

  test('parses product-specific material and sewing cost rows', () {
    final workbook = xlsx.Excel.createExcel();
    final defaultSheet = workbook.tables.keys.first;
    workbook.rename(defaultSheet, 'HPP');
    final sheet = workbook['HPP'];
    sheet.appendRow([
      for (final header in [
        'Nama produk',
        'Jenis biaya',
        'Nama bahan baku/ongkos',
        'Qty',
        'Satuan',
        'Harga satuan (Rp)',
      ])
        xlsx.TextCellValue(header),
    ]);
    sheet.appendRow([
      xlsx.TextCellValue('Tas Kanvas'),
      xlsx.TextCellValue('Bahan baku'),
      xlsx.TextCellValue('Kain'),
      xlsx.DoubleCellValue(1.5),
      xlsx.TextCellValue('meter'),
      xlsx.IntCellValue(35000),
    ]);
    sheet.appendRow([
      xlsx.TextCellValue('Tas Kanvas'),
      xlsx.TextCellValue('Ongkos'),
      xlsx.TextCellValue('Jahit tas'),
      xlsx.IntCellValue(1),
      xlsx.TextCellValue('pcs'),
      xlsx.IntCellValue(15000),
    ]);
    sheet.appendRow([
      xlsx.TextCellValue('Dompet'),
      xlsx.TextCellValue('Bahan baku'),
      xlsx.TextCellValue('Kulit sintetis'),
      xlsx.IntCellValue(2),
      xlsx.TextCellValue('lembar'),
      xlsx.TextCellValue('12.500'),
    ]);

    final rows = parseHppWorkbook(workbook.encode()!);

    expect(rows, hasLength(3));
    expect(rows[0].productName, 'Tas Kanvas');
    expect(rows[0].qty, 1.5);
    expect(rows[0].category, MaterialCategory.bahanBaku);
    expect(rows[1].category, MaterialCategory.ongkosJahit);
    expect(rows[2].price, 12500);
  });

  test('evaluates arithmetic formulas and cell references', () {
    final workbook = xlsx.Excel.createExcel();
    final defaultSheet = workbook.tables.keys.first;
    workbook.rename(defaultSheet, 'HPP');
    final sheet = workbook['HPP'];
    sheet.appendRow([
      for (final header in [
        'Nama produk',
        'Jenis biaya',
        'Nama bahan baku/ongkos',
        'Qty',
        'Satuan',
        'Harga satuan (Rp)',
      ])
        xlsx.TextCellValue(header),
    ]);
    sheet.appendRow([
      xlsx.TextCellValue('Tas Kanvas'),
      xlsx.TextCellValue('Bahan baku'),
      xlsx.TextCellValue('Kain'),
      xlsx.IntCellValue(0),
      xlsx.TextCellValue('meter'),
      xlsx.IntCellValue(0),
    ]);
    sheet.cell(xlsx.CellIndex.indexByString('D2')).setFormula('=6/3');
    sheet
        .cell(xlsx.CellIndex.indexByString('F2'))
        .setFormula('=(D2*5000+2000-1000)/2+2^3+50%');

    final rows = parseHppWorkbook(workbook.encode()!);

    expect(rows.single.qty, 2);
    expect(rows.single.price, 5508.5);
  });

  test('reports division by zero in an HPP formula', () {
    final workbook = xlsx.Excel.createExcel();
    final defaultSheet = workbook.tables.keys.first;
    workbook.rename(defaultSheet, 'HPP');
    final sheet = workbook['HPP'];
    sheet.appendRow([
      for (final header in [
        'Nama produk',
        'Jenis biaya',
        'Nama bahan baku/ongkos',
        'Qty',
        'Satuan',
        'Harga satuan (Rp)',
      ])
        xlsx.TextCellValue(header),
    ]);
    sheet.appendRow([
      xlsx.TextCellValue('Tas Kanvas'),
      xlsx.TextCellValue('Bahan baku'),
      xlsx.TextCellValue('Kain'),
      xlsx.IntCellValue(1),
      xlsx.TextCellValue('meter'),
      xlsx.IntCellValue(0),
    ]);
    sheet.cell(xlsx.CellIndex.indexByString('F2')).setFormula('=100/0');

    expect(
      () => parseHppWorkbook(workbook.encode()!),
      throwsA(
        isA<FormatException>()
            .having(
              (error) => error.message,
              'message',
              contains('Harga satuan tidak valid pada baris 2'),
            )
            .having(
              (error) => error.message,
              'message',
              contains('membagi dengan nol'),
            ),
      ),
    );
  });

  test('rejects missing required HPP values with row number', () {
    final workbook = xlsx.Excel.createExcel();
    final defaultSheet = workbook.tables.keys.first;
    workbook.rename(defaultSheet, 'HPP');
    workbook['HPP'].appendRow([
      for (final header in [
        'Nama produk',
        'Jenis biaya',
        'Nama bahan baku/ongkos',
        'Qty',
        'Satuan',
        'Harga satuan (Rp)',
      ])
        xlsx.TextCellValue(header),
    ]);
    workbook['HPP'].appendRow([
      xlsx.TextCellValue('Tas Kanvas'),
      xlsx.TextCellValue('Bahan baku'),
      xlsx.TextCellValue('Kain'),
      xlsx.IntCellValue(0),
      xlsx.TextCellValue('meter'),
      xlsx.IntCellValue(35000),
    ]);

    expect(
      () => parseHppWorkbook(workbook.encode()!),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('baris 2'),
        ),
      ),
    );
  });
}
