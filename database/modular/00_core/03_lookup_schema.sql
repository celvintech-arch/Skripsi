/*
 Fungsi: Membuat tabel antrean lookup backup.
 Script kanonik aktif untuk fungsi ini.
*/

USE [dec_dummy];
GO
SET XACT_ABORT ON;
GO

IF OBJECT_ID('dbo.BackupLookupRequest','U') IS NULL
BEGIN
 CREATE TABLE dbo.BackupLookupRequest(
  LookupId UNIQUEIDENTIFIER NOT NULL CONSTRAINT PK_BackupLookupRequest PRIMARY KEY DEFAULT NEWID(),
  AgentId UNIQUEIDENTIFIER NOT NULL,
  QueryType VARCHAR(10) NOT NULL,
  SearchKeyword NVARCHAR(100) NULL,
  FilterYear CHAR(4) NULL,
  RequestedBy VARCHAR(50) NOT NULL,
  Status VARCHAR(20) NOT NULL CONSTRAINT DF_BackupLookupRequest_Status DEFAULT('WAITING'),
  ResultJson NVARCHAR(MAX) NULL,
  ErrorMessage NVARCHAR(1000) NULL,
  LeaseExpiresAt DATETIME2(0) NULL,
  CreatedAt DATETIME2(0) NOT NULL CONSTRAINT DF_BackupLookupRequest_CreatedAt DEFAULT SYSDATETIME(),
  CompletedAt DATETIME2(0) NULL,
  ExpiresAt DATETIME2(0) NOT NULL CONSTRAINT DF_BackupLookupRequest_ExpiresAt DEFAULT DATEADD(MINUTE,15,SYSDATETIME()),
  CONSTRAINT FK_BackupLookupRequest_Agent FOREIGN KEY(AgentId) REFERENCES dbo.BackupAgentNode(AgentId),
  CONSTRAINT CK_BackupLookupRequest_QueryType CHECK(QueryType IN('PERIODS','SEARCH')),
  CONSTRAINT CK_BackupLookupRequest_Status CHECK(Status IN('WAITING','CLAIMED','SUCCESS','FAILED'))
 );
 CREATE INDEX IX_BackupLookupRequest_Queue ON dbo.BackupLookupRequest(AgentId,Status,CreatedAt);
END;
GO

/* Migrasi instalasi lama dari AgentName ke AgentId tanpa kehilangan antrean lookup. */
IF COL_LENGTH(N'dbo.BackupLookupRequest',N'AgentId') IS NULL
 ALTER TABLE dbo.BackupLookupRequest ADD AgentId UNIQUEIDENTIFIER NULL;
GO
IF COL_LENGTH(N'dbo.BackupLookupRequest',N'AgentName') IS NOT NULL
BEGIN
 EXEC sys.sp_executesql N'
  UPDATE q SET AgentId=a.AgentId
  FROM dbo.BackupLookupRequest q
  JOIN dbo.BackupAgentNode a ON a.AgentName=q.AgentName;';
END;
GO
IF EXISTS(SELECT 1 FROM dbo.BackupLookupRequest WHERE AgentId IS NULL)
 THROW 51293,'Migrasi BackupLookupRequest gagal karena terdapat AgentName yang tidak terdaftar.',1;
ALTER TABLE dbo.BackupLookupRequest ALTER COLUMN AgentId UNIQUEIDENTIFIER NOT NULL;
GO
IF EXISTS(SELECT 1 FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID(N'dbo.BackupLookupRequest') AND name=N'FK_BackupLookupRequest_Agent')
 ALTER TABLE dbo.BackupLookupRequest DROP CONSTRAINT FK_BackupLookupRequest_Agent;
GO
IF EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'dbo.BackupLookupRequest') AND name=N'IX_BackupLookupRequest_Queue')
 DROP INDEX IX_BackupLookupRequest_Queue ON dbo.BackupLookupRequest;
GO
IF COL_LENGTH(N'dbo.BackupLookupRequest',N'AgentName') IS NOT NULL
 ALTER TABLE dbo.BackupLookupRequest DROP COLUMN AgentName;
GO
IF NOT EXISTS(SELECT 1 FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID(N'dbo.BackupLookupRequest') AND name=N'FK_BackupLookupRequest_Agent')
 ALTER TABLE dbo.BackupLookupRequest WITH CHECK ADD CONSTRAINT FK_BackupLookupRequest_Agent
  FOREIGN KEY(AgentId) REFERENCES dbo.BackupAgentNode(AgentId);
GO
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'dbo.BackupLookupRequest') AND name=N'IX_BackupLookupRequest_Queue')
 CREATE INDEX IX_BackupLookupRequest_Queue ON dbo.BackupLookupRequest(AgentId,Status,CreatedAt);
GO
