/*
  INSTALLER GABUNGAN MODUL BACKUP DATA LINTAR

  Target        : dec_dummy
  Jalankan      : melalui SSMS dengan akun yang berwenang
  Sumber        : 17 file pada scripts/modular sesuai urutan README.md

  PERHATIAN:
  1. Uji terlebih dahulu pada salinan/staging dec_dummy.
  2. Buat full backup dec_dummy sebelum menjalankan pada lingkungan aktif.
  3. Pastikan login IIS pada bagian izin sesuai Application Pool yang digunakan.
  4. Installer ini tidak membuat dec_dummy_backup, tidak mendaftarkan API key,
     dan tidak memasang SQL Server Agent job pada node backup.
  5. Jika salah satu batch gagal, hentikan eksekusi, perbaiki penyebabnya,
     lalu jalankan kembali karena objek dibuat secara idempotent.
*/

/* ========================================================================== 
   BAGIAN 01/17 : 00_core\01_agent_and_operator_tables.sql
   ========================================================================== */
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

/* ========================================================================== 
   BAGIAN 02/17 : 00_core\02_transfer_and_inventory_tables.sql
   ========================================================================== */
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

/* ========================================================================== 
   BAGIAN 03/17 : 00_core\03_lookup_schema.sql
   ========================================================================== */
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

/* ========================================================================== 
   BAGIAN 04/17 : 00_core\04_validate_source_tables.sql
   ========================================================================== */
/*
 Fungsi: Memvalidasi empat tabel sumber langsung pada database dec_dummy.
 Script ini hanya membaca metadata dan tidak membuat, mengubah, atau menghapus
 tabel maupun data akademik.
*/

USE [dec_dummy];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF DB_ID(N'dec_dummy') IS NULL
    THROW 51200, 'Database sumber dec_dummy tidak ditemukan pada SQL Server ini.', 1;

DECLARE @RequiredTables TABLE
(
    TableName SYSNAME NOT NULL PRIMARY KEY,
    RequiresAcademicYear BIT NOT NULL
);

INSERT @RequiredTables(TableName, RequiresAcademicYear)
VALUES
    (N'tbio01', 0),
    (N'treg', 1),
    (N'tkrs06', 1),
    (N't_absensi14', 1);

IF EXISTS
(
    SELECT 1
    FROM @RequiredTables r
    WHERE OBJECT_ID(N'dbo.' + r.TableName, N'U') IS NULL
)
BEGIN
    SELECT r.TableName AS MissingTable
    FROM @RequiredTables r
    WHERE OBJECT_ID(N'dbo.' + r.TableName, N'U') IS NULL;

    THROW 51201, 'Satu atau lebih tabel sumber wajib tidak ditemukan pada dec_dummy.', 1;
END;

IF EXISTS
(
    SELECT 1
    FROM @RequiredTables r
    WHERE COL_LENGTH(N'dbo.' + r.TableName, N'nim1') IS NULL
       OR (r.RequiresAcademicYear = 1 AND COL_LENGTH(N'dbo.' + r.TableName, N'th_akdk') IS NULL)
)
BEGIN
    SELECT
        r.TableName,
        CASE WHEN COL_LENGTH(N'dbo.' + r.TableName, N'nim1') IS NULL THEN 0 ELSE 1 END AS HasNim1,
        CASE WHEN r.RequiresAcademicYear = 0 OR COL_LENGTH(N'dbo.' + r.TableName, N'th_akdk') IS NOT NULL THEN 1 ELSE 0 END AS HasThAkdk
    FROM @RequiredTables r;

    THROW 51202, 'Struktur tabel sumber tidak memenuhi kolom minimum backup.', 1;
END;

SELECT
    r.TableName,
    SUM(p.rows) AS TotalRows,
    CAST(1 AS bit) AS IsReady
FROM @RequiredTables r
JOIN sys.tables t ON t.name = r.TableName AND t.schema_id = SCHEMA_ID(N'dbo')
JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0, 1)
GROUP BY r.TableName
ORDER BY r.TableName;

PRINT N'Validasi tabel sumber dec_dummy selesai. Tidak ada data yang diubah.';
GO

/* ========================================================================== 
   BAGIAN 05/17 : 01_security\01_operator_access.sql
   ========================================================================== */
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

/* ========================================================================== 
   BAGIAN 06/17 : 01_security\02_primary_agent_and_heartbeat.sql
   ========================================================================== */
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

/* ========================================================================== 
   BAGIAN 07/17 : 02_backup\01_create_backup_jobs.sql
   ========================================================================== */
/*
 Fungsi: Membuat antrean backup berdasarkan Tahun Akademik atau satu NIM.
 Script kanonik aktif untuk fungsi ini.
*/

USE [dec_dummy];
GO
SET XACT_ABORT ON;
GO

