/*
 Fungsi: Mengonfirmasi batch pemulihan secara idempotent.
 Script kanonik aktif untuk fungsi ini.
*/

USE [dec_dummy];
GO
SET XACT_ABORT ON;
GO


CREATE OR ALTER PROCEDURE dbo.sp_AgentConfirmRestoreBatch @ApiKey NVARCHAR(256),@JobId UNIQUEIDENTIFIER,@NimsJson NVARCHAR(MAX),@LastNim CHAR(9)
AS
BEGIN
 SET NOCOUNT ON;
 IF NOT EXISTS(SELECT 1 FROM dbo.BackupTransferJob j JOIN dbo.BackupAgentNode a ON a.AgentName=j.AgentName WHERE j.JobId=@JobId AND j.OperationType='RESTORE' AND j.Status IN('CLAIMED','TRANSFERRING') AND a.IsPrimary=1 AND a.IsEnabled=1 AND a.ApiKeyHash=HASHBYTES('SHA2_256',@ApiKey)) THROW 51104,'Job atau token tidak valid.',1;
 ;WITH n AS(SELECT DISTINCT CONVERT(char(9),[value]) Nim1 FROM OPENJSON(@NimsJson) WHERE LEN(CONVERT(varchar(30),[value]))=9)
 MERGE dbo.BackupTransferJobStudent t USING n s ON t.JobId=@JobId AND t.Nim1=s.Nim1
 WHEN MATCHED THEN UPDATE SET Status='RESTORED'
 WHEN NOT MATCHED THEN INSERT(JobId,Nim1,Status) VALUES(@JobId,s.Nim1,'RESTORED');
 UPDATE dbo.BackupTransferJob SET Status='TRANSFERRING',LastProgressNim=@LastNim,ProcessedStudents=(SELECT COUNT(*) FROM dbo.BackupTransferJobStudent WHERE JobId=@JobId AND Status='RESTORED'),LeaseExpiresAt=DATEADD(MINUTE,5,SYSDATETIME()) WHERE JobId=@JobId;
 SELECT LastProgressNim,ProcessedStudents FROM dbo.BackupTransferJob WHERE JobId=@JobId;
END;
GO

