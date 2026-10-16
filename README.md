# PocketR — Catatan Keuangan

Aplikasi Flutter native untuk mencatat penjualan dan biaya bisnis, menghitung
HPP produk, laba bersih, zakat, dan pembagian profit owner. Tampilan memakai
gaya kaca biru yang responsif untuk layar ponsel maupun desktop.

## Fitur

- Ringkasan bulanan, grafik omzet harian, target omzet, marketplace, dan rekap tahunan.
- Pencatatan penjualan per tanggal, marketplace, produk/varian, kuantitas, pesanan,
  uang diterima, dan HPP yang tersimpan pada catatan.
- Impor penjualan CSV dengan validasi produk dan deteksi duplikat.
- Pencatatan biaya operasional, iklan dengan kalkulasi PPN, gaji, dan THR.
- Pengelolaan produk, varian, daftar bahan baku, dan perhitungan HPP.
- Pelacakan stok awal, penambahan/koreksi stok, stok minimum, dan pengurangan
  otomatis dari penjualan.
- Perhitungan laba bersih, zakat mal, bagian owner, dan status pembayaran owner.
- Penyimpanan otomatis pada perangkat, serta ekspor/pemulihan backup JSON.
- Auto-save backup berkala ke direktori lokal pilihan dengan interval 1–30 menit;
  satu file `pocketr-autosave.pcktr` ditimpa setiap kali.
- Bahasa antarmuka Indonesia dan English, dengan pilihan tersimpan di perangkat.

Data backup menggunakan bentuk JSON PocketR yang kompatibel dengan backup
aplikasi HTML. Dari aplikasi HTML, buat file backup JSON terlebih dahulu lalu
pulihkan file itu melalui menu **Backup / Pulihkan** di aplikasi Flutter.
Foto produk dan logo disimpan di perangkat ini dan tidak disertakan di file
backup `.pcktr`, sehingga file backup hanya berisi data aplikasi. Gambar
disimpan dalam format dan ukuran aslinya di penyimpanan internal aplikasi.
