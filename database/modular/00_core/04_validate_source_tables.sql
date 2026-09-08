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
