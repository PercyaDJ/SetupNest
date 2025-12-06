[CmdletBinding()]
param()

# ========= REGLAGES =========
$RepoUrl = "https://github.com/PercyaDJ/SetupNest"

# ========= GARDE STA (pas de relance automatique) =========
# Si pas en STA, on explique et on sort proprement.
if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne [System.Threading.ApartmentState]::STA) {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
    [System.Windows.Forms.MessageBox]::Show(
        "Lance le script via start-SetupNest.cmd (il force le mode STA).",
        "Mode STA requis",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
    exit 3
}


# ========= PREP =========
try { Set-Location -LiteralPath $PSScriptRoot } catch {}
try { Unblock-File -Path $PSCommandPath -ErrorAction SilentlyContinue } catch {}
try { Unblock-File -Path (Join-Path $PSScriptRoot 'apps.json') -ErrorAction SilentlyContinue } catch {}
try { Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force -ErrorAction SilentlyContinue } catch {}
$ErrorActionPreference = "Continue"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# --- Cue banner (placeholder) pour TextBox en PS5 ---
$cueCode = @"
using System;
using System.Runtime.InteropServices;
public static class CueBanner {
  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  public static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, string lParam);
}
"@
Add-Type -TypeDefinition $cueCode
$EM_SETCUEBANNER = 0x1501
function Set-CueBanner([System.Windows.Forms.TextBox]$tb, [string]$text) {
    try { [CueBanner]::SendMessage($tb.Handle, $EM_SETCUEBANNER, [IntPtr]::Zero, $text) | Out-Null } catch {}
}

