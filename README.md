# LINTAR Backup Data

Source code aplikasi Backup Data mahasiswa untuk lingkungan PUSDATIN Universitas Tarumanagara. Sistem terdiri atas portal ASP.NET Web Forms, PowerShell backup agent, dan objek kontrol Microsoft SQL Server.

## Struktur repository

- `web/backup_data`: portal dan API internal.
- `agent`: PowerShell agent, utilitas pemulihan file `.bak`, konfigurasi contoh, dan installer SQL Server Agent Job.
- `database`: installer gabungan dan skrip SQL modular.
- `tests`: pemeriksaan statis dan integrasi yang dijalankan secara eksplisit.
- `docs`: dokumentasi arsitektur dan panduan cutover.

## Keamanan

Repository ini tidak menyimpan API key aktif, konfigurasi server aktif, connection string berkredensial, log, file `.bak`, atau data mahasiswa. Salin salah satu `agent.config.*.example.json` menjadi file konfigurasi lokal dan isi nilainya pada server tujuan. Jangan commit file konfigurasi hasil salinan tersebut.

Koneksi database aktif portal diwarisi dari include LINTAR di luar folder aplikasi. File koneksi induk tersebut sengaja tidak disertakan.

## Instalasi ringkas

1. Review `database/install_backup_data_all.sql`, lalu uji pada lingkungan staging.
2. Salin `web/backup_data` ke aplikasi IIS yang sesuai.
3. Salin isi `agent` ke folder agent pada server backup.
4. Buat konfigurasi lokal dari berkas `.example.json`.
5. Daftarkan agent dan SQL Server Agent Job sesuai `agent/README.md`.
6. Jalankan pengujian pada `tests` sebelum cutover.

Menjalankan installer, agent, atau pengujian integrasi dapat mengakses database. Selalu gunakan salinan/staging dan persetujuan DBA terlebih dahulu.
