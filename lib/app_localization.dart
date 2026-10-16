import 'package:flutter/material.dart' as material;

const appLanguagePreferenceKey = 'pocketr_language_v1';
final appLanguageCode = material.ValueNotifier<String>('id');

const _englishText = <String, String>{
  'Impor penjualan dari Excel': 'Import sales from Excel',
  'Template HPP': 'COGS template',
  'Impor HPP': 'Import COGS',
  'Simpan template impor HPP': 'Save COGS import template',
  'Pilih file impor HPP': 'Choose a COGS import file',
  'Template HPP berhasil disimpan.': 'COGS template saved.',
  'Template HPP gagal dibuat': 'Could not create the COGS template',
  'Konfirmasi impor HPP': 'Confirm COGS import',
  'Impor HPP berhasil': 'COGS import completed',
  'Impor HPP gagal': 'COGS import failed',
  'Pilih platform penjualan untuk impor. Saat ini format Shopee tersedia; platform lain akan menyusul karena format Excel berbeda.': 'Choose a platform to import from. Shopee is currently supported; other platforms will follow because their Excel formats differ.',
  'Gagal menyimpan data': 'Could not save data',
  'Bulan yang dipilih gagal disimpan': 'Could not save the selected month',
  'Nomor pesanan disalin.': 'Order number copied.',
  'Nomor pesanan gagal disalin': 'Could not copy the order number',
  'Cadangan berhasil disimpan.': 'Backup saved successfully.',
  'Cadangan gagal dibuat': 'Could not create backup',
  'Backup seluruh data': 'Back up all data',
  'Backup Settings': 'Back up now',
  'Restore Settings': 'Restore settings',
  'Simpan data, foto profil dan produk, serta berkas impor agar bisa dipulihkan di perangkat lain.': 'Save your data, profile and product photos, and imported files so they can be restored on another device.',
  'Simpan cadangan lengkap PocketR': 'Save complete PocketR backup',
  'Membuat cadangan lengkap PocketR...': 'Creating complete PocketR backup...',
  'Cadangan lengkap beserta foto berhasil disimpan.':
      'Complete backup with photos saved successfully.',
  'Cadangan lengkap gagal dibuat': 'Could not create the complete backup',
  'Auto-save gagal': 'Auto-save failed',
  'Gagal mengubah mode layar penuh': 'Could not change fullscreen mode',
  'Direktori auto-save gagal dipilih': 'Could not choose the auto-save folder',
  'Pengaturan auto-save gagal diubah': 'Could not update auto-save settings',
  'Interval auto-save gagal diubah': 'Could not change the auto-save interval',
  'Pemulihan cadangan gagal': 'Could not restore backup',
  'Berkas berhasil dibuka.': 'File opened.',
  'Pilih tepat 2 berkas: rincian pesanan selesai dan laporan saldo Shopee.': 'Select exactly 2 files: the completed order details and Shopee balance report.',
  'Berkas Excel Shopee gagal dipilih':
      'Could not select the Shopee Excel files',
  'Template Excel berhasil disimpan.': 'Excel template saved.',
  'Template Excel gagal dibuat': 'Could not create the Excel template',
  'Impor Excel': 'Import Excel',
  'Pilih template penjualan manual': 'Choose the manual sales template',
  'Konfirmasi impor manual': 'Confirm manual import',
  'Impor Excel manual gagal': 'Manual Excel import failed',
  'Katalog produk berhasil diperbarui.': 'Product catalog updated.',
  'Siap ditambahkan dari template manual.':
      'Ready to add from the manual template.',
  'Varian baru': 'New variants',
  'Varian dari Excel yang belum ada di katalog dan akan ditambahkan.': 'Variants from the Excel file that are not in the catalog and will be added.',
  'Data Excel berhasil diekspor.': 'Data exported to Excel.',
  'Ekspor Excel gagal': 'Could not export to Excel',
  'Impor Excel Shopee gagal': 'Shopee Excel import failed',
  'Semua data telah dihapus.': 'All data has been deleted.',
  'Foto profil tidak bisa dibuka': 'Could not open the profile photo',
  'Profil tidak bisa dibuka': 'Could not open the profile',
  'Ikuti Cuoraex': 'Follow Cuoraex',
  'Pilih media sosial untuk melihat profil':
      'Choose a social network to view the profile',
  'Check for update': 'Check for update',
  'Lihat versi terbaru di GitHub': 'View the latest version on GitHub',
  'Tautan repositori tidak bisa dibuka.': 'Could not open the repository link.',
  'Foto profil tidak bisa disimpan': 'Could not save the profile photo',
  'Foto profil tidak bisa disimpan: isi berkas tidak terbaca.':
      'Could not save the profile photo: the file could not be read.',
  'Profil berhasil diperbarui.': 'Profile updated.',
  'Data pemilik berhasil diperbarui.': 'Owner details updated.',
  'Tambahkan produk dulu di menu Produk dan HPP.':
      'Add a product first from Products & COGS.',
  'Pengeluaran tersimpan.': 'Expense saved.',
  'Atur ulang akan menghapus ringkasan, penjualan, pengeluaran, produk, bahan baku/HPP, dan pengaturan secara permanen. Pastikan data yang masih dibutuhkan sudah dicadangkan.': 'Resetting will permanently delete your summary, sales, expenses, products, materials/COGS, and settings. Make sure to back up anything you still need.',
  'Produk tersimpan.': 'Product saved.',
  'Foto produk tidak bisa dibuka': 'Could not open the product photo',
  'Produk stok tidak ditemukan.': 'Stocked product not found.',
  'Stok tersimpan.': 'Stock saved.',
  'Nama varian tidak boleh memakai tanda “/”.':
      'Variant names can’t contain a “/”.',
  'Produk baru belum memiliki bahan/HPP. HPP penjualan awal Rp0; lengkapi HPP di katalog setelah impor.': 'New products do not have materials/COGS yet. Their initial sales use Rp0 COGS; complete the COGS in the catalog after importing.',
  'Produk baru belum memiliki bahan/HPP. HPP penjualan awal Rp0; lengkapi HPP di katalog.': 'New products do not have materials/COGS yet. Initial sales use Rp0 COGS; complete the COGS in the catalog.',
  'Template input manual': 'Manual entry template',
  'Lembar pencatatan umum, bukan format ekspor platform.':
      'A general-purpose worksheet, not a marketplace export format.',
  'Tidak ada penjualan yang bisa diimpor': 'No sales to import',
  'Tidak ada data pada bagian ini.': 'Nothing to show here yet.',
  'Konfirmasi impor Shopee': 'Confirm Shopee import',
  'Siap ditambahkan dari berkas Shopee.': 'Ready to add from the Shopee file.',
  'Contoh data yang perlu diperiksa': 'A few rows to review',
  'Batal': 'Cancel',
  'Impor': 'Import',
  'Tutup': 'Close',
  'Tutup foto': 'Close photo',
  'Tutup kalkulator': 'Close calculator',
  'Lihat foto besar': 'View full-size image',
  'Klik untuk melihat daftar penjualan': 'Click to view the sales list',
  'Klik untuk melihat detail catatan impor': 'Click to view import notes',
  'Klik untuk menyalin nomor pesanan': 'Click to copy the order number',
  'Nomor pesanan kosong': 'No order number',
  'Halaman sebelumnya': 'Previous page',
  'Halaman berikutnya': 'Next page',
  'Bulan sebelumnya': 'Previous month',
  'Bulan berikutnya': 'Next month',
  'Hapus pencarian': 'Clear search',
  'Ada varian produk dengan stok 5 pcs atau kurang':
      'At least one product variant has 5 units or fewer in stock',
  'Contoh: 2,5': 'Example: 2.5',
  'Qty': 'Qty',
  'Varian lain': 'Other variants',
  'Pilih bahan tersimpan': 'Choose a saved material',
  'Tanpa satuan': 'No unit',
  'Nama pegawai': 'Employee name',
  'Nama biaya': 'Expense name',
  'Wajib diisi': 'Required',
  'Persiapan THR Lebaran': 'Holiday bonus reserve',
  'Keterangan': 'Description',
  'Penjualan siap diimpor': 'Sales ready to import',
  'Rincian setiap baris penjualan yang akan ditambahkan.':
      'Details of each sale that will be added.',
  'Warna baru': 'New colors',
  'Varian warna yang akan ditambahkan ke produk terkait.':
      'Color variants that will be added to the relevant products.',
  'Tidak ada di laporan saldo': 'Missing from the balance report',
  'Pesanan ditemukan di rincian pesanan selesai, tetapi tidak ada transaksi masuk yang cocok di laporan saldo.': 'The order appears in the completed orders file, but there is no matching incoming transaction in the balance report.',
  'Produk/varian dilewati': 'Skipped products/variants',
  'Pesanan yang tidak diimpor karena data produk, varian, tanggal, jumlah, atau subtotal bermasalah.': 'Orders skipped because product, variant, date, quantity, or subtotal details are invalid.',
  'Duplikat': 'Duplicates',
  'Baris berikut sudah tercatat sebelumnya dan tidak akan ditambahkan lagi.':
      'These rows are already on file and won’t be added again.',
  'Status belum selesai': 'Incomplete order status',
  'Baris ini diabaikan karena status pesanan belum selesai.':
      'This row was skipped because the order is not marked as complete.',
  'Catatan impor': 'Import notes',
  'Tambah biaya': 'Add expense',
  'Operasional lain': 'Other operating costs',
  'HPP produk terjual': 'COGS of goods sold',
  'Biaya iklan (+PPN)': 'Advertising costs (+VAT)',
  'Omzet (uang diterima)': 'Revenue (amount received)',
  'Total pengeluaran': 'Total expenses',
  'Operasional, iklan, gaji, THR, zakat':
      'Operations, ads, payroll, holiday bonus, zakat',
  'kuantitas bulan ini': 'quantity this month',
  'Biaya operasional': 'Operating costs',
  'operasional': 'Operating',
  'iklan': 'Advertising',
  'gaji pegawai': 'Staff pay',
  'thr lebaran': 'Holiday bonus',
  'pengeluaran': 'expenses',
  'lainnya': 'Other',
  '(termasuk gaji & THR)': '(including payroll and holiday bonuses)',
  'Belum ada bahan': 'No materials yet',
  'Belum ada data bulan ini': 'No data for this month yet',
  'Belum ada stok': 'No stock yet',
  'Catat penjualan di menu Penjualan.': 'Add sales from the Sales menu.',
  'Catat stok awal agar jumlah tersedia otomatis berkurang saat penjualan dicatat.': 'Record opening stock so the available quantity goes down automatically as sales are entered.',
  'Coba kata kunci pencarian yang lain.': 'Try a different search term.',
  'Coba lagi': 'Try again',
  'Format berkas Lazada berbeda dan dukungan impor sedang disiapkan.':
      'Lazada uses a different file format; import support is in the works.',
  'Format berkas Tokopedia berbeda dan dukungan impor sedang disiapkan.':
      'Tokopedia uses a different file format; import support is in the works.',
  'Format ekspor TikTok berbeda dan dukungan impor sedang disiapkan.':
      'TikTok uses a different export format; import support is in the works.',
  'Iklan untuk produk': 'Ad for product',
  'Impor Penjualan': 'Import Sales',
  'Masukkan bahan baku atau biaya produksi produk ini.':
      'Enter materials or production costs for this product.',
  'Omzet harian': 'Daily revenue',
  'Pembagian laba pemilik': 'Owner profit split',
  'Perhitungan laba': 'Profit calculation',
  'Pilih': 'Select',
  'Pilih 2 berkas': 'Select 2 files',
  'Pilih dua berkas ekspor: rincian pesanan selesai dan laporan saldo.': 'Choose two export files: completed order details and the balance report.',
  'Pilih produk untuk diedit': 'Choose a product to edit',
  'Produk terjual': 'Products sold',
  'Segera hadir': 'Coming soon',
  'Simpan & tambah lagi': 'Save & add another',
  'Tambah catatan pengeluaran menggunakan tombol di atas.':
      'Add an expense using the button above.',
  'Tambah pemilik': 'Add owner',
  'Tambah penjualan untuk mencatat pesanan di bulan ini.':
      'Add sales to record this month’s orders.',
  'Tambahkan produk untuk mengelola varian dan bahan.':
      'Add a product to manage its variants and materials.',
  'Tambahkan produk, lalu pilih dari daftar untuk mengelola varian dan bahan baku.': 'Add a product, then choose it from the list to manage its variants and materials.',
  'Tidak ada hasil pencarian': 'No search results',
  'Unduh template': 'Download template',
  'mis. Hitam, Cokelat': 'e.g. Black, Brown',
  'mis. L, XL atau 38, 40': 'e.g. L, XL or 38, 40',
  'mis. Tote Bag Kanvas': 'e.g. Canvas Tote Bag',
  'Konfirmasi': 'Confirm',
  'Profil bisnis': 'Business profile',
  'Pilih logo dari komputer': 'Choose a logo from your computer',
  'Hapus logo': 'Remove logo',
  'Pengaturan': 'Settings',
  'Tentang': 'About',
  'Tentang PocketR': 'About PocketR',
  'Kelola keuangan usaha dengan lebih rapi.':
      'Keep your business finances organized.',
  'PocketR membantu mencatat penjualan dan pengeluaran, menghitung HPP dan laba, serta memantau stok dan pembagian laba dalam satu aplikasi.': 'PocketR helps you track sales and expenses, calculate product costs and profit, and keep an eye on stock and profit sharing—all in one place.',
  'Fitur utama': 'Key features',
  'Informasi aplikasi': 'App information',
  'Ringkasan usaha': 'Business overview',
  'Pantau omzet, pengeluaran, laba bersih, dan performa usaha setiap bulan.':
      'See revenue, expenses, net profit, and monthly performance at a glance.',
  'Penjualan & HPP': 'Sales & COGS',
  'Catat transaksi dan hitung HPP per produk dengan lebih mudah.':
      'Record sales and calculate per-product COGS with ease.',
  'Stok & pengeluaran': 'Stock & expenses',
  'Pantau persediaan dan biaya usaha dalam satu alur.':
      'Keep stock levels and business costs in check.',
  'Data tetap di perangkat': 'Your data stays on your device',
  'Data disimpan secara lokal. Ekspor ke Excel atau buat cadangan saat dibutuhkan.': 'Your data is stored locally. Export to Excel or create a backup whenever you need it.',
  'Dibuat oleh': 'Created by',
  'Versi': 'Version',
  'Peringatan': 'Warning',
  'Auto-save lokal': 'Local auto-save',
  'Satu file cadangan akan ditimpa setiap interval.':
      'One backup file will be overwritten at each interval.',
  'Interval': 'Interval',
  'Direktori penyimpanan': 'Save folder',
  'Belum dipilih': 'Not selected',
  'File: pocketr-autosave.pcktr': 'File: pocketr-autosave.pcktr',
  '1 jam': '1 hr',
  '1 mnt': '1 min',
  '2 mnt': '2 min',
  '4 mnt': '4 min',
  '5 mnt': '5 min',
  '10 mnt': '10 min',
  '15 mnt': '15 min',
  '30 mnt': '30 min',
  'Pilih folder': 'Choose folder',
  'Pilih folder untuk memulai auto-save':
      'Choose a folder to start auto-saving',
  'Bahasa aplikasi': 'App language',
  'Pilih bahasa untuk seluruh tampilan aplikasi.':
      'Choose the language used throughout the app.',
  'Bahasa Indonesia': 'Indonesian',
  'Bahasa tidak berubah': 'Language was not changed',
  'Gagal memuat data': 'Could not load data',
  'Impor gagal': 'Import failed',
  'Gagal menyimpan bahasa': 'Could not save language',
  'Auto-save nonaktif': 'Auto-save is off',
  'Auto-save aktif · menunggu pencadangan pertama':
      'Auto-save is on · waiting for the first backup',
  'Ubah pemilik': 'Edit owners',
  'Atur nama dan porsi pembagian untuk setiap pemilik.':
      'Set each owner’s name and profit share.',
  'Nama pemilik': 'Owner name',
  'Persentase': 'Percentage',
  'Lunas': 'Paid',
  'Belum': 'Unpaid',
  'Total omzet': 'Total revenue',
  'Total': 'Total',
  'Nominal zakat terhitung': 'Calculated zakat',
  'Zakat dihitung dari laba sebelum zakat. Laba bersih adalah nilai setelah zakat dan menjadi dasar pembagian untuk pemilik.': 'Zakat is calculated from profit before zakat. Net profit is the amount after zakat and is used to calculate each owner’s share.',
  'Stok menipis': 'Low stock',
  'Nama': 'Name',
  'Satuan': 'Unit',
  'Harga': 'Price',
  'Harga satuan': 'Unit price',
  'List produk': 'Products',
  'Edit produk': 'Edit product',
  'HPP per pcs': 'COGS per piece',
  'Varian': 'Variants',
  'opsional, Warna / Ukuran': 'Optional: color / size',
  'Belum ada varian.': 'No variants yet.',
  'Rincian bahan baku': 'Material details',
  'Total HPP': 'Total COGS',
  'Bahan / biaya': 'Material / cost',
  'Catatan': 'Notes',
  'Subtotal': 'Subtotal',
  'Total stok': 'Total stock',
  'Varian produk': 'Product variants',
  'Contoh: Hitam, Cokelat. Hindari tanda garis miring.':
      'Example: Black, Brown. Avoid using slashes.',
  'Cadangkan data': 'Back up data',
  'Data tersimpan otomatis di perangkat ini. Buat cadangan berkala agar mudah dipindahkan atau dipulihkan.': 'Your data is saved on this device. Create backups regularly so it is easy to move or restore.',
  'Pulihkan dari cadangan': 'Restore from backup',
  'Hapus semua data': 'Delete all data',
  'Persentase zakat': 'Zakat rate',
  'Zakat (%)': 'Zakat (%)',
  'Masukkan nilai dari 0 sampai 100%.': 'Enter a value from 0 to 100%.',
  'TERSEDIA': 'AVAILABLE',
  'SEGERA HADIR': 'COMING SOON',
  'STOK': 'STOCK',
  'VARIAN': 'VARIANT',
  'Tanpa warna': 'No color',
  'Edit stok': 'Edit stock',
  'Aktifkan stok': 'Enable stock',
  'Tambah stok': 'Add stock',
  'Isi minimal satu jumlah stok.': 'Enter at least one stock quantity.',
  'Penjualan pada tanggal stok awal dan sesudahnya akan mengurangi jumlah tersedia.': 'Sales dated on or after the opening stock date reduce the available quantity.',
  'Kalkulator': 'Calculator',
  'Selesai': 'Done',
  'Total diterima · semua halaman': 'Total received · all pages',
  'Baris per halaman': 'Rows per page',
  'Produk': 'Products',
  'Nomor pesanan': 'Order number',
  'Pesanan': 'Orders',
  'Omzet': 'Revenue',
  'Tanggal dipesan': 'Order date',
  'Rincian': 'Details',
  'Uang diterima': 'Amount received',
  'Uang diterima (omzet)': 'Revenue received',
  'Nama bisnis': 'Business name',
  'Tulisan di bawah nama': 'Text below the business name',
  'Biaya': 'Expense',
  'Tanggal': 'Date',
  'Jumlah': 'Amount',
  'Ubah': 'Edit',
  'Hapus': 'Delete',
  'Hapus produk?': 'Delete product?',
  'Tambah penjualan': 'Add sale',
  'Ubah penjualan': 'Edit sale',
  'Tanpa ukuran': 'No size',
  'Tanpa varian': 'No variant',
  'Platform penjualan': 'Sales platform',
  'Produk baru': 'New product',
  'Warna': 'Color',
  'Ukuran': 'Size',
  'Varian opsional. Pisahkan beberapa warna atau ukuran dengan koma. Bisa diubah nanti di detail produk.': 'Variants are optional. Separate multiple colors or sizes with commas. You can edit them later in the product details.',
  'Isi bahan secara manual': 'Enter materials manually',
  'OPERASIONAL': 'OPERATING',
  'IKLAN': 'ADVERTISING',
  'GAJI PEGAWAI': 'STAFF PAY',
  'THR LEBARAN': 'HOLIDAY BONUS',
  'Operasional': 'Operating',
  'Iklan': 'Advertising',
  'Gaji pegawai': 'Staff pay',
  'THR Lebaran': 'Holiday bonus',
  'Lazada': 'Lazada',
  'Shopee': 'Shopee',
  'TikTok': 'TikTok',
  'TikTok Shop': 'TikTok Shop',
  'Tokopedia': 'Tokopedia',
  'Lainnya': 'Other',
  'Lain': 'Other',
  'Pengeluaran': 'Expenses',
  'Penjualan': 'Sales',
  'Ringkasan': 'Summary',
  'Produk dan HPP': 'Products & COGS',
  'Ekspor Excel': 'Export to Excel',
  'Simpan berkas': 'Save File',
  'Buka berkas': 'Open File',
  'Daftar bahan baku': 'Materials',
  'Daftar ongkos': 'Production costs',
  'Tambah': 'Add',
  'Cari produk / pesanan': 'Search products / orders',
  'Pilih bulan': 'Choose month',
  'Jenis biaya': 'Expense type',
  'Pengeluaran baru': 'New expense',
  'Tambah pengeluaran': 'Add expense',
  'Ubah pengeluaran': 'Edit expense',
  'Pilih produk': 'Choose product',
  'Tidak ada produk': 'No products found',
  'Tidak ada data': 'No data',
  'Belum ada data': 'No data yet',
  'Belum ada penjualan': 'No sales yet',
  'Belum ada pengeluaran': 'No expenses yet',
  'Belum ada produk': 'No products yet',
  'Semua': 'All',
  'Semua produk / umum': 'All products / general',
  'Tanggal penjualan': 'Sale date',
  'Jumlah terjual': 'Quantity sold',
  'Laba bersih': 'Net profit',
  'Target omzet': 'Revenue target',
  'Simpan perubahan': 'Save changes',
  'Simpan': 'Save',
  'Tambah produk': 'Add product',
  'Nama produk': 'Product name',
  'Cari': 'Search',
  'Kembali': 'Back',
  'Lanjut': 'Next',
  'Periode': 'Period',
  'Bulanan': 'Monthly',
  'Tahunan': 'Yearly',
  'Hari ini': 'Today',
  'Pilih tanggal': 'Choose date',
  'Pilih warna': 'Choose color',
  'Pilih ukuran': 'Choose size',
  'Detail produk': 'Product details',
  'Tambah bahan': 'Add material',
  'Tambah bahan baku': 'Add material',
  'Hapus bahan': 'Remove material',
  'Edit bahan': 'Edit material',
  'Harga jual': 'Sale price',
  'Modal': 'Cost',
  'Untung': 'Profit',
  'Laba': 'Profit',
  'Marketplace': 'Marketplace',
  'Saldo': 'Balance',
  'Stok': 'Stock',
  'Tanggal stok': 'Stock date',
  'Stok awal': 'Opening stock',
  'Peringatan stok minimum': 'Low-stock warning',
  'Penjualan tersimpan': 'Sales saved',
  'Pengeluaran tersimpan': 'Expense saved',
  'Data berhasil disimpan': 'Data saved',
  'Data berhasil dihapus': 'Data deleted',
  'Berkas berhasil disimpan': 'File saved',
  'Berkas berhasil dibuka': 'File opened',
  'Pilih berkas cadangan PocketR': 'Choose a PocketR backup file',
  'Simpan cadangan PocketR': 'Save PocketR backup',
  'Pilih dua berkas ekspor Shopee': 'Choose the two Shopee export files',
  'Simpan templat impor Excel': 'Save Excel import template',
  'Ekspor data PocketR ke Excel': 'Export PocketR data to Excel',
  'Pilih logo usaha': 'Choose a business logo',
  'Pilih gambar produk': 'Choose a product image',
  'Pilih kedua berkas ekspor Shopee.': 'Select both Shopee export files.',
  'Hapus semua data?': 'Delete all data?',
  'Produk, bahan, penjualan, pengeluaran, dan pengaturan akan dihapus permanen.': 'Products, materials, sales, expenses, and settings will be permanently deleted.',
  'Hapus penjualan?': 'Delete this sale?',
  'Catatan penjualan ini akan dihapus.': 'This sale will be deleted.',
  'Hapus data?': 'Delete this entry?',
  'Catatan ini akan dihapus.': 'This entry will be deleted.',
  'Hapus bahan baku?': 'Delete this material?',
  'Hapus rincian bahan?': 'Remove this material from the product?',
  'Pilih direktori auto-save PocketR': 'Choose a PocketR auto-save folder',
  'Bahasa aplikasi gagal disimpan': 'Could not save the app language',
  'Atur ulang semua data': 'Reset all data',
  'Tambah pengeluaran baru': 'Add an expense',
  'Tanggal transaksi': 'Transaction date',
  'Kuantitas': 'Quantity',
  'Porsi': 'Share',
  'Pilih platform penjualan': 'Choose a sales platform',
  'Pilih kategori': 'Choose a category',
  'Pilih metode': 'Choose a method',
  'Angka tidak valid.': 'Invalid number.',
  'Bahan baku': 'Raw materials',
  'Belum ada bahan baku': 'No raw materials yet',
  'Belum ada ongkos': 'No production costs yet',
  'Biaya rutin': 'Recurring costs',
  'biaya rutin': 'recurring costs',
  'bulan ini': 'this month',
  'platform': 'platforms',
  'Gaji + THR': 'Staff pay + holiday bonus',
  'pegawai & cadangan': 'staff and bonus reserves',
  'Gaji': 'Staff pay',
  'THR': 'Holiday bonus',
  'pesanan tercatat': 'orders recorded',
  'bahan': 'material',
  'ongkos jahit': 'sewing cost',
  'Bulan': 'Month',
  'Daftar berkas cadangan tidak valid.': 'Invalid backup file list.',
  'Bulan yang dipilih gagal disimpan.': 'Could not save the selected month.',
  'Direktori auto-save gagal disimpan.': 'Could not save the auto-save folder.',
  'Direktori auto-save tidak ditemukan.': 'Auto-save folder not found.',
  'Direktori yang dipilih tidak dapat diakses.':
      'The selected folder cannot be accessed.',
  'Ekspresi belum lengkap.': 'The expression is incomplete.',
  'Ekspresi tidak valid.': 'The expression is invalid.',
  'Hapus produk': 'Delete product',
  'Hapus gambar': 'Remove image',
  'Harga satuan (Rp)': 'Unit price (IDR)',
  'HPP penjualan awal Rp0; lengkapi HPP di katalog setelah impor.': 'Initial sales use Rp0 COGS; complete the COGS in the catalog after importing.',
  'Input belum lengkap': 'Some required fields are missing',
  'Interval auto-save gagal disimpan.':
      'Could not save the auto-save interval.',
  'Interval tidak tersedia.': 'This interval is unavailable.',
  'Isi berkas foto tidak terbaca.': 'Could not read the image file.',
  'Isi berkas tidak terbaca.': 'Could not read the file contents.',
  'Jumlah (Rp)': 'Amount (IDR)',
  'Biaya iklan sebelum PPN (Rp)': 'Advertising cost before VAT (IDR)',
  'Catatan (opsional)': 'Notes (optional)',
  'Jumlah tidak boleh 0': 'Quantity must be greater than zero',
  'Jumlah tidak boleh negatif': 'Quantity cannot be negative',
  'Kolom SKU atau SKU Induk tidak ditemukan di berkas rincian pesanan selesai.': 'Could not find the SKU or Parent SKU column in the completed order details.',
  'Kolom Waktu Pesanan Dibuat atau Waktu Pembayaran Dilakukan tidak ditemukan.':
      'Could not find the order creation or payment time column.',
  'Kurung belum ditutup.': 'A parenthesis is missing.',
  'Laba kotor': 'Gross profit',
  'Metadata berkas cadangan tidak valid.': 'Invalid backup file metadata.',
  'Migrasi penyimpanan lokal gagal.': 'Local data migration failed.',
  'Nama bahan / biaya': 'Material / cost name',
  'Nilai HPP tersimpan pada catatan penjualan ini.':
      'The COGS for this sale is saved in its record.',
  'Nomor pesanan (opsional)': 'Order number (optional)',
  'Pengaturan auto-save gagal disimpan.':
      'Could not save the auto-save settings.',
  'Bahasa aplikasi gagal disimpan.': 'Could not save the app language.',
  'Penjualan diperbarui.': 'Sale updated.',
  'Penjualan tersimpan.': 'Sale saved.',
  'Penyesuaian stok': 'Stock adjustment',
  'Penyimpanan lokal menolak data.': 'Local storage rejected the data.',
  'Persentase harus berupa angka antara 0 sampai 100.':
      'Enter a percentage between 0 and 100.',
  'Persentase zakat harus antara 0 dan 100%.':
      'The zakat rate must be between 0 and 100%.',
  'Pilih dari Bahan Baku': 'Choose from raw materials',
  'Qty harus lebih dari 0': 'Quantity must be greater than zero',
  'Ringkasan Bulanan': 'Monthly Summary',
  'Tambah manual': 'Add manually',
  'Tambahkan kain, resleting, atau komponen produk.':
      'Add fabric, zippers, or other product components.',
  'Tambahkan ongkos jahit untuk dipakai dalam HPP produk.':
      'Add sewing costs to include in the product COGS.',
  'Tidak ada ruang untuk membuka menu pagination.':
      'There is not enough room to open the pagination menu.',
  'Tidak bisa dibagi nol': 'Cannot divide by zero',
  'Tidak bisa dibagi nol.': 'Cannot divide by zero.',
  'Tidak bisa menentukan posisi menu pagination.':
      'Could not determine the pagination menu position.',
  'Tidak menemukan lembar laporan saldo Shopee.':
      'Could not find the Shopee balance report sheet.',
  'Tidak menemukan lembar rincian pesanan selesai Shopee.':
      'Could not find the completed Shopee order details sheet.',
  'Tidak terdefinisi': 'Undefined',
  'Total pembagian harus tepat 100% untuk menyimpan.':
      'Owner shares must add up to exactly 100% before saving.',
  'Uang diterima (Rp)': 'Amount received (IDR)',
  'Ubah nama': 'Rename',
  'Ubah produk': 'Edit product',
  'Ukuran (pisahkan dengan koma)': 'Sizes (separate with commas)',
  'Warna (pisahkan dengan koma)': 'Colors (separate with commas)',
  'Warna sudah dipilih': 'This color has already been selected',
  'Warna wajib diisi': 'Choose a color',
  'Hasil tidak valid.': 'The result is invalid.',
};

