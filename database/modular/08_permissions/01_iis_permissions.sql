/*
 Fungsi: Memberikan seluruh hak minimum aplikasi IIS setelah semua objek dibuat.
 Script kanonik aktif untuk fungsi ini.
*/

USE [dec_dummy];
GO
SET XACT_ABORT ON;
GO

GRANT EXECUTE ON dbo.sp_CheckBackupOperatorAccess TO [IIS APPPOOL\DefaultAppPool];
GRANT EXECUTE ON dbo.sp_GetBackupOperatorRole TO [IIS APPPOOL\DefaultAppPool];
GRANT EXECUTE ON dbo.sp_SetBackupOperatorAccess TO [IIS APPPOOL\DefaultAppPool];
GRANT EXECUTE ON dbo.sp_AgentHeartbeat TO [IIS APPPOOL\DefaultAppPool];
GRANT EXECUTE ON dbo.sp_CreateBackupTransferJob TO [IIS APPPOOL\DefaultAppPool];
GRANT EXECUTE ON dbo.sp_CreateBackupNimTransferJob TO [IIS APPPOOL\DefaultAppPool];
GRANT EXECUTE ON dbo.sp_CreateRestoreTransferJob TO [IIS APPPOOL\DefaultAppPool];
GRANT EXECUTE ON dbo.sp_CreateBackupExportJob TO [IIS APPPOOL\DefaultAppPool];
GRANT EXECUTE ON dbo.sp_CreateBackupLookupRequest TO [IIS APPPOOL\DefaultAppPool];
GRANT EXECUTE ON dbo.sp_GetBackupLookupRequest TO [IIS APPPOOL\DefaultAppPool];
GRANT EXECUTE ON dbo.sp_AgentClaimBackupTransferJob TO [IIS APPPOOL\DefaultAppPool];
GRANT EXECUTE ON dbo.sp_AgentGetBackupBatch TO [IIS APPPOOL\DefaultAppPool];
GRANT EXECUTE ON dbo.sp_AgentConfirmBackupBatch TO [IIS APPPOOL\DefaultAppPool];
GRANT EXECUTE ON dbo.sp_AgentConfirmRestoreBatch TO [IIS APPPOOL\DefaultAppPool];
GRANT EXECUTE ON dbo.sp_AgentSyncPeriodInventory TO [IIS APPPOOL\DefaultAppPool];
GRANT EXECUTE ON dbo.sp_SaveBackupJobConfiguration TO [IIS APPPOOL\DefaultAppPool];
GRANT SELECT ON dbo.BackupAgentNode TO [IIS APPPOOL\DefaultAppPool];
GRANT SELECT ON dbo.BackupOperatorAccess TO [IIS APPPOOL\DefaultAppPool];
GRANT SELECT ON dbo.BackupAgentPeriodInventory TO [IIS APPPOOL\DefaultAppPool];
GRANT SELECT ON dbo.BackupJobConfiguration TO [IIS APPPOOL\DefaultAppPool];
GRANT SELECT, UPDATE ON dbo.BackupTransferJob TO [IIS APPPOOL\DefaultAppPool];
GRANT SELECT, INSERT, UPDATE ON dbo.BackupTransferJobStudent TO [IIS APPPOOL\DefaultAppPool];
GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.BackupLookupRequest TO [IIS APPPOOL\DefaultAppPool];
-- Tabel sumber hanya dapat dibaca saat backup. INSERT hanya diperlukan ketika
-- operator secara eksplisit menjalankan pemulihan. UPDATE dan DELETE tidak diberikan.
GRANT SELECT, INSERT ON dbo.tbio01 TO [IIS APPPOOL\DefaultAppPool];
GRANT SELECT, INSERT ON dbo.treg TO [IIS APPPOOL\DefaultAppPool];
GRANT SELECT, INSERT ON dbo.tkrs06 TO [IIS APPPOOL\DefaultAppPool];
GRANT SELECT, INSERT ON dbo.t_absensi14 TO [IIS APPPOOL\DefaultAppPool];
GO
