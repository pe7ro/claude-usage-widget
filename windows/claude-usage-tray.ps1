# SPDX-FileCopyrightText: 2026 pe7ro
# SPDX-License-Identifier: MIT
<#
.SYNOPSIS
Claude Usage in the Windows notification area: the 5-hour plan limit on the icon, both limits and
every recent Claude Code session in its menu.

.DESCRIPTION
Shows what `claude_usage.py report --json` reports, so install that first (README, part 1). It asks
for a report every PollSeconds; the figures themselves only change when a Claude Code session gets
a response. Windows PowerShell 5.1 or later, no modules.

Not yet tested on Windows. -Print runs everything except the tray icon, and works anywhere.

.EXAMPLE
powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File claude-usage-tray.ps1

.EXAMPLE
powershell -NoProfile -ExecutionPolicy Bypass -File claude-usage-tray.ps1 -Print
#>
param(
    # The recorder, where the README's Windows steps put it.
    [string]$Script = (Join-Path $env:LOCALAPPDATA 'claude-usage\claude_usage.py'),
    # How to run it: py if the Python launcher is installed, else python.
    [string]$Python = '',
    [int]$PollSeconds = 30,
    # Print what the icon, tooltip and menu would show, once, and exit.
    [switch]$Print
)

# Same thresholds as the Plasma widget.
$WarnAt = 70
$CriticalAt = 90
# The report layout this script reads; claude_usage.py bumps it only for incompatible changes.
$ReportVersion = 1

# Kept ASCII: Windows PowerShell 5.1 reads a script without a BOM in the ANSI code page.
$Dot = " $([char]0x00B7) "
$Dash = [string][char]0x2014
$About = [string][char]0x2248

if (-not $Python) {
    if (Get-Command py -ErrorAction SilentlyContinue) { $Python = 'py' } else { $Python = 'python' }
}

# --- the report --------------------------------------------------------------------------------

