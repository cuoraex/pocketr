import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocketr/data.dart';

void main() {
  test('makeId returns unique IDs for consecutive calls', () {
    final ids = List.generate(100, (_) => makeId());

    expect(ids.toSet(), hasLength(100));
  });

  test('translates generic legacy owner names into Indonesian', () {
    expect(Owner.fromJson({'name': 'Owner 2'}).name, 'Pemilik 2');
    expect(Owner.fromJson({'name': 'Ayu'}).name, 'Ayu');
  });

  group('FinanceData', () {
    test('can omit profile and product images from saved data', () {
      final data = FinanceData(
        logo: 'data:image/png;base64,bG9nbw==',
        products: [
          Product(name: 'Tas', img: 'data:image/jpeg;base64,aW1hZ2U='),
        ],
        targetRevenue: 125000,
      );

      final compact = data.toBackup(includeImages: false);
      final full = data.toBackup();

      expect(compact, contains('"targetRev": 125000.0'));
      expect(compact, isNot(contains('base64')));
      expect(full, contains('base64'));
    });

    test(
      'aggregates product sales without merging missing or conflicting IDs',
      () {
        final totals = aggregateProductSales([
          Sale(
            id: 'saki',
            date: '2026-10-12',
            platform: 'shopee',
            productId: '',
            productName: 'Saki',
            qty: 3,
            received: 30000,
            hpp: 5000,
          ),
          Sale(
            id: 'tas',
            date: '2026-10-12',
            platform: 'shopee',
            productId: '',
            productName: 'Tas',
            qty: 2,
            received: 20000,
            hpp: 4000,
          ),
          Sale(
            id: 'dompet',
            date: '2026-10-12',
            platform: 'shopee',
            productId: 'reused-id',
            productName: 'Dompet',
            qty: 4,
            received: 40000,
            hpp: 3000,
          ),
          Sale(
            id: 'topi',
            date: '2026-10-12',
            platform: 'shopee',
            productId: 'reused-id',
            productName: 'Topi',
            qty: 1,
            received: 10000,
            hpp: 2000,
          ),
        ]);

        expect(totals.length, 4);
        expect(totals.values.map((total) => total.$1).toSet(), {
          'Saki',
          'Tas',
          'Dompet',
          'Topi',
        });
        expect(
          totals.values.fold<double>(0, (sum, total) => sum + total.$2),
          10,
        );
        expect(
          totals.values.fold<double>(0, (sum, total) => sum + total.$3),
          100000,
        );
      },
    );

    test(
      'aggregates product HPP using the current product cost when provided',
      () {
        final totals = aggregateProductSales([
          Sale(
            id: 'sale',
            date: '2026-10-12',
            platform: 'shopee',
            productId: 'product',
            productName: 'Tas',
            qty: 3,
            received: 30000,
            hpp: 100,
          ),
        ], hppForSale: (_) => 4500);

        expect(totals.values.single.$4, 13500);
      },
    );

    test('repairs missing and duplicate product IDs and relinks sales', () {
      final data = FinanceData.fromJson({
        'products': [
          {'id': '', 'name': 'Aika'},
          {'id': '', 'name': 'Bochi'},
          {'id': 'shared-id', 'name': 'Haru'},
          {'id': 'shared-id', 'name': 'Miki'},
        ],
        'sales': [
          {
            'id': 'sale-bochi',
            'date': '2026-10-12',
            'platform': 'shopee',
            'productId': '',
            'productName': 'Bochi',
          },
          {
            'id': 'sale-miki',
            'date': '2026-10-12',
            'platform': 'shopee',
            'productId': 'shared-id',
            'productName': 'Miki',
          },
        ],
      });

      expect(data.products.map((product) => product.id).toSet(), hasLength(4));
      final bochi = data.products.singleWhere(
        (product) => product.name == 'Bochi',
      );
      final miki = data.products.singleWhere(
        (product) => product.name == 'Miki',
      );
      expect(data.sales[0].productId, bochi.id);
      expect(data.sales[1].productId, miki.id);
    });

    test(
      'calculates monthly profit, advertising tax, zakat, and owner shares',
      () {
        final data = FinanceData(
          products: [Product(id: 'p1', name: 'Tas', materials: [])],
          sales: [
            Sale(
              id: 's1',
              date: '2026-10-12',
              platform: 'shopee',
              productId: 'p1',
              productName: 'Tas',
              qty: 2,
              received: 200000,
              hpp: 50000,
            ),
            Sale(
              id: 's2',
              date: '2026-09-12',
              platform: 'shopee',
              productId: 'p1',
              productName: 'Tas',
              qty: 1,
              received: 100000,
              hpp: 50000,
            ),
          ],
          expenses: [
            Expense(
              id: 'e1',
              month: '2026-10',
              category: 'operasional',
              name: 'Internet',
              amount: 10000,
            ),
            Expense(
              id: 'e2',
              month: '2026-10',
              category: 'iklan',
              name: 'Iklan',
              amount: 20000,
              ppn: true,
            ),
          ],
        );

        final result = data.summary('2026-10');
        expect(result.revenue, 200000);
        expect(result.hpp, 100000);
        expect(result.orders, 1);
        expect(result.ppn, 2200);
        expect(result.preTax, 67800);
        expect(result.zakat, 1695);
        expect(result.net, 66105);
        expect(data.summary('2026-09').revenue, 100000);
      },
    );

    test('reads and writes the existing HTML backup JSON shape', () {
      const backup = '''
      {
        "linkedMat": true,
        "profile": {"name":"PocketR","tagline":"Catatan Keuangan"},
        "products":[{"id":"p1","name":"Tas","img":"data:image/png;base64,aGVsbG8=","stock":{"min":2,"log":[{"id":"st1","date":"2026-10-12","qty":5,"note":"Stok awal"}]},"materials":[{"id":"m1","name":"Kain","qty":2,"unit":"meter","price":15000}],"colors":["Hitam"],"sizes":["L"]}],
        "materials":[],
        "sales":[{"id":"s1","date":"2026-10-12","platform":"shopee","productId":"p1","productName":"Tas","qty":1,"orderNo":"ABC","received":50000,"hpp":30000,"color":"Hitam","size":"L","variant":"Hitam / L"}],
        "expenses":[{"id":"e1","month":"2026-10","cat":"iklan","name":"Iklan","amount":10000,"platform":"shopee","productId":"p1","productName":"Tas","ppn":true}],
        "paid":{"2026-10:o1":true},
        "settings":{"zakatPct":2.5,"ppnPct":11,"targetRev":500000,"owners":[{"id":"o1","name":"Ayu","pct":100}],"shopeeProductMappings":{"rochinkutasransel":"p1"}}
      }
      ''';

      final data = FinanceData.fromBackup(backup);
      expect(data.businessName, 'PocketR');
      expect(data.products.single.hpp, 30000);
      expect(data.stockOf(data.products.single), 4);
      expect(data.products.single.img, 'data:image/png;base64,aGVsbG8=');
      expect(data.sales.single.variant, 'Hitam / L');
      expect(data.expenses.single.category, 'iklan');
      expect(data.paid['2026-10:o1'], isTrue);
      expect(data.targetRevenue, 500000);
      expect(data.shopeeProductMappings['rochinkutasransel'], 'p1');

      final restored = FinanceData.fromBackup(data.toBackup());
      expect(restored.sales.single.orderNo, 'ABC');
      expect(restored.expenses.single.ppn, isTrue);
      expect(restored.owners.single.name, 'Ayu');
      expect(restored.shopeeProductMappings['rochinkutasransel'], 'p1');
      expect(restored.products.single.stock?.log.single.note, 'Stok awal');
      expect(
        restored.products.single.toJson()['stock'],
        isNot(containsPair('min', anything)),
      );
    });

    test('calculates stock independently for each color', () {
      final product = Product(
        id: 'p1',
        name: 'Tas',
        colors: ['Hitam', 'Cokelat'],
        stock: StockData(
          log: [
            StockEntry(
              date: '2026-10-10',
              qty: 10,
              color: 'Hitam',
              note: 'Stok awal',
            ),
            StockEntry(
              date: '2026-10-10',
              qty: 6,
              color: 'Cokelat',
              note: 'Stok awal',
            ),
          ],
        ),
      );
      final data = FinanceData(
        products: [product],
        sales: [
          Sale(
            date: '2026-10-11',
            platform: 'shopee',
            productId: 'p1',
            productName: 'Tas',
            qty: 3,
            color: 'Hitam',
          ),
          Sale(
            date: '2026-10-12',
            platform: 'shopee',
            productId: 'p1',
            productName: 'Tas',
            qty: 2,
            color: 'Cokelat',
          ),
        ],
      );

      expect(data.stockByColor(product), {'Hitam': 7, 'Cokelat': 4});
      expect(data.stockOf(product), 11);
    });

    test(
      'persists THR expense date and defaults legacy expenses to month start',
      () {
        final expense = Expense(
          month: '2026-10',
          category: 'thr',
          name: 'Persiapan THR Lebaran',
          date: '2026-10-14',
        );

        final restored = Expense.fromJson(expense.toJson());
        final legacy = Expense.fromJson({
          'month': '2026-10',
          'cat': 'thr',
          'name': 'Persiapan THR Lebaran',
        });

        expect(restored.date, '2026-10-14');
        expect(legacy.date, '2026-10-01');
      },
    );

    test('keeps legacy stock entries in the uncolored group', () {
      final product = Product(
        id: 'p1',
        name: 'Tas',
        colors: ['Hitam'],
        stock: StockData(
          log: [StockEntry(date: '2026-10-10', qty: 8, note: 'Stok lama')],
        ),
      );
      final data = FinanceData(
        products: [product],
        sales: [
          Sale(
            date: '2026-10-11',
            platform: 'shopee',
            productId: 'p1',
            productName: 'Tas',
            qty: 2,
          ),
        ],
      );

      expect(data.stockByColor(product), {'Hitam': 0, '': 6});
      expect(data.stockOf(product), 6);
      expect(StockEntry.fromJson(product.stock!.log.single.toJson()).color, '');
    });

    test('supports moving the legacy balance into per-color opening stock', () {
      final product = Product(
        id: 'p1',
        name: 'Tas',
        colors: ['Hitam'],
        stock: StockData(
          log: [
            StockEntry(date: '2026-10-10', qty: 10, note: 'Stok lama'),
            StockEntry(
              date: '2026-10-12',
              qty: -7,
              note: 'Pindahkan saldo lama',
            ),
            StockEntry(
              date: '2026-10-12',
              qty: 8,
              color: 'Hitam',
              note: 'Stok awal Hitam',
            ),
          ],
        ),
      );
      final data = FinanceData(
        products: [product],
        sales: [
          Sale(
            date: '2026-10-11',
            platform: 'shopee',
            productId: 'p1',
            productName: 'Tas',
            qty: 3,
            color: 'Hitam',
          ),
          Sale(
            date: '2026-10-13',
            platform: 'shopee',
            productId: 'p1',
            productName: 'Tas',
            qty: 2,
            color: 'Hitam',
          ),
        ],
      );

      expect(data.stockByColor(product), {'Hitam': 6, '': 0});
      expect(data.stockOf(product), 6);
    });

    test('uses PocketR instead of the old Rochinku profile default', () {
      final data = FinanceData.fromJson({
        'profile': {'name': 'Rochinku'},
      });

      expect(data.businessName, 'PocketR');
    });

    test('rejects invalid files instead of restoring empty data', () {
      expect(
        () => FinanceData.fromBackup('{"settings":{}}'),
        throwsFormatException,
      );
    });

    test('reads the JSON archive envelope without losing finance data', () {
      final data = FinanceData(
        businessName: 'Toko Contoh',
        sales: [
          Sale(
            id: 's1',
            date: '2026-10-12',
            platform: 'shopee',
            productId: 'p1',
            productName: 'Tas',
            qty: 1,
            received: 50000,
            hpp: 20000,
          ),
        ],
      );
      final envelope = jsonEncode({
        'format': 'pocketr-backup',
        'version': 2,
        'data': data.toJson(),
        'files': [
          {'name': 'foto.jpg', 'bytes': 'AA=='},
        ],
      });

      final restored = FinanceData.fromBackup(envelope);
      expect(restored.businessName, 'Toko Contoh');
      expect(restored.sales.single.orderNo, '');
      expect(restored.sales.single.received, 50000);
    });

    test('continues to read legacy backup envelopes', () {
      final legacyEnvelope = jsonEncode({
        'format': 'rochinku-backup',
        'version': 2,
        'data': FinanceData(businessName: 'Toko Lama').toJson(),
      });

      final restored = FinanceData.fromBackup(legacyEnvelope);

      expect(restored.businessName, 'Toko Lama');
    });

    test('linked product materials use the current catalog price for HPP', () {
      final data = FinanceData(
        materials: [
          MaterialCost(id: 'fabric', name: 'Kain', price: 30000, unit: 'meter'),
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
                price: 100,
                ref: 'fabric',
              ),
            ],
          ),
        ],
      );

      expect(data.productHpp(data.products.single), 60000);
    });

    test(
      'sewing costs persist as a category and are included in product HPP',
      () {
        final data = FinanceData(
          materials: [
            MaterialCost(
              id: 'sewing',
              name: 'Jahit tas',
              category: MaterialCategory.ongkosJahit,
              price: 12000,
              unit: 'pcs',
            ),
          ],
          products: [
            Product(
              id: 'bag',
              name: 'Tas',
              materials: [
                MaterialCost(
                  id: 'sewing-use',
                  name: 'Jahit lama',
                  qty: 2,
                  ref: 'sewing',
                ),
              ],
            ),
          ],
        );

        final restored = FinanceData.fromJson(data.toJson());

        expect(data.productHpp(data.products.single), 24000);
        expect(
          restored.materials.single.category,
          MaterialCategory.ongkosJahit,
        );
        expect(
          restored
              .effectiveMaterial(restored.products.single.materials.single)
              .category,
          MaterialCategory.ongkosJahit,
        );
        expect(
          MaterialCost.fromJson({'name': 'Kain'}).category,
          MaterialCategory.bahanBaku,
        );
      },
    );

    test('stock is reduced by sales recorded on or after stock entry date', () {
      final product = Product(
        id: 'p1',
        name: 'Tas',
        stock: StockData(
          log: [
            StockEntry(date: '2026-10-10', qty: 10, note: 'Stok awal'),
            StockEntry(date: '2026-10-11', qty: 3, note: 'Produksi'),
          ],
        ),
      );
      final data = FinanceData(
        products: [product],
        sales: [
          Sale(
            date: '2026-10-09',
            platform: 'shopee',
            productId: 'p1',
            productName: 'Tas',
            qty: 4,
          ),
          Sale(
            date: '2026-10-12',
            platform: 'shopee',
            productId: 'p1',
            productName: 'Tas',
            qty: 5,
          ),
        ],
      );

      expect(data.stockOf(product), 8);
    });
  });

  group('formatting helpers', () {
    test('formats rupiah and month navigation', () {
      expect(formatMoney(1234567), 'Rp 1.234.567');
      expect(formatMoney(-1234), '-Rp 1.234');
      expect(shiftMonth('2026-01', -1), '2025-12');
      expect(monthLabel('2026-10'), 'Oktober 2026');
    });
  });

  test('parses quoted CSV fields and alternate delimiters', () {
    expect(
      parseCsvRows(
        'Tanggal,Produk,Catatan\r\n2026-10-12,"Tas, mini","Varian ""baru"""\r\n',
      ),
      [
        ['Tanggal', 'Produk', 'Catatan'],
        ['2026-10-12', 'Tas, mini', 'Varian "baru"'],
      ],
    );
    expect(parseCsvRows('Tanggal;Produk;Qty\n12/10/2026;Tas;2'), [
      ['Tanggal', 'Produk', 'Qty'],
      ['12/10/2026', 'Tas', '2'],
    ]);
  });
}
