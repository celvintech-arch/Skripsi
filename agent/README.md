# LINTAR Backup Agent - Node Backup Utama dengan API Key

Web LINTAR membuat antrean pada `dec_dummy`. Ketika job diaktifkan, SQL Server Agent pada satu node backup utama menjalankan `BackupAgent.ps1` setiap satu menit. Script mengambil job melalui API, lalu membaca/menulis `dec_dummy_backup` sebagai database backup melalui koneksi SQL lokal. Web tidak mempunyai koneksi langsung ke database backup pada node.

## 1. Token agent

Gunakan token acak minimal 32 karakter dan simpan hanya di file konfigurasi environment yang aktif. Database live hanya menyimpan hash SHA-256 token melalui:

```sql
EXEC dbo.sp_RegisterPrimaryBackupAgent
 @AgentName=N'BACKUP-LAPTOP-UTAMA',
 @ApiKey=N'TOKEN_ACAK_MINIMAL_32_KARAKTER';
```

## 2. Database aktif

Gunakan hanya script aktif di `scripts/modular` dan ikuti urutan pada `scripts/modular/README.md`. Migration monolitik lama sudah dihapus agar procedure versi lama tidak dapat menimpa definisi terbaru.

`sp_CreateBackupTransferJob` menolak job backup kedua ketika masih ada status `WAITING`, `CLAIMED`, atau `TRANSFERRING`. Pemeriksaan jadwal dijalankan langsung oleh endpoint claim, sehingga tidak diperlukan job scheduler kedua pada server live.

Hak akses operator diberikan setelah instalasi:

```sql
EXEC dbo.sp_SetBackupOperatorAccess
 @UserId=N'ID_LINTAR',
 @AccessRole='ADMIN_BACKUP',
 @IsEnabled=1;
```

Website menggunakan `STAFF_BACKUP` untuk akses penuh dan `MANAGER_BACKUP` untuk akses Dashboard serta Summary Report saja. Migration role dan source website aktif telah dipasang pada 7 September 2026; validasi login nyata per role tetap dilakukan melalui UAT.
## 3. URL API

Endpoint menerima HTTP maupun HTTPS dan selalu mewajibkan API key. Agent hanya mengizinkan HTTP jika `AllowHttp=true`; gunakan HTTP untuk jaringan development internal saja. URL produksi modul adalah:

`https://lintar.untar.ac.id/backup_data/api`

Endpoint yang dipanggil adalah `/agent.aspx?action=...`. Pada production, gunakan HTTPS dan `AllowHttp=false` karena API key tidak dienkripsi melalui HTTP.

## 4. Izin koneksi IIS

API menggunakan Windows Integrated Security untuk membuka `dec_dummy`. Jika IIS dan SQL Server berada pada mesin yang sama, buat login dan user database untuk Application Pool yang digunakan. Instalasi saat ini menggunakan `IIS APPPOOL\DefaultAppPool`.

Setelah user database tersedia, jalankan `scripts/modular/08_permissions/01_iis_permissions.sql`. Script tersebut memberikan hak minimum, termasuk `SELECT` pada `BackupJobConfiguration` yang dibutuhkan endpoint claim. Jika IIS dan SQL Server berbeda mesin, gunakan akun domain/service account dan jangan menggunakan virtual account lokal sebagai identitas lintas mesin.

## 5. Konfigurasi node backup