CREATE OR ALTER PROCEDURE dbo.sp_CreateBackupTransferJob
 @CutoffThAkdk CHAR(5),@RequestedBy VARCHAR(50),@TriggerSource VARCHAR(10)='MANUAL',
 @SelectionMode VARCHAR(10)='UP_TO',@StartThAkdk CHAR(5)=NULL,
 @SelectedTables VARCHAR(100)='tbio01,treg,tkrs06,t_absensi14'
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 SET @SelectionMode=UPPER(LTRIM(RTRIM(@SelectionMode))); SET @StartThAkdk=NULLIF(LTRIM(RTRIM(@StartThAkdk)),'');
 SET @SelectedTables=LOWER(REPLACE(ISNULL(NULLIF(LTRIM(RTRIM(@SelectedTables)),''),'tbio01,treg,tkrs06,t_absensi14'),' ',''));
 DECLARE @tables TABLE(TableName VARCHAR(30) PRIMARY KEY);
 INSERT @tables SELECT DISTINCT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@SelectedTables,',') WHERE LTRIM(RTRIM(value))<>'';
 IF NOT EXISTS(SELECT 1 FROM @tables) OR EXISTS(SELECT 1 FROM @tables WHERE TableName NOT IN('tbio01','treg','tkrs06','t_absensi14')) THROW 51147,'Pilihan tabel backup tidak valid.',1;
 IF NOT EXISTS(SELECT 1 FROM @tables WHERE TableName IN('treg','tkrs06','t_absensi14')) THROW 51149,'Pilih minimal satu tabel Registrasi, KRS, atau Absensi.',1;
 IF EXISTS(SELECT 1 FROM @tables WHERE TableName<>'tbio01') AND NOT EXISTS(SELECT 1 FROM @tables WHERE TableName='tbio01') INSERT @tables VALUES('tbio01');
 SET @SelectedTables='tbio01'+CASE WHEN EXISTS(SELECT 1 FROM @tables WHERE TableName='treg') THEN ',treg' ELSE '' END+CASE WHEN EXISTS(SELECT 1 FROM @tables WHERE TableName='tkrs06') THEN ',tkrs06' ELSE '' END+CASE WHEN EXISTS(SELECT 1 FROM @tables WHERE TableName='t_absensi14') THEN ',t_absensi14' ELSE '' END;
 IF @CutoffThAkdk NOT LIKE '[0-9][0-9][0-9][0-9][0-9]' THROW 51105,'TA akhir atau batas harus lima digit.',1;
 IF @TriggerSource NOT IN('MANUAL','SCHEDULED') THROW 51106,'TriggerSource tidak valid.',1;
 IF @SelectionMode NOT IN('SINGLE','RANGE','UP_TO') THROW 51145,'Cakupan backup tidak valid.',1;
 IF @SelectionMode='RANGE' AND (@StartThAkdk IS NULL OR @StartThAkdk NOT LIKE '[0-9][0-9][0-9][0-9][0-9]') THROW 51146,'TA awal rentang harus lima digit.',1;
 IF @SelectionMode='RANGE' AND @StartThAkdk>@CutoffThAkdk BEGIN DECLARE @swap CHAR(5)=@StartThAkdk;SET @StartThAkdk=@CutoffThAkdk;SET @CutoffThAkdk=@swap;END;
 DECLARE @agent NVARCHAR(128),@job UNIQUEIDENTIFIER=NEWID(),@target NVARCHAR(30);
 SET @target=CASE @SelectionMode WHEN 'SINGLE' THEN CONCAT('SINGLE:',@CutoffThAkdk) WHEN 'RANGE' THEN CONCAT('RANGE:',@StartThAkdk,'-',@CutoffThAkdk) ELSE CONCAT('UP_TO:',@CutoffThAkdk) END;
 SELECT @agent=AgentName FROM dbo.BackupAgentNode WHERE IsPrimary=1 AND IsEnabled=1;
 IF @agent IS NULL THROW 51103,'Node backup utama belum didaftarkan.',1;
 BEGIN TRAN;
 IF EXISTS(SELECT 1 FROM dbo.BackupTransferJob WITH(UPDLOCK,HOLDLOCK) WHERE OperationType='BACKUP' AND Status IN('WAITING','CLAIMED','TRANSFERRING'))
 BEGIN
  ROLLBACK;
  THROW 51122,'Masih ada job backup aktif atau menunggu. Tunggu job tersebut selesai sebelum membuat job baru.',1;
 END;
 INSERT dbo.BackupTransferJob(JobId,AgentName,OperationType,TriggerSource,CutoffThAkdk,RestoreThAkdkList,SelectedTables,RequestedBy,Status)
 VALUES(@job,@agent,'BACKUP',@TriggerSource,@CutoffThAkdk,@target,@SelectedTables,@RequestedBy,'WAITING');
 INSERT dbo.BackupTransferJobStudent(JobId,Nim1)
 SELECT DISTINCT @job,b.nim1
 FROM dbo.tbio01 b
 JOIN dbo.treg r ON r.nim1=b.nim1
 WHERE ((@SelectionMode='SINGLE' AND LTRIM(RTRIM(r.th_akdk))=@CutoffThAkdk)
     OR (@SelectionMode='RANGE' AND LTRIM(RTRIM(r.th_akdk)) BETWEEN @StartThAkdk AND @CutoffThAkdk)
     OR (@SelectionMode='UP_TO' AND LTRIM(RTRIM(r.th_akdk))<=@CutoffThAkdk));
 DECLARE @candidateStudents INT=(SELECT COUNT(*) FROM dbo.BackupTransferJobStudent WHERE JobId=@job);
 UPDATE dbo.BackupTransferJob SET TotalStudents=@candidateStudents,ProgressMessage=CASE WHEN @candidateStudents>0 THEN 'Menunggu Database Backup' END,Status=CASE WHEN @candidateStudents=0 THEN 'SUCCESS' ELSE Status END,CompletedAt=CASE WHEN @candidateStudents=0 THEN SYSDATETIME() ELSE CompletedAt END,ResultMessage=CASE WHEN @candidateStudents=0 THEN '0 Data Mahasiswa Berhasil Dibackup' ELSE ResultMessage END WHERE JobId=@job;
 COMMIT;
 SELECT @job JobId,COUNT(*) CandidateStudents,(SELECT Status FROM dbo.BackupTransferJob WHERE JobId=@job) Status
 FROM dbo.BackupTransferJobStudent WHERE JobId=@job;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_CreateBackupNimTransferJob
 @StudentNim CHAR(9),@RequestedBy VARCHAR(50),
 @SelectedTables VARCHAR(100)='tbio01,treg,tkrs06,t_absensi14'
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 SET @StudentNim=NULLIF(LTRIM(RTRIM(@StudentNim)),'');
 SET @SelectedTables=LOWER(REPLACE(ISNULL(NULLIF(LTRIM(RTRIM(@SelectedTables)),''),'tbio01,treg,tkrs06,t_absensi14'),' ',''));
 DECLARE @tables TABLE(TableName VARCHAR(30) PRIMARY KEY);
 INSERT @tables SELECT DISTINCT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@SelectedTables,',') WHERE LTRIM(RTRIM(value))<>'';
 IF NOT EXISTS(SELECT 1 FROM @tables) OR EXISTS(SELECT 1 FROM @tables WHERE TableName NOT IN('tbio01','treg','tkrs06','t_absensi14')) THROW 51147,'Pilihan tabel backup tidak valid.',1;
 IF NOT EXISTS(SELECT 1 FROM @tables WHERE TableName IN('treg','tkrs06','t_absensi14')) THROW 51149,'Pilih minimal satu tabel Registrasi, KRS, atau Absensi.',1;
 IF EXISTS(SELECT 1 FROM @tables WHERE TableName<>'tbio01') AND NOT EXISTS(SELECT 1 FROM @tables WHERE TableName='tbio01') INSERT @tables VALUES('tbio01');
 SET @SelectedTables='tbio01'+CASE WHEN EXISTS(SELECT 1 FROM @tables WHERE TableName='treg') THEN ',treg' ELSE '' END+CASE WHEN EXISTS(SELECT 1 FROM @tables WHERE TableName='tkrs06') THEN ',tkrs06' ELSE '' END+CASE WHEN EXISTS(SELECT 1 FROM @tables WHERE TableName='t_absensi14') THEN ',t_absensi14' ELSE '' END;
 IF @StudentNim IS NULL OR LEN(@StudentNim)<>9 OR @StudentNim LIKE '%[^0-9A-Za-z]%' THROW 51142,'NIM harus tepat 9 karakter alfanumerik.',1;
 DECLARE @agent NVARCHAR(128),@job UNIQUEIDENTIFIER=NEWID(),@latestTa CHAR(5);
 SELECT @agent=AgentName FROM dbo.BackupAgentNode WHERE IsPrimary=1 AND IsEnabled=1;
 IF @agent IS NULL THROW 51103,'Node backup utama belum didaftarkan.',1;
 SELECT TOP(1) @latestTa=LTRIM(RTRIM(r.th_akdk))
 FROM dbo.tbio01 b JOIN dbo.treg r ON r.nim1=b.nim1
 WHERE b.nim1=@StudentNim ORDER BY r.th_akdk DESC,r.tgl_entry DESC;
 IF @latestTa IS NULL THROW 51143,'NIM tidak ditemukan atau tidak memiliki data registrasi di database aktif.',1;
 BEGIN TRAN;
 IF EXISTS(SELECT 1 FROM dbo.BackupTransferJob WITH(UPDLOCK,HOLDLOCK) WHERE OperationType='BACKUP' AND Status IN('WAITING','CLAIMED','TRANSFERRING'))
 BEGIN
  ROLLBACK;
  THROW 51122,'Masih ada job backup aktif atau menunggu. Tunggu job tersebut selesai sebelum membuat job baru.',1;
 END;
 INSERT dbo.BackupTransferJob(JobId,AgentName,OperationType,TriggerSource,CutoffThAkdk,StudentNim,SelectedTables,RequestedBy,Status,TotalStudents,ProgressMessage)
 VALUES(@job,@agent,'BACKUP','MANUAL',@latestTa,@StudentNim,@SelectedTables,@RequestedBy,'WAITING',1,'Menunggu Database Backup');
 INSERT dbo.BackupTransferJobStudent(JobId,Nim1) VALUES(@job,@StudentNim);
 COMMIT;
 SELECT @job JobId,1 CandidateStudents,'WAITING' Status;
