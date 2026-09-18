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

DECLARE @RequiredAgentForeignKeys TABLE
(
 TableName SYSNAME NOT NULL,
 ForeignKeyName SYSNAME NOT NULL
);
INSERT @RequiredAgentForeignKeys(TableName,ForeignKeyName) VALUES
 (N'BackupTransferJob',N'FK_BackupTransferJob_Agent'),
 (N'BackupAgentPeriodInventory',N'FK_BackupAgentPeriodInventory_Agent'),
 (N'BackupLookupRequest',N'FK_BackupLookupRequest_Agent');

SELECT r.TableName,r.ForeignKeyName,
 CASE WHEN EXISTS
 (
  SELECT 1
  FROM sys.foreign_keys fk
  JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id=fk.object_id
  JOIN sys.columns pc ON pc.object_id=fkc.parent_object_id AND pc.column_id=fkc.parent_column_id
  JOIN sys.columns rc ON rc.object_id=fkc.referenced_object_id AND rc.column_id=fkc.referenced_column_id
  WHERE fk.parent_object_id=OBJECT_ID(N'dbo.'+r.TableName)
    AND fk.name=r.ForeignKeyName
    AND fk.referenced_object_id=OBJECT_ID(N'dbo.BackupAgentNode')
    AND pc.name=N'AgentId' AND rc.name=N'AgentId'
 ) THEN 'OK' ELSE 'MISSING' END AS RelationStatus
FROM @RequiredAgentForeignKeys r;

IF EXISTS
(
 SELECT 1 FROM @RequiredAgentForeignKeys r
 WHERE NOT EXISTS
 (
  SELECT 1
  FROM sys.foreign_keys fk
  JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id=fk.object_id
  JOIN sys.columns pc ON pc.object_id=fkc.parent_object_id AND pc.column_id=fkc.parent_column_id
  JOIN sys.columns rc ON rc.object_id=fkc.referenced_object_id AND rc.column_id=fkc.referenced_column_id
  WHERE fk.parent_object_id=OBJECT_ID(N'dbo.'+r.TableName)
    AND fk.name=r.ForeignKeyName
    AND fk.referenced_object_id=OBJECT_ID(N'dbo.BackupAgentNode')
    AND pc.name=N'AgentId' AND rc.name=N'AgentId'
 )
)
 THROW 51294,'Relasi AgentId belum lengkap. Periksa hasil verifikasi relasi.',1;

IF COL_LENGTH(N'dbo.BackupTransferJob',N'AgentName') IS NOT NULL
 OR COL_LENGTH(N'dbo.BackupAgentPeriodInventory',N'AgentName') IS NOT NULL
 OR COL_LENGTH(N'dbo.BackupLookupRequest',N'AgentName') IS NOT NULL
 THROW 51295,'Kolom relasi AgentName lama masih tersedia pada tabel operasional.',1;
GO
