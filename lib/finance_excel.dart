import 'package:excel/excel.dart' as xlsx;

import 'app_localization.dart';
import 'data.dart';

List<int> createFinanceExcelBytes(
  FinanceData data,
  String month, {
  String languageCode = 'id',
}) {
  final english = languageCode == 'en';
  final summarySheetName = english ? 'Summary' : 'Ringkasan';
  final salesSheetName = english ? 'Sales' : 'Penjualan';
  final expenseSheetName = english ? 'Expenses' : 'Pengeluaran';
  final productSheetName = english ? 'Products and COGS' : 'Produk dan HPP';
  final workbook = xlsx.Excel.createExcel();
  workbook.rename(workbook.tables.keys.first, summarySheetName);

  final sales = data.sales.where((sale) => sale.date.startsWith(month)).toList()
    ..sort((a, b) {
      final dateOrder = a.date.compareTo(b.date);
      return dateOrder != 0
          ? dateOrder
          : a.productName.compareTo(b.productName);
    });
  final expenses =
      data.expenses.where((expense) => expense.month == month).toList()
        ..sort((a, b) {
          final dateOrder = a.date.compareTo(b.date);
          return dateOrder != 0 ? dateOrder : a.name.compareTo(b.name);
        });

  _writeSummarySheet(
    workbook[summarySheetName],
    data,
    month,
    languageCode: languageCode,
  );
  _writeSalesSheet(
    workbook[salesSheetName],
    sales,
    month,
    languageCode: languageCode,
  );
  _writeExpenseSheet(
    workbook[expenseSheetName],
    data,
    expenses,
    month,
    languageCode: languageCode,
  );
  _writeProductSheet(
    workbook[productSheetName],
    data,
    month,
    languageCode: languageCode,
  );

  final bytes = workbook.encode();
  if (bytes == null) {
    throw const FormatException('Berkas Excel gagal dibuat.');
  }
  return bytes;
}

void _writeSummarySheet(
  xlsx.Sheet sheet,
  FinanceData data,
  String month, {
  required String languageCode,
}) {
  final english = languageCode == 'en';
  _setWidths(sheet, const [38, 25]);
  _writeTitle(
    sheet,
    english ? 'FINANCIAL SUMMARY' : 'RINGKASAN KEUANGAN',
    '${data.businessName}  ·  ${_exportMonthLabel(month, languageCode)}',
    lastColumn: 1,
  );

  final summary = data.summary(month);
  var row = 3;
  row = _writeSection(
    sheet,
    row,
    english ? 'SALES SUMMARY' : 'RINGKASAN PENJUALAN',
    lastColumn: 1,
  );
  _writeHeader(
    sheet,
    row++,
    english ? const ['Metric', 'Value'] : const ['Indikator', 'Nilai'],
  );
  row = _writeSummaryRows(sheet, row, [
    (
      english ? 'Revenue / amount received' : 'Omzet / uang diterima',
      summary.revenue,
      true,
    ),
    (english ? 'Order count' : 'Jumlah pesanan', summary.orders, false),
    (
      english ? 'Units sold (pcs)' : 'Jumlah produk terjual (pcs)',
      summary.pcs,
      false,
    ),
    (english ? 'Total sales COGS' : 'Total HPP penjualan', summary.hpp, true),
    (
      english ? 'Gross profit' : 'Laba kotor',
      summary.revenue - summary.hpp,
      true,
    ),
  ]);

  row++;
  row = _writeSection(
    sheet,
    row,
    english ? 'EXPENSE BREAKDOWN' : 'RINCIAN PENGELUARAN',
    lastColumn: 1,
  );
  _writeHeader(
    sheet,
    row++,
    english
        ? const ['Category', 'Amount (Rp)']
        : const ['Kategori', 'Jumlah (Rp)'],
  );
  row = _writeSummaryRows(sheet, row, [
    (
      english ? 'Operating expenses' : 'Biaya operasional',
      summary.operations,
      true,
    ),
    (english ? 'Ads' : 'Iklan', summary.ads, true),
    (english ? 'Ads VAT' : 'PPN iklan', summary.ppn, true),
    (english ? 'Staff salaries' : 'Gaji pegawai', summary.salary, true),
    (english ? 'Holiday bonus' : 'THR Lebaran', summary.thr, true),
    (
      english
          ? 'Total expenses before zakat'
          : 'Total pengeluaran sebelum zakat',
      summary.operations +
          summary.ads +
          summary.ppn +
          summary.salary +
          summary.thr,
      true,
    ),
  ]);

  row++;
  row = _writeSection(
    sheet,
    row,
    english ? 'PROFIT AND DISTRIBUTION' : 'LABA DAN PEMBAGIAN',
    lastColumn: 1,
  );
  _writeHeader(
    sheet,
    row++,
    english
        ? const ['Metric', 'Value (Rp)']
        : const ['Indikator', 'Nilai (Rp)'],
  );
  row = _writeSummaryRows(
    sheet,
    row,
    [
      (
        english ? 'Profit before zakat' : 'Laba sebelum zakat',
        summary.preTax,
        true,
      ),
      ('Zakat', summary.zakat, true),
      (english ? 'Net profit' : 'Laba bersih', summary.net, true),
      for (final owner in data.owners)
        (
          '${localizeOwnerName(owner.name, languageCode: languageCode)} (${owner.pct.toStringAsFixed(1)}%)',
          summary.net * owner.pct / 100,
          true,
        ),
    ],
    emphasizeLast: true,
    languageCode: languageCode,
  );
  sheet.setRowHeight(row, 8);
}

