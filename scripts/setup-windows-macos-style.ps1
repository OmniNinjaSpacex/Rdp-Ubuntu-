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
$ApplyScript = Join-Path $MacRoot 'Apply-MacStyle.ps1'
$ShellScript = Join-Path $MacRoot 'MacBook-Lite-Shell.ps1'
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

foreach ($Group in @('Administrators', 'Remote Desktop Users')) {
    try {
        Add-LocalGroupMember -Group $Group -Member $RdpUser -ErrorAction Stop
    } catch {
        if ($_.Exception.Message -notmatch 'already a member') {
            Write-Warning $_.Exception.Message
        }
    }
}

Write-Host '==> Baixando pacote Apple Cursor completo para Windows'
$CursorZip = Join-Path $MacRoot 'macOS-Windows.zip'
Invoke-WebRequest -Uri 'https://github.com/ful1e5/apple_cursor/releases/download/v2.0.1/macOS-Windows.zip' -OutFile $CursorZip
Expand-Archive -Path $CursorZip -DestinationPath $CursorRoot -Force
$CursorInf = Get-ChildItem -Path $CursorRoot -Filter 'install.inf' -Recurse | Select-Object -First 1
if (-not $CursorInf) { throw 'install.inf do Apple Cursor nao encontrado.' }

$CursorFiles = Get-ChildItem -Path $CursorRoot -Recurse -File | Where-Object { $_.Extension -in @('.cur','.ani') }
if ($CursorFiles.Count -lt 10) {
    throw "Pacote Apple Cursor parece incompleto: somente $($CursorFiles.Count) arquivos .cur/.ani encontrados."
}
Write-Host "Apple Cursor completo preparado: $($CursorFiles.Count) arquivos de cursor."

Write-Host '==> Gerando wallpaper abstrato inspirado em macOS'
Add-Type -AssemblyName System.Drawing
$Wallpaper = Join-Path $MacRoot 'mac-style-wallpaper.bmp'
$Bitmap = New-Object System.Drawing.Bitmap 1920,1080
$Graphics = [System.Drawing.Graphics]::FromImage($Bitmap)
$Rect = New-Object System.Drawing.Rectangle 0,0,1920,1080
$Gradient = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    $Rect,
    [System.Drawing.Color]::FromArgb(255,28,53,128),
    [System.Drawing.Color]::FromArgb(255,151,76,196),
    32
)
$Graphics.FillRectangle($Gradient, $Rect)
$Glow1 = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(75,255,255,255))
$Glow2 = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(55,65,205,255))
$Glow3 = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(38,255,130,210))
$Graphics.FillEllipse($Glow1, 1080, -210, 1000, 850)
$Graphics.FillEllipse($Glow2, -260, 520, 1120, 760)
$Graphics.FillEllipse($Glow3, 570, 350, 950, 720)
$Bitmap.Save($Wallpaper, [System.Drawing.Imaging.ImageFormat]::Bmp)
$Glow3.Dispose()
$Glow2.Dispose()
$Glow1.Dispose()
$Gradient.Dispose()
$Graphics.Dispose()
$Bitmap.Dispose()

Write-Host '==> Copiando MacBook Stable Shell e personalizacao interativa'
$SourceApplyScript = Join-Path $PSScriptRoot 'apply-windows-macos-style-user.ps1'
$SourceShellScript = Join-Path $PSScriptRoot 'start-macbook-lite-shell.ps1'
if (-not (Test-Path $SourceApplyScript)) { throw "Script auxiliar nao encontrado: $SourceApplyScript" }
if (-not (Test-Path $SourceShellScript)) { throw "MacBook shell nao encontrado: $SourceShellScript" }
Copy-Item -Path $SourceApplyScript -Destination $ApplyScript -Force
Copy-Item -Path $SourceShellScript -Destination $ShellScript -Force

Write-Host '==> Registrando personalizacao dentro da sessao grafica RDP'
$StartupDir = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup'
New-Item -ItemType Directory -Force -Path $StartupDir | Out-Null
$StartupFile = Join-Path $StartupDir 'MacStyle-Interactive.cmd'
$StartupLine = '@powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $ApplyScript
Set-Content -Path $StartupFile -Value $StartupLine -Encoding ASCII

# Remove old task and any old Seelen autostart leftovers from previous versions.
Unregister-ScheduledTask -TaskName 'MacStyle-CloudPC' -Confirm:$false -ErrorAction SilentlyContinue
Get-Process -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessName -match 'seelen' } |
    Stop-Process -Force -ErrorAction SilentlyContinue

Write-Host '==> Instalando Tailscale'
$TailscaleMsi = Join-Path $MacRoot 'tailscale.msi'
Invoke-WebRequest -Uri 'https://pkgs.tailscale.com/stable/tailscale-setup-latest-amd64.msi' -OutFile $TailscaleMsi
Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/i', $TailscaleMsi, '/quiet', '/norestart') -Wait

$TailscaleExe = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
if (-not (Test-Path $TailscaleExe)) { throw 'Tailscale.exe nao encontrado apos a instalacao.' }

Write-Host '==> Conectando Tailscale'
& $TailscaleExe up --authkey=$TsAuthKey --hostname=$TsHostname --accept-dns=false
$TsIp = (& $TailscaleExe ip -4 | Select-Object -First 1).Trim()
if ($TsIp -notmatch '^100\.') { throw "IPv4 Tailscale invalido: $TsIp" }

Write-Host '==> Restringindo RDP a rede Tailscale'
try {
    Get-NetFirewallRule -DisplayGroup 'Remote Desktop' |
        Get-NetFirewallAddressFilter |
        Set-NetFirewallAddressFilter -RemoteAddress '100.64.0.0/10'
} catch {
    Write-Warning "Nao foi possivel restringir o filtro RDP: $($_.Exception.Message)"
}

$ConnectionInfo = @(
    "TAILSCALE_IP=$TsIp",
    "RDP_USER=$RdpUser",
    "CURSOR_FILES=$($CursorFiles.Count)",
    'CURSOR_THEME=macOS Complete',
    'MAC_SHELL=MacBook Stable Lite',
    'SEELEN_INSTALLED=False'
)
Set-Content -Path (Join-Path $MacRoot 'connection.env') -Value $ConnectionInfo -Encoding ASCII

Write-Host '==> Verificacao final'
Get-Service -Name TermService | Format-Table Status,Name -AutoSize
Get-LocalUser -Name $RdpUser | Select-Object Name,Enabled,PasswordExpires | Format-List
Write-Host "Tailscale IP: $TsIp"
Write-Host "Usuario RDP: $RdpUser"
Write-Host "Arquivos Apple Cursor: $($CursorFiles.Count)"
Write-Host 'MacBook Stable Lite shell preparado.'
Write-Host 'Windows macOS-style dev/test pronto.'
