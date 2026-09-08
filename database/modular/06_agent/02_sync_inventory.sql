/*
 Fungsi: Menyinkronkan inventaris backup per Tahun Akademik.
 Script kanonik aktif untuk fungsi ini.
*/

USE [dec_dummy];
GO
SET XACT_ABORT ON;
GO


CREATE OR ALTER PROCEDURE dbo.sp_AgentSyncPeriodInventory @ApiKey NVARCHAR(256),@InventoryJson NVARCHAR(MAX)
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 IF ISJSON(@InventoryJson)<>1 THROW 51112,'Inventaris agent tidak valid.',1;
 DECLARE @agent NVARCHAR(128);
 SELECT @agent=AgentName FROM dbo.BackupAgentNode WHERE IsPrimary=1 AND IsEnabled=1 AND ApiKeyHash=HASHBYTES('SHA2_256',@ApiKey);
 IF @agent IS NULL THROW 51104,'Token agent tidak valid.',1;
 DECLARE @items TABLE(ThAkdk CHAR(5) PRIMARY KEY,StudentCount INT,LatestStudentCount INT);
 INSERT @items SELECT CONVERT(char(5),JSON_VALUE([value],'$.thAkdk')),CONVERT(int,JSON_VALUE([value],'$.studentCount')),CONVERT(int,JSON_VALUE([value],'$.latestStudentCount')) FROM OPENJSON(@InventoryJson) WHERE JSON_VALUE([value],'$.thAkdk') LIKE '[0-9][0-9][0-9][0-9][0-9]';
 BEGIN TRAN;
 DELETE p FROM dbo.BackupAgentPeriodInventory p WHERE p.AgentName=@agent AND NOT EXISTS(SELECT 1 FROM @items i WHERE i.ThAkdk=p.ThAkdk);
 MERGE dbo.BackupAgentPeriodInventory t USING @items s ON t.AgentName=@agent AND t.ThAkdk=s.ThAkdk
 WHEN MATCHED THEN UPDATE SET StudentCount=s.StudentCount,LatestStudentCount=s.LatestStudentCount,UpdatedAt=SYSDATETIME()
 WHEN NOT MATCHED THEN INSERT(AgentName,ThAkdk,StudentCount,LatestStudentCount) VALUES(@agent,s.ThAkdk,s.StudentCount,s.LatestStudentCount);
 COMMIT;
END;
GO
