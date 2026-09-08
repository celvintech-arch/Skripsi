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

