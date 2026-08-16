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

Write-Host '==> Baixando Apple Cursor para Windows'
$CursorZip = Join-Path $MacRoot 'macOS-Windows.zip'
Invoke-WebRequest -Uri 'https://github.com/ful1e5/apple_cursor/releases/download/v2.0.1/macOS-Windows.zip' -OutFile $CursorZip
Expand-Archive -Path $CursorZip -DestinationPath $CursorRoot -Force
$CursorInf = Get-ChildItem -Path $CursorRoot -Filter 'install.inf' -Recurse | Select-Object -First 1
if (-not $CursorInf) { throw 'install.inf do Apple Cursor nao encontrado.' }
Write-Host "Apple Cursor preparado em $CursorRoot"

Write-Host '==> Gerando wallpaper abstrato inspirado em macOS'
Add-Type -AssemblyName System.Drawing
$Wallpaper = Join-Path $MacRoot 'mac-style-wallpaper.bmp'
$Bitmap = New-Object System.Drawing.Bitmap 1920,1080
$Graphics = [System.Drawing.Graphics]::FromImage($Bitmap)
$Rect = New-Object System.Drawing.Rectangle 0,0,1920,1080
$Gradient = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    $Rect,
    [System.Drawing.Color]::FromArgb(255,35,79,190),
    [System.Drawing.Color]::FromArgb(255,154,73,210),
    35
)
$Graphics.FillRectangle($Gradient, $Rect)
$Glow1 = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(65,255,255,255))
$Glow2 = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(45,80,220,255))
$Graphics.FillEllipse($Glow1, 1050, -180, 1050, 900)
$Graphics.FillEllipse($Glow2, -300, 480, 1200, 800)
$Bitmap.Save($Wallpaper, [System.Drawing.Imaging.ImageFormat]::Bmp)
$Glow2.Dispose()
$Glow1.Dispose()
$Gradient.Dispose()
$Graphics.Dispose()
$Bitmap.Dispose()

Write-Host '==> Copiando personalizacao do usuario'
$SourceApplyScript = Join-Path $PSScriptRoot 'apply-windows-macos-style-user.ps1'
if (-not (Test-Path $SourceApplyScript)) { throw "Script auxiliar nao encontrado: $SourceApplyScript" }
Copy-Item -Path $SourceApplyScript -Destination $ApplyScript -Force

Write-Host '==> Instalando Seelen UI (melhor esforco)'
$SeelenInstalled = $false
try {
    $Release = Invoke-RestMethod -Uri 'https://api.github.com/repos/eythaann/Seelen-UI/releases/latest' -Headers @{ 'User-Agent' = 'GitHub-Actions-MacStyle' }
    $Asset = $Release.assets |
        Where-Object { $_.name -match '^Seelen\.UI_.*_x64-setup\.exe$' } |
        Select-Object -First 1

    if (-not $Asset) { throw 'Instalador x64 do Seelen UI nao encontrado.' }

    $SeelenSetup = Join-Path $MacRoot 'SeelenUI-setup.exe'
    Invoke-WebRequest -Uri $Asset.browser_download_url -OutFile $SeelenSetup
    $SeelenProcess = Start-Process -FilePath $SeelenSetup -ArgumentList @('/S','/ALLUSERS') -Wait -PassThru

    if ($SeelenProcess.ExitCode -eq 0) {
        $SeelenInstalled = $true
        Write-Host 'Seelen UI instalado.'
    } else {
        Write-Warning "Seelen UI retornou codigo $($SeelenProcess.ExitCode). O Windows/RDP continuara funcionando."
    }
} catch {
    Write-Warning "Seelen UI nao foi instalado automaticamente: $($_.Exception.Message)"
}

Write-Host '==> Registrando personalizacao para o logon do cloudpc'
$TaskArguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $ApplyScript
$TaskAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $TaskArguments
$TaskTrigger = New-ScheduledTaskTrigger -AtLogOn -User $RdpUser

try {
    Register-ScheduledTask -TaskName 'MacStyle-CloudPC' -Action $TaskAction -Trigger $TaskTrigger -User $RdpUser -Password $RdpPassword -RunLevel Highest -Force | Out-Null
} catch {
    Write-Warning "Falha ao registrar tarefa com credenciais: $($_.Exception.Message)"
    $StartupDir = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup'
    New-Item -ItemType Directory -Force -Path $StartupDir | Out-Null
    $StartupFile = Join-Path $StartupDir 'MacStyle.cmd'
    $StartupLine = '@powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $ApplyScript
    Set-Content -Path $StartupFile -Value $StartupLine -Encoding ASCII
}

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
    "SEELEN_INSTALLED=$SeelenInstalled",
    'CURSOR_THEME=Apple Cursor macOS'
)
Set-Content -Path (Join-Path $MacRoot 'connection.env') -Value $ConnectionInfo -Encoding ASCII

Write-Host '==> Verificacao final'
Get-Service -Name TermService | Format-Table Status,Name -AutoSize
Get-LocalUser -Name $RdpUser | Select-Object Name,Enabled,PasswordExpires | Format-List
Write-Host "Tailscale IP: $TsIp"
Write-Host "Usuario RDP: $RdpUser"
Write-Host "Seelen UI instalado: $SeelenInstalled"
Write-Host 'Windows macOS-style dev/test pronto.'