const _englishMonths = <String, String>{
  'Januari': 'January',
  'Februari': 'February',
  'Maret': 'March',
  'April': 'April',
  'Mei': 'May',
  'Juni': 'June',
  'Juli': 'July',
  'Agustus': 'August',
  'September': 'September',
  'Oktober': 'October',
  'November': 'November',
  'Desember': 'December',
};

String localizeAppText(String text, {String? languageCode}) {
  if ((languageCode ?? appLanguageCode.value) != 'en') return text;
  final translation = _englishText[text];
  if (translation != null) return translation;

  final expenseAction = RegExp(r'^(Tambah|Ubah) (.+)$').firstMatch(text);
  if (expenseAction != null) {
    final action = expenseAction.group(1) == 'Tambah' ? 'Add' : 'Edit';
    final category = expenseAction.group(2)!.toLowerCase();
    final englishCategory = switch (category) {
      'operasional' => 'operating expense',
      'iklan' => 'advertising expense',
      'gaji' || 'gaji pegawai' => 'staff expense',
      'thr' || 'thr lebaran' => 'holiday bonus',
      _ => localizeAppText(expenseAction.group(2)!, languageCode: 'en'),
    };
    return '$action $englishCategory';
  }

  final zakatTitle = RegExp(r'^Zakat mal · (.+)$').firstMatch(text);
  if (zakatTitle != null) {
    return 'Zakat on wealth · ${localizeAppText(zakatTitle.group(1)!, languageCode: 'en')}';
  }

  if (text.startsWith('• ')) {
    return '• ${localizeShopeeImportDetail(text.substring(2), languageCode: 'en')}';
  }

  final errorSeparator = text.indexOf(': ');
  if (errorSeparator > 0 && !text.contains('\n')) {
    final prefix = text.substring(0, errorSeparator);
    final translatedPrefix = localizeAppText(prefix, languageCode: 'en');
    if (translatedPrefix != prefix) {
      final detail = localizeAppText(
        text.substring(errorSeparator + 2),
        languageCode: 'en',
      );
      return '$translatedPrefix: $detail';
    }
  }

  final monthName = _englishMonths[text];
  if (monthName != null) return monthName;
  final fullDate = RegExp(
    r'^(\d{1,2}) (Januari|Februari|Maret|April|Mei|Juni|Juli|Agustus|September|Oktober|November|Desember) (\d{4})$',
  ).firstMatch(text);
  if (fullDate != null) {
    return '${fullDate.group(1)} ${_englishMonths[fullDate.group(2)]} ${fullDate.group(3)}';
  }
  final month = RegExp(
    r'^(Januari|Februari|Maret|April|Mei|Juni|Juli|Agustus|September|Oktober|November|Desember)( .+)$',
  ).firstMatch(text);
  if (month != null) {
    return '${_englishMonths[month.group(1)]}${month.group(2)}';
  }
  final dateLabel = RegExp(r'^Tgl (.+)$').firstMatch(text);
  if (dateLabel != null) return 'Date ${dateLabel.group(1)}';
  final from = RegExp(r'^dari (.+)$').firstMatch(text);
  if (from != null) return 'of ${from.group(1)}';
  final salesCount = RegExp(r'^(\d+) baris penjualan$').firstMatch(text);
  if (salesCount != null) {
    final noun = salesCount.group(1) == '1' ? 'sales row' : 'sales rows';
    return '${salesCount.group(1)} $noun';
  }
  final importedShopeeSales = RegExp(
    r'^(\d+) penjualan Shopee berhasil diimpor\.(.*)$',
  ).firstMatch(text);
  if (importedShopeeSales != null) {
    final details = importedShopeeSales.group(2)!.replaceAllMapped(
      RegExp(
        r' (\d+) produk baru dan (\d+) warna ditambahkan\. Lengkapi HPP produk baru di katalog\.',
      ),
      (match) {
        final products = match.group(1) == '1' ? 'new product' : 'new products';
        final colors = match.group(2) == '1' ? 'color' : 'colors';
        return ' ${match.group(1)} $products and ${match.group(2)} $colors were added. Complete their COGS in the catalog.';
      },
    );
    final count = importedShopeeSales.group(1)!;
    final noun = count == '1' ? 'sale' : 'sales';
    return '$count Shopee $noun imported successfully.$details';
  }
  final importedManualSales = RegExp(
    r'^(\d+) penjualan manual berhasil diimpor\.(.*)$',
  ).firstMatch(text);
  if (importedManualSales != null) {
    final count = importedManualSales.group(1)!;
    final noun = count == '1' ? 'manual sale' : 'manual sales';
    final details = importedManualSales
        .group(2)!
        .replaceAllMapped(
          RegExp(r' (\d+) produk baru ditambahkan\.'),
          (match) =>
              ' ${match.group(1)} ${match.group(1) == '1' ? 'new product' : 'new products'} added.',
        )
        .replaceAllMapped(
          RegExp(r' (\d+) varian baru ditambahkan\.'),
          (match) =>
              ' ${match.group(1)} ${match.group(1) == '1' ? 'new variant' : 'new variants'} added.',
        )
        .replaceAll(
          ' HPP produk baru Rp0; lengkapi di katalog.',
          ' New products have Rp0 COGS; complete the COGS in the catalog.',
        )
        .replaceAllMapped(
          RegExp(r' (\d+) duplikat dilewati\.'),
          (match) => ' ${match.group(1)} duplicates skipped.',
        );
    return '$count $noun imported successfully.'
        '$details';
  }
  final returnedRows = RegExp(
    r'^(\d+) baris dengan semua qty dikembalikan akan diabaikan\.$',
  ).firstMatch(text);
  if (returnedRows != null) {
    final noun = returnedRows.group(1) == '1' ? 'row' : 'rows';
    return '${returnedRows.group(1)} $noun with all quantities returned will be skipped.';
  }
  final materialCount = RegExp(r'^(\d+) bahan · terjual ([\d.,]+) pcs$')
      .firstMatch(text);
  if (materialCount != null) {
    final noun = materialCount.group(1) == '1' ? 'material' : 'materials';
    return '${materialCount.group(1)} $noun · ${materialCount.group(2)} pcs sold';
  }
  final piecesSold = RegExp(r'^([\d.,]+) pcs terjual$').firstMatch(text);
  if (piecesSold != null) return '${piecesSold.group(1)} pcs sold';
  final stockCount = RegExp(r'^([\d.,]+) pcs$').firstMatch(text);
  if (stockCount != null) return '${stockCount.group(1)} pcs';
  final pageCount = RegExp(r'^Halaman (\d+) dari (\d+)$').firstMatch(text);
  if (pageCount != null) {
    return 'Page ${pageCount.group(1)} of ${pageCount.group(2)}';
  }
  final cogs = RegExp(r'^HPP (.+)$').firstMatch(text);
  if (cogs != null) return 'COGS ${cogs.group(1)}';
  final revenue = RegExp(r'^Omzet (.+)$').firstMatch(text);
  if (revenue != null) return 'Revenue ${revenue.group(1)}';
  final sold = RegExp(r'^Penjualan (.+) pcs$').firstMatch(text);
  if (sold != null) return 'Sales: ${sold.group(1)} pcs';
  final progress = RegExp(r'^(\d+)% tercapai$').firstMatch(text);
  if (progress != null) return '${progress.group(1)}% reached';
  final orderRange = RegExp(r'^(.+) dari (.+)$').firstMatch(text);
  if (orderRange != null && text.contains('–')) {
    return '${orderRange.group(1)} of ${orderRange.group(2)}';
  }
  final ownerShare = RegExp(r'^(.+) · ([\d.,]+)%$').firstMatch(text);
  if (ownerShare != null) {
    return '${ownerShare.group(1)} · ${ownerShare.group(2)}%';
  }
  final paidTotal = RegExp(r'^Total dibayar: (.+)$').firstMatch(text);
  if (paidTotal != null) return 'Total paid: ${paidTotal.group(1)}';
  final vat = RegExp(r'^Tambahkan PPN (.+)%$').firstMatch(text);
  if (vat != null) return 'Add VAT at ${vat.group(1)}%';
  final expense = RegExp(r'^Biaya (.+)$').firstMatch(text);
  if (expense != null) {
    final name = expense.group(1)!;
    final titleCase = name.isEmpty
        ? name
        : '${name[0].toUpperCase()}${name.substring(1)}';
    final category =
        _englishText[name] ??
        _englishText[titleCase] ??
        _englishText[name.toUpperCase()];
    return '${category ?? 'Other'} expense';
  }
  final deletedProduct = RegExp(
    r'^“(.+)” akan dihapus\. Riwayat penjualan produk tetap tersimpan\.$',
  ).firstMatch(text);
  if (deletedProduct != null) {
    return '“${deletedProduct.group(1)}” will be deleted. Its sales history will remain.';
  }
  final dataLoadError = RegExp(r'^Data tidak bisa dibuka: (.+)$')
      .firstMatch(text);
  if (dataLoadError != null) {
    return 'Could not open data: ${dataLoadError.group(1)}';
  }
  final detailTooltip = RegExp(r'^Klik untuk melihat detail: (.+)$')
      .firstMatch(text);
  if (detailTooltip != null) {
    return 'Click to view details: ${localizeAppText(detailTooltip.group(1)!, languageCode: 'en')}';
  }
  final removeOwnerTooltip = RegExp(r'^Hapus pemilik (\d+)$').firstMatch(text);
  if (removeOwnerTooltip != null) {
    return 'Remove owner ${removeOwnerTooltip.group(1)}';
  }
  final noRows = RegExp(
    r'^Tidak ada baris penjualan yang bisa ditambahkan\.([\s\S]*)$',
  ).firstMatch(text);
  if (noRows != null) {
    final details = noRows
        .group(1)!
        .replaceAllMapped(
          RegExp(
            r'(\d+) produk baru dan (\d+) warna dari Excel tetap disimpan\. HPP produk baru Rp0; lengkapi di katalog\.',
          ),
          (match) {
            final products = match.group(1) == '1'
                ? 'new product'
                : 'new products';
            final colors = match.group(2) == '1' ? 'color' : 'colors';
            return '${match.group(1)} $products and ${match.group(2)} $colors from Excel were saved. Their COGS is Rp0; complete them in the catalog.';
          },
        )
        .replaceAllMapped(
          RegExp(r'(\d+) pesanan belum ditemukan di laporan saldo\.'),
          (match) =>
              '${match.group(1)} orders were not found in the balance report.',
        )
        .replaceAllMapped(
          RegExp(r'(\d+) pesanan dilewati karena data produk/varian\.'),
          (match) =>
              '${match.group(1)} orders were skipped because product or variant details were missing.',
        )
        .replaceAllMapped(
          RegExp(r'(\d+) duplikat dilewati\.'),
          (match) => '${match.group(1)} duplicates were skipped.',
        );
    final translatedDetails = details
        .split('\n')
        .map((line) {
          if (line.startsWith('Baris ') || line.startsWith('Pesanan ')) {
            return localizeShopeeImportDetail(line, languageCode: 'en');
          }
          return line;
        })
        .join('\n');
    return 'No sales rows could be added.$translatedDetails';
  }
  final rate = RegExp(r'^Total persentase (.+)% \(idealnya 100%\)\.$')
      .firstMatch(text);
  if (rate != null) return 'Total share: ${rate.group(1)}% (ideally 100%).';
  final share = RegExp(
    r'^Total pembagian (.+)% · (sudah 100%|harus 100% untuk menyimpan)$',
  ).firstMatch(text);
  if (share != null) {
    final status = share.group(2) == 'sudah 100%'
        ? 'exactly 100%'
        : 'must equal 100% to save';
    return 'Total share: ${share.group(1)}% · $status';
  }
  final autoSaveFailure = RegExp(r'^Gagal: (.+)$').firstMatch(text);
  if (autoSaveFailure != null) {
    return 'Error: ${autoSaveFailure.group(1)}';
  }
  final lastFileUpdate = RegExp(r'^File terakhir diperbarui pukul (.+)$')
      .firstMatch(text);
  if (lastFileUpdate != null) {
    return 'Last file updated at ${lastFileUpdate.group(1)}';
  }
  final materialDetails = RegExp(r'^Qty (.+) · (.+) · (.+)$').firstMatch(text);
  if (materialDetails != null) {
    final unit = materialDetails.group(2) == 'Tanpa satuan'
        ? 'No unit'
        : materialDetails.group(2);
    return 'Qty ${materialDetails.group(1)} · $unit · ${materialDetails.group(3)}';
  }
  final monthlyOrders = RegExp(
    r'^(\d+) pesanan · ([\d.,]+) pcs(?: · ([▲▼]) ([\d.,]+)% vs bulan lalu)?$',
  ).firstMatch(text);
  if (monthlyOrders != null) {
    final noun = monthlyOrders.group(1) == '1' ? 'order' : 'orders';
    final growth = monthlyOrders.group(3) == null
        ? ''
        : ' · ${monthlyOrders.group(3)} ${monthlyOrders.group(4)}% vs. last month';
    return '${monthlyOrders.group(1)} $noun · ${monthlyOrders.group(2)} pcs$growth';
  }
  final margin = RegExp(r'^Margin (.+)%$').firstMatch(text);
  if (margin != null) return 'Profit margin: ${margin.group(1)}%';
  final revenuePercentage = RegExp(r'^([\d.,]+)% dari omzet$').firstMatch(text);
  if (revenuePercentage != null) {
    return '${revenuePercentage.group(1)}% of revenue';
  }
  final revenueTarget = RegExp(r'^Target omzet (.+)$').firstMatch(text);
  if (revenueTarget != null) {
    return 'Revenue target · ${localizeAppText(revenueTarget.group(1)!, languageCode: 'en')}';
  }
  final advertisingVat = RegExp(r'^PPN iklan (.+)%$').firstMatch(text);
  if (advertisingVat != null) {
    return 'Ad VAT ${advertisingVat.group(1)}%';
  }
  final annualProfit = RegExp(r'^Laba tahunan · (.+)$').firstMatch(text);
  if (annualProfit != null) {
    return 'Annual profit · ${localizeAppText(annualProfit.group(1)!, languageCode: 'en')}';
  }
  final salesList = RegExp(r'^Daftar penjualan · (.+)$').firstMatch(text);
  if (salesList != null) {
    return 'Sales list · ${localizeAppText(salesList.group(1)!, languageCode: 'en')}';
  }
  final zakatMonth = RegExp(r'^Zakat mal · (.+)$').firstMatch(text);
  if (zakatMonth != null) {
    return 'Zakat · ${localizeAppText(zakatMonth.group(1)!, languageCode: 'en')}';
  }
  final period = RegExp(r'^Periode (.+)\.$').firstMatch(text);
  if (period != null) {
    return 'Period ${localizeAppText(period.group(1)!, languageCode: 'en')}.';
  }
  final rowsPerPage = RegExp(r'^(\d+) baris$').firstMatch(text);
  if (rowsPerPage != null) return '${rowsPerPage.group(1)} rows';
  final expenseTitle = RegExp(r'^(Tambah|Ubah) (.+)$').firstMatch(text);
  if (expenseTitle != null) {
    final verb = expenseTitle.group(1) == 'Tambah' ? 'Add' : 'Edit';
    final noun = localizeAppText(expenseTitle.group(2)!, languageCode: 'en');
    return '$verb $noun';
  }
  final emptyOwnerName = RegExp(r'^Nama pemilik (\d+) tidak boleh kosong\.$')
      .firstMatch(text);
  if (emptyOwnerName != null) {
    return 'Owner ${emptyOwnerName.group(1)} needs a name.';
  }
  final unavailableProduct = RegExp(
    r'^Produk [“"](.+)[”"] tidak lagi tersedia\.$',
  ).firstMatch(text);
  if (unavailableProduct != null) {
    return 'Product “${unavailableProduct.group(1)}” is no longer available.';
  }
  final unreadableFile = RegExp(r'^Isi berkas "(.+)" tidak terbaca\.$')
      .firstMatch(text);
  if (unreadableFile != null) {
    return 'Could not read the contents of “${unreadableFile.group(1)}”.';
  }
  final localizedImportNotes = text
      .replaceAllMapped(
        RegExp(r'(\d+) baris dengan semua qty dikembalikan akan diabaikan\.'),
        (match) {
          final noun = match.group(1) == '1' ? 'row' : 'rows';
          return '${match.group(1)} $noun with all quantities returned will be skipped.';
        },
      )
      .replaceAll(
        'Produk baru belum memiliki bahan/HPP. HPP penjualan awal Rp0; lengkapi HPP di katalog setelah impor.',
        'New products do not have materials/COGS yet. Their initial sales use Rp0 COGS; complete the COGS in the catalog after importing.',
      );
  if (localizedImportNotes != text) return localizedImportNotes;
  return text;
}

