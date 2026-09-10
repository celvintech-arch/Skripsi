# Dokumentasi Sistem Backup Data Mahasiswa LINTAR

Dokumen ini menjelaskan implementasi modul `backup_data` yang terpasang saat ini serta rencana pengembangan berikutnya. Sistem menyalin data akademik dari database aktif ke database backup. Operasi backup tidak menghapus data pada database aktif.

## 1. Ruang Lingkup

Sistem menyediakan:

- backup manual berdasarkan satu Tahun Akademik, rentang Tahun Akademik, batas Tahun Akademik, atau NIM;
- backup otomatis berdasarkan jadwal;
- pemilihan satu database sumber `dec_dummy`;
- pembaruan salinan lama dengan upsert;
- antrean, heartbeat, progres, log, statistik, dan riwayat;
- pemulihan berdasarkan Tahun Akademik atau NIM;
- ekspor database backup ke berkas SQL Server `.bak`;
- dua peran pengguna: Staf mempunyai akses penuh, sedangkan Manager hanya mempunyai akses Dashboard dan Laporan.

Status mahasiswa aktif atau nonaktif tidak digunakan sebagai filter.

Kode peran dan Laporan telah diimplementasikan, migrasi peran telah dipasang oleh pengelola, dan source telah dipindahkan ke website aktif pada 7 September 2026.

## 2. Database dan Tabel

Database aktif bernama `dec_dummy`. Portal dan API membaca langsung:

| Tabel | Data |
|---|---|
| `dbo.tbio01` | Biodata mahasiswa |
| `dbo.treg` | Registrasi mahasiswa |
| `dbo.tkrs06` | Kartu Rencana Studi |
| `dbo.t_absensi14` | Presensi mahasiswa |

Database backup bernama `dec_dummy_backup` pada node backup dan menggunakan tabel:

| Tabel backup | Tabel sumber |
|---|---|
| `dbo.tbio01_backup` | `dbo.tbio01` |
| `dbo.treg_backup` | `dbo.treg` |
| `dbo.tkrs06_backup` | `dbo.tkrs06` |
| `dbo.t_absensi14_backup` | `dbo.t_absensi14` |

Tabel kontrol `Backup*` berada pada `dec_dummy`. Tidak ada tabel sumber pengganti dan web tidak membuka koneksi langsung ke `dec_dummy_backup`.

## 3. Sumber Koneksi Database Aktif

Portal dan API menggunakan `/con_ascx2022/condecdummy.ascx`. File tersebut tetap menjadi satu-satunya sumber alamat server, nama database, pengguna, dan kata sandi database aktif. Modul hanya mengubah format connection string OLE DB menjadi SqlClient di memori. `web.config` modul tidak menyimpan connection string atau kredensial database lain. File `condecdummy.ascx` tidak diubah oleh refaktor ini.

## 4. Arsitektur Deployment

```text
Pengguna LINTAR
      |
      v
https://lintar.untar.ac.id/backup_data
      |
      +-- portal ASP.NET Web Forms
      +-- API /backup_data/api/agent.aspx
      +-- dec_dummy (data aktif dan tabel kontrol)
                    ^
                    | HTTP/HTTPS + X-Backup-Agent-Key
                    |
C:\BackupAgent\BackupAgent.ps1
      |
      +-- dec_dummy_backup
      +-- folder ekspor .bak
```

Folder web aktif `backup_data` hanya boleh berisi file runtime. Agent aktif berada di `C:\BackupAgent`, sedangkan paket deployment ditempatkan di `C:\BackupAgent\DeploymentPackage`. Salinan source website yang siap dipasang berada pada `DeploymentPackage\web\backup_data`; SQL, agent, pengujian, dan dokumentasi tetap berada di foldernya masing-masing di luar web root aktif.

Diagram di atas menggambarkan target production. Lingkungan development menggunakan URL internal pada `agent.config.development.json` dengan `AllowHttp=true`; perpindahan ke URL production dilakukan melalui cutover terpisah.

## 5. Perilaku Backup

### Berdasarkan Tahun Akademik

