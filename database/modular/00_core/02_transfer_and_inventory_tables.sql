/*
 Fungsi: Membuat tabel antrean, detail mahasiswa, dan inventaris backup.
 Script kanonik untuk instalasi baru.
*/

USE [dec_dummy];
GO

SET XACT_ABORT ON;
GO

IF OBJECT_ID(N'dbo.BackupTransferJob', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.BackupTransferJob
    (
        JobId UNIQUEIDENTIFIER NOT NULL CONSTRAINT PK_BackupTransferJob PRIMARY KEY DEFAULT NEWID(),
        AgentName NVARCHAR(128) NOT NULL,
        OperationType VARCHAR(10) NOT NULL,
        TriggerSource VARCHAR(10) NOT NULL CONSTRAINT DF_BackupTransferJob_Trigger DEFAULT('MANUAL'),
        CutoffThAkdk CHAR(5) NULL,
        StudentNim CHAR(9) NULL,
        RestoreThAkdkList NVARCHAR(MAX) NULL,
        SelectedTables VARCHAR(100) NOT NULL CONSTRAINT DF_BackupTransferJob_SelectedTables DEFAULT('tbio01,treg,tkrs06,t_absensi14'),
        RequestedBy VARCHAR(50) NOT NULL,
        Status VARCHAR(20) NOT NULL CONSTRAINT DF_BackupTransferJob_Status DEFAULT('WAITING'),
        LeaseExpiresAt DATETIME2(0) NULL,
        RetryCount INT NOT NULL CONSTRAINT DF_BackupTransferJob_Retry DEFAULT(0),
        LastProgressNim CHAR(9) NULL,
        ProcessedStudents INT NOT NULL CONSTRAINT DF_BackupTransferJob_Processed DEFAULT(0),
        TotalStudents INT NULL,
        ProgressMessage NVARCHAR(2000) NULL,
        ResultMessage NVARCHAR(2000) NULL,
        ErrorMessage NVARCHAR(2000) NULL,
        CreatedAt DATETIME2(0) NOT NULL CONSTRAINT DF_BackupTransferJob_CreatedAt DEFAULT SYSDATETIME(),
        StartedAt DATETIME2(0) NULL,
        CompletedAt DATETIME2(0) NULL,
        CONSTRAINT FK_BackupTransferJob_Agent FOREIGN KEY(AgentName) REFERENCES dbo.BackupAgentNode(AgentName),
        CONSTRAINT CK_BackupTransferJob_Operation CHECK(OperationType IN('BACKUP','RESTORE','EXPORT')),
        CONSTRAINT CK_BackupTransferJob_Trigger CHECK(TriggerSource IN('MANUAL','SCHEDULED')),
        CONSTRAINT CK_BackupTransferJob_Status CHECK(Status IN('WAITING','CLAIMED','TRANSFERRING','SUCCESS','FAILED'))
    );
END;
GO

IF COL_LENGTH(N'dbo.BackupTransferJob',N'SelectedTables') IS NULL
BEGIN
    ALTER TABLE dbo.BackupTransferJob ADD SelectedTables VARCHAR(100) NOT NULL
        CONSTRAINT DF_BackupTransferJob_SelectedTables DEFAULT('tbio01,treg,tkrs06,t_absensi14') WITH VALUES;
END;
GO

IF OBJECT_ID(N'dbo.BackupTransferJobStudent', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.BackupTransferJobStudent
    (
        JobId UNIQUEIDENTIFIER NOT NULL,
        Nim1 CHAR(9) NOT NULL,
        Status VARCHAR(20) NOT NULL CONSTRAINT DF_BackupTransferJobStudent_Status DEFAULT('PENDING'),
        CONSTRAINT PK_BackupTransferJobStudent PRIMARY KEY(JobId,Nim1),
        CONSTRAINT FK_BackupTransferJobStudent_Job FOREIGN KEY(JobId) REFERENCES dbo.BackupTransferJob(JobId),
        CONSTRAINT CK_BackupTransferJobStudent_Status CHECK(Status IN('PENDING','COPIED','RESTORED','SKIPPED'))
    );
END;
GO

IF OBJECT_ID(N'dbo.BackupAgentPeriodInventory', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.BackupAgentPeriodInventory
    (
        AgentName NVARCHAR(128) NOT NULL,
        ThAkdk CHAR(5) NOT NULL,
        StudentCount INT NOT NULL,
        LatestStudentCount INT NULL,
        UpdatedAt DATETIME2(0) NOT NULL CONSTRAINT DF_BackupAgentPeriodInventory_UpdatedAt DEFAULT SYSDATETIME(),
        CONSTRAINT PK_BackupAgentPeriodInventory PRIMARY KEY(AgentName,ThAkdk),
        CONSTRAINT FK_BackupAgentPeriodInventory_Agent FOREIGN KEY(AgentName) REFERENCES dbo.BackupAgentNode(AgentName)
    );
END;
GO
