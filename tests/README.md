# Pengujian Otomatis Backup Data

Suite ini memeriksa source, konfigurasi, API, halaman web, penyederhanaan UI, ekspor PDF Laporan Ringkasan, Database Backup lokal, ukuran batch, pemisahan pesan, keamanan data sumber, dan pemulihan. Pengujian tidak membuat proses backup/pemulihan dan tidak mengubah data mahasiswa.

## Menjalankan pengujian lengkap

Jalankan pada komputer Database Backup:

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\BackupAgent\DeploymentPackage\tests\Run-BackupTests.ps1 -ApplicationRoot C:\inetpub\wwwroot\backup_data -ToolingRoot C:\BackupAgent\DeploymentPackage -ConfigPath C:\BackupAgent\agent.config.development.json -ReportPath C:\BackupAgent\TestResults\latest.json

Exit code 0 berarti seluruh tes wajib berhasil. Exit code 1 berarti ada tes gagal.

## Opsi

- -SkipApi: hanya tes source, konfigurasi, dan database lokal.
- -SkipLocalDatabase: tidak membuka koneksi SQL lokal.
- -TestBothProtocols: ikut memeriksa HTTP dan HTTPS.
- -ReportPath: menyimpan hasil JSON tanpa menyimpan API key atau password.

Tes heartbeat hanya memperbarui status kesehatan agent seperti heartbeat normal. Tidak ada job yang diklaim dan tidak ada tabel mahasiswa yang ditulis.

- memastikan seluruh SQL berada pada sumber modular dan setiap stored procedure hanya memiliki satu definisi.

## Hasil terakhir

Pengujian setelah penyederhanaan UI dengan `-SkipApi -SkipLocalDatabase` menghasilkan **28 PASS, 0 FAIL, dan 5 SKIP**. Pemeriksaan tambahan mencakup pembagian menu Staf, istilah Laporan Ringkasan dan Riwayat Proses, panel backup otomatis yang dapat dilipat, bantuan setiap mode, SweetAlert, guard server Staf/Manager, sifat read-only laporan, serta generator PDF tanpa akses database. Lima pengujian dilewati karena memerlukan API bertoken atau koneksi database dan baru dijalankan setelah ada persetujuan operasi data.
