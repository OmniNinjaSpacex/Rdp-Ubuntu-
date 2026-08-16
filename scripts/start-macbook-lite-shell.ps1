$ErrorActionPreference = 'SilentlyContinue'

if ($env:USERNAME -ine 'cloudpc') { exit 0 }

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# Avoid duplicate bars/docks if Startup is triggered more than once.
$createdNew = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\MacBookLiteShell-cloudpc', [ref]$createdNew)
if (-not $createdNew) { exit 0 }

$screenWidth = [System.Windows.SystemParameters]::PrimaryScreenWidth
$screenHeight = [System.Windows.SystemParameters]::PrimaryScreenHeight

function Start-App {
    param([string]$Target, [string]$Arguments = '')
    try {
        if ($Arguments) {
            Start-Process -FilePath $Target -ArgumentList $Arguments
        } else {
            Start-Process -FilePath $Target
        }
    } catch {}
}

$firefox = 'C:\Program Files\Mozilla Firefox\firefox.exe'
$browser = if (Test-Path $firefox) { $firefox } else { 'msedge.exe' }
$terminal = if (Test-Path "$env:LOCALAPPDATA\Microsoft\WindowsApps\wt.exe") {
    "$env:LOCALAPPDATA\Microsoft\WindowsApps\wt.exe"
} else {
    "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
}

# ---------------- Top menu bar ----------------
$top = New-Object System.Windows.Window
$top.WindowStyle = 'None'
$top.ResizeMode = 'NoResize'
$top.ShowInTaskbar = $false
$top.Topmost = $true
$top.AllowsTransparency = $true
$top.Background = [System.Windows.Media.Brushes]::Transparent
$top.Width = $screenWidth
$top.Height = 34
$top.Left = 0
$top.Top = 0

$topBorder = New-Object System.Windows.Controls.Border
$topBorder.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(235, 246, 246, 246))
$topBorder.BorderBrush = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(80, 160, 160, 160))
$topBorder.BorderThickness = '0,0,0,1'
$top.Content = $topBorder

$topGrid = New-Object System.Windows.Controls.Grid
$topBorder.Child = $topGrid

$left = New-Object System.Windows.Controls.StackPanel
$left.Orientation = 'Horizontal'
$left.HorizontalAlignment = 'Left'
$left.VerticalAlignment = 'Center'
$left.Margin = '14,0,0,0'
$topGrid.Children.Add($left) | Out-Null

foreach ($text in @('●','Finder','File','Edit','View','Go','Window','Help')) {
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = $text
    $tb.FontFamily = 'Segoe UI'
    $tb.FontSize = if ($text -eq '●') { 14 } else { 13 }
    $tb.FontWeight = if ($text -eq 'Finder') { 'SemiBold' } else { 'Normal' }
    $tb.Margin = if ($text -eq '●') { '0,0,14,0' } else { '0,0,16,0' }
    $tb.VerticalAlignment = 'Center'
    $tb.Foreground = [System.Windows.Media.Brushes]::Black
    $left.Children.Add($tb) | Out-Null
}

$clock = New-Object System.Windows.Controls.TextBlock
$clock.FontFamily = 'Segoe UI'
$clock.FontSize = 13
$clock.FontWeight = 'SemiBold'
$clock.HorizontalAlignment = 'Right'
$clock.VerticalAlignment = 'Center'
$clock.Margin = '0,0,16,0'
$clock.Foreground = [System.Windows.Media.Brushes]::Black
$topGrid.Children.Add($clock) | Out-Null

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(1)
$timer.Add_Tick({ $clock.Text = (Get-Date).ToString('ddd  HH:mm') })
$clock.Text = (Get-Date).ToString('ddd  HH:mm')
$timer.Start()

# ---------------- Bottom dock ----------------
$dock = New-Object System.Windows.Window
$dock.WindowStyle = 'None'
$dock.ResizeMode = 'NoResize'
$dock.ShowInTaskbar = $false
$dock.Topmost = $true
$dock.AllowsTransparency = $true
$dock.Background = [System.Windows.Media.Brushes]::Transparent
$dock.Width = 650
$dock.Height = 84
$dock.Left = [Math]::Max(0, ($screenWidth - $dock.Width) / 2)
$dock.Top = [Math]::Max(40, $screenHeight - 132)

$dockBorder = New-Object System.Windows.Controls.Border
$dockBorder.CornerRadius = 20
$dockBorder.Padding = '12,8,12,8'
$dockBorder.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(220, 238, 238, 238))
$dockBorder.BorderBrush = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(95, 150, 150, 150))
$dockBorder.BorderThickness = 1
$dock.Content = $dockBorder

$dockPanel = New-Object System.Windows.Controls.StackPanel
$dockPanel.Orientation = 'Horizontal'
$dockPanel.HorizontalAlignment = 'Center'
$dockPanel.VerticalAlignment = 'Center'
$dockBorder.Child = $dockPanel

function Add-DockButton {
    param(
        [string]$Label,
        [string]$Glyph,
        [scriptblock]$Action
    )

    $button = New-Object System.Windows.Controls.Button
    $button.Width = 78
    $button.Height = 64
    $button.Margin = '3,0,3,0'
    $button.Background = [System.Windows.Media.Brushes]::Transparent
    $button.BorderThickness = 0
    $button.Cursor = 'Hand'
    $button.ToolTip = $Label

    $scale = New-Object System.Windows.Media.ScaleTransform(1,1)
    $button.RenderTransform = $scale
    $button.RenderTransformOrigin = '0.5,1'

    $content = New-Object System.Windows.Controls.StackPanel
    $content.VerticalAlignment = 'Center'

    $icon = New-Object System.Windows.Controls.TextBlock
    $icon.Text = $Glyph
    $icon.FontFamily = 'Segoe UI Emoji'
    $icon.FontSize = 31
    $icon.HorizontalAlignment = 'Center'
    $icon.Foreground = [System.Windows.Media.Brushes]::Black

    $text = New-Object System.Windows.Controls.TextBlock
    $text.Text = $Label
    $text.FontFamily = 'Segoe UI'
    $text.FontSize = 10
    $text.HorizontalAlignment = 'Center'
    $text.Foreground = [System.Windows.Media.Brushes]::Black

    $content.Children.Add($icon) | Out-Null
    $content.Children.Add($text) | Out-Null
    $button.Content = $content

    $button.Add_MouseEnter({
        $this.RenderTransform.ScaleX = 1.18
        $this.RenderTransform.ScaleY = 1.18
    })
    $button.Add_MouseLeave({
        $this.RenderTransform.ScaleX = 1.0
        $this.RenderTransform.ScaleY = 1.0
    })
    $button.Add_Click($Action)
    $dockPanel.Children.Add($button) | Out-Null
}

Add-DockButton 'Finder' '📁' { Start-App "$env:WINDIR\explorer.exe" }
Add-DockButton 'Safari' '🌐' { Start-App $browser }
Add-DockButton 'Launchpad' '▦' { Start-App "$env:WINDIR\explorer.exe" 'shell:AppsFolder' }
Add-DockButton 'Settings' '⚙' { Start-App "$env:WINDIR\explorer.exe" 'ms-settings:' }
Add-DockButton 'Terminal' '⌘' { Start-App $terminal }
Add-DockButton 'Trash' '🗑' { Start-App "$env:WINDIR\explorer.exe" 'shell:RecycleBinFolder' }

# Keep both windows alive in the same WPF dispatcher.
$top.Show()
$dock.ShowDialog() | Out-Null

$timer.Stop()
$mutex.ReleaseMutex() | Out-Null
$mutex.Dispose()