# ========= WINGET =========
function Ensure-Winget {
    if (Get-Command winget -ErrorAction SilentlyContinue) { return }
    $msg = @"
winget n'est pas disponible sur ce systeme.

winget fait partie de l'application "App Installer" (Microsoft Store).
J'ouvre la page pour installation. Relance ensuite ce script.
"@
    $r = [System.Windows.Forms.MessageBox]::Show($msg, "winget manquant",
        [System.Windows.Forms.MessageBoxButtons]::OKCancel,
        [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($r -eq [System.Windows.Forms.DialogResult]::OK) {
        try { Start-Process "ms-windows-store://pdp/?productid=9NBLGGH4NNS1" } catch {}
    }
    exit 1
}

function Join-Args([string[]]$Arguments) {
    $parts = @()
    foreach ($a in $Arguments) {
        if ($null -eq $a) { continue }
        if ($a -match '\s') { $parts += '"' + ($a -replace '"','\"') + '"' }
        else { $parts += $a }
    }
    return ($parts -join ' ')
}

function Invoke-WingetStreaming {
    param([string[]]$Arguments,[System.Windows.Forms.TextBox]$LogBox)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "winget.exe"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding  = [System.Text.Encoding]::UTF8
    $psi.Arguments = Join-Args $Arguments

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi

    $handlerOut = [System.Diagnostics.DataReceivedEventHandler]{ if ($_.Data) { Add-LogLineSafe -LogBox $LogBox -Line $_.Data } }
    $handlerErr = [System.Diagnostics.DataReceivedEventHandler]{ if ($_.Data) { Add-LogLineSafe -LogBox $LogBox -Line ("[ERR] " + $_.Data) } }

    $p.add_OutputDataReceived($handlerOut)
    $p.add_ErrorDataReceived($handlerErr)

    $null = $p.Start()
    $p.BeginOutputReadLine()
    $p.BeginErrorReadLine()
    
    # Boucle d'attente non bloquante pour garder l'UI vivante et afficher les logs en temps réel
    while (-not $p.HasExited) {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 50
    }
    # Au cas où
    $p.WaitForExit()
    return $p.ExitCode
}

# Fonction optimisée utilisant le cache si possible, sinon fallback
function Winget-IsInstalled { param([string]$Id)
    if ($script:InstalledIds.ContainsKey($Id)) { return $true }
    # Fallback lent si cache pas prêt (rare)
    winget list --id $Id --accept-source-agreements | Select-String $Id -Quiet
}

function Winget-Install {
    param(
        [string]$Id,
        [System.Windows.Forms.TextBox]$LogBox,
        [string]$Scope  # "user" ou "machine" (optionnel)
    )
    $args = @('install','--id',$Id,'--silent','--accept-package-agreements','--accept-source-agreements')
    if ($Scope -and ($Scope -match '^(user|machine)$')) { $args += @('--scope', $Scope) }
    [void](Invoke-WingetStreaming -Arguments $args -LogBox $LogBox)
}

function Winget-UpgradeId  { param([string]$Id,[System.Windows.Forms.TextBox]$LogBox)
    [void](Invoke-WingetStreaming -Arguments @('upgrade','--id',$Id,'--silent','--accept-package-agreements','--accept-source-agreements') -LogBox $LogBox)
}
function Winget-UpgradeAll { param([System.Windows.Forms.TextBox]$LogBox)
    [void](Invoke-WingetStreaming -Arguments @('upgrade','--all','--silent','--accept-package-agreements','--accept-source-agreements') -LogBox $LogBox)
}
function Winget-Uninstall  { param([string]$Id,[System.Windows.Forms.TextBox]$LogBox)
    [void](Invoke-WingetStreaming -Arguments @('uninstall','--id',$Id,'--silent','--accept-source-agreements') -LogBox $LogBox)
}

# ========= CONFIG =========
function Load-AppsConfig {
    $configPath = Join-Path $PSScriptRoot "apps.json"
    
    # Auto-download si absent (Mode Portable/EXE)
    if (-not (Test-Path $configPath)) {
        try {
            # On tente de le récupérer depuis le repo
            $url = "$RepoUrl/raw/main/apps.json"
            Invoke-WebRequest $url -OutFile $configPath -ErrorAction Stop
        } catch {
            [System.Windows.Forms.MessageBox]::Show(("Fichier apps.json introuvable et impossible à télécharger.`n`nUrl : {0}`nErreur : {1}" -f $url, $_.Exception.Message),
                "Erreur - Config manquante",[System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
            exit 1
        }
    }

    try {
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        $raw  = [System.IO.File]::ReadAllText($configPath, $utf8)
        if ([string]::IsNullOrWhiteSpace($raw)) { throw "apps.json vide" }
        $json = $raw | ConvertFrom-Json
        return $json
    } catch {
        [System.Windows.Forms.MessageBox]::Show(("Impossible de lire apps.json (UTF-8). Details : {0}" -f $_.Exception.Message),
            "Erreur - JSON invalide",[System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        exit 1
    }
}

# ========= LOG UI =========
function Add-LogLineSafe { param([System.Windows.Forms.TextBox]$LogBox,[string]$Line)
    try {
        if ($LogBox.InvokeRequired) {
            $null = $LogBox.BeginInvoke([Action]{
                $LogBox.AppendText($Line + "`r`n")
                $LogBox.SelectionStart = $LogBox.Text.Length
                $LogBox.ScrollToCaret()
            })
        } else {
            $LogBox.AppendText($Line + "`r`n")
            $LogBox.SelectionStart = $LogBox.Text.Length
            $LogBox.ScrollToCaret()
        }
    } catch {}
}
function Write-UILog { param([System.Windows.Forms.TextBox]$LogBox,[string]$Message)
    Add-LogLineSafe -LogBox $LogBox -Line $Message
}

# ========= ACTIONS =========
function Install-App {
    param(
        [pscustomobject]$App,
        [System.Windows.Forms.TextBox]$LogBox
    )
    $name = $App.name
    $id   = $App.id
    $scope = $null
    if ($App.PSObject.Properties.Name -contains 'scope') { $scope = [string]$App.scope }

    Write-UILog $LogBox "=== INSTALL: $name ($id) ==="
    # Optim: check cache
    if ($script:InstalledIds.ContainsKey($id)) { Write-UILog $LogBox "Deja installe, ignore."; Write-UILog $LogBox ""; return }

    try {
        Set-Status "Installation: $name" $true
        Winget-Install -Id $id -LogBox $LogBox -Scope $scope
        Set-Status "OK: $name"
    } catch {
        Write-UILog $LogBox ("Erreur installation : {0}" -f $_.Exception.Message)
    }
    Write-UILog $LogBox ""
}
function Update-App { param([pscustomobject]$App,[System.Windows.Forms.TextBox]$LogBox)
    $name=$App.name; $id=$App.id
    Write-UILog $LogBox "=== UPDATE: $name ($id) ==="
    # Optim: Check cache
    if (-not $script:InstalledIds.ContainsKey($id)) { Write-UILog $LogBox "Non installe -> rien a mettre a jour."; Write-UILog $LogBox ""; return }
    try { Set-Status "Mise a jour: $name" $true; Winget-UpgradeId -Id $id -LogBox $LogBox; Set-Status "OK: $name"; }
    catch { Write-UILog $LogBox ("Erreur mise a jour : {0}" -f $_.Exception.Message) }
    Write-UILog $LogBox ""
}
function Uninstall-App { param([pscustomobject]$App,[System.Windows.Forms.TextBox]$LogBox)
    $name=$App.name; $id=$App.id
    Write-UILog $LogBox "=== UNINSTALL: $name ($id) ==="
    # Optim: check cache
    if (-not $script:InstalledIds.ContainsKey($id)) { Write-UILog $LogBox "Non installe -> rien a desinstaller."; Write-UILog $LogBox ""; return }
    try { Set-Status "Desinstallation: $name" $true; Winget-Uninstall -Id $id -LogBox $LogBox; Set-Status "OK: $name"; }
    catch { Write-UILog $LogBox ("Erreur desinstallation : {0}" -f $_.Exception.Message) }
    Write-UILog $LogBox ""
}

# ========= DONNEES =========
Ensure-Winget
$apps = Load-AppsConfig
foreach ($app in $apps) {
    if (-not $app.PSObject.Properties.Name -contains "category" -or [string]::IsNullOrWhiteSpace($app.category)) {
        $app | Add-Member -NotePropertyName category -NotePropertyValue "Divers" -Force
    }
}
$script:AppsMaster = $apps

# Etats installés / upgradables
$script:InstalledIds  = @{}
$script:UpgradableIds = @{}

function Refresh-AppState {
    param([System.Windows.Forms.TextBox]$LogBox)
    
    $start = Get-Date
    Set-Status "Scan etat applications..." $true
    
    # Reset
    $script:InstalledIds  = @{}
    $script:UpgradableIds = @{}

    try {
        # --- 1. Scan des applications installées ---
        Write-UILog $LogBox "Scan des applications installees (winget list)..."
        [System.Windows.Forms.Application]::DoEvents()

        # On utilise une astuce pour aller plus vite : pas de draw de colonnes trop complexe, juste récup raw
        $listOut = winget list --accept-source-agreements --disable-interactivity 2>$null
        
        $allOutput = $listOut -join "`n"
        
        # Pour CHAQUE App de notre catalogue, vérifier si son ID est présent
        foreach ($app in $script:AppsMaster) {
            $id = $app.id
            if ($allOutput.Contains($id)) {
                 $script:InstalledIds[$id] = $true
            }
        }
        
        # --- 2. Scan des mises à jour ---
        Write-UILog $LogBox "Verification des mises a jour (winget upgrade)..."
        [System.Windows.Forms.Application]::DoEvents()
        
        $upOut = winget upgrade --accept-source-agreements --disable-interactivity 2>$null
        $allUpOutput = $upOut -join "`n"
        
        foreach ($app in $script:AppsMaster) {
            $id = $app.id
            if ($script:InstalledIds.ContainsKey($id)) {
               # Si installé, on vérifie si update dispo
               if ($allUpOutput.Contains($id)) {
                   $script:UpgradableIds[$id] = $true
               }
            }
        }

        $duration = (Get-Date) - $start
        Write-UILog $LogBox ("Scan termine en {0:N1}s. {1} installees, {2} updates dispos." -f $duration.TotalSeconds, $script:InstalledIds.Count, $script:UpgradableIds.Count)
        
    } catch {
        Write-UILog $LogBox ("Erreur critique durant le scan : {0}" -f $_.Exception.Message)
    }
    
    Set-Status "Pret" $false
}

# ========= UI =========
$form = New-Object System.Windows.Forms.Form
$form.Text = "SetupNest - Installateur win-get"
$form.Size = [System.Drawing.Size]::new(1100, 700)
$form.MinimumSize = [System.Drawing.Size]::new(960, 560)
$form.StartPosition = "CenterScreen"
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$form.AutoScaleMode = 'Dpi'

# Icone du projet
try {
    $iconUrl  = "$RepoUrl/raw/main/logo.ico"
    $iconPath = Join-Path $env:TEMP "SetupNest-Logo.ico"
    # On télécharge si absent ou vieux (> 1 jour ? non simple check existence pour perf)
    if (-not (Test-Path $iconPath)) {
        Invoke-WebRequest $iconUrl -OutFile $iconPath -ErrorAction SilentlyContinue
    }
    if (Test-Path $iconPath) {
        $form.Icon = [System.Drawing.Icon]::new($iconPath)
    }
} catch {}

# Layout global
$layout = New-Object System.Windows.Forms.TableLayoutPanel
$layout.Dock = 'Fill'
$layout.ColumnCount = 1
$layout.RowCount = 3
$layout.RowStyles.Add( (New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)) )
$layout.RowStyles.Add( (New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)) )
$layout.RowStyles.Add( (New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)) )
$form.Controls.Add($layout)

# Header 2 colonnes
$header = New-Object System.Windows.Forms.TableLayoutPanel
$header.Dock = 'Fill'
$header.AutoSize = $true
$header.AutoSizeMode = 'GrowAndShrink'
$header.Padding = [System.Windows.Forms.Padding]::new(10, 8, 10, 6)
$header.ColumnCount = 2
$csHeaderLeft  = New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)
$csHeaderRight = New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize)
[void]$header.ColumnStyles.Add($csHeaderLeft)
[void]$header.ColumnStyles.Add($csHeaderRight)
$layout.Controls.Add($header, 0, 0)

$lbl = New-Object System.Windows.Forms.Label
$lbl.Text = "Selectionnez les applications a installer ou mettre a jour :"
$lbl.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$lbl.AutoSize = $true
$lbl.Anchor = 'Left'
$header.Controls.Add($lbl, 0, 0)

# Bloc droit header (2 lignes)
$hdrRight = New-Object System.Windows.Forms.TableLayoutPanel
$hdrRight.AutoSize = $true
$hdrRight.AutoSizeMode = 'GrowAndShrink'
$hdrRight.ColumnCount = 1
$hdrRight.RowCount = 2
[void]$hdrRight.RowStyles.Add( (New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)) )
[void]$hdrRight.RowStyles.Add( (New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)) )
$hdrRight.Padding = [System.Windows.Forms.Padding]::new(0,0,0,0)
$hdrRight.Margin  = [System.Windows.Forms.Padding]::new(0,0,0,0)
$hdrRight.Anchor  = 'Right'
$header.Controls.Add($hdrRight, 1, 0)

