# install-gui.ps1
# SetupNest - Winget GUI (PS5-compatible)
# UI propre : header autosize, groupboxes, search + cue banner, split sécurisé, bottom bar nette
# Live search (>=2 chars), expand/collapse, lien repo si aucun résultat
# Streaming winget logs (stdout/stderr)
# Code ASCII ; apps.json lu en UTF-8

[CmdletBinding()]
param()

# ===== Settings =====
$RepoUrl = "https://github.com/PercyaDJ/SetupNest"  # <- mets l'URL de ton repo

# ===== Relaunch in STA (PS5) =====
try {
    if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
        $psExe = (Get-Process -Id $PID).Path
        $args  = @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-STA','-File',"`"$PSCommandPath`"")
        $psi   = New-Object System.Diagnostics.ProcessStartInfo -Property @{
            FileName         = $psExe
            WorkingDirectory = (Split-Path -Parent $PSCommandPath)
            UseShellExecute  = $true
            Arguments        = ($args -join ' ')
        }
        [Diagnostics.Process]::Start($psi) | Out-Null
        exit
    }
} catch {
    Write-Error "Impossible de relancer en STA : $($_.Exception.Message)"
    exit 2
}

# ===== Prep =====
try { Set-Location -LiteralPath $PSScriptRoot } catch {}
try { Unblock-File -Path $PSCommandPath -ErrorAction SilentlyContinue } catch {}
try { Unblock-File -Path (Join-Path $PSScriptRoot 'apps.json') -ErrorAction SilentlyContinue } catch {}
try { Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force -ErrorAction SilentlyContinue } catch {}
$ErrorActionPreference = "Stop"

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

