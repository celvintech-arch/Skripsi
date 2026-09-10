[CmdletBinding()]
param(
 [string]$ApplicationRoot='',
 [string]$ToolingRoot='',
 [string]$ConfigPath='',
 [switch]$SkipApi,
 [switch]$SkipLocalDatabase,
 [switch]$TestBothProtocols,
 [string]$ReportPath
)
$ErrorActionPreference='Stop'
if([string]::IsNullOrWhiteSpace($ToolingRoot)){$ToolingRoot=Split-Path -Parent $PSScriptRoot}
if([string]::IsNullOrWhiteSpace($ApplicationRoot)){$ApplicationRoot=Join-Path $ToolingRoot 'web\backup_data'}
if([string]::IsNullOrWhiteSpace($ConfigPath)){$ConfigPath=Join-Path $ToolingRoot 'agent\agent.config.development.example.json'}
$results=New-Object System.Collections.Generic.List[object]
$script:Config=$null
$script:LocalDatabaseReady=$false

function Add-Result([string]$Name,[string]$Category,[string]$Status,[string]$Detail,[long]$DurationMs){
 $results.Add([pscustomobject][ordered]@{Name=$Name;Category=$Category;Status=$Status;Detail=$Detail;DurationMs=$DurationMs})
}
function Invoke-Test([string]$Name,[string]$Category,[scriptblock]$Test){
 $watch=[Diagnostics.Stopwatch]::StartNew()
 try{$detail=& $Test;$watch.Stop();Add-Result $Name $Category 'PASS' ([string]$detail) $watch.ElapsedMilliseconds}
 catch{$watch.Stop();Add-Result $Name $Category 'FAIL' $_.Exception.Message $watch.ElapsedMilliseconds}
}
function Add-SkippedTest([string]$Name,[string]$Category,[string]$Reason){Add-Result $Name $Category 'SKIP' $Reason 0}
function Assert-True([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Get-HttpStatus([scriptblock]$Request){
 try{$response=& $Request;return [pscustomobject]@{Status=[int]$response.StatusCode;Content=[string]$response.Content}}
 catch{
  if($null -ne $_.Exception.Response){
   $status=[int]$_.Exception.Response.StatusCode;$content=''
   try{$stream=$_.Exception.Response.GetResponseStream();if($null -ne $stream){$reader=New-Object IO.StreamReader($stream);$content=$reader.ReadToEnd();$reader.Dispose()}}catch{}
   return [pscustomobject]@{Status=$status;Content=$content}
  }
  throw
 }
}
function Get-WebPageStatus([string]$Uri){
 $request=[System.Net.HttpWebRequest]::Create($Uri)
 $request.Method='GET'
 $request.AllowAutoRedirect=$false
 $request.Timeout=30000
 $response=$null
 try{
  $response=$request.GetResponse()
  $status=[int]$response.StatusCode
  $content=''
  $stream=$response.GetResponseStream()
  if($null -ne $stream){$reader=New-Object IO.StreamReader($stream);$content=$reader.ReadToEnd();$reader.Dispose()}
  return [pscustomobject]@{Status=$status;Content=$content}
 }finally{if($null -ne $response){$response.Dispose()}}
}
function Get-SafeConfig {
 Assert-True (Test-Path -LiteralPath $ConfigPath) "Config agent tidak ditemukan: $ConfigPath"
 $config=Get-Content -LiteralPath $ConfigPath -Raw|ConvertFrom-Json
 Assert-True ($null -ne $config) 'Config agent tidak dapat dibaca.'
 return $config
}

Invoke-Test 'File inti tersedia' 'Source' {
 $runtimeRequired=@('index.aspx','index.ascx','api\agent.aspx','ascx\backup.ascx','ascx\pemulihan.ascx','ascx\riwayat.ascx','ascx\statistik.ascx','ascx\summary_report.ascx','ascx\pdf_report_writer.ascx')
 $toolingRequired=@('agent\BackupAgent.ps1','database\modular\03_restore\01_create_restore_job.sql','database\install_role_summary_report.sql')
 $missing=@($runtimeRequired|Where-Object{-not(Test-Path -LiteralPath(Join-Path $ApplicationRoot $_))})
 $missing+=@($toolingRequired|Where-Object{-not(Test-Path -LiteralPath(Join-Path $ToolingRoot $_))})
 Assert-True ($missing.Count -eq 0) ('File hilang: '+($missing -join ', '))
 "$($runtimeRequired.Count+$toolingRequired.Count) file inti ditemukan pada runtime dan tooling."
}
Invoke-Test 'Agent tidak memanggil fungsi PowerShell yang hilang' 'Source' {
 $agentPath=Join-Path $ToolingRoot 'agent\BackupAgent.ps1'
 $tokens=$null;$parseErrors=$null
 $ast=[Management.Automation.Language.Parser]::ParseFile($agentPath,[ref]$tokens,[ref]$parseErrors)
 Assert-True (@($parseErrors).Count -eq 0) ('Agent memiliki kesalahan sintaks: '+((@($parseErrors)|ForEach-Object{$_.Message})-join '; '))
 $definitions=@($ast.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst]},$true)|ForEach-Object{$_.Name.ToLowerInvariant()})
 $commands=@($ast.FindAll({param($node)$node -is [Management.Automation.Language.CommandAst]},$true)|ForEach-Object{$_.GetCommandName()}|Where-Object{$_}|Sort-Object -Unique)
 $unknown=@($commands|Where-Object{$name=$_;($definitions -notcontains $name.ToLowerInvariant()) -and $null -eq (Get-Command $name -ErrorAction SilentlyContinue)})
 Assert-True ($unknown.Count -eq 0) ('Fungsi atau perintah tidak ditemukan: '+($unknown -join ', '))
 "$($definitions.Count) fungsi agent dan seluruh pemanggilannya dapat diidentifikasi."
}
Invoke-Test 'IIS memiliki izin baca konfigurasi backup otomatis' 'Security' {
 $permissionSource=Get-Content -LiteralPath (Join-Path $ToolingRoot 'database\modular\08_permissions\01_iis_permissions.sql') -Raw
 Assert-True ($permissionSource -match '(?i)GRANT\s+SELECT\s+ON\s+dbo\.BackupJobConfiguration\s+TO\s+\[IIS APPPOOL\\DefaultAppPool\]') 'Izin SELECT BackupJobConfiguration untuk IIS belum tersedia.'
 'Akses langsung API dan portal ke BackupJobConfiguration memiliki izin SELECT minimum.'
}
Invoke-Test 'Tidak ada istilah atau kontrak backup lama' 'Source' {
 $runtimeFiles=@(Get-ChildItem -LiteralPath $ApplicationRoot -Recurse -File)
 $excludedRoots=@((Join-Path $ToolingRoot '.git'),(Join-Path $ToolingRoot 'sources'),(Join-Path $ToolingRoot 'TestResults'))
 $toolingFiles=@(Get-ChildItem -LiteralPath $ToolingRoot -Recurse -File|Where-Object{$path=$_.FullName;-not @($excludedRoots|Where-Object{$path.StartsWith($_,[StringComparison]::OrdinalIgnoreCase)}).Count})
 $files=$runtimeFiles+$toolingFiles
 $files=@($files|Where-Object {$_.Extension -in @('.aspx','.ascx','.ashx','.css','.js','.json','.md','.ps1','.cmd','.sql')})
 $idTerms=@(
  -join([char[]](97,114,115,105,112)),
  -join([char[]](97,114,99,104,105,118,101)),
  -join([char[]](97,114,99,104,105,118)),
  -join([char[]](112,101,110,103,97,114,115,105,112,97,110))
 )
 $forbiddenPattern='(?i)'+(($idTerms|ForEach-Object{[regex]::Escape($_)})-join '|')
 $contentMatches=@($files|Select-String -Pattern $forbiddenPattern|Where-Object{$_.Line -notmatch 'fa-file-archive-o'})
 $pathMatches=@($runtimeFiles|Where-Object {$_.FullName.Substring($ApplicationRoot.TrimEnd('\\').Length).TrimStart('\\') -match $forbiddenPattern})
 Assert-True ($contentMatches.Count -eq 0) "Masih ada $($contentMatches.Count) istilah lama pada isi file."
 Assert-True ($pathMatches.Count -eq 0) "Masih ada nama file atau folder lama: $(($pathMatches.FullName)-join ', ')"
 'Isi dan path source bersih dari terminologi lama.'
}
Invoke-Test 'Script SQL hanya memiliki satu definisi aktif per procedure' 'Source' {
 $scriptsRoot=Join-Path $ToolingRoot 'database\modular'
 $sqlFiles=@(Get-ChildItem -LiteralPath $scriptsRoot -Recurse -File -Filter *.sql)
 Assert-True ($sqlFiles.Count -gt 0) 'Script SQL aktif tidak ditemukan.'
 $definitions=@()
 foreach($file in $sqlFiles){
  $content=Get-Content -LiteralPath $file.FullName -Raw
  $definitions+=@([regex]::Matches($content,'(?im)\bCREATE\s+(?:OR\s+ALTER\s+)?PROCEDURE\s+(?:\[?dbo\]?\.)?\[?(?<name>[A-Za-z0-9_]+)\]?')|ForEach-Object{$_.Groups['name'].Value})
 }
 $duplicates=@($definitions|Group-Object|Where-Object{$_.Count -gt 1})
 Assert-True ($duplicates.Count -eq 0) ('Procedure didefinisikan berulang: '+(($duplicates|ForEach-Object{$_.Name})-join ', '))
 $runtimeCalls=@()
 foreach($folder in @('api','ascx')){
  $path=Join-Path $ApplicationRoot $folder
  foreach($file in Get-ChildItem -LiteralPath $path -Recurse -File -Include *.aspx,*.ascx){
   $content=Get-Content -LiteralPath $file.FullName -Raw
   $runtimeCalls+=@([regex]::Matches($content,'New\s+SqlCommand\("dbo\.(?<name>sp_[A-Za-z0-9_]+)"')|ForEach-Object{$_.Groups['name'].Value})
  }
 }
 $missing=@($runtimeCalls|Sort-Object -Unique|Where-Object{$_ -notin $definitions})
 Assert-True ($missing.Count -eq 0) ('Procedure runtime tidak memiliki script aktif: '+($missing -join ', '))
 "$($sqlFiles.Count) file SQL, $($definitions.Count) procedure unik, tanpa duplikasi."
}
Invoke-Test 'Backup per NIM dihapus dan Pemulihan per NIM tetap difilter' 'UI' {
 $backup=Get-Content -LiteralPath(Join-Path $ApplicationRoot 'ascx\backup.ascx')-Raw
 $restore=Get-Content -LiteralPath(Join-Path $ApplicationRoot 'ascx\pemulihan.ascx')-Raw
 Assert-True ($backup -notmatch '(?i)backup\s+(?:mahasiswa\s+)?per\s+NIM|section=nim|sp_CreateBackupNimTransferJob|gvBackupNimStudents') 'Fitur Backup per NIM masih tersedia pada halaman Backup.'
 Assert-True ($restore.Contains('New ListItem("- Pilih Tahun Akademik -","")')) 'Dropdown pemulihan per NIM belum memiliki pilihan awal wajib.'
 Assert-True ($restore -notmatch 'CreateLookup\("SEARCH","",""\)') 'Pemulihan masih membuat lookup seluruh mahasiswa saat halaman dibuka.'
 Assert-True ($restore.Contains('ShowEmptyRestoreNimState()')) 'State awal pemulihan per NIM belum tersedia.'
 'Backup per NIM tidak diekspos dan Pemulihan per NIM tidak memuat mahasiswa sebelum TA dipilih.'
}
Invoke-Test 'Web tidak mengakses database backup secara langsung' 'Architecture' {
 $files=@()
 foreach($relative in @('api','ascx')){$folder=Join-Path $ApplicationRoot $relative;if(Test-Path -LiteralPath $folder){$files+=@(Get-ChildItem -LiteralPath $folder -File -Recurse -Include *.ashx,*.ascx)}}
 $violations=@($files|Select-String -Pattern '(?i)dec_dummy_backup\s*\.\s*dbo|Data\s+Source\s*=.*dec_dummy_backup')
 Assert-True ($violations.Count -eq 0) 'Ditemukan akses database backup langsung dari web.'
 'Tidak ada koneksi/query lintas database backup pada halaman dan API.'
}
Invoke-Test 'Koneksi aktif menggunakan condecdummy tanpa kredensial ganda' 'Configuration' {
 $adapter=Get-Content -LiteralPath(Join-Path $ApplicationRoot 'ascx\con_backup.ascx')-Raw
 $api=Get-Content -LiteralPath(Join-Path $ApplicationRoot 'api\agent.aspx')-Raw
 $webConfig=Get-Content -LiteralPath(Join-Path $ApplicationRoot 'web.config')-Raw
 Assert-True ($adapter.Contains('virtual="/con_ascx2022/condecdummy.ascx"')) 'Adapter portal belum menggunakan condecdummy.ascx.'
 Assert-True ($api.Contains('virtual="/con_ascx2022/condecdummy.ascx"')) 'API belum menggunakan condecdummy.ascx.'
 Assert-True ($webConfig -notmatch '(?i)BackupLiveConnection|Data\s+Source\s*=|Initial\s+Catalog\s*=|Password\s*=') 'web.config masih menyimpan koneksi database aktif terpisah.'
 'Portal dan API mengambil koneksi dari condecdummy; web.config tidak menggandakan kredensial.'
}
Invoke-Test 'Folder web hanya memuat runtime' 'Security' {
 $forbidden=@('agent','scripts','deployment','tests','docs','TestResults')
 $present=@($forbidden|Where-Object{Test-Path -LiteralPath(Join-Path $ApplicationRoot $_)})
 Assert-True ($present.Count -eq 0) ('Tooling masih berada di web root: '+($present -join ', '))
 'Agent, SQL, deployment, pengujian, dan dokumentasi berada di luar web root.'
}
Invoke-Test 'API tidak memiliki endpoint deployment sementara' 'Security' {
 $api=Get-Content -LiteralPath(Join-Path $ApplicationRoot 'api\agent.aspx')-Raw
 Assert-True ($api -notmatch '(?i)migratejobmessages|deployrollback') 'Endpoint deployment sementara masih aktif.'
 Assert-True ($api -match 'X-Backup-Agent-Key') 'Validasi API key tidak ditemukan.'
 Assert-True ($api -notmatch 'Request\.IsSecureConnection') 'API masih menolak koneksi HTTP yang diizinkan untuk lingkungan ini.'
 Assert-True ($api -match 'ContentLength>104857600') 'API belum membatasi payload 100 MB.'
 $webConfig=Get-Content -LiteralPath(Join-Path $ApplicationRoot 'web.config')-Raw
 Assert-True ($webConfig -match '(?is)<location\s+path="api/agent\.aspx">.*?<allow\s+users="\*"') 'API key endpoint masih dapat terhalang autentikasi cookie LINTAR.'
 'Endpoint sementara tidak ada dan header API key diwajibkan.'
}
Invoke-Test 'Pesan job dipisahkan berdasarkan fungsi' 'Data model' {
 $api=Get-Content -LiteralPath(Join-Path $ApplicationRoot 'api\agent.aspx')-Raw
 $history=Get-Content -LiteralPath(Join-Path $ApplicationRoot 'ascx\riwayat.ascx')-Raw
 foreach($column in @('ProgressMessage','ResultMessage','ErrorMessage')){Assert-True ($api.Contains($column)) "API belum menggunakan $column.";Assert-True ($history.Contains($column)) "Riwayat belum menggunakan $column."}
 'Tiga kolom pesan digunakan API dan Riwayat.'
}
Invoke-Test 'Riwayat hanya menampilkan proses yang telah selesai' 'Data safety' {
 $page=Get-Content -LiteralPath(Join-Path $ApplicationRoot 'ascx\riwayat.ascx')-Raw
 $commands=@([regex]::Matches($page,'CommandName="(?<name>[A-Za-z0-9_]+)"')|ForEach-Object{$_.Groups['name'].Value}|Sort-Object -Unique)
 Assert-True ($commands.Count -eq 0) 'Riwayat proses selesai masih memiliki tombol tindakan.'
 Assert-True ($page -notmatch '(?i)UPDATE\s+dbo\.BackupTransferJob') 'Halaman riwayat masih dapat mengubah status proses.'
 Assert-True ($page.Contains('Not IsActiveTransferStatus')) 'Riwayat belum mengecualikan proses aktif yang ditampilkan pada Dashboard.'
 'Riwayat bersifat baca-saja dan hanya menampilkan proses yang sudah selesai.'
}
Invoke-Test 'Istilah tampilan menggunakan Database Backup' 'UI' {
 $files=Get-ChildItem -LiteralPath(Join-Path $ApplicationRoot 'ascx')-File -Filter *.ascx
 $forbidden=@($files|Select-String -Pattern '(?i)Menunggu\s+laptop|Laptop\s+backup'|Where-Object{$_.Line -notmatch 'Regex\.Replace'})
 Assert-True ($forbidden.Count -eq 0) 'Masih ada istilah laptop pada teks yang ditampilkan.'
 $main=Get-Content -LiteralPath(Join-Path $ApplicationRoot 'ascx\backup.ascx')-Raw
 Assert-True ($main.Contains('<h1>Backup Data</h1>')) 'Judul halaman utama belum menggunakan istilah backup.'
 Assert-True ($main -notmatch '(?i)<label[^>]*>\s*Database sumber') 'Pilihan database sumber masih ditampilkan kepada pengguna.'
 'Teks status dan halaman utama menggunakan Database Backup.'
}
Invoke-Test 'Backup tidak menghapus data sumber' 'Data safety' {
 $sql=Get-Content -LiteralPath(Join-Path $ToolingRoot 'database\modular\02_backup\02_agent_backup_batches.sql')-Raw
 $agent=Get-Content -LiteralPath(Join-Path $ToolingRoot 'agent\BackupAgent.ps1')-Raw
 Assert-True ($sql -notmatch '(?im)DELETE\s+(?:\w+\s+)?FROM\s+dbo\.(?:tbio01|treg|tkrs06|t_absensi14)') 'Stored procedure konfirmasi masih menghapus data sumber.'
 $runtime=(@(Get-Content -LiteralPath(Join-Path $ApplicationRoot 'api\agent.aspx')-Raw),@(Get-Content -LiteralPath(Join-Path $ToolingRoot 'database\modular\02_backup\01_create_backup_jobs.sql')-Raw),@($sql)) -join "`n"
 Assert-True ($runtime -notmatch '(?im)(?:UPDATE|DELETE\s+(?:\w+\s+)?FROM|TRUNCATE\s+TABLE)\s+dbo\.(?:tbio01|treg|tkrs06|t_absensi14)\b') 'Alur backup masih dapat mengubah atau menghapus tabel sumber.'
 Assert-True ($agent -notmatch '(?i)DELETE\s+FROM\s+dbo\.\W*\+?\(?Quote-Id\s+\$target') 'Agent masih menghapus salinan lama sebelum menulis backup.'
 Assert-True ($agent.Contains('WHEN MATCHED THEN UPDATE SET')) 'Agent belum memperbarui salinan lama dengan upsert.'
 Assert-True ($agent.Contains('WHEN NOT MATCHED BY TARGET THEN INSERT')) 'Agent belum memasukkan data backup baru dengan upsert.'
 'Tidak ada penghapusan sumber; agent menggunakan insert/update dan mempertahankan baris backup lama.'
}
Invoke-Test 'Backup mencakup semua status mahasiswa' 'Data selection' {
 $sql=Get-Content -LiteralPath(Join-Path $ToolingRoot 'database\modular\02_backup\01_create_backup_jobs.sql')-Raw
 $page=Get-Content -LiteralPath(Join-Path $ApplicationRoot 'ascx\backup.ascx')-Raw
 Assert-True ($sql -notmatch '(?i)WHERE\s+ISNULL\(L\.sts_reg.*NOT\s+IN') 'Stored procedure backup masih membatasi status registrasi.'
 Assert-True ($sql -notmatch '(?i)@latestStatus\s+IN') 'Backup per NIM masih menolak mahasiswa aktif.'
 Assert-True ($page -notmatch "L\.rn=1\s+AND\s+L\.sts_reg\s+NOT\s+IN\('A','C','R'\)\s+AND\s+\(@year") 'Daftar backup per NIM masih memfilter mahasiswa nonaktif.'
 Assert-True ($page -notmatch '(?i)ActiveStudents|InactiveStudents|data-active|data-inactive|StatusRegistrasi') 'Tampilan backup masih membagi atau memfilter mahasiswa berdasarkan status.'
 Assert-True ($sql -notmatch '(?i)ROW_NUMBER\(\)\s+OVER\s*\(PARTITION BY\s+r?\.?nim1') 'Backup Tahun Akademik masih memilih hanya registrasi terakhir mahasiswa.'
 Assert-True ($sql -match '(?i)SELECT\s+DISTINCT\s+@job\s*,\s*b\.nim1[\s\S]*JOIN\s+dbo\.treg\s+r[\s\S]*r\.th_akdk') 'Kandidat backup belum dipilih dari baris Tahun Akademik yang benar-benar tersedia.'
 'Backup Tahun Akademik menerima seluruh mahasiswa tanpa membedakan status.'
}
Invoke-Test 'Sumber backup menggunakan tabel langsung dec_dummy' 'Architecture' {
 $api=Get-Content -LiteralPath(Join-Path $ApplicationRoot 'api\agent.aspx')-Raw
 $validation=Get-Content -LiteralPath(Join-Path $ToolingRoot 'database\modular\00_core\04_validate_source_tables.sql')-Raw
 foreach($table in @('tbio01','treg','tkrs06','t_absensi14')){
  Assert-True ($api -match "'${table}'") "API belum memetakan dbo.$table."
  Assert-True ($validation -match "N'${table}'") "Validasi belum memeriksa dbo.$table."
 }
 Assert-True ($api -notmatch '(?i)\w+_live') 'API masih menggunakan tabel bayangan _live.'
 Assert-True ($validation -notmatch '(?i)CREATE\s+(?:TABLE|INDEX)|SELECT\s+\*\s+INTO|ALTER\s+TABLE') 'Validasi sumber masih mengubah struktur database aktif.'
 'API membaca empat tabel sumber langsung dan validasi metadata bersifat read-only.'
}
Invoke-Test 'Pilihan tabel diteruskan dari UI sampai agent' 'Feature' {
 $backup=Get-Content -LiteralPath(Join-Path $ApplicationRoot 'ascx\backup.ascx')-Raw
 $restore=Get-Content -LiteralPath(Join-Path $ApplicationRoot 'ascx\pemulihan.ascx')-Raw
 $history=Get-Content -LiteralPath(Join-Path $ApplicationRoot 'ascx\riwayat.ascx')-Raw
 $api=Get-Content -LiteralPath(Join-Path $ApplicationRoot 'api\agent.aspx')-Raw
 $agent=Get-Content -LiteralPath(Join-Path $ToolingRoot 'agent\BackupAgent.ps1')-Raw
 $schema=Get-Content -LiteralPath(Join-Path $ToolingRoot 'database\modular\00_core\02_transfer_and_inventory_tables.sql')-Raw
 foreach($control in @('cblScheduleTables','cblBackupTables')){Assert-True ($backup.Contains($control)) "Kontrol $control belum tersedia."}
 foreach($control in @('cblRestoreNimTables','cblRestorePeriodTables')){Assert-True ($restore.Contains($control)) "Kontrol $control belum tersedia."}
 foreach($table in @('tbio01','treg','tkrs06','t_absensi14')){Assert-True ($backup.Contains('Value="'+$table+'"')) "Pilihan backup $table belum tersedia.";Assert-True ($restore.Contains('Value="'+$table+'"')) "Pilihan restore $table belum tersedia."}
 Assert-True ($schema -match '(?i)SelectedTables\s+VARCHAR\(100\)') 'Kolom pilihan tabel job belum tersedia.'
 Assert-True ($api.Contains('GetSelectedJobTables')) 'API belum memvalidasi pilihan tabel dari job.'
 Assert-True ($agent.Contains('Get-SelectedTableNames')) 'Agent belum membatasi pemrosesan ke tabel terpilih.'
 Assert-True ($history.Contains('TableLabel')) 'Riwayat belum menampilkan pilihan tabel.'
 'Pemilihan tabel tersedia pada backup otomatis, backup Tahun Akademik, dan seluruh mode pemulihan; pilihan diteruskan melalui job, API, serta agent.'
}
Invoke-Test 'Restore melewati konflik tanpa menimpa data aktif' 'Data safety' {
 $api=Get-Content -LiteralPath(Join-Path $ApplicationRoot 'api\agent.aspx')-Raw
 $agent=Get-Content -LiteralPath(Join-Path $ToolingRoot 'agent\BackupAgent.ps1')-Raw
 Assert-True ($api.Contains('InsertMissingLiveRows')) 'Restore per baris belum digunakan.'
 Assert-True ($api.Contains('GetRestoreKeyColumns')) 'Pemilihan primary/unique key untuk restore belum tersedia.'
 Assert-True ($api.Contains('WHERE source_rows.rn=1 AND NOT EXISTS')) 'Restore belum melewati baris yang sudah tersedia.'
 Assert-True ($api -notmatch '(?im)\b(?:UPDATE|DELETE|MERGE)\s+(?:dbo\.)?\[?(?:tbio01|treg|tkrs06|t_absensi14)\]?\b') 'Restore masih dapat menimpa atau menghapus tabel aktif.'
 Assert-True ($agent.Contains("Get-LocalRows `$target `$nims")) 'Restore belum membaca hanya tabel terpilih dengan filter periode.'
 Assert-True ($agent -notmatch '(?s)Get-RestoreTotal.*?ROW_NUMBER\(\).*?function Get-LocalRestoreBatch') 'Pemulihan TA masih didasarkan pada Tahun Akademik terakhir mahasiswa.'
 'Restore memasukkan hanya baris yang belum ada, menyaring periode, dan tidak menimpa data aktif.'
}
Invoke-Test 'Role Staf dan Manager diterapkan pada server' 'Authorization' {
 $auth=Get-Content -LiteralPath (Join-Path $ApplicationRoot 'ascx\con_backup.ascx') -Raw
 $index=Get-Content -LiteralPath (Join-Path $ApplicationRoot 'index.ascx') -Raw
 $operator=Get-Content -LiteralPath (Join-Path $ApplicationRoot 'ascx\operator.ascx') -Raw
 $security=Get-Content -LiteralPath (Join-Path $ToolingRoot 'database\modular\01_security\01_operator_access.sql') -Raw
 Assert-True ($auth.Contains('STAFF_BACKUP') -and $auth.Contains('MANAGER_BACKUP')) 'Role Staf dan Manager belum dikenali adapter otorisasi.'
 Assert-True ($index -match 'IsManagerView\s+AndAlso\s+CurrentTab\s+<>\s+"dashboard"') 'Pembatasan tab Manager belum dilakukan pada server.'
 Assert-True ($index.Contains('ascx/summary_report.ascx')) 'Laporan belum dimuat oleh router server.'
 Assert-True ($operator.Contains('Value="STAFF_BACKUP"') -and $operator.Contains('Value="MANAGER_BACKUP"')) 'Pengelolaan pengguna belum menyediakan kedua role.'
 Assert-True ($security.Contains('sp_GetBackupOperatorRole') -and $security.Contains("'STAFF_BACKUP','MANAGER_BACKUP'")) 'Stored procedure role belum sesuai.'
 'Manager dibatasi ke Dashboard/Laporan dan Staf tetap memiliki akses operasional.'
}
Invoke-Test 'Struktur repository menggunakan lokasi source terbaru' 'Repository' {
 Assert-True ($ApplicationRoot.StartsWith((Join-Path $ToolingRoot 'web'),[StringComparison]::OrdinalIgnoreCase)) 'Source website tidak berada pada folder web repository.'
 Assert-True (Test-Path -LiteralPath (Join-Path $ToolingRoot 'database\install_backup_data_all.sql')) 'Installer gabungan database tidak ditemukan.'
 Assert-True (Test-Path -LiteralPath (Join-Path $ToolingRoot 'database\modular')) 'Folder database/modular tidak ditemukan.'
 'Website, installer, dan SQL modular menggunakan struktur repository terbaru.'
}
Invoke-Test 'Kontrol operasional mewajibkan role Staf' 'Authorization' {
 foreach($name in @('backup.ascx','pemulihan.ascx','riwayat.ascx','operator.ascx','ekspor.ascx')){
  $source=Get-Content -LiteralPath (Join-Path $ApplicationRoot ('ascx\'+$name)) -Raw
  Assert-True ($source.Contains('RequireBackupStaff()')) "$name belum memiliki guard role Staf."
 }
 $dashboard=Get-Content -LiteralPath (Join-Path $ApplicationRoot 'ascx\statistik.ascx') -Raw
 Assert-True ($dashboard.Contains('RequireBackupReportAccess()')) 'Dashboard belum memiliki guard akses laporan.'
 'Semua kontrol yang mengubah proses dilindungi guard Staf pada server.'
}
Invoke-Test 'Dashboard memuat pusat pemantauan operasional' 'UI' {
 $dashboard=Get-Content -LiteralPath (Join-Path $ApplicationRoot 'ascx\statistik.ascx') -Raw
 foreach($token in @('litServiceStatus','litAgentName','litLastHeartbeat','litAgentMessage','litAutomaticStatus','litAutomaticFrequency','litAutomaticScope','litNextSchedule','litLastBackup','litLastRestore','litLastExport','gvActiveDashboard')){Assert-True ($dashboard.Contains($token)) "Komponen Dashboard belum tersedia: $token"}
 Assert-True ($dashboard.Contains('ReadBackupServiceState()')) 'Dashboard belum menggunakan status layanan terpusat.'
 'Dashboard menampilkan status layanan, agent, jadwal, aktivitas terakhir, dan proses aktif.'
}
Invoke-Test 'Backup dan pemulihan memeriksa kesiapan layanan' 'Data safety' {
 $connection=Get-Content -LiteralPath (Join-Path $ApplicationRoot 'ascx\con_backup.ascx') -Raw
 $backup=Get-Content -LiteralPath (Join-Path $ApplicationRoot 'ascx\backup.ascx') -Raw
 $restore=Get-Content -LiteralPath (Join-Path $ApplicationRoot 'ascx\pemulihan.ascx') -Raw
 Assert-True ($connection.Contains('ReadBackupServiceState') -and $connection.Contains('EnsureBackupServiceReady')) 'Status kesiapan bersama belum tersedia.'
 Assert-True ($connection.Contains('If state IsNot Nothing AndAlso state.IsReady Then Return ""')) 'Pesan status siap masih ditampilkan pada halaman operasional.'
 Assert-True ($backup.Contains('EnsureBackupServiceReady(CurrentBackupService,"Backup")') -and $backup.Contains('Lihat Riwayat Proses')) 'Backup belum diblokir ketika layanan tidak siap atau belum memberi tautan riwayat.'
 Assert-True ($restore.Contains('EnsureBackupServiceReady(CurrentBackupService,"Pemulihan")') -and $restore.Contains('Lihat Riwayat Proses')) 'Pemulihan belum diblokir ketika layanan tidak siap atau belum memberi tautan riwayat.'
 Assert-True ($restore -match '(?i)data aktif yang sudah ada (?:akan )?dilewati dan tidak ditimpa') 'Penjelasan penanganan konflik data aktif belum jelas.'
 'Backup dan pemulihan memakai status yang sama, menolak layanan tidak siap, dan mengarahkan ke Riwayat Proses.'
}
Invoke-Test 'Riwayat memiliki filter proses selesai dalam satu baris' 'UI' {
 $history=Get-Content -LiteralPath (Join-Path $ApplicationRoot 'ascx\riwayat.ascx') -Raw
 foreach($token in @('ddlHistoryOperation','ddlHistoryStatus','BACKUP','RESTORE','EXPORT','SUCCESS','FAILED','CANCELLED')){Assert-True ($history.Contains($token)) "Filter riwayat belum lengkap: $token"}
 Assert-True ($history -notmatch 'gvActiveProcesses|Proses Sedang Berjalan|CancelJob') 'Riwayat masih memuat proses aktif atau tindakan pembatalan.'
 Assert-True ($history.Contains('history-filter-field') -and $history.Contains('history-filter-action')) 'Struktur filter satu baris belum tersedia.'
 'Filter operasi/status selesai tersedia dalam satu baris dan proses aktif hanya ditampilkan pada Dashboard.'
}
Invoke-Test 'Laporan tersedia dan bersifat read-only' 'Feature' {
 $path=Join-Path $ApplicationRoot 'ascx\summary_report.ascx'
 Assert-True (Test-Path -LiteralPath $path) 'File Laporan belum tersedia.'
 $report=Get-Content -LiteralPath $path -Raw
 Assert-True ($report.Contains('RequireBackupReportAccess()')) 'Laporan belum memeriksa akses laporan.'
 Assert-True ($report.Contains('@StartDate') -and $report.Contains('@EndExclusive')) 'Filter tanggal belum memakai parameter SQL.'
 Assert-True ($report.Contains('BackupTransferJob') -and $report.Contains('BackupAgentPeriodInventory')) 'Sumber laporan belum menggunakan tabel kontrol dan inventaris.'
 Assert-True ($report -notmatch '(?im)^\s*(INSERT|UPDATE|DELETE|MERGE|TRUNCATE|EXEC(?:UTE)?)\s') 'Laporan memuat perintah perubahan data.'
 Assert-True ($report -notmatch 'litSuccessRate|Tingkat Keberhasilan') 'Metrik tingkat keberhasilan yang sudah dihapus masih tersedia.'
 'Laporan membaca tabel kontrol/inventaris dengan filter berparameter tanpa perintah perubahan data.'
}
Invoke-Test 'Ekspor menampilkan metadata hasil' 'UI' {
 $export=Get-Content -LiteralPath (Join-Path $ApplicationRoot 'ascx\ekspor.ascx') -Raw
 $api=Get-Content -LiteralPath (Join-Path $ApplicationRoot 'api\agent.aspx') -Raw
 foreach($token in @('litLastExportStatus','FileNameLabel','SizeLabel','VerificationLabel','RESTORE VERIFYONLY')){Assert-True ($export.Contains($token)) "Informasi ekspor belum lengkap: $token"}
 Assert-True ($export -notmatch 'ChecksumLabel|Checksum SHA-256') 'Checksum SHA-256 masih ditampilkan pada halaman Ekspor.'
 Assert-True ($api.Contains('SHA-256:')) 'Checksum SHA-256 tidak lagi disimpan pada hasil proses agent.'
 Assert-True ($export -notmatch '(?i)Ekspor membuat file') 'Paragraf penjelasan ekspor yang sudah dihapus masih ditampilkan.'
 'Status, nama file, ukuran, dan verifikasi ditampilkan; SHA-256 tetap dicatat pada hasil agent tanpa ditampilkan pada halaman.'
}
Invoke-Test 'Kelola Pengguna melindungi akun yang sedang login' 'Authorization' {
 $operator=Get-Content -LiteralPath (Join-Path $ApplicationRoot 'ascx\operator.ascx') -Raw
 Assert-True ($operator.Contains('IsCurrentOperator') -and $operator.Contains('Akun yang sedang digunakan tidak dapat dinonaktifkan sendiri')) 'Perlindungan nonaktifkan akun sendiri belum tersedia.'
 Assert-True (([regex]::Matches($operator,'sedang login tidak dapat mengubah dirinya sendiri menjadi Manager')).Count -ge 2) 'Perubahan diri menjadi Manager belum dilindungi pada seluruh jalur.'
 Assert-True ($operator.Contains('Staf</strong>') -and $operator.Contains('Manager</strong>') -and $operator.Contains('Akses read-only hanya ke Dashboard dan Laporan')) 'Ringkasan hak akses belum tersedia.'
 'Hak akses dijelaskan dan akun aktif tidak dapat menonaktifkan atau menurunkan haknya sendiri.'
}
Invoke-Test 'Laporan dapat diekspor ke PDF secara aman' 'Feature' {
 $report=Get-Content -LiteralPath (Join-Path $ApplicationRoot 'ascx\summary_report.ascx') -Raw
 $writer=Get-Content -LiteralPath (Join-Path $ApplicationRoot 'ascx\pdf_report_writer.ascx') -Raw
 Assert-True ($report.Contains('btnExportPdf_Click')) 'Handler ekspor PDF belum tersedia.'
 Assert-True ($report.Contains('BackupSummaryPdfWriter.Create')) 'Laporan belum menggunakan generator PDF.'
 Assert-True ($report.Contains('Response.ContentType="application/pdf"')) 'Respons ekspor belum menggunakan content type PDF.'
 Assert-True ($report.Contains('Content-Disposition') -and $report.Contains('LINTAR_Laporan_Ringkasan_')) 'Nama lampiran PDF belum diterapkan.'
 Assert-True ($report.Contains('RequireBackupReportAccess()')) 'Ekspor PDF belum dilindungi akses laporan.'
 Assert-True ($writer.Contains('%PDF-1.4') -and $writer.Contains('xref') -and $writer.Contains('Halaman ')) 'Generator belum membentuk struktur dan nomor halaman PDF.'
 Assert-True ($writer -notmatch '(?i)\b(?:SqlCommand|SqlConnection|INSERT|UPDATE|DELETE|MERGE|TRUNCATE)\b') 'Generator PDF tidak boleh mengakses atau mengubah database.'
 'Ekspor PDF memakai filter laporan, guard role, lampiran terunduh, dan generator tanpa akses database.'
}
Invoke-Test 'Migration role kompatibel dengan akun lama' 'Data model' {
 $core=Get-Content -LiteralPath (Join-Path $ToolingRoot 'database\modular\00_core\01_agent_and_operator_tables.sql') -Raw
 $permissions=Get-Content -LiteralPath (Join-Path $ToolingRoot 'database\modular\08_permissions\01_iis_permissions.sql') -Raw
 Assert-True ($core.Contains("'STAFF_BACKUP','MANAGER_BACKUP','ADMIN_BACKUP','ADMIN','SUPERADMIN'")) 'Constraint role belum mempertahankan kompatibilitas akun lama.'
 Assert-True ($permissions.Contains('GRANT EXECUTE ON dbo.sp_GetBackupOperatorRole')) 'IIS belum diberi izin minimum membaca role melalui procedure.'
 'Role lama tetap dipetakan sebagai Staf dan role baru tersedia tanpa menghapus akun.'
}
Invoke-Test 'CSS tampilan terpusat di style.css' 'UI' {
 $markup=@(Get-Item -LiteralPath (Join-Path $ApplicationRoot 'Site.master'),(Join-Path $ApplicationRoot 'index.ascx'))+@(Get-ChildItem -LiteralPath (Join-Path $ApplicationRoot 'ascx') -File -Filter *.ascx)
 $styleBlocks=@($markup|Select-String -Pattern '<style(?:\s|>)' -CaseSensitive:$false)
 $inlineStyles=@($markup|Select-String -Pattern '\sstyle\s*=' -CaseSensitive:$false)
 $scriptStyles=@($markup|Select-String -Pattern '\.style\.' -CaseSensitive:$false)
 Assert-True ($styleBlocks.Count -eq 0) "Masih ada $($styleBlocks.Count) blok style pada markup."
 Assert-True ($inlineStyles.Count -eq 0) "Masih ada $($inlineStyles.Count) inline style pada markup."
 Assert-True ($scriptStyles.Count -eq 0) "Masih ada $($scriptStyles.Count) perubahan style langsung dari JavaScript."
 $central=Join-Path $ApplicationRoot 'style.css'
 Assert-True (Test-Path -LiteralPath $central) 'style.css tidak ditemukan.'
 Assert-True ((Get-Item -LiteralPath $central).Length -gt 0) 'style.css kosong.'
 'Tidak ada style pada markup/JavaScript; seluruh CSS statis berada di style.css.'
}
Invoke-Test 'Antarmuka operasional disederhanakan dan konsisten' 'UI' {
 $index=Get-Content -LiteralPath (Join-Path $ApplicationRoot 'index.ascx') -Raw
 $master=Get-Content -LiteralPath (Join-Path $ApplicationRoot 'Site.master') -Raw
 $backup=Get-Content -LiteralPath (Join-Path $ApplicationRoot 'ascx\backup.ascx') -Raw
 $restore=Get-Content -LiteralPath (Join-Path $ApplicationRoot 'ascx\pemulihan.ascx') -Raw
 $history=Get-Content -LiteralPath (Join-Path $ApplicationRoot 'ascx\riwayat.ascx') -Raw
 $report=Get-Content -LiteralPath (Join-Path $ApplicationRoot 'ascx\summary_report.ascx') -Raw
 $operationalPages=@($backup,$restore,$history,(Get-Content -LiteralPath (Join-Path $ApplicationRoot 'ascx\operator.ascx') -Raw),(Get-Content -LiteralPath (Join-Path $ApplicationRoot 'ascx\ekspor.ascx') -Raw)) -join "`n"
 foreach($group in @('Operasional','Pemantauan','Administrasi')){Assert-True ($index.Contains('> '+$group+' <')) "Kelompok menu $group belum tersedia."}
 Assert-True ($index.Contains('> Laporan</a>') -and $index.Contains('Riwayat Proses')) 'Istilah menu belum disederhanakan.'
 Assert-True ($master.Contains('window.backupConfirm') -and $master.Contains('window.Swal.fire')) 'Konfirmasi SweetAlert global belum tersedia.'
 Assert-True ($operationalPages -notmatch '(?i)return\s+(?:window\.)?confirm\s*\(') 'Masih ada konfirmasi browser langsung pada halaman operasional.'
 Assert-True ($backup.Contains('id="pnlAutomaticSettings" class="panel-collapse collapse"')) 'Pengaturan backup otomatis belum dapat dibuka/tutup.'
 Assert-True (([regex]::Matches($backup,'backup-mode-help')).Count -ge 2 -and ([regex]::Matches($restore,'backup-mode-help')).Count -ge 2) 'Petunjuk singkat setiap mode belum lengkap.'
 Assert-True ($report.Contains('summary-filter-grid') -and $report.Contains('<h1>Laporan</h1>')) 'Filter dan istilah laporan belum disederhanakan.'
 'Menu dikelompokkan, istilah diseragamkan, panel otomatis dapat dilipat, bantuan tersedia, dan konfirmasi memakai SweetAlert.'
}

Invoke-Test 'Konfigurasi agent valid' 'Configuration' {
 $script:Config=Get-SafeConfig;$uri=$null
 Assert-True ([Uri]::TryCreate([string]$script:Config.ApiBaseUrl,[UriKind]::Absolute,[ref]$uri)) 'ApiBaseUrl tidak valid.'
 Assert-True ($uri.Scheme -in @('http','https')) 'ApiBaseUrl hanya boleh menggunakan HTTP atau HTTPS.'
 Assert-True ($uri.Scheme -ne 'http' -or [bool]$script:Config.AllowHttp) 'ApiBaseUrl HTTP memerlukan AllowHttp=true.'
 Assert-True (-not[string]::IsNullOrWhiteSpace([string]$script:Config.LocalSqlConnection)) 'LocalSqlConnection kosong.'
 Assert-True (([string]$script:Config.ApiKey).Length -ge 32 -and ([string]$script:Config.ApiKey).Length -le 256) 'ApiKey harus 32-256 karakter.'
 'URL, koneksi SQL lokal, dan panjang API key valid.'
}
Invoke-Test 'Ukuran batch backup dan pemulihan adalah 500' 'Configuration' {
 if($null -eq $script:Config){$script:Config=Get-SafeConfig}
 $backupBatchSize=if($null -eq $script:Config.BackupBatchSize){500}else{[int]$script:Config.BackupBatchSize}
 Assert-True ($backupBatchSize -eq 500) 'BackupBatchSize bukan 500.'
 Assert-True ([int]$script:Config.RestoreBatchSize -eq 500) 'RestoreBatchSize bukan 500.'
 'BackupBatchSize=500 dan RestoreBatchSize=500.'
}

if($SkipLocalDatabase){Add-SkippedTest 'Koneksi dan konsistensi Database Backup' 'Database' 'Dilewati dengan -SkipLocalDatabase.'}
else{
 Invoke-Test 'Koneksi dan konsistensi Database Backup' 'Database' {
  if($null -eq $script:Config){$script:Config=Get-SafeConfig}
  $connection=[regex]::Replace([string]$script:Config.LocalSqlConnection,'^\s*(ConnectionString|Connection String)\s*=\s*','').Trim()
  $cn=New-Object System.Data.SqlClient.SqlConnection($connection)
  try{
   $cn.Open();$tableCmd=$cn.CreateCommand()
   $tableCmd.CommandText="SELECT CASE WHEN OBJECT_ID('dbo.tbio01_backup','U') IS NOT NULL AND OBJECT_ID('dbo.treg_backup','U') IS NOT NULL AND OBJECT_ID('dbo.tkrs06_backup','U') IS NOT NULL AND OBJECT_ID('dbo.t_absensi14_backup','U') IS NOT NULL THEN 1 ELSE 0 END"
   Assert-True ([int]$tableCmd.ExecuteScalar() -eq 1) 'Satu atau lebih tabel backup wajib belum tersedia.'
   $cmd=$cn.CreateCommand();$cmd.CommandTimeout=120;$cmd.CommandText=@"
SELECT
 (SELECT COUNT(*) FROM (SELECT DISTINCT nim1 FROM dbo.treg_backup EXCEPT SELECT DISTINCT nim1 FROM dbo.tbio01_backup)x)
 +(SELECT COUNT(*) FROM (SELECT DISTINCT nim1 FROM dbo.t_absensi14_backup EXCEPT SELECT DISTINCT nim1 FROM dbo.tbio01_backup)x)
 +(SELECT COUNT(*) FROM (SELECT DISTINCT nim1 FROM dbo.tkrs06_backup EXCEPT SELECT DISTINCT nim1 FROM dbo.tbio01_backup)x) OrphanRows,
 (SELECT COUNT_BIG(*) FROM dbo.tbio01_backup) StudentRows;
"@
   $rd=$cmd.ExecuteReader();Assert-True $rd.Read() 'Query konsistensi tidak menghasilkan data.'
   $orphans=[int64]$rd['OrphanRows'];$students=[int64]$rd['StudentRows'];$rd.Close()
   Assert-True ($orphans -eq 0) "Ditemukan $orphans kelompok data tanpa biodata."
   $script:LocalDatabaseReady=$true
   "$students mahasiswa; tidak ada registrasi/KRS/absensi tanpa biodata."
  }finally{$cn.Dispose()}
 }
}

if($SkipApi){
 foreach($item in @('Token salah ditolak API','Heartbeat agent diterima API','Endpoint tidak dikenal menghasilkan 404','Halaman web dapat dijangkau')){Add-SkippedTest $item 'API' 'Dilewati dengan -SkipApi.'}
}else{
 Invoke-Test 'Token salah ditolak API' 'API' {
  if($null -eq $script:Config){$script:Config=Get-SafeConfig}
  $uri=([string]$script:Config.ApiBaseUrl).TrimEnd('/')+'/agent.aspx?action=heartbeat'
  $headers=@{'X-Backup-Agent-Key'=('X'*40)};$body=@{databaseReady=$script:LocalDatabaseReady;message='Pengujian token tidak valid'}|ConvertTo-Json -Compress
  $response=Get-HttpStatus{Invoke-WebRequest -UseBasicParsing -Method Post -Uri $uri -Headers $headers -ContentType 'application/json' -Body $body -TimeoutSec 30}
  Assert-True ($response.Status -in @(400,401,403)) "Token salah menghasilkan HTTP $($response.Status)."
  "Token salah ditolak dengan HTTP $($response.Status)."
 }
 Invoke-Test 'Heartbeat agent diterima API' 'API' {
  if($null -eq $script:Config){$script:Config=Get-SafeConfig}
  $uri=([string]$script:Config.ApiBaseUrl).TrimEnd('/')+'/agent.aspx?action=heartbeat'
  $headers=@{'X-Backup-Agent-Key'=[string]$script:Config.ApiKey};$body=@{databaseReady=$script:LocalDatabaseReady;message='Pengujian otomatis kesehatan sistem'}|ConvertTo-Json -Compress
  $response=Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -ContentType 'application/json' -Body $body -TimeoutSec 30
  Assert-True ([bool]$response.ok) 'Heartbeat tidak mengembalikan ok=true.'
  Assert-True (-not[string]::IsNullOrWhiteSpace([string]$response.agentName)) 'Identitas agent kosong.'
  "Heartbeat diterima untuk agent $($response.agentName)."
 }
 Invoke-Test 'Endpoint tidak dikenal menghasilkan 404' 'API' {
  if($null -eq $script:Config){$script:Config=Get-SafeConfig}
  $uri=([string]$script:Config.ApiBaseUrl).TrimEnd('/')+'/agent.aspx?action=automatedtestmissing'
  $response=Get-HttpStatus{Invoke-WebRequest -UseBasicParsing -Method Post -Uri $uri -ContentType 'application/json' -Body '{}' -TimeoutSec 30}
  Assert-True ($response.Status -eq 404) "Endpoint tidak dikenal menghasilkan HTTP $($response.Status)."
  'Endpoint tidak dikenal ditolak dengan HTTP 404.'
 }
 Invoke-Test 'Halaman web dapat dijangkau' 'Web' {
  if($null -eq $script:Config){$script:Config=Get-SafeConfig}
  $apiUri=[Uri]([string]$script:Config.ApiBaseUrl);$sitePath=$apiUri.AbsolutePath-replace'/api/?$',''
  $pageUri='{0}://{1}{2}/index.aspx?tab=riwayat'-f $apiUri.Scheme,$apiUri.Authority,$sitePath.TrimEnd('/')
  $response=Get-WebPageStatus $pageUri
  Assert-True ($response.Status -in @(200,302)) "Halaman menghasilkan HTTP $($response.Status)."
  Assert-True ($response.Content -notmatch 'Compiler Error|BC[0-9]{5}') 'Halaman menghasilkan compiler error.'
  "Halaman merespons HTTP $($response.Status)."
 }
 if($TestBothProtocols){
  Invoke-Test 'Protokol HTTP dan HTTPS dapat dijangkau' 'Web' {
   if($null -eq $script:Config){$script:Config=Get-SafeConfig}
   $apiUri=[Uri]([string]$script:Config.ApiBaseUrl);$sitePath=$apiUri.AbsolutePath-replace'/api/?$','';$statuses=@()
   foreach($scheme in @('http','https')){
    $pageUri='{0}://{1}{2}/index.aspx?tab=riwayat'-f $scheme,$apiUri.Authority,$sitePath.TrimEnd('/')
    $response=Get-WebPageStatus $pageUri
    Assert-True ($response.Status -in @(200,301,302)) "$scheme menghasilkan HTTP $($response.Status).";$statuses+="$scheme=$($response.Status)"
   }
   $statuses-join'; '
  }
 }else{Add-SkippedTest 'Protokol HTTP dan HTTPS dapat dijangkau' 'Web' 'Gunakan -TestBothProtocols untuk mengaktifkan.'}
}

$passed=@($results|Where-Object Status -eq 'PASS').Count;$failed=@($results|Where-Object Status -eq 'FAIL').Count;$skipped=@($results|Where-Object Status -eq 'SKIP').Count
$results|Format-Table Status,Category,Name,DurationMs,Detail -Wrap -AutoSize
Write-Host '';Write-Host("Ringkasan: PASS={0}, FAIL={1}, SKIP={2}"-f$passed,$failed,$skipped)
if(-not[string]::IsNullOrWhiteSpace($ReportPath)){
 $directory=Split-Path -Parent $ReportPath;if(-not[string]::IsNullOrWhiteSpace($directory)-and-not(Test-Path -LiteralPath $directory)){[void](New-Item -ItemType Directory -Path $directory -Force)}
 [ordered]@{generatedAt=(Get-Date).ToString('o');computerName=$env:COMPUTERNAME;applicationRoot=$ApplicationRoot;toolingRoot=$ToolingRoot;passed=$passed;failed=$failed;skipped=$skipped;results=@($results|ForEach-Object{$_})}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $ReportPath -Encoding UTF8
 Write-Host "Laporan JSON: $ReportPath"
}
if($failed-gt 0){exit 1}
exit 0