$tbSearch = New-Object System.Windows.Forms.TextBox
$tbSearch.Width = 240
Set-CueBanner $tbSearch "Rechercher (nom ou id)..."
$tbSearch.Anchor = 'Right'
$hdrRight.Controls.Add($tbSearch, 0, 0)

$hdrBtns = New-Object System.Windows.Forms.FlowLayoutPanel
$hdrBtns.AutoSize      = $true
$hdrBtns.AutoSizeMode  = 'GrowAndShrink'
$hdrBtns.WrapContents  = $false
$hdrBtns.FlowDirection = 'LeftToRight'
$hdrBtns.Padding       = [System.Windows.Forms.Padding]::new(0,4,0,0)
$hdrBtns.Margin        = [System.Windows.Forms.Padding]::new(0,0,0,0)
$hdrBtns.Anchor        = 'Right'
$hdrRight.Controls.Add($hdrBtns, 0, 1)

$btnClear    = New-Object System.Windows.Forms.Button; $btnClear.Text    = "Effacer";        $btnClear.AutoSize = $true
$btnExpand   = New-Object System.Windows.Forms.Button; $btnExpand.Text   = "Deplier tout";   $btnExpand.AutoSize = $true
$btnCollapse = New-Object System.Windows.Forms.Button; $btnCollapse.Text = "Replier tout";   $btnCollapse.AutoSize = $true
$btnRefresh  = New-Object System.Windows.Forms.Button; $btnRefresh.Text  = "Rafraichir";     $btnRefresh.AutoSize = $true
$hdrBtns.Controls.AddRange(@($btnClear,$btnExpand,$btnCollapse,$btnRefresh))

