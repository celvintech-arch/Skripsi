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