int _writeSummaryRows(
  xlsx.Sheet sheet,
  int startRow,
  List<(String, num, bool)> rows, {
  bool emphasizeLast = false,
  String languageCode = 'id',
}) {
  for (var index = 0; index < rows.length; index++) {
    final item = rows[index];
    final isEmphasized =
        (emphasizeLast && index == rows.length - 1) ||
        item.$1 == (languageCode == 'en' ? 'Net profit' : 'Laba bersih');
    _writeDataRow(
      sheet,
      startRow + index,
      [item.$1, item.$2],
      currencyColumns: item.$3 ? {1} : const {},
      numericColumns: item.$3 ? const {} : {1},
      emphasized: isEmphasized,
      band: index,
    );
  }
  return startRow + rows.length;
}

void _writeSalesSheet(
  xlsx.Sheet sheet,
  List<Sale> sales,
  String month, {
  required String languageCode,
}) {
  final english = languageCode == 'en';
  final headers = english
      ? const [
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
        ]
      : const [
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
        ];
  _setWidths(sheet, const [15, 17, 24, 30, 24, 11, 22, 19, 21, 22]);
  _writeTitle(
    sheet,
    english ? 'SALES DATA' : 'DATA PENJUALAN',
    english
        ? '${_exportMonthLabel(month, languageCode)}  ·  ${sales.length} transactions'
        : 'Periode ${_exportMonthLabel(month, languageCode)}  ·  ${sales.length} transaksi',
    lastColumn: headers.length - 1,
  );
  _writeHeader(sheet, 3, headers);

  var totalQty = 0.0;
  var totalReceived = 0.0;
  var totalHpp = 0.0;
  var row = 4;
  if (sales.isEmpty) {
    _writeMessageRow(
      sheet,
      row++,
      english
          ? 'No sales data for this month.'
          : 'Tidak ada data penjualan pada bulan ini.',
    );
  } else {
    for (var index = 0; index < sales.length; index++) {
      final sale = sales[index];
      final hpp = sale.qty * sale.hpp;
      totalQty += sale.qty;
      totalReceived += sale.received;
      totalHpp += hpp;
      _writeDataRow(
        sheet,
        row++,
        [
          sale.date,
          _exportMarketplaceName(sale.platform, languageCode),
          sale.orderNo,
          sale.productName,
          sale.variant,
          sale.qty,
          sale.received,
          sale.hpp,
          hpp,
          sale.received - hpp,
        ],
        currencyColumns: {6, 7, 8, 9},
        numericColumns: {5},
        band: index,
      );
    }
  }
  _writeDataRow(
    sheet,
    row,
    [
      'TOTAL',
      '',
      '',
      '',
      '',
      totalQty,
      totalReceived,
      null,
      totalHpp,
      totalReceived - totalHpp,
    ],
    currencyColumns: {6, 8, 9},
    numericColumns: {5},
    emphasized: true,
  );
}