# Contenu
$contentPad = New-Object System.Windows.Forms.Panel
$contentPad.Dock = 'Fill'
$contentPad.Padding = [System.Windows.Forms.Padding]::new(8, 0, 8, 0)
$layout.Controls.Add($contentPad, 0, 1)

$split = New-Object System.Windows.Forms.SplitContainer
$split.Dock = 'Fill'
$split.Orientation = 'Vertical'
$contentPad.Controls.Add($split)

$grpLeft = New-Object System.Windows.Forms.GroupBox
$grpLeft.Text = "Catalogue"
$grpLeft.Dock = 'Fill'
$grpLeft.Padding = [System.Windows.Forms.Padding]::new(8,18,8,8)
$split.Panel1.Controls.Add($grpLeft)

$tree = New-Object System.Windows.Forms.TreeView
$tree.Dock = 'Fill'
$tree.CheckBoxes = $true
$tree.HideSelection = $false
$tree.ShowLines = $true
$tree.ShowPlusMinus = $true
$tree.ShowRootLines = $true
$tree.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$grpLeft.Controls.Add($tree)

$grpRight = New-Object System.Windows.Forms.GroupBox
$grpRight.Text = "Journal d'execution"
$grpRight.Dock = 'Fill'
$grpRight.Padding = [System.Windows.Forms.Padding]::new(8,18,8,8)
$split.Panel2.Controls.Add($grpRight)

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Dock = 'Fill'
$logBox.Multiline = $true
$logBox.ScrollBars = "Vertical"
$logBox.ReadOnly = $true
$logBox.BackColor = [System.Drawing.Color]::FromArgb(30,30,30)
$logBox.ForeColor = [System.Drawing.Color]::LightGray
$logBox.Font = New-Object System.Drawing.Font("Consolas", 10)
$grpRight.Controls.Add($logBox)

