$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

if ($env:USERNAME -ine 'cloudpc') { exit 0 }

$MacRoot = 'C:\MacStyle'
$LogFile = Join-Path $MacRoot 'safari-like.log'
$Firefox = 'C:\Program Files\Mozilla Firefox\firefox.exe'

function Write-MacLog {
    param([string]$Message)
    Add-Content -Path $LogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
}

if (-not (Test-Path $Firefox)) {
    Write-MacLog 'Firefox not found; Safari-like configuration skipped.'
    exit 0
}

Start-Sleep -Seconds 4
Write-MacLog 'Configuring Safari-like Firefox in interactive RDP session.'

$ProfilesRoot = Join-Path $env:APPDATA 'Mozilla\Firefox\Profiles'
if (-not (Test-Path $ProfilesRoot) -or -not (Get-ChildItem $ProfilesRoot -Directory -ErrorAction SilentlyContinue)) {
    Start-Process -FilePath $Firefox -ArgumentList @('-CreateProfile','MacLike') -Wait -WindowStyle Hidden
    Start-Sleep -Seconds 1
}

$Profile = Get-ChildItem $ProfilesRoot -Directory -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if ($Profile) {
    $Chrome = Join-Path $Profile.FullName 'chrome'
    New-Item -ItemType Directory -Force -Path $Chrome | Out-Null

    try {
        Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/gauravrocks009/safari-firefox/main/userChrome.css' -OutFile (Join-Path $Chrome 'userChrome.css')
        Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/gauravrocks009/safari-firefox/main/userContent.css' -OutFile (Join-Path $Chrome 'userContent.css')

        @'
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
user_pref("svg.context-properties.content.enabled", true);
user_pref("widget.non-native-theme.use-theme-accent", true);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.aboutConfig.showWarning", false);
user_pref("browser.startup.firstrunSkipsHomepage", true);
user_pref("browser.tabs.warnOnClose", false);
'@ | Set-Content -Path (Join-Path $Profile.FullName 'user.js') -Encoding UTF8
        Write-MacLog "Safari Firefox CSS installed in $($Profile.FullName)"
    } catch {
        Write-MacLog "Safari Firefox CSS download failed: $($_.Exception.Message)"
    }
} else {
    Write-MacLog 'Firefox profile could not be created.'
}

# Create familiar macOS-style entry points while keeping the underlying Windows apps explicit.
$Desktop = [Environment]::GetFolderPath('Desktop')
$StartMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Mac-like'
New-Item -ItemType Directory -Force -Path $StartMenu | Out-Null

$Shell = New-Object -ComObject WScript.Shell
function New-MacShortcut {
    param(
        [string]$Name,
        [string]$Target,
        [string]$Arguments,
        [string]$Icon
    )

    foreach ($Folder in @($Desktop,$StartMenu)) {
        if (-not (Test-Path $Folder)) { continue }
        $Link = $Shell.CreateShortcut((Join-Path $Folder "$Name.lnk"))
        $Link.TargetPath = $Target
        if ($Arguments) { $Link.Arguments = $Arguments }
        if ($Icon) { $Link.IconLocation = $Icon }
        $Link.WorkingDirectory = Split-Path $Target -Parent
        $Link.Save()
    }
}

New-MacShortcut -Name 'Safari (Firefox)' -Target $Firefox -Arguments '' -Icon "$Firefox,0"
New-MacShortcut -Name 'Finder' -Target "$env:WINDIR\explorer.exe" -Arguments '' -Icon "$env:WINDIR\explorer.exe,0"
New-MacShortcut -Name 'System Settings' -Target "$env:WINDIR\explorer.exe" -Arguments 'ms-settings:' -Icon "$env:WINDIR\System32\imageres.dll,109"

$Terminal = if (Test-Path "$env:LOCALAPPDATA\Microsoft\WindowsApps\wt.exe") { "$env:LOCALAPPDATA\Microsoft\WindowsApps\wt.exe" } else { "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" }
New-MacShortcut -Name 'Terminal' -Target $Terminal -Arguments '' -Icon "$Terminal,0"
New-MacShortcut -Name 'Launchpad' -Target "$env:WINDIR\explorer.exe" -Arguments 'shell:AppsFolder' -Icon "$env:WINDIR\System32\imageres.dll,15"
New-MacShortcut -Name 'Trash' -Target "$env:WINDIR\explorer.exe" -Arguments 'shell:RecycleBinFolder' -Icon "$env:WINDIR\System32\imageres.dll,55"

# Small browser performance preferences: keep first-run/background extras out of the way.
$FirefoxPolicies = 'HKCU:\Software\Policies\Mozilla\Firefox'
New-Item -Path $FirefoxPolicies -Force | Out-Null
New-ItemProperty -Path $FirefoxPolicies -Name DisableTelemetry -PropertyType DWord -Value 1 -Force | Out-Null
New-ItemProperty -Path $FirefoxPolicies -Name DisableDefaultBrowserAgent -PropertyType DWord -Value 1 -Force | Out-Null

Write-MacLog 'Mac-like shortcuts and Safari-like browser configuration completed.'