1. Salin file agent ke `C:\BackupAgent`.
2. Salin template development atau production menjadi `agent.config.development.json` atau `agent.config.production.json`.
3. Isi `ApiKey`, URL API, koneksi SQL lokal, `BackupBatchSize=500`, dan `RestoreBatchSize=500`. Gunakan `AllowHttp=true` hanya untuk development internal; production wajib `false`. Nama database diambil dari `Initial Catalog` pada koneksi SQL lokal.
4. Batasi permission kedua file konfigurasi untuk administrator dan akun layanan SQL Server Agent.
5. Jalankan uji satu kali:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\BackupAgent\BackupAgent.ps1 -ConfigPath C:\BackupAgent\agent.config.production.json
```

6. Pastikan keluaran manual memuat `databaseReady=true` dan `backupStatsReceived=true`.
7. Uji backup satu NIM dan ulangi NIM yang sama untuk memeriksa upsert.
8. Untuk instalasi baru saja, jalankan `C:\BackupAgent\DeploymentPackage\agent\install_backup_agent_job.sql` setelah pengujian manual disetujui. Script menghapus job bernama sama, membuatnya kembali dengan konfigurasi production, mengaktifkannya, dan langsung memulai agent. Jangan jalankan ulang script tersebut pada job yang sudah terpasang tanpa rencana cutover dan persetujuan operasi data.

## Perilaku data

- Backup melakukan insert/update transaksional per batch menggunakan staging table, `SqlBulkCopy`, dan `MERGE`. Data pada database aktif tidak dihapus.
- Setiap job membawa `SelectedTables`; agent hanya membaca dan menulis tabel yang dipilih. `tbio01` selalu disertakan jika tabel akademik lain dipilih.
- Baris lama pada database backup yang tidak lagi ada di sumber tetap dipertahankan. Baris yang masih ada diperbarui berdasarkan indeks unik atau kunci natural tabel LINTAR.
- Restore menyalin data ke database aktif tanpa menghapus backup lokal; pengiriman menggunakan batch terkonfigurasi dan `SqlBulkCopy`.
- Restore tidak pernah menimpa data yang sudah berada di database live.
- Restore per NIM mengirim seluruh riwayat NIM. Restore per Tahun Akademik hanya mengirim baris pada periode yang dipilih beserta biodatanya.
- Restore memasukkan baris yang kuncinya belum ada dan melewati baris yang sudah tersedia. Data aktif tidak diperbarui atau dihapus.
- Exception yang tertangkap agent langsung menandai job `FAILED`; proses yang mati mendadak tetap dipulihkan melalui lease/retry.
- Agent menolak memproses job jika terdapat NIM yatim antara tabel biodata, registrasi, KRS, atau absensi backup.
- Detail hasil pencarian (maksimal 100 baris) hanya dikirim sebagai cache sementara 15 menit; inventaris permanen tetap berupa jumlah per Tahun Akademik.
- `Get-PeriodInventory` membaca tiga tabel akademik backup setiap lima menit dan mengirim `studentCount` serta `latestStudentCount` per Tahun Akademik ke API.
- Pencarian backup memakai antrean lookup HTTP/JSON; IIS tidak membuka koneksi SQL ke node backup.
- Pemulihan dibuat secara eksplisit melalui pilihan NIM atau Tahun Akademik pada portal.

## Verifikasi

```sql
SELECT AgentName,IsPrimary,IsEnabled,LastSeenAt,LastDatabaseReady,LastMessage
FROM dbo.BackupAgentNode;

SELECT TOP 20 JobId,OperationType,Status,RetryCount,ProcessedStudents,CreatedAt,CompletedAt,ErrorMessage
FROM dbo.BackupTransferJob ORDER BY CreatedAt DESC;
```

Hasil uji manual pada 28 Agustus 2026 menunjukkan agent `BACKUP-SERVER-UTAMA` berhasil mengirim heartbeat dengan `databaseReady=true` dan `backupStatsReceived=true`. Per 4 September 2026, job telah terpasang tetapi dinonaktifkan dan menggunakan `agent.config.development.json`. Sistem baru siap operasional penuh setelah hanya ada satu primary agent, heartbeat tetap baru, `LastDatabaseReady=1`, SQL Server Agent diaktifkan dengan persetujuan, serta uji backup/restore staging berstatus `SUCCESS`.
## Pembatalan dan progress

Tab **Riwayat Backup** menampilkan progress yang sudah dikonfirmasi serta pesan batch yang sedang berjalan. Tombol **Batalkan** menghentikan job aktif. Data backup yang sudah commit tetap tersimpan dan data aktif tidak dihapus. Secara kompatibel status database tetap `FAILED` dengan awalan pesan `[CANCELLED]`, sedangkan UI menampilkannya sebagai **Dibatalkan**.

## Ekspor dan restore database manual

Menu **Ekspor Database** membuat job manual. Agent menyimpan file `.bak` ke `ExportDirectory`, menjalankan `RESTORE VERIFYONLY WITH CHECKSUM`, menghitung SHA-256, lalu mencatat hasilnya pada riwayat. File tidak disediakan melalui HTTP.

Pada instalasi saat ini, `C:\BackupAgent\RestoreBackupDatabase.cmd` memakai konfigurasi development. Untuk production, jalankan `RestoreBackupDatabase.ps1` dengan `-ConfigPath C:\BackupAgent\agent.config.production.json`. Utilitas menolak tujuan `dec_dummy` dan `dec_dummy_backup`, menolak database yang sudah ada, dan memvalidasi empat tabel backup setelah restore.

## Mengaktifkan HTTPS

1. Pada server IIS, jalankan PowerShell sebagai Administrator lalu jalankan `C:\BackupAgent\DeploymentPackage\agent\configure_iis_https.ps1`.
2. Pada node backup, jalankan PowerShell sebagai Administrator lalu jalankan `C:\BackupAgent\DeploymentPackage\agent\trust_iis_https_on_agent.ps1`.
3. Pastikan `ApiBaseUrl` menjadi `https://lintar.untar.ac.id/backup_data/api`, `AllowHttp=false`, dan port 443 dapat diakses.

Skrip membuat sertifikat server RSA 3072-bit non-exportable, menambahkan binding IIS 443, mengekspor public certificate, mempercayainya pada node agent, lalu menguji heartbeat HTTPS.