# Split securise
function Get-ValidSplitDistance([System.Windows.Forms.Control]$c,[int]$p1Min,[int]$p2Min,[double]$ratio){
    $usable = [Math]::Max(600, $c.ClientSize.Width)
    $desired = [int]([Math]::Round($usable * $ratio))
    $min = $p1Min
    $max = $usable - $p2Min
    if ($max -lt $min) { $max = $min }
    if ($desired -lt $min) { $desired = $min }
    if ($desired -gt $max) { $desired = $max }
    return $desired
}
$form.Add_Shown({
    $p1Min = 350; $p2Min = 360
    $split.Panel1MinSize = $p1Min
    $split.Panel2MinSize = $p2Min
    $split.SplitterWidth  = 6
    $split.SplitterDistance = Get-ValidSplitDistance $contentPad $p1Min $p2Min 0.55
})
$form.Add_Resize({
    $p1Min = $split.Panel1MinSize
    $p2Min = $split.Panel2MinSize
    $usable = $contentPad.ClientSize.Width
    $min = $p1Min
    $max = $usable - $p2Min
    if ($max -lt $min) { $max = $min }
    if ($split.SplitterDistance -lt $min) { $split.SplitterDistance = $min }
    if ($split.SplitterDistance -gt $max) { $split.SplitterDistance = $max }
})

# Barre de boutons bas
$bottomWrap = New-Object System.Windows.Forms.Panel
$bottomWrap.Dock = 'Fill'
$bottomWrap.Padding = [System.Windows.Forms.Padding]::new(10,6,10,10)
$layout.Controls.Add($bottomWrap, 0, 2)

$bottom = New-Object System.Windows.Forms.TableLayoutPanel
$bottom.Dock = 'Fill'
$bottom.AutoSize = $true
$bottom.AutoSizeMode = 'GrowAndShrink'
$bottom.ColumnCount = 2
$csBottomLeft  = New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 60)
$csBottomRight = New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 40)
[void]$bottom.ColumnStyles.Add($csBottomLeft)
[void]$bottom.ColumnStyles.Add($csBottomRight)
$bottomWrap.Controls.Add($bottom)