Mahasiswa dipilih apabila mempunyai baris `treg` pada Tahun Akademik yang dipilih. Data yang dikirim adalah:

- satu biodata `tbio01` untuk NIM terpilih;
- hanya baris `treg`, `tkrs06`, dan `t_absensi14` yang termasuk cakupan Tahun Akademik;
- hanya tabel yang dipilih pengguna; `tbio01` otomatis disertakan sebagai data induk jika tabel akademik lain dipilih;
- untuk mode batas, hanya baris dengan Tahun Akademik kurang dari atau sama dengan batas;
- untuk mode rentang, hanya baris di antara TA awal dan TA akhir.

Pemilihan tidak didasarkan pada Tahun Akademik terakhir mahasiswa.

### Penulisan ke Database Backup

Agent menggunakan staging table, `SqlBulkCopy`, transaksi, dan upsert:

- baris dengan kunci sama diperbarui;
- baris baru ditambahkan;
- baris lama pada database backup yang sudah tidak ada di sumber tetap dipertahankan;
- tidak ada `DELETE`, `UPDATE`, atau `TRUNCATE` terhadap empat tabel aktif dalam alur backup.

## 6. Backup Otomatis

Jadwal tersimpan pada `BackupJobConfiguration`. Saat jadwal jatuh tempo, API membuat job backup dengan cakupan batas Tahun Akademik yang tersimpan. Agent mengambil job tersebut dan menjalankan aturan yang sama dengan backup manual. Mengaktifkan jadwal tidak membuat data aktif terhapus.

## 7. Pemulihan

Pemulihan hanya berjalan setelah tindakan eksplisit administrator.

- Pemulihan per NIM mengirim seluruh riwayat NIM dari database backup.
- Pemulihan per Tahun Akademik hanya mengirim baris `treg_backup`, `tkrs06_backup`, dan `t_absensi14_backup` pada periode yang dipilih serta biodata NIM terkait.
- Pengguna dapat memilih tabel yang dipulihkan. Pemulihan Tahun Akademik mewajibkan minimal satu tabel akademik, sedangkan `tbio01` otomatis disertakan untuk menjaga hubungan data mahasiswa.
- Setiap baris diperiksa menggunakan primary key atau unique key tabel aktif. Jika tabel tidak mempunyai indeks unik, modul menggunakan kunci natural aman yang telah ditetapkan.
- Baris yang belum ada dimasukkan ke database aktif.
- Baris dengan kunci yang sudah ada dilewati; baris aktif tidak diperbarui dan tidak dihapus.
- Salinan pada database backup tetap disimpan.
- Status `SKIPPED` berarti seluruh baris untuk NIM pada batch tersebut sudah tersedia; apabila minimal satu baris baru berhasil dimasukkan, NIM dicatat `RESTORED`.

## 8. Keamanan API

API berada pada `/backup_data/api/agent.aspx` dan:

- menerima HTTP maupun HTTPS dan selalu mewajibkan API key;
- hanya menerima metode POST;
- mewajibkan header `X-Backup-Agent-Key` sepanjang 32–256 karakter;
- membatasi request maksimum 100 MB;
- menonaktifkan cache respons;
- membatasi action dengan allowlist;
- tidak menyediakan endpoint deployment atau eksekusi SQL umum.

Token asli hanya disimpan pada file konfigurasi environment aktif dan hash SHA-256 pada tabel agent. Jangan simpan token asli dalam source atau dokumentasi.

## 9. Konfigurasi Agent

```json
{
  "ApiBaseUrl": "https://lintar.untar.ac.id/backup_data/api",
  "AllowHttp": false,
  "LocalSqlConnection": "Data Source=localhost;Initial Catalog=dec_dummy_backup;Integrated Security=SSPI;Connect Timeout=15;",
  "ApiKey": "GANTI_DENGAN_TOKEN_ACAK_MINIMAL_32_KARAKTER",
  "BackupBatchSize": 500,
  "RestoreBatchSize": 500,
  "ExportDirectory": "C:\\BackupAgent\\Exports"
}
```

