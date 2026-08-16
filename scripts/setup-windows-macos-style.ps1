$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$RdpUser = if ($env:RDP_USER) { $env:RDP_USER } else { 'cloudpc' }
$RdpPassword = $env:RDP_PASSWORD
$TsAuthKey = $env:TAILSCALE_AUTHKEY
$TsHostname = if ($env:TS_HOSTNAME) { $env:TS_HOSTNAME } else { "gh-macwin-$env:GITHUB_RUN_ID" }

if ([string]::IsNullOrWhiteSpace($RdpPassword)) { throw 'RDP_PASSWORD nao definido.' }
if ([string]::IsNullOrWhiteSpace($TsAuthKey)) { throw 'TAILSCALE_AUTHKEY nao definido.' }
if ($RdpPassword.Length -lt 12) { throw 'RDP_PASSWORD deve ter pelo menos 12 caracteres.' }

$MacRoot = 'C:\MacStyle'
$CursorRoot = Join-Path $MacRoot 'AppleCursor'
New-Item -ItemType Directory -Force -Path $MacRoot, $CursorRoot | Out-Null

Write-Host '==> Habilitando RDP nativo do Windows'
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -Value 0
Enable-NetFirewallRule -DisplayGroup 'Remote Desktop'
Set-Service -Name TermService -StartupType Automatic
Start-Service -Name TermService -ErrorAction SilentlyContinue

Write-Host "==> Criando/atualizando usuario $RdpUser"
$SecurePass = ConvertTo-SecureString $RdpPassword -AsPlainText -Force
$Existing = Get-LocalUser -Name $RdpUser -ErrorAction SilentlyContinue
if ($Existing) {
    Set-LocalUser -Name $RdpUser -Password $SecurePass -PasswordNeverExpires $true
} else {
    New-LocalUser -Name $RdpUser -Password $SecurePass -PasswordNeverExpires -AccountNeverExpires | Out-Null
}
foreach ($group in @('Administrators', 'Remote Desktop Users')) {
    try { Add-LocalGroupMember -Group $group -Member $RdpUser -ErrorAction Stop } catch {
        if ($_.Exception.Message -notmatch 'already a member') { Write-Warning $_.Exception.Message }
    }
}