function NewBtn($t) { $b=New-Object System.Windows.Forms.Button; $b.AutoSize=$true; $b.AutoSizeMode='GrowAndShrink'; $b.Margin=[System.Windows.Forms.Padding]::new(6,6,6,6); $b.Text=$t; return $b }

$flowLeft = New-Object System.Windows.Forms.FlowLayoutPanel
$flowLeft.Dock = 'Fill'
$flowLeft.WrapContents = $true
$flowLeft.AutoSize = $true
$flowLeft.AutoSizeMode = 'GrowAndShrink'
$bottom.Controls.Add($flowLeft, 0, 0)

$btnCheckAll      = NewBtn "Tout cocher"
$btnUncheckAll    = NewBtn "Tout decocher"
$flowLeft.Controls.AddRange(@($btnCheckAll,$btnUncheckAll))

$flowRight = New-Object System.Windows.Forms.FlowLayoutPanel
$flowRight.Dock = 'Fill'
$flowRight.WrapContents = $true
$flowRight.AutoSize = $true
$flowRight.AutoSizeMode = 'GrowAndShrink'
$flowRight.FlowDirection = 'LeftToRight'
$flowRight.Anchor = 'Right'
$bottom.Controls.Add($flowRight, 1, 0)

$btnInstall       = NewBtn "Installer la selection"
$btnUpdateSel     = NewBtn "Mettre a jour"
$btnUpdateAll     = NewBtn "Tout Mettre a jour"
$btnUninstallSel  = NewBtn "Desinstaller"
$btnShortcut      = NewBtn "Creer raccourci bureau" # NOUVEAU
$flowRight.Controls.AddRange(@($btnInstall,$btnUpdateSel,$btnUpdateAll,$btnUninstallSel,$btnShortcut))

