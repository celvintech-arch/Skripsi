/*
 Fungsi: Membuat antrean ekspor database backup.
 Script kanonik aktif untuk fungsi ini.
*/

USE [dec_dummy];
GO
SET XACT_ABORT ON;
GO


CREATE OR ALTER PROCEDURE dbo.sp_CreateBackupExportJob @RequestedBy VARCHAR(50)
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 DECLARE @agent NVARCHAR(128),@job UNIQUEIDENTIFIER=NEWID();
 SELECT @agent=AgentName FROM dbo.BackupAgentNode WHERE IsPrimary=1 AND IsEnabled=1;
 IF @agent IS NULL THROW 51103,'Node backup utama belum didaftarkan.',1;
 BEGIN TRAN;
 IF EXISTS(SELECT 1 FROM dbo.BackupTransferJob WITH(UPDLOCK,HOLDLOCK) WHERE OperationType='EXPORT' AND Status IN('WAITING','CLAIMED','TRANSFERRING'))
 BEGIN ROLLBACK; THROW 51140,'Masih ada ekspor database yang aktif atau menunggu.',1; END;
 INSERT dbo.BackupTransferJob(JobId,AgentName,OperationType,TriggerSource,RequestedBy,Status,ProgressMessage)
 VALUES(@job,@agent,'EXPORT','MANUAL',@RequestedBy,'WAITING','Menunggu Database Backup');
 COMMIT;
 SELECT @job JobId,'WAITING' Status;
END;
GO
