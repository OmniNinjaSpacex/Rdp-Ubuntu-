$ErrorActionPreference = 'SilentlyContinue'

if ($env:USERNAME -ine 'cloudpc') { exit 0 }

$MacRoot = 'C:\MacStyle'
$CursorRoot = Join-Path $MacRoot 'AppleCursor'
$Wallpaper = Join-Path $MacRoot 'mac-style-wallpaper.bmp'
$LogFile = Join-Path $MacRoot 'user-style.log'

function Write-StyleLog {
    param([string]$Message)
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $LogFile -Value "[$stamp] $Message"
}

Write-StyleLog "Interactive personalization started for $env:USERNAME / session $env:SESSIONNAME"
Start-Sleep -Seconds 3

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
Set-ItemProperty -Path $Personalize -Name EnableTransparency -Type DWord -Value 1

$VisualEffects = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
New-Item -Path $VisualEffects -Force | Out-Null
Set-ItemProperty -Path $VisualEffects -Name VisualFXSetting -Type DWord -Value 1

$Desktop = 'HKCU:\Control Panel\Desktop'
New-Item -Path $Desktop -Force | Out-Null
Set-ItemProperty -Path $Desktop -Name MenuShowDelay -Value '120'
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

# Load every .cur/.ani from the real Windows package.
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

# Complete Windows system cursor map. The Apple package's Work/Busy states are animated .ani files.
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
        Write-StyleLog "Cursor $($entry.Key) -> $file"
        $Applied++
    } else {
        $Resolved[$entry.Key] = ''
        Write-StyleLog "Cursor state missing: $($entry.Key); candidates=$($entry.Value -join ',')"
    }
}

# Register a real selectable Windows cursor scheme in the exact system slot order.
$SchemeOrder = @(
    'Arrow','Help','AppStarting','Wait','Crosshair','IBeam','NWPen','No',
    'SizeNS','SizeWE','SizeNWSE','SizeNESW','SizeAll','UpArrow','Hand','Pin','Person'
)
$SchemeValues = foreach ($name in $SchemeOrder) { [string]$Resolved[$name] }
$SchemeString = $SchemeValues -join ','
New-ItemProperty -Path $SchemesKey -Name 'macOS Complete' -Value $SchemeString -PropertyType String -Force | Out-Null
Set-Item -Path $CursorKey -Value 'macOS Complete'

if ($Applied -gt 0) {
    [MacStyle.NativeMethods]::SystemParametersInfo(0x0057, 0, [IntPtr]::Zero, 3) | Out-Null
    Write-StyleLog "macOS Complete cursor scheme applied: $Applied/$($CursorMap.Count) Windows states"
} else {
    Write-StyleLog 'No Apple cursor files were found.'
}

Apply-Wallpaper

Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Start-Process -FilePath 'explorer.exe'
Start-Sleep -Seconds 3

# Explorer sometimes reloads defaults in a new RDP shell, so force both again.
Apply-Wallpaper
[MacStyle.NativeMethods]::SystemParametersInfo(0x0057, 0, [IntPtr]::Zero, 3) | Out-Null

# Start Seelen UI in this same RDP desktop.
$CandidateRoots = @(
    'C:\Program Files\Seelen UI',
    'C:\Program Files\Seelen',
    (Join-Path $env:LOCALAPPDATA 'Programs\Seelen UI'),
    (Join-Path $env:LOCALAPPDATA 'Seelen UI')
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
    $ExistingSeelen = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $SeelenExe.FullName }
    if (-not $ExistingSeelen) {
        Start-Process -FilePath $SeelenExe.FullName
        Write-StyleLog "Seelen UI started interactively: $($SeelenExe.FullName)"
    }
} else {
    Write-StyleLog 'Seelen UI executable was not found for this profile.'
}

Write-StyleLog 'Interactive macOS-style personalization completed.'
