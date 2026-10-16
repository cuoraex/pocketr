import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketr/app_localization.dart';

void main() {
  group('localizeAppText', () {
    test('leaves Indonesian copy unchanged and translates English copy', () {
      expect(localizeAppText('Pengaturan', languageCode: 'id'), 'Pengaturan');
      expect(localizeAppText('Pengaturan', languageCode: 'en'), 'Settings');
    });

    test('translates About page content', () {
      expect(localizeAppText('Tentang', languageCode: 'en'), 'About');
      expect(
        localizeAppText('Tentang PocketR', languageCode: 'en'),
        'About PocketR',
      );
      expect(
        localizeAppText(
          'Kelola keuangan usaha dengan lebih rapi.',
          languageCode: 'en',
        ),
        'Keep your business finances organized.',
      );
      expect(localizeAppText('Dibuat oleh', languageCode: 'en'), 'Created by');
      expect(localizeAppText('Versi', languageCode: 'en'), 'Version');
    });

    test('translates dynamic app messages', () {
      expect(
        localizeAppText(
          '2 penjualan Shopee berhasil diimpor.',
          languageCode: 'en',
        ),
        '2 Shopee sales imported successfully.',
      );
      expect(
        localizeAppText(
          '2 penjualan manual berhasil diimpor. '
          '1 produk baru ditambahkan. 2 varian baru ditambahkan. '
          'HPP produk baru Rp0; lengkapi di katalog. 1 duplikat dilewati.',
          languageCode: 'en',
        ),
        '2 manual sales imported successfully. '
        '1 new product added. 2 new variants added. '
        'New products have Rp0 COGS; complete the COGS in the catalog. '
        '1 duplicates skipped.',
      );
      expect(
        localizeAppText(
          'Auto-save gagal: disk unavailable',
          languageCode: 'en',
        ),
        'Auto-save failed: disk unavailable',
      );
      expect(
        localizeAppText('Oktober 2025', languageCode: 'en'),
        'October 2025',
      );
      expect(
        localizeAppText('15 Oktober 2025', languageCode: 'en'),
        '15 October 2025',
      );
      expect(
        localizeAppText('Biaya gaji pegawai', languageCode: 'en'),
        'Staff pay expense',
      );
      expect(
        localizeAppText(
          'Klik untuk melihat detail: Omzet harian',
          languageCode: 'en',
        ),
        'Click to view details: Daily revenue',
      );
      expect(
        localizeAppText('Target omzet Oktober 2026', languageCode: 'en'),
        'Revenue target · October 2026',
      );
      expect(
        localizeAppText('Gagal: permission denied', languageCode: 'en'),
        'Error: permission denied',
      );
      expect(
        localizeAppText('Qty 2 · Tanpa satuan · Rp1.000', languageCode: 'en'),
        'Qty 2 · No unit · Rp1.000',
      );
      expect(
        localizeAppText(
          '1 pesanan · 2 pcs · ▲ 20% vs bulan lalu',
          languageCode: 'en',
        ),
        '1 order · 2 pcs · ▲ 20% vs. last month',
      );
      expect(
        localizeAppText(
          'File terakhir diperbarui pukul 10:30',
          languageCode: 'en',
        ),
        'Last file updated at 10:30',
      );
      expect(localizeAppText('Januari', languageCode: 'en'), 'January');
      expect(
        localizeAppText('Tambah ongkos jahit', languageCode: 'en'),
        'Add sewing cost',
      );
      expect(
        localizeAppText('Nama bisnis', languageCode: 'en'),
        'Business name',
      );
      expect(
        localizeAppText('1 pesanan · 2 pcs', languageCode: 'en'),
        '1 order · 2 pcs',
      );
      expect(
        localizeAppText(
          '2 penjualan Shopee berhasil diimpor. 3 produk baru dan 4 warna ditambahkan. Lengkapi HPP produk baru di katalog.',
          languageCode: 'en',
        ),
        '2 Shopee sales imported successfully. 3 new products and 4 colors were added. Complete their COGS in the catalog.',
      );
      expect(
        localizeAppText(
          '1 baris dengan semua qty dikembalikan akan diabaikan. Produk baru belum memiliki bahan/HPP. HPP penjualan awal Rp0; lengkapi HPP di katalog setelah impor.',
          languageCode: 'en',
        ),
        '1 row with all quantities returned will be skipped. New products do not have materials/COGS yet. Their initial sales use Rp0 COGS; complete the COGS in the catalog after importing.',
      );
    });

    test('translates generated owner names without changing custom names', () {
      expect(localizeOwnerName('Pemilik 1', languageCode: 'en'), 'Owner 1');
      expect(localizeOwnerName('Pemilik 1', languageCode: 'id'), 'Pemilik 1');
      expect(localizeOwnerName('Pengaturan', languageCode: 'en'), 'Pengaturan');
    });

    test('translates remaining expense and reset warning copy', () {
      expect(localizeAppText('Gaji', languageCode: 'en'), 'Staff pay');
      expect(localizeAppText('THR', languageCode: 'en'), 'Holiday bonus');
      expect(localizeAppText('bulan ini', languageCode: 'en'), 'this month');
      expect(
        localizeAppText('Tambah Iklan', languageCode: 'en'),
        'Add advertising expense',
      );
      expect(
        localizeAppText('Zakat mal · Oktober 2026', languageCode: 'en'),
        'Zakat on wealth · October 2026',
      );
      expect(
        localizeAppText(
          'Atur ulang akan menghapus ringkasan, penjualan, pengeluaran, produk, bahan baku/HPP, dan pengaturan secara permanen. Pastikan data yang masih dibutuhkan sudah dicadangkan.',
          languageCode: 'en',
        ),
        'Resetting will permanently delete your summary, sales, expenses, products, materials/COGS, and settings. Make sure to back up anything you still need.',
      );
    });

    test(
      'translates import detail labels while preserving imported values',
      () {
        expect(
          localizeShopeeImportDetail(
            'Pesanan SO-123 · status selesai\nTas Kanvas · Qty 2',
            languageCode: 'en',
          ),
          'Order SO-123 · status selesai\nTas Kanvas · Qty 2',
        );
        expect(
          localizeShopeeImportDetail(
            'Baris 8: varian "M" belum ada di katalog.',
            languageCode: 'en',
          ),
          'Row 8: variant “M” is not in the catalog.',
        );
        expect(
          localizeShopeeImportDetail(
            'Pesanan SO-123\nBaris 8: SKU produk kosong.',
            languageCode: 'en',
          ),
          'Order SO-123\nRow 8: product SKU is missing.',
        );
        expect(
          localizeAppText(
            'Tidak ada baris penjualan yang bisa ditambahkan. '
            '\n\nBaris 8: varian "M" belum ada di katalog.',
            languageCode: 'en',
          ),
          'No sales rows could be added. \n\nRow 8: variant “M” is not in the catalog.',
        );
      },
    );
  });

  testWidgets('AppText follows language changes without translating raw text', (
    tester,
  ) async {
    appLanguageCode.value = 'id';
    await tester.pumpWidget(
      ValueListenableBuilder<String>(
        valueListenable: appLanguageCode,
        builder: (context, languageCode, _) => MaterialApp(
          locale: Locale(languageCode),
          home: const Scaffold(
            body: Column(
              children: [AppText('Pengaturan'), AppText.raw('Pengaturan')],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Pengaturan'), findsNWidgets(2));
    appLanguageCode.value = 'en';
    await tester.pump();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Pengaturan'), findsOneWidget);
    appLanguageCode.value = 'id';
  });
}
