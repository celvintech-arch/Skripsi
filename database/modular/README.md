# Script SQL aktif backup data

Folder ini adalah satu-satunya sumber SQL instalasi modul backup. Setiap file dipisahkan berdasarkan fungsi agar procedure tidak didefinisikan berulang di beberapa migration.

## Pemakaian pada database yang sudah terpasang

- Jalankan `09_verification/01_verify_objects.sql` untuk pemeriksaan read-only.
- Jalankan file fungsi tertentu hanya ketika objek pada fungsi tersebut perlu dibuat atau diperbarui.
- Untuk menambahkan role pada instalasi yang sudah berjalan, gunakan `../../deployment/install_role_summary_report.sql` tanpa menjalankan ulang seluruh installer.
- Jangan menjalankan ulang seluruh rangkaian pada database produksi tanpa pengujian dan backup yang sesuai.

## Urutan instalasi database baru

Jalankan melalui SSMS pada `dec_dummy` dengan akun administrator:

Untuk satu file siap-jalankan, gunakan `../../deployment/install_backup_data_all.sql`. Installer tersebut menggabungkan seluruh sumber berikut dalam urutan yang sama. Jika terjadi kegagalan parsial, perbaiki penyebabnya lalu jalankan kembali installer; tabel memakai pemeriksaan keberadaan dan procedure memakai `CREATE OR ALTER`.

1. `00_core/01_agent_and_operator_tables.sql`
2. `00_core/02_transfer_and_inventory_tables.sql`
3. `00_core/03_lookup_schema.sql`
4. `00_core/04_validate_source_tables.sql`
5. `01_security/01_operator_access.sql`
6. `01_security/02_primary_agent_and_heartbeat.sql`
7. `02_backup/01_create_backup_jobs.sql`
8. `02_backup/02_agent_backup_batches.sql`
9. `03_restore/01_create_restore_job.sql`
10. `03_restore/02_agent_restore_batches.sql`
11. `04_maintenance/02_export_backup_job.sql`
12. `05_lookup/01_backup_lookup.sql`
13. `06_agent/01_claim_job.sql`
14. `06_agent/02_sync_inventory.sql`
15. `07_scheduler/01_configuration_and_schedule.sql`
16. `08_permissions/01_iis_permissions.sql`
17. `09_verification/01_verify_objects.sql`

Setelah itu daftarkan primary agent menggunakan `dbo.sp_RegisterPrimaryBackupAgent`.

Sebelum bagian permission dijalankan, pastikan login dan user database untuk identitas Application Pool IIS telah dibuat. Instalasi saat ini menggunakan `IIS APPPOOL\DefaultAppPool`. File `08_permissions/01_iis_permissions.sql` memberikan hak minimum dan mencakup `SELECT` pada `BackupJobConfiguration` untuk portal serta endpoint claim.

## Pembagian fungsi

| Folder | Fungsi |
|---|---|
| `00_core` | Tabel kontrol, constraint, inventaris, lookup, relasi pemulihan, dan validasi tabel sumber `dec_dummy`. |
| `01_security` | Role Staf/Manager, pengelolaan pengguna, registrasi primary agent, dan heartbeat. |
| `02_backup` | Pembuatan job serta transfer batch backup non-destruktif. |
| `03_restore` | Pembuatan job serta konfirmasi batch pemulihan. |
| `04_maintenance` | Ekspor database backup. |
| `05_lookup` | Antrean dan hasil pencarian melalui agent. |
| `06_agent` | Claim, lease, retry job, dan inventaris. |
| `07_scheduler` | Konfigurasi serta pembuatan backup otomatis. |
| `08_permissions` | Hak minimum application pool IIS. |
| `09_verification` | Pemeriksaan read-only kelengkapan objek. |

Semua file dalam folder ini merupakan script aktif. Migration monolitik dan deployment sementara telah dihapus untuk mencegah procedure versi lama menimpa definisi terbaru.

Setiap job backup dan pemulihan menyimpan daftar tabel pada `BackupTransferJob.SelectedTables`. Daftar yang diizinkan adalah `tbio01`, `treg`, `tkrs06`, dan `t_absensi14`; `tbio01` otomatis ditambahkan jika tabel lain dipilih. Konfigurasi backup otomatis menyimpan pilihan yang sama pada `BackupJobConfiguration.SelectedTables`.

## Validasi versi saat ini

- Alias hasil validasi tabel sumber menggunakan `TotalRows` agar tidak berbenturan dengan keyword SQL Server.
- `sp_AgentSyncPeriodInventory` diakhiri pemisah batch `GO` sebelum script berikutnya.
- Installer gabungan terakhir memuat 17 bagian dan 17 stored procedure, termasuk `sp_GetBackupOperatorRole`.
- Kandidat role dan Summary Report menghasilkan **26 PASS, 0 FAIL, dan 5 SKIP**; pengujian login nyata serta integrasi database dijalankan setelah migration dan cutover disetujui.
