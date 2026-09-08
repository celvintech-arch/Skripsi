# Checklist Cutover `backup_data`

Checklist ini digunakan setelah source dan staging disetujui. Tahap yang menjalankan SQL atau operasi data memerlukan persetujuan tersendiri.

## 1. Source dan keamanan

- [ ] Folder web bernama `backup_data` dan tidak memuat folder `agent`, `scripts`, `deployment`, `tests`, atau dokumentasi.
- [ ] Source yang akan dipasang berasal dari `C:\BackupAgent\DeploymentPackage\web\backup_data` dan hash-nya diverifikasi setelah penyalinan.
- [ ] Portal dan API memasukkan `/con_ascx2022/condecdummy.ascx`; file tersebut tidak diubah.
- [ ] `web.config` tidak memiliki connection string database.
- [ ] URL produksi adalah `https://lintar.untar.ac.id/backup_data`.
- [ ] Jalur production hanya diekspos melalui HTTPS dan API menerima hanya POST bertoken.
- [ ] Token agent berbeda dari contoh dan panjangnya 32–256 karakter.
- [ ] Permission file konfigurasi dibatasi untuk administrator dan akun layanan agent.

## 2. Staging database

- [ ] Installer diuji pada salinan `dec_dummy`.
- [ ] Keempat tabel `tbio01`, `treg`, `tkrs06`, dan `t_absensi14` lolos validasi metadata.
- [ ] Principal yang dipakai `condecdummy.ascx` mempunyai izin minimum yang diperlukan.
- [ ] Tidak ada `UPDATE`, `DELETE`, atau `TRUNCATE` atas tabel aktif pada alur backup.
- [ ] Pemulihan hanya mempunyai izin `INSERT` atas tabel aktif.
- [ ] Verifikasi objek tidak menghasilkan status `MISSING`.

## 3. Node backup

- [ ] Paket source disalin ke `C:\BackupAgent\DeploymentPackage` tanpa menimpa agent aktif.
- [ ] `agent.config.production.json` memakai `https://lintar.untar.ac.id/backup_data/api` dan `AllowHttp=false`.
- [ ] `LocalSqlConnection` menunjuk ke `dec_dummy_backup`.
- [ ] Sertifikat HTTPS valid dan dipercaya node backup.
- [ ] Agent manual menghasilkan heartbeat sehat.
- [ ] Job otomatis belum diaktifkan sebelum semua tes staging lulus.

## 4. Pengujian staging

- [ ] Suite source lulus dengan `-SkipApi -SkipLocalDatabase`.
- [ ] Halaman login dan semua menu dapat dibuka tanpa compiler error.
- [ ] Token salah ditolak.
- [ ] Backup satu NIM menambah/memperbarui backup tanpa mengubah jumlah atau isi baris aktif.
- [ ] Pengulangan backup NIM tidak membuat duplikasi.
- [ ] Backup satu TA hanya menyalin baris periode itu, bukan seluruh riwayat NIM.
- [ ] Backup rentang dan batas TA mengikuti cakupan yang dipilih.
- [ ] Baris lama pada database backup tetap ada ketika tidak lagi ada pada sumber.
- [ ] Pemulihan memasukkan baris yang hilang dan melewati kunci yang sudah ada tanpa overwrite.
- [ ] Pemulihan per TA tidak mengirim periode di luar pilihan.
- [ ] Ekspor `.bak` dan `RESTORE VERIFYONLY` berhasil.
- [ ] Backup otomatis berjalan sesuai konfigurasi.

## 5. Aktivasi produksi

- [ ] Buat backup penuh dan rencana rollback sebelum perubahan SQL produksi.
- [ ] Pasang runtime `backup_data` dan uji HTTPS.
- [ ] Jalankan perubahan SQL yang telah disetujui DBA.
- [ ] Setelah disetujui, promosikan `BackupAgent.ps1` final ke `C:\BackupAgent` dan pertahankan `agent.config.production.json`.
- [ ] Jalankan satu heartbeat tanpa mengambil job data.
- [ ] Lakukan smoke test yang telah disetujui.
- [ ] Aktifkan job otomatis hanya setelah hasil smoke test diterima.
- [ ] Pantau heartbeat, antrean, progres, error, dan pertumbuhan database backup.

## 6. Kriteria pembatalan

Batalkan cutover apabila terjadi compiler error, token salah diterima, koneksi tidak menggunakan HTTPS, tabel aktif berubah saat backup, muncul duplikasi backup, pemulihan menimpa baris aktif, atau heartbeat gagal. Nonaktifkan agent baru dan kembalikan menu/runtime sebelumnya; jangan menghapus data sebagai langkah rollback.

## Status refaktor source

Runtime hasil optimasi telah dipasang pada jalur development `backup_data`. Pengujian statis pascadeploy tanggal 4 September 2026 menghasilkan **21 PASS, 0 FAIL, dan 5 SKIP**. Job `LINTAR Backup Agent` tetap nonaktif dan menggunakan konfigurasi development. Pengujian operasi data dan aktivasi production belum dilakukan. Tidak ada SQL, backup, pemulihan, ekspor, atau perubahan data yang dijalankan pada tahap optimasi ini.

## 7. Cutover peran dan Laporan Ringkasan

Source fitur, migrasi peran, dan cutover website telah selesai. Pengujian akun nyata dan UAT tetap diperlukan.

- [x] Tetapkan peran `STAFF_BACKUP` dengan akses penuh dan `MANAGER_BACKUP` dengan akses Dashboard serta Laporan Ringkasan saja.
- [x] Pertahankan role lama sebagai Staf untuk kompatibilitas tanpa memperbarui data akun secara otomatis.
- [x] Terapkan pemeriksaan role pada server untuk menu, URL langsung, dan postback.
- [ ] Pastikan Manager tidak dapat membuat, membatalkan, memulihkan, mengekspor, atau mengubah konfigurasi.
- [x] Tambahkan filter dan metrik dasar Laporan Ringkasan.
- [x] Pastikan Laporan bersifat baca-saja dan tidak membuka koneksi web langsung ke `dec_dummy_backup`.
- [x] Tambahkan ekspor PDF yang mengikuti filter aktif dan dibuat langsung di memori server.
- [x] Validasi struktur PDF serta render halaman awal, tengah, dan akhir menggunakan data uji.
- [x] Jalankan `deployment/install_role_summary_report.sql` pada `dec_dummy` setelah review DBA.
- [x] Pasang source website setelah migration berhasil.
- [ ] Laksanakan pengujian akses dan UAT terpisah untuk Staf serta Manager, termasuk unduhan PDF dengan data aktual.

## 8. Penyederhanaan antarmuka

- [x] Kelompokkan menu Staf menjadi Operasional, Pemantauan, dan Administrasi.
- [x] Ubah nama tampilan menjadi Laporan Ringkasan dan Riwayat Proses.
- [x] Jadikan pengaturan Backup Otomatis sebagai panel yang dapat dibuka dan ditutup.
- [x] Tambahkan petunjuk singkat pada mode backup dan pemulihan.
- [x] Susun filter Laporan Ringkasan secara responsif untuk layar kecil.
- [x] Gunakan SweetAlert untuk konfirmasi tindakan, dengan fallback aman jika pustaka tidak tersedia.
- [x] Kompilasi ASP.NET Web Forms berhasil dan pengujian statis menghasilkan **28 PASS, 0 FAIL, dan 5 SKIP**.
- [ ] Validasi kemudahan penggunaan melalui UAT dan SUS bersama Staf serta Manager.
