/*
 Fungsi: Memverifikasi kesesuaian jumlah mahasiswa database aktif vs inventaris backup per Tahun Akademik.
 Mencakup mahasiswa dari tabel Registrasi (treg), KRS (tkrs06), dan Absensi (t_absensi14) yang memiliki biodata di tbio01.
*/

USE [dec_dummy];
GO
SET XACT_ABORT ON;
GO

CREATE OR ALTER PROCEDURE dbo.sp_VerifyBackupPeriodInventory @ThAkdk CHAR(5) = NULL
AS
BEGIN
 SET NOCOUNT ON;

 DECLARE @targets TABLE(ThAkdk CHAR(5) PRIMARY KEY);
 IF @ThAkdk IS NOT NULL AND @ThAkdk <> ''
  INSERT @targets(ThAkdk) VALUES(@ThAkdk);
 ELSE
  INSERT @targets(ThAkdk) SELECT DISTINCT ThAkdk FROM dbo.BackupAgentPeriodInventory;

 ;WITH LiveAcademicRows AS (
  SELECT r.th_akdk, r.nim1 FROM dbo.treg r JOIN @targets t ON t.ThAkdk = r.th_akdk
  UNION
  SELECT k.th_akdk, k.nim1 FROM dbo.tkrs06 k JOIN @targets t ON t.ThAkdk = k.th_akdk
  UNION
  SELECT a.th_akdk, a.nim1 FROM dbo.t_absensi14 a JOIN @targets t ON t.ThAkdk = a.th_akdk
 ),
 LiveCounts AS (
  SELECT a.th_akdk, COUNT(DISTINCT a.nim1) AS LiveCount
  FROM LiveAcademicRows a
  JOIN dbo.tbio01 b ON b.nim1 = a.nim1
  GROUP BY a.th_akdk
 )
 UPDATE p
 SET 
  p.LiveStudentCount = ISNULL(l.LiveCount, 0),
  p.VerificationStatus = CASE 
   WHEN p.StudentCount = ISNULL(l.LiveCount, 0) THEN 'VERIFIED' 
   WHEN ISNULL(l.LiveCount, 0) = 0 AND p.StudentCount > 0 THEN 'ARCHIVED'
   ELSE 'MISMATCH' 
  END,
  p.VerifiedAt = SYSDATETIME()
 FROM dbo.BackupAgentPeriodInventory p
 JOIN @targets t ON t.ThAkdk = p.ThAkdk
 LEFT JOIN LiveCounts l ON l.th_akdk = p.ThAkdk;
END;
GO
