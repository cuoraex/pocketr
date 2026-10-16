import 'package:excel/excel.dart' as xlsx;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketr/app_localization.dart';
import 'package:pocketr/data.dart';
import 'package:pocketr/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _windowManagerChannel = MethodChannel('window_manager');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    appLanguageCode.value = 'id';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_windowManagerChannel, (call) async {
          if (call.method == 'isMaximized') return false;
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_windowManagerChannel, null);
    appLanguageCode.value = 'id';
  });

  Future<void> pumpFinanceHome(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(const MaterialApp(home: FinanceHome()));
    await tester.pumpAndSettle();
  }

  testWidgets('desktop navigation opens each primary section', (tester) async {
    await pumpFinanceHome(tester);
    expect(tester.takeException(), isNull, reason: 'initial summary layout');

    expect(find.text('Ringkasan Bulanan'), findsOneWidget);

    await tester.tap(find.text('Penjualan').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'sales page layout');
    expect(find.text('Impor Penjualan'), findsOneWidget);

    await tester.tap(find.text('Pengeluaran').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'expenses page layout');
    expect(find.text('Pengeluaran').last, findsOneWidget);

    await tester.tap(find.text('Produk dan HPP').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'products page layout');
    expect(find.text('Produk dan HPP').last, findsOneWidget);

    await tester.tap(find.text('Ringkasan').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'return to summary layout');
    expect(find.text('Ringkasan Bulanan'), findsOneWidget);
  });

  testWidgets('annual summary displays totals for the selected year', (
    tester,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final data = FinanceData(
      sales: [
        Sale(
          date: '2026-01-10',
          platform: 'shopee',
          productId: '',
          productName: 'Bag',
          received: 1000,
          hpp: 100,
        ),
        Sale(
          date: '2026-02-10',
          platform: 'shopee',
          productId: '',
          productName: 'Hat',
          received: 2000,
          hpp: 200,
        ),
      ],
      expenses: [
        Expense(
          month: '2026-01',
          category: 'operasional',
          name: 'Packing',
          amount: 100,
        ),
      ],
    );
    await preferences.setString('pocketr_v1', data.toBackup());
    await preferences.setString('pocketr_selected_month_v1', '2026-02');
    await pumpFinanceHome(tester);

    final annualNet = data.summary('2026-01').net + data.summary('2026-02').net;
    expect(find.text('Laba tahunan · 2026'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('annual-total-row')),
        matching: find.text('Total'),
      ),
      findsOneWidget,
    );
    expect(find.text(formatMoney(annualNet)), findsOneWidget);
  });

  testWidgets('sales import offers the manual Excel template flow', (
    tester,
  ) async {
    await pumpFinanceHome(tester);

    await tester.tap(find.text('Penjualan').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Impor Penjualan').last);
    await tester.pumpAndSettle();

    expect(find.text('Template input manual'), findsOneWidget);
    expect(find.text('Impor Excel'), findsOneWidget);
    expect(find.text('Unduh template'), findsOneWidget);
  });

  testWidgets('Shopee import starts after selecting two files', (tester) async {
    FilePicker.platform = _FixedFilePicker.withFiles([
      PlatformFile(
        name: 'orders.xlsx',
        size: 3,
        bytes: Uint8List.fromList([1]),
      ),
      PlatformFile(
        name: 'balance.xlsx',
        size: 3,
        bytes: Uint8List.fromList([2]),
      ),
    ]);
    addTearDown(() => FilePicker.platform = _FixedFilePicker(null));
    await pumpFinanceHome(tester);

    await tester.tap(find.text('Penjualan').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Impor Penjualan').last);
    await tester.pumpAndSettle();

    expect(find.text('Batal'), findsNothing);
    expect(find.text('Impor'), findsNothing);
    await tester.tap(find.byIcon(Icons.close).last);
    await tester.pumpAndSettle();
    expect(find.text('Impor penjualan dari Excel'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Impor Penjualan').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pilih 2 berkas'));
    await tester.pumpAndSettle();

    expect(find.text('Impor penjualan dari Excel'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('manual Excel import creates missing products and variants', (
    tester,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      'pocketr_v1',
      FinanceData(
        products: [Product(id: 'existing-product', name: 'Keep product')],
      ).toBackup(),
    );
    final workbook = xlsx.Excel.createExcel();
    workbook.rename(workbook.tables.keys.first, 'Penjualan');
    final sheet = workbook.tables['Penjualan']!;
    sheet.appendRow(
      const [
        'Tanggal',
        'Platform',
        'Produk',
        'Varian',
        'Qty',
        'No Pesanan',
        'Uang Diterima',
        'HPP/Pcs',
      ].map(xlsx.TextCellValue.new).toList(),
    );
    final values = [
      xlsx.TextCellValue('2026-10-15'),
      xlsx.TextCellValue('Shopee'),
      xlsx.TextCellValue('Audit bag'),
      xlsx.TextCellValue('Biru / M'),
      xlsx.IntCellValue(1),
      xlsx.TextCellValue('MANUAL-1'),
      xlsx.IntCellValue(25000),
      xlsx.TextCellValue(''),
    ];
    sheet.appendRow(values);
    sheet.appendRow([
      xlsx.TextCellValue('2026-10-15'),
      xlsx.TextCellValue('Shopee'),
      xlsx.TextCellValue('Audit pouch'),
      xlsx.TextCellValue('Merah / S'),
      xlsx.IntCellValue(1),
      xlsx.TextCellValue('MANUAL-2'),
      xlsx.IntCellValue(30000),
      xlsx.TextCellValue(''),
    ]);
    FilePicker.platform = _FixedFilePicker(
      Uint8List.fromList(workbook.encode()!),
    );
    addTearDown(() => FilePicker.platform = _FixedFilePicker(null));
    await pumpFinanceHome(tester);

    await tester.tap(find.text('Penjualan').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Impor Penjualan').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Impor Excel'));
    await tester.pump();
    expect(find.text('Membaca berkas Excel...'), findsNothing);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 1)),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 baris penjualan'), findsOneWidget);
    expect(find.text('Produk baru'), findsOneWidget);
    expect(find.text('Varian baru'), findsOneWidget);
    expect(
      find.text(
        'Produk baru belum memiliki bahan/HPP. HPP penjualan awal Rp0; '
        'lengkapi HPP di katalog setelah impor.',
      ),
      findsOneWidget,
    );
    expect(
      tester.takeException(),
      isNull,
      reason: 'manual import confirmation layout',
    );
    await tester.tap(find.text('Impor').last);
    await tester.pumpAndSettle();
    expect(find.text('Impor penjualan dari Excel'), findsNothing);

    final savedData = FinanceData.fromBackup(
      preferences.getString('pocketr_v1')!,
    );
    expect(savedData.products, hasLength(3));
    expect(
      savedData.products.map((product) => product.id).toSet(),
      hasLength(3),
    );
    final importedProduct = savedData.products.singleWhere(
      (product) => product.name == 'Audit bag',
    );
    final importedPouch = savedData.products.singleWhere(
      (product) => product.name == 'Audit pouch',
    );
    expect(importedProduct.colors, ['Biru']);
    expect(importedProduct.sizes, ['M']);
    expect(importedPouch.colors, ['Merah']);
    expect(importedPouch.sizes, ['S']);
    expect(savedData.sales, hasLength(2));
    expect(
      savedData.sales
          .singleWhere((sale) => sale.productName == importedProduct.name)
          .productId,
      importedProduct.id,
    );
    expect(
      savedData.sales
          .singleWhere((sale) => sale.productName == importedPouch.name)
          .productId,
      importedPouch.id,
    );

    await tester.tap(find.text('Produk dan HPP').first);
    await tester.pumpAndSettle();
    expect(find.text('Audit bag'), findsNWidgets(2));
    await tester.tap(find.text('Keep product').first);
    await tester.pumpAndSettle();
    expect(find.text('Keep product'), findsNWidgets(2));
    await tester.tap(find.text('Audit pouch').first);
    await tester.pumpAndSettle();
    expect(find.text('Audit pouch'), findsNWidgets(2));
    await tester.tap(find.text('Audit bag').first);
    await tester.pumpAndSettle();
    expect(find.text('Audit bag'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings warns before reset and allows cancellation', (
    tester,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      'pocketr_v1',
      FinanceData(products: [Product(name: 'Keep this product')]).toBackup(),
    );
    await pumpFinanceHome(tester);

    await tester.tap(find.text('Pengaturan').last);
    await tester.pumpAndSettle();
    expect(find.text('Peringatan'), findsOneWidget);

    await tester.tap(find.text('Atur ulang semua data'));
    await tester.pumpAndSettle();
    expect(find.text('Hapus semua data?'), findsOneWidget);

    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();
    expect(find.text('Hapus semua data?'), findsNothing);
    expect(
      FinanceData.fromBackup(preferences.getString('pocketr_v1')!).products,
      hasLength(1),
    );
  });

  testWidgets('confirmed reset clears and persists finance data', (
    tester,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      'pocketr_v1',
      FinanceData(products: [Product(name: 'Delete this product')]).toBackup(),
    );
    await pumpFinanceHome(tester);

    await tester.tap(find.text('Pengaturan').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Atur ulang semua data'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hapus'));
    await tester.pumpAndSettle();

    expect(
      FinanceData.fromBackup(preferences.getString('pocketr_v1')!).products,
      isEmpty,
    );
  });

  testWidgets('new product is saved to local storage', (tester) async {
    final preferences = await SharedPreferences.getInstance();
    await pumpFinanceHome(tester);

    await tester.tap(find.text('Produk dan HPP').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tambah produk').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Audit product');
    await tester.tap(find.text('Simpan').last);
    await tester.pumpAndSettle();

    final savedData = FinanceData.fromBackup(
      preferences.getString('pocketr_v1')!,
    );
    expect(savedData.products.map((product) => product.name), [
      'Audit product',
    ]);
  });

  testWidgets('new sale is linked to a product and saved locally', (
    tester,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      'pocketr_v1',
      FinanceData(
        products: [Product(id: 'audit-product', name: 'Audit bag')],
      ).toBackup(),
    );
    await pumpFinanceHome(tester);

    await tester.tap(find.text('Penjualan').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tambah penjualan').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(1), '25000');
    await tester.tap(find.text('Simpan').last);
    await tester.pumpAndSettle();

    final savedData = FinanceData.fromBackup(
      preferences.getString('pocketr_v1')!,
    );
    expect(savedData.sales, hasLength(1));
    expect(savedData.sales.single.productId, 'audit-product');
    expect(savedData.sales.single.received, 25000);
  });

  testWidgets('new operating expense is saved locally', (tester) async {
    final preferences = await SharedPreferences.getInstance();
    await pumpFinanceHome(tester);

    await tester.tap(find.text('Pengeluaran').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tambah biaya').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Packaging');
    await tester.enterText(find.byType(TextFormField).at(1), '5000');
    await tester.tap(find.text('Simpan').last);
    await tester.pumpAndSettle();

    final savedData = FinanceData.fromBackup(
      preferences.getString('pocketr_v1')!,
    );
    expect(savedData.expenses, hasLength(1));
    expect(savedData.expenses.single.name, 'Packaging');
    expect(savedData.expenses.single.amount, 5000);
    expect(savedData.expenses.single.category, 'operasional');
  });
}

class _FixedFilePicker extends FilePicker {
  _FixedFilePicker(Uint8List? bytes)
    : _result = bytes == null
          ? null
          : FilePickerResult([
              PlatformFile(
                name: 'manual.xlsx',
                size: bytes.length,
                bytes: bytes,
              ),
            ]);

  _FixedFilePicker.withFiles(List<PlatformFile> files)
    : _result = FilePickerResult(files);

  final FilePickerResult? _result;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async => _result;
}
