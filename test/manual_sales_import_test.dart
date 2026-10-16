import 'package:excel/excel.dart' as xlsx;
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketr/manual_sales_import.dart';
import 'package:pocketr/sales_template.dart';

void main() {
  test('parses manual sales rows from the Indonesian template', () {
    final workbook = xlsx.Excel.decodeBytes(createSalesTemplateBytes());
    final sheet = workbook.tables['Penjualan']!;
    final values = [
      xlsx.DateCellValue(year: 2026, month: 10, day: 15),
      xlsx.TextCellValue('Shopee'),
      xlsx.TextCellValue('Tas'),
      xlsx.TextCellValue('Biru / M'),
      xlsx.IntCellValue(2),
      xlsx.TextCellValue('ORDER-1'),
      xlsx.IntCellValue(50000),
      xlsx.IntCellValue(12000),
    ];
    for (final entry in values.indexed) {
      sheet.updateCell(
        xlsx.CellIndex.indexByColumnRow(columnIndex: entry.$1, rowIndex: 1),
        entry.$2,
      );
    }

    final rows = parseManualSalesWorkbook(workbook.encode()!);

    expect(rows, hasLength(1));
    expect(rows.single.date, '2026-10-15');
    expect(rows.single.platform, 'shopee');
    expect(rows.single.productName, 'Tas');
    expect(rows.single.variant, 'Biru / M');
    expect(rows.single.qty, 2);
    expect(rows.single.orderNo, 'ORDER-1');
    expect(rows.single.amountReceived, 50000);
    expect(rows.single.hppPerUnit, 12000);
  });

  test('parses English headers and allows optional order and COGS', () {
    final workbook = xlsx.Excel.decodeBytes(
      createSalesTemplateBytes(languageCode: 'en'),
    );
    final sheet = workbook.tables['Sales']!;
    final values = [
      xlsx.TextCellValue('2026-10-15'),
      xlsx.TextCellValue('Other'),
      xlsx.TextCellValue('Mug'),
      xlsx.TextCellValue(''),
      xlsx.DoubleCellValue(1.5),
      xlsx.TextCellValue(''),
      xlsx.DoubleCellValue(12345.5),
      xlsx.TextCellValue(''),
    ];
    for (final entry in values.indexed) {
      sheet.updateCell(
        xlsx.CellIndex.indexByColumnRow(columnIndex: entry.$1, rowIndex: 1),
        entry.$2,
      );
    }

    final rows = parseManualSalesWorkbook(workbook.encode()!);

    expect(rows.single.platform, 'lainnya');
    expect(rows.single.qty, 1.5);
    expect(rows.single.orderNo, isEmpty);
    expect(rows.single.hppPerUnit, isNull);
  });

  test('evaluates arithmetic formulas in numeric sales columns', () {
    final workbook = xlsx.Excel.decodeBytes(createSalesTemplateBytes());
    final sheet = workbook.tables['Penjualan']!;
    final values = [
      xlsx.TextCellValue('2026-10-15'),
      xlsx.TextCellValue('Shopee'),
      xlsx.TextCellValue('Tas'),
      xlsx.TextCellValue(''),
      xlsx.IntCellValue(0),
      xlsx.TextCellValue(''),
      xlsx.IntCellValue(0),
      xlsx.IntCellValue(0),
    ];
    for (final entry in values.indexed) {
      sheet.updateCell(
        xlsx.CellIndex.indexByColumnRow(columnIndex: entry.$1, rowIndex: 1),
        entry.$2,
      );
    }
    sheet.cell(xlsx.CellIndex.indexByString('E2')).setFormula('=6/3');
    sheet.cell(xlsx.CellIndex.indexByString('G2')).setFormula('=E2*25000');
    sheet.cell(xlsx.CellIndex.indexByString('H2')).setFormula('=G2/4');

    final rows = parseManualSalesWorkbook(workbook.encode()!);

    expect(rows.single.qty, 2);
    expect(rows.single.amountReceived, 50000);
    expect(rows.single.hppPerUnit, 12500);
  });

  test('rejects invalid required data with the worksheet row number', () {
    final workbook = xlsx.Excel.decodeBytes(createSalesTemplateBytes());
    final values = [
      xlsx.TextCellValue('2026-10-15'),
      xlsx.TextCellValue('Shopee'),
      xlsx.TextCellValue('Tas'),
      xlsx.TextCellValue(''),
      xlsx.IntCellValue(0),
      xlsx.TextCellValue(''),
      xlsx.IntCellValue(10000),
      xlsx.TextCellValue(''),
    ];
    final sheet = workbook.tables['Penjualan']!;
    for (final entry in values.indexed) {
      sheet.updateCell(
        xlsx.CellIndex.indexByColumnRow(columnIndex: entry.$1, rowIndex: 1),
        entry.$2,
      );
    }

    expect(
      () => parseManualSalesWorkbook(workbook.encode()!),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('baris 2'),
        ),
      ),
    );
  });

  test('rejects impossible calendar dates', () {
    final workbook = xlsx.Excel.decodeBytes(createSalesTemplateBytes());
    final values = [
      xlsx.TextCellValue('2026-02-30'),
      xlsx.TextCellValue('Shopee'),
      xlsx.TextCellValue('Tas'),
      xlsx.TextCellValue(''),
      xlsx.IntCellValue(1),
      xlsx.TextCellValue(''),
      xlsx.IntCellValue(10000),
      xlsx.TextCellValue(''),
    ];
    final sheet = workbook.tables['Penjualan']!;
    for (final entry in values.indexed) {
      sheet.updateCell(
        xlsx.CellIndex.indexByColumnRow(columnIndex: entry.$1, rowIndex: 1),
        entry.$2,
      );
    }

    expect(
      () => parseManualSalesWorkbook(workbook.encode()!),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('Tanggal tidak valid'),
        ),
      ),
    );
  });
}
