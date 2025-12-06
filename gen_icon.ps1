Add-Type -AssemblyName System.Drawing
$err = $null
try {
    $srcPath = Join-Path $PSScriptRoot "logo.png"
    $icoPath = Join-Path $PSScriptRoot "logo.ico"
    
    $src = [System.Drawing.Bitmap]::FromFile($srcPath)
    # Resize to 256x256 for better quality on modern Windows
    $bmp = New-Object System.Drawing.Bitmap(256, 256)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.DrawImage($src, 0, 0, 256, 256)
    
    $icon = [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
    
    $fs = [System.IO.File]::Create($icoPath)
    $icon.Save($fs)
    $fs.Close()
    
    $icon.Dispose()
    $bmp.Dispose()
    $g.Dispose()
    $src.Dispose()
    Write-Host "ICON_GENERATED_OK"
} catch {
    Write-Error $_
}
