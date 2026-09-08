[CmdletBinding()]
param([string]$CertificatePath='C:\BackupAgent\LintarBackupHttps.cer',[string]$ConfigPath='C:\BackupAgent\agent.config.production.json')
$ErrorActionPreference='Stop'
$admin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if(-not $admin){throw 'Jalankan PowerShell sebagai Administrator pada laptop backup.'}
if(-not (Test-Path -LiteralPath $CertificatePath)){throw 'Sertifikat publik HTTPS belum tersedia. Jalankan configure_iis_https.ps1 pada server IIS lebih dahulu.'}
Import-Certificate -FilePath $CertificatePath -CertStoreLocation 'Cert:\LocalMachine\Root'|Out-Null
$config=Get-Content -LiteralPath $ConfigPath -Raw|ConvertFrom-Json
$config.ApiBaseUrl=([string]$config.ApiBaseUrl)-replace '^http://','https://'
$config|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $ConfigPath -Encoding UTF8
Invoke-RestMethod -Method Post -Uri ($config.ApiBaseUrl.TrimEnd('/')+'/agent.aspx?action=heartbeat') -Headers @{'X-Backup-Agent-Key'=[string]$config.ApiKey} -ContentType 'application/json' -Body '{"databaseReady":true,"message":"Verifikasi HTTPS"}'|Out-Null
Write-Output ('HTTPS_TRUSTED ApiBaseUrl='+$config.ApiBaseUrl)