String localizeOwnerName(String name, {String? languageCode}) {
  if ((languageCode ?? appLanguageCode.value) != 'en') return name;
  final generatedName = RegExp(r'^Pemilik (\d+)$').firstMatch(name);
  if (generatedName == null) return name;
  return 'Owner ${generatedName.group(1)}';
}

String localizeShopeeImportDetail(String text, {String? languageCode}) {
  if ((languageCode ?? appLanguageCode.value) != 'en') return text;

  final statusRow = RegExp(r'^Pesanan (.+) · status (.+)\n(.+) · Qty (.+)$')
      .firstMatch(text);
  if (statusRow != null) {
    final status = statusRow.group(2) == '(kosong)'
        ? '(blank)'
        : statusRow.group(2);
    return 'Order ${statusRow.group(1)} · status $status\n${statusRow.group(3)} · Qty ${statusRow.group(4)}';
  }
  final returnedOrder = RegExp(
    r'^Pesanan (.+)\n(.+) · Terjual (.+) · Dikembalikan (.+)$',
  ).firstMatch(text);
  if (returnedOrder != null) {
    return 'Order ${returnedOrder.group(1)}\n${returnedOrder.group(2)} · Sold ${returnedOrder.group(3)} · Returned ${returnedOrder.group(4)}';
  }
  final invalidRow = RegExp(r'^Baris (\d+): (.+)\.$').firstMatch(text);
  if (invalidRow != null) {
    final row = invalidRow.group(1);
    final problem = invalidRow.group(2)!;
    final missingVariant = RegExp(r'^varian "(.+)" belum ada di katalog$')
        .firstMatch(problem);
    if (missingVariant != null) {
      return 'Row $row: variant “${missingVariant.group(1)}” is not in the catalog.';
    }
    final invalidSku = RegExp(r'^SKU "(.+)" tidak bisa ditambahkan ke katalog$')
        .firstMatch(problem);
    if (invalidSku != null) {
      return 'Row $row: SKU “${invalidSku.group(1)}” could not be added to the catalog.';
    }
    final translatedProblem = switch (problem) {
      'tanggal selesai tidak valid' => 'invalid completion date',
      'jumlah tidak valid' => 'invalid quantity',
      'SKU produk kosong' => 'product SKU is missing',
      _ => null,
    };
    if (translatedProblem != null) {
      return 'Row $row: $translatedProblem.';
    }
  }
  final invalidSubtotal = RegExp(
    r'^Pesanan (.+): subtotal produk tidak valid\.$',
  ).firstMatch(text);
  if (invalidSubtotal != null) {
    return 'Order ${invalidSubtotal.group(1)}: invalid product subtotal.';
  }
  if (text.startsWith('Pesanan ')) {
    final lines = text.split('\n');
    lines[0] = lines[0].replaceFirst('Pesanan ', 'Order ');
    for (var index = 1; index < lines.length; index++) {
      if (lines[index].startsWith('Baris ')) {
        lines[index] = localizeShopeeImportDetail(
          lines[index],
          languageCode: 'en',
        );
      }
    }
    return lines.join('\n');
  }
  return text;
}

