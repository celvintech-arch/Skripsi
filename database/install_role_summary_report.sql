/*
  MIGRATION ROLE DAN SUMMARY REPORT LINTAR

  Target   : dec_dummy
  Dampak   : tabel kontrol BackupOperatorAccess, procedure role, dan permission IIS
  Tidak melakukan backup/restore dan tidak mengubah tbio01, treg, tkrs06, atau t_absensi14.
*/

USE [dec_dummy];
GO
SET XACT_ABORT ON;
GO

IF OBJECT_ID('dbo.BackupOperatorAccess','U') IS NULL
    THROW 51300,'BackupOperatorAccess belum tersedia. Jalankan installer utama terlebih dahulu.',1;
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

CREATE OR ALTER PROCEDURE dbo.sp_SetBackupOperatorAccess
    @UserId NVARCHAR(50),
    @AccessRole VARCHAR(30)='STAFF_BACKUP',
    @IsEnabled BIT=1
AS
BEGIN
    SET NOCOUNT ON;
    SET @UserId=LTRIM(RTRIM(@UserId));
    SET @AccessRole=UPPER(LTRIM(RTRIM(@AccessRole)));
    IF @UserId='' THROW 51120,'UserId wajib diisi.',1;
    IF @AccessRole NOT IN('STAFF_BACKUP','MANAGER_BACKUP') THROW 51121,'Role backup harus STAFF_BACKUP atau MANAGER_BACKUP.',1;

    MERGE dbo.BackupOperatorAccess AS t
    USING(SELECT @UserId AS UserId) AS s ON t.UserId=s.UserId
    WHEN MATCHED THEN UPDATE SET AccessRole=@AccessRole,IsEnabled=@IsEnabled,UpdatedAt=SYSDATETIME()
    WHEN NOT MATCHED THEN INSERT(UserId,AccessRole,IsEnabled) VALUES(@UserId,@AccessRole,@IsEnabled);
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_GetBackupOperatorRole
    @UserId NVARCHAR(50)
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TOP(1)
        CASE WHEN IsEnabled=0 THEN 'DENIED_BACKUP' WHEN AccessRole='MANAGER_BACKUP' THEN 'MANAGER_BACKUP' ELSE 'STAFF_BACKUP' END AS AccessRole
    FROM dbo.BackupOperatorAccess
    WHERE UserId=LTRIM(RTRIM(@UserId));
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_CheckBackupOperatorAccess
    @UserId NVARCHAR(50)
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    SELECT CAST(CASE WHEN EXISTS(
        SELECT 1 FROM dbo.BackupOperatorAccess
        WHERE UserId=LTRIM(RTRIM(@UserId))
          AND IsEnabled=1
          AND AccessRole IN('STAFF_BACKUP','MANAGER_BACKUP','ADMIN_BACKUP','ADMIN','SUPERADMIN')
    ) THEN 1 ELSE 0 END AS BIT) AS HasAccess;
END;
GO

IF DATABASE_PRINCIPAL_ID(N'IIS APPPOOL\DefaultAppPool') IS NULL
    THROW 51301,'User database IIS APPPOOL\DefaultAppPool belum tersedia.',1;
GO
GRANT EXECUTE ON dbo.sp_CheckBackupOperatorAccess TO [IIS APPPOOL\DefaultAppPool];
GRANT EXECUTE ON dbo.sp_GetBackupOperatorRole TO [IIS APPPOOL\DefaultAppPool];
GRANT EXECUTE ON dbo.sp_SetBackupOperatorAccess TO [IIS APPPOOL\DefaultAppPool];
GRANT SELECT ON dbo.BackupOperatorAccess TO [IIS APPPOOL\DefaultAppPool];
GO

SELECT UserId,
       CASE WHEN AccessRole='MANAGER_BACKUP' THEN 'MANAGER_BACKUP' ELSE 'STAFF_BACKUP' END EffectiveRole,
       IsEnabled
FROM dbo.BackupOperatorAccess
ORDER BY IsEnabled DESC,UserId;

IF OBJECT_ID('dbo.sp_GetBackupOperatorRole','P') IS NULL
    THROW 51302,'Migration role belum lengkap.',1;
GO
