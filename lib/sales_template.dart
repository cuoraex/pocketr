import 'package:excel/excel.dart' as xlsx;

List<int> createSalesTemplateBytes({String languageCode = 'id'}) {
  final english = languageCode == 'en';
  final salesSheetName = english ? 'Sales' : 'Penjualan';
  final guideSheetName = english ? 'Guide' : 'Panduan';
  final requiredLabel = english ? 'Required' : 'Wajib';
  final workbook = xlsx.Excel.createExcel();
  final defaultSheet = workbook.tables.keys.first;
  workbook.rename(defaultSheet, salesSheetName);

  final salesSheet = workbook[salesSheetName];
  final headers = english
      ? const [
          'Date',
          'Platform',
          'Product',
          'Variant',
          'Qty',
          'Order No.',
          'Amount Received',
          'COGS/Unit',
        ]
      : const [
          'Tanggal',
          'Platform',
          'Produk',
          'Varian',
          'Qty',
          'No Pesanan',
          'Uang Diterima',
          'HPP/Pcs',
        ];
  salesSheet.appendRow(headers.map(xlsx.TextCellValue.new).toList());

  final requiredHeaderStyle = xlsx.CellStyle(
    backgroundColorHex: xlsx.ExcelColor.fromHexString('FF174A70'),
    fontColorHex: xlsx.ExcelColor.white,
    fontSize: 11,
    bold: true,
    horizontalAlign: xlsx.HorizontalAlign.Center,
    verticalAlign: xlsx.VerticalAlign.Center,
    textWrapping: xlsx.TextWrapping.WrapText,
    bottomBorder: xlsx.Border(
      borderStyle: xlsx.BorderStyle.Medium,
      borderColorHex: xlsx.ExcelColor.fromHexString('FF69C7D2'),
    ),
  );
  final optionalHeaderStyle = requiredHeaderStyle.copyWith(
    backgroundColorHexVal: xlsx.ExcelColor.fromHexString('FF236E7B'),
  );
  final inputBorder = xlsx.Border(
    borderStyle: xlsx.BorderStyle.Thin,
    borderColorHex: xlsx.ExcelColor.fromHexString('FFDCE7F0'),
  );
  final bodyStyles = [
    for (var band = 0; band < 2; band++)
      for (var column = 0; column < headers.length; column++)
        xlsx.CellStyle(
          backgroundColorHex: xlsx.ExcelColor.fromHexString(
            band == 0 ? 'FFF7FAFD' : 'FFFFFFFF',
          ),
          fontColorHex: xlsx.ExcelColor.fromHexString('FF263B4A'),
          verticalAlign: xlsx.VerticalAlign.Center,
          leftBorder: inputBorder,
          rightBorder: inputBorder,
          bottomBorder: inputBorder,
          numberFormat: switch (column) {
            0 => xlsx.NumFormat.custom(formatCode: 'yyyy-mm-dd'),
            4 => xlsx.NumFormat.custom(formatCode: '#,##0'),
            6 || 7 => xlsx.NumFormat.custom(formatCode: '#,##0'),
            _ => xlsx.NumFormat.standard_0,
          },
        ),
  ];

  for (var column = 0; column < headers.length; column++) {
    salesSheet.setColumnWidth(
      column,
      const <double>[16, 18, 30, 24, 10, 24, 22, 15][column],
    );
    salesSheet
        .cell(xlsx.CellIndex.indexByColumnRow(columnIndex: column, rowIndex: 0))
        .cellStyle = column == 3 || column == 5 || column == 7
        ? optionalHeaderStyle
        : requiredHeaderStyle;
  }
  salesSheet.setRowHeight(0, 34);
  for (var row = 1; row <= 2000; row++) {
    salesSheet.setRowHeight(row, 24);
    for (var column = 0; column < headers.length; column++) {
      salesSheet
              .cell(
                xlsx.CellIndex.indexByColumnRow(
                  columnIndex: column,
                  rowIndex: row,
                ),
              )
              .cellStyle =
          bodyStyles[(row % 2) * headers.length + column];
    }
  }

  final guideSheet = workbook[guideSheetName];
  const ink = 'FF17364F';
  const blue = 'FF1C6591';
  const paleBlue = 'FFEAF4FA';
  const teal = 'FF1D7884';
  const white = 'FFFFFFFF';
  const muted = 'FF52697B';
  const line = 'FFDCE7F0';
  for (final entry in const [(0, 4.0), (1, 24.0), (2, 18.0), (3, 66.0)]) {
    guideSheet.setColumnWidth(entry.$1, entry.$2);
  }

  void mergeTitle(int row, String text, xlsx.CellStyle style) {
    guideSheet.merge(
      xlsx.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row),
      xlsx.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row),
    );
    guideSheet.updateCell(
      xlsx.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row),
      xlsx.TextCellValue(text),
    );
    for (var column = 1; column <= 3; column++) {
      guideSheet
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

  xlsx.CellStyle solidStyle({
    required String background,
    required String foreground,
    int fontSize = 11,
    bool bold = false,
    xlsx.HorizontalAlign horizontal = xlsx.HorizontalAlign.Left,
    xlsx.VerticalAlign vertical = xlsx.VerticalAlign.Center,
    xlsx.TextWrapping wrap = xlsx.TextWrapping.WrapText,
    bool hasBottomBorder = false,
  }) => xlsx.CellStyle(
    backgroundColorHex: xlsx.ExcelColor.fromHexString(background),
    fontColorHex: xlsx.ExcelColor.fromHexString(foreground),
    fontSize: fontSize,
    bold: bold,
    horizontalAlign: horizontal,
    verticalAlign: vertical,
    textWrapping: wrap,
    bottomBorder: hasBottomBorder
        ? xlsx.Border(
            borderStyle: xlsx.BorderStyle.Thin,
            borderColorHex: xlsx.ExcelColor.fromHexString(line),
          )
        : null,
  );

  mergeTitle(
    0,
    english ? 'POCKETR  |  SALES TEMPLATE' : 'POCKETR  |  TEMPLATE PENJUALAN',
    solidStyle(background: ink, foreground: white, fontSize: 18, bold: true),
  );
  mergeTitle(
    1,
    english
        ? 'A simple worksheet for preparing sales data in a clean, consistent format.'
        : 'Lembar kerja untuk menyiapkan data penjualan dengan format yang rapi dan konsisten.',
    solidStyle(background: paleBlue, foreground: muted, fontSize: 11),
  );
  mergeTitle(
    3,
    english ? 'GET STARTED' : 'MULAI DI SINI',
    solidStyle(background: blue, foreground: white, bold: true),
  );
  final steps = english
      ? const [
          '01   Open the Sales sheet and enter your data starting on row 2.',
          '02   Do not change the header names or their order.',
          '03   Save as .xlsx and double-check the numbers before using it.',
        ]
      : const [
          '01   Buka lembar Penjualan, lalu isi data mulai dari baris 2.',
          '02   Jangan mengubah nama atau urutan kolom pada baris header.',
          '03   Simpan sebagai .xlsx dan periksa kembali angka sebelum digunakan.',
        ];
  for (final step in steps.indexed) {
    mergeTitle(
      4 + step.$1,
      step.$2,
      solidStyle(
        background: step.$1.isEven ? 'FFF7FAFD' : white,
        foreground: ink,
        hasBottomBorder: true,
      ),
    );
  }
  mergeTitle(
    8,
    english ? 'COLUMN GUIDE' : 'PANDUAN KOLOM',
    solidStyle(background: teal, foreground: white, bold: true),
  );

  final guideHeaders = english
      ? const ['Column', 'Requirement', 'Format and example']
      : const ['Kolom', 'Isi', 'Format dan contoh'];
  for (var column = 0; column < guideHeaders.length; column++) {
    guideSheet.updateCell(
      xlsx.CellIndex.indexByColumnRow(columnIndex: column + 1, rowIndex: 9),
      xlsx.TextCellValue(guideHeaders[column]),
      cellStyle: solidStyle(
        background: ink,
        foreground: white,
        bold: true,
        horizontal: column == 0
            ? xlsx.HorizontalAlign.Left
            : xlsx.HorizontalAlign.Center,
      ),
    );
  }
  final fields = english
      ? const [
          ('Date', 'Required', 'YYYY-MM-DD  ·  example: 2026-10-13'),
          (
            'Platform',
            'Required',
            'Shopee, Tokopedia, Lazada, TikTok, or Other',
          ),
          (
            'Product',
            'Required',
            'Must exactly match a product in your PocketR catalog',
          ),
          ('Variant', 'Optional', 'Separate multiple options with /'),
          ('Qty', 'Required', 'Quantity sold; must be greater than 0'),
          ('Order No.', 'Optional', 'Used to help detect duplicate orders'),
          (
            'Amount Received',
            'Required',
            'Numbers only; no Rp or thousand separators',
          ),
          (
            'COGS/Unit',
            'Optional',
            'Leave blank to use the COGS from your catalog',
          ),
        ]
      : const [
          ('Tanggal', 'Wajib', 'YYYY-MM-DD  ·  contoh 2026-10-13'),
          (
            'Platform',
            'Wajib',
            'Shopee, Tokopedia, Lazada, TikTok, atau Lainnya',
          ),
          (
            'Produk',
            'Wajib',
            'Nama produk harus sama persis dengan katalog PocketR',
          ),
          ('Varian', 'Opsional', 'Pisahkan beberapa pilihan dengan tanda /'),
          ('Qty', 'Wajib', 'Jumlah terjual, angka lebih dari 0'),
          (
            'No Pesanan',
            'Opsional',
            'Dipakai untuk membantu mendeteksi duplikat',
          ),
          (
            'Uang Diterima',
            'Wajib',
            'Isi angka saja, tanpa Rp atau pemisah ribuan',
          ),
          ('HPP/Pcs', 'Opsional', 'Kosongkan untuk memakai HPP dari katalog'),
        ];
  for (var row = 0; row < fields.length; row++) {
    final values = fields[row];
    final background = row.isEven ? 'FFF7FAFD' : white;
    final cells = [values.$1, values.$2, values.$3];
    for (var column = 0; column < cells.length; column++) {
      guideSheet.updateCell(
        xlsx.CellIndex.indexByColumnRow(
          columnIndex: column + 1,
          rowIndex: row + 10,
        ),
        xlsx.TextCellValue(cells[column]),
        cellStyle: solidStyle(
          background: column == 1 && values.$2 == requiredLabel
              ? 'FFE6F3EC'
              : background,
          foreground: column == 1 && values.$2 == requiredLabel
              ? 'FF236746'
              : column == 1
              ? muted
              : ink,
          bold: column == 0 || column == 1,
          hasBottomBorder: true,
        ),
      );
    }
  }
  mergeTitle(
    19,
    english ? 'BEFORE YOU FINISH' : 'CEK SEBELUM SELESAI',
    solidStyle(background: blue, foreground: white, bold: true),
  );
  mergeTitle(
    20,
    english
        ? 'Make sure dates are valid, Qty is greater than 0, and product names match your catalog.'
        : 'Pastikan tanggal valid, Qty lebih dari 0, dan nama produk cocok dengan katalog.',
    solidStyle(background: paleBlue, foreground: ink),
  );
  mergeTitle(
    21,
    english ? 'Teal columns on the Sales sheet are optional.' : 'Kolom berwarna biru kehijauan pada lembar Penjualan bersifat opsional.',
    solidStyle(background: paleBlue, foreground: muted, fontSize: 10),
  );

  guideSheet.setRowHeight(0, 38);
  guideSheet.setRowHeight(1, 30);
  guideSheet.setRowHeight(3, 25);
  for (var row = 4; row <= 6; row++) {
    guideSheet.setRowHeight(row, 26);
  }
  guideSheet.setRowHeight(8, 25);
  guideSheet.setRowHeight(9, 24);
  for (var row = 10; row <= 17; row++) {
    guideSheet.setRowHeight(row, 30);
  }
  guideSheet.setRowHeight(19, 25);
  guideSheet.setRowHeight(20, 30);
  guideSheet.setRowHeight(21, 27);

  final encoded = workbook.encode();
  if (encoded == null) {
    throw const FormatException('Template Excel gagal dibuat.');
  }
  return encoded;
}
