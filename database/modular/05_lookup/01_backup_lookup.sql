/*
 Fungsi: Membuat dan membaca lookup backup melalui antrean agent.
 Script kanonik aktif untuk fungsi ini.
*/

USE [dec_dummy];
GO
SET XACT_ABORT ON;
GO

CREATE OR ALTER PROCEDURE dbo.sp_CreateBackupLookupRequest
 @QueryType VARCHAR(10),@SearchKeyword NVARCHAR(100)=NULL,@FilterYear CHAR(4)=NULL,@RequestedBy VARCHAR(50)
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 SET @QueryType=UPPER(LTRIM(RTRIM(@QueryType)));
 SET @SearchKeyword=NULLIF(LTRIM(RTRIM(@SearchKeyword)),'');
 SET @FilterYear=NULLIF(LTRIM(RTRIM(@FilterYear)),'');
 IF @QueryType NOT IN('PERIODS','SEARCH') THROW 51150,'Jenis lookup backup tidak valid.',1;
 IF @FilterYear IS NOT NULL AND @FilterYear NOT LIKE '[0-9][0-9][0-9][0-9]' THROW 51151,'Filter tahun tidak valid.',1;
 IF LEN(ISNULL(@SearchKeyword,''))>100 THROW 51152,'Kata pencarian terlalu panjang.',1;
 DECLARE @agent NVARCHAR(128),@id UNIQUEIDENTIFIER;
 SELECT @agent=AgentName FROM dbo.BackupAgentNode WHERE IsPrimary=1 AND IsEnabled=1;
 IF @agent IS NULL THROW 51103,'Node backup utama belum didaftarkan.',1;
 DELETE dbo.BackupLookupRequest WHERE ExpiresAt<DATEADD(HOUR,-1,SYSDATETIME());
 SELECT TOP(1) @id=LookupId FROM dbo.BackupLookupRequest
 WHERE AgentName=@agent AND QueryType=@QueryType
  AND ISNULL(SearchKeyword,'')=ISNULL(@SearchKeyword,'') AND ISNULL(FilterYear,'')=ISNULL(@FilterYear,'')
  AND ((Status IN('WAITING','CLAIMED') AND ExpiresAt>SYSDATETIME()) OR (Status='SUCCESS' AND CompletedAt>DATEADD(MINUTE,-5,SYSDATETIME())))
 ORDER BY CreatedAt DESC;
 IF @id IS NULL
 BEGIN
  SET @id=NEWID();
  INSERT dbo.BackupLookupRequest(LookupId,AgentName,QueryType,SearchKeyword,FilterYear,RequestedBy,Status)
  VALUES(@id,@agent,@QueryType,@SearchKeyword,@FilterYear,@RequestedBy,'WAITING');
 END;
 SELECT LookupId,Status,ResultJson,ErrorMessage,SearchKeyword,FilterYear FROM dbo.BackupLookupRequest WHERE LookupId=@id;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_GetBackupLookupRequest @LookupId UNIQUEIDENTIFIER
AS
BEGIN
 SET NOCOUNT ON;
 SELECT LookupId,QueryType,Status,ResultJson,ErrorMessage,SearchKeyword,FilterYear,CreatedAt,CompletedAt,ExpiresAt
 FROM dbo.BackupLookupRequest WHERE LookupId=@LookupId AND ExpiresAt>SYSDATETIME();
END;
GO

