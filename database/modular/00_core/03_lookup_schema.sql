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
  AgentName NVARCHAR(128) NOT NULL,
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
  CONSTRAINT FK_BackupLookupRequest_Agent FOREIGN KEY(AgentName) REFERENCES dbo.BackupAgentNode(AgentName),
  CONSTRAINT CK_BackupLookupRequest_QueryType CHECK(QueryType IN('PERIODS','SEARCH')),
  CONSTRAINT CK_BackupLookupRequest_Status CHECK(Status IN('WAITING','CLAIMED','SUCCESS','FAILED'))
 );
 CREATE INDEX IX_BackupLookupRequest_Queue ON dbo.BackupLookupRequest(AgentName,Status,CreatedAt);
END;
GO
