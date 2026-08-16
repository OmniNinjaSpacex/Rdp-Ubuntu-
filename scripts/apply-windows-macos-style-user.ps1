$ErrorActionPreference = 'SilentlyContinue'

$MacRoot = 'C:\MacStyle'
$CursorRoot = Join-Path $MacRoot 'AppleCursor'
$Wallpaper = Join-Path $MacRoot 'mac-style-wallpaper.bmp'

Write-Host 'Applying lightweight macOS-style user settings...'

# Windows taskbar: centered, cleaner and less cluttered.
$Advanced = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
New-Item -Path $Advanced -Force | Out-Null
Set-ItemProperty -Path $Advanced -Name TaskbarAl -Type DWord -Value 1
Set-ItemProperty -Path $Advanced -Name TaskbarDa -Type DWord -Value 0
Set-ItemProperty -Path $Advanced -Name ShowTaskViewButton -Type DWord -Value 0

$Search = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'
New-Item -Path $Search -Force | Out-Null
Set-ItemProperty -Path $Search -Name SearchboxTaskbarMode -Type DWord -Value 0

# Light, translucent look while avoiding expensive shell animations.
$Personalize = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
New-Item -Path $Personalize -Force | Out-Null
Set-ItemProperty -Path $Personalize -Name AppsUseLightTheme -Type DWord -Value 1
Set-ItemProperty -Path $Personalize -Name SystemUsesLightTheme -Type DWord -Value 1
Set-ItemProperty -Path $Personalize -Name EnableTransparency -Type DWord -Value 1

$Desktop = 'HKCU:\Control Panel\Desktop'
New-Item -Path $Desktop -Force | Out-Null
Set-ItemProperty -Path $Desktop -Name MenuShowDelay -Value '80'
Set-ItemProperty -Path $Desktop -Name WallpaperStyle -Value '10'
Set-ItemProperty -Path $Desktop -Name TileWallpaper -Value '0'
if (Test-Path $Wallpaper) {
    Set-ItemProperty -Path $Desktop -Name Wallpaper -Value $Wallpaper
}

$WindowMetrics = 'HKCU:\Control Panel\Desktop\WindowMetrics'
New-Item -Path $WindowMetrics -Force | Out-Null
Set-ItemProperty -Path $WindowMetrics -Name MinAnimate -Value '0'

# Install/register Apple Cursor for this profile and apply the macOS cursor scheme.
$Inf = Get-ChildItem -Path $CursorRoot -Filter 'install.inf' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if ($Inf) {
    Start-Process -FilePath 'rundll32.exe' -ArgumentList @('setupapi.dll,InstallHinfSection','DefaultInstall','132',$Inf.FullName) -Wait -WindowStyle Hidden
    Start-Sleep -Seconds 1
}

$Schemes = 'HKCU:\Control Panel\Cursors\Schemes'
if (Test-Path $Schemes) {
    $SchemeProperties = (Get-ItemProperty -Path $Schemes).PSObject.Properties
    $Scheme = $SchemeProperties | Where-Object { $_.Name -match 'macOS' } | Select-Object -First 1

    if ($Scheme -and $Scheme.Value) {
        $CursorKey = 'HKCU:\Control Panel\Cursors'
        New-Item -Path $CursorKey -Force | Out-Null
        $Parts = [string]$Scheme.Value -split ','
        $Names = @(
            'Arrow','Help','AppStarting','Wait','Crosshair','IBeam','NWPen','No',
            'SizeNS','SizeWE','SizeNWSE','SizeNESW','SizeAll','UpArrow','Hand','Pin','Person'
        )

        Set-Item -Path $CursorKey -Value $Scheme.Name
        Set-ItemProperty -Path $CursorKey -Name CursorBaseSize -Value '32'

        for ($i = 0; $i -lt [Math]::Min($Names.Count, $Parts.Count); $i++) {
            $Value = $Parts[$i].Trim()
            if (-not [string]::IsNullOrWhiteSpace($Value)) {
                Set-ItemProperty -Path $CursorKey -Name $Names[$i] -Value $Value
            }
        }
    }
}

# Refresh wallpaper and per-user shell settings.
Start-Process -FilePath 'rundll32.exe' -ArgumentList 'user32.dll,UpdatePerUserSystemParameters' -WindowStyle Hidden -Wait

# Start Seelen UI if it is installed. If not, Windows stays fully usable.
$CandidateRoots = @(
    'C:\Program Files\Seelen UI',
    'C:\Program Files\Seelen',
    (Join-Path $env:LOCALAPPDATA 'Programs\Seelen UI')
)

$SeelenExe = $null
foreach ($Root in $CandidateRoots) {
    if (Test-Path $Root) {
        $SeelenExe = Get-ChildItem -Path $Root -Filter '*.exe' -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match 'seelen' -and $_.Name -notmatch 'setup|uninstall|update' } |
            Select-Object -First 1
        if ($SeelenExe) { break }
    }
}

if ($SeelenExe) {
    Start-Process -FilePath $SeelenExe.FullName
}

# Restart Explorer once so the taskbar, wallpaper and cursors are refreshed.
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 700
Start-Process -FilePath 'explorer.exe'

Write-Host 'macOS-style user settings applied.'
