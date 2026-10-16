# PocketR — Catatan Keuangan

Aplikasi Flutter native untuk mencatat penjualan dan biaya bisnis, menghitung
HPP produk, laba bersih, zakat, dan pembagian profit owner. Tampilan memakai
gaya kaca biru yang responsif untuk layar ponsel maupun desktop.

## Fitur

- Ringkasan bulanan, grafik omzet harian, target omzet, marketplace, dan rekap tahunan.
- Pencatatan penjualan per tanggal, marketplace, produk/varian, kuantitas, pesanan,
  uang diterima, dan HPP yang tersimpan pada catatan.
- Impor penjualan CSV XLS dengan validasi produk dan deteksi duplikat.
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

Detail Screenshoot
<img width="1919" height="1079" alt="5" src="https://github.com/user-attachments/assets/f4495636-b059-446d-ae0f-ae312349fc05" />
<img width="1919" height="1079" alt="4" src="https://github.com/user-attachments/assets/672c04c2-b8cb-4fd9-950e-bffbe08128db" />
<img width="1919" height="1079" alt="3" src="https://github.com/user-attachments/assets/71f62782-c3fa-43a8-a836-b3ebe3a11830" />
<img width="1907" height="1078" alt="2" src="https://github.com/user-attachments/assets/4f4814fb-b9d8-4c75-b835-23f9c9d892f7" />
<img width="1919" height="1079" alt="1" src="https://github.com/user-attachments/assets/32e2cffe-1703-43d4-94a4-a113d56af84f" />
