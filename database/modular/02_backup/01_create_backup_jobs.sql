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
