/*
 Fungsi: Memverifikasi kesesuaian jumlah mahasiswa database aktif vs inventaris backup per Tahun Akademik.
*/

USE [dec_dummy];
GO
SET XACT_ABORT ON;
GO

CREATE OR ALTER PROCEDURE dbo.sp_VerifyBackupPeriodInventory @ThAkdk CHAR(5) = NULL
AS
BEGIN
 SET NOCOUNT ON;
 UPDATE p
 SET 
  p.LiveStudentCount = ISNULL(l.LiveCount, 0),
  p.VerificationStatus = CASE WHEN p.StudentCount = ISNULL(l.LiveCount, 0) THEN 'VERIFIED' ELSE 'MISMATCH' END,
  p.VerifiedAt = SYSDATETIME()
 FROM dbo.BackupAgentPeriodInventory p
 LEFT JOIN (
  SELECT th_akdk, COUNT(DISTINCT nim1) AS LiveCount
  FROM dbo.treg
  WHERE (@ThAkdk IS NULL OR @ThAkdk = '' OR th_akdk = @ThAkdk)
    AND th_akdk IN (SELECT ThAkdk FROM dbo.BackupAgentPeriodInventory)
  GROUP BY th_akdk
 ) l ON l.th_akdk = p.ThAkdk
 WHERE (@ThAkdk IS NULL OR @ThAkdk = '' OR p.ThAkdk = @ThAkdk);
END;
GO
