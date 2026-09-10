# Pengujian Otomatis Backup Data

Suite ini memeriksa source, konfigurasi, API, halaman web, penyederhanaan UI, ekspor PDF Laporan, Database Backup lokal, ukuran batch, pemisahan pesan, keamanan data sumber, dan pemulihan. Pengujian tidak membuat proses backup/pemulihan dan tidak mengubah data mahasiswa.

## Menjalankan pemeriksaan statis yang aman dari repository

Jalankan dari root repository. Perintah ini tidak membuka API atau database:

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-BackupTests.ps1 -SkipApi -SkipLocalDatabase -ReportPath .\TestResults\latest.json

Exit code 0 berarti seluruh tes wajib berhasil. Exit code 1 berarti ada tes gagal.

## Opsi

- -SkipApi: hanya tes source, konfigurasi, dan database lokal.
- -SkipLocalDatabase: tidak membuka koneksi SQL lokal.
- -TestBothProtocols: ikut memeriksa HTTP dan HTTPS.
- -ReportPath: menyimpan hasil JSON tanpa menyimpan API key atau password.

Tanpa opsi `-SkipApi`, tes heartbeat memperbarui status kesehatan agent seperti heartbeat normal. Gunakan mode tersebut hanya pada lingkungan yang memang diizinkan. Tidak ada job yang diklaim dan tidak ada tabel mahasiswa yang ditulis.

- memastikan seluruh SQL berada pada sumber modular dan setiap stored procedure hanya memiliki satu definisi.

## Hasil terakhir

Pengujian statis mencakup pusat pemantauan Dashboard, kesiapan Database Backup, filter Riwayat Proses, metadata ekspor, perlindungan akun yang sedang login, metrik ringkas Laporan, penghapusan Backup per NIM, guard server Staf/Manager, sifat read-only laporan, serta generator PDF tanpa akses database. Path pengujian mengikuti struktur repository `web/backup_data`, `database/modular`, dan `database/install_*`.
