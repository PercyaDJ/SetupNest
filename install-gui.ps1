# install-gui.ps1
# GUI TreeView pour piloter winget :
# Installer / Mettre a jour (selection ou tout) / Desinstaller / Exporter / Importer
# ASCII-only (pas d'emojis, pas de guillemets typographiques)

[CmdletBinding()]
param()

# ===== Bootstrap de lancement (STA, chemin, debloquage, erreurs) =====
try {
    if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
        $psExe = (Get-Process -Id $PID).Path
        $args  = @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-STA','-File',"`"$PSCommandPath`"")
        $psi   = New-Object System.Diagnostics.ProcessStartInfo -Property @{
            FileName         = $psExe
            ArgumentList     = $args
            WorkingDirectory = (Split-Path -Parent $PSCommandPath)
            UseShellExecute  = $true
        }
        [Diagnostics.Process]::Start($psi) | Out-Null
        exit
    }
} catch {
    Write-Error "Relance en STA impossible : $($_.Exception.Message)"
    exit 2
}

try { Set-Location -LiteralPath $PSScriptRoot } catch {}
try { Unblock-File -Path $PSCommandPath -ErrorAction SilentlyContinue } catch {}
try { Unblock-File -Path (Join-Path $PSScriptRoot 'apps.json') -ErrorAction SilentlyContinue } catch {}
try { Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force -ErrorAction SilentlyContinue } catch {}

$ErrorActionPreference = "Stop"
try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
} catch {
    Write-Error "Impossible de charger Windows Forms : $($_.Exception.Message)"
    try {
        [System.Windows.Forms.MessageBox]::Show(
            "Erreur de lancement : Windows Forms non disponible.`nDetails : $($_.Exception.Message)",
            "Erreur - WinForms",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    } catch {}
    exit 3
}
# ===== Fin bootstrap =====

# ----------------------------
# Detection / aide pour winget
# ----------------------------
function Ensure-Winget {
    if (Get-Command winget -ErrorAction SilentlyContinue) { return }

    $msg = @"
winget n'est pas disponible sur ce systeme.

winget fait partie de l'application "App Installer" du Microsoft Store.

Je peux ouvrir la page du Store pour installer App Installer.
Une fois l'installation terminee, ferme ce script puis relance-le.
"@

    $result = [System.Windows.Forms.MessageBox]::Show(
        $msg,
        "winget manquant",
        [System.Windows.Forms.MessageBoxButtons]::OKCancel,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )

    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        try {
            Start-Process "ms-windows-store://pdp/?productid=9NBLGGH4NNS1"
        } catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Impossible d'ouvrir Microsoft Store automatiquement.`nCherche App Installer dans le Store.",
                "Erreur ouverture Store",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        }
    }

    [System.Windows.Forms.MessageBox]::Show(
        "Le script va se fermer maintenant.`nInstalle App Installer / winget puis relance.",
        "Arret du script",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null

    exit 1
}

