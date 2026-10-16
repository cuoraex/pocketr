import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'data.dart';
import 'local_file_archive.dart';

class SqliteBackupContents {
  const SqliteBackupContents({required this.data, required this.files});

  final FinanceData data;
  final List<ArchivedFile> files;
}

class FinanceSqliteStore {
  FinanceSqliteStore() : _directory = null;

  FinanceSqliteStore.withDirectory(Directory directory)
    : _directory = directory;

  FinanceSqliteStore.inMemory({Directory? supportDirectory})
    : _directory = supportDirectory {
    _inMemoryDatabase = sqlite3.openInMemory();
    _createSchema(_inMemoryDatabase!);
  }

  static FinanceSqliteStore instance = FinanceSqliteStore();

  final Directory? _directory;
  Database? _inMemoryDatabase;
  Database? _database;
  Future<Database>? _opening;

  Future<FinanceData?> load() async {
    final database = await _open();
    return _readData(database);
  }

  Future<Directory> supportDirectory() async =>
      _directory ?? await getApplicationSupportDirectory();

  Future<void> save(FinanceData data) {
    final database = _database ?? _inMemoryDatabase;
    if (database != null) {
      _writeData(database, data);
      return Future<void>.value();
    }
    return _open().then((database) => _writeData(database, data));
  }