Nama database backup diambil dari `Initial Catalog`, sehingga agent tidak bergantung pada alamat database aktif.

Untuk development internal berbasis HTTP, gunakan `agent.config.development.json` dengan `AllowHttp=true`. Pada production, gunakan `agent.config.production.json`, HTTPS, dan `AllowHttp=false`.

## 10. File SQL

- `deployment/install_backup_data_all.sql`: installer gabungan untuk penyiapan awal.
- `deployment/install_role_summary_report.sql`: migration minimal role untuk database yang sudah terpasang; tidak menyentuh tabel akademik dan tidak menjalankan backup/restore.
- `scripts/modular`: sumber kanonik untuk pemeliharaan per modul.
- `scripts/modular/00_core/04_validate_source_tables.sql`: validasi read-only atas tabel sumber.
- `scripts/modular/08_permissions/01_iis_permissions.sql`: izin minimum untuk identitas aplikasi yang dikonfigurasi.
- `scripts/modular/09_verification/01_verify_objects.sql`: verifikasi objek.

Script SQL harus diuji pada salinan database dan ditinjau DBA sebelum production. Optimasi runtime dan pembaruan dokumentasi tanggal 4 September 2026 tidak menjalankan script SQL dan tidak mengubah database.

## 11. Pengujian Aman

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\BackupAgent\DeploymentPackage\tests\Run-BackupTests.ps1 `
  -ApplicationRoot C:\inetpub\wwwroot\backup_data `
  -ToolingRoot C:\BackupAgent\DeploymentPackage `
  -ConfigPath C:\BackupAgent\agent.config.development.json `
  -SkipApi -SkipLocalDatabase
