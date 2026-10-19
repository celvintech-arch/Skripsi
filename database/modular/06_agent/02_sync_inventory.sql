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
 DECLARE @agent UNIQUEIDENTIFIER;
 SELECT @agent=AgentId FROM dbo.BackupAgentNode WHERE IsPrimary=1 AND IsEnabled=1 AND ApiKeyHash=HASHBYTES('SHA2_256',@ApiKey);
 IF @agent IS NULL THROW 51104,'Token agent tidak valid.',1;
 DECLARE @items TABLE(ThAkdk CHAR(5) PRIMARY KEY,StudentCount INT,LatestStudentCount INT);
 INSERT @items SELECT CONVERT(char(5),JSON_VALUE([value],'$.thAkdk')),CONVERT(int,JSON_VALUE([value],'$.studentCount')),CONVERT(int,JSON_VALUE([value],'$.latestStudentCount')) FROM OPENJSON(@InventoryJson) WHERE JSON_VALUE([value],'$.thAkdk') LIKE '[0-9][0-9][0-9][0-9][0-9]';
 BEGIN TRAN;
 DELETE p FROM dbo.BackupAgentPeriodInventory p WHERE p.AgentId=@agent AND NOT EXISTS(SELECT 1 FROM @items i WHERE i.ThAkdk=p.ThAkdk);
 MERGE dbo.BackupAgentPeriodInventory t USING @items s ON t.AgentId=@agent AND t.ThAkdk=s.ThAkdk
 WHEN MATCHED THEN UPDATE SET StudentCount=s.StudentCount,LatestStudentCount=s.LatestStudentCount,UpdatedAt=SYSDATETIME()
 WHEN NOT MATCHED THEN INSERT(AgentId,ThAkdk,StudentCount,LatestStudentCount) VALUES(@agent,s.ThAkdk,s.StudentCount,s.LatestStudentCount);

 -- Hitung verifikasi data aktif (live) vs data backup untuk periode bersangkutan
 ;WITH LiveAcademicRows AS (
  SELECT r.th_akdk, r.nim1 FROM dbo.treg r JOIN @items i ON i.ThAkdk = r.th_akdk
  UNION
  SELECT k.th_akdk, k.nim1 FROM dbo.tkrs06 k JOIN @items i ON i.ThAkdk = k.th_akdk
  UNION
  SELECT a.th_akdk, a.nim1 FROM dbo.t_absensi14 a JOIN @items i ON i.ThAkdk = a.th_akdk
 ),
 LiveCounts AS (
  SELECT a.th_akdk, COUNT(DISTINCT a.nim1) AS LiveCount
  FROM LiveAcademicRows a
  JOIN dbo.tbio01 b ON b.nim1 = a.nim1
  GROUP BY a.th_akdk
 )
 UPDATE p
 SET 
  p.LiveStudentCount = ISNULL(l.LiveCount, 0),
  p.VerificationStatus = CASE 
   WHEN p.StudentCount = ISNULL(l.LiveCount, 0) THEN 'VERIFIED' 
   WHEN ISNULL(l.LiveCount, 0) = 0 AND p.StudentCount > 0 THEN 'ARCHIVED'
   ELSE 'MISMATCH' 
  END,
  p.VerifiedAt = SYSDATETIME()
 FROM dbo.BackupAgentPeriodInventory p
 LEFT JOIN LiveCounts l ON l.th_akdk = p.ThAkdk
 WHERE p.AgentId = @agent;

 COMMIT;
END;
GO