class AppText extends material.StatelessWidget {
  const AppText(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.softWrap,
    this.overflow,
    this.translate = true,
  }) : textSpan = null;

  const AppText.rich(
    this.textSpan, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.softWrap,
    this.overflow,
    this.translate = true,
  }) : data = null;

  const AppText.raw(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.softWrap,
    this.overflow,
  }) : textSpan = null,
       translate = false;

  final String? data;
  final material.InlineSpan? textSpan;
  final material.TextStyle? style;
  final material.TextAlign? textAlign;
  final int? maxLines;
  final bool? softWrap;
  final material.TextOverflow? overflow;
  final bool translate;

  @override
  material.Widget build(material.BuildContext context) =>
      material.ValueListenableBuilder<String>(
        valueListenable: appLanguageCode,
        builder: (context, code, _) => _buildForLanguage(code),
      );

  material.Widget _buildForLanguage(String code) {
    final renderedText = data == null
        ? null
        : translate
        ? localizeAppText(data!, languageCode: code)
        : data;
    final renderedSpan = textSpan == null || !translate
        ? textSpan
        : _translateSpan(textSpan!, code);
    if (renderedText != null) {
      return material.Text(
        renderedText,
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
        softWrap: softWrap,
        overflow: overflow,
      );
    }
    return material.Text.rich(
      renderedSpan!,
      style: style,
      textAlign: textAlign,
      maxLines: maxLines,
      softWrap: softWrap,
      overflow: overflow,
    );
  }
}

material.InlineSpan _translateSpan(
  material.InlineSpan span,
  String languageCode,
) {
  if (span is! material.TextSpan) return span;
  return material.TextSpan(
    text: span.text == null
        ? null
        : localizeAppText(span.text!, languageCode: languageCode),
    children: span.children
        ?.map((child) => _translateSpan(child, languageCode))
        .toList(growable: false),
    style: span.style,
    recognizer: span.recognizer,
    mouseCursor: span.mouseCursor,
    onEnter: span.onEnter,
    onExit: span.onExit,
    semanticsLabel: span.semanticsLabel == null
        ? null
        : localizeAppText(span.semanticsLabel!, languageCode: languageCode),
    locale: span.locale,
    spellOut: span.spellOut,
  );
}
