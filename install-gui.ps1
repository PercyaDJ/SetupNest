# install-gui.ps1
# GUI avec catégories dépliables (TreeView) pour installer des applis via winget

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

function Ensure-Winget {
    # On s'assure d'avoir Windows.Forms pour les MessageBox
    Add-Type -AssemblyName System.Windows.Forms

    # winget déjà dispo → tout va bien
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        return
    }

    # winget manquant → on propose d'ouvrir le Microsoft Store
    $msg = @"
winget n'est pas disponible sur ce système.

winget fait partie de l'application "App Installer" distribuée via le Microsoft Store.

Je peux ouvrir la page du Store pour que tu installes App Installer.
Une fois l'installation terminée, ferme ce script puis relance-le.
"@

    $result = [System.Windows.Forms.MessageBox]::Show(
        $msg,
        "winget manquant",
        [System.Windows.Forms.MessageBoxButtons]::OKCancel,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )

    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        try {
            # Ouvre la page "App Installer" dans le Microsoft Store
            Start-Process "ms-windows-store://pdp/?productid=9NBLGGH4NNS1"
        } catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Impossible d'ouvrir le Microsoft Store automatiquement.`nTu peux chercher 'App Installer' manuellement dans le Store.",
                "Erreur ouverture Store",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        }
    }

    # Dans tous les cas, on stoppe le script proprement
    [System.Windows.Forms.MessageBox]::Show(
        "Le script va se fermer maintenant.`nInstalle App Installer / winget puis relance-le.",
        "Arrêt du script",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null

    exit 1
}