Write-Host '==> Instalando Apple Cursor para Windows'
$CursorZip = Join-Path $MacRoot 'macOS-Windows.zip'
Invoke-WebRequest -Uri 'https://github.com/ful1e5/apple_cursor/releases/download/v2.0.1/macOS-Windows.zip' -OutFile $CursorZip
Expand-Archive -Path $CursorZip -DestinationPath $CursorRoot -Force
$CursorInf = Get-ChildItem -Path $CursorRoot -Filter 'install.inf' -Recurse | Select-Object -First 1
if (-not $CursorInf) { throw 'install.inf do Apple Cursor nao encontrado.' }
$CursorInstall = Start-Process -FilePath 'rundll32.exe' -ArgumentList "setupapi.dll,InstallHinfSection DefaultInstall 132 `"$($CursorInf.FullName)`"" -Wait -PassThru
Write-Host "Apple Cursor instalado. Codigo: $($CursorInstall.ExitCode)"

Write-Host '==> Gerando wallpaper abstrato inspirado em macOS'
Add-Type -AssemblyName System.Drawing
$wallpaper = Join-Path $MacRoot 'mac-style-wallpaper.bmp'
$bmp = New-Object System.Drawing.Bitmap 1920,1080
$g = [System.Drawing.Graphics]::FromImage($bmp)
$rect = New-Object System.Drawing.Rectangle 0,0,1920,1080
$brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, [System.Drawing.Color]::FromArgb(255,35,79,190), [System.Drawing.Color]::FromArgb(255,154,73,210), 35)
$g.FillRectangle($brush,$rect)
$ellipseBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(65,255,255,255))
$g.FillEllipse($ellipseBrush,1050,-180,1050,900)
$ellipseBrush2 = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(45,80,220,255))
$g.FillEllipse($ellipseBrush2,-300,480,1200,800)
$bmp.Save($wallpaper,[System.Drawing.Imaging.ImageFormat]::Bmp)
$ellipseBrush2.Dispose(); $ellipseBrush.Dispose(); $brush.Dispose(); $g.Dispose(); $bmp.Dispose()

Write-Host '==> Instalando Seelen UI (dock/barra/launcher estilo macOS)'
$SeelenInstalled = $false
try {
    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/eythaann/Seelen-UI/releases/latest' -Headers @{ 'User-Agent' = 'GitHub-Actions-MacStyle' }
    $asset = $release.assets | Where-Object { $_.name -match '^Seelen\.UI_.*_x64-setup\.exe$' } | Select-Object -First 1
    if (-not $asset) { throw 'Instalador x64 do Seelen UI nao encontrado na release atual.' }
    $SeelenSetup = Join-Path $MacRoot 'SeelenUI-setup.exe'
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $SeelenSetup
    $proc = Start-Process -FilePath $SeelenSetup -ArgumentList '/S','/AllUsers' -Wait -PassThru
    if ($proc.ExitCode -eq 0) { $SeelenInstalled = $true } else { Write-Warning "Seelen UI retornou codigo $($proc.ExitCode). O Windows/RDP continuara funcionando." }
} catch {
    Write-Warning "Nao foi possivel instalar Seelen UI automaticamente: $($_.Exception.Message)"
}

Write-Host '==> Criando configuracao de primeiro logon para o usuario RDP'
$FirstLogon = Join-Path $MacRoot 'Apply-MacStyle.ps1'
$FirstLogonContent = @'
$ErrorActionPreference = 'SilentlyContinue'
if ($env:USERNAME -ne '__RDP_USER__') { exit 0 }

$MacRoot = 'C:\MacStyle'
$CursorRoot = Join-Path $MacRoot 'AppleCursor'
$wallpaper = Join-Path $MacRoot 'mac-style-wallpaper.bmp'

# Visual limpo e leve: centraliza a barra e remove elementos extras.
$adv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
New-Item -Path $adv -Force | Out-Null
Set-ItemProperty $adv -Name TaskbarAl -Type DWord -Value 1
Set-ItemProperty $adv -Name TaskbarDa -Type DWord -Value 0
Set-ItemProperty $adv -Name ShowTaskViewButton -Type DWord -Value 0
$search = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'
New-Item -Path $search -Force | Out-Null
Set-ItemProperty $search -Name SearchboxTaskbarMode -Type DWord -Value 0

# Tema claro com transparencia, mantendo a interface responsiva.
$personalize = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
New-Item -Path $personalize -Force | Out-Null
Set-ItemProperty $personalize -Name AppsUseLightTheme -Type DWord -Value 1
Set-ItemProperty $personalize -Name SystemUsesLightTheme -Type DWord -Value 1
Set-ItemProperty $personalize -Name EnableTransparency -Type DWord -Value 1

# Reduz animacoes do shell do Windows; o dock pode manter suas proprias animacoes.
$desktop = 'HKCU:\Control Panel\Desktop'
Set-ItemProperty $desktop -Name MenuShowDelay -Value '80'
$windowMetrics = 'HKCU:\Control Panel\Desktop\WindowMetrics'
Set-ItemProperty $windowMetrics -Name MinAnimate -Value '0'

# Wallpaper local e leve.
Set-ItemProperty $desktop -Name WallpaperStyle -Value '10'
Set-ItemProperty $desktop -Name TileWallpaper -Value '0'
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class NativeMacStyle {
  [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)]
  public static extern bool SystemParametersInfo(int action, int param, string value, int flags);
}
"@
[NativeMacStyle]::SystemParametersInfo(20,0,$wallpaper,3) | Out-Null

# Registra o Apple Cursor para este perfil e aplica a scheme completa.
$inf = Get-ChildItem -Path $CursorRoot -Filter install.inf -Recurse | Select-Object -First 1
if ($inf) {
  Start-Process rundll32.exe -ArgumentList "setupapi.dll,InstallHinfSection DefaultInstall 132 `"$($inf.FullName)`"" -Wait
  Start-Sleep -Seconds 2
}
$schemes = 'HKCU:\Control Panel\Cursors\Schemes'
$schemeProp = $null
if (Test-Path $schemes) {
  $props = Get-ItemProperty $schemes
  $schemeProp = $props.PSObject.Properties | Where-Object { $_.Name -match 'macOS' } | Select-Object -First 1
}
if ($schemeProp -and $schemeProp.Value) {
  $parts = [string]$schemeProp.Value -split ','
  $cursorNames = @('Arrow','Help','AppStarting','Wait','Crosshair','IBeam','NWPen','No','SizeNS','SizeWE','SizeNWSE','SizeNESW','SizeAll','UpArrow','Hand','Pin','Person')
  $cursorKey = 'HKCU:\Control Panel\Cursors'
  New-Item -Path $cursorKey -Force | Out-Null
  Set-Item -Path $cursorKey -Value $schemeProp.Name
  Set-ItemProperty $cursorKey -Name CursorBaseSize -Value '32'
  for ($i=0; $i -lt [Math]::Min($cursorNames.Count,$parts.Count); $i++) {
    if (-not [string]::IsNullOrWhiteSpace($parts[$i])) {
      Set-ItemProperty $cursorKey -Name $cursorNames[$i] -Value $parts[$i].Trim()
    }
  }
  [NativeMacStyle]::SystemParametersInfo(0x0057,0,$null,3) | Out-Null
}

