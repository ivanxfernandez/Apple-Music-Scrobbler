# Regenerates src/AppleMusicScrobbler/app.ico from IconFactory.cs (PNG-compressed, 16-256 px).
# Usage: powershell -ExecutionPolicy Bypass -File tools\make-icon.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
Add-Type -Path (Join-Path $root 'src\AppleMusicScrobbler\IconFactory.cs') -ReferencedAssemblies System.Drawing

$sizes = 16, 20, 24, 32, 40, 48, 64, 128, 256
$images = foreach ($size in $sizes) {
    $bmp = [AppleMusicScrobbler.IconFactory]::DrawBitmap([AppleMusicScrobbler.IconFactory]::Red, $size)
    $ms = New-Object IO.MemoryStream
    $bmp.Save($ms, [Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    , $ms.ToArray()
}

$out = New-Object IO.MemoryStream
$w = New-Object IO.BinaryWriter $out
$w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$sizes.Count)     # ICONDIR
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {                                      # ICONDIRENTRY
    $dim = if ($sizes[$i] -ge 256) { 0 } else { $sizes[$i] }
    $w.Write([byte]$dim); $w.Write([byte]$dim); $w.Write([byte]0); $w.Write([byte]0)
    $w.Write([uint16]1); $w.Write([uint16]32)
    $w.Write([uint32]$images[$i].Length); $w.Write([uint32]$offset)
    $offset += $images[$i].Length
}
foreach ($img in $images) { $w.Write($img) }
$w.Flush()

$path = Join-Path $root 'src\AppleMusicScrobbler\app.ico'
[IO.File]::WriteAllBytes($path, $out.ToArray())
$bmp = [AppleMusicScrobbler.IconFactory]::DrawBitmap([AppleMusicScrobbler.IconFactory]::Red, 256)
$bmp.Save((Join-Path $root 'docs\icon.png'), [Drawing.Imaging.ImageFormat]::Png)
"Wrote $path"
