# Deploy perubahan mode backup

Jalankan script berikut melalui SSMS pada database `dec_dummy`, sesuai urutan:

1. `00_core/04_validate_source_tables.sql`
2. `02_backup/01_create_backup_jobs.sql`
3. `02_backup/02_agent_backup_batches.sql`
4. `03_restore/01_create_restore_job.sql`
5. `04_maintenance/02_export_backup_job.sql`
6. `06_agent/01_claim_job.sql`

Script validasi memastikan `dec_dummy.dbo.tbio01`, `treg`, `tkrs06`, dan `t_absensi14` tersedia tanpa mengubah data. Script pembuatan job memilih mahasiswa berdasarkan Tahun Akademik atau NIM tanpa menyaring status registrasi. Konfirmasi batch hanya menandai progres dan tidak menghapus data sumber.

Setelah deploy, periksa definisi procedure:

```sql
SELECT OBJECT_DEFINITION(OBJECT_ID('dbo.sp_CreateBackupTransferJob'));
SELECT OBJECT_DEFINITION(OBJECT_ID('dbo.sp_CreateBackupNimTransferJob'));
SELECT OBJECT_DEFINITION(OBJECT_ID('dbo.sp_AgentConfirmBackupBatch'));
```

Pastikan hasil pemeriksaan:

- tidak terdapat filter berdasarkan `sts_reg` pada pembuatan kandidat;
- seluruh status mahasiswa dapat dipilih untuk backup; dan
- tidak terdapat `DELETE` terhadap `tbio01`, `treg`, `tkrs06`, atau `t_absensi14`.

Agent yang terpasang harus menggunakan versi `BackupAgent.ps1` terbaru. Agent melakukan insert/update berdasarkan indeks unik atau kunci natural tabel LINTAR dan tidak menghapus salinan backup lama yang tidak lagi tersedia pada sumber.

Setelah seluruh script berhasil dijalankan dan hasil verifikasi tidak lagi memuat operasi destruktif, aktifkan kembali job pada instance SQL Server node backup:

```sql
USE msdb;
EXEC dbo.sp_update_job
 @job_name=N'LINTAR Backup Agent',
 @enabled=1;
EXEC dbo.sp_start_job
 @job_name=N'LINTAR Backup Agent';
```
