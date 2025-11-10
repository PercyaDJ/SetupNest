# install-gui.ps1
# Lance un panneau graphique avec cases à cocher pour installer des applis via winget

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

function Ensure-Winget {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        [System.Windows.Forms.MessageBox]::Show(
            "winget n'est pas disponible sur ce système.`n`nInstalle 'App Installer' depuis le Microsoft Store puis relance le script.",
            "Erreur – winget introuvable",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        exit 1
    }
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

# Chargement des assemblies GUI
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

Ensure-Winget
$apps = Load-AppsConfig

# ---------- CONSTRUCTION DE LA FENÊTRE ----------

$form = New-Object System.Windows.Forms.Form
$form.Text = "Installateur automatique – Ninite perso"
$form.Size = New-Object System.Drawing.Size(800, 600)
$form.StartPosition = "CenterScreen"

# Label
$label = New-Object System.Windows.Forms.Label
$label.Text = "Sélectionne les applications à installer :"
$label.AutoSize = $true
$label.Location = New-Object System.Drawing.Point(10, 10)
$form.Controls.Add($label)

# Zone de recherche
$searchLabel = New-Object System.Windows.Forms.Label
$searchLabel.Text = "Filtrer :"
$searchLabel.AutoSize = $true
$searchLabel.Location = New-Object System.Drawing.Point(10, 40)
$form.Controls.Add($searchLabel)

$searchBox = New-Object System.Windows.Forms.TextBox
$searchBox.Location = New-Object System.Drawing.Point(70, 38)
$searchBox.Width = 250
$form.Controls.Add($searchBox)

# Liste à cocher
$checkedListBox = New-Object System.Windows.Forms.CheckedListBox
$checkedListBox.Location = New-Object System.Drawing.Point(10, 70)
$checkedListBox.Size = New-Object System.Drawing.Size(500, 450)
$checkedListBox.CheckOnClick = $true
$checkedListBox.DisplayMember = "name"
$form.Controls.Add($checkedListBox)

# Zone log
$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Location = New-Object System.Drawing.Point(520, 70)
$logBox.Size = New-Object System.Drawing.Size(260, 450)
$logBox.Multiline = $true
$logBox.ScrollBars = "Vertical"
$logBox.ReadOnly = $true
$form.Controls.Add($logBox)

# Bouton Tout cocher
$btnCheckAll = New-Object System.Windows.Forms.Button
$btnCheckAll.Text = "Tout cocher"
$btnCheckAll.Location = New-Object System.Drawing.Point(330, 36)
$btnCheckAll.Width = 85
$form.Controls.Add($btnCheckAll)

# Bouton Tout décocher
$btnUncheckAll = New-Object System.Windows.Forms.Button
$btnUncheckAll.Text = "Tout décocher"
$btnUncheckAll.Location = New-Object System.Drawing.Point(420, 36)
$btnUncheckAll.Width = 95
$form.Controls.Add($btnUncheckAll)

# Bouton Installer
$btnInstall = New-Object System.Windows.Forms.Button
$btnInstall.Text = "Installer la sélection"
$btnInstall.Location = New-Object System.Drawing.Point(10, 530)
$btnInstall.Width = 180
$form.Controls.Add($btnInstall)

# Bouton Fermer
$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = "Fermer"
$btnClose.Location = New-Object System.Drawing.Point(680, 530)
$btnClose.Width = 100
$form.Controls.Add($btnClose)

# ---------- LOGIQUE D'AFFICHAGE DES APPS ----------

# On garde une copie complète en mémoire
$global:AllApps = $apps

function Refresh-AppList {
    param(
        [string]$Filter
    )

    $checkedListBox.Items.Clear()

    $filtered = $global:AllApps
    if ($Filter -and $Filter.Trim().Length -gt 0) {
        $f = $Filter.Trim().ToLower()
        $filtered = $global:AllApps | Where-Object {
            $_.name.ToLower().Contains($f) -or
            ($_.category -and $_.category.ToLower().Contains($f))
        }
    }

    foreach ($app in $filtered) {
        $idx = $checkedListBox.Items.Add($app)
        if ($app.default -eq $true) {
            $checkedListBox.SetItemChecked($idx, $true)
        }
    }
}

# Premier remplissage
Refresh-AppList ""

# ---------- ÉVÈNEMENTS ----------

# Filtre dynamique
$searchBox.Add_TextChanged({
    Refresh-AppList $searchBox.Text
})

# Tout cocher
$btnCheckAll.Add_Click({
    for ($i = 0; $i -lt $checkedListBox.Items.Count; $i++) {
        $checkedListBox.SetItemChecked($i, $true)
    }
})

# Tout décocher
$btnUncheckAll.Add_Click({
    for ($i = 0; $i -lt $checkedListBox.Items.Count; $i++) {
        $checkedListBox.SetItemChecked($i, $false)
    }
})

# Fermer
$btnClose.Add_Click({
    $form.Close()
})

# Installer
$btnInstall.Add_Click({
    if ($checkedListBox.CheckedItems.Count -eq 0) {
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

    foreach ($item in $checkedListBox.CheckedItems) {
        Install-App -App $item -LogBox $logBox
    }

    $logBox.AppendText("🎉 Terminé. Pense à redémarrer si nécessaire.`r`n")
    $btnInstall.Enabled = $true
})

# ---------- LANCEMENT ----------

[System.Windows.Forms.Application]::Run($form)