END;
GO

/* ========================================================================== 
   BAGIAN 08/17 : 02_backup\02_agent_backup_batches.sql
   ========================================================================== */
/*
 Fungsi: Mengambil dan mengonfirmasi batch backup, termasuk tkrs06.
 Script kanonik aktif untuk fungsi ini.
*/

USE [dec_dummy];
GO
SET XACT_ABORT ON;
GO


CREATE OR ALTER PROCEDURE dbo.sp_AgentGetBackupBatch @ApiKey NVARCHAR(256),@JobId UNIQUEIDENTIFIER,@BatchSize INT=1000
AS
BEGIN
 SET NOCOUNT ON;
 IF @BatchSize NOT BETWEEN 1 AND 1000 THROW 51110,'Ukuran batch tidak valid.',1;
 IF NOT EXISTS(SELECT 1 FROM dbo.BackupTransferJob j JOIN dbo.BackupAgentNode a ON a.AgentName=j.AgentName
  WHERE j.JobId=@JobId AND j.OperationType='BACKUP' AND j.Status IN('CLAIMED','TRANSFERRING') AND a.IsPrimary=1 AND a.IsEnabled=1 AND a.ApiKeyHash=HASHBYTES('SHA2_256',@ApiKey)) THROW 51104,'Job atau token tidak valid.',1;
 UPDATE dbo.BackupTransferJob SET Status='TRANSFERRING',LeaseExpiresAt=DATEADD(MINUTE,5,SYSDATETIME()) WHERE JobId=@JobId;
 SELECT TOP(@BatchSize) Nim1 FROM dbo.BackupTransferJobStudent WHERE JobId=@JobId AND Status='PENDING' ORDER BY Nim1;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_AgentConfirmBackupBatch @ApiKey NVARCHAR(256),@JobId UNIQUEIDENTIFIER,@NimsJson NVARCHAR(MAX)
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 IF ISJSON(@NimsJson)<>1 THROW 51111,'Daftar mahasiswa tidak valid.',1;
 BEGIN TRAN;
 IF NOT EXISTS(SELECT 1 FROM dbo.BackupTransferJob j JOIN dbo.BackupAgentNode a ON a.AgentName=j.AgentName
  WHERE j.JobId=@JobId AND j.OperationType='BACKUP' AND j.Status IN('CLAIMED','TRANSFERRING') AND a.IsPrimary=1 AND a.IsEnabled=1 AND a.ApiKeyHash=HASHBYTES('SHA2_256',@ApiKey)) BEGIN ROLLBACK; THROW 51104,'Job atau token tidak valid.',1; END;
 ;WITH n AS(SELECT DISTINCT CONVERT(char(9),[value]) Nim1 FROM OPENJSON(@NimsJson) WHERE LEN(CONVERT(varchar(30),[value]))=9)
 UPDATE s SET Status='COPIED' FROM dbo.BackupTransferJobStudent s JOIN n ON n.Nim1=s.Nim1 WHERE s.JobId=@JobId AND s.Status='PENDING';
 UPDATE dbo.BackupTransferJob SET Status='TRANSFERRING',LeaseExpiresAt=DATEADD(MINUTE,5,SYSDATETIME()),ProcessedStudents=(SELECT COUNT(*) FROM dbo.BackupTransferJobStudent WHERE JobId=@JobId AND Status='COPIED') WHERE JobId=@JobId;
 IF NOT EXISTS(SELECT 1 FROM dbo.BackupTransferJobStudent WHERE JobId=@JobId AND Status='PENDING')
 BEGIN
   UPDATE dbo.BackupTransferJob SET Status='SUCCESS',CompletedAt=SYSDATETIME(),LeaseExpiresAt=NULL,ProgressMessage=NULL,ResultMessage=COALESCE(ResultMessage,CONCAT(ProcessedStudents,' Data Mahasiswa Berhasil Dibackup')),ErrorMessage=NULL WHERE JobId=@JobId;
 END;
 COMMIT;
 SELECT Status,ProcessedStudents CopiedStudents,(SELECT COUNT(*) FROM dbo.BackupTransferJobStudent WHERE JobId=@JobId AND Status='PENDING') PendingStudents FROM dbo.BackupTransferJob WHERE JobId=@JobId;
