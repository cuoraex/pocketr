import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pocketr/backup.dart';
import 'package:pocketr/data.dart';
import 'package:pocketr/finance_database.dart';
import 'package:pocketr/local_file_archive.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('backup file extension defaults to pcktr', () {
    expect(
      ensureBackupFileExtension(r'C:\backups\my-backup'),
      r'C:\backups\my-backup.pcktr',
    );
    expect(
      ensureBackupFileExtension(r'C:\backups\my-backup.pcktr'),
      r'C:\backups\my-backup.pcktr',
    );
    expect(
      ensureBackupFileExtension(r'C:\backups\my-backup.JSON'),
      r'C:\backups\my-backup.pcktr',
    );
  });

  test(
    'full backup is SQLite and includes data, photos, and archived files',
    () async {
      final data = FinanceData(
        logo: 'data:image/png;base64,bG9nbw==',
        products: [
          Product(name: 'Tas', img: 'data:image/jpeg;base64,cGhvdG8='),
        ],
        targetRevenue: 125000,
      );
      final files = [
        ArchivedFile(
          name: 'sales.csv',
          extension: 'csv',
          contentType: 'text/csv',
          source: 'sales_import',
          importedAt: '2026-10-16T00:00:00.000',
          sizeBytes: 3,
          bytes: Uint8List.fromList([65, 44, 66]),
        ),
      ];

      final bytes = createFullBackupBytes(data, files);
      expect(String.fromCharCodes(bytes.take(16)), 'SQLite format 3\u0000');

      final restored = await FinanceSqliteStore.readBackupBytes(bytes);
      expect(restored.data.logo, data.logo);
      expect(restored.data.products.single.img, data.products.single.img);
      expect(restored.data.targetRevenue, 125000);
      expect(restored.files.single.name, 'sales.csv');
      expect(restored.files.single.bytes, [65, 44, 66]);
    },
  );

  test(
    'regular backup is SQLite and excludes archived files and photos',
    () async {
      final data = FinanceData(
        logo: 'data:image/png;base64,bG9nbw==',
        products: [
          Product(name: 'Tas', img: 'data:image/jpeg;base64,cGhvdG8='),
        ],
        sales: [
          Sale(
            date: '2026-10-16',
            platform: 'shopee',
            productId: '1',
            productName: 'Tas',
            qty: 2,
            received: 100,
          ),
        ],
      );

      final restored = await FinanceSqliteStore.readBackupBytes(
        createBackupBytes(data),
      );
      expect(restored.data.sales.single.productName, 'Tas');
      expect(restored.data.logo, isEmpty);
      expect(restored.data.products.single.img, isEmpty);
      expect(restored.files, isEmpty);
    },
  );

  test(
    'overwrite backup keeps a single file and replaces its content',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'pocketr_overwrite_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final path = p.join(directory.path, 'pocketr-autosave.pcktr');

      await writeOverwriteBackup(path, Uint8List.fromList([1, 2, 3]));
      await writeOverwriteBackup(path, Uint8List.fromList([4, 5]));

      expect(await File(path).readAsBytes(), [4, 5]);
      final files = await directory
          .list()
          .map((e) => p.basename(e.path))
          .toList();
      expect(files, ['pocketr-autosave.pcktr']);
    },
  );

  test('timestamped backups retain only the latest seven versions', () async {
    final directory = await Directory.systemTemp.createTemp(
      'pocketr-backup-retention-',
    );
    try {
      final timestamp = DateTime(2026, 10, 16, 12, 30, 45, 123);
      for (var index = 0; index < 8; index++) {
        await writeTimestampedBackup(
          p.join(directory.path, 'selected.pcktr'),
          Uint8List.fromList([index]),
          prefix: 'pocketr-',
          now: timestamp,
        );
      }
      final backups = await directory
          .list()
          .where((entry) => entry is File)
          .cast<File>()
          .toList();
      expect(backups, hasLength(7));
      expect(
        backups.map((file) => p.basename(file.path)),
        everyElement(
          matches(RegExp(r'^pocketr-20261016-123045-123-\d{4}\.pcktr$')),
        ),
      );
      expect(backups.map((file) => file.readAsBytesSync().single).toSet(), {
        1,
        2,
        3,
        4,
        5,
        6,
        7,
      });
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('finance data persists in SQLite tables', () async {
    final directory = await Directory.systemTemp.createTemp(
      'pocketr-finance-database-',
    );
    var store = FinanceSqliteStore.withDirectory(directory);
    try {
      final data = FinanceData(
        businessName: 'Usaha',
        products: [
          Product(
            id: 'product-1',
            name: 'Tas',
            colors: ['Biru'],
            sizes: ['M'],
            variants: ['Biru / M'],
            materials: [
              MaterialCost(
                id: 'product-material-1',
                name: 'Kain',
                qty: 2,
                unit: 'meter',
                price: 12,
                ref: 'material-1',
                category: MaterialCategory.bahanBaku,
              ),
            ],
            stock: StockData(
              log: [
                StockEntry(
                  id: 'stock-1',
                  date: '2026-10-16',
                  qty: 3,
                  note: 'Restock',
                  color: 'Biru',
                ),
              ],
            ),
          ),
        ],
        materials: [MaterialCost(id: 'material-1', name: 'Kain', price: 12)],
        sales: [
          Sale(
            id: 'sale-1',
            date: '2026-10-16',
            platform: 'shopee',
            productId: 'product-1',
            productName: 'Tas',
            qty: 1,
            received: 100,
            hpp: 24,
            color: 'Biru',
            size: 'M',
          ),
        ],
        expenses: [
          Expense(
            id: 'expense-1',
            month: '2026-10',
            category: 'operasional',
            name: 'Packing',
            amount: 10,
          ),
        ],
        targetRevenue: 450000,
        paid: {'2026-10:o1': true},
        shopeeProductMappings: {'Tas': 'product-1'},
      );
      await store.save(data);
      await store.close();
      store = FinanceSqliteStore.withDirectory(directory);
      final loaded = await store.load();

      expect(loaded?.businessName, 'Usaha');
      expect(loaded?.products.single.id, 'product-1');
      expect(loaded?.products.single.colors, ['Biru']);
      expect(loaded?.products.single.materials.single.ref, 'material-1');
      expect(loaded?.products.single.stock?.log.single.note, 'Restock');
      expect(loaded?.materials.single.price, 12);
      expect(loaded?.sales.single.received, 100);
      expect(loaded?.expenses.single.name, 'Packing');
      expect(loaded?.paid['2026-10:o1'], isTrue);
      expect(loaded?.shopeeProductMappings['Tas'], 'product-1');
      expect(loaded?.targetRevenue, 450000);
      final database = sqlite3.open(
        p.join(directory.path, 'pocketr.db'),
        mode: OpenMode.readOnly,
      );
      try {
        expect(
          database
              .select("SELECT typeof(received) AS type FROM sales")
              .single['type'],
          'integer',
        );
        expect(
          database
              .select("SELECT typeof(amount) AS type FROM expenses")
              .single['type'],
          'integer',
        );
        expect(
          database
              .select(
                "SELECT typeof(value) AS type FROM app_settings WHERE key = 'targetRevenue'",
              )
              .single['type'],
          'integer',
        );
        expect(
          database.select('PRAGMA journal_mode').single.values.single,
          'wal',
        );
      } finally {
        database.close();
      }
    } finally {
      await store.close();
      await directory.delete(recursive: true);
    }
  });

  test('upgrades legacy SQLite money columns to integers', () async {
    final directory = await Directory.systemTemp.createTemp(
      'pocketr-finance-money-migration-',
    );
    final legacyDatabase = sqlite3.open(p.join(directory.path, 'pocketr.db'));
    legacyDatabase.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    legacyDatabase.execute(
      "INSERT INTO app_settings (key, value) VALUES ('targetRevenue', '120.5')",
    );
    legacyDatabase.execute('''
      CREATE TABLE sales (
        id TEXT NOT NULL,
        date TEXT NOT NULL,
        platform TEXT NOT NULL,
        product_id TEXT NOT NULL,
        product_name TEXT NOT NULL,
        qty REAL NOT NULL,
        order_no TEXT NOT NULL,
        received REAL NOT NULL,
        hpp REAL NOT NULL,
        color TEXT NOT NULL,
        size TEXT NOT NULL,
        other TEXT NOT NULL
      )
    ''');
    legacyDatabase.execute('''
      INSERT INTO sales
      VALUES ('sale-1', '2026-10-16', 'shopee', '', 'Bag', 1, '', 12.5, 3.5, '', '', '')
    ''');
    legacyDatabase.close();

    final store = FinanceSqliteStore.withDirectory(directory);
    try {
      final loaded = await store.load();
      expect(loaded?.targetRevenue, 121);
      expect(loaded?.sales.single.received, 13);
      await store.close();

      final database = sqlite3.open(
        p.join(directory.path, 'pocketr.db'),
        mode: OpenMode.readOnly,
      );
      try {
        expect(
          database
              .select(
                "SELECT typeof(value) AS type FROM app_settings WHERE key = 'targetRevenue'",
              )
              .single['type'],
          'integer',
        );
        expect(
          database
              .select("SELECT typeof(received) AS type FROM sales")
              .single['type'],
          'integer',
        );
        expect(
          database
              .select("SELECT typeof(hpp) AS type FROM sales")
              .single['type'],
          'integer',
        );
      } finally {
        database.close();
      }
    } finally {
      await store.close();
      await directory.delete(recursive: true);
    }
  });

  test('clearData removes every finance and archive table row', () async {
    final directory = await Directory.systemTemp.createTemp(
      'pocketr-finance-clear-',
    );
    final store = FinanceSqliteStore.withDirectory(directory);
    try {
      await store.save(
        FinanceData(
          products: [Product(name: 'Bag')],
          sales: [
            Sale(
              date: '2026-10-16',
              platform: 'shopee',
              productId: '',
              productName: 'Bag',
              received: 100,
            ),
          ],
          expenses: [
            Expense(
              month: '2026-10',
              category: 'operasional',
              name: 'Packaging',
              amount: 10,
            ),
          ],
        ),
      );
      await store.clearData();
      expect(await store.load(), isNull);

      final database = sqlite3.open(
        p.join(directory.path, 'pocketr.db'),
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
    } finally {
      await store.close();
      await directory.delete(recursive: true);
    }
  });
}