# ===== Winget presence =====
function Ensure-Winget {
    if (Get-Command winget -ErrorAction SilentlyContinue) { return }
    $msg = @"
winget n'est pas disponible sur ce systeme.

winget fait partie de l'application "App Installer" du Microsoft Store.

Je peux ouvrir la page du Store pour installer App Installer.
Une fois l'installation terminee, ferme ce script puis relance-le.
"@
    $r = [System.Windows.Forms.MessageBox]::Show($msg, "winget manquant",
        [System.Windows.Forms.MessageBoxButtons]::OKCancel,
        [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($r -eq [System.Windows.Forms.DialogResult]::OK) {
        try { Start-Process "ms-windows-store://pdp/?productid=9NBLGGH4NNS1" } catch {}
    }
    [System.Windows.Forms.MessageBox]::Show(
        "Le script va se fermer maintenant. Installe App Installer / winget puis relance.",
        "Arret du script",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
    exit 1
}

# ===== Read apps.json (UTF-8) =====
function Load-AppsConfig {
    $configPath = Join-Path $PSScriptRoot "apps.json"
    if (-not (Test-Path $configPath)) {
        [System.Windows.Forms.MessageBox]::Show(("Fichier apps.json introuvable.`n`nAttendu : {0}" -f $configPath),
            "Erreur - config manquante",[System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        exit 1
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

# ===== Logging & streaming =====
function Write-UILog { param([System.Windows.Forms.TextBox]$LogBox,[string]$Message)
    $LogBox.AppendText("$Message`r`n")
    $LogBox.SelectionStart = $LogBox.Text.Length
    $LogBox.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}
function Add-LogLineSafe { param([System.Windows.Forms.TextBox]$LogBox,[string]$Line)
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
    $p.WaitForExit()
    return $p.ExitCode
}

# ===== Winget helpers =====
function Winget-IsInstalled { param([string]$Id)
    winget list --id $Id --accept-source-agreements | Select-String $Id -Quiet
}
function Winget-Install    { param([string]$Id,[System.Windows.Forms.TextBox]$LogBox)
    [void](Invoke-WingetStreaming -Arguments @('install','--id',$Id,'--silent','--accept-package-agreements','--accept-source-agreements') -LogBox $LogBox)
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

# ===== Actions =====
function Install-App { param([pscustomobject]$App,[System.Windows.Forms.TextBox]$LogBox)
    $name=$App.name; $id=$App.id
    Write-UILog $LogBox "=== INSTALL: $name ($id) ==="
    if (Winget-IsInstalled -Id $id) { Write-UILog $LogBox "Deja installe, ignore."; Write-UILog $LogBox ""; return }
    try { Write-UILog $LogBox "Installation en cours..."; Winget-Install -Id $id -LogBox $LogBox; Write-UILog $LogBox "Installation terminee." }
    catch { Write-UILog $LogBox ("Erreur pendant l'installation : {0}" -f $_.Exception.Message) }
    Write-UILog $LogBox ""
}
function Update-App { param([pscustomobject]$App,[System.Windows.Forms.TextBox]$LogBox)
    $name=$App.name; $id=$App.id
    Write-UILog $LogBox "=== UPDATE: $name ($id) ==="
    if (-not (Winget-IsInstalled -Id $id)) { Write-UILog $LogBox "Non installe -> rien a mettre a jour."; Write-UILog $LogBox ""; return }
    try { Write-UILog $LogBox "Mise a jour en cours..."; Winget-UpgradeId -Id $id -LogBox $LogBox; Write-UILog $LogBox "Mise a jour terminee (si disponible)." }
    catch { Write-UILog $LogBox ("Erreur pendant la mise a jour : {0}" -f $_.Exception.Message) }
    Write-UILog $LogBox ""
}
function Uninstall-App { param([pscustomobject]$App,[System.Windows.Forms.TextBox]$LogBox)
    $name=$App.name; $id=$App.id
    Write-UILog $LogBox "=== UNINSTALL: $name ($id) ==="
    if (-not (Winget-IsInstalled -Id $id)) { Write-UILog $LogBox "Non installe -> rien a desinstaller."; Write-UILog $LogBox ""; return }
    try { Write-UILog $LogBox "Desinstallation en cours..."; Winget-Uninstall -Id $id -LogBox $LogBox; Write-UILog $LogBox "Desinstallation terminee." }
    catch { Write-UILog $LogBox ("Erreur pendant la desinstallation : {0}" -f $_.Exception.Message) }
    Write-UILog $LogBox ""
}

# ===== Data =====
Ensure-Winget
$apps = Load-AppsConfig
foreach ($app in $apps) {
    if (-not $app.PSObject.Properties.Name -contains "category" -or [string]::IsNullOrWhiteSpace($app.category)) {
        $app | Add-Member -NotePropertyName category -NotePropertyValue "Divers" -Force
    }
}
$script:AppsMaster = $apps  # source pour la recherche

# ===== UI (Form + Layout) =====
$form = New-Object System.Windows.Forms.Form
$form.Text = "SetupNest - Installateur winget (GUI)"
$form.Size = [System.Drawing.Size]::new(1100, 700)
$form.MinimumSize = [System.Drawing.Size]::new(960, 560)
$form.StartPosition = "CenterScreen"
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$form.AutoScaleMode = 'Dpi'

# Layout global 3 lignes
$layout = New-Object System.Windows.Forms.TableLayoutPanel
$layout.Dock = 'Fill'
$layout.ColumnCount = 1
$layout.RowCount = 3
$layout.RowStyles.Add( (New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)) )   # header autosize
$layout.RowStyles.Add( (New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)) ) # contenu
$layout.RowStyles.Add( (New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)) )   # boutons
$form.Controls.Add($layout)

# ===== Header propre (TableLayout 2 colonnes) =====
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

# Col 0 : titre
$lbl = New-Object System.Windows.Forms.Label
$lbl.Text = "Categories -> coche les applis a traiter :"
$lbl.AutoSize = $true
$lbl.Anchor = 'Left'
$header.Controls.Add($lbl, 0, 0)

# Col 1 : bloc droit (2 lignes : recherche / boutons)
$hdrRight = New-Object System.Windows.Forms.TableLayoutPanel
$hdrRight.AutoSize = $true
$hdrRight.AutoSizeMode = 'GrowAndShrink'
$hdrRight.ColumnCount = 1
$hdrRight.RowCount = 2
# 2 lignes en AutoSize
[void]$hdrRight.RowStyles.Add( (New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)) )
[void]$hdrRight.RowStyles.Add( (New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)) )
$hdrRight.Padding = [System.Windows.Forms.Padding]::new(0,0,0,0)
$hdrRight.Margin  = [System.Windows.Forms.Padding]::new(0,0,0,0)
$hdrRight.Anchor  = 'Right'
$header.Controls.Add($hdrRight, 1, 0)

# Ligne 1 : zone de recherche
$tbSearch = New-Object System.Windows.Forms.TextBox
$tbSearch.Width = 240
Set-CueBanner $tbSearch "Rechercher (nom ou id)..."
$tbSearch.Anchor = 'Right'
$hdrRight.Controls.Add($tbSearch, 0, 0)

# Ligne 2 : boutons sur UNE SEULE LIGNE, alignes a droite
$hdrBtns = New-Object System.Windows.Forms.FlowLayoutPanel
$hdrBtns.AutoSize      = $true
$hdrBtns.AutoSizeMode  = 'GrowAndShrink'
$hdrBtns.WrapContents  = $false          # <- force une seule ligne
$hdrBtns.FlowDirection = 'LeftToRight'
$hdrBtns.Padding       = [System.Windows.Forms.Padding]::new(0,4,0,0)
$hdrBtns.Margin        = [System.Windows.Forms.Padding]::new(0,0,0,0)
$hdrBtns.Anchor        = 'Right'
$hdrRight.Controls.Add($hdrBtns, 0, 1)

$btnClear = New-Object System.Windows.Forms.Button
$btnClear.Text = "Effacer"
$btnClear.AutoSize = $true

$btnExpand = New-Object System.Windows.Forms.Button
$btnExpand.Text = "Deplier tout"
$btnExpand.AutoSize = $true

$btnCollapse = New-Object System.Windows.Forms.Button
$btnCollapse.Text = "Replier tout"
$btnCollapse.AutoSize = $true

$hdrBtns.Controls.AddRange(@($btnClear,$btnExpand,$btnCollapse))

# ===== Contenu : 2 colonnes avec GroupBox =====
$contentPad = New-Object System.Windows.Forms.Panel
$contentPad.Dock = 'Fill'
$contentPad.Padding = [System.Windows.Forms.Padding]::new(8, 0, 8, 0)
$layout.Controls.Add($contentPad, 0, 1)

$split = New-Object System.Windows.Forms.SplitContainer
$split.Dock = 'Fill'
$split.Orientation = 'Vertical'
$contentPad.Controls.Add($split)

# Left group (catalogue)
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
$tree.Font = $form.Font
$grpLeft.Controls.Add($tree)

# Right group (journal)
$grpRight = New-Object System.Windows.Forms.GroupBox
$grpRight.Text = "Journal"
$grpRight.Dock = 'Fill'
$grpRight.Padding = [System.Windows.Forms.Padding]::new(8,18,8,8)
$split.Panel2.Controls.Add($grpRight)

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Dock = 'Fill'
$logBox.Multiline = $true
$logBox.ScrollBars = "Vertical"
$logBox.ReadOnly = $true
$logBox.Font = New-Object System.Drawing.Font("Consolas", 10)
$grpRight.Controls.Add($logBox)

# Split sécurisé
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
    $p1Min = 320; $p2Min = 360
    $split.Panel1MinSize = $p1Min
    $split.Panel2MinSize = $p2Min
    $split.SplitterWidth  = 5
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

# ===== Tree building (search + repo link) =====
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
            $n = New-Object System.Windows.Forms.TreeNode
            $n.Text = $app.name
            $n.Tag  = $app
            if ($app.default -eq $true -and $flt.Length -eq 0) { $n.Checked = $true }
            [void]$cat.Nodes.Add($n)
            $added++
        }
        [void]$tree.Nodes.Add($cat)
    }

    if ($added -eq 0) {
        $hint = New-Object System.Windows.Forms.TreeNode
        $hint.Text = "Aucun resultat. Proposer un ajout: $RepoUrl"
        $hint.Tag  = @{ type = 'repo'; url = $RepoUrl }
        [void]$tree.Nodes.Add($hint)
        $tree.ExpandAll()
    } else {
        if ($flt.Length -ge 2) { $tree.ExpandAll() } else { $tree.CollapseAll() }
    }
    $tree.EndUpdate()
}
Build-Tree