END;
GO

/* ========================================================================== 
   BAGIAN 09/17 : 03_restore\01_create_restore_job.sql
   ========================================================================== */
/*
 Fungsi: Membuat antrean pemulihan berdasarkan NIM atau daftar Tahun Akademik.
 Script kanonik aktif untuk fungsi ini.
*/

USE [dec_dummy];
GO
SET XACT_ABORT ON;
GO


CREATE OR ALTER PROCEDURE dbo.sp_CreateRestoreTransferJob
 @StudentNim CHAR(9)=NULL,@ThAkdkList NVARCHAR(MAX)=NULL,@RequestedBy VARCHAR(50),@ExpectedStudents INT=NULL,
 @SelectedTables VARCHAR(100)='tbio01,treg,tkrs06,t_absensi14'
AS
BEGIN
 SET NOCOUNT ON;
 SET @StudentNim=NULLIF(LTRIM(RTRIM(@StudentNim)),''); SET @ThAkdkList=NULLIF(LTRIM(RTRIM(@ThAkdkList)),'');
 SET @SelectedTables=LOWER(REPLACE(ISNULL(NULLIF(LTRIM(RTRIM(@SelectedTables)),''),'tbio01,treg,tkrs06,t_absensi14'),' ',''));
 DECLARE @tables TABLE(TableName VARCHAR(30) PRIMARY KEY);
 INSERT @tables SELECT DISTINCT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@SelectedTables,',') WHERE LTRIM(RTRIM(value))<>'';
 IF NOT EXISTS(SELECT 1 FROM @tables) OR EXISTS(SELECT 1 FROM @tables WHERE TableName NOT IN('tbio01','treg','tkrs06','t_absensi14')) THROW 51148,'Pilihan tabel pemulihan tidak valid.',1;
 IF NOT EXISTS(SELECT 1 FROM @tables WHERE TableName IN('treg','tkrs06','t_absensi14')) THROW 51149,'Pilih minimal satu tabel Registrasi, KRS, atau Absensi.',1;
 IF EXISTS(SELECT 1 FROM @tables WHERE TableName<>'tbio01') AND NOT EXISTS(SELECT 1 FROM @tables WHERE TableName='tbio01') INSERT @tables VALUES('tbio01');
 SET @SelectedTables='tbio01'+CASE WHEN EXISTS(SELECT 1 FROM @tables WHERE TableName='treg') THEN ',treg' ELSE '' END+CASE WHEN EXISTS(SELECT 1 FROM @tables WHERE TableName='tkrs06') THEN ',tkrs06' ELSE '' END+CASE WHEN EXISTS(SELECT 1 FROM @tables WHERE TableName='t_absensi14') THEN ',t_absensi14' ELSE '' END;
 IF @StudentNim IS NULL AND @ThAkdkList IS NULL THROW 51107,'Isi NIM atau pilih Tahun Akademik.',1;
 IF @StudentNim IS NOT NULL AND (LEN(@StudentNim)<>9 OR @StudentNim LIKE '%[^0-9A-Za-z]%') THROW 51108,'NIM harus 9 karakter alfanumerik.',1;
 IF @ThAkdkList IS NOT NULL AND EXISTS(SELECT 1 FROM STRING_SPLIT(@ThAkdkList,',') WHERE LTRIM(RTRIM(value)) NOT LIKE '[0-9][0-9][0-9][0-9][0-9]') THROW 51109,'Daftar Tahun Akademik tidak valid.',1;
 IF @ExpectedStudents IS NOT NULL AND @ExpectedStudents<0 THROW 51141,'Jumlah hasil filter tidak valid.',1;
 DECLARE @agent NVARCHAR(128),@job UNIQUEIDENTIFIER=NEWID();
 SELECT @agent=AgentName FROM dbo.BackupAgentNode WHERE IsPrimary=1 AND IsEnabled=1;
 IF @agent IS NULL THROW 51103,'Node backup utama belum didaftarkan.',1;
 INSERT dbo.BackupTransferJob(JobId,AgentName,OperationType,TriggerSource,StudentNim,RestoreThAkdkList,SelectedTables,RequestedBy,Status,TotalStudents,ProgressMessage)
 VALUES(@job,@agent,'RESTORE','MANUAL',@StudentNim,@ThAkdkList,@SelectedTables,@RequestedBy,'WAITING',@ExpectedStudents,'Menunggu Database Backup');
 SELECT @job JobId,'WAITING' Status;