```

Pengujian integrasi API, backup, pemulihan, ekspor, dan penjadwalan baru dilakukan pada staging setelah persetujuan terpisah.

## 12. Status Implementasi per 7 September 2026

- Runtime telah dipasang pada jalur `backup_data`.
- Koneksi aktif diarahkan ke `condecdummy.ascx` tanpa mengubah file tersebut.
- Backup TA telah diubah menjadi berbasis baris pada TA yang dipilih.
- Pemulihan telah diubah menjadi insert-only per baris/kunci.
- Backup dan pemulihan mendukung pemilihan `tbio01`, `treg`, `tkrs06`, dan `t_absensi14`; `tbio01` otomatis disertakan jika tabel akademik dipilih.
- Agent aktif dan salinan pada Deployment Package telah disamakan. Konfigurasi development dan production dipisahkan.
- Job `LINTAR Backup Agent` terpasang, menggunakan `agent.config.development.json`, dan tetap dinonaktifkan sampai pengguna mengizinkan eksekusi.
- Pengujian optimasi sebelum penambahan role menghasilkan **21 PASS, 0 FAIL, dan 5 SKIP**.
- Endpoint aktif hanya menerima POST dan menolak permintaan tanpa API key dengan status HTTP 401.
- Migration role dijalankan oleh pengelola. Proses cutover source tidak menjalankan backup, restore, ekspor, agent, atau perubahan data akademik.
- Peran dan Laporan telah dipasang pada website aktif setelah migrasi database diselesaikan oleh pengelola.
- Verifikasi pascacutover fitur peran menghasilkan **26 PASS, 0 FAIL, dan 5 SKIP**; verifikasi setelah penambahan ekspor PDF menghasilkan **27 PASS, 0 FAIL, dan 5 SKIP**; verifikasi setelah penyederhanaan antarmuka menghasilkan **28 PASS, 0 FAIL, dan 5 SKIP**. Login nyata per peran dan pengujian operasi data tetap menunggu UAT.

## 13. Implementasi Peran dan Laporan

Source fitur, migrasi peran, dan cutover website telah selesai. Pengujian login nyata menggunakan akun Staf dan Manager tetap diperlukan untuk UAT.

### 13.1 Tujuan

Implementasi memisahkan kewenangan pengguna menjadi dua peran dan menyediakan laporan ringkas yang bersifat read-only. Pembatasan diterapkan pada router dan kontrol sisi server, bukan hanya dengan menyembunyikan menu pada antarmuka.

### 13.2 Matriks Hak Akses

| Fungsi | Staf | Manager |
|---|---:|---:|
| Dashboard | Ya | Ya |
| Laporan dan ekspor PDF | Ya | Ya |
| Backup manual dan otomatis | Ya | Tidak |
| Pemulihan data | Ya | Tidak |
| Riwayat dan pembatalan proses | Ya | Tidak |
| Status dan inventaris operasional | Ya | Tidak |
| Kelola pengguna/operator | Ya | Tidak |
| Ekspor database backup | Ya | Tidak |

Peran **Staf** mempunyai akses penuh terhadap seluruh fungsi modul. Peran **Manager** hanya dapat membuka Dashboard dan Laporan serta tidak dapat membuat, membatalkan, atau mengubah proses maupun konfigurasi.

### 13.3 Otorisasi yang Diimplementasikan

- Role disimpan sebagai `STAFF_BACKUP` atau `MANAGER_BACKUP`.
- Role lama `ADMIN_BACKUP`, `ADMIN`, dan `SUPERADMIN` tetap dipetakan sebagai Staf untuk kompatibilitas.
- Role modul dari `BackupOperatorAccess` diprioritaskan dibanding role umum pada session LINTAR.
- Akun yang dinonaktifkan ditolak walaupun mempunyai role umum administrator pada session.
- Role divalidasi pada router serta setiap kontrol yang dapat membuat atau mengubah proses.
- Manager yang mencoba membuka URL operasional secara langsung diarahkan kembali ke Dashboard dengan pesan akses ditolak.
- API agent tetap menggunakan API key dan tidak mengikuti role pengguna portal.
- Staf tidak dapat menonaktifkan atau menurunkan role akun yang sedang digunakannya sendiri.

### 13.4 Cakupan Laporan

Laporan merupakan halaman baca-saja yang mengambil data dari `BackupTransferJob`, `BackupAgentPeriodInventory`, dan `BackupAgentNode` melalui database aktif. Web tetap tidak membuka koneksi langsung ke `dec_dummy_backup`.

Informasi minimum yang disarankan:

- jumlah proses backup, pemulihan, dan ekspor berdasarkan status;
- jumlah mahasiswa dan baris backup per Tahun Akademik serta per tabel;
- waktu backup terakhir, durasi, jumlah data yang diproses, dan hasil terakhir;
- ringkasan proses berhasil, gagal, dibatalkan, dan masih berjalan;
- status koneksi berkala serta kesiapan Database Backup;
- filter rentang tanggal maksimum 366 hari, Tahun Akademik, jenis operasi, status, dan tabel;
- daftar maksimum 100 proses terbaru yang sesuai filter.

Tampilan menggunakan kartu ringkasan proses, tabel detail proses, dan inventaris per Tahun Akademik. Tombol **Ekspor PDF** menghasilkan laporan A4 lanskap berdasarkan filter yang sedang dipilih, berisi metrik ringkas, maksimum 100 proses terbaru, serta inventaris per Tahun Akademik. PDF dibuat langsung di memori server dan dikirim sebagai lampiran; tidak ada berkas sementara, koneksi langsung ke `dec_dummy_backup`, ataupun perubahan data. Ekspor Excel belum termasuk implementasi saat ini.

### 13.5 Status Penerapan

1. **Selesai:** source peran, menu, pembatasan sisi server, pengelolaan pengguna, Dashboard, dan Laporan.
2. **Selesai:** migration SQL idempotent dan installer gabungan; sintaks 70 batch telah lolos `PARSEONLY`.
3. **Selesai:** pengujian statis setelah penyempurnaan antarmuka menghasilkan **33 PASS, 0 FAIL, dan 5 SKIP**; pemeriksaan API serta database sengaja dilewati.
4. **Selesai oleh pengelola:** `database/install_role_summary_report.sql` pada `dec_dummy`.
5. **Selesai:** cutover source ke website aktif dan verifikasi kesamaan hash.
6. **Selesai:** generator PDF dikompilasi dari source website, menghasilkan PDF uji delapan halaman yang valid, dan halaman awal, tengah, serta akhir telah dirender untuk pemeriksaan tata letak.
7. **Belum dijalankan:** pengujian login nyata dan UAT terpisah untuk Staf serta Manager, termasuk unduhan PDF dengan data aktual.

### 13.6 Kriteria Penerimaan

- Staf dapat menggunakan seluruh fungsi yang tersedia.
- Manager hanya dapat melihat Dashboard dan Laporan.
- Manager tidak dapat menjalankan fungsi operasional melalui URL atau request langsung.
- Laporan menampilkan nilai yang konsisten dengan tabel kontrol dan inventaris.
- Filter laporan tidak menjalankan perubahan data.
- PDF dapat diunduh oleh Staf dan Manager, mengikuti filter aktif, terbuka tanpa kesalahan, dan tidak memicu job maupun perubahan data.
- Perubahan role dan akses penting dapat ditelusuri melalui log.

## 14. Penyederhanaan Antarmuka

Antarmuka operasional telah diringkas tanpa mengubah kontrak database atau alur pemrosesan:

- menu Staf dikelompokkan menjadi **Operasional**, **Pemantauan**, dan **Administrasi**;
- istilah tampilan menggunakan **Laporan**, **Riwayat Proses**, dan **layanan pemrosesan backup**;
- pengaturan Backup Otomatis ditempatkan pada panel yang dapat dibuka dan ditutup;
- halaman Backup memiliki mode Tahun Akademik dan otomatis, sedangkan Pemulihan tetap mendukung Tahun Akademik serta NIM;
- filter Laporan menggunakan susunan responsif tiga, dua, atau satu kolom sesuai lebar layar;
- tindakan penting memakai dialog SweetAlert yang konsisten, dengan fallback dialog browser jika pustaka tidak tersedia.

Dashboard berfungsi sebagai pusat pemantauan dan menjadi satu-satunya halaman yang menampilkan proses aktif, selain status kesiapan Database Backup, identitas serta heartbeat agent utama, pesan agent, konfigurasi backup otomatis, dan proses terakhir. Halaman Backup dan Pemulihan menggunakan pemeriksaan kesiapan yang sama sebelum membuat permintaan; pesan hanya ditampilkan ketika layanan belum siap atau statusnya tidak dapat diperiksa. Halaman Riwayat bersifat baca-saja, hanya menampilkan proses yang telah selesai, serta menyediakan filter operasi dan status dalam satu baris pada layar desktop. Halaman Ekspor menampilkan nama file, ukuran, dan status verifikasi; SHA-256 tetap dicatat pada hasil proses agent tetapi disembunyikan dari tampilan utama. File `.bak` tetap berada pada server Database Backup.

Kelola Pengguna menampilkan ringkasan hak akses Staf dan Manager. Perlindungan sisi server dan antarmuka mencegah pengguna yang sedang login menonaktifkan dirinya sendiri atau mengubah dirinya menjadi Manager. Router dan kontrol halaman tetap membatasi Manager hanya pada Dashboard dan Laporan, termasuk akses melalui URL langsung.

Sebanyak **33 pemeriksaan statis** telah lulus tanpa akses API atau database. Penilaian kemudahan penggunaan secara empiris tetap harus dilakukan melalui UAT dan SUS bersama pengguna Staf serta Manager.

### 14.1 Keterkaitan dengan Bab 1 dan Bab 2

- **Bab 1:** penguatan Dashboard, status kesiapan, filter riwayat, dan tautan pemantauan memperjelas jawaban sistem terhadap kebutuhan staf untuk mengendalikan serta menelusuri proses backup. Pembatasan role mendukung kebutuhan dua kelompok pengguna.
- **Bab 2:** rancangan antarmuka, use case, activity diagram, struktur navigasi, dan rancangan pengujian perlu menampilkan status layanan bersama, filter Riwayat Proses, metrik ringkas Laporan, metadata ekspor, serta aturan perlindungan akun sendiri. Alur data utama dan arsitektur pemisahan server tidak berubah.
