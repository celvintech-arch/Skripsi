[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$ConfigPath)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Data
$config = Get-Content -Raw -LiteralPath $ConfigPath | ConvertFrom-Json
$AgentLogPath = Join-Path $PSScriptRoot 'BackupAgent.log'
if((Test-Path -LiteralPath $AgentLogPath) -and (Get-Item -LiteralPath $AgentLogPath).Length -gt 5MB){Move-Item -LiteralPath $AgentLogPath -Destination ($AgentLogPath+'.previous') -Force}
$script:BackupBatchSize=if($null -eq $config.BackupBatchSize){500}else{[int]$config.BackupBatchSize}
if($script:BackupBatchSize -lt 1 -or $script:BackupBatchSize -gt 1000){throw 'BackupBatchSize harus antara 1 dan 1000.'}
$script:RestoreBatchSize=if($null -eq $config.RestoreBatchSize){500}else{[int]$config.RestoreBatchSize}
if($script:RestoreBatchSize -lt 1 -or $script:RestoreBatchSize -gt 500){throw 'RestoreBatchSize harus antara 1 dan 500.'}

function Write-AgentLog([string]$Message) {
 $line=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')+' | '+$Message
 try {[IO.File]::AppendAllText($AgentLogPath,$line+[Environment]::NewLine)} catch {}
 Write-Host $line
}
$script:ApiKey=[string]$config.ApiKey
if([string]::IsNullOrWhiteSpace($script:ApiKey) -or $script:ApiKey.Length -lt 32 -or $script:ApiKey.Length -gt 256){throw 'ApiKey minimal 32 karakter dan wajib diisi.'}
$apiUri=$null
if(-not [Uri]::TryCreate([string]$config.ApiBaseUrl,[UriKind]::Absolute,[ref]$apiUri)){throw 'ApiBaseUrl tidak valid.'}
if($apiUri.Scheme -ne 'http' -and $apiUri.Scheme -ne 'https'){throw 'ApiBaseUrl hanya mendukung HTTP atau HTTPS.'}
$allowHttp=if($null -eq $config.AllowHttp){$false}else{[Convert]::ToBoolean($config.AllowHttp)}
if($apiUri.Scheme -eq 'http' -and -not $allowHttp){throw 'ApiBaseUrl HTTP hanya diizinkan jika AllowHttp=true. Production wajib menggunakan HTTPS.'}
$script:ApiBaseUrl=$apiUri.AbsoluteUri.TrimEnd('/')
function Invoke-AgentApi([string]$Action,[hashtable]$Body) {
 $headers=@{'X-Backup-Agent-Key'=$script:ApiKey}
 try{return Invoke-RestMethod -Method Post -Uri ($script:ApiBaseUrl + '/agent.aspx?action=' + $Action) -Headers $headers -ContentType 'application/json' -Body ($Body | ConvertTo-Json -Compress -Depth 8)}
 catch{
  $message=$_.Exception.Message;$response=$_.Exception.Response
  if($null -ne $response){try{$encoded=[string]$response.Headers["X-Backup-Error"];if(-not [string]::IsNullOrWhiteSpace($encoded)){$message=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded))};$stream=$response.GetResponseStream();if($null -ne $stream){$reader=[IO.StreamReader]::new($stream);$detail=$reader.ReadToEnd();$reader.Dispose();if(-not [string]::IsNullOrWhiteSpace($detail)){$message+=" | "+$detail}}}catch{}}
  throw ('API '+$Action+' gagal: '+$message)
 }
}
function Quote-Id([string]$Name) { '[' + $Name.Replace(']',']]') + ']' }
function Get-LocalConnectionString { return (([string]$config.LocalSqlConnection) -replace '^\s*(ConnectionString|Connection String)\s*=\s*','').Trim() }
function Get-BackupDatabaseName {
 $builder=[System.Data.SqlClient.SqlConnectionStringBuilder]::new((Get-LocalConnectionString))
 if([string]::IsNullOrWhiteSpace($builder.InitialCatalog)){throw 'LocalSqlConnection wajib memiliki Initial Catalog.'}
 return $builder.InitialCatalog
}
function Get-BackupSchema {
 $schema=Invoke-AgentApi 'schema' @{databaseReady=$false;message='Memeriksa schema lokal'}
 if (-not $schema.ok -or $schema.tables.Count -eq 0) { throw 'Schema sumber tidak tersedia.' }
 return $schema
}
function Ensure-BackupSchema($schema) {
 if($null -eq $schema){$schema=Get-BackupSchema}
 $database=Get-BackupDatabaseName;$localConnection=Get-LocalConnectionString
 $masterConnection=[regex]::Replace($localConnection,'(?i)(Initial\s+Catalog|Database)\s*=\s*[^;]*','Initial Catalog=master')
 if($masterConnection -eq $localConnection){$masterConnection += ';Initial Catalog=master'}
 $cn=[System.Data.SqlClient.SqlConnection]::new($masterConnection);$cn.Open()
 try{$cmd=$cn.CreateCommand();$cmd.CommandText="IF DB_ID(N'$($database.Replace("'","''"))') IS NULL CREATE DATABASE $(Quote-Id $database);";[void]$cmd.ExecuteNonQuery()}finally{$cn.Close()}
 $cn=[System.Data.SqlClient.SqlConnection]::new($localConnection);$cn.Open()
 try{
  $schema.tables|Group-Object table|ForEach-Object{
   $table=$_.Name;$columns=$_.Group|Sort-Object order|ForEach-Object{"$(Quote-Id $_.name) $($_.type) $(if($_.nullable){'NULL'}else{'NOT NULL'})"}
   $cmd=$cn.CreateCommand();$cmd.CommandText="IF OBJECT_ID(N'dbo.$table',N'U') IS NULL CREATE TABLE dbo.$(Quote-Id $table) ("+($columns -join ',')+');';[void]$cmd.ExecuteNonQuery()
  }
  $cmd=$cn.CreateCommand();$cmd.CommandTimeout=600
   $cmd.CommandText=@"
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'dbo.tbio01_backup') AND name=N'IX_tbio01_backup_nim1') CREATE INDEX IX_tbio01_backup_nim1 ON dbo.tbio01_backup(nim1);
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'dbo.treg_backup') AND name=N'IX_treg_backup_nim1') CREATE INDEX IX_treg_backup_nim1 ON dbo.treg_backup(nim1);
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'dbo.treg_backup') AND name=N'IX_treg_backup_th_akdk_nim1') CREATE INDEX IX_treg_backup_th_akdk_nim1 ON dbo.treg_backup(th_akdk,nim1);
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'dbo.tkrs06_backup') AND name=N'IX_tkrs06_backup_nim1') CREATE INDEX IX_tkrs06_backup_nim1 ON dbo.tkrs06_backup(nim1);
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'dbo.tkrs06_backup') AND name=N'IX_tkrs06_backup_th_akdk_nim1') CREATE INDEX IX_tkrs06_backup_th_akdk_nim1 ON dbo.tkrs06_backup(th_akdk,nim1);
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'dbo.t_absensi14_backup') AND name=N'IX_t_absensi14_backup_nim1') CREATE INDEX IX_t_absensi14_backup_nim1 ON dbo.t_absensi14_backup(nim1);
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'dbo.t_absensi14_backup') AND name=N'IX_t_absensi14_backup_th_akdk_nim1') CREATE INDEX IX_t_absensi14_backup_th_akdk_nim1 ON dbo.t_absensi14_backup(th_akdk,nim1);
"@
  [void]$cmd.ExecuteNonQuery()
 }finally{$cn.Close()}
 return $schema
}
function Test-BackupDatabase {
 try{
  $cn=[System.Data.SqlClient.SqlConnection]::new((Get-LocalConnectionString));$cn.Open()
  try{
   $cmd=$cn.CreateCommand();$cmd.CommandText=@"
;WITH RowCounts AS
(
 SELECT o.name TableName,SUM(p.rows) TotalRows
 FROM sys.objects o
 JOIN sys.partitions p ON p.object_id=o.object_id AND p.index_id IN(0,1)
 WHERE o.schema_id=SCHEMA_ID('dbo') AND o.name IN('tbio01_backup','treg_backup','tkrs06_backup','t_absensi14_backup')
 GROUP BY o.name
)
SELECT
 CASE WHEN OBJECT_ID('dbo.tbio01_backup','U') IS NOT NULL AND OBJECT_ID('dbo.treg_backup','U') IS NOT NULL AND OBJECT_ID('dbo.tkrs06_backup','U') IS NOT NULL AND OBJECT_ID('dbo.t_absensi14_backup','U') IS NOT NULL THEN 1 ELSE 0 END TablesReady,
 ISNULL(MAX(CASE WHEN TableName='tbio01_backup' THEN TotalRows END),0) BioRows,
 ISNULL(MAX(CASE WHEN TableName='treg_backup' THEN TotalRows END),0) RegRows,
 ISNULL(MAX(CASE WHEN TableName='tkrs06_backup' THEN TotalRows END),0) KrsRows,
 ISNULL(MAX(CASE WHEN TableName='t_absensi14_backup' THEN TotalRows END),0) AbsensiRows,
 (SELECT COUNT(*) FROM (SELECT nim1 FROM dbo.treg_backup UNION SELECT nim1 FROM dbo.tkrs06_backup UNION SELECT nim1 FROM dbo.t_absensi14_backup) a WHERE NOT EXISTS(SELECT 1 FROM dbo.tbio01_backup b WHERE b.nim1=a.nim1)) OrphanRows,
 (SELECT SUM(CONVERT(decimal(18,2),size)*8.0/1024.0) FROM sys.database_files WHERE type=0) SizeMb
FROM RowCounts
"@
    $rd=$cmd.ExecuteReader();if(-not $rd.Read()){throw 'Pemeriksaan konsistensi tidak menghasilkan data.'}
    $tablesReady=([int]$rd['TablesReady'] -eq 1);$bioRows=[int64]$rd['BioRows'];$regRows=[int64]$rd['RegRows'];$krsRows=[int64]$rd['KrsRows'];$absRows=[int64]$rd['AbsensiRows'];$orphans=[int]$rd['OrphanRows'];$sizeMb=[double]$rd['SizeMb'];$ready=$tablesReady -and $orphans -eq 0;$rd.Close()
    $latencyMs=$null
    if($bioRows -gt 0){
     $sample=$cn.CreateCommand();$sample.CommandText='SELECT TOP(1) RTRIM(nim1) FROM dbo.tbio01_backup ORDER BY nim1';$sampleNim=[string]$sample.ExecuteScalar()
     if(-not [string]::IsNullOrWhiteSpace($sampleNim)){$lookup=$cn.CreateCommand();$lookup.CommandText='SELECT COUNT(*) FROM dbo.tbio01_backup WHERE nim1=@nim';$p=$lookup.Parameters.Add('@nim',[System.Data.SqlDbType]::Char,9);$p.Value=$sampleNim;$watch=[Diagnostics.Stopwatch]::StartNew();[void]$lookup.ExecuteScalar();$watch.Stop();$latencyMs=[Math]::Round($watch.Elapsed.TotalMilliseconds,2)}
    }
    $stats=[ordered]@{bioRows=$bioRows;regRows=$regRows;krsRows=$krsRows;absRows=$absRows;sizeMb=[Math]::Round($sizeMb,2);lookupLatencyMs=$latencyMs;inconsistencies=$orphans;checkedAt=(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')}
    $message=$stats|ConvertTo-Json -Compress
   }finally{$cn.Close()}
   @{Ready=$ready;Message=$message;BioRows=$bioRows;RegRows=$regRows;KrsRows=$krsRows;AbsRows=$absRows;SizeMb=$sizeMb;LookupLatencyMs=$latencyMs;Inconsistencies=$orphans}
 }catch{@{Ready=$false;Message=$_.Exception.Message}}
}
function Get-PeriodInventory {
 $periods=[Collections.Generic.List[object]]::new()
 $cn=[System.Data.SqlClient.SqlConnection]::new((Get-LocalConnectionString));$cn.Open()
 try{
  $cmd=$cn.CreateCommand();$cmd.CommandTimeout=300
  $cmd.CommandText=@"
;WITH AcademicRows AS
(
 SELECT RTRIM(nim1) Nim1,LTRIM(RTRIM(th_akdk)) ThAkdk FROM dbo.treg_backup
 UNION
 SELECT RTRIM(nim1),LTRIM(RTRIM(th_akdk)) FROM dbo.tkrs06_backup
 UNION
 SELECT RTRIM(nim1),LTRIM(RTRIM(th_akdk)) FROM dbo.t_absensi14_backup
),
Registration AS
(
 SELECT
  Nim1,
  ThAkdk,
  ROW_NUMBER() OVER
  (
   PARTITION BY nim1
   ORDER BY ThAkdk DESC
  ) LatestOrder
 FROM AcademicRows
 WHERE nim1 IS NOT NULL
   AND LTRIM(RTRIM(nim1))<>''
   AND ThAkdk LIKE '[0-9][0-9][0-9][0-9][0-9]'
),
PeriodTotals AS
(
 SELECT ThAkdk,COUNT(DISTINCT Nim1) StudentCount
 FROM Registration
 GROUP BY ThAkdk
),
LatestTotals AS
(
 SELECT ThAkdk,COUNT(*) LatestStudentCount
 FROM Registration
 WHERE LatestOrder=1
 GROUP BY ThAkdk
)
SELECT
 p.ThAkdk,
 p.StudentCount,
 ISNULL(l.LatestStudentCount,0) LatestStudentCount
FROM PeriodTotals p
LEFT JOIN LatestTotals l ON l.ThAkdk=p.ThAkdk
ORDER BY p.ThAkdk DESC;
"@
  $rd=$cmd.ExecuteReader()
  while($rd.Read()){
   [void]$periods.Add([pscustomobject][ordered]@{
    thAkdk=$rd['ThAkdk'].ToString().Trim()
    studentCount=[Convert]::ToInt32($rd['StudentCount'])
    latestStudentCount=[Convert]::ToInt32($rd['LatestStudentCount'])
   })
  }
  $rd.Close()
 }finally{$cn.Close()}
 return ,$periods.ToArray()
}
function New-BackupDataTable($cn,$tx,[string]$target,$columns,$rows) {
 $included=@()
 foreach($col in $columns){
  foreach($row in $rows){if($null -ne $row.PSObject.Properties[$col.name]){$included+=$col;break}}
 }
 if($included.Count -eq 0){return $null}
 $schemaCmd=$cn.CreateCommand();$schemaCmd.Transaction=$tx
 $schemaCmd.CommandText='SELECT TOP (0) '+(($included|ForEach-Object{Quote-Id $_.name}) -join ',')+' FROM dbo.'+(Quote-Id $target)
 $reader=$schemaCmd.ExecuteReader();$table=[System.Data.DataTable]::new()
 for($i=0;$i -lt $reader.FieldCount;$i++){[void]$table.Columns.Add($reader.GetName($i),$reader.GetFieldType($i))}
 $reader.Close()
 foreach($sourceRow in $rows){
  $dataRow=$table.NewRow()
  foreach($col in $included){
   $prop=$sourceRow.PSObject.Properties[$col.name]
   if($null -eq $prop -or $null -eq $prop.Value){$dataRow[$col.name]=[DBNull]::Value;continue}
   $value=$prop.Value;$dataType=$table.Columns[$col.name].DataType
   if($dataType -eq [byte[]] -and $value -is [string]){$value=[Convert]::FromBase64String($value)}
   elseif($dataType -eq [Guid] -and $value -isnot [Guid]){$value=[Guid]$value}
   elseif($dataType -eq [DateTime] -and $value -isnot [DateTime]){$value=[DateTime]$value}
   elseif($dataType -eq [DateTimeOffset] -and $value -isnot [DateTimeOffset]){$value=[DateTimeOffset]$value}
   elseif($dataType -eq [TimeSpan] -and $value -isnot [TimeSpan]){$value=[TimeSpan]::Parse([string]$value)}
   $dataRow[$col.name]=$value
  }
  [void]$table.Rows.Add($dataRow)
 }
 return ,$table
}
function Get-BackupKeyColumns([string]$target,$columns) {
 $columnList=@($columns)
 if($columnList.Count -eq 0){throw ('Schema tabel '+$target+' tidak ditemukan. Backup dibatalkan.')}
 $keys=@($columnList|Where-Object{$_.key -eq $true}|Sort-Object keyOrder)
 if($keys.Count -gt 0){return @($keys)}
 $normalizedTarget=$target.Trim().ToLowerInvariant()
 if(-not $normalizedTarget.EndsWith('_backup')){$normalizedTarget+='_backup'}
 $fallback=@{
  'tbio01_backup'=@('nim1')
  'treg_backup'=@('th_akdk','nim1')
  'tkrs06_backup'=@('th_akdk','nim1','kode_mk','kd_kls')
  't_absensi14_backup'=@('th_akdk','kd_mk','kd_kls','jns_kul','tgl_temu','nim1','temuke')
 }
 if(-not $fallback.ContainsKey($normalizedTarget)){throw ('Definisi kunci natural tabel '+$target+' tidak tersedia. Backup dibatalkan.')}
 $keys=@()
 $missing=@()
 foreach($name in @($fallback[$normalizedTarget])){
  $match=$columnList|Where-Object{[string]::Equals([string]$_.name,$name,[StringComparison]::OrdinalIgnoreCase)}|Select-Object -First 1
  if($null -eq $match){$missing+=$name}else{$keys+=$match}
 }
 if($missing.Count -gt 0){throw ('Kunci natural tabel '+$target+' tidak lengkap pada schema sumber. Kolom yang tidak ditemukan: '+($missing -join ', ')+'. Backup dibatalkan.')}
 return @($keys)
}
function Get-SelectedTableNames([string]$csv) {
 $order=@('tbio01','treg','tkrs06','t_absensi14')
 if([string]::IsNullOrWhiteSpace($csv)){$csv=$order -join ','}
 $selected=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
 foreach($value in $csv.Split(',')){
  $name=$value.Trim().ToLowerInvariant()
  if([string]::IsNullOrWhiteSpace($name)){continue}
  if($order -notcontains $name){throw ('Pilihan tabel tidak valid: '+$name)}
  [void]$selected.Add($name)
 }
 if($selected.Count -eq 0){throw 'Minimal satu tabel harus dipilih.'}
 if($selected.Count -gt 0){[void]$selected.Add('tbio01')}
 return @($order|Where-Object{$selected.Contains($_)})
}
function Save-BackupBatch($batch,$schema) {
 $cn=[System.Data.SqlClient.SqlConnection]::new((Get-LocalConnectionString));$cn.Open();$tx=$cn.BeginTransaction()
 try{
  $nims=@($batch.nims);if($nims.Count -eq 0){$tx.Commit();return}
  $selectedTables=@(Get-SelectedTableNames ([string]$batch.selectedTables))
  $targetTables=@($selectedTables|ForEach-Object{$_+'_backup'})
  $requiredTables=@('tbio01_backup')
  if($targetTables -contains 'treg_backup'){$requiredTables+=@('treg_backup')}
  foreach($requiredTable in $requiredTables){
   $foundNims=@{}
   foreach($sourceRow in @($batch.tables.$requiredTable)){if($null -ne $sourceRow -and $null -ne $sourceRow.nim1){$foundNims[[string]$sourceRow.nim1.Trim()]=$true}}
   foreach($requiredNim in $nims){if(-not $foundNims.ContainsKey(([string]$requiredNim).Trim())){throw ('Payload backup tidak lengkap: '+$requiredTable+' tidak memiliki NIM '+$requiredNim+'. Batch dibatalkan sebelum data lokal diubah.')}}
  }
  foreach($target in $targetTables){
   $columns=@($schema.tables|Where-Object{$_.table -eq $target}|Sort-Object order)
   $keyColumns=@(Get-BackupKeyColumns $target $columns)
   $rows=@($batch.tables.$target)
   if($rows.Count -gt 0){
    $data=New-BackupDataTable $cn $tx $target $columns $rows
    if($null -ne $data -and $data.Rows.Count -gt 0){
     $stage='#BackupStage_'+([Guid]::NewGuid().ToString('N'))
     $columnNames=@($data.Columns|ForEach-Object{$_.ColumnName})
     $quotedColumns=@($columnNames|ForEach-Object{Quote-Id $_})
     $create=$cn.CreateCommand();$create.Transaction=$tx
     $create.CommandText='SELECT TOP (0) '+($quotedColumns -join ',')+' INTO '+(Quote-Id $stage)+' FROM dbo.'+(Quote-Id $target)+';'
     [void]$create.ExecuteNonQuery()
     $bulk=[System.Data.SqlClient.SqlBulkCopy]::new($cn,[System.Data.SqlClient.SqlBulkCopyOptions]::TableLock,$tx)
     try{
      $bulk.DestinationTableName=(Quote-Id $stage);$bulk.BatchSize=$data.Rows.Count;$bulk.BulkCopyTimeout=600
      foreach($column in $data.Columns){[void]$bulk.ColumnMappings.Add($column.ColumnName,$column.ColumnName)}
      $bulk.WriteToServer($data)
     }finally{$bulk.Close()}
     $usableKeys=@($keyColumns|Where-Object{$columnNames -contains [string]$_.name})
     if($usableKeys.Count -ne $keyColumns.Count){throw ('Payload '+$target+' tidak memuat seluruh primary key. Backup dibatalkan.')}
     $on=@($usableKeys|ForEach-Object{'(target.'+(Quote-Id $_.name)+'=source.'+(Quote-Id $_.name)+' OR (target.'+(Quote-Id $_.name)+' IS NULL AND source.'+(Quote-Id $_.name)+' IS NULL))'}) -join ' AND '
     $updates=@($columnNames|Where-Object{$columnName=$_; -not ($usableKeys|Where-Object{[string]$_.name -eq $columnName})}|ForEach-Object{'target.'+(Quote-Id $_)+'=source.'+(Quote-Id $_)})
     $merge=$cn.CreateCommand();$merge.Transaction=$tx;$merge.CommandTimeout=600
     $merge.CommandText='MERGE dbo.'+(Quote-Id $target)+' WITH (HOLDLOCK) AS target USING '+(Quote-Id $stage)+' AS source ON '+$on+' '+$(if($updates.Count -gt 0){'WHEN MATCHED THEN UPDATE SET '+($updates -join ',')+' '}else{''})+'WHEN NOT MATCHED BY TARGET THEN INSERT ('+($quotedColumns -join ',')+') VALUES ('+(($columnNames|ForEach-Object{'source.'+(Quote-Id $_)}) -join ',')+');'
     [void]$merge.ExecuteNonQuery()
    }
   }
  }
  $tx.Commit()
 }catch{try{$tx.Rollback()}catch{};throw}finally{$cn.Close()}
}function Get-LocalRows([string]$table,[string[]]$nims,[string[]]$periods=@()) {
 $result=@();if($nims.Count -eq 0){return $result};$cn=[System.Data.SqlClient.SqlConnection]::new((Get-LocalConnectionString));$cn.Open()
 try{
  $cols=@();$meta=$cn.CreateCommand();$meta.CommandText="SELECT QUOTENAME(name) FROM sys.columns WHERE object_id=OBJECT_ID('dbo.$table') ORDER BY column_id";$rd=$meta.ExecuteReader();while($rd.Read()){$cols+=$rd.GetString(0)};$rd.Close()
  $cmd=$cn.CreateCommand();$ps=@();for($i=0;$i -lt $nims.Count;$i++){$pn='@n'+$i;$ps+=$pn;$p=$cmd.Parameters.Add($pn,[System.Data.SqlDbType]::Char,9);$p.Value=$nims[$i]}
   $periodFilter=''
   if($table -ne 'tbio01_backup' -and $periods.Count -gt 0){
    $periodParameters=@()
    for($i=0;$i -lt $periods.Count;$i++){$pn='@rp'+$i;$periodParameters+=$pn;$p=$cmd.Parameters.Add($pn,[System.Data.SqlDbType]::Char,5);$p.Value=$periods[$i]}
    $periodFilter=' AND LTRIM(RTRIM(th_akdk)) IN ('+($periodParameters -join ',')+')'
   }
   $cmd.CommandText='SELECT '+($cols -join ',')+' FROM dbo.'+(Quote-Id $table)+' WHERE nim1 IN ('+($ps -join ',')+')'+$periodFilter;$rd=$cmd.ExecuteReader()
  while($rd.Read()){$row=[ordered]@{};for($i=0;$i -lt $rd.FieldCount;$i++){$row[$rd.GetName($i)]=if($rd.IsDBNull($i)){$null}else{$rd.GetValue($i)}};$result+=[pscustomobject]$row};$rd.Close()
 }finally{$cn.Close()};return $result
}
function Get-RestorePeriods([string]$thAkdkList) {
 $periods=@($thAkdkList.Split(',')|ForEach-Object{$_.Trim()}|Where-Object{$_ -match '^\d{5}$'}|Select-Object -Unique)
 if($periods.Count -eq 0){throw 'Daftar Tahun Akademik job kosong.'}
 return ,$periods
}
function Get-RestoreTotal([string]$studentNim,[string]$thAkdkList,[string]$selectedTablesCsv) {
 $cn=[System.Data.SqlClient.SqlConnection]::new((Get-LocalConnectionString));$cn.Open()
 try{
  $cmd=$cn.CreateCommand()
  if(-not [string]::IsNullOrWhiteSpace($studentNim)){$cmd.CommandText='SELECT COUNT(*) FROM dbo.tbio01_backup WHERE nim1=@nim';$p=$cmd.Parameters.Add('@nim',[System.Data.SqlDbType]::Char,9);$p.Value=$studentNim}
   else{
    $sources=@(Get-SelectedTableNames $selectedTablesCsv|Where-Object{$_ -ne 'tbio01'})
    if($sources.Count -eq 0){throw 'Pemulihan berdasarkan Tahun Akademik memerlukan minimal satu tabel akademik.'}
    $periods=Get-RestorePeriods $thAkdkList;$ps=@();for($i=0;$i -lt $periods.Count;$i++){$pn='@ta'+$i;$ps+=$pn;$p=$cmd.Parameters.Add($pn,[System.Data.SqlDbType]::Char,5);$p.Value=$periods[$i]}
    $unions=@($sources|ForEach-Object{'SELECT nim1,LTRIM(RTRIM(th_akdk)) th_akdk FROM dbo.'+$_+'_backup'})
    $cmd.CommandText='SELECT COUNT(DISTINCT nim1) FROM ('+($unions -join ' UNION ')+') d WHERE th_akdk IN ('+($ps -join ',')+')'
   }
  return [int]$cmd.ExecuteScalar()
 }finally{$cn.Close()}
}
function Get-LocalRestoreBatch([string]$studentNim,[string]$thAkdkList,[string]$selectedTablesCsv,[string]$afterNim,[int]$batchSize) {
 $cn=[System.Data.SqlClient.SqlConnection]::new((Get-LocalConnectionString));$cn.Open();$nims=@()
 try{
  $cmd=$cn.CreateCommand();$after=if([string]::IsNullOrWhiteSpace($afterNim)){''}else{$afterNim};$p=$cmd.Parameters.Add('@after',[System.Data.SqlDbType]::Char,9);$p.Value=$after
  $p=$cmd.Parameters.Add('@batch',[System.Data.SqlDbType]::Int);$p.Value=$batchSize
  if(-not [string]::IsNullOrWhiteSpace($studentNim)){$cmd.CommandText='SELECT TOP (@batch) nim1 FROM dbo.tbio01_backup WHERE nim1=@nim AND nim1>@after ORDER BY nim1';$p=$cmd.Parameters.Add('@nim',[System.Data.SqlDbType]::Char,9);$p.Value=$studentNim}
   else{
    $sources=@(Get-SelectedTableNames $selectedTablesCsv|Where-Object{$_ -ne 'tbio01'})
    if($sources.Count -eq 0){throw 'Pemulihan berdasarkan Tahun Akademik memerlukan minimal satu tabel akademik.'}
    $periods=Get-RestorePeriods $thAkdkList;$ps=@();for($i=0;$i -lt $periods.Count;$i++){$pn='@ta'+$i;$ps+=$pn;$p=$cmd.Parameters.Add($pn,[System.Data.SqlDbType]::Char,5);$p.Value=$periods[$i]}
    $unions=@($sources|ForEach-Object{'SELECT nim1,LTRIM(RTRIM(th_akdk)) th_akdk FROM dbo.'+$_+'_backup'})
    $cmd.CommandText='SELECT DISTINCT TOP (@batch) nim1 FROM ('+($unions -join ' UNION ')+') d WHERE th_akdk IN ('+($ps -join ',')+') AND nim1>@after ORDER BY nim1'
   }
  $rd=$cmd.ExecuteReader();while($rd.Read()){$nims+=$rd.GetString(0).Trim()};$rd.Close()
 }finally{$cn.Close()}
  $rowPeriods=if([string]::IsNullOrWhiteSpace($studentNim)){@(Get-RestorePeriods $thAkdkList)}else{@()}
  $selectedTables=@(Get-SelectedTableNames $selectedTablesCsv);$tablePayload=[ordered]@{}
  foreach($source in $selectedTables){$target=$source+'_backup';$tablePayload[$target]=@(Get-LocalRows $target $nims $(if($source -eq 'tbio01'){@()}else{$rowPeriods}))}
  [pscustomobject]@{nims=@($nims);selectedTables=($selectedTables -join ',');tables=$tablePayload}
}
function Process-RestoreJob($claim,$database) {
 $studentNim=[string]$claim.studentNim
 $periods=[string]$claim.restoreThAkdkList
 $selectedTables=[string]$claim.selectedTables
 $after=[string]$claim.lastProgressNim
 $total=Get-RestoreTotal $studentNim $periods $selectedTables
 if(-not (Update-JobProgress $claim 'Menyiapkan pemulihan' 0 $total)){return}
 do{
  $batch=Get-LocalRestoreBatch $studentNim $periods $selectedTables $after $script:RestoreBatchSize
  if(@($batch.nims).Count -eq 0){break}
  if(-not (Update-JobProgress $claim 'Mengirim batch pemulihan' @($batch.nims).Count $total)){return}
  $result=Invoke-AgentApi 'restorepush' @{databaseReady=$database.Ready;message='Proses Pemulihan';jobId=[string]$claim.jobId;nims=@($batch.nims);tables=$batch.tables}
  $after=[string]$result.lastProgressNim
  Write-AgentLog ('Pemulihan job '+$claim.jobId+': '+$result.restoredStudents+' dipulihkan; '+$result.skippedStudents+' dilewati.')
 }while(@($batch.nims).Count -gt 0)
 if(-not (Update-JobProgress $claim 'Menyelesaikan pemulihan' 0 $total)){return}
 $complete=Invoke-AgentApi 'restorecomplete' @{databaseReady=$database.Ready;message='Pemulihan selesai';jobId=[string]$claim.jobId}
 Write-AgentLog ('Pemulihan job '+$claim.jobId+' selesai: '+$complete.processedStudents+' dipulihkan; '+$complete.skippedStudents+' dilewati.')
}
function Get-BackupSearchResult([string]$keyword,[string]$year) {
 $items=@();$cn=[System.Data.SqlClient.SqlConnection]::new((Get-LocalConnectionString));$cn.Open()
 try{
  $cmd=$cn.CreateCommand();$cmd.CommandTimeout=120
   $cmd.CommandText=";WITH A AS(SELECT nim1,LTRIM(RTRIM(th_akdk)) th_akdk FROM dbo.treg_backup UNION SELECT nim1,LTRIM(RTRIM(th_akdk)) FROM dbo.tkrs06_backup UNION SELECT nim1,LTRIM(RTRIM(th_akdk)) FROM dbo.t_absensi14_backup) SELECT TOP(100) RTRIM(b.nim1) Nim1,LTRIM(RTRIM(b.nama)) Nama,ISNULL(MAX(A.th_akdk),'') ThAkdk FROM dbo.tbio01_backup b LEFT JOIN A ON A.nim1=b.nim1 WHERE (@year='' OR EXISTS(SELECT 1 FROM A y WHERE y.nim1=b.nim1 AND LEFT(y.th_akdk,4)=@year)) AND (@keyword='' OR b.nim1 LIKE @keyword+'%' OR b.nama LIKE '%'+@keyword+'%') GROUP BY b.nim1,b.nama ORDER BY ISNULL(MAX(A.th_akdk),'') DESC,b.nim1"
  $cmd.Parameters.Add('@year',[System.Data.SqlDbType]::Char,4).Value=if([string]::IsNullOrWhiteSpace($year)){''}else{$year}
  $cmd.Parameters.Add('@keyword',[System.Data.SqlDbType]::NVarChar,100).Value=if([string]::IsNullOrWhiteSpace($keyword)){''}else{$keyword}
  $rd=$cmd.ExecuteReader();while($rd.Read()){$items+=[pscustomobject]@{nim1=$rd['Nim1'].ToString().Trim();nama=$rd['Nama'].ToString().Trim();thAkdk=$rd['ThAkdk'].ToString().Trim()}};$rd.Close()
 }finally{$cn.Close()}
 [pscustomobject]@{students=@($items);limited=($items.Count -eq 100)}
}
function Get-BackupPeriodLookupResult {
 $periodRows=@();$cn=[System.Data.SqlClient.SqlConnection]::new((Get-LocalConnectionString));$cn.Open()
 try{
  $cmd=$cn.CreateCommand();$cmd.CommandTimeout=300
  $cmd.CommandText=";WITH A AS(SELECT nim1,LTRIM(RTRIM(th_akdk)) th_akdk FROM dbo.treg_backup UNION SELECT nim1,LTRIM(RTRIM(th_akdk)) FROM dbo.tkrs06_backup UNION SELECT nim1,LTRIM(RTRIM(th_akdk)) FROM dbo.t_absensi14_backup) SELECT th_akdk,COUNT(DISTINCT nim1) StudentCount FROM A WHERE th_akdk LIKE '[0-9][0-9][0-9][0-9][0-9]' GROUP BY th_akdk ORDER BY th_akdk DESC"
  $rd=$cmd.ExecuteReader();while($rd.Read()){$periodRows+=[pscustomobject]@{thAkdk=$rd['th_akdk'].ToString().Trim();studentCount=[int]$rd['StudentCount']}};$rd.Close()
  }finally{$cn.Close()}
 $periods=@($periodRows|ForEach-Object{[pscustomobject]@{thAkdk=$_.thAkdk;backupMhs=[int]$_.studentCount;eligibleMhs=[int]$_.studentCount}})
 [pscustomobject]@{periods=$periods}
}
function Process-BackupLookups {
 for($i=0;$i -lt 5;$i++){
  $lookup=Invoke-AgentApi 'lookupclaim' @{databaseReady=$true;message='Memeriksa permintaan pencarian backup'}
  if(-not [bool]$lookup.hasLookup){break}
  try{
   $result=if(([string]$lookup.queryType).ToUpperInvariant() -eq 'PERIODS'){Get-BackupPeriodLookupResult}else{Get-BackupSearchResult ([string]$lookup.searchKeyword) ([string]$lookup.filterYear)}
   [void](Invoke-AgentApi 'lookupcomplete' @{databaseReady=$true;message='Lookup backup selesai';lookupId=[string]$lookup.lookupId;success=$true;result=$result})
  }catch{
   $reason=[string]$_.Exception.Message
   try{[void](Invoke-AgentApi 'lookupcomplete' @{databaseReady=$true;message='Lookup backup gagal';lookupId=[string]$lookup.lookupId;success=$false;errorMessage=$reason})}catch{}
   Write-AgentLog ('Lookup '+[string]$lookup.lookupId+' gagal: '+$reason)
  }
 }
}
function Update-JobProgress($claim,[string]$message,[int]$currentBatch,[int]$totalStudents) {
 $progress=Invoke-AgentApi 'jobprogress' @{databaseReady=$true;message=$message;jobId=[string]$claim.jobId;currentBatchStudents=$currentBatch;totalStudents=$totalStudents}
 if([bool]$progress.cancelled){Write-AgentLog ('Job '+$claim.jobId+' sudah dibatalkan pengguna; proses dihentikan dengan aman.');return $false}
 return $true
}
function Process-ExportJob($claim,$database) {
 if(-not (Update-JobProgress $claim 'Menyiapkan ekspor database backup' 0 0)){return}
 $outputDirectory=if([string]::IsNullOrWhiteSpace([string]$config.ExportDirectory)){Join-Path $PSScriptRoot 'Exports'}else{[string]$config.ExportDirectory}
 $outputDirectory=[IO.Path]::GetFullPath($outputDirectory)
 if($outputDirectory.TrimEnd('\') -eq [IO.Path]::GetPathRoot($outputDirectory).TrimEnd('\')){throw 'ExportDirectory tidak boleh berupa root drive.'}
 [IO.Directory]::CreateDirectory($outputDirectory)|Out-Null
 $databaseName=Get-BackupDatabaseName
 $safeDatabaseName=($databaseName -replace '[^0-9A-Za-z_-]','_')
 $jobFileId=([string]$claim.jobId).Replace('-','')
 $fileName=$safeDatabaseName+'_export_'+$jobFileId+'.bak'
 $backupPath=Join-Path $outputDirectory $fileName
 $cn=[System.Data.SqlClient.SqlConnection]::new((Get-LocalConnectionString));$cn.Open()
 try{
  $cmd=$cn.CreateCommand();$cmd.CommandTimeout=0
  $cmd.CommandText='BACKUP DATABASE '+(Quote-Id $databaseName)+' TO DISK=@path WITH COPY_ONLY,INIT,CHECKSUM,NAME=@name,STATS=10;'
  $cmd.Parameters.Add('@path',[System.Data.SqlDbType]::NVarChar,4000).Value=$backupPath
  $cmd.Parameters.Add('@name',[System.Data.SqlDbType]::NVarChar,128).Value=('Ekspor manual '+$databaseName+' '+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
  [void]$cmd.ExecuteNonQuery()
  if(-not (Update-JobProgress $claim 'Memverifikasi file ekspor' 0 0)){return}
  $verify=$cn.CreateCommand();$verify.CommandTimeout=0;$verify.CommandText='RESTORE VERIFYONLY FROM DISK=@path WITH CHECKSUM;';$verify.Parameters.Add('@path',[System.Data.SqlDbType]::NVarChar,4000).Value=$backupPath;[void]$verify.ExecuteNonQuery()
 }catch{
  if(Test-Path -LiteralPath $backupPath){try{[IO.File]::Delete($backupPath)}catch{}}
  throw
 }finally{$cn.Close()}
 $file=[IO.FileInfo]::new($backupPath)
 if(-not $file.Exists -or $file.Length -le 0){throw 'File ekspor tidak terbentuk.'}
 $hash=(Get-FileHash -Algorithm SHA256 -LiteralPath $backupPath).Hash
 $confirm=Invoke-AgentApi 'exportconfirm' @{databaseReady=$database.Ready;message='Ekspor database selesai';jobId=[string]$claim.jobId;fileName=$file.Name;sizeBytes=$file.Length;sha256=$hash}
 Write-AgentLog ('Ekspor job '+$claim.jobId+' selesai: '+$backupPath+' | '+$file.Length+' bytes | SHA-256 '+$hash)
}
function Process-BackupJobs($schema,$database) {
 $claim=Invoke-AgentApi 'claim' @{databaseReady=$database.Ready;message=$database.Message};if(-not $claim.hasJob){return}
 try{
  if([string]$claim.operationType -eq 'EXPORT'){Process-ExportJob $claim $database;return}
  if([string]$claim.operationType -eq 'RESTORE'){Process-RestoreJob $claim $database;return}
  if([string]$claim.operationType -ne 'BACKUP'){throw ('Operasi tidak didukung: '+[string]$claim.operationType)}
  if($null -eq $schema){$schema=Get-BackupSchema}
  $baseline=$null
  try{$baseline=Invoke-AgentApi 'backupmetrics' @{databaseReady=$database.Ready;message='Mengambil baseline sebelum backup';phase='baseline';jobId=[string]$claim.jobId}}catch{Write-AgentLog ('Peringatan: baseline job '+$claim.jobId+' tidak tercatat: '+$_.Exception.Message)}
  do{
   $batch=Invoke-AgentApi 'backupbatch' @{databaseReady=$database.Ready;message='Proses Backup';jobId=[string]$claim.jobId;batchSize=$script:BackupBatchSize}
   if(@($batch.nims).Count -eq 0){break}
   if(-not (Update-JobProgress $claim 'Proses Backup' @($batch.nims).Count 0)){return}
   Save-BackupBatch $batch $schema
   if(-not (Update-JobProgress $claim 'Proses Backup' @($batch.nims).Count 0)){return}
   $confirm=Invoke-AgentApi 'backupconfirm' @{databaseReady=$database.Ready;message='Proses Backup';jobId=[string]$claim.jobId;nims=@($batch.nims)}
   Write-AgentLog ('Backup job '+$claim.jobId+': '+$confirm.status+'; tersalin '+$confirm.copiedStudents+' mahasiswa.')
  }while([int]$confirm.pendingStudents -gt 0)
  if([string]$confirm.status -eq 'SUCCESS' -and $null -ne $baseline){
   try{
    $after=Test-BackupDatabase
     [void](Invoke-AgentApi 'backupmetrics' @{databaseReady=$after.Ready;message='Menyimpan perbandingan sebelum dan sesudah backup';phase='complete';jobId=[string]$claim.jobId;liveBioBefore=[int64]$baseline.bioRows;liveRegBefore=[int64]$baseline.regRows;liveKrsBefore=[int64]$baseline.krsRows;liveAbsBefore=[int64]$baseline.absRows;liveSizeBefore=[double]$baseline.sizeMb;arcBioBefore=[int64]$database.BioRows;arcRegBefore=[int64]$database.RegRows;arcKrsBefore=[int64]$database.KrsRows;arcAbsBefore=[int64]$database.AbsRows;arcSizeBefore=[double]$database.SizeMb;arcBioAfter=[int64]$after.BioRows;arcRegAfter=[int64]$after.RegRows;arcKrsAfter=[int64]$after.KrsRows;arcAbsAfter=[int64]$after.AbsRows;arcSizeAfter=[double]$after.SizeMb})
   }catch{Write-AgentLog ('Peringatan: snapshot job '+$claim.jobId+' tidak tersimpan: '+$_.Exception.Message)}
  }
 }catch{
  $reason=[string]$_.Exception.Message
  try{$failed=Invoke-AgentApi 'jobfail' @{databaseReady=$database.Ready;message='Job dihentikan oleh agent';jobId=[string]$claim.jobId;errorMessage=$reason};Write-AgentLog ('Job '+$claim.jobId+' ditandai '+$failed.status+': '+$reason)}catch{Write-AgentLog ('Pelaporan gagal untuk job '+$claim.jobId+' juga gagal: '+$_.Exception.Message)}
  throw $reason
 }
}
try{
 $database=Test-BackupDatabase
 $schema=$null
 if(-not $database.Ready){$schema=Ensure-BackupSchema $null;$database=Test-BackupDatabase}
 $heartbeat=Invoke-AgentApi 'heartbeat' @{databaseReady=$database.Ready;message=$database.Message}
 if($database.Ready){
  try{Process-BackupLookups}catch{Write-AgentLog ('Peringatan: lookup backup belum tersedia: '+$_.Exception.Message)}
  if((Get-Date).Minute % 5 -eq 0){[void](Invoke-AgentApi 'inventory' @{databaseReady=$database.Ready;message='Memperbarui inventaris lokal';periods=(Get-PeriodInventory)})}
  Process-BackupJobs $schema $database
 }
 Write-AgentLog ($heartbeat|ConvertTo-Json -Compress)
}catch{
 $detail="Backup agent gagal: $($_.Exception.Message)"
 Write-AgentLog $detail
 Write-Error $detail
 exit 1
}