END;
GO

/* ========================================================================== 
   BAGIAN 10/17 : 03_restore\02_agent_restore_batches.sql
   ========================================================================== */
/*
 Fungsi: Mengonfirmasi batch pemulihan secara idempotent.
 Script kanonik aktif untuk fungsi ini.
*/

USE [dec_dummy];
GO
SET XACT_ABORT ON;
GO


CREATE OR ALTER PROCEDURE dbo.sp_AgentConfirmRestoreBatch @ApiKey NVARCHAR(256),@JobId UNIQUEIDENTIFIER,@NimsJson NVARCHAR(MAX),@LastNim CHAR(9)
AS
BEGIN
 SET NOCOUNT ON;
 IF NOT EXISTS(SELECT 1 FROM dbo.BackupTransferJob j JOIN dbo.BackupAgentNode a ON a.AgentName=j.AgentName WHERE j.JobId=@JobId AND j.OperationType='RESTORE' AND j.Status IN('CLAIMED','TRANSFERRING') AND a.IsPrimary=1 AND a.IsEnabled=1 AND a.ApiKeyHash=HASHBYTES('SHA2_256',@ApiKey)) THROW 51104,'Job atau token tidak valid.',1;
 ;WITH n AS(SELECT DISTINCT CONVERT(char(9),[value]) Nim1 FROM OPENJSON(@NimsJson) WHERE LEN(CONVERT(varchar(30),[value]))=9)
 MERGE dbo.BackupTransferJobStudent t USING n s ON t.JobId=@JobId AND t.Nim1=s.Nim1
 WHEN MATCHED THEN UPDATE SET Status='RESTORED'
 WHEN NOT MATCHED THEN INSERT(JobId,Nim1,Status) VALUES(@JobId,s.Nim1,'RESTORED');
 UPDATE dbo.BackupTransferJob SET Status='TRANSFERRING',LastProgressNim=@LastNim,ProcessedStudents=(SELECT COUNT(*) FROM dbo.BackupTransferJobStudent WHERE JobId=@JobId AND Status='RESTORED'),LeaseExpiresAt=DATEADD(MINUTE,5,SYSDATETIME()) WHERE JobId=@JobId;
 SELECT LastProgressNim,ProcessedStudents FROM dbo.BackupTransferJob WHERE JobId=@JobId;
END;
GO

/* ========================================================================== 
   BAGIAN 11/17 : 04_maintenance\02_export_backup_job.sql
   ========================================================================== */
/*
 Fungsi: Membuat antrean ekspor database backup.
 Script kanonik aktif untuk fungsi ini.
*/

USE [dec_dummy];
GO
SET XACT_ABORT ON;
GO


CREATE OR ALTER PROCEDURE dbo.sp_CreateBackupExportJob @RequestedBy VARCHAR(50)
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 DECLARE @agent NVARCHAR(128),@job UNIQUEIDENTIFIER=NEWID();
 SELECT @agent=AgentName FROM dbo.BackupAgentNode WHERE IsPrimary=1 AND IsEnabled=1;
 IF @agent IS NULL THROW 51103,'Node backup utama belum didaftarkan.',1;
 BEGIN TRAN;
 IF EXISTS(SELECT 1 FROM dbo.BackupTransferJob WITH(UPDLOCK,HOLDLOCK) WHERE OperationType='EXPORT' AND Status IN('WAITING','CLAIMED','TRANSFERRING'))
 BEGIN ROLLBACK; THROW 51140,'Masih ada ekspor database yang aktif atau menunggu.',1; END;
 INSERT dbo.BackupTransferJob(JobId,AgentName,OperationType,TriggerSource,RequestedBy,Status,ProgressMessage)
 VALUES(@job,@agent,'EXPORT','MANUAL',@RequestedBy,'WAITING','Menunggu Database Backup');
 COMMIT;
 SELECT @job JobId,'WAITING' Status;
END;
GO

/* ========================================================================== 
   BAGIAN 12/17 : 05_lookup\01_backup_lookup.sql
   ========================================================================== */
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

/* ========================================================================== 
   BAGIAN 13/17 : 06_agent\01_claim_job.sql
   ========================================================================== */
/*
 Fungsi: Mengambil satu job dan memulihkan lease yang kedaluwarsa.
 Script kanonik aktif untuk fungsi ini.
*/

USE [dec_dummy];
GO
SET XACT_ABORT ON;
GO