function Load-AppsConfig {
    $configPath = Join-Path $PSScriptRoot "apps.json"

    if (-not (Test-Path $configPath)) {
        [System.Windows.Forms.MessageBox]::Show(
            "Fichier apps.json introuvable.`n`nAttendu ici : $configPath",
            "Erreur – config manquante",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        exit 1
    }

    try {
        $json = Get-Content $configPath -Raw | ConvertFrom-Json
    } catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Impossible de lire apps.json.`nVérifie que le JSON est valide.",
            "Erreur – JSON invalide",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        exit 1
    }

    return $json
}

function Install-App {
    param(
        [pscustomobject]$App,
        [System.Windows.Forms.TextBox]$LogBox
    )

    $name = $App.name
    $id   = $App.id

    $log = {
        param($msg, $LogBoxInner)
        $LogBoxInner.AppendText("$msg`r`n")
        $LogBoxInner.SelectionStart = $LogBoxInner.Text.Length
        $LogBoxInner.ScrollToCaret()
        [System.Windows.Forms.Application]::DoEvents()
    }

    & $log "=== $name ($id) ===" $LogBox

    # Vérifie si déjà installé
    $installed = winget list --id $id --accept-source-agreements | Select-String $id -Quiet

    if ($installed) {
        & $log "✅ Déjà installé, on saute." $LogBox
        & $log "" $LogBox
        return
    }

    try {
        & $log "⏬ Installation en cours..." $LogBox
        winget install --id $id --silent --accept-package-agreements --accept-source-agreements | Out-Null
        & $log "✅ Installation terminée." $LogBox
    } catch {
        & $log "❌ Erreur pendant l'installation : $($_.Exception.Message)" $LogBox
    }

    & $log "" $LogBox
}

# ---------- GUI ----------

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# Vérifie la présence de winget et aide à l'installer si besoin
Ensure-Winget

# Charge la config des applis
$apps = Load-AppsConfig

# Form
$form = New-Object System.Windows.Forms.Form
$form.Text = "Installateur automatique – Ninite perso"
$form.Size = New-Object System.Drawing.Size(900, 600)
$form.StartPosition = "CenterScreen"

# Label titre
$label = New-Object System.Windows.Forms.Label
$label.Text = "Sélectionne les applications par catégorie :"
$label.AutoSize = $true
$label.Location = New-Object System.Drawing.Point(10, 10)
$form.Controls.Add($label)

# TreeView pour catégories + applis
$tree = New-Object System.Windows.Forms.TreeView
$tree.Location = New-Object System.Drawing.Point(10, 40)
$tree.Size = New-Object System.Drawing.Size(520, 480)
$tree.CheckBoxes = $true
$tree.HideSelection = $false
$tree.ShowLines = $true
$tree.ShowPlusMinus = $true
$tree.ShowRootLines = $true
$form.Controls.Add($tree)

# Zone log
$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Location = New-Object System.Drawing.Point(540, 40)
$logBox.Size = New-Object System.Drawing.Size(340, 480)
$logBox.Multiline = $true
$logBox.ScrollBars = "Vertical"
$logBox.ReadOnly = $true
$form.Controls.Add($logBox)

# Bouton Tout cocher
$btnCheckAll = New-Object System.Windows.Forms.Button
$btnCheckAll.Text = "Tout cocher"
$btnCheckAll.Location = New-Object System.Drawing.Point(10, 530)
$btnCheckAll.Width = 120
$form.Controls.Add($btnCheckAll)

# Bouton Tout décocher
$btnUncheckAll = New-Object System.Windows.Forms.Button
$btnUncheckAll.Text = "Tout décocher"
$btnUncheckAll.Location = New-Object System.Drawing.Point(140, 530)
$btnUncheckAll.Width = 120
$form.Controls.Add($btnUncheckAll)

# Bouton Installer
$btnInstall = New-Object System.Windows.Forms.Button
$btnInstall.Text = "Installer la sélection"
$btnInstall.Location = New-Object System.Drawing.Point(270, 530)
$btnInstall.Width = 170
$form.Controls.Add($btnInstall)

# Bouton Fermer
$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = "Fermer"
$btnClose.Location = New-Object System.Drawing.Point(780, 530)
$btnClose.Width = 100
$form.Controls.Add($btnClose)

# ---------- Construction de l'arbre catégories / applis ----------

# On met une catégorie "Divers" si non renseignée
foreach ($app in $apps) {
    if (-not $app.PSObject.Properties.Name -contains "category" -or [string]::IsNullOrWhiteSpace($app.category)) {
        $app | Add-Member -NotePropertyName category -NotePropertyValue "Divers" -Force
    }
}

# Grouper par catégorie
$grouped = $apps | Sort-Object category, name | Group-Object category

# Flag pour éviter les boucles dans AfterCheck
$script:SuppressCheckEvent = $false

# Remplir le TreeView
foreach ($g in $grouped) {
    $catName = $g.Name
    $catNode = New-Object System.Windows.Forms.TreeNode
    $catNode.Text = $catName
    $catNode.Tag  = $null   # les applis sont sur les nœuds enfants

    foreach ($app in ($g.Group | Sort-Object name)) {
        $child = New-Object System.Windows.Forms.TreeNode
        $child.Text = $app.name
        $child.Tag  = $app
        if ($app.default -eq $true) {
            $child.Checked = $true
        }
        [void]$catNode.Nodes.Add($child)
    }

    [void]$tree.Nodes.Add($catNode)
}

$tree.ExpandAll()

# ---------- Gestion des cases à cocher dans l'arbre ----------

# Quand on coche/décoche une catégorie, on coche/décoche tous les enfants.
# Quand on coche/décoche un enfant, on met à jour le parent (catégorie).

$tree.Add_AfterCheck({
    param($sender, $e)

    if ($script:SuppressCheckEvent) { return }

    $script:SuppressCheckEvent = $true
    $node = $e.Node

    if ($node.Nodes.Count -gt 0) {
        # Nœud catégorie : reporter l'état sur tous les enfants
        foreach ($child in $node.Nodes) {
            $child.Checked = $node.Checked
        }
    } else {
        # Nœud appli : mettre à jour le parent
        $parent = $node.Parent
        if ($parent -ne $null) {
            $allChecked  = $true
            $allUnchecked = $true

            foreach ($child in $parent.Nodes) {
                if ($child.Checked) {
                    $allUnchecked = $false
                } else {
                    $allChecked = $false
                }
            }

            # Catégorie cochée seulement si TOUTES les applis de la catégorie sont cochées
            $parent.Checked = $allChecked
        }
    }

    $script:SuppressCheckEvent = $false
})

# ---------- Fonctions utilitaires ----------

function Get-CheckedAppsFromTree {
    param(
        [System.Windows.Forms.TreeView]$TreeView
    )

    $selected = @()

    foreach ($catNode in $TreeView.Nodes) {
        foreach ($child in $catNode.Nodes) {
            if ($child.Checked -and $child.Tag -ne $null) {
                $selected += $child.Tag
            }
        }
    }

    return $selected
}

# ---------- Événements boutons ----------

$btnCheckAll.Add_Click({
    $script:SuppressCheckEvent = $true
    foreach ($catNode in $tree.Nodes) {
        $catNode.Checked = $true
        foreach ($child in $catNode.Nodes) {
            $child.Checked = $true
        }
    }
    $script:SuppressCheckEvent = $false
})

$btnUncheckAll.Add_Click({
    $script:SuppressCheckEvent = $true
    foreach ($catNode in $tree.Nodes) {
        $catNode.Checked = $false
        foreach ($child in $catNode.Nodes) {
            $child.Checked = $false
        }
    }
    $script:SuppressCheckEvent = $false
})

$btnClose.Add_Click({
    $form.Close()
})

$btnInstall.Add_Click({
    $selectedApps = Get-CheckedAppsFromTree -TreeView $tree

    if ($selectedApps.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "Aucune application sélectionnée.",
            "Info",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
        return
    }

    $btnInstall.Enabled = $false
    $logBox.AppendText("Démarrage des installations...`r`n`r`n")

    foreach ($app in $selectedApps) {
        Install-App -App $app -LogBox $logBox
    }

    $logBox.AppendText("🎉 Terminé. Pense à redémarrer si nécessaire.`r`n")
    $btnInstall.Enabled = $true
})

# ---------- Lancer la fenêtre ----------

[System.Windows.Forms.Application]::Run($form)
