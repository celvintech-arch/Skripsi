param([string]$ConfigPath = "")
if([string]::IsNullOrWhiteSpace($ConfigPath)){throw 'ConfigPath wajib diisi.'}
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Data
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Quote-SqlIdentifier([string]$value){'['+$value.Replace(']',']]')+']'}
function Get-MasterConnectionString {
 $cfg=Get-Content -Raw -LiteralPath $ConfigPath|ConvertFrom-Json
 $builder=[System.Data.SqlClient.SqlConnectionStringBuilder]::new(([string]$cfg.LocalSqlConnection -replace '^\s*(ConnectionString|Connection String)\s*=\s*','').Trim())
 $builder['Initial Catalog']='master';return $builder.ConnectionString
}
function Get-SqlDefaultPath($cn,[string]$property,[int]$fileType){
 $cmd=$cn.CreateCommand();$cmd.CommandText='SELECT CONVERT(nvarchar(4000),SERVERPROPERTY(@property))';$cmd.Parameters.Add('@property',[System.Data.SqlDbType]::NVarChar,100).Value=$property
 $path=[string]$cmd.ExecuteScalar()
 if([string]::IsNullOrWhiteSpace($path)){
  $cmd=$cn.CreateCommand();$cmd.CommandText='SELECT TOP(1) LEFT(physical_name,LEN(physical_name)-CHARINDEX(''\'',REVERSE(physical_name))+1) FROM master.sys.master_files WHERE type=@type ORDER BY database_id';$cmd.Parameters.Add('@type',[System.Data.SqlDbType]::Int).Value=$fileType;$path=[string]$cmd.ExecuteScalar()
 }
 if([string]::IsNullOrWhiteSpace($path)){throw 'Folder data default SQL Server tidak ditemukan.'}
 return $path.TrimEnd('\')
}
function Restore-BackupFile([string]$backupPath,[string]$destinationName,[System.Windows.Forms.Label]$statusLabel){
 if(-not (Test-Path -LiteralPath $backupPath -PathType Leaf)){throw 'File .bak tidak ditemukan.'}
 if($destinationName -notmatch '^[0-9A-Za-z_]{3,80}$'){throw 'Nama database harus 3-80 karakter: huruf, angka, atau garis bawah.'}
 if($destinationName -in @('dec_dummy','dec_dummy_backup')){throw 'Database aktif dan backup utama tidak boleh menjadi tujuan restore.'}
 $cn=[System.Data.SqlClient.SqlConnection]::new((Get-MasterConnectionString));$cn.Open()
 try{
  $exists=$cn.CreateCommand();$exists.CommandText='SELECT COUNT(*) FROM sys.databases WHERE name=@name';$exists.Parameters.Add('@name',[System.Data.SqlDbType]::NVarChar,128).Value=$destinationName
  if([int]$exists.ExecuteScalar() -gt 0){throw 'Database tujuan sudah ada. Gunakan nama database baru.'}
  $statusLabel.Text='Memverifikasi backup...';[System.Windows.Forms.Application]::DoEvents()
  $verify=$cn.CreateCommand();$verify.CommandTimeout=0;$verify.CommandText='RESTORE VERIFYONLY FROM DISK=@backup WITH CHECKSUM';$verify.Parameters.Add('@backup',[System.Data.SqlDbType]::NVarChar,4000).Value=$backupPath;[void]$verify.ExecuteNonQuery()
  $files=@();$list=$cn.CreateCommand();$list.CommandTimeout=0;$list.CommandText='RESTORE FILELISTONLY FROM DISK=@backup';$list.Parameters.Add('@backup',[System.Data.SqlDbType]::NVarChar,4000).Value=$backupPath;$rd=$list.ExecuteReader()
  while($rd.Read()){$files+=[pscustomobject]@{LogicalName=[string]$rd['LogicalName'];Type=[string]$rd['Type']}};$rd.Close()
  if($files.Count -eq 0){throw 'Daftar file database pada backup kosong.'}
  $dataPath=Get-SqlDefaultPath $cn 'InstanceDefaultDataPath' 0;$logPath=Get-SqlDefaultPath $cn 'InstanceDefaultLogPath' 1
  $restore=$cn.CreateCommand();$restore.CommandTimeout=0;$restore.Parameters.Add('@backup',[System.Data.SqlDbType]::NVarChar,4000).Value=$backupPath;$moves=@();$dataNo=0;$logNo=0
  foreach($file in $files){
   if($file.Type -eq 'L'){$logNo++;$physical=Join-Path $logPath ($destinationName+'_log'+$(if($logNo -gt 1){'_'+$logNo}else{''})+'.ldf')}
   else{$dataNo++;$physical=Join-Path $dataPath ($destinationName+$(if($dataNo -gt 1){'_'+$dataNo}else{''})+'.mdf')}
   if(Test-Path -LiteralPath $physical){throw 'File tujuan sudah ada: '+$physical}
   $logicalParam='@logical'+$moves.Count;$physicalParam='@physical'+$moves.Count
   $restore.Parameters.Add($logicalParam,[System.Data.SqlDbType]::NVarChar,128).Value=$file.LogicalName;$restore.Parameters.Add($physicalParam,[System.Data.SqlDbType]::NVarChar,4000).Value=$physical
   $moves+=('MOVE '+$logicalParam+' TO '+$physicalParam)
  }
  $restore.CommandText='RESTORE DATABASE '+(Quote-SqlIdentifier $destinationName)+' FROM DISK=@backup WITH '+($moves -join ',')+',RECOVERY,STATS=10'
  $statusLabel.Text='Memulihkan database baru...';[System.Windows.Forms.Application]::DoEvents();[void]$restore.ExecuteNonQuery()
 }finally{$cn.Close()}
 $check=[System.Data.SqlClient.SqlConnection]::new((Get-MasterConnectionString));$check.Open()
 try{
   $cmd=$check.CreateCommand();$cmd.CommandText='SELECT COUNT(*) FROM '+(Quote-SqlIdentifier $destinationName)+'.sys.tables WHERE name IN(''tbio01_backup'',''treg_backup'',''tkrs06_backup'',''t_absensi14_backup'')';$tables=[int]$cmd.ExecuteScalar()
   if($tables -ne 4){throw 'Restore selesai, tetapi tabel backup wajib tidak lengkap. Database tidak dihapus otomatis.'}
   $cmd=$check.CreateCommand();$cmd.CommandText='SELECT (SELECT COUNT(*) FROM '+(Quote-SqlIdentifier $destinationName)+'.dbo.tbio01_backup) BioRows,(SELECT COUNT(*) FROM '+(Quote-SqlIdentifier $destinationName)+'.dbo.treg_backup) RegRows,(SELECT COUNT(*) FROM '+(Quote-SqlIdentifier $destinationName)+'.dbo.tkrs06_backup) KrsRows,(SELECT COUNT(*) FROM '+(Quote-SqlIdentifier $destinationName)+'.dbo.t_absensi14_backup) AbsRows';$rd=$cmd.ExecuteReader();[void]$rd.Read();$summary='Database '+$destinationName+' berhasil dibuat.'+[Environment]::NewLine+'Biodata: '+([int64]$rd['BioRows']).ToString('N0')+[Environment]::NewLine+'Registrasi: '+([int64]$rd['RegRows']).ToString('N0')+[Environment]::NewLine+'KRS: '+([int64]$rd['KrsRows']).ToString('N0')+[Environment]::NewLine+'Absensi: '+([int64]$rd['AbsRows']).ToString('N0');$rd.Close();return $summary
 }finally{$check.Close()}
}

