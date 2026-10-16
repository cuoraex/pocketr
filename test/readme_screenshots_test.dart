@Tags(['readme-screenshots'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketr/data.dart';
import 'package:pocketr/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _windowManagerChannel = MethodChannel('window_manager');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture README screens', (tester) async {
    SharedPreferences.setMockInitialValues({
      'pocketr_v1': FinanceData(
        businessName: 'Kedai Contoh',
        tagline: 'Contoh usaha',
        targetRevenue: 1000000,
        products: [
          Product(
            id: 'p1',
            name: 'Tas Kanvas',
            materials: [
              MaterialCost(
                name: 'Kain kanvas',
                qty: 1.5,
                unit: 'meter',
                price: 35000,
              ),
              MaterialCost(
                name: 'Ongkos jahit',
                qty: 1,
                unit: 'pcs',
                price: 15000,
                category: MaterialCategory.ongkosJahit,
              ),
            ],
            colors: ['Hitam', 'Krem'],
            sizes: ['M', 'L'],
            stock: StockData(),
          ),
          Product(
            id: 'p2',
            name: 'Dompet Mini',
            materials: [
              MaterialCost(
                name: 'Kulit sintetis',
                qty: 1,
                unit: 'lembar',
                price: 12000,
              ),
            ],
          ),
        ],
        sales: [
          Sale(
            id: 's1',
            date: '2026-10-15',
            platform: 'shopee',
            productId: 'p1',
            productName: 'Tas Kanvas',
            qty: 2,
            orderNo: 'ORD-001',
            received: 150000,
            hpp: 50000,
            color: 'Hitam',
            size: 'M',
          ),
          Sale(
            id: 's2',
            date: '2026-10-14',
            platform: 'tokopedia',
            productId: 'p2',
            productName: 'Dompet Mini',
            qty: 1,
            orderNo: 'ORD-002',
            received: 45000,
            hpp: 12000,
          ),
        ],
        expenses: [
          Expense(
            id: 'e1',
            month: '2026-10',
            date: '2026-10-15',
            category: 'operasional',
            name: 'Kemasan',
            amount: 15000,
          ),
          Expense(
            id: 'e2',
            month: '2026-10',
            date: '2026-10-14',
            category: 'iklan',
            name: 'Iklan Shopee',
            amount: 10000,
            platform: 'shopee',
            ppn: true,
          ),
        ],
      ).toBackup(),
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_windowManagerChannel, (call) async {
          if (call.method == 'isMaximized') return false;
          return null;
        });
    tester.view
      ..physicalSize = const Size(1440, 1000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: const MaterialApp(home: FinanceHome()),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }

    Future<void> capture(String name) async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(boundaryKey),
      );
      final image = await boundary.toImage(pixelRatio: 1);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) throw StateError('Failed to encode screenshot $name');
      await tester.runAsync(() async {
        final directory = Directory('screenshots');
        await directory.create(recursive: true);
        await File('screenshots\\$name.png').writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
      });
    }

    await capture('dashboard');
    for (final entry in const [
      ('Penjualan', 'sales'),
      ('Pengeluaran', 'expenses'),
      ('Produk dan HPP', 'products'),
      ('Tentang', 'about'),
    ]) {
      final nav = find.text(entry.$1);
      await tester.tap(nav.first);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      await capture(entry.$2);
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_windowManagerChannel, null);
  });
}
