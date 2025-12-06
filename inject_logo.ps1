$p = Join-Path $PSScriptRoot "install-gui.ps1"
$l = Join-Path $PSScriptRoot "logo.png"

Write-Host "Reading logo.png..."
$b = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($l))

Write-Host "Reading install-gui.ps1..."
# Use UTF8 explicitly to avoid encoding issues
$utf8 = New-Object System.Text.UTF8Encoding($false) # No BOM
$c = [System.IO.File]::ReadAllText($p, $utf8)

if ($c.Contains("PLACEHOLDER_LOGO_B64")) {
    # Replace only the first occurrence just in case, though replace usually does all.
    # String.Replace works fine here.
    $n = $c.Replace('PLACEHOLDER_LOGO_B64', $b)
    
    Write-Host "Writing back..."
    [System.IO.File]::WriteAllText($p, $n, $utf8)
    Write-Host "LOGO_INJECTED"
} else {
    Write-Host "Placeholder not found."
}