void _writeExpenseSheet(
  xlsx.Sheet sheet,
  FinanceData data,
  List<Expense> expenses,
  String month, {
  required String languageCode,
}) {
  final english = languageCode == 'en';
  final headers = english
      ? const [
          'Date',
          'Category',
          'Expense name',
          'Notes',
          'Platform',
          'Related product',
          'Amount before VAT (Rp)',
          'VAT (Rp)',
          'Total (Rp)',
        ]
      : const [
          'Tanggal',
          'Kategori',
          'Nama pengeluaran',
          'Catatan',
          'Platform',
          'Produk terkait',
          'Jumlah sebelum PPN (Rp)',
          'PPN (Rp)',
          'Total (Rp)',
        ];
  _setWidths(sheet, const [15, 21, 28, 36, 17, 26, 25, 18, 21]);
  _writeTitle(
    sheet,
    english ? 'EXPENSE DATA' : 'DATA PENGELUARAN',
    english
        ? '${_exportMonthLabel(month, languageCode)}  ·  ${expenses.length} transactions'
        : 'Periode ${_exportMonthLabel(month, languageCode)}  ·  ${expenses.length} transaksi',
    lastColumn: headers.length - 1,
  );
  _writeHeader(sheet, 3, headers);

  var totalAmount = 0.0;
  var totalPpn = 0.0;
  var total = 0.0;
  var row = 4;
  if (expenses.isEmpty) {
    _writeMessageRow(
      sheet,
      row++,
      english
          ? 'No expense data for this month.'
          : 'Tidak ada data pengeluaran pada bulan ini.',
    );
  } else {
    for (var index = 0; index < expenses.length; index++) {
      final expense = expenses[index];
      final expenseTotal = data.expenseTotal(expense);
      final ppn = expenseTotal - expense.amount;
      totalAmount += expense.amount;
      totalPpn += ppn;
      total += expenseTotal;
      _writeDataRow(
        sheet,
        row++,
        [
          expense.date.isEmpty ? expense.month : expense.date,
          _exportCategoryName(expense.category, languageCode),
          expense.name,
          expense.note,
          expense.category == 'iklan'
              ? _exportMarketplaceName(expense.platform, languageCode)
              : '',
          expense.productName,
          expense.amount,
          ppn,
          expenseTotal,
        ],
        currencyColumns: {6, 7, 8},
        band: index,
      );
    }
  }
  _writeDataRow(
    sheet,
    row,
    ['TOTAL', '', '', '', '', '', totalAmount, totalPpn, total],
    currencyColumns: {6, 7, 8},
    emphasized: true,
  );
}

void _writeProductSheet(
  xlsx.Sheet sheet,
  FinanceData data,
  String month, {
  required String languageCode,
}) {
  final english = languageCode == 'en';
  final overviewHeaders = english
      ? const [
          'Product',
          'COGS/unit (Rp)',
          'Component count',
          'Variants',
          'Stock (pcs)',
        ]
      : const [
          'Produk',
          'HPP/pcs (Rp)',
          'Jumlah komponen',
          'Varian',
          'Stok (pcs)',
        ];
  final detailHeaders = english
      ? const [
          'Product',
          'Cost type',
          'Material / labor',
          'Qty per product',
          'Unit',
          'Unit price (Rp)',
          'COGS subtotal (Rp)',
        ]
      : const [
          'Produk',
          'Jenis biaya',
          'Bahan / ongkos',
          'Qty per produk',
          'Satuan',
          'Harga satuan (Rp)',
          'Subtotal HPP (Rp)',
        ];
  _setWidths(sheet, const [30, 20, 32, 14, 16, 22, 22]);
  _writeTitle(
    sheet,
    english ? 'PRODUCTS AND COGS' : 'PRODUK DAN HPP',
    english
        ? '${data.businessName}  ·  COGS calculated from the catalog at export  ·  ${_exportMonthLabel(month, languageCode)}'
        : '${data.businessName}  ·  HPP dihitung dari katalog saat ekspor  ·  ${_exportMonthLabel(month, languageCode)}',
    lastColumn: detailHeaders.length - 1,
  );

  final products = [...data.products]
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  var row = _writeSection(
    sheet,
    3,
    english ? 'PRODUCT SUMMARY' : 'RINGKASAN PRODUK',
    lastColumn: 6,
  );
  _writeHeader(sheet, row++, overviewHeaders);
  if (products.isEmpty) {
    _writeMessageRow(
      sheet,
      row++,
      english
          ? 'No products in the catalog yet.'
          : 'Belum ada produk di katalog.',
    );
  } else {
    for (var index = 0; index < products.length; index++) {
      final product = products[index];
      final variations = [
        if (product.colors.isNotEmpty)
          '${english ? 'Colors' : 'Warna'}: ${product.colors.join(', ')}',
        if (product.sizes.isNotEmpty)
          '${english ? 'Sizes' : 'Ukuran'}: ${product.sizes.join(', ')}',
        if (product.variants.isNotEmpty)
          '${english ? 'Variants' : 'Varian'}: ${product.variants.join(', ')}',
      ].join(' · ');
      _writeDataRow(
        sheet,
        row++,
        [
          product.name,
          data.productHpp(product),
          product.materials.length,
          variations,
          data.stockOf(product),
        ],
        currencyColumns: {1},
        numericColumns: {2, 4},
        band: index,
      );
    }
  }

  row += 2;
  row = _writeSection(
    sheet,
    row,
    english ? 'COGS COMPONENT DETAILS' : 'RINCIAN KOMPONEN HPP',
    lastColumn: 6,
  );
  _writeHeader(sheet, row++, detailHeaders);
  if (products.isEmpty) {
    _writeMessageRow(
      sheet,
      row++,
      english ? 'No COGS details yet.' : 'Belum ada rincian HPP.',
    );
  } else {
    for (final product in products) {
      if (product.materials.isEmpty) {
        _writeDataRow(sheet, row++, [
          product.name,
          '',
          english
              ? 'No material or labor details'
              : 'Belum ada rincian bahan atau ongkos',
          null,
          '',
          null,
          null,
        ], band: row);
      } else {
        for (final material in product.materials) {
          final effective = data.effectiveMaterial(material);
          _writeDataRow(
            sheet,
            row++,
            [
              product.name,
              effective.category == MaterialCategory.ongkosJahit
                  ? english
                        ? 'Labor'
                        : 'Ongkos'
                  : english
                  ? 'Raw material'
                  : 'Bahan baku',
              effective.name,
              effective.qty,
              effective.unit,
              effective.price,
              effective.subtotal,
            ],
            currencyColumns: {5, 6},
            numericColumns: {3},
            band: row,
          );
        }
      }
      _writeDataRow(
        sheet,
        row++,
        [
          '${english ? 'TOTAL COGS/UNIT' : 'TOTAL HPP/PCS'} · ${product.name}',
          '',
          '',
          null,
          '',
          null,
          data.productHpp(product),
        ],
        currencyColumns: {6},
        emphasized: true,
      );
    }
  }
}