CREATE OR ALTER PROCEDURE dbo.sp_AgentClaimBackupTransferJob @ApiKey NVARCHAR(256),@LeaseMinutes INT=5
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 DECLARE @agent NVARCHAR(128),@job UNIQUEIDENTIFIER;
 SELECT @agent=AgentName FROM dbo.BackupAgentNode WHERE IsPrimary=1 AND IsEnabled=1 AND ApiKeyHash=HASHBYTES('SHA2_256',@ApiKey);
 IF @agent IS NULL THROW 51104,'Token agent tidak valid.',1;
 BEGIN TRAN;
 UPDATE dbo.BackupTransferJob SET Status=CASE WHEN RetryCount>=5 THEN 'FAILED' ELSE 'WAITING' END,
  RetryCount=RetryCount+1,LeaseExpiresAt=NULL,ProgressMessage=CASE WHEN RetryCount>=5 THEN NULL ELSE 'Menunggu Database Backup' END,ResultMessage=NULL,ErrorMessage=CASE WHEN RetryCount>=5 THEN 'Batas retry agent terlampaui.' ELSE NULL END,
  CompletedAt=CASE WHEN RetryCount>=5 THEN SYSDATETIME() ELSE CompletedAt END
 WHERE AgentName=@agent AND Status IN('CLAIMED','TRANSFERRING') AND LeaseExpiresAt<SYSDATETIME();
 SELECT TOP(1) @job=JobId FROM dbo.BackupTransferJob WITH(UPDLOCK,READPAST)
 WHERE AgentName=@agent AND Status='WAITING' ORDER BY CreatedAt,JobId;
 IF @job IS NOT NULL UPDATE dbo.BackupTransferJob SET Status='CLAIMED',StartedAt=COALESCE(StartedAt,SYSDATETIME()),LeaseExpiresAt=DATEADD(MINUTE,@LeaseMinutes,SYSDATETIME()) WHERE JobId=@job;
 COMMIT;
 SELECT JobId,OperationType,CutoffThAkdk,StudentNim,RestoreThAkdkList,SelectedTables,LastProgressNim,RetryCount,
  (SELECT COUNT(*) FROM dbo.BackupTransferJobStudent s WHERE s.JobId=j.JobId) TargetStudents
 FROM dbo.BackupTransferJob j WHERE JobId=@job;
END;
GO

/* ========================================================================== 
   BAGIAN 14/17 : 06_agent\02_sync_inventory.sql
   ========================================================================== */
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
 DECLARE @agent NVARCHAR(128);
 SELECT @agent=AgentName FROM dbo.BackupAgentNode WHERE IsPrimary=1 AND IsEnabled=1 AND ApiKeyHash=HASHBYTES('SHA2_256',@ApiKey);
 IF @agent IS NULL THROW 51104,'Token agent tidak valid.',1;
 DECLARE @items TABLE(ThAkdk CHAR(5) PRIMARY KEY,StudentCount INT,LatestStudentCount INT);
 INSERT @items SELECT CONVERT(char(5),JSON_VALUE([value],'$.thAkdk')),CONVERT(int,JSON_VALUE([value],'$.studentCount')),CONVERT(int,JSON_VALUE([value],'$.latestStudentCount')) FROM OPENJSON(@InventoryJson) WHERE JSON_VALUE([value],'$.thAkdk') LIKE '[0-9][0-9][0-9][0-9][0-9]';
 BEGIN TRAN;
 DELETE p FROM dbo.BackupAgentPeriodInventory p WHERE p.AgentName=@agent AND NOT EXISTS(SELECT 1 FROM @items i WHERE i.ThAkdk=p.ThAkdk);
 MERGE dbo.BackupAgentPeriodInventory t USING @items s ON t.AgentName=@agent AND t.ThAkdk=s.ThAkdk
 WHEN MATCHED THEN UPDATE SET StudentCount=s.StudentCount,LatestStudentCount=s.LatestStudentCount,UpdatedAt=SYSDATETIME()
 WHEN NOT MATCHED THEN INSERT(AgentName,ThAkdk,StudentCount,LatestStudentCount) VALUES(@agent,s.ThAkdk,s.StudentCount,s.LatestStudentCount);
 COMMIT;
END;
GO

/* ========================================================================== 
   BAGIAN 15/17 : 07_scheduler\01_configuration_and_schedule.sql
   ========================================================================== */
/*
 Fungsi: Menyimpan konfigurasi backup otomatis; endpoint claim membuat job ketika jadwal jatuh tempo.
 Script kanonik aktif untuk fungsi ini.
*/

USE [dec_dummy];
GO
SET XACT_ABORT ON;
GO

IF OBJECT_ID('dbo.BackupJobConfiguration','U') IS NULL
BEGIN
 CREATE TABLE dbo.BackupJobConfiguration(
  ConfigurationId INT NOT NULL CONSTRAINT PK_BackupJobConfiguration PRIMARY KEY,
  IsEnabled BIT NOT NULL,Frequency VARCHAR(10) NOT NULL,ExecutionTime TIME(0) NOT NULL,
  CutoffThAkdk CHAR(5) NOT NULL,NextRunAt DATETIME2(0) NULL,
  SelectedTables VARCHAR(100) NOT NULL CONSTRAINT DF_BackupJobConfiguration_SelectedTables DEFAULT('tbio01,treg,tkrs06,t_absensi14'),
  UpdatedAt DATETIME2(0) NOT NULL,UpdatedBy VARCHAR(50) NOT NULL
 );
 INSERT dbo.BackupJobConfiguration(ConfigurationId,IsEnabled,Frequency,ExecutionTime,CutoffThAkdk,NextRunAt,SelectedTables,UpdatedAt,UpdatedBy) VALUES(1,0,'DAILY','23:00','20001',NULL,'tbio01,treg,tkrs06,t_absensi14',SYSDATETIME(),'System');
END;
GO

IF COL_LENGTH(N'dbo.BackupJobConfiguration',N'SelectedTables') IS NULL
BEGIN
 ALTER TABLE dbo.BackupJobConfiguration ADD SelectedTables VARCHAR(100) NOT NULL
  CONSTRAINT DF_BackupJobConfiguration_SelectedTables DEFAULT('tbio01,treg,tkrs06,t_absensi14') WITH VALUES;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_SaveBackupJobConfiguration
 @IsEnabled BIT,@Frequency VARCHAR(10),@ExecutionTime TIME(0),@CutoffThAkdk CHAR(5),@AdminUser VARCHAR(50),
 @SelectedTables VARCHAR(100)='tbio01,treg,tkrs06,t_absensi14'
