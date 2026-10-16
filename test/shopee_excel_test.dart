import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' as archive;
import 'package:excel/excel.dart' as xlsx;
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketr/shopee_excel.dart';

void main() {
  test('prefers order creation time when choosing the sale date', () {
    expect(
      findShopeeOrderDateColumnIndex([
        'Waktu Pesanan Selesai',
        'Waktu Pembayaran Dilakukan',
        'Waktu Pesanan Dibuat',
      ]),
      2,
    );
  });

  test('falls back to payment time but not completion time', () {
    expect(
      findShopeeOrderDateColumnIndex([
        'No. Pesanan',
        'Waktu Pembayaran Dilakukan',
        'Waktu Pesanan Selesai',
      ]),
      1,
    );
    expect(findShopeeOrderDateColumnIndex(['Waktu Pesanan Selesai']), isNull);
    expect(findShopeeOrderDateColumnIndex(['No. Pesanan']), isNull);
  });

  test('decodes workbooks with Shopee absolute worksheet targets', () async {
    final source = xlsx.Excel.createExcel();
    source['Sheet1'].appendRow([xlsx.TextCellValue('Order number')]);
    final sourceBytes = source.encode()!;

    final zippedWorkbook = archive.ZipDecoder().decodeBytes(sourceBytes);
    final relationships = zippedWorkbook.findFile(
      'xl/_rels/workbook.xml.rels',
    )!;
    final originalXml = utf8.decode(relationships.content as List<int>);
    final shopeeXml = originalXml.replaceAll(
      'Target="worksheets/',
      'Target="/xl/worksheets/',
    );
    expect(shopeeXml, isNot(originalXml));

    final shopeeXmlBytes = Uint8List.fromList(utf8.encode(shopeeXml));
    zippedWorkbook.addFile(
      archive.ArchiveFile(
        relationships.name,
        shopeeXmlBytes.length,
        shopeeXmlBytes,
      ),
    );
    final shopeeBytes = archive.ZipEncoder().encode(zippedWorkbook)!;

    final decoded = await decodeShopeeWorkbookRows(
      Uint8List.fromList(shopeeBytes),
    );

    expect(decoded, hasLength(1));
    expect(decoded.single.single, ['Order number']);
  });
}