String _exportMonthLabel(String month, String languageCode) {
  if (languageCode != 'en') return monthLabel(month);
  const englishMonths = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  final parts = month.split('-');
  return '${englishMonths[int.parse(parts[1]) - 1]} ${parts[0]}';
}

String _exportMarketplaceName(String platform, String languageCode) {
  final name = marketplaceNames[platform] ?? platform;
  return languageCode == 'en' && platform == 'lainnya' ? 'Other' : name;
}

String _exportCategoryName(String category, String languageCode) {
  if (languageCode != 'en') return categoryNames[category] ?? category;
  return switch (category) {
    'operasional' => 'Operating',
    'iklan' => 'Advertising',
    'gaji' => 'Staff salaries',
    'thr' => 'Holiday bonus',
    _ => categoryNames[category] ?? category,
  };
}

int _writeSection(
  xlsx.Sheet sheet,
  int row,
  String title, {
  required int lastColumn,
}) {
  _mergeText(sheet, row, title, lastColumn: lastColumn, style: _sectionStyle());
  sheet.setRowHeight(row, 25);
  return row + 1;
}

void _writeTitle(
  xlsx.Sheet sheet,
  String title,
  String subtitle, {
  required int lastColumn,
}) {
  _mergeText(sheet, 0, title, lastColumn: lastColumn, style: _titleStyle());
  _mergeText(
    sheet,
    1,
    subtitle,
    lastColumn: lastColumn,
    style: _subtitleStyle(),
  );
  sheet
    ..setRowHeight(0, 38)
    ..setRowHeight(1, 28);
}

void _mergeText(
  xlsx.Sheet sheet,
  int row,
  String text, {
  required int lastColumn,
  required xlsx.CellStyle style,
}) {
  if (lastColumn > 0) {
    sheet.merge(
      xlsx.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
      xlsx.CellIndex.indexByColumnRow(columnIndex: lastColumn, rowIndex: row),
      customValue: xlsx.TextCellValue(text),
    );
  }
  for (var column = 0; column <= lastColumn; column++) {
    sheet
            .cell(
              xlsx.CellIndex.indexByColumnRow(
                columnIndex: column,
                rowIndex: row,
              ),
            )
            .cellStyle =
        style;
  }
}

void _writeHeader(xlsx.Sheet sheet, int row, List<String> headers) {
  for (var column = 0; column < headers.length; column++) {
    _writeCell(sheet, row, column, headers[column], _headerStyle());
  }
  sheet.setRowHeight(row, 34);
}