# Sync parent/children checks
$script:SuppressCheckEvent = $false
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

# Repo double-click on hint
$tree.Add_NodeMouseDoubleClick({
    param($sender, $e)
    if ($e.Node -and $e.Node.Tag -and $e.Node.Tag.type -eq 'repo' -and $e.Node.Tag.url) {
        try { Start-Process $e.Node.Tag.url } catch {}
    }
})

# Search + expand/collapse actions
$tbSearch.Add_TextChanged({
    $txt = $tbSearch.Text
    if ($null -ne $txt -and $txt.Trim().Length -ge 2) { Build-Tree -FilterText $txt }
    else { Build-Tree }
})
$btnClear.Add_Click({ $tbSearch.Text = ""; Build-Tree })
$btnExpand.Add_Click({ $tree.ExpandAll() })
$btnCollapse.Add_Click({ $tree.CollapseAll() })

# ===== Bottom buttons (2 blocs) =====
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

# Bloc gauche (selection)
$flowLeft = New-Object System.Windows.Forms.FlowLayoutPanel
$flowLeft.Dock = 'Fill'
$flowLeft.WrapContents = $true
$flowLeft.AutoSize = $true
$flowLeft.AutoSizeMode = 'GrowAndShrink'
$bottom.Controls.Add($flowLeft, 0, 0)

