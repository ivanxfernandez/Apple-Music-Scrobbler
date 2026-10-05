# Captures docs/menu.png (tray menu) and docs/setup.png (first-run window) for the README.
# Quit the running Apple Music Scrobbler first (the menu screenshot needs a real, connected instance).
# Usage: powershell -ExecutionPolicy Bypass -File tools\screenshots.ps1
# CI (.github/workflows/screenshots.yml) uses -OutDir, -Suffix and -ExtraArgs "--dry-run ..." (no Last.fm login there).
# ExtraArgs is one space-separated string: arrays don't survive powershell.exe -File.
param([string]$Exe, [string]$OutDir, [string]$Suffix = '', [string]$ExtraArgs = '')
$extra = @($ExtraArgs -split ' ' | Where-Object { $_ })
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
if (-not $Exe) { $Exe = Join-Path $root 'src\AppleMusicScrobbler\bin\Release\net48\AppleMusicScrobbler.exe' }

Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class Win {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr hWnd, int attr, out RECT rect, int size);
    // Visible top-level windows of a process, by visual bounds (without the invisible resize border).
    public static List<RECT> Windows(int processId) {
        var result = new List<RECT>();
        EnumWindows((h, l) => {
            uint pid; GetWindowThreadProcessId(h, out pid);
            RECT r;
            if (pid == processId && IsWindowVisible(h) && DwmGetWindowAttribute(h, 9, out r, Marshal.SizeOf(typeof(RECT))) == 0
                && r.Right - r.Left > 20 && r.Bottom - r.Top > 20) result.Add(r);
            return true;
        }, IntPtr.Zero);
        return result;
    }
}
'@
[void][Win]::SetProcessDPIAware()

function Save-Screenshot([Win+RECT]$r, [string]$Path) {
    $bmp = New-Object Drawing.Bitmap ($r.Right - $r.Left), ($r.Bottom - $r.Top)
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($r.Left, $r.Top, 0, 0, $bmp.Size)
    $bmp.Save($Path, [Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
    "Wrote $Path"
}

function Capture([string[]]$Arguments, [int]$WaitSeconds, [string]$Path) {
    $p = Start-Process $Exe -ArgumentList $Arguments -PassThru
    try {
        Start-Sleep -Seconds $WaitSeconds
        $windows = [Win]::Windows($p.Id)
        if (-not $windows.Count) { throw "No window found for $Arguments" }
        $largest = $windows | Sort-Object { ($_.Right - $_.Left) * ($_.Bottom - $_.Top) } -Descending | Select-Object -First 1
        Save-Screenshot $largest $Path
    } finally {
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    }
}

if (Get-Process AppleMusicScrobbler -ErrorAction SilentlyContinue) {
    throw 'Quit Apple Music Scrobbler first (tray icon > Quit), then run this again.'
}
$docs = if ($OutDir) { $OutDir } else { Join-Path $root 'docs' }
New-Item -ItemType Directory -Force $docs | Out-Null
Capture (@('--show-setup') + $extra) 3 (Join-Path $docs "setup$Suffix.png")
Capture (@('--open-menu') + $extra) 7 (Join-Path $docs "menu$Suffix.png")
