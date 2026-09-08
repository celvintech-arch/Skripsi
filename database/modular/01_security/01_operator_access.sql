/*
 Fungsi: Membuat prosedur pengelolaan dan pemeriksaan akses operator.
 Script kanonik aktif untuk fungsi ini.
*/

USE [dec_dummy];
GO
SET XACT_ABORT ON;
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