AS
BEGIN
 SET NOCOUNT ON;
 SET @SelectedTables=LOWER(REPLACE(ISNULL(NULLIF(LTRIM(RTRIM(@SelectedTables)),''),'tbio01,treg,tkrs06,t_absensi14'),' ',''));
 DECLARE @tables TABLE(TableName VARCHAR(30) PRIMARY KEY);
 INSERT @tables SELECT DISTINCT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@SelectedTables,',') WHERE LTRIM(RTRIM(value))<>'';
 IF NOT EXISTS(SELECT 1 FROM @tables) OR EXISTS(SELECT 1 FROM @tables WHERE TableName NOT IN('tbio01','treg','tkrs06','t_absensi14')) THROW 50012,'Pilihan tabel backup otomatis tidak valid.',1;
 IF NOT EXISTS(SELECT 1 FROM @tables WHERE TableName IN('treg','tkrs06','t_absensi14')) THROW 50013,'Pilih minimal satu tabel Registrasi, KRS, atau Absensi.',1;
 IF EXISTS(SELECT 1 FROM @tables WHERE TableName<>'tbio01') AND NOT EXISTS(SELECT 1 FROM @tables WHERE TableName='tbio01') INSERT @tables VALUES('tbio01');
 SET @SelectedTables='tbio01'+CASE WHEN EXISTS(SELECT 1 FROM @tables WHERE TableName='treg') THEN ',treg' ELSE '' END+CASE WHEN EXISTS(SELECT 1 FROM @tables WHERE TableName='tkrs06') THEN ',tkrs06' ELSE '' END+CASE WHEN EXISTS(SELECT 1 FROM @tables WHERE TableName='t_absensi14') THEN ',t_absensi14' ELSE '' END;
 IF @Frequency NOT IN('DAILY','MONTHLY','SEMESTER') THROW 50010,'Frekuensi harus DAILY, MONTHLY, atau SEMESTER.',1;
 IF @CutoffThAkdk NOT LIKE '[0-9][0-9][0-9][0-9][0-9]' THROW 50011,'Cutoff TA harus lima digit.',1;
 DECLARE @now DATETIME2(0)=SYSDATETIME(),@today DATETIME2(0),@next DATETIME2(0),@sec INT=DATEDIFF(SECOND,CAST('00:00:00' AS time),@ExecutionTime);
 SET @today=DATEADD(SECOND,@sec,CAST(CAST(@now AS date) AS datetime2(0)));
 IF @Frequency='DAILY' SET @next=CASE WHEN @today>@now THEN @today ELSE DATEADD(DAY,1,@today) END;
 IF @Frequency='MONTHLY' BEGIN SET @next=DATEADD(SECOND,@sec,CAST(DATEFROMPARTS(YEAR(@now),MONTH(@now),1) AS datetime2(0))); IF @next<=@now SET @next=DATEADD(MONTH,1,@next); END;
 IF @Frequency='SEMESTER' BEGIN
  DECLARE @jan DATETIME2(0)=DATEADD(SECOND,@sec,CAST(DATEFROMPARTS(YEAR(@now),1,1) AS datetime2(0))),@jul DATETIME2(0)=DATEADD(SECOND,@sec,CAST(DATEFROMPARTS(YEAR(@now),7,1) AS datetime2(0)));
  SET @next=CASE WHEN @now<@jan THEN @jan WHEN @now<@jul THEN @jul ELSE DATEADD(YEAR,1,@jan) END;
 END;
 MERGE dbo.BackupJobConfiguration t USING(SELECT 1 ConfigurationId)s ON t.ConfigurationId=s.ConfigurationId
 WHEN MATCHED THEN UPDATE SET IsEnabled=@IsEnabled,Frequency=@Frequency,ExecutionTime=@ExecutionTime,CutoffThAkdk=@CutoffThAkdk,NextRunAt=CASE WHEN @IsEnabled=1 THEN @next ELSE NULL END,SelectedTables=@SelectedTables,UpdatedAt=@now,UpdatedBy=@AdminUser
 WHEN NOT MATCHED THEN INSERT(ConfigurationId,IsEnabled,Frequency,ExecutionTime,CutoffThAkdk,NextRunAt,SelectedTables,UpdatedAt,UpdatedBy) VALUES(1,@IsEnabled,@Frequency,@ExecutionTime,@CutoffThAkdk,CASE WHEN @IsEnabled=1 THEN @next ELSE NULL END,@SelectedTables,@now,@AdminUser);
 SELECT IsEnabled,Frequency,ExecutionTime,CutoffThAkdk,NextRunAt,SelectedTables FROM dbo.BackupJobConfiguration WHERE ConfigurationId=1;
END;
GO

/* ========================================================================== 
   BAGIAN 16/17 : 08_permissions\01_iis_permissions.sql
   ========================================================================== */
/*
 Fungsi: Memberikan seluruh hak minimum aplikasi IIS setelah semua objek dibuat.
 Script kanonik aktif untuk fungsi ini.
*/

USE [dec_dummy];
GO
SET XACT_ABORT ON;
GO

