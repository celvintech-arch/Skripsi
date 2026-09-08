/*
 Fungsi: Mengambil satu job dan memulihkan lease yang kedaluwarsa.
 Script kanonik aktif untuk fungsi ini.
*/

USE [dec_dummy];
GO
SET XACT_ABORT ON;
GO

CREATE OR ALTER PROCEDURE dbo.sp_AgentClaimBackupTransferJob @ApiKey NVARCHAR(256),@LeaseMinutes INT=5
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 DECLARE @agent NVARCHAR(128),@job UNIQUEIDENTIFIER;
 SELECT @agent=AgentName FROM dbo.BackupAgentNode WHERE IsPrimary=1 AND IsEnabled=1 AND ApiKeyHash=HASHBYTES('SHA2_256',@ApiKey);
 IF @agent IS NULL THROW 51104,'Token agent tidak valid.',1;
 BEGIN TRAN;
 UPDATE dbo.BackupTransferJob SET Status=CASE WHEN RetryCount>=5 THEN 'FAILED' ELSE 'WAITING' END,
  RetryCount=RetryCount+1,LeaseExpiresAt=NULL,ProgressMessage=CASE WHEN RetryCount>=5 THEN NULL ELSE 'Menunggu Database Backup' END,ResultMessage=NULL,ErrorMessage=CASE WHEN RetryCount>=5 THEN 'Batas retry agent terlampaui.' ELSE NULL END,
  CompletedAt=CASE WHEN RetryCount>=5 THEN SYSDATETIME() ELSE CompletedAt END
 WHERE AgentName=@agent AND Status IN('CLAIMED','TRANSFERRING') AND LeaseExpiresAt<SYSDATETIME();
 SELECT TOP(1) @job=JobId FROM dbo.BackupTransferJob WITH(UPDLOCK,READPAST)
 WHERE AgentName=@agent AND Status='WAITING' ORDER BY CreatedAt,JobId;
 IF @job IS NOT NULL UPDATE dbo.BackupTransferJob SET Status='CLAIMED',StartedAt=COALESCE(StartedAt,SYSDATETIME()),LeaseExpiresAt=DATEADD(MINUTE,@LeaseMinutes,SYSDATETIME()) WHERE JobId=@job;
 COMMIT;
 SELECT JobId,OperationType,CutoffThAkdk,StudentNim,RestoreThAkdkList,SelectedTables,LastProgressNim,RetryCount,
  (SELECT COUNT(*) FROM dbo.BackupTransferJobStudent s WHERE s.JobId=j.JobId) TargetStudents
 FROM dbo.BackupTransferJob j WHERE JobId=@job;
END;
GO
