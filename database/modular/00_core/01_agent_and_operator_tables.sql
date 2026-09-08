/*
 Fungsi: Membuat tabel identitas agent dan allowlist operator.
 Script kanonik aktif untuk fungsi ini.
*/

USE [dec_dummy];
GO
SET XACT_ABORT ON;
GO

IF OBJECT_ID('dbo.BackupAgentNode','U') IS NULL
BEGIN
    CREATE TABLE dbo.BackupAgentNode(
        AgentId UNIQUEIDENTIFIER NOT NULL CONSTRAINT PK_BackupAgentNode PRIMARY KEY DEFAULT NEWID(),
        AgentName NVARCHAR(128) NOT NULL CONSTRAINT UQ_BackupAgentNode_AgentName UNIQUE,
        ApiKeyHash VARBINARY(32) NULL,
        IsPrimary BIT NOT NULL CONSTRAINT DF_BackupAgentNode_IsPrimary DEFAULT(0),
        IsEnabled BIT NOT NULL CONSTRAINT DF_BackupAgentNode_IsEnabled DEFAULT(1),
        LastSeenAt DATETIME2(0) NULL, LastDatabaseReady BIT NULL, LastMessage NVARCHAR(500) NULL,
        CreatedAt DATETIME2(0) NOT NULL CONSTRAINT DF_BackupAgentNode_CreatedAt DEFAULT SYSDATETIME(),
        UpdatedAt DATETIME2(0) NOT NULL CONSTRAINT DF_BackupAgentNode_UpdatedAt DEFAULT SYSDATETIME()
    );
END;
GO
IF COL_LENGTH('dbo.BackupAgentNode','IsPrimary') IS NULL ALTER TABLE dbo.BackupAgentNode ADD IsPrimary BIT NOT NULL CONSTRAINT DF_BackupAgentNode_IsPrimary DEFAULT(0);
IF COL_LENGTH('dbo.BackupAgentNode','ApiKeyHash') IS NOT NULL ALTER TABLE dbo.BackupAgentNode ALTER COLUMN ApiKeyHash VARBINARY(32) NULL;
GO
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.BackupAgentNode') AND name='UX_BackupAgentNode_Primary')
    CREATE UNIQUE INDEX UX_BackupAgentNode_Primary ON dbo.BackupAgentNode(IsPrimary) WHERE IsPrimary=1;
GO

IF OBJECT_ID('dbo.BackupOperatorAccess','U') IS NULL
BEGIN
    CREATE TABLE dbo.BackupOperatorAccess(
        UserId NVARCHAR(50) NOT NULL CONSTRAINT PK_BackupOperatorAccess PRIMARY KEY,
        AccessRole VARCHAR(30) NOT NULL CONSTRAINT DF_BackupOperatorAccess_Role DEFAULT('STAFF_BACKUP'),
        IsEnabled BIT NOT NULL CONSTRAINT DF_BackupOperatorAccess_Enabled DEFAULT(1),
        CreatedAt DATETIME2(0) NOT NULL CONSTRAINT DF_BackupOperatorAccess_CreatedAt DEFAULT SYSDATETIME(),
        UpdatedAt DATETIME2(0) NOT NULL CONSTRAINT DF_BackupOperatorAccess_UpdatedAt DEFAULT SYSDATETIME(),
        CONSTRAINT CK_BackupOperatorAccess_Role CHECK(AccessRole IN('STAFF_BACKUP','MANAGER_BACKUP','ADMIN_BACKUP','ADMIN','SUPERADMIN'))
    );
END;
GO

IF EXISTS(SELECT 1 FROM sys.check_constraints WHERE parent_object_id=OBJECT_ID('dbo.BackupOperatorAccess') AND name='CK_BackupOperatorAccess_Role')
    ALTER TABLE dbo.BackupOperatorAccess DROP CONSTRAINT CK_BackupOperatorAccess_Role;
GO
ALTER TABLE dbo.BackupOperatorAccess WITH CHECK ADD CONSTRAINT CK_BackupOperatorAccess_Role
    CHECK(AccessRole IN('STAFF_BACKUP','MANAGER_BACKUP','ADMIN_BACKUP','ADMIN','SUPERADMIN'));
GO

IF EXISTS(SELECT 1 FROM sys.default_constraints WHERE parent_object_id=OBJECT_ID('dbo.BackupOperatorAccess') AND name='DF_BackupOperatorAccess_Role')
    ALTER TABLE dbo.BackupOperatorAccess DROP CONSTRAINT DF_BackupOperatorAccess_Role;
GO
ALTER TABLE dbo.BackupOperatorAccess ADD CONSTRAINT DF_BackupOperatorAccess_Role DEFAULT('STAFF_BACKUP') FOR AccessRole;
GO