# ----------------------------
# Chargement de la config JSON
# ----------------------------
function Load-AppsConfig {
    $configPath = Join-Path $PSScriptRoot "apps.json"

    if (-not (Test-Path $configPath)) {
        [System.Windows.Forms.MessageBox]::Show(
            ("Fichier apps.json introuvable.`n`nAttendu ici : {0}" -f $configPath),
            "Erreur - config manquante",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        exit 1
    }

    try {
        $json = Get-Content $configPath -Raw | ConvertFrom-Json
    } catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Impossible de lire apps.json.`nVerifie que le JSON est valide (UTF-8).",
            "Erreur - JSON invalide",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        exit 1
    }

    return $json
}

# ----------------------------
# Helpers winget + logging
# ----------------------------
function Write-UILog {
    param(
        [System.Windows.Forms.TextBox]$LogBox,
        [string]$Message
    )
    $LogBox.AppendText("$Message`r`n")
    $LogBox.SelectionStart = $LogBox.Text.Length
    $LogBox.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

function Winget-IsInstalled {
    param([string]$Id)
    winget list --id $Id --accept-source-agreements | Select-String $Id -Quiet
}

function Winget-Install   { param([string]$Id) winget install  --id $Id --silent --accept-package-agreements --accept-source-agreements | Out-Null }
function Winget-UpgradeId { param([string]$Id) winget upgrade  --id $Id --silent --accept-package-agreements --accept-source-agreements | Out-Null }
function Winget-UpgradeAll { winget upgrade --all --silent --accept-package-agreements --accept-source-agreements | Out-Null }
function Winget-Uninstall { param([string]$Id) winget uninstall --id $Id --silent --accept-source-agreements | Out-Null }

# ----------------------------
# Actions par application
# ----------------------------
function Install-App {
    param([pscustomobject]$App,[System.Windows.Forms.TextBox]$LogBox)
    $name = $App.name; $id = $App.id
    Write-UILog $LogBox "=== INSTALL: $name ($id) ==="
    if (Winget-IsInstalled -Id $id) { Write-UILog $LogBox "Deja installe, on saute."; Write-UILog $LogBox ""; return }
    try { Write-UILog $LogBox "Installation en cours..."; Winget-Install -Id $id; Write-UILog $LogBox "Installation terminee." }
    catch { Write-UILog $LogBox ("Erreur pendant l'installation : {0}" -f $_.Exception.Message) }
    Write-UILog $LogBox ""
}

function Update-App {
    param([pscustomobject]$App,[System.Windows.Forms.TextBox]$LogBox)
    $name = $App.name; $id = $App.id
    Write-UILog $LogBox "=== UPDATE: $name ($id) ==="
    if (-not (Winget-IsInstalled -Id $id)) { Write-UILog $LogBox "Non installe -> rien a mettre a jour."; Write-UILog $LogBox ""; return }
    try { Write-UILog $LogBox "Mise a jour en cours..."; Winget-UpgradeId -Id $id; Write-UILog $LogBox "Mise a jour terminee (si disponible)." }
    catch { Write-UILog $LogBox ("Erreur pendant la mise a jour : {0}" -f $_.Exception.Message) }
    Write-UILog $LogBox ""
}

function Uninstall-App {
    param([pscustomobject]$App,[System.Windows.Forms.TextBox]$LogBox)
    $name = $App.name; $id = $App.id
    Write-UILog $LogBox "=== UNINSTALL: $name ($id) ==="
    if (-not (Winget-IsInstalled -Id $id)) { Write-UILog $LogBox "Non installe -> rien a desinstaller."; Write-UILog $LogBox ""; return }
    try { Write-UILog $LogBox "Desinstallation en cours..."; Winget-Uninstall -Id $id; Write-UILog $LogBox "Desinstallation terminee." }
    catch { Write-UILog $LogBox ("Erreur pendant la desinstallation : {0}" -f $_.Exception.Message) }
    Write-UILog $LogBox ""
}

# ----------------------------
# GUI (TreeView + boutons)
# ----------------------------
[System.Windows.Forms.Application]::EnableVisualStyles()

Ensure-Winget
$apps = Load-AppsConfig

# Normalise les categories vides
foreach ($app in $apps) {
    if (-not $app.PSObject.Properties.Name -contains "category" -or [string]::IsNullOrWhiteSpace($app.category)) {
        $app | Add-Member -NotePropertyName category -NotePropertyValue "Divers" -Force
    }
}

# Form
$form = New-Object System.Windows.Forms.Form
$form.Text = "SetupNest - Installateur winget (GUI)"
$form.Size = New-Object System.Drawing.Size(1040, 650)
$form.StartPosition = "CenterScreen"

# Titre
$label = New-Object System.Windows.Forms.Label
$label.Text = "Categories -> coche les applis a traiter :"
$label.AutoSize = $true
$label.Location = New-Object System.Drawing.Point(10, 10)
$form.Controls.Add($label)

# TreeView
$tree = New-Object System.Windows.Forms.TreeView
$tree.Location = New-Object System.Drawing.Point(10, 40)
$tree.Size = New-Object System.Drawing.Size(600, 520)
$tree.CheckBoxes = $true
$tree.HideSelection = $false
$tree.ShowLines = $true
$tree.ShowPlusMinus = $true
$tree.ShowRootLines = $true
$form.Controls.Add($tree)

# Log
$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Location = New-Object System.Drawing.Point(620, 40)
$logBox.Size = New-Object System.Drawing.Size(400, 520)
$logBox.Multiline = $true
$logBox.ScrollBars = "Vertical"
$logBox.ReadOnly = $true
$form.Controls.Add($logBox)

# Boutons
$btnWidth = 190
$gap = 10
$leftCol = 10
$midCol  = 210
$rightCol = 410
$lastCol = 610
$y1 = 570
$y2 = 570

$btnCheckAll = New-Object System.Windows.Forms.Button
$btnCheckAll.Text = "Tout cocher"
$btnCheckAll.Location = New-Object System.Drawing.Point($leftCol, $y1)
$btnCheckAll.Width = $btnWidth
$form.Controls.Add($btnCheckAll)

$btnUncheckAll = New-Object System.Windows.Forms.Button
$btnUncheckAll.Text = "Tout decocher"
$btnUncheckAll.Location = New-Object System.Drawing.Point($midCol, $y1)
$btnUncheckAll.Width = $btnWidth
$form.Controls.Add($btnUncheckAll)

$btnInstall = New-Object System.Windows.Forms.Button
$btnInstall.Text = "Installer la selection"
$btnInstall.Location = New-Object System.Drawing.Point($rightCol, $y1)
$btnInstall.Width = $btnWidth
$form.Controls.Add($btnInstall)

$btnUpdateSel = New-Object System.Windows.Forms.Button
$btnUpdateSel.Text = "Mettre a jour la selection"
$btnUpdateSel.Location = New-Object System.Drawing.Point($lastCol, $y1)
$btnUpdateSel.Width = $btnWidth
$form.Controls.Add($btnUpdateSel)

$btnUpdateAll = New-Object System.Windows.Forms.Button
$btnUpdateAll.Text = "Mettre a jour TOUT"
$btnUpdateAll.Location = New-Object System.Drawing.Point($leftCol, $y2+$gap)
$btnUpdateAll.Width = $btnWidth
$form.Controls.Add($btnUpdateAll)

$btnUninstallSel = New-Object System.Windows.Forms.Button
$btnUninstallSel.Text = "Desinstaller la selection"
$btnUninstallSel.Location = New-Object System.Drawing.Point($midCol, $y2+$gap)
$btnUninstallSel.Width = $btnWidth
$form.Controls.Add($btnUninstallSel)

$btnExportSel = New-Object System.Windows.Forms.Button
$btnExportSel.Text = "Exporter la selection (JSON)"
$btnExportSel.Location = New-Object System.Drawing.Point($rightCol, $y2+$gap)
$btnExportSel.Width = $btnWidth
$form.Controls.Add($btnExportSel)

$btnImportSel = New-Object System.Windows.Forms.Button
$btnImportSel.Text = "Importer selection (JSON)"
$btnImportSel.Location = New-Object System.Drawing.Point($lastCol, $y2+$gap)
$btnImportSel.Width = $btnWidth
$form.Controls.Add($btnImportSel)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = "Fermer"
$btnClose.Location = New-Object System.Drawing.Point(920, $y2+$gap)
$btnClose.Width = 100
$form.Controls.Add($btnClose)

# ----------------------------
# Construction de l'arbre
# ----------------------------
$grouped = $apps | Sort-Object category, name | Group-Object category
$script:SuppressCheckEvent = $false

foreach ($g in $grouped) {
    $catNode = New-Object System.Windows.Forms.TreeNode
    $catNode.Text = $g.Name
    $catNode.Tag  = $null

    foreach ($app in ($g.Group | Sort-Object name)) {
        $child = New-Object System.Windows.Forms.TreeNode
        $child.Text = $app.name
        $child.Tag  = $app
        if ($app.default -eq $true) { $child.Checked = $true }
        [void]$catNode.Nodes.Add($child)
    }
    [void]$tree.Nodes.Add($catNode)
}
$tree.ExpandAll()

# Coche/decohe parent-enfants
$tree.Add_AfterCheck({
    param($sender, $e)
    if ($script:SuppressCheckEvent) { return }
    $script:SuppressCheckEvent = $true

    $node = $e.Node
    if ($node.Nodes.Count -gt 0) {
        foreach ($child in $node.Nodes) { $child.Checked = $node.Checked }
    } else {
        $parent = $node.Parent
        if ($parent -ne $null) {
            $allChecked = $true
            foreach ($child in $parent.Nodes) { if (-not $child.Checked) { $allChecked = $false } }
            $parent.Checked = $allChecked
        }
    }
    $script:SuppressCheckEvent = $false
})

# ----------------------------
# Utilitaires sur la selection
# ----------------------------
function Get-CheckedAppsFromTree {
    param([System.Windows.Forms.TreeView]$TreeView)
    $selected = @()
    foreach ($catNode in $TreeView.Nodes) {
        foreach ($child in $catNode.Nodes) {
            if ($child.Checked -and $child.Tag -ne $null) { $selected += $child.Tag }
        }
    }
    $selected
}

function Set-CheckedFromIds {
    param([System.Windows.Forms.TreeView]$TreeView,[string[]]$Ids)
    $idsHash = @{}
    foreach ($id in $Ids) { $idsHash[$id] = $true }

    $script:SuppressCheckEvent = $true
    foreach ($catNode in $TreeView.Nodes) {
        $catShouldCheck = $true
        foreach ($child in $catNode.Nodes) {
            if ($child.Tag -and $idsHash.ContainsKey($child.Tag.id)) { $child.Checked = $true }
            else { $child.Checked = $false; $catShouldCheck = $false }
        }
        $catNode.Checked = $catShouldCheck -and ($catNode.Nodes.Count -gt 0)
    }
    $script:SuppressCheckEvent = $false
}

# ----------------------------
# Actions boutons
# ----------------------------
$btnCheckAll.Add_Click({
    $script:SuppressCheckEvent = $true
    foreach ($catNode in $tree.Nodes) { 
        $catNode.Checked = $true
        foreach ($child in $catNode.Nodes) { $child.Checked = $true }
    }
    $script:SuppressCheckEvent = $false
})

$btnUncheckAll.Add_Click({
    $script:SuppressCheckEvent = $true
    foreach ($catNode in $tree.Nodes) { 
        $catNode.Checked = $false
        foreach ($child in $catNode.Nodes) { $child.Checked = $false }
    }
    $script:SuppressCheckEvent = $false
})

$btnClose.Add_Click({ $form.Close() })

$btnInstall.Add_Click({
    $selected = Get-CheckedAppsFromTree -TreeView $tree
    if ($selected.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Aucune application selectionnee.","Info",
            [System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        return
    }
    $btnInstall.Enabled = $false
    Write-UILog $logBox "=== INSTALLATION de la selection ==="
    foreach ($app in $selected) { Install-App -App $app -LogBox $logBox }
    Write-UILog $logBox "Installations terminees."
    $btnInstall.Enabled = $true
})

$btnUpdateSel.Add_Click({
    $selected = Get-CheckedAppsFromTree -TreeView $tree
    if ($selected.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Aucune application selectionnee.","Info",
            [System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        return
    }
    $btnUpdateSel.Enabled = $false
    Write-UILog $logBox "=== MISE A JOUR de la selection ==="
    foreach ($app in $selected) { Update-App -App $app -LogBox $logBox }
    Write-UILog $logBox "Mises a jour effectuees (si disponibles)."
    $btnUpdateSel.Enabled = $true
})

$btnUpdateAll.Add_Click({
    $btnUpdateAll.Enabled = $false
    Write-UILog $logBox "=== MISE A JOUR DE TOUS LES PAQUETS DISPONIBLES ==="
    try {
        Winget-UpgradeAll
        Write-UILog $logBox "Mise a jour globale terminee (si disponible)."
    } catch {
        Write-UILog $logBox ("Erreur update all : {0}" -f $_.Exception.Message)
    }
    $btnUpdateAll.Enabled = $true
})

$btnUninstallSel.Add_Click({
    $selected = Get-CheckedAppsFromTree -TreeView $tree
    if ($selected.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Aucune application selectionnee.","Info",
            [System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        return
    }
    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "Tu vas desinstaller les applications cochees. Continuer ?",
        "Confirmation",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    $btnUninstallSel.Enabled = $false
    Write-UILog $logBox "=== DESINSTALLATION de la selection ==="
    foreach ($app in $selected) { Uninstall-App -App $app -LogBox $logBox }
    Write-UILog $logBox "Desinstallations terminees."
    $btnUninstallSel.Enabled = $true
})

$btnExportSel.Add_Click({
    $selected = Get-CheckedAppsFromTree -TreeView $tree
    if ($selected.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Aucune application selectionnee a exporter.","Info",
            [System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        return
    }
    $sfd = New-Object System.Windows.Forms.SaveFileDialog
    $sfd.Filter = "JSON (*.json)|*.json"
    $sfd.Title  = "Exporter la selection"
    $sfd.FileName = "apps-selection.json"
    if ($sfd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        try {
            $export = @()
            foreach ($app in $selected) {
                $export += [pscustomobject]@{
                    name     = $app.name
                    id       = $app.id
                    category = $app.category
                    default  = $app.default
                }
            }
            ($export | ConvertTo-Json -Depth 4 | Out-String).Trim() | Set-Content -Path $sfd.FileName -Encoding UTF8
            Write-UILog $logBox ("Export effectue vers : {0}" -f $sfd.FileName)
        } catch {
            Write-UILog $logBox ("Erreur export : {0}" -f $_.Exception.Message)
        }
    }
})

$btnImportSel.Add_Click({
    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Filter = "JSON (*.json)|*.json|Tous (*.*)|*.*"
    $ofd.Title  = "Importer une selection"
    if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        try {
            $json = Get-Content $ofd.FileName -Raw | ConvertFrom-Json
            $ids = @()
            if ($json -is [System.Array]) {
                foreach ($it in $json) {
                    if ($it -is [string]) { $ids += $it }
                    elseif ($it.PSObject.Properties.Name -contains "id") { $ids += [string]$it.id }
                }
            } elseif ($json.PSObject.Properties.Name -contains "apps") {
                foreach ($it in $json.apps) {
                    if ($it.PSObject.Properties.Name -contains "id") { $ids += [string]$it.id }
                }
            }
            if ($ids.Count -eq 0) {
                [System.Windows.Forms.MessageBox]::Show(
                    "Aucun identifiant d'application detecte dans le fichier.",
                    "Import vide",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                ) | Out-Null
                return
            }
            Set-CheckedFromIds -TreeView $tree -Ids $ids
            Write-UILog $logBox ("Import termine : {0} application(s) cochee(s) depuis {1}." -f $ids.Count, $ofd.FileName)
        } catch {
            Write-UILog $logBox ("Erreur import : {0}" -f $_.Exception.Message)
        }
    }
})

# Lancer la fenetre
[System.Windows.Forms.Application]::Run($form)
