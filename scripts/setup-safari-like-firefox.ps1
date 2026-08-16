$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$MacRoot = 'C:\MacStyle'
$ApplyScript = Join-Path $MacRoot 'Apply-SafariLike-Firefox.ps1'
New-Item -ItemType Directory -Force -Path $MacRoot | Out-Null

Write-Host '==> Instalando Firefox atual para a experiencia Safari-like'
$Firefox = 'C:\Program Files\Mozilla Firefox\firefox.exe'
if (-not (Test-Path $Firefox)) {
    $Installer = Join-Path $MacRoot 'FirefoxSetup.exe'
    Invoke-WebRequest -Uri 'https://download.mozilla.org/?product=firefox-latest-ssl&os=win64&lang=pt-BR' -OutFile $Installer
    $Process = Start-Process -FilePath $Installer -ArgumentList '/S' -Wait -PassThru
    if ($Process.ExitCode -ne 0 -and -not (Test-Path $Firefox)) {
        throw "Firefox installer returned $($Process.ExitCode)"
    }
}

if (-not (Test-Path $Firefox)) {
    throw 'Firefox nao foi encontrado apos a instalacao.'
}
Write-Host "Firefox pronto: $Firefox"

Write-Host '==> Preparando configuracao Safari-like para o login grafico'
$SourceApply = Join-Path $PSScriptRoot 'apply-safari-like-firefox-user.ps1'
if (-not (Test-Path $SourceApply)) {
    throw "Script auxiliar nao encontrado: $SourceApply"
}
Copy-Item -Path $SourceApply -Destination $ApplyScript -Force

$StartupDir = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup'
New-Item -ItemType Directory -Force -Path $StartupDir | Out-Null
$StartupFile = Join-Path $StartupDir 'SafariLike-Interactive.cmd'
$StartupLine = '@powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $ApplyScript
Set-Content -Path $StartupFile -Value $StartupLine -Encoding ASCII

Write-Host 'Safari-like Firefox sera configurado dentro da sessao RDP do cloudpc.'
