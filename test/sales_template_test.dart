import 'package:excel/excel.dart' as xlsx;
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketr/sales_template.dart';

void main() {
  test('creates a formatted sales workbook with the import headers intact', () {
    final workbook = xlsx.Excel.decodeBytes(createSalesTemplateBytes());
    final sales = workbook.tables['Penjualan']!;
    final guide = workbook.tables['Panduan']!;

    expect(sales.rows.first.map((cell) => cell?.value?.toString()).toList(), [
      'Tanggal',
      'Platform',
      'Produk',
      'Varian',
      'Qty',
      'No Pesanan',
      'Uang Diterima',
      'HPP/Pcs',
    ]);
    expect(sales.rows.length, 2001);
    expect(sales.rows[1].every((cell) => cell?.value == null), isTrue);
    expect(
      sales
          .cell(xlsx.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0))
          .cellStyle
          ?.backgroundColor
          .colorHex,
      'FF174A70',
    );
    expect(
      guide.rows[0][1]?.value?.toString(),
      'POCKETR  |  TEMPLATE PENJUALAN',
    );
    expect(
      guide.rows[9].skip(1).map((cell) => cell?.value?.toString()).toList(),
      ['Kolom', 'Isi', 'Format dan contoh'],
    );

    final englishWorkbook = xlsx.Excel.decodeBytes(
      createSalesTemplateBytes(languageCode: 'en'),
    );
    expect(englishWorkbook.tables.keys, ['Sales', 'Guide']);
    expect(
      englishWorkbook.tables['Sales']!.rows.first
          .map((cell) => cell?.value?.toString())
          .toList(),
      [
        'Date',
        'Platform',
        'Product',
        'Variant',
        'Qty',
        'Order No.',
        'Amount Received',
        'COGS/Unit',
      ],
    );
    expect(
      englishWorkbook.tables['Guide']!.rows[0][1]?.value?.toString(),
      'POCKETR  |  SALES TEMPLATE',
    );
    expect(
      englishWorkbook.tables['Guide']!.rows[9]
          .skip(1)
          .map((cell) => cell?.value?.toString())
          .toList(),
      ['Column', 'Requirement', 'Format and example'],
    );
    expect(
      englishWorkbook.tables['Guide']!.rows[10][2]?.value?.toString(),
      'Required',
    );
  });
}
