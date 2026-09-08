/*
 Fungsi: Mendaftarkan satu primary agent dan menerima heartbeat bertoken.
 Script kanonik aktif untuk fungsi ini.
*/

USE [dec_dummy];
GO
SET XACT_ABORT ON;
GO

CREATE OR ALTER PROCEDURE dbo.sp_RegisterPrimaryBackupAgent
    @AgentName NVARCHAR(128), @ApiKey NVARCHAR(256)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF LEN(@ApiKey)<32 THROW 51101,'ApiKey minimal 32 karakter.',1;
    BEGIN TRAN;
    UPDATE dbo.BackupAgentNode SET IsPrimary=0,IsEnabled=0,UpdatedAt=SYSDATETIME() WHERE AgentName<>LTRIM(RTRIM(@AgentName));
    MERGE dbo.BackupAgentNode AS t
    USING(SELECT LTRIM(RTRIM(@AgentName)) AgentName) AS s ON t.AgentName=s.AgentName
    WHEN MATCHED THEN UPDATE SET ApiKeyHash=HASHBYTES('SHA2_256',@ApiKey),IsPrimary=1,IsEnabled=1,UpdatedAt=SYSDATETIME()
    WHEN NOT MATCHED THEN INSERT(AgentName,ApiKeyHash,IsPrimary,IsEnabled)
         VALUES(s.AgentName,HASHBYTES('SHA2_256',@ApiKey),1,1);
    COMMIT;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_AgentHeartbeat
    @ApiKey NVARCHAR(256), @DatabaseReady BIT, @Message NVARCHAR(500)=NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.BackupAgentNode
       SET LastSeenAt=SYSDATETIME(),LastDatabaseReady=@DatabaseReady,LastMessage=@Message,UpdatedAt=SYSDATETIME()
     WHERE IsPrimary=1 AND IsEnabled=1 AND ApiKeyHash=HASHBYTES('SHA2_256',@ApiKey);
    IF @@ROWCOUNT<>1 THROW 51104,'Token agent tidak terdaftar atau sudah dinonaktifkan.',1;
    SELECT AgentName,LastSeenAt,LastDatabaseReady FROM dbo.BackupAgentNode WHERE IsPrimary=1 AND IsEnabled=1;
END;
GO
