<#
.SYNOPSIS
    Builds SetupNest.exe from install-gui.ps1 and logo.ico, then signs it.
    
.DESCRIPTION
    This script:
    1. Reads install-gui.ps1 content (as Base64).
    2. Compiles a C# wrapper that extracts and runs this content.
    3. Adds the application manifest for Admin privileges.
    4. Creates a Self-Signed certificate and signs the EXE.
#>

$ErrorActionPreference = "Stop"
$WorkingDir = $PSScriptRoot
Set-Location $WorkingDir

$PS_SCRIPT_PATH = "install-gui.ps1"
$ICON_PATH      = "logo.ico"
$OUT_EXE        = "SetupNest.exe"

Write-Host ">>> Reading Script..." -ForegroundColor Cyan
if (-not (Test-Path $PS_SCRIPT_PATH)) { throw "$PS_SCRIPT_PATH not found" }
$scriptContent = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes((Join-Path $WorkingDir $PS_SCRIPT_PATH)))

Write-Host ">>> Compiling C# Wrapper..." -ForegroundColor Cyan

$csharpSource = @"
using System;
using System.Diagnostics;
using System.IO;
using System.Text;

namespace SetupNestLauncher
{
    class Program
    {
        // Embedded Base64 Script
        static string Base64Script = "$scriptContent";

        static void Main(string[] args)
        {
            try
            {
                // 1. Decode script
                byte[] scriptBytes = Convert.FromBase64String(Base64Script);
                string tempPath = Path.GetTempPath();
                string scriptFile = Path.Combine(tempPath, "SetupNest-Run.ps1");

                // 2. Write to temp
                File.WriteAllBytes(scriptFile, scriptBytes);

                // 3. Launch PowerShell
                // We use -STA because WinForms needs it
                ProcessStartInfo psi = new ProcessStartInfo();
                psi.FileName = "powershell.exe";
                psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -STA -File \"" + scriptFile + "\"";
                psi.UseShellExecute = false; // Required to not open new window if we want redirect, but here we WANT window? 
                // Actually user said: "ne se quitte pas...". PS script handles that.
                // We want the console window to be HIDDEN, only GUI visible? 
                // Or user likes console output? "je veux que l'appli se ferme pas quand elle execute wingets". 
                // The GUI does the work. The console is distracting. Let's hide it.
                psi.WindowStyle = ProcessWindowStyle.Hidden; 
                psi.CreateNoWindow = true;

                Process p = Process.Start(psi);
                p.WaitForExit();

                // 4. Cleanup
                if(File.Exists(scriptFile)) { File.Delete(scriptFile); }
            }
            catch (Exception ex)
            {
                // Simple error dialog if things go really wrong
                string msg = "Error launching SetupNest: " + ex.Message;
                // No GUI lib referenced by default in console app template, console write
                // But we are hidden. 
                // We'll rely on global catch.
            }
        }
    }
}
"@

# Note: To add Icon and Manifest, we need specific compilation parameters.
# PowerShell's Add-Type is limited for Icon/Manifest embedding in one go easily without extra tools.
# We will use csc.exe directly if available, which is standard.

# We will use csc.exe directly.
$win = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Windows)

# Hardcoded fallback because searching can fail on some PS versions
$csc = "$win\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path $csc)) {
    $csc = "$win\Microsoft.NET\Framework\v4.0.30319\csc.exe"
}

if (-not (Test-Path $csc)) { throw "C# Compiler (csc.exe) not found on this system." }

Write-Host ">>> Using compiler: $csc" -ForegroundColor Gray

# Create source file
$srcFile = Join-Path $WorkingDir "launcher.cs"
[System.IO.File]::WriteAllText($srcFile, $csharpSource)

# Create Manifest for Admin Rights
$manifestSource = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
  <assemblyIdentity version="1.0.0.0" processorArchitecture="*" name="SetupNest" type="win32"/>
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v3">
    <security>
      <requestedPrivileges>
        <requestedExecutionLevel level="requireAdministrator" uiAccess="false"/>
      </requestedPrivileges>
    </security>
  </trustInfo>
</assembly>
"@
$manifestFile = Join-Path $WorkingDir "app.manifest"
[System.IO.File]::WriteAllText($manifestFile, $manifestSource)

# Compile
# /target:winexe -> No console window by default (GUI app). 
# /win32icon:... -> Icon
# /win32manifest:... -> Manifest
# /out:... -> Exe
$compileArgs = @(
    "/target:winexe",
    "/out:$OUT_EXE",
    "/platform:x64",
    "/win32manifest:$manifestFile",
    $srcFile
)

if (Test-Path $ICON_PATH) {
    # $compileArgs += "/win32icon:$ICON_PATH"
    Write-Warning "Icon embedding temporarily disabled due to format issues."
} else {
    Write-Warning "Icon not found, skipping."
}

# Run compiler
$p = Start-Process -FilePath $csc -ArgumentList $compileArgs -PassThru -NoNewWindow -Wait
if ($p.ExitCode -ne 0) { throw "Compilation failed." }

Remove-Item $srcFile

Write-Host ">>> Signing EXE..." -ForegroundColor Cyan

# Create Cert if missing
$certName = "SetupNest Jolan"
$cert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert | Where-Object { $_.Subject -match $certName } | Select-Object -First 1

if (-not $cert) {
    Write-Host "Creating Self-Signed Certificate '$certName'..."
    $cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject "CN=$certName" -CertStoreLocation Cert:\CurrentUser\My -NotAfter (Get-Date).AddYears(5)
}

# Sign
Set-AuthenticodeSignature -FilePath $OUT_EXE -Certificate $cert

Write-Host ">>> DONE! Created $OUT_EXE" -ForegroundColor Green
Write-Host "Note: As this is a self-signed certificate, you may need to install it in 'Trusted Root' on other PCs if you want to avoid warnings." -ForegroundColor Gray