$btnShortcut.Add_Click({
    try {
        $WshShell = New-Object -ComObject WScript.Shell
        $DesktopPath = $WshShell.SpecialFolders.Item("Desktop")
        $ShortcutFile = Join-Path $DesktopPath "SetupNest.lnk"
        $Shortcut = $WshShell.CreateShortcut($ShortcutFile)
        # Point to current executable
        $Shortcut.TargetPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        # If we are in PS script mode (not exe), protect against pointing to powershell.exe
        if ($Shortcut.TargetPath -match "powershell") {
            $Shortcut.TargetPath = Join-Path $PSScriptRoot "start-SetupNest.cmd"
            if (-not (Test-Path $Shortcut.TargetPath)) { 
                # Fallback
                $Shortcut.TargetPath = $PSCommandPath
            }
            $Shortcut.IconLocation = "$PSScriptRoot\logo.ico"
        } else {
            # In EXE mode, the EXE itself has the icon
            $Shortcut.IconLocation = $Shortcut.TargetPath
        }
        $Shortcut.Description = "SetupNest - Installateur d'applications"
        $Shortcut.Save()
        [System.Windows.Forms.MessageBox]::Show("Raccourci cree sur le bureau !", "Succes", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Erreur creation raccourci : " + $_.Exception.Message, "Erreur", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
})

# ===== StatusStrip + Progress =====
$status = New-Object System.Windows.Forms.StatusStrip
$lblStatus = New-Object System.Windows.Forms.ToolStripStatusLabel
$prog = New-Object System.Windows.Forms.ToolStripProgressBar
$prog.Visible = $false
[void]$status.Items.Add($lblStatus)
[void]$status.Items.Add($prog)
$status.Dock = 'Bottom'
$form.Controls.Add($status)

function Set-Status($text, [bool]$busy = $false) {
    if ($status.InvokeRequired) {
        $status.Invoke([Action]{ 
            $lblStatus.Text = $text
            if ($busy) { $prog.Visible = $true; $prog.Style = 'Marquee' } else { $prog.Visible = $false }
        })
    } else {
        $lblStatus.Text = $text
        if ($busy) { $prog.Visible = $true; $prog.Style = 'Marquee' } else { $prog.Visible = $false }
    }
    [System.Windows.Forms.Application]::DoEvents()
}

# ===== Construction de l'arbre avec badges =====
$script:SuppressCheckEvent = $false

function Build-Tree { param([string]$FilterText = "")
    $tree.BeginUpdate()
    $tree.Nodes.Clear()

    $flt = ""
    if ($null -ne $FilterText) { $flt = $FilterText.Trim().ToLowerInvariant() }

    $src = $script:AppsMaster
    $added = 0
    $groups = $src | Group-Object category

    foreach ($g in ($groups | Sort-Object Name)) {
        $children = $g.Group
        if ($flt.Length -ge 2) {
            $children = $children | Where-Object {
                $_.name.ToString().ToLowerInvariant().Contains($flt) -or
                $_.id.ToString().ToLowerInvariant().Contains($flt)
            }
        }
        if (-not $children -or $children.Count -eq 0) { continue }

        $cat = New-Object System.Windows.Forms.TreeNode
        $cat.Text = $g.Name
        
        foreach ($app in ($children | Sort-Object name)) {
            $prefix = "     "
            $state = "none"
            
            if ($script:InstalledIds.ContainsKey($app.id))  { 
                 $prefix = "[OK] "
                 $state = "installed"
            }
            if ($script:UpgradableIds.ContainsKey($app.id)) { 
                 $prefix = "[MAJ] " 
                 $state = "upgradable"
            }
            
            $n = New-Object System.Windows.Forms.TreeNode
            $n.Text = $prefix + $app.name
            $n.Tag  = $app
            
            if ($state -eq 'installed') { $n.ForeColor = [System.Drawing.Color]::DarkGreen }
            if ($state -eq 'upgradable') { $n.ForeColor = [System.Drawing.Color]::DarkOrange }

            if ($app.default -eq $true -and $flt.Length -eq 0) { $n.Checked = $true }
            
            [void]$cat.Nodes.Add($n)
            $added++
        }
        [void]$tree.Nodes.Add($cat)
    }

    if ($added -eq 0) {
        $hint = New-Object System.Windows.Forms.TreeNode
        $hint.Text = "Aucun resultat. Code source: $RepoUrl"
        $hint.Tag  = @{ type = 'repo'; url = $RepoUrl }
        [void]$tree.Nodes.Add($hint)
        $tree.ExpandAll()
    } else {
        if ($flt.Length -ge 2) { $tree.ExpandAll() } else { $tree.CollapseAll() }
    }
    $tree.EndUpdate()
}

$tree.Add_AfterCheck({
    param($sender,$e)
    if ($script:SuppressCheckEvent) { return }
    $script:SuppressCheckEvent = $true
    $node = $e.Node
    if ($node.Nodes.Count -gt 0) {
        foreach ($c in $node.Nodes) { $c.Checked = $node.Checked }
    } else {
        $p = $node.Parent
        if ($p -ne $null) {
            $all = $true
            foreach ($c in $p.Nodes) { if (-not $c.Checked) { $all = $false } }
            $p.Checked = $all
        }
    }
    $script:SuppressCheckEvent = $false
})

$tree.Add_NodeMouseDoubleClick({
    param($sender, $e)
    if ($e.Node -and $e.Node.Tag -and $e.Node.Tag.type -eq 'repo' -and $e.Node.Tag.url) {
        try { Start-Process $e.Node.Tag.url } catch {}
    }
})

# Recherche
$tbSearch.Add_TextChanged({
    $txt = $tbSearch.Text
    if ($null -ne $txt -and $txt.Trim().Length -ge 2) { Build-Tree -FilterText $txt }
    else { Build-Tree }
})
$btnClear.Add_Click({ $tbSearch.Text = ""; Build-Tree })
$btnExpand.Add_Click({ $tree.ExpandAll() })
$btnCollapse.Add_Click({ $tree.CollapseAll() })
$btnRefresh.Add_Click({
    Write-UILog $logBox "Rafraichissement de l'etat des applications..."
    Refresh-AppState -LogBox $logBox
    Build-Tree -FilterText ($tbSearch.Text)
})

# Selection helpers
function Get-SelectedApps(){
    $sel=@()
    foreach($cat in $tree.Nodes){
        foreach($c in $cat.Nodes){
            if($c.Checked -and $c.Tag -and ($c.Tag -is [pscustomobject])){ $sel+=$c.Tag }
        }
    }
    return $sel
}

# Boutons bas
$btnCheckAll.Add_Click({
    $script:SuppressCheckEvent=$true
    foreach ($cat in $tree.Nodes){ $cat.Checked=$true; foreach($c in $cat.Nodes){ $c.Checked=$true } }
    $script:SuppressCheckEvent=$false
})
$btnUncheckAll.Add_Click({
    $script:SuppressCheckEvent=$true
    foreach ($cat in $tree.Nodes){ $cat.Checked=$false; foreach($c in $cat.Nodes){ $c.Checked=$false } }
    $script:SuppressCheckEvent=$false
})

$btnInstall.Add_Click({
    $sel = Get-SelectedApps
    if($sel.Count -eq 0){
        [System.Windows.Forms.MessageBox]::Show("Aucune application selectionnee.","Information",
            [System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        return
    }
    $btnInstall.Enabled=$false
    Set-Status "Installation de la selection..." $true
    Write-UILog $logBox "=== INSTALLATION de la selection ==="
    foreach($a in $sel){ Install-App -App $a -LogBox $logBox }
    Set-Status "Pret" $false
    Write-UILog $logBox "Installations terminees."
    $btnInstall.Enabled=$true
    Refresh-AppState -LogBox $logBox
    Build-Tree -FilterText ($tbSearch.Text)
})

$btnUpdateSel.Add_Click({
    $sel = Get-SelectedApps
    if($sel.Count -eq 0){
        [System.Windows.Forms.MessageBox]::Show("Aucune application selectionnee.","Information",
            [System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        return
    }
    $btnUpdateSel.Enabled=$false
    Set-Status "Mise a jour de la selection..." $true
    Write-UILog $logBox "=== MISE A JOUR de la selection ==="
    foreach($a in $sel){ Update-App -App $a -LogBox $logBox }
    Set-Status "Pret" $false
    Write-UILog $logBox "Mises a jour effectuees (si disponibles)."
    $btnUpdateSel.Enabled=$true
    Refresh-AppState -LogBox $logBox
    Build-Tree -FilterText ($tbSearch.Text)
})

$btnUpdateAll.Add_Click({
    $btnUpdateAll.Enabled=$false
    Set-Status "Mise a jour globale (tous les paquets systeme)..." $true
    Write-UILog $logBox "=== MISE A JOUR GLOBALE ==="
    try { Winget-UpgradeAll -LogBox $logBox; Write-UILog $logBox "Mise a jour globale terminee." }
    catch { Write-UILog $logBox ("Erreur update all : {0}" -f $_.Exception.Message) }
    Set-Status "Pret" $false
    $btnUpdateAll.Enabled=$true
    Refresh-AppState -LogBox $logBox
    Build-Tree -FilterText ($tbSearch.Text)
})

$btnUninstallSel.Add_Click({
    $sel = Get-SelectedApps
    if($sel.Count -eq 0){
        [System.Windows.Forms.MessageBox]::Show("Aucune application selectionnee.","Information",
            [System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        return
    }
    $c = [System.Windows.Forms.MessageBox]::Show("Vous allez desinstaller les applications cochees.`n`nCette action peut etre destructrice. Continuer ?","Confirmation de suppression",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,[System.Windows.Forms.MessageBoxIcon]::Warning)
    if($c -ne [System.Windows.Forms.DialogResult]::Yes){ return }

    $btnUninstallSel.Enabled=$false
    Set-Status "Desinstallation de la selection..." $true
    Write-UILog $logBox "=== DESINSTALLATION de la selection ==="
    foreach($a in $sel){ Uninstall-App -App $a -LogBox $logBox }
    Set-Status "Pret" $false
    Write-UILog $logBox "Desinstallations terminees."
    $btnUninstallSel.Enabled=$true
    Refresh-AppState -LogBox $logBox
    Build-Tree -FilterText ($tbSearch.Text)
})

# Premier affichage
$form.Add_Shown({
    $form.Refresh()
    # Petit délai pour laisser l'UI s'afficher avant de geler pour le premier scan
    [System.Windows.Forms.Application]::DoEvents()
    Start-Sleep -Milliseconds 100
    Refresh-AppState -LogBox $logBox
    Build-Tree
})

[System.Windows.Forms.Application]::Run($form)