$btnCheckAll      = NewBtn "Tout cocher"
$btnUncheckAll    = NewBtn "Tout decocher"
$flowLeft.Controls.AddRange(@($btnCheckAll,$btnUncheckAll))

# Bloc droit (actions)
$flowRight = New-Object System.Windows.Forms.FlowLayoutPanel
$flowRight.Dock = 'Fill'
$flowRight.WrapContents = $true
$flowRight.AutoSize = $true
$flowRight.AutoSizeMode = 'GrowAndShrink'
$flowRight.FlowDirection = 'LeftToRight'
$flowRight.Anchor = 'Right'
$bottom.Controls.Add($flowRight, 1, 0)

$btnInstall       = NewBtn "Installer la selection"
$btnUpdateSel     = NewBtn "Mettre a jour la selection"
$btnUpdateAll     = NewBtn "Tout mettre a jour"
$btnUninstallSel  = NewBtn "Desinstaller la selection"
$btnExportSel     = NewBtn "Exporter la selection (JSON)"
$btnImportSel     = NewBtn "Importer selection (JSON)"
$btnClose         = NewBtn "Fermer"
$flowRight.Controls.AddRange(@(
    $btnInstall,$btnUpdateSel,$btnUpdateAll,$btnUninstallSel,$btnExportSel,$btnImportSel,$btnClose
))

# Tooltips
$tip = New-Object System.Windows.Forms.ToolTip
$tip.SetToolTip($tbSearch,"Filtrer (nom ou id) - 2 caracteres minimum")
$tip.SetToolTip($btnClear,"Effacer le filtre")
$tip.SetToolTip($btnExpand,"Deplier tout")
$tip.SetToolTip($btnCollapse,"Replier tout")
$tip.SetToolTip($btnCheckAll,"Cocher toutes les applis")
$tip.SetToolTip($btnUncheckAll,"Decocher toutes les applis")

# ===== Button handlers =====
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
$btnClose.Add_Click({ $form.Close() })

function Get-SelectedApps(){
    $sel=@()
    foreach($cat in $tree.Nodes){
        foreach($c in $cat.Nodes){
            if($c.Checked -and $c.Tag -and ($c.Tag -is [pscustomobject])){ $sel+=$c.Tag }
        }
    }
    return $sel
}

