$ErrorActionPreference = 'SilentlyContinue'

if ($env:USERNAME -ine 'cloudpc') { exit 0 }

$MacRoot = 'C:\MacStyle'
$CursorRoot = Join-Path $MacRoot 'AppleCursor'
$Wallpaper = Join-Path $MacRoot 'mac-style-wallpaper.bmp'
$ShellScript = Join-Path $MacRoot 'MacBook-Lite-Shell.ps1'
$LogFile = Join-Path $MacRoot 'user-style.log'

function Write-StyleLog {
    param([string]$Message)
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $LogFile -Value "[$stamp] $Message"
}

Write-StyleLog "Stable MacBook personalization started for $env:USERNAME / session $env:SESSIONNAME"
Start-Sleep -Seconds 3

# Keep Windows itself light and predictable. The Mac-like look is provided by the
# lightweight overlay instead of replacing Explorer or using a third-party shell.
$Advanced = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
New-Item -Path $Advanced -Force | Out-Null
Set-ItemProperty -Path $Advanced -Name TaskbarAl -Type DWord -Value 1
Set-ItemProperty -Path $Advanced -Name TaskbarDa -Type DWord -Value 0
Set-ItemProperty -Path $Advanced -Name ShowTaskViewButton -Type DWord -Value 0

$Search = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'
New-Item -Path $Search -Force | Out-Null
Set-ItemProperty -Path $Search -Name SearchboxTaskbarMode -Type DWord -Value 0

$Personalize = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
New-Item -Path $Personalize -Force | Out-Null
Set-ItemProperty -Path $Personalize -Name AppsUseLightTheme -Type DWord -Value 1
Set-ItemProperty -Path $Personalize -Name SystemUsesLightTheme -Type DWord -Value 1
# Disable native Windows transparency to reduce RDP rendering glitches. The custom
# MacBook bars use their own simple alpha layer instead.
Set-ItemProperty -Path $Personalize -Name EnableTransparency -Type DWord -Value 0

$Desktop = 'HKCU:\Control Panel\Desktop'
New-Item -Path $Desktop -Force | Out-Null
Set-ItemProperty -Path $Desktop -Name MenuShowDelay -Value '100'
Set-ItemProperty -Path $Desktop -Name WallpaperStyle -Value '10'
Set-ItemProperty -Path $Desktop -Name TileWallpaper -Value '0'

$WindowMetrics = 'HKCU:\Control Panel\Desktop\WindowMetrics'
New-Item -Path $WindowMetrics -Force | Out-Null
Set-ItemProperty -Path $WindowMetrics -Name MinAnimate -Value '1'

if (-not ('MacStyle.NativeMethods' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace MacStyle {
    public static class NativeMethods {
        [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
        public static extern bool SystemParametersInfo(int action, int param, string value, int flags);

        [DllImport("user32.dll", SetLastError=true)]
        public static extern bool SystemParametersInfo(int action, int param, IntPtr value, int flags);
    }
}
'@
}

function Apply-Wallpaper {
    if (Test-Path $Wallpaper) {
        Set-ItemProperty -Path $Desktop -Name Wallpaper -Value $Wallpaper
        [MacStyle.NativeMethods]::SystemParametersInfo(20, 0, $Wallpaper, 3) | Out-Null
        Write-StyleLog "Wallpaper applied: $Wallpaper"
    } else {
        Write-StyleLog "Wallpaper missing: $Wallpaper"
    }
}

$CursorFiles = @()
if (Test-Path $CursorRoot) {
    $CursorFiles = Get-ChildItem -Path $CursorRoot -Recurse -File |
        Where-Object { $_.Extension -in @('.cur', '.ani') }
}
Write-StyleLog "Apple Cursor package files found: $($CursorFiles.Count)"

function Find-AppleCursor {
    param([string[]]$Candidates)

    foreach ($candidate in $Candidates) {
        $exact = $CursorFiles | Where-Object { $_.BaseName -ieq $candidate } | Select-Object -First 1
        if ($exact) { return $exact.FullName }
    }

    foreach ($candidate in $Candidates) {
        $partial = $CursorFiles | Where-Object { $_.BaseName -match [regex]::Escape($candidate) } | Select-Object -First 1
        if ($partial) { return $partial.FullName }
    }

    return $null
}

$CursorMap = [ordered]@{
    Arrow       = @('Pointer','left_ptr')
    Help        = @('Help','question_arrow')
    AppStarting = @('Work','left_ptr_watch')
    Wait        = @('Busy','wait')
    Crosshair   = @('Cross','crosshair','cross')
    IBeam       = @('Text','xterm')
    NWPen       = @('Handwriting','pencil')
    No          = @('Unavailiable','Unavailable','crossed_circle')
    SizeNS      = @('Vert','sb_v_double_arrow')
    SizeWE      = @('Horz','sb_h_double_arrow')
    SizeNWSE    = @('Dng1','bottom_right_corner')
    SizeNESW    = @('Dng2','bottom_left_corner')
    SizeAll     = @('Move','all-scroll')
    UpArrow     = @('Alternate','right_ptr')
    Hand        = @('Link','hand2')
    Pin         = @('Pin','pin')
    Person      = @('Person','person')
}

$CursorKey = 'HKCU:\Control Panel\Cursors'
$SchemesKey = 'HKCU:\Control Panel\Cursors\Schemes'
New-Item -Path $CursorKey -Force | Out-Null
New-Item -Path $SchemesKey -Force | Out-Null
Set-ItemProperty -Path $CursorKey -Name CursorBaseSize -Type DWord -Value 32

$Resolved = [ordered]@{}
$Applied = 0
foreach ($entry in $CursorMap.GetEnumerator()) {
    $file = Find-AppleCursor -Candidates $entry.Value
    if ($file) {
        Set-ItemProperty -Path $CursorKey -Name $entry.Key -Value $file
        $Resolved[$entry.Key] = $file
        $Applied++
    } else {
        $Resolved[$entry.Key] = ''
    }
}

$SchemeOrder = @(
    'Arrow','Help','AppStarting','Wait','Crosshair','IBeam','NWPen','No',
    'SizeNS','SizeWE','SizeNWSE','SizeNESW','SizeAll','UpArrow','Hand','Pin','Person'
)
$SchemeString = (($SchemeOrder | ForEach-Object { [string]$Resolved[$_] }) -join ',')
New-ItemProperty -Path $SchemesKey -Name 'macOS Complete' -Value $SchemeString -PropertyType String -Force | Out-Null
Set-Item -Path $CursorKey -Value 'macOS Complete'
[MacStyle.NativeMethods]::SystemParametersInfo(0x0057, 0, [IntPtr]::Zero, 3) | Out-Null
Write-StyleLog "macOS Complete cursor scheme applied: $Applied/$($CursorMap.Count) states"

Apply-Wallpaper

# IMPORTANT: do not kill/restart Explorer. That was a source of flicker and RDP shell bugs.
# Launch the lightweight MacBook overlay in its own STA PowerShell process.
if (Test-Path $ShellScript) {
    Start-Process -FilePath 'powershell.exe' -ArgumentList @(
        '-NoProfile',
        '-STA',
        '-ExecutionPolicy','Bypass',
        '-WindowStyle','Hidden',
        '-File',"`"$ShellScript`""
    ) -WindowStyle Hidden
    Write-StyleLog 'MacBook Lite Shell launch requested.'
} else {
    Write-StyleLog "MacBook Lite Shell missing: $ShellScript"
}

Write-StyleLog 'Stable MacBook personalization completed without restarting Explorer.'
