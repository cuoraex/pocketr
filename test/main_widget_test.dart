import 'dart:convert';
import 'dart:io';

import 'package:excel/excel.dart' as xlsx;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pocketr/app_localization.dart';
import 'package:pocketr/data.dart';
import 'package:pocketr/finance_database.dart';
import 'package:pocketr/local_file_archive.dart';
import 'package:pocketr/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

const _windowManagerChannel = MethodChannel('window_manager');
const _windowStateChannel = MethodChannel('pocketr/window_state');

Uint8List _workbookBytes(List<String> headers) {
  final workbook = xlsx.Excel.createExcel();
  workbook.tables.values.first.appendRow(
    headers.map(xlsx.TextCellValue.new).toList(),
  );
  return Uint8List.fromList(workbook.encode()!);
}

Future<void> _pumpUi(WidgetTester tester) async {
  for (var frame = 0; frame < 12; frame++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 250));
  }
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory databaseDirectory;

  setUp(() async {
    databaseDirectory = await Directory.systemTemp.createTemp(
      'pocketr-widget-database-',
    );
    FinanceSqliteStore.instance = FinanceSqliteStore.withDirectory(
      databaseDirectory,
    );
    LocalFileArchive.instance = LocalFileArchive.inMemory();
    SharedPreferences.setMockInitialValues({});
    appLanguageCode.value = 'id';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_windowManagerChannel, (call) async {
          if (call.method == 'isMaximized') return false;
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_windowStateChannel, (call) async {
          if (call.method == 'dismissDialogOnOutsideClick') return true;
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_windowManagerChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_windowStateChannel, null);
    appLanguageCode.value = 'id';
  });

  tearDown(() async {
    await FinanceSqliteStore.instance.close();
    await databaseDirectory.delete(recursive: true);
    await LocalFileArchive.instance.close();
    FinanceSqliteStore.instance = FinanceSqliteStore();
    LocalFileArchive.instance = LocalFileArchive();
  });

  Future<void> pumpFinanceHome(
    WidgetTester tester, {
    bool includeAppNotificationLayer = false,
  }) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      includeAppNotificationLayer
          ? const PocketRApp()
          : const MaterialApp(home: FinanceHome()),
    );
    await _pumpUi(tester);
  }

  testWidgets('desktop navigation opens each primary section', (tester) async {
    await pumpFinanceHome(tester);
    expect(tester.takeException(), isNull, reason: 'initial summary layout');
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Image && widget.image is MemoryImage,
      ),
      findsOneWidget,
    );

    expect(find.text('Ringkasan Bulanan'), findsOneWidget);

    await tester.tap(find.text('Penjualan').first);
    await _pumpUi(tester);
    expect(tester.takeException(), isNull, reason: 'sales page layout');
    expect(find.text('Impor Penjualan'), findsOneWidget);

    await tester.tap(find.text('Pengeluaran').first);
    await _pumpUi(tester);
    expect(tester.takeException(), isNull, reason: 'expenses page layout');
    expect(find.text('Pengeluaran').last, findsOneWidget);

    await tester.tap(find.text('Produk dan HPP').first);
    await _pumpUi(tester);
    expect(tester.takeException(), isNull, reason: 'products page layout');
    expect(find.text('Produk dan HPP').last, findsOneWidget);

    await tester.tap(find.text('Ringkasan').first);
    await _pumpUi(tester);
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

    expect(preferences.getString('pocketr_v1'), isNull);
    expect((await FinanceSqliteStore.instance.load())?.sales, hasLength(2));
    final legacyArchive = File(
      p.join(
        (await FinanceSqliteStore.instance.supportDirectory()).path,
        'legacy_backup',
        'pocketr_v1.json',
      ),
    );
    expect(legacyArchive.readAsStringSync(), data.toBackup());
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
    await _pumpUi(tester);
    await tester.tap(find.text('Impor Penjualan').last);
    await _pumpUi(tester);

    expect(find.text('Template input manual'), findsOneWidget);
    expect(find.text('Impor Excel'), findsOneWidget);
    expect(find.text('Unduh template'), findsOneWidget);
  });

  testWidgets('Shopee import starts after selecting two files', (tester) async {
    final orderWorkbook = _workbookBytes([
      'No. Pesanan',
      'Status Pesanan',
      'Jumlah',
      'Subtotal Pesanan',
    ]);
    final balanceWorkbook = _workbookBytes([
      'Tipe Transaksi',
      'No. Pesanan',
      'Jenis Transaksi',
      'Jumlah',
      'Status',
    ]);
    FilePicker.platform = _FixedFilePicker.withFiles([
      PlatformFile(
        name: 'orders.xlsx',
        size: orderWorkbook.length,
        bytes: orderWorkbook,
      ),
      PlatformFile(
        name: 'balance.xlsx',
        size: balanceWorkbook.length,
        bytes: balanceWorkbook,
      ),
    ]);
    addTearDown(() => FilePicker.platform = _FixedFilePicker(null));
    await pumpFinanceHome(tester);

    await tester.tap(find.text('Penjualan').first);
    await _pumpUi(tester);
    await tester.tap(find.text('Impor Penjualan').last);
    await _pumpUi(tester);

    expect(find.text('Batal'), findsNothing);
    expect(find.text('Impor'), findsNothing);
    await tester.tap(find.byIcon(Icons.close).last);
    await _pumpUi(tester);
    expect(find.text('Impor penjualan dari Excel'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Impor Penjualan').last);
    await _pumpUi(tester);
    await tester.tap(find.text('Pilih 2 berkas'));
    await _pumpUi(tester);

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
    await _pumpUi(tester);
    await tester.tap(find.text('Impor Penjualan').last);
    await _pumpUi(tester);
    await tester.tap(find.text('Impor Excel'));
    await tester.pump();
    expect(find.text('Membaca berkas Excel...'), findsNothing);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 1)),
    );
    await _pumpUi(tester);

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
    await _pumpUi(tester);
    expect(find.text('Impor penjualan dari Excel'), findsNothing);

    final savedData = (await FinanceSqliteStore.instance.load())!;
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
    await _pumpUi(tester);
    expect(find.text('Audit bag'), findsNWidgets(2));
    await tester.tap(find.text('Keep product').first);
    await _pumpUi(tester);
    expect(find.text('Keep product'), findsNWidgets(2));
    await tester.tap(find.text('Audit pouch').first);
    await _pumpUi(tester);
    expect(find.text('Audit pouch'), findsNWidgets(2));
    await tester.tap(find.text('Audit bag').first);
    await _pumpUi(tester);
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
    await _pumpUi(tester);
    expect(find.text('Peringatan'), findsOneWidget);
    expect(find.text('Restore Settings'), findsOneWidget);
    expect(find.text('Backup Settings'), findsOneWidget);

    final resetButton = find.text('Atur ulang semua data');
    await tester.ensureVisible(resetButton);
    await tester.tap(resetButton);
    await _pumpUi(tester);
    expect(find.text('Hapus semua data?'), findsOneWidget);

    await tester.tap(find.text('Batal'));
    await _pumpUi(tester);
    expect(find.text('Hapus semua data?'), findsNothing);
    expect((await FinanceSqliteStore.instance.load())!.products, hasLength(1));
  });

  testWidgets('Restore Settings opens the backup file picker', (tester) async {
    final picker = _FixedFilePicker(null);
    FilePicker.platform = picker;
    addTearDown(() => FilePicker.platform = _FixedFilePicker(null));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_windowStateChannel, (call) async {
          if (call.method == 'dismissDialogOnOutsideClick') return true;
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_windowStateChannel, null),
    );
    await pumpFinanceHome(tester);

    await tester.tap(find.text('Pengaturan').last);
    await _pumpUi(tester);
    expect(find.text('Restore Settings'), findsOneWidget);
    expect(find.text('Backup Settings'), findsOneWidget);
    final buttonsAlignment = find
        .ancestor(
          of: find.text('Backup Settings'),
          matching: find.byType(Align),
        )
        .first;
    final backupButton = find
        .ancestor(
          of: find.text('Backup Settings'),
          matching: find.byType(InkWell),
        )
        .first;
    expect(
      tester.getRect(backupButton).right,
      closeTo(tester.getRect(buttonsAlignment).right, 0.5),
    );

    await tester.tap(find.text('Restore Settings'));
    await _pumpUi(tester);

    expect(picker.pickFilesRequested, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('restores legacy JSON and archives it outside SQLite', (
    tester,
  ) async {
    final data = FinanceData(
      products: [Product(id: 'legacy-product', name: 'Legacy bag')],
      sales: [
        Sale(
          id: 'legacy-sale',
          date: '2026-10-16',
          platform: 'shopee',
          productId: 'legacy-product',
          productName: 'Legacy bag',
          received: 50000,
        ),
      ],
    );
    final backupBytes = Uint8List.fromList(utf8.encode(data.toBackup()));
    FilePicker.platform = _FixedFilePicker.withFiles([
      PlatformFile(
        name: 'legacy-backup.json',
        size: backupBytes.length,
        bytes: backupBytes,
      ),
    ]);
    addTearDown(() => FilePicker.platform = _FixedFilePicker(null));
    await pumpFinanceHome(tester);

    await tester.tap(find.text('Pengaturan').last);
    await _pumpUi(tester);
    await tester.tap(find.text('Restore Settings'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await _pumpUi(tester);

    final restored = await FinanceSqliteStore.instance.load();
    expect(restored?.products.single.name, 'Legacy bag');
    expect(restored?.sales.single.received, 50000);
    expect(
      await tester.runAsync(() => LocalFileArchive.instance.listFiles()),
      isEmpty,
    );
    final legacyFiles = Directory(
      p.join(
        (await FinanceSqliteStore.instance.supportDirectory()).path,
        'legacy_backup',
      ),
    ).listSync();
    expect(legacyFiles, hasLength(1));
    expect(File(legacyFiles.single.path).readAsBytesSync(), backupBytes);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Backup Settings opens the save dialog before preparing data', (
    tester,
  ) async {
    final picker = _FixedFilePicker(null);
    FilePicker.platform = picker;
    addTearDown(() => FilePicker.platform = _FixedFilePicker(null));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_windowStateChannel, (call) async {
          if (call.method == 'dismissDialogOnOutsideClick') return true;
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_windowStateChannel, null),
    );
    await pumpFinanceHome(tester);

    await tester.tap(find.text('Pengaturan').last);
    await _pumpUi(tester);
    await tester.tap(find.text('Backup Settings'));
    await _pumpUi(tester);

    expect(picker.saveFileRequested, isTrue);
    expect(picker.saveFileBytes, isNull);
    expect(find.text('Pengaturan').last, findsOneWidget);
    expect(find.text('Restore Settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('notifications render over the settings dialog', (tester) async {
    final picker = _FixedFilePicker(null)..directoryPickerShouldThrow = true;
    FilePicker.platform = picker;
    addTearDown(() => FilePicker.platform = _FixedFilePicker(null));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_windowStateChannel, (call) async {
          if (call.method == 'dismissDialogOnOutsideClick') return true;
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_windowStateChannel, null),
    );
    await pumpFinanceHome(tester, includeAppNotificationLayer: true);

    await tester.tap(find.text('Pengaturan').last);
    await _pumpUi(tester);
    await tester.tap(find.text('Pilih folder'));
    await _pumpUi(tester);

    final notificationFinder = find.textContaining(
      'Direktori auto-save gagal dipilih',
    );
    expect(notificationFinder, findsOneWidget);
    final notificationText = tester.widget<Text>(notificationFinder);
    expect(notificationText.style?.fontSize, 13);
    expect(notificationText.style?.decoration, TextDecoration.none);
    expect(tester.getRect(notificationFinder).height, lessThan(80));
    expect(find.text('Restore Settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
    await _pumpUi(tester);
    final resetButton = find.text('Atur ulang semua data');
    await tester.ensureVisible(resetButton);
    await tester.tap(resetButton);
    await _pumpUi(tester);
    await tester.tap(find.text('Hapus'));
    await _pumpUi(tester);

    expect(await FinanceSqliteStore.instance.load(), isNull);
    await FinanceSqliteStore.instance.close();
    final database = sqlite3.open(
      p.join(databaseDirectory.path, 'pocketr.db'),
      mode: OpenMode.readOnly,
    );
    try {
      for (final table in [
        'app_settings',
        'products',
        'product_materials',
        'product_attributes',
        'stock_entries',
        'materials',
        'sales',
        'expenses',
        'owners',
        'paid',
        'shopee_product_mappings',
        'archived_files',
      ]) {
        expect(
          database
              .select('SELECT COUNT(*) AS count FROM $table')
              .single['count'],
          0,
          reason: '$table should be empty after reset',
        );
      }
    } finally {
      database.close();
    }
  });

  testWidgets('new product is saved to local storage', (tester) async {
    await pumpFinanceHome(tester);

    await tester.tap(find.text('Produk dan HPP').first);
    await _pumpUi(tester);
    await tester.tap(find.text('Tambah produk').last);
    await _pumpUi(tester);
    await tester.enterText(find.byType(TextFormField).first, 'Audit product');
    await tester.tap(find.text('Simpan').last);
    await _pumpUi(tester);

    final savedData = (await FinanceSqliteStore.instance.load())!;
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
    await _pumpUi(tester);
    await tester.tap(find.text('Tambah penjualan').last);
    await _pumpUi(tester);
    await tester.enterText(find.byType(TextFormField).at(1), '25000');
    await tester.tap(find.text('Simpan').last);
    await _pumpUi(tester);

    final savedData = (await FinanceSqliteStore.instance.load())!;
    expect(savedData.sales, hasLength(1));
    expect(savedData.sales.single.productId, 'audit-product');
    expect(savedData.sales.single.received, 25000);
  });

  testWidgets('new operating expense is saved locally', (tester) async {
    await pumpFinanceHome(tester);

    await tester.tap(find.text('Pengeluaran').first);
    await _pumpUi(tester);
    await tester.tap(find.text('Tambah biaya').last);
    await _pumpUi(tester);
    await tester.enterText(find.byType(TextFormField).first, 'Packaging');
    await tester.enterText(find.byType(TextFormField).at(1), '5000');
    await tester.tap(find.text('Simpan').last);
    await _pumpUi(tester);

    final savedData = (await FinanceSqliteStore.instance.load())!;
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
  bool pickFilesRequested = false;
  bool saveFileRequested = false;
  bool directoryPickerShouldThrow = false;
  Uint8List? saveFileBytes;

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
  }) async {
    pickFilesRequested = true;
    return _result;
  }

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    saveFileRequested = true;
    saveFileBytes = bytes;
    return null;
  }

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    bool lockParentWindow = false,
    String? initialDirectory,
  }) async {
    if (directoryPickerShouldThrow) {
      throw StateError('Test directory picker failure');
    }
    return null;
  }
}