void _writeDataRow(
  xlsx.Sheet sheet,
  int row,
  List<Object?> values, {
  Set<int> currencyColumns = const {},
  Set<int> numericColumns = const {},
  bool emphasized = false,
  int band = 0,
}) {
  for (var column = 0; column < values.length; column++) {
    final isCurrency = currencyColumns.contains(column);
    final isNumeric = numericColumns.contains(column) || isCurrency;
    final value = values[column];
    final isNegative = value is num && value < 0;
    _writeCell(
      sheet,
      row,
      column,
      value,
      xlsx.CellStyle(
        backgroundColorHex: xlsx.ExcelColor.fromHexString(
          emphasized
              ? 'FFDDEAF3'
              : band.isEven
              ? 'FFF7FAFD'
              : 'FFFFFFFF',
        ),
        fontColorHex: xlsx.ExcelColor.fromHexString(
          isNegative ? 'FFB73535' : 'FF263B4A',
        ),
        bold: emphasized,
        horizontalAlign: isNumeric
            ? xlsx.HorizontalAlign.Right
            : xlsx.HorizontalAlign.Left,
        verticalAlign: xlsx.VerticalAlign.Center,
        textWrapping: xlsx.TextWrapping.WrapText,
        bottomBorder: xlsx.Border(
          borderStyle: xlsx.BorderStyle.Thin,
          borderColorHex: xlsx.ExcelColor.fromHexString('FFDCE7F0'),
        ),
        numberFormat: isCurrency
            ? xlsx.NumFormat.custom(
                formatCode: '"Rp" #,##0.##;[Red]("Rp" #,##0.##)',
              )
            : isNumeric
            ? xlsx.NumFormat.custom(formatCode: '#,##0.##')
            : xlsx.NumFormat.standard_0,
      ),
    );
  }
  sheet.setRowHeight(row, emphasized ? 27 : 25);
}

void _writeMessageRow(xlsx.Sheet sheet, int row, String message) {
  _writeCell(sheet, row, 0, message, _messageStyle());
  sheet.setRowHeight(row, 30);
}

void _writeCell(
  xlsx.Sheet sheet,
  int row,
  int column,
  Object? value,
  xlsx.CellStyle style,
) {
  sheet.updateCell(
    xlsx.CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row),
    _toCellValue(value),
    cellStyle: style,
  );
}

xlsx.CellValue _toCellValue(Object? value) => switch (value) {
  null => xlsx.TextCellValue(''),
  int value => xlsx.IntCellValue(value),
  num value => xlsx.DoubleCellValue(value.toDouble()),
  _ => xlsx.TextCellValue(value.toString()),
};

void _setWidths(xlsx.Sheet sheet, List<double> widths) {
  for (var column = 0; column < widths.length; column++) {
    sheet.setColumnWidth(column, widths[column]);
  }
}

xlsx.CellStyle _titleStyle() => xlsx.CellStyle(
  backgroundColorHex: xlsx.ExcelColor.fromHexString('FF17364F'),
  fontColorHex: xlsx.ExcelColor.white,
  fontSize: 18,
  bold: true,
  verticalAlign: xlsx.VerticalAlign.Center,
);

xlsx.CellStyle _subtitleStyle() => xlsx.CellStyle(
  backgroundColorHex: xlsx.ExcelColor.fromHexString('FFEAF4FA'),
  fontColorHex: xlsx.ExcelColor.fromHexString('FF52697B'),
  fontSize: 10,
  verticalAlign: xlsx.VerticalAlign.Center,
  textWrapping: xlsx.TextWrapping.WrapText,
);

xlsx.CellStyle _sectionStyle() => xlsx.CellStyle(
  backgroundColorHex: xlsx.ExcelColor.fromHexString('FF236E7B'),
  fontColorHex: xlsx.ExcelColor.white,
  fontSize: 11,
  bold: true,
  verticalAlign: xlsx.VerticalAlign.Center,
);

xlsx.CellStyle _headerStyle() => xlsx.CellStyle(
  backgroundColorHex: xlsx.ExcelColor.fromHexString('FF174A70'),
  fontColorHex: xlsx.ExcelColor.white,
  fontSize: 10,
  bold: true,
  horizontalAlign: xlsx.HorizontalAlign.Center,
  verticalAlign: xlsx.VerticalAlign.Center,
  textWrapping: xlsx.TextWrapping.WrapText,
  bottomBorder: xlsx.Border(
    borderStyle: xlsx.BorderStyle.Medium,
    borderColorHex: xlsx.ExcelColor.fromHexString('FF69C7D2'),
  ),
);

xlsx.CellStyle _messageStyle() => xlsx.CellStyle(
  backgroundColorHex: xlsx.ExcelColor.fromHexString('FFF7FAFD'),
  fontColorHex: xlsx.ExcelColor.fromHexString('FF52697B'),
  italic: true,
  verticalAlign: xlsx.VerticalAlign.Center,
);
