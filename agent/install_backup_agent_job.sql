/*
  Jalankan DI LAPTOP AGENT pada koneksi SQL Server lokal, sebagai sysadmin.
  Prasyarat:
  - SQL Server Agent lokal berstatus Running.
  - C:\BackupAgent\BackupAgent.ps1 dan C:\BackupAgent\agent.config.production.json tersedia.
  - Akun layanan SQL Server Agent dapat membaca folder C:\BackupAgent.
*/
USE msdb;
GO

DECLARE @JobName sysname = N'LINTAR Backup Agent';
DECLARE @ScheduleName sysname = N'LINTAR Backup Agent - tiap 1 menit';

IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = @JobName)
BEGIN
    EXEC dbo.sp_delete_job @job_name = @JobName;
END;

IF EXISTS (SELECT 1 FROM dbo.sysschedules WHERE name = @ScheduleName)
BEGIN
    EXEC dbo.sp_delete_schedule @schedule_name = @ScheduleName;
END;
GO

EXEC dbo.sp_add_job
    @job_name = N'LINTAR Backup Agent',
    @enabled = 1,
    @description = N'Mengirim heartbeat dan memproses job backup/pemulihan LINTAR ke Database Backup lokal.';
GO

EXEC dbo.sp_add_jobstep
    @job_name = N'LINTAR Backup Agent',
    @step_name = N'Jalankan Backup Agent',
    @subsystem = N'CmdExec',
    @command = N'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\BackupAgent\BackupAgent.ps1" -ConfigPath "C:\BackupAgent\agent.config.production.json"',
    @on_success_action = 1,
    @on_fail_action = 2,
    @retry_attempts = 3,
    @retry_interval = 1;
GO

EXEC dbo.sp_add_schedule
    @schedule_name = N'LINTAR Backup Agent - tiap 1 menit',
    @enabled = 1,
    @freq_type = 4,
    @freq_interval = 1,
    @freq_subday_type = 4,
    @freq_subday_interval = 1,
    @active_start_time = 000000;
GO

EXEC dbo.sp_attach_schedule
    @job_name = N'LINTAR Backup Agent',
    @schedule_name = N'LINTAR Backup Agent - tiap 1 menit';
GO

EXEC dbo.sp_add_jobserver
    @job_name = N'LINTAR Backup Agent';
GO

EXEC dbo.sp_start_job @job_name = N'LINTAR Backup Agent';
GO