GRANT EXECUTE ON dbo.sp_CheckBackupOperatorAccess TO [IIS APPPOOL\DefaultAppPool];
GRANT EXECUTE ON dbo.sp_GetBackupOperatorRole TO [IIS APPPOOL\DefaultAppPool];
GRANT EXECUTE ON dbo.sp_SetBackupOperatorAccess TO [IIS APPPOOL\DefaultAppPool];
GRANT EXECUTE ON dbo.sp_AgentHeartbeat TO [IIS APPPOOL\DefaultAppPool];
GRANT EXECUTE ON dbo.sp_CreateBackupTransferJob TO [IIS APPPOOL\DefaultAppPool];
GRANT EXECUTE ON dbo.sp_CreateBackupNimTransferJob TO [IIS APPPOOL\DefaultAppPool];
GRANT EXECUTE ON dbo.sp_CreateRestoreTransferJob TO [IIS APPPOOL\DefaultAppPool];
GRANT EXECUTE ON dbo.sp_CreateBackupExportJob TO [IIS APPPOOL\DefaultAppPool];
GRANT EXECUTE ON dbo.sp_CreateBackupLookupRequest TO [IIS APPPOOL\DefaultAppPool];
GRANT EXECUTE ON dbo.sp_GetBackupLookupRequest TO [IIS APPPOOL\DefaultAppPool];
GRANT EXECUTE ON dbo.sp_AgentClaimBackupTransferJob TO [IIS APPPOOL\DefaultAppPool];
GRANT EXECUTE ON dbo.sp_AgentGetBackupBatch TO [IIS APPPOOL\DefaultAppPool];
GRANT EXECUTE ON dbo.sp_AgentConfirmBackupBatch TO [IIS APPPOOL\DefaultAppPool];
GRANT EXECUTE ON dbo.sp_AgentConfirmRestoreBatch TO [IIS APPPOOL\DefaultAppPool];
GRANT EXECUTE ON dbo.sp_AgentSyncPeriodInventory TO [IIS APPPOOL\DefaultAppPool];
GRANT EXECUTE ON dbo.sp_SaveBackupJobConfiguration TO [IIS APPPOOL\DefaultAppPool];
GRANT SELECT ON dbo.BackupAgentNode TO [IIS APPPOOL\DefaultAppPool];
GRANT SELECT ON dbo.BackupOperatorAccess TO [IIS APPPOOL\DefaultAppPool];
GRANT SELECT ON dbo.BackupAgentPeriodInventory TO [IIS APPPOOL\DefaultAppPool];
GRANT SELECT ON dbo.BackupJobConfiguration TO [IIS APPPOOL\DefaultAppPool];
GRANT SELECT, UPDATE ON dbo.BackupTransferJob TO [IIS APPPOOL\DefaultAppPool];
GRANT SELECT, INSERT, UPDATE ON dbo.BackupTransferJobStudent TO [IIS APPPOOL\DefaultAppPool];
GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.BackupLookupRequest TO [IIS APPPOOL\DefaultAppPool];
-- Tabel sumber hanya dapat dibaca saat backup. INSERT hanya diperlukan ketika
-- operator secara eksplisit menjalankan pemulihan. UPDATE dan DELETE tidak diberikan.
GRANT SELECT, INSERT ON dbo.tbio01 TO [IIS APPPOOL\DefaultAppPool];
GRANT SELECT, INSERT ON dbo.treg TO [IIS APPPOOL\DefaultAppPool];
GRANT SELECT, INSERT ON dbo.tkrs06 TO [IIS APPPOOL\DefaultAppPool];
GRANT SELECT, INSERT ON dbo.t_absensi14 TO [IIS APPPOOL\DefaultAppPool];
GO

/* ========================================================================== 
   BAGIAN 17/17 : 09_verification\01_verify_objects.sql
   ========================================================================== */
/*
 Fungsi: Memastikan tabel dan prosedur wajib tersedia tanpa mengubah data.
 Script kanonik aktif untuk fungsi ini.
*/

USE [dec_dummy];
GO
SET XACT_ABORT ON;
GO

DECLARE @RequiredObjects TABLE(ObjectName SYSNAME NOT NULL, ObjectType CHAR(2) NOT NULL);
INSERT @RequiredObjects(ObjectName,ObjectType) VALUES
 ('BackupAgentNode','U'),('BackupOperatorAccess','U'),('BackupTransferJob','U'),
 ('BackupTransferJobStudent','U'),('BackupAgentPeriodInventory','U'),('BackupLookupRequest','U'),
 ('tkrs06','U'),('sp_GetBackupOperatorRole','P'),('sp_RegisterPrimaryBackupAgent','P'),('sp_AgentHeartbeat','P'),
 ('sp_CreateBackupTransferJob','P'),('sp_CreateBackupNimTransferJob','P'),
 ('sp_CreateRestoreTransferJob','P'),
 ('sp_CreateBackupExportJob','P'),('sp_CreateBackupLookupRequest','P'),
 ('sp_GetBackupLookupRequest','P'),
 ('sp_AgentClaimBackupTransferJob','P'),('sp_AgentGetBackupBatch','P'),
 ('sp_AgentConfirmBackupBatch','P'),('sp_AgentConfirmRestoreBatch','P'),
 ('sp_AgentSyncPeriodInventory','P'),
 ('BackupJobConfiguration','U'),('sp_SaveBackupJobConfiguration','P');

SELECT ObjectName,ObjectType,
 CASE WHEN OBJECT_ID(N'dbo.'+ObjectName,ObjectType) IS NULL THEN 'MISSING' ELSE 'OK' END AS InstallationStatus
FROM @RequiredObjects
ORDER BY InstallationStatus DESC,ObjectType,ObjectName;

IF EXISTS(SELECT 1 FROM @RequiredObjects WHERE OBJECT_ID(N'dbo.'+ObjectName,ObjectType) IS NULL)
 THROW 51290,'Instalasi modular belum lengkap. Periksa objek berstatus MISSING.',1;
GO

PRINT N'Pemrosesan batch selesai. Instalasi hanya dinyatakan berhasil jika verifikasi tidak menampilkan MISSING dan tidak ada pesan error.';
GO
