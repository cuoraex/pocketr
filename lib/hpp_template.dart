import 'dart:convert';

import 'package:archive/archive.dart' as archive;
import 'package:excel/excel.dart' as xlsx;

List<int> createHppTemplateBytes() {
  final workbook = xlsx.Excel.createExcel();
  workbook.rename(workbook.tables.keys.first, 'HPP');
  final hppSheet = workbook['HPP'];

  const headers = [
    'Nama produk',
    'Jenis biaya',
    'Nama bahan baku/ongkos',
    'Qty',
    'Satuan',
    'Harga satuan (Rp)',
  ];
  hppSheet.appendRow(headers.map(xlsx.TextCellValue.new).toList());
  const widths = [28.0, 20.0, 32.0, 12.0, 16.0, 22.0];
  for (var column = 0; column < headers.length; column++) {
    hppSheet.setColumnWidth(column, widths[column]);
    hppSheet
        .cell(xlsx.CellIndex.indexByColumnRow(columnIndex: column, rowIndex: 0))
        .cellStyle = xlsx.CellStyle(
      backgroundColorHex: xlsx.ExcelColor.fromHexString('FF174A70'),
      fontColorHex: xlsx.ExcelColor.white,
      fontSize: 11,
      bold: true,
      horizontalAlign: xlsx.HorizontalAlign.Center,
      verticalAlign: xlsx.VerticalAlign.Center,
      textWrapping: xlsx.TextWrapping.WrapText,
    );
  }
  hppSheet.setRowHeight(0, 34);

  final guide = workbook['Panduan'];
  guide.setColumnWidth(0, 26);
  guide.setColumnWidth(1, 92);
  guide.appendRow([
    xlsx.TextCellValue('Panduan impor HPP'),
    xlsx.TextCellValue('Keterangan'),
  ]);
  const instructions = [
    (
      '1. Isi lembar HPP',
      'Mulai isi data pada baris 2. Jangan ubah nama kolom.',
    ),
    (
      '2. Satu baris per rincian',
      'Isi ulang Nama produk untuk setiap bahan baku atau ongkos.',
    ),
    ('3. Jenis biaya', 'Pilih "Bahan baku" atau "Ongkos" dari dropdown.'),
    (
      '4. Qty, satuan, harga',
      'Qty harus lebih dari 0; satuan wajib diisi; harga satuan dalam Rupiah. Kolom angka mendukung rumus +, -, *, /, ^, % dan referensi sel pada lembar yang sama.',
    ),
    (
      '5. Produk yang sudah ada',
      'Nama produk yang cocok akan mengganti rincian HPP lama. Foto, varian, dan stok tetap.',
    ),
    (
      '6. HPP tiap produk mandiri',
      'Rincian pada file ini disimpan khusus untuk produk tersebut, tidak mengubah katalog bahan baku.',
    ),
    ('Contoh jenis', 'Bahan baku: Kain kanvas | 1.5 | meter | 35000'),
    ('Contoh ongkos', 'Ongkos: Jahit tas | 1 | pcs | 15000'),
  ];
  for (final instruction in instructions) {
    guide.appendRow([
      xlsx.TextCellValue(instruction.$1),
      xlsx.TextCellValue(instruction.$2),
    ]);
  }

  final bytes = workbook.encode();
  if (bytes == null) {
    throw const FormatException('Template HPP gagal dibuat.');
  }
  return _addCostTypeDropdown(bytes);
}

List<int> _addCostTypeDropdown(List<int> bytes) {
  final zippedWorkbook = archive.ZipDecoder().decodeBytes(bytes);
  const sheetPath = 'xl/worksheets/sheet1.xml';
  final sheet = zippedWorkbook.findFile(sheetPath);
  if (sheet == null || sheet.content is! List<int>) {
    throw const FormatException('Lembar HPP template tidak dapat dibaca.');
  }
  final source = utf8.decode(sheet.content as List<int>, allowMalformed: false);
  const validation =
      '<dataValidations count="1"><dataValidation type="list" '
      'allowBlank="0" showInputMessage="1" showErrorMessage="1" '
      'sqref="B2:B1000"><formula1>"Bahan baku,Ongkos"</formula1>'
      '<promptTitle>Jenis biaya</promptTitle>'
      '<prompt>Pilih Bahan baku atau Ongkos.</prompt>'
      '<errorTitle>Jenis biaya tidak valid</errorTitle>'
      '<error>Pilih Bahan baku atau Ongkos dari daftar.</error>'
      '</dataValidation></dataValidations>';
  if (!source.contains('</sheetData>')) {
    throw const FormatException('Struktur lembar HPP template tidak valid.');
  }
  final updatedXml = source.replaceFirst(
    '</sheetData>',
    '</sheetData>$validation',
  );
  final updatedBytes = utf8.encode(updatedXml);
  zippedWorkbook.addFile(
    archive.ArchiveFile(sheetPath, updatedBytes.length, updatedBytes),
  );
  final result = archive.ZipEncoder().encode(zippedWorkbook);
  if (result == null) {
    throw const FormatException('Dropdown template HPP gagal dibuat.');
  }
  return result;
}
