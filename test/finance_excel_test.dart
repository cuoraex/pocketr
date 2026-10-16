import 'package:excel/excel.dart' as xlsx;
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketr/data.dart';
import 'package:pocketr/finance_excel.dart';

void main() {
  test(
    'exports readable sheets for the selected month and product catalog',
    () {
      final data = FinanceData(
        businessName: 'PocketR Demo',
        materials: [
          MaterialCost(id: 'fabric', name: 'Kain', unit: 'meter', price: 1000),
          MaterialCost(
            id: 'sewing',
            name: 'Jahit tas',
            unit: 'pcs',
            price: 5000,
            category: MaterialCategory.ongkosJahit,
          ),
        ],
        products: [
          Product(
            id: 'bag',
            name: 'Tas',
            materials: [
              MaterialCost(
                id: 'fabric-use',
                name: 'Kain lama',
                qty: 2,
                ref: 'fabric',
              ),
              MaterialCost(id: 'sewing-use', name: 'Jahit lama', ref: 'sewing'),
            ],
            colors: ['Hitam'],
            sizes: ['M'],
          ),
        ],
        sales: [
          Sale(
            id: 'sale-current',
            date: '2026-10-12',
            platform: 'shopee',
            productId: 'bag',
            productName: 'Tas',
            qty: 2,
            orderNo: 'ORD-1',
            received: 30000,
            hpp: 6500,
          ),
          Sale(
            id: 'sale-previous',
            date: '2026-09-28',
            platform: 'shopee',
            productId: 'bag',
            productName: 'Transaksi lama',
            qty: 1,
            received: 10000,
            hpp: 6500,
          ),
        ],
        expenses: [
          Expense(
            month: '2026-10',
            category: 'iklan',
            name: 'Iklan Shopee',
            date: '2026-10-13',
            amount: 1000,
            platform: 'shopee',
            productName: 'Tas',
            ppn: true,
          ),
          Expense(
            month: '2026-09',
            category: 'operasional',
            name: 'Biaya lama',
            amount: 900,
          ),
        ],
      );

      final workbook = xlsx.Excel.decodeBytes(
        createFinanceExcelBytes(data, '2026-10'),
      );

      expect(workbook.tables.keys, [
        'Ringkasan',
        'Penjualan',
        'Pengeluaran',
        'Produk dan HPP',
      ]);
      final summary = workbook.tables['Ringkasan']!;
      expect(summary.rows[0][0]?.value.toString(), 'RINGKASAN KEUANGAN');
      expect(summary.rows[1][0]?.value.toString(), contains('Oktober 2026'));

      final sales = workbook.tables['Penjualan']!;
      expect(sales.rows[3].map((cell) => cell?.value.toString()).toList(), [
        'Tanggal',
        'Platform',
        'No. pesanan',
        'Produk',
        'Varian',
        'Qty',
        'Uang diterima (Rp)',
        'HPP/pcs (Rp)',
        'Total HPP (Rp)',
        'Laba kotor (Rp)',
      ]);
      expect(sales.rows[4][3]?.value.toString(), 'Tas');
      expect(
        sales.rows.any(
          (row) =>
              row.any((cell) => cell?.value.toString() == 'Transaksi lama'),
        ),
        isFalse,
      );

      final expenses = workbook.tables['Pengeluaran']!;
      expect(expenses.rows[4][2]?.value.toString(), 'Iklan Shopee');
      expect(_numericCellValue(expenses.rows[4][8]?.value), 1110);
      expect(
        expenses.rows.any(
          (row) => row.any((cell) => cell?.value.toString() == 'Biaya lama'),
        ),
        isFalse,
      );

      final products = workbook.tables['Produk dan HPP']!;
      expect(products.rows[4][0]?.value.toString(), 'Produk');
      expect(_numericCellValue(products.rows[5][1]?.value), 7000);
      expect(
        products.rows.any(
          (row) => row.any((cell) => cell?.value.toString() == 'Ongkos'),
        ),
        isTrue,
      );

      final englishWorkbook = xlsx.Excel.decodeBytes(
        createFinanceExcelBytes(data, '2026-10', languageCode: 'en'),
      );
      expect(englishWorkbook.tables.keys, [
        'Summary',
        'Sales',
        'Expenses',
        'Products and COGS',
      ]);
      expect(
        englishWorkbook.tables['Summary']!.rows[0][0]?.value.toString(),
        'FINANCIAL SUMMARY',
      );
      expect(
        englishWorkbook.tables['Summary']!.rows[1][0]?.value.toString(),
        contains('October 2026'),
      );
      expect(
        englishWorkbook.tables['Sales']!.rows[3]
            .map((cell) => cell?.value.toString())
            .toList(),
        [
          'Date',
          'Platform',
          'Order No.',
          'Product',
          'Variant',
          'Qty',
          'Amount received (Rp)',
          'COGS/unit (Rp)',
          'Total COGS (Rp)',
          'Gross profit (Rp)',
        ],
      );
      expect(
        englishWorkbook.tables['Expenses']!.rows[3]
            .map((cell) => cell?.value.toString())
            .toList(),
        [
          'Date',
          'Category',
          'Expense name',
          'Notes',
          'Platform',
          'Related product',
          'Amount before VAT (Rp)',
          'VAT (Rp)',
          'Total (Rp)',
        ],
      );
      expect(
        englishWorkbook.tables['Expenses']!.rows[4][1]?.value.toString(),
        'Advertising',
      );
      expect(
        englishWorkbook.tables['Products and COGS']!.rows[3][0]?.value
            .toString(),
        'PRODUCT SUMMARY',
      );
    },
  );
}

num _numericCellValue(xlsx.CellValue? value) => switch (value) {
  xlsx.IntCellValue intValue => intValue.value,
  xlsx.DoubleCellValue doubleValue => doubleValue.value,
  _ => throw StateError('Expected a numeric Excel cell.'),
};
