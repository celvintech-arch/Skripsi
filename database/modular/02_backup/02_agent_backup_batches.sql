/*
 Fungsi: Mengambil dan mengonfirmasi batch backup, termasuk tkrs06.
 Script kanonik aktif untuk fungsi ini.
*/

USE [dec_dummy];
GO
SET XACT_ABORT ON;
GO


CREATE OR ALTER PROCEDURE dbo.sp_AgentGetBackupBatch @ApiKey NVARCHAR(256),@JobId UNIQUEIDENTIFIER,@BatchSize INT=1000
AS
BEGIN
 SET NOCOUNT ON;
 IF @BatchSize NOT BETWEEN 1 AND 1000 THROW 51110,'Ukuran batch tidak valid.',1;
 IF NOT EXISTS(SELECT 1 FROM dbo.BackupTransferJob j JOIN dbo.BackupAgentNode a ON a.AgentName=j.AgentName
  WHERE j.JobId=@JobId AND j.OperationType='BACKUP' AND j.Status IN('CLAIMED','TRANSFERRING') AND a.IsPrimary=1 AND a.IsEnabled=1 AND a.ApiKeyHash=HASHBYTES('SHA2_256',@ApiKey)) THROW 51104,'Job atau token tidak valid.',1;
 UPDATE dbo.BackupTransferJob SET Status='TRANSFERRING',LeaseExpiresAt=DATEADD(MINUTE,5,SYSDATETIME()) WHERE JobId=@JobId;
 SELECT TOP(@BatchSize) Nim1 FROM dbo.BackupTransferJobStudent WHERE JobId=@JobId AND Status='PENDING' ORDER BY Nim1;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_AgentConfirmBackupBatch @ApiKey NVARCHAR(256),@JobId UNIQUEIDENTIFIER,@NimsJson NVARCHAR(MAX)
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 IF ISJSON(@NimsJson)<>1 THROW 51111,'Daftar mahasiswa tidak valid.',1;
 BEGIN TRAN;
 IF NOT EXISTS(SELECT 1 FROM dbo.BackupTransferJob j JOIN dbo.BackupAgentNode a ON a.AgentName=j.AgentName
  WHERE j.JobId=@JobId AND j.OperationType='BACKUP' AND j.Status IN('CLAIMED','TRANSFERRING') AND a.IsPrimary=1 AND a.IsEnabled=1 AND a.ApiKeyHash=HASHBYTES('SHA2_256',@ApiKey)) BEGIN ROLLBACK; THROW 51104,'Job atau token tidak valid.',1; END;
 ;WITH n AS(SELECT DISTINCT CONVERT(char(9),[value]) Nim1 FROM OPENJSON(@NimsJson) WHERE LEN(CONVERT(varchar(30),[value]))=9)
 UPDATE s SET Status='COPIED' FROM dbo.BackupTransferJobStudent s JOIN n ON n.Nim1=s.Nim1 WHERE s.JobId=@JobId AND s.Status='PENDING';
 UPDATE dbo.BackupTransferJob SET Status='TRANSFERRING',LeaseExpiresAt=DATEADD(MINUTE,5,SYSDATETIME()),ProcessedStudents=(SELECT COUNT(*) FROM dbo.BackupTransferJobStudent WHERE JobId=@JobId AND Status='COPIED') WHERE JobId=@JobId;
 IF NOT EXISTS(SELECT 1 FROM dbo.BackupTransferJobStudent WHERE JobId=@JobId AND Status='PENDING')
 BEGIN
   UPDATE dbo.BackupTransferJob SET Status='SUCCESS',CompletedAt=SYSDATETIME(),LeaseExpiresAt=NULL,ProgressMessage=NULL,ResultMessage=COALESCE(ResultMessage,CONCAT(ProcessedStudents,' Data Mahasiswa Berhasil Dibackup')),ErrorMessage=NULL WHERE JobId=@JobId;
 END;
 COMMIT;
 SELECT Status,ProcessedStudents CopiedStudents,(SELECT COUNT(*) FROM dbo.BackupTransferJobStudent WHERE JobId=@JobId AND Status='PENDING') PendingStudents FROM dbo.BackupTransferJob WHERE JobId=@JobId;
END;
GO