# Inicia o Seelen UI se a instalacao estiver disponivel.
$locations = @(
  'C:\Program Files\Seelen UI',
  'C:\Program Files\Seelen',
  "$env:LOCALAPPDATA\Programs\Seelen UI"
)
$seelenExe = $null
foreach ($loc in $locations) {
  if (Test-Path $loc) {
    $seelenExe = Get-ChildItem $loc -Filter '*.exe' -Recurse | Where-Object { $_.Name -match 'seelen' -and $_.Name -notmatch 'uninstall|setup' } | Select-Object -First 1
    if ($seelenExe) { break }
  }
}
if (-not $seelenExe) {
  $uninstallRoots = @('HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')
  foreach ($root in $uninstallRoots) {
    $app = Get-ItemProperty $root | Where-Object { $_.DisplayName -match 'Seelen' } | Select-Object -First 1
    if ($app -and $app.InstallLocation -and (Test-Path $app.InstallLocation)) {
      $seelenExe = Get-ChildItem $app.InstallLocation -Filter '*.exe' -Recurse | Where-Object { $_.Name -match 'seelen' -and $_.Name -notmatch 'uninstall|setup' } | Select-Object -First 1
      if ($seelenExe) { break }
    }
  }
}
if ($seelenExe) { Start-Process $seelenExe.FullName }

# Reinicia o Explorer para aplicar a barra centralizada.
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
Start-Process explorer.exe
'@
$FirstLogonContent = $FirstLogonContent.Replace('__RDP_USER__', $RdpUser)
Set-Content -Path $FirstLogon -Value $FirstLogonContent -Encoding UTF8

# Executa o script em todo logon do cloudpc com privilegios altos; nao grava a senha no arquivo.
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$FirstLogon`""
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $RdpUser
try {
    Register-ScheduledTask -TaskName 'MacStyle-CloudPC' -Action $action -Trigger $trigger -User $RdpUser -Password $RdpPassword -RunLevel Highest -Force | Out-Null
} catch {
    Write-Warning "Falha ao registrar tarefa de personalizacao: $($_.Exception.Message)"
    $startup = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\MacStyle.cmd'
    Set-Content -Path $startup -Value "@powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$FirstLogon`""" -Encoding ASCII
}

Write-Host '==> Instalando Tailscale'
$TailscaleMsi = Join-Path $MacRoot 'tailscale.msi'
Invoke-WebRequest -Uri 'https://pkgs.tailscale.com/stable/tailscale-setup-latest-amd64.msi' -OutFile $TailscaleMsi
Start-Process msiexec.exe -ArgumentList '/i', $TailscaleMsi, '/quiet', '/norestart' -Wait
$TailscaleExe = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
if (-not (Test-Path $TailscaleExe)) { throw 'Tailscale.exe nao encontrado apos a instalacao.' }

Write-Host '==> Conectando Tailscale'
& $TailscaleExe up --authkey=$TsAuthKey --hostname=$TsHostname --accept-dns=false
$TsIp = (& $TailscaleExe ip -4 | Select-Object -First 1).Trim()
if ($TsIp -notmatch '^100\.') { throw "IPv4 Tailscale invalido: $TsIp" }

Write-Host '==> Limitando RDP a enderecos Tailscale'
try {
    Get-NetFirewallRule -DisplayGroup 'Remote Desktop' | Get-NetFirewallAddressFilter | Set-NetFirewallAddressFilter -RemoteAddress '100.64.0.0/10'
} catch {
    Write-Warning "Nao foi possivel restringir o filtro RDP: $($_.Exception.Message)"
}

@"
TAILSCALE_IP=$TsIp
RDP_USER=$RdpUser
SEELEN_INSTALLED=$SeelenInstalled
CURSOR_THEME=Apple Cursor macOS
"@ | Set-Content -Path 'C:\MacStyle\connection.env' -Encoding ASCII

Write-Host '==> Verificacao final'
Get-Service TermService | Format-Table Status,Name -AutoSize
Get-LocalUser -Name $RdpUser | Select-Object Name,Enabled,PasswordExpires | Format-List
Write-Host "Tailscale IP: $TsIp"
Write-Host "Usuario RDP: $RdpUser"
Write-Host "Seelen UI instalado: $SeelenInstalled"
Write-Host 'Windows macOS-style dev/test pronto.'
