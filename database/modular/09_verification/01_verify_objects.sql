/*
 Fungsi: Memastikan tabel dan prosedur wajib tersedia tanpa mengubah data.
 Script kanonik aktif untuk fungsi ini.
*/

USE [dec_dummy];
GO
SET XACT_ABORT ON;
GO

DECLARE @RequiredObjects TABLE(ObjectName SYSNAME NOT NULL, ObjectType CHAR(2) NOT NULL);
INSERT @RequiredObjects(ObjectName,ObjectType) VALUES
 ('BackupAgentNode','U'),('BackupOperatorAccess','U'),('BackupTransferJob','U'),
 ('BackupTransferJobStudent','U'),('BackupAgentPeriodInventory','U'),('BackupLookupRequest','U'),
 ('tkrs06','U'),('sp_GetBackupOperatorRole','P'),('sp_RegisterPrimaryBackupAgent','P'),('sp_AgentHeartbeat','P'),
 ('sp_CreateBackupTransferJob','P'),('sp_CreateBackupNimTransferJob','P'),
 ('sp_CreateRestoreTransferJob','P'),
 ('sp_CreateBackupExportJob','P'),('sp_CreateBackupLookupRequest','P'),
 ('sp_GetBackupLookupRequest','P'),
 ('sp_AgentClaimBackupTransferJob','P'),('sp_AgentGetBackupBatch','P'),
 ('sp_AgentConfirmBackupBatch','P'),('sp_AgentConfirmRestoreBatch','P'),
 ('sp_AgentSyncPeriodInventory','P'),
 ('BackupJobConfiguration','U'),('sp_SaveBackupJobConfiguration','P');

SELECT ObjectName,ObjectType,
 CASE WHEN OBJECT_ID(N'dbo.'+ObjectName,ObjectType) IS NULL THEN 'MISSING' ELSE 'OK' END AS InstallationStatus
FROM @RequiredObjects
ORDER BY InstallationStatus DESC,ObjectType,ObjectName;

IF EXISTS(SELECT 1 FROM @RequiredObjects WHERE OBJECT_ID(N'dbo.'+ObjectName,ObjectType) IS NULL)
 THROW 51290,'Instalasi modular belum lengkap. Periksa objek berstatus MISSING.',1;
GO