  Future<void> clearData() async {
    final database = await _open();
    database.execute('BEGIN IMMEDIATE');
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
        database.execute('DELETE FROM $table');
      }
      database.execute('COMMIT');
    } catch (_) {
      database.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<void> close() async {
    final inMemoryDatabase = _inMemoryDatabase;
    if (inMemoryDatabase != null) {
      inMemoryDatabase.close();
      _inMemoryDatabase = null;
      return;
    }
    final opening = _opening;
    if (opening == null) return;
    final database = _database ?? await opening;
    database.close();
    _database = null;
    _opening = null;
  }

  Future<Database> _open() {
    final inMemoryDatabase = _inMemoryDatabase;
    if (inMemoryDatabase != null) return Future.value(inMemoryDatabase);
    final database = _database;
    if (database != null) return Future.value(database);
    return _opening ??= _openDatabase();
  }

  Future<Database> _openDatabase() async {
    final directory = _directory ?? await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    final database = sqlite3.open(p.join(directory.path, 'pocketr.db'));
    final journalMode = database.select('PRAGMA journal_mode = WAL');
    if (journalMode.single.values.single.toString().toLowerCase() != 'wal') {
      database.close();
      throw StateError('SQLite gagal mengaktifkan write-ahead logging.');
    }
    _createSchema(database);
    _migrateMoneyStorage(database);
    _database = database;
    return database;
  }

  static void _migrateMoneyStorage(Database database) {
    final migrations = <(String, String, String, String)>[
      (
        'app_settings',
        'value',
        'key, value',
        'key, CASE WHEN key = \'targetRevenue\' THEN CAST(ROUND(value) AS INTEGER) ELSE value END',
      ),
      (
        'product_materials',
        'price',
        'product_id, position, id, name, qty, unit, price, ref, category',
        'product_id, position, id, name, qty, unit, CAST(ROUND(price) AS INTEGER), ref, category',
      ),
      (
        'materials',
        'price',
        'id, name, qty, unit, price, ref, category',
        'id, name, qty, unit, CAST(ROUND(price) AS INTEGER), ref, category',
      ),
      (
        'sales',
        'received',
        'id, date, platform, product_id, product_name, qty, order_no, received, hpp, color, size, other',
        'id, date, platform, product_id, product_name, qty, order_no, CAST(ROUND(received) AS INTEGER), CAST(ROUND(hpp) AS INTEGER), color, size, other',
      ),
      (
        'expenses',
        'amount',
        'id, month, category, name, date, amount, note, platform, product_id, product_name, ppn',
        'id, month, category, name, date, CAST(ROUND(amount) AS INTEGER), note, platform, product_id, product_name, ppn',
      ),
    ];
    final needsMigration = migrations.where((migration) {
      final (table, column, _, _) = migration;
      final columns = database.select('PRAGMA table_info($table)');
      final existing = columns.where((row) => row['name'] == column);
      return existing.isNotEmpty &&
          existing.single['type'].toString().toUpperCase() != 'INTEGER' &&
          !(table == 'app_settings' &&
              existing.single['type'].toString().isEmpty);
    }).toList();
    if (needsMigration.isEmpty) return;

    database.execute('BEGIN IMMEDIATE');
    try {
      for (final migration in needsMigration) {
        final (table, _, columns, selectColumns) = migration;
        final temporaryTable = '${table}_integer_migration';
        final originalDefinition =
            database.select(
                  "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?",
                  [table],
                ).single['sql']
                as String;
        final updatedDefinition = switch (table) {
          'app_settings' =>
            '''
            CREATE TABLE $temporaryTable (
              key TEXT PRIMARY KEY,
              value NOT NULL
            )
          ''',
          'product_materials' =>
            '''
            CREATE TABLE $temporaryTable (
              product_id TEXT NOT NULL, position INTEGER NOT NULL, id TEXT NOT NULL,
              name TEXT NOT NULL, qty REAL NOT NULL, unit TEXT NOT NULL,
              price INTEGER NOT NULL, ref TEXT, category TEXT NOT NULL
            )
          ''',
          'materials' =>
            '''
            CREATE TABLE $temporaryTable (
              id TEXT NOT NULL, name TEXT NOT NULL, qty REAL NOT NULL,
              unit TEXT NOT NULL, price INTEGER NOT NULL, ref TEXT,
              category TEXT NOT NULL
            )
          ''',
          'sales' =>
            '''
            CREATE TABLE $temporaryTable (
              id TEXT NOT NULL, date TEXT NOT NULL, platform TEXT NOT NULL,
              product_id TEXT NOT NULL, product_name TEXT NOT NULL,
              qty REAL NOT NULL, order_no TEXT NOT NULL, received INTEGER NOT NULL,
              hpp INTEGER NOT NULL, color TEXT NOT NULL, size TEXT NOT NULL,
              other TEXT NOT NULL
            )
          ''',
          _ =>
            '''
            CREATE TABLE $temporaryTable (
              id TEXT NOT NULL, month TEXT NOT NULL, category TEXT NOT NULL,
              name TEXT NOT NULL, date TEXT NOT NULL, amount INTEGER NOT NULL,
              note TEXT NOT NULL, platform TEXT NOT NULL, product_id TEXT NOT NULL,
              product_name TEXT NOT NULL, ppn INTEGER NOT NULL
            )
          ''',
        };
        if (originalDefinition.isEmpty) {
          throw StateError('Skema tabel SQLite $table tidak ditemukan.');
        }
        database.execute(updatedDefinition);
        database.execute(
          'INSERT INTO $temporaryTable ($columns) SELECT $selectColumns FROM $table',
        );
        database.execute('DROP TABLE $table');
        database.execute('ALTER TABLE $temporaryTable RENAME TO $table');
      }
      database.execute('COMMIT');
    } catch (_) {
      database.execute('ROLLBACK');
      rethrow;
    }
  }

  static Uint8List createBackupBytes(
    FinanceData data, {
    List<ArchivedFile> files = const [],
    required bool includeFiles,
  }) {
    final tempDirectory = Directory.systemTemp.createTempSync(
      'pocketr-sqlite-backup-',
    );
    final databasePath = p.join(tempDirectory.path, 'pocketr-source.db');
    final backupPath = p.join(tempDirectory.path, 'pocketr-backup.db');
    final database = sqlite3.open(databasePath);
    try {
      _createSchema(database);
      _writeData(database, data, includeImages: includeFiles);
      if (includeFiles) _writeArchivedFiles(database, files);
      database.execute(
        "INSERT OR REPLACE INTO metadata (key, value) VALUES ('format', 'pocketr-sqlite-backup')",
      );
      database.execute("VACUUM INTO '${backupPath.replaceAll("'", "''")}'");
      return Uint8List.fromList(File(backupPath).readAsBytesSync());
    } finally {
      database.close();
      tempDirectory.deleteSync(recursive: true);
    }
  }

  static Future<SqliteBackupContents> readBackupBytes(Uint8List bytes) async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'pocketr-sqlite-restore-',
    );
    final databasePath = p.join(tempDirectory.path, 'pocketr-backup.db');
    try {
      await File(databasePath).writeAsBytes(bytes, flush: true);
      final database = sqlite3.open(databasePath, mode: OpenMode.readOnly);
      try {
        final format = database.select(
          "SELECT value FROM metadata WHERE key = 'format'",
        );
        if (format.isEmpty ||
            format.single['value'] != 'pocketr-sqlite-backup') {
          throw const FormatException(
            'Format cadangan SQLite PocketR tidak valid.',
          );
        }
        final data = _readData(database);
        if (data == null) {
          throw const FormatException('Data keuangan tidak ditemukan.');
        }
        return SqliteBackupContents(
          data: data,
          files: _readArchivedFiles(database),
        );
      } finally {
        database.close();
      }
    } finally {
      await tempDirectory.delete(recursive: true);
    }
  }

  static void _createSchema(Database database) {
    database.execute('''
      CREATE TABLE IF NOT EXISTS metadata (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    database.execute('''
      INSERT OR IGNORE INTO metadata (key, value)
      VALUES ('format', 'pocketr-sqlite'), ('version', '1')
    ''');
    database.execute('''
      CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY,
        value NOT NULL
      )
    ''');
    database.execute('''
      CREATE TABLE IF NOT EXISTS products (
        id TEXT NOT NULL,
        name TEXT NOT NULL,
        image TEXT NOT NULL,
        has_stock INTEGER NOT NULL
      )
    ''');
    database.execute('''
      CREATE TABLE IF NOT EXISTS product_materials (
        product_id TEXT NOT NULL,
        position INTEGER NOT NULL,
        id TEXT NOT NULL,
        name TEXT NOT NULL,
        qty REAL NOT NULL,
        unit TEXT NOT NULL,
        price INTEGER NOT NULL,
        ref TEXT,
        category TEXT NOT NULL
      )
    ''');
    database.execute('''
      CREATE TABLE IF NOT EXISTS product_attributes (
        product_id TEXT NOT NULL,
        kind TEXT NOT NULL,
        position INTEGER NOT NULL,
        value TEXT NOT NULL
      )
    ''');
    database.execute('''
      CREATE TABLE IF NOT EXISTS stock_entries (
        product_id TEXT NOT NULL,
        position INTEGER NOT NULL,
        id TEXT NOT NULL,
        date TEXT NOT NULL,
        qty REAL NOT NULL,
        note TEXT NOT NULL,
        color TEXT NOT NULL
      )
    ''');
    database.execute('''
      CREATE TABLE IF NOT EXISTS materials (
        id TEXT NOT NULL,
        name TEXT NOT NULL,
        qty REAL NOT NULL,
        unit TEXT NOT NULL,
        price INTEGER NOT NULL,
        ref TEXT,
        category TEXT NOT NULL
      )
    ''');
    database.execute('''
      CREATE TABLE IF NOT EXISTS sales (
        id TEXT NOT NULL,
        date TEXT NOT NULL,
        platform TEXT NOT NULL,
        product_id TEXT NOT NULL,
        product_name TEXT NOT NULL,
        qty REAL NOT NULL,
        order_no TEXT NOT NULL,
        received INTEGER NOT NULL,
        hpp INTEGER NOT NULL,
        color TEXT NOT NULL,
        size TEXT NOT NULL,
        other TEXT NOT NULL
      )
    ''');
    database.execute('''
      CREATE TABLE IF NOT EXISTS expenses (
        id TEXT NOT NULL,
        month TEXT NOT NULL,
        category TEXT NOT NULL,
        name TEXT NOT NULL,
        date TEXT NOT NULL,
        amount INTEGER NOT NULL,
        note TEXT NOT NULL,
        platform TEXT NOT NULL,
        product_id TEXT NOT NULL,
        product_name TEXT NOT NULL,
        ppn INTEGER NOT NULL
      )
    ''');
    database.execute('''
      CREATE TABLE IF NOT EXISTS owners (
        id TEXT NOT NULL,
        name TEXT NOT NULL,
        pct REAL NOT NULL
      )
    ''');
    database.execute('''
      CREATE TABLE IF NOT EXISTS paid (
        key TEXT PRIMARY KEY,
        value INTEGER NOT NULL
      )
    ''');
    database.execute('''
      CREATE TABLE IF NOT EXISTS shopee_product_mappings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    database.execute('''
      CREATE TABLE IF NOT EXISTS archived_files (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        extension TEXT NOT NULL,
        content_type TEXT NOT NULL,
        source TEXT NOT NULL,
        imported_at TEXT NOT NULL,
        size_bytes INTEGER NOT NULL,
        bytes BLOB NOT NULL
      )
    ''');
  }

  static void _writeData(
    Database database,
    FinanceData data, {
    bool includeImages = false,
  }) {
    database.execute('BEGIN IMMEDIATE');
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
      ]) {
        database.execute('DELETE FROM $table');
      }
      final settings = <String, Object?>{
        'businessName': data.businessName,
        'tagline': data.tagline,
        'zakatPct': data.zakatPct,
        'ppnPct': data.ppnPct,
        'targetRevenue': data.targetRevenue.round(),
        'stockWarningThreshold': data.stockWarningThreshold,
        if (includeImages && data.logo.isNotEmpty) 'logo': data.logo,
      };
      for (final entry in settings.entries) {
        database.execute(
          'INSERT INTO app_settings (key, value) VALUES (?, ?)',
          [entry.key, entry.value],
        );
      }
      for (final product in data.products) {
        database.execute(
          '''
          INSERT INTO products (id, name, image, has_stock)
          VALUES (?, ?, ?, ?)
          ''',
          [
            product.id,
            product.name,
            includeImages ? product.img : '',
            product.stock == null ? 0 : 1,
          ],
        );
        for (var index = 0; index < product.materials.length; index++) {
          final material = product.materials[index];
          database.execute(
            '''
            INSERT INTO product_materials
              (product_id, position, id, name, qty, unit, price, ref, category)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''',
            [
              product.id,
              index,
              material.id,
              material.name,
              material.qty,
              material.unit,
              material.price.round(),
              material.ref,
              material.category.name,
            ],
          );
        }
        for (final (kind, values) in [
          ('color', product.colors),
          ('size', product.sizes),
          ('variant', product.variants),
        ]) {
          for (var index = 0; index < values.length; index++) {
            database.execute(
              '''
              INSERT INTO product_attributes (product_id, kind, position, value)
              VALUES (?, ?, ?, ?)
              ''',
              [product.id, kind, index, values[index]],
            );
          }
        }
        if (product.stock case final stock?) {
          for (var index = 0; index < stock.log.length; index++) {
            final entry = stock.log[index];
            database.execute(
              '''
              INSERT INTO stock_entries
                (product_id, position, id, date, qty, note, color)
              VALUES (?, ?, ?, ?, ?, ?, ?)
              ''',
              [
                product.id,
                index,
                entry.id,
                entry.date,
                entry.qty,
                entry.note,
                entry.color,
              ],
            );
          }
        }
      }
      for (final material in data.materials) {
        database.execute(
          '''
          INSERT INTO materials (id, name, qty, unit, price, ref, category)
          VALUES (?, ?, ?, ?, ?, ?, ?)
          ''',
          [
            material.id,
            material.name,
            material.qty,
            material.unit,
            material.price.round(),
            material.ref,
            material.category.name,
          ],
        );
      }
      for (final sale in data.sales) {
        database.execute(
          '''
          INSERT INTO sales
            (id, date, platform, product_id, product_name, qty, order_no,
             received, hpp, color, size, other)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ''',
          [
            sale.id,
            sale.date,
            sale.platform,
            sale.productId,
            sale.productName,
            sale.qty,
            sale.orderNo,
            sale.received.round(),
            sale.hpp.round(),
            sale.color,
            sale.size,
            sale.other,
          ],
        );
      }
      for (final expense in data.expenses) {
        database.execute(
          '''
          INSERT INTO expenses
            (id, month, category, name, date, amount, note, platform,
             product_id, product_name, ppn)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ''',
          [
            expense.id,
            expense.month,
            expense.category,
            expense.name,
            expense.date,
            expense.amount.round(),
            expense.note,
            expense.platform,
            expense.productId,
            expense.productName,
            expense.ppn ? 1 : 0,
          ],
        );
      }
      for (final owner in data.owners) {
        database.execute(
          'INSERT INTO owners (id, name, pct) VALUES (?, ?, ?)',
          [owner.id, owner.name, owner.pct],
        );
      }
      for (final entry in data.paid.entries) {
        database.execute('INSERT INTO paid (key, value) VALUES (?, ?)', [
          entry.key,
          entry.value ? 1 : 0,
        ]);
      }
      for (final entry in data.shopeeProductMappings.entries) {
        database.execute(
          'INSERT INTO shopee_product_mappings (key, value) VALUES (?, ?)',
          [entry.key, entry.value],
        );
      }
      database.execute('COMMIT');
    } catch (_) {
      database.execute('ROLLBACK');
      rethrow;
    }
  }

  static FinanceData? _readData(Database database) {
    final settingsRows = database.select('SELECT key, value FROM app_settings');
    if (settingsRows.isEmpty) return null;
    final settings = <String, dynamic>{
      for (final row in settingsRows) row['key'] as String: row['value'],
    };
    final profile = <String, dynamic>{
      'name': settings['businessName'],
      'tagline': settings['tagline'],
      if (settings.containsKey('logo')) 'logo': settings['logo'],
    };
    final financeSettings = <String, dynamic>{
      'zakatPct': settings['zakatPct'],
      'ppnPct': settings['ppnPct'],
      'targetRev': settings['targetRevenue'],
      'stockWarningThreshold': settings['stockWarningThreshold'],
      'owners': [
        for (final row in database.select('SELECT id, name, pct FROM owners'))
          {'id': row['id'], 'name': row['name'], 'pct': row['pct']},
      ],
      'shopeeProductMappings': {
        for (final row in database.select(
          'SELECT key, value FROM shopee_product_mappings',
        ))
          row['key'] as String: row['value'] as String,
      },
    };
    return FinanceData.fromJson({
      'profile': profile,
      'settings': financeSettings,
      'products': _readProducts(database),
      'materials': [
        for (final row in database.select('SELECT * FROM materials'))
          _materialRecord(row),
      ],
      'sales': [
        for (final row in database.select('SELECT * FROM sales'))
          {
            'id': row['id'],
            'date': row['date'],
            'platform': row['platform'],
            'productId': row['product_id'],
            'productName': row['product_name'],
            'qty': row['qty'],
            'orderNo': row['order_no'],
            'received': row['received'],
            'hpp': row['hpp'],
            'color': row['color'],
            'size': row['size'],
            'other': row['other'],
          },
      ],
      'expenses': [
        for (final row in database.select('SELECT * FROM expenses'))
          {
            'id': row['id'],
            'month': row['month'],
            'cat': row['category'],
            'name': row['name'],
            'date': row['date'],
            'amount': row['amount'],
            'note': row['note'],
            'platform': row['platform'],
            'productId': row['product_id'],
            'productName': row['product_name'],
            'ppn': row['ppn'] == 1,
          },
      ],
      'paid': {
        for (final row in database.select('SELECT key, value FROM paid'))
          row['key'] as String: row['value'] == 1,
      },
    });
  }

  static List<Map<String, Object?>> _readProducts(Database database) {
    final products = <Map<String, Object?>>[];
    for (final row in database.select('SELECT * FROM products')) {
      final productId = row['id'] as String;
      final attributes = database.select(
        '''
        SELECT kind, value FROM product_attributes
        WHERE product_id = ? ORDER BY position
        ''',
        [productId],
      );
      final stockEntries = database.select(
        '''
        SELECT id, date, qty, note, color FROM stock_entries
        WHERE product_id = ? ORDER BY position
        ''',
        [productId],
      );
      products.add({
        'id': productId,
        'name': row['name'],
        'img': row['image'],
        'materials': [
          for (final material in database.select(
            '''
            SELECT * FROM product_materials
            WHERE product_id = ? ORDER BY position
            ''',
            [productId],
          ))
            _materialRecord(material),
        ],
        'colors': [
          for (final attribute in attributes.where(
            (attribute) => attribute['kind'] == 'color',
          ))
            attribute['value'],
        ],
        'sizes': [
          for (final attribute in attributes.where(
            (attribute) => attribute['kind'] == 'size',
          ))
            attribute['value'],
        ],
        'variants': [
          for (final attribute in attributes.where(
            (attribute) => attribute['kind'] == 'variant',
          ))
            attribute['value'],
        ],
        if (row['has_stock'] == 1)
          'stock': {
            'log': [
              for (final entry in stockEntries)
                {
                  'id': entry['id'],
                  'date': entry['date'],
                  'qty': entry['qty'],
                  'note': entry['note'],
                  'color': entry['color'],
                },
            ],
          },
      });
    }
    return products;
  }

  static Map<String, Object?> _materialRecord(Row row) => {
    'id': row['id'],
    'name': row['name'],
    'qty': row['qty'],
    'unit': row['unit'],
    'price': row['price'],
    if (row['ref'] != null) 'ref': row['ref'],
    'category': row['category'],
  };

  static void _writeArchivedFiles(Database database, List<ArchivedFile> files) {
    for (final file in files) {
      database.execute(
        '''
        INSERT INTO archived_files
          (name, extension, content_type, source, imported_at, size_bytes, bytes)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          file.name,
          file.extension,
          file.contentType,
          file.source,
          file.importedAt,
          file.sizeBytes,
          file.bytes,
        ],
      );
    }
  }

  static List<ArchivedFile> _readArchivedFiles(Database database) {
    final rows = database.select('''
      SELECT name, extension, content_type, source, imported_at, size_bytes, bytes
      FROM archived_files ORDER BY id
      ''');
    return [
      for (final row in rows)
        ArchivedFile(
          name: row['name'] as String,
          extension: row['extension'] as String,
          contentType: row['content_type'] as String,
          source: row['source'] as String,
          importedAt: row['imported_at'] as String,
          sizeBytes: row['size_bytes'] as int,
          bytes: Uint8List.fromList(row['bytes'] as List<int>),
        ),
    ];
  }
}