function Get-Now {
    [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() / 1000.0
}

# @{ Report = the parsed report or $null; Error = '' or what went wrong }
function Get-Report {
    if (-not (Test-Path -LiteralPath $Script)) {
        return @{ Report = $null; Error = "claude_usage.py not found at $Script (README, part 1)" }
    }
    try {
        $lines = & $Python $Script report --json 2>&1 | ForEach-Object { "$_" }
    } catch {
        return @{ Report = $null; Error = "cannot run ${Python}: $($_.Exception.Message)" }
    }
    if ($LASTEXITCODE -ne 0) {
        return @{ Report = $null; Error = "report exited with ${LASTEXITCODE}: $($lines -join ' ')" }
    }
    try {
        $report = ($lines -join "`n") | ConvertFrom-Json
    } catch {
        return @{ Report = $null; Error = "unreadable report: $($_.Exception.Message)" }
    }
    if ($report.version -ne $ReportVersion) {
        return @{ Report = $null; Error = "claude-usage reports version $($report.version), this script reads ${ReportVersion}: upgrade both" }
    }
    return @{ Report = $report; Error = '' }
}

# --- text, as in the widget's format.js --------------------------------------------------------

function ConvertFrom-Epoch($Ts) {
    [DateTimeOffset]::FromUnixTimeMilliseconds([long]([double]$Ts * 1000)).LocalDateTime
}

function Round-Half-Up([double]$X) {
    [math]::Round($X, [MidpointRounding]::AwayFromZero)
}

# "4d 3h", "2h 13m", "47m", "<1m"
function Format-Duration([double]$Seconds) {
    $s = [math]::Max(0, [math]::Floor($Seconds))
    $d = [math]::Floor($s / 86400)
    $h = [math]::Floor(($s % 86400) / 3600)
    $m = [math]::Floor(($s % 3600) / 60)
    if ($d -gt 0) { return "${d}d ${h}h" }
    if ($h -gt 0) { return "${h}h ${m}m" }
    if ($m -gt 0) { return "${m}m" }
    return '<1m'
}

# A clock time, with the weekday when it isn't today: "16:40", "Mon 09:00"
function Format-When($Ts, [double]$Now) {
    if ($null -eq $Ts) { return '?' }
    $t = ConvertFrom-Epoch $Ts
    if ($t.Date -eq (ConvertFrom-Epoch $Now).Date) { return $t.ToString('HH:mm') }
    return $t.ToString('ddd HH:mm')
}

function Format-Ago($Ts, [double]$Now) {
    if ($null -eq $Ts) { return '' }
    if ($Now - [double]$Ts -lt 60) { return 'just now' }
    return (Format-Duration ($Now - [double]$Ts)) + ' ago'
}

function Format-Percent($P) {
    "$(Round-Half-Up $P)%"
}

# "812k", "1M", "1.5M"
function Format-Tokens($N) {
    if ($null -eq $N) { return '?' }
    $n = [double]$N
    if ($n -ge 1e6) {
        $m = $n / 1e6
        if ($m -ge 10 -or [math]::Abs($m - [math]::Round($m)) -lt 0.05) { return "$(Round-Half-Up $m)M" }
        return $m.ToString('0.0', [Globalization.CultureInfo]::InvariantCulture) + 'M'
    }
    if ($n -ge 1e3) { return "$(Round-Half-Up ($n / 1e3))k" }
    return "$(Round-Half-Up $n)"
}

# The window has reset since the reading was taken: its usage is unknown until the next Claude
# Code response, so it is shown as reset, never as a made-up 0%.
function Test-Reset($Limit, [double]$Now) {
    if ($null -eq $Limit) { return $false }
    return [bool]$Limit.expired -or ($null -ne $Limit.resets_at -and [double]$Limit.resets_at -le $Now)
}

# "none" | "normal" | "warn" | "critical"
function Get-Level($Percent) {
    if ($null -eq $Percent) { return 'none' }
    if ([double]$Percent -ge $CriticalAt) { return 'critical' }
    if ([double]$Percent -ge $WarnAt) { return 'warn' }
    return 'normal'
}

function Format-Limit([string]$Name, $Limit, [double]$Now) {
    if ($null -eq $Limit) { return "${Name}: no reading yet" }
    if (Test-Reset $Limit $Now) { return "${Name}: reset at $(Format-When $Limit.resets_at $Now)${Dot}no reading since" }
    $parts = @("${Name}: $(Format-Percent $Limit.used_percentage)")
    if ($null -ne $Limit.resets_at) {
        $parts += "resets $(Format-When $Limit.resets_at $Now)${Dot}in $(Format-Duration ([double]$Limit.resets_at - $Now))"
    }
    $parts += "as of $(Format-When $Limit.as_of $Now)"
    return $parts -join $Dot
}

function Format-Session($S, [double]$Now) {
    $ctx = $S.context
    $parts = @($S.title)
    $model = $S.model_short
    if (-not $model) { $model = $S.model }
    if ($model) { $parts += $model }
    if ($null -ne $ctx -and $null -ne $ctx.used_percentage) {
        $parts += "$(Format-Percent $ctx.used_percentage) used"
        $parts += "$(Format-Tokens $ctx.free_tokens) free of $(Format-Tokens $ctx.size)"
    } else {
        $parts += 'context not measured yet'
    }
    if ($S.state -eq 'ended') { $parts += "ended $(Format-Ago $S.ended_at $Now)" }
    elseif ($S.state -eq 'idle') { $parts += "idle $(Format-Ago $S.last_response_at $Now)" }
    else { $parts += Format-Ago $S.last_response_at $Now }
    return $parts -join $Dot
}

function Format-SessionTip($S) {
    $parts = @()
    if ($S.cwd_display) { $parts += $S.cwd_display }
    if ($S.cost_usd) { $parts += "$About `$" + ([double]$S.cost_usd).ToString('0.00', [Globalization.CultureInfo]::InvariantCulture) }
    return $parts -join $Dot
}

# Everything the tray shows, from one report: @{ Badge; Level; Tooltip; Items = @(@{ Text; Tip } or '-') }
function Get-View($Report, [string]$ErrorText, [double]$Now) {
    $limits = $null
    if ($null -ne $Report) { $limits = $Report.limits }
    $five = $null
    $seven = $null
    $spend = $null
    if ($null -ne $limits) { $five = $limits.five_hour; $seven = $limits.seven_day; $spend = $limits.spend_limit }

    if ($ErrorText) {
        $badge = '!'; $level = 'critical'; $tooltip = 'Claude usage: error, see the menu'
    } elseif ($null -eq $five -or (Test-Reset $five $Now)) {
        $badge = $Dash; $level = 'none'
        if ($null -eq $five) { $tooltip = 'Claude usage: no reading yet' }
        else { $tooltip = "Claude 5h: reset at $(Format-When $five.resets_at $Now)" }
    } else {
        $badge = [string](Round-Half-Up $five.used_percentage)
        $level = Get-Level $five.used_percentage
        $tooltip = "Claude 5h $(Format-Percent $five.used_percentage)"
        if ($null -ne $five.resets_at) { $tooltip += " ($(Format-Duration ([double]$five.resets_at - $Now)))" }
        if ($null -ne $seven -and -not (Test-Reset $seven $Now)) { $tooltip += "${Dot}7d $(Format-Percent $seven.used_percentage)" }
    }

    $items = @()
    if ($ErrorText) { $items += @{ Text = "Error: $ErrorText"; Tip = '' }; $items += '-' }
    $items += @{ Text = (Format-Limit '5 hours' $five $Now); Tip = '' }
    $items += @{ Text = (Format-Limit '7 days' $seven $Now); Tip = '' }
    if ($null -ne $spend) { $items += @{ Text = (Format-Limit 'Spend limit' $spend $Now); Tip = '' } }
    $items += '-'
    $sessions = @()
    if ($null -ne $Report -and $null -ne $Report.sessions) { $sessions = @($Report.sessions) }
    if ($sessions.Count -eq 0) { $items += @{ Text = 'No Claude Code session seen in the last 24 hours'; Tip = '' } }
    foreach ($s in $sessions) { $items += @{ Text = (Format-Session $s $Now); Tip = (Format-SessionTip $s) } }

    # NotifyIcon.Text takes at most 63 characters on .NET Framework.
    if ($tooltip.Length -gt 63) { $tooltip = $tooltip.Substring(0, 63) }
    return @{ Badge = $badge; Level = $level; Tooltip = $tooltip; Items = $items }
}

if ($Print) {
    $now = Get-Now
    $result = Get-Report
    $view = Get-View $result.Report $result.Error $now
    "icon:    $($view.Badge) ($($view.Level))"
    "tooltip: $($view.Tooltip)"
    foreach ($item in $view.Items) {
        if ($item -eq '-') { '---' }
        elseif ($item.Tip) { "$($item.Text)    [$($item.Tip)]" }
        else { $item.Text }
    }
    exit 0
}

# --- the tray icon -----------------------------------------------------------------------------

# One icon, however often the script is started (a Startup shortcut plus a manual start).
$mutex = New-Object System.Threading.Mutex($false, 'Local\ClaudeUsageTray')
if (-not $mutex.WaitOne(0)) { exit 0 }

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -Namespace ClaudeUsage -Name Native -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool DestroyIcon(System.IntPtr handle);
'@
[System.Windows.Forms.Application]::EnableVisualStyles()

# The percentage on a square coloured by level; white text reads on light and dark taskbars.
function New-BadgeIcon([string]$Text, [string]$Level) {
    $size = [System.Windows.Forms.SystemInformation]::SmallIconSize
    $bmp = New-Object System.Drawing.Bitmap $size.Width, $size.Height
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    switch ($Level) {
        'critical' { $color = [System.Drawing.Color]::FromArgb(218, 68, 83) }
        'warn'     { $color = [System.Drawing.Color]::FromArgb(246, 116, 0) }
        'normal'   { $color = [System.Drawing.Color]::FromArgb(39, 128, 190) }
        default    { $color = [System.Drawing.Color]::FromArgb(110, 110, 110) }
    }
    $brush = New-Object System.Drawing.SolidBrush $color
    $g.FillRectangle($brush, 0, 0, $size.Width, $size.Height)
    $px = $size.Height * 0.62
    if ($Text.Length -ge 3) { $px = $size.Height * 0.46 }
    $font = New-Object System.Drawing.Font('Segoe UI', [single]$px, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $format = New-Object System.Drawing.StringFormat
    $format.Alignment = [System.Drawing.StringAlignment]::Center
    $format.LineAlignment = [System.Drawing.StringAlignment]::Center
    $rect = New-Object System.Drawing.RectangleF(0, 0, $size.Width, $size.Height)
    $g.DrawString($Text, $font, [System.Drawing.Brushes]::White, $rect, $format)
    $g.Dispose(); $font.Dispose(); $brush.Dispose(); $format.Dispose()
    # FromHandle doesn't own the handle: keep a copy that does, and free the original.
    $handle = $bmp.GetHicon()
    $icon = [System.Drawing.Icon]::FromHandle($handle).Clone()
    [void][ClaudeUsage.Native]::DestroyIcon($handle)
    $bmp.Dispose()
    return $icon
}

$notify = New-Object System.Windows.Forms.NotifyIcon
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$menu.ShowItemToolTips = $true
$notify.ContextMenuStrip = $menu

function Update-Tray {
    try {
        $now = Get-Now
        $result = Get-Report
        $view = Get-View $result.Report $result.Error $now
    } catch {
        $view = Get-View $null "$($_.Exception.Message)" (Get-Now)
    }
    $old = $notify.Icon
    $notify.Icon = New-BadgeIcon $view.Badge $view.Level
    if ($null -ne $old) { $old.Dispose() }
    $notify.Text = $view.Tooltip

    $menu.Items.Clear()
    foreach ($item in $view.Items) {
        if ($item -eq '-') { [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)); continue }
        $entry = New-Object System.Windows.Forms.ToolStripMenuItem($item.Text)
        if ($item.Tip) { $entry.ToolTipText = $item.Tip }
        [void]$menu.Items.Add($entry)
    }
    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    $refresh = New-Object System.Windows.Forms.ToolStripMenuItem('Refresh')
    $refresh.add_Click({ Update-Tray })
    [void]$menu.Items.Add($refresh)
    $quit = New-Object System.Windows.Forms.ToolStripMenuItem('Quit')
    $quit.add_Click({
        $timer.Stop()
        $notify.Visible = $false
        [System.Windows.Forms.Application]::Exit()
    })
    [void]$menu.Items.Add($quit)
}

# A left click opens the same menu as a right click. NotifyIcon only does that for the right
# button, through a private method.
$notify.add_MouseUp({
    param($sender, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $show = [System.Windows.Forms.NotifyIcon].GetMethod('ShowContextMenu',
            [System.Reflection.BindingFlags]'Instance,NonPublic')
        [void]$show.Invoke($notify, $null)
    }
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = [math]::Max(5, $PollSeconds) * 1000
$timer.add_Tick({ Update-Tray })

Update-Tray
$notify.Visible = $true
$timer.Start()
[System.Windows.Forms.Application]::Run()

$notify.Dispose()
$mutex.ReleaseMutex()