$btnInstall.Add_Click({
    $sel = Get-SelectedApps
    if($sel.Count -eq 0){
        [System.Windows.Forms.MessageBox]::Show("Aucune application selectionnee.","Information",
            [System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        return
    }
    $btnInstall.Enabled=$false
    Write-UILog $logBox "=== INSTALLATION de la selection ==="
    foreach($a in $sel){ Install-App -App $a -LogBox $logBox }
    Write-UILog $logBox "Installations terminees."
    $btnInstall.Enabled=$true
})

$btnUpdateSel.Add_Click({
    $sel = Get-SelectedApps
    if($sel.Count -eq 0){
        [System.Windows.Forms.MessageBox]::Show("Aucune application selectionnee.","Information",
            [System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        return
    }
    $btnUpdateSel.Enabled=$false
    Write-UILog $logBox "=== MISE A JOUR de la selection ==="
    foreach($a in $sel){ Update-App -App $a -LogBox $logBox }
    Write-UILog $logBox "Mises a jour effectuees (si disponibles)."
    $btnUpdateSel.Enabled=$true
})

$btnUpdateAll.Add_Click({
    $btnUpdateAll.Enabled=$false
    Write-UILog $logBox "=== MISE A JOUR DE TOUS LES PAQUETS DISPONIBLES ==="
    try { Winget-UpgradeAll -LogBox $logBox; Write-UILog $logBox "Mise a jour globale terminee (si disponible)." }
    catch { Write-UILog $logBox ("Erreur update all : {0}" -f $_.Exception.Message) }
    $btnUpdateAll.Enabled=$true
})

$btnUninstallSel.Add_Click({
    $sel = Get-SelectedApps
    if($sel.Count -eq 0){
        [System.Windows.Forms.MessageBox]::Show("Aucune application selectionnee.","Information",
            [System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        return
    }
    $c = [System.Windows.Forms.MessageBox]::Show("Tu vas desinstaller les applications cochees. Continuer ?","Confirmation",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,[System.Windows.Forms.MessageBoxIcon]::Warning)
    if($c -ne [System.Windows.Forms.DialogResult]::Yes){ return }

    $btnUninstallSel.Enabled=$false
    Write-UILog $logBox "=== DESINSTALLATION de la selection ==="
    foreach($a in $sel){ Uninstall-App -App $a -LogBox $logBox }
    Write-UILog $logBox "Desinstallations terminees."
    $btnUninstallSel.Enabled=$true
})

$btnExportSel.Add_Click({
    $sel = Get-SelectedApps
    if($sel.Count -eq 0){
        [System.Windows.Forms.MessageBox]::Show("Aucune application selectionnee a exporter.","Information",
            [System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        return
    }
    $sfd=New-Object System.Windows.Forms.SaveFileDialog
    $sfd.Filter="JSON (*.json)|*.json"
    $sfd.Title="Exporter la selection"
    $sfd.FileName="apps-selection.json"
    if($sfd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK){
        try{
            ($sel | ConvertTo-Json -Depth 4 | Out-String).Trim() | Set-Content -Path $sfd.FileName -Encoding UTF8
            Write-UILog $logBox ("Export effectue vers : {0}" -f $sfd.FileName)
        } catch {
            Write-UILog $logBox ("Erreur export : {0}" -f $_.Exception.Message)
        }
    }
})

$btnImportSel.Add_Click({
    $ofd=New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Filter="JSON (*.json)|*.json|Tous (*.*)|*.*"
    $ofd.Title="Importer une selection"
    if($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK){
        try{
            $json = Get-Content $ofd.FileName -Raw | ConvertFrom-Json
            $ids=@()
            if($json -is [System.Array]){
                foreach($it in $json){
                    if($it -is [string]){ $ids+=$it }
                    elseif($it.PSObject.Properties.Name -contains "id"){ $ids+=[string]$it.id }
                }
            } elseif($json.PSObject.Properties.Name -contains "apps"){
                foreach($it in $json.apps){ if($it.PSObject.Properties.Name -contains "id"){ $ids+=[string]$it.id } }
            }
            if($ids.Count -eq 0){
                [System.Windows.Forms.MessageBox]::Show("Aucun identifiant d'application detecte.","Import vide",
                    [System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
                return
            }
            $hash=@{}; foreach($i in $ids){ $hash[$i]=$true }
            $script:SuppressCheckEvent=$true
            foreach($cat in $tree.Nodes){
                $all=$true
                foreach($c in $cat.Nodes){
                    if($c.Tag -and $hash.ContainsKey($c.Tag.id)){ $c.Checked=$true } else { $c.Checked=$false; $all=$false }
                }
                $cat.Checked = $all -and ($cat.Nodes.Count -gt 0)
            }
            $script:SuppressCheckEvent=$false
            Write-UILog $logBox ("Import termine : {0} application(s) cochee(s) depuis {1}." -f $ids.Count,$ofd.FileName)
        } catch {
            Write-UILog $logBox ("Erreur import : {0}" -f $_.Exception.Message)
        }
    }
})

[System.Windows.Forms.Application]::Run($form)