$form=New-Object System.Windows.Forms.Form;$form.Text='Pemulihan Database Backup';$form.Size=New-Object Drawing.Size(720,300);$form.StartPosition='CenterScreen';$form.FormBorderStyle='FixedDialog';$form.MaximizeBox=$false
$lblFile=New-Object Windows.Forms.Label;$lblFile.Text='File backup (.bak)';$lblFile.Location=New-Object Drawing.Point(20,22);$lblFile.AutoSize=$true
$txtFile=New-Object Windows.Forms.TextBox;$txtFile.Location=New-Object Drawing.Point(20,45);$txtFile.Size=New-Object Drawing.Size(570,24)
$btnBrowse=New-Object Windows.Forms.Button;$btnBrowse.Text='Pilih File';$btnBrowse.Location=New-Object Drawing.Point(600,43);$btnBrowse.Size=New-Object Drawing.Size(90,28)
$lblDb=New-Object Windows.Forms.Label;$lblDb.Text='Nama database baru';$lblDb.Location=New-Object Drawing.Point(20,88);$lblDb.AutoSize=$true
$txtDb=New-Object Windows.Forms.TextBox;$txtDb.Location=New-Object Drawing.Point(20,111);$txtDb.Size=New-Object Drawing.Size(350,24);$txtDb.Text='dec_dummy_backup_import_'+(Get-Date -Format 'yyyyMMdd_HHmm')
$btnRestore=New-Object Windows.Forms.Button;$btnRestore.Text='Verifikasi dan Restore';$btnRestore.Location=New-Object Drawing.Point(20,157);$btnRestore.Size=New-Object Drawing.Size(180,34);$btnRestore.BackColor=[Drawing.Color]::FromArgb(0,166,90);$btnRestore.ForeColor=[Drawing.Color]::White
$lblStatus=New-Object Windows.Forms.Label;$lblStatus.Text='Pilih file ekspor dan tentukan nama database baru.';$lblStatus.Location=New-Object Drawing.Point(20,210);$lblStatus.Size=New-Object Drawing.Size(670,40)
$dialog=New-Object Windows.Forms.OpenFileDialog;$dialog.Filter='SQL Server backup (*.bak)|*.bak';$dialog.CheckFileExists=$true
$btnBrowse.Add_Click({if($dialog.ShowDialog() -eq 'OK'){$txtFile.Text=$dialog.FileName}})
$btnRestore.Add_Click({
 if([Windows.Forms.MessageBox]::Show('Restore akan membuat database baru. Lanjutkan?','Konfirmasi',[Windows.Forms.MessageBoxButtons]::YesNo,[Windows.Forms.MessageBoxIcon]::Question) -ne 'Yes'){return}
 $btnRestore.Enabled=$false
 try{$result=Restore-BackupFile $txtFile.Text.Trim() $txtDb.Text.Trim() $lblStatus;$lblStatus.Text='Restore berhasil.';[Windows.Forms.MessageBox]::Show($result,'Berhasil',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Information)|Out-Null}
 catch{$lblStatus.Text='Restore gagal.';[Windows.Forms.MessageBox]::Show($_.Exception.Message,'Restore gagal',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Error)|Out-Null}
 finally{$btnRestore.Enabled=$true}
})
$form.Controls.AddRange(@($lblFile,$txtFile,$btnBrowse,$lblDb,$txtDb,$btnRestore,$lblStatus));[void]$form.ShowDialog()
