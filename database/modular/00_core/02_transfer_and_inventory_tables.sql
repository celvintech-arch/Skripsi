/*
 Fungsi: Membuat tabel antrean, detail mahasiswa, dan inventaris backup.
 Script kanonik untuk instalasi baru dan migrasi relasi agent lama.
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
        AgentId UNIQUEIDENTIFIER NOT NULL,
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
        CONSTRAINT FK_BackupTransferJob_Agent FOREIGN KEY(AgentId) REFERENCES dbo.BackupAgentNode(AgentId),
        CONSTRAINT CK_BackupTransferJob_Operation CHECK(OperationType IN('BACKUP','RESTORE','EXPORT')),
        CONSTRAINT CK_BackupTransferJob_Trigger CHECK(TriggerSource IN('MANUAL','SCHEDULED')),
        CONSTRAINT CK_BackupTransferJob_Status CHECK(Status IN('WAITING','CLAIMED','TRANSFERRING','SUCCESS','FAILED'))
    );
END;
GO

/* Migrasi instalasi lama: petakan AgentName ke AgentId sebelum mengganti FK. */
IF COL_LENGTH(N'dbo.BackupTransferJob',N'AgentId') IS NULL
    ALTER TABLE dbo.BackupTransferJob ADD AgentId UNIQUEIDENTIFIER NULL;
GO
IF COL_LENGTH(N'dbo.BackupTransferJob',N'AgentName') IS NOT NULL
BEGIN
    EXEC sys.sp_executesql N'
        UPDATE j SET AgentId=a.AgentId
        FROM dbo.BackupTransferJob j
        JOIN dbo.BackupAgentNode a ON a.AgentName=j.AgentName;';
END;
GO
IF EXISTS(SELECT 1 FROM dbo.BackupTransferJob WHERE AgentId IS NULL)
    THROW 51291,'Migrasi BackupTransferJob gagal karena terdapat AgentName yang tidak terdaftar.',1;
ALTER TABLE dbo.BackupTransferJob ALTER COLUMN AgentId UNIQUEIDENTIFIER NOT NULL;
GO

IF EXISTS(SELECT 1 FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID(N'dbo.BackupTransferJob') AND name=N'FK_BackupTransferJob_Agent')
    ALTER TABLE dbo.BackupTransferJob DROP CONSTRAINT FK_BackupTransferJob_Agent;
GO
IF NOT EXISTS(SELECT 1 FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID(N'dbo.BackupTransferJob') AND name=N'FK_BackupTransferJob_Agent')
    ALTER TABLE dbo.BackupTransferJob WITH CHECK ADD CONSTRAINT FK_BackupTransferJob_Agent
        FOREIGN KEY(AgentId) REFERENCES dbo.BackupAgentNode(AgentId);
GO
IF COL_LENGTH(N'dbo.BackupTransferJob',N'AgentName') IS NOT NULL
    ALTER TABLE dbo.BackupTransferJob DROP COLUMN AgentName;
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
        AgentId UNIQUEIDENTIFIER NOT NULL,
        ThAkdk CHAR(5) NOT NULL,
        StudentCount INT NOT NULL,
        LatestStudentCount INT NULL,
        UpdatedAt DATETIME2(0) NOT NULL CONSTRAINT DF_BackupAgentPeriodInventory_UpdatedAt DEFAULT SYSDATETIME(),
        CONSTRAINT PK_BackupAgentPeriodInventory PRIMARY KEY(AgentId,ThAkdk),
        CONSTRAINT FK_BackupAgentPeriodInventory_Agent FOREIGN KEY(AgentId) REFERENCES dbo.BackupAgentNode(AgentId)
    );
END;
GO

/* Migrasi primary key inventaris dari AgentName ke AgentId. */
IF COL_LENGTH(N'dbo.BackupAgentPeriodInventory',N'AgentId') IS NULL
    ALTER TABLE dbo.BackupAgentPeriodInventory ADD AgentId UNIQUEIDENTIFIER NULL;
GO
IF COL_LENGTH(N'dbo.BackupAgentPeriodInventory',N'AgentName') IS NOT NULL
BEGIN
    EXEC sys.sp_executesql N'
        UPDATE p SET AgentId=a.AgentId
        FROM dbo.BackupAgentPeriodInventory p
        JOIN dbo.BackupAgentNode a ON a.AgentName=p.AgentName;';
END;
GO
IF EXISTS(SELECT 1 FROM dbo.BackupAgentPeriodInventory WHERE AgentId IS NULL)
    THROW 51292,'Migrasi BackupAgentPeriodInventory gagal karena terdapat AgentName yang tidak terdaftar.',1;
ALTER TABLE dbo.BackupAgentPeriodInventory ALTER COLUMN AgentId UNIQUEIDENTIFIER NOT NULL;
GO

IF EXISTS(SELECT 1 FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID(N'dbo.BackupAgentPeriodInventory') AND name=N'FK_BackupAgentPeriodInventory_Agent')
    ALTER TABLE dbo.BackupAgentPeriodInventory DROP CONSTRAINT FK_BackupAgentPeriodInventory_Agent;
GO
IF COL_LENGTH(N'dbo.BackupAgentPeriodInventory',N'AgentName') IS NOT NULL
BEGIN
    IF EXISTS(SELECT 1 FROM sys.key_constraints WHERE parent_object_id=OBJECT_ID(N'dbo.BackupAgentPeriodInventory') AND name=N'PK_BackupAgentPeriodInventory')
        ALTER TABLE dbo.BackupAgentPeriodInventory DROP CONSTRAINT PK_BackupAgentPeriodInventory;
    ALTER TABLE dbo.BackupAgentPeriodInventory DROP COLUMN AgentName;
END;
GO
IF NOT EXISTS(SELECT 1 FROM sys.key_constraints WHERE parent_object_id=OBJECT_ID(N'dbo.BackupAgentPeriodInventory') AND name=N'PK_BackupAgentPeriodInventory')
    ALTER TABLE dbo.BackupAgentPeriodInventory ADD CONSTRAINT PK_BackupAgentPeriodInventory PRIMARY KEY(AgentId,ThAkdk);
GO
IF NOT EXISTS(SELECT 1 FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID(N'dbo.BackupAgentPeriodInventory') AND name=N'FK_BackupAgentPeriodInventory_Agent')
    ALTER TABLE dbo.BackupAgentPeriodInventory WITH CHECK ADD CONSTRAINT FK_BackupAgentPeriodInventory_Agent
        FOREIGN KEY(AgentId) REFERENCES dbo.BackupAgentNode(AgentId);
GO

/* Kolom verifikasi data aktif vs backup per periode */
IF COL_LENGTH(N'dbo.BackupAgentPeriodInventory', N'LiveStudentCount') IS NULL
    ALTER TABLE dbo.BackupAgentPeriodInventory ADD LiveStudentCount INT NULL;
GO
IF COL_LENGTH(N'dbo.BackupAgentPeriodInventory', N'VerificationStatus') IS NULL
    ALTER TABLE dbo.BackupAgentPeriodInventory ADD VerificationStatus VARCHAR(20) NULL CONSTRAINT DF_BackupAgentPeriodInventory_Status DEFAULT 'UNVERIFIED';
GO
IF COL_LENGTH(N'dbo.BackupAgentPeriodInventory', N'VerifiedAt') IS NULL
    ALTER TABLE dbo.BackupAgentPeriodInventory ADD VerifiedAt DATETIME2 NULL;
GO

