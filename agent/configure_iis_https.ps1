[CmdletBinding()]
param([string]$SiteName='Default Web Site',[string]$ServerIp='127.0.0.1',[string]$CertificateOutput=(Join-Path $PSScriptRoot 'LintarBackupHttps.cer'))
$ErrorActionPreference='Stop'
$admin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if(-not $admin){throw 'Jalankan PowerShell sebagai Administrator pada server IIS.'}
Import-Module WebAdministration
if(-not (Get-Website -Name $SiteName -ErrorAction SilentlyContinue)){throw "Website IIS '$SiteName' tidak ditemukan."}
$cert=Get-ChildItem Cert:\LocalMachine\My|Where-Object{$_.FriendlyName -eq 'LINTAR Backup API HTTPS' -and $_.NotAfter -gt (Get-Date).AddDays(30)}|Sort-Object NotAfter -Descending|Select-Object -First 1
if($null -eq $cert){$cert=New-SelfSignedCertificate -Type SSLServerAuthentication -Subject "CN=$ServerIp" -TextExtension @("2.5.29.17={text}ipaddress=$ServerIp") -CertStoreLocation 'Cert:\LocalMachine\My' -FriendlyName 'LINTAR Backup API HTTPS' -KeyAlgorithm RSA -KeyLength 3072 -HashAlgorithm SHA256 -NotAfter (Get-Date).AddYears(3) -KeyExportPolicy NonExportable}
if(-not (Get-WebBinding -Name $SiteName -Protocol https -Port 443 -ErrorAction SilentlyContinue)){New-WebBinding -Name $SiteName -Protocol https -Port 443 -IPAddress '*'}
$binding=Get-WebBinding -Name $SiteName -Protocol https -Port 443
$binding.AddSslCertificate($cert.Thumbprint,'My')
Export-Certificate -Cert $cert -FilePath $CertificateOutput -Force|Out-Null
Write-Output ("HTTPS_READY Thumbprint={0}; Expires={1:o}; Certificate={2}" -f $cert.Thumbprint,$cert.NotAfter,$CertificateOutput)
