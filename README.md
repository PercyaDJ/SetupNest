
# SetupNest Winget GUI “sous stéroïdes”

Un installateur graphique pour Windows basé sur winget qui permet d’installer, mettre à jour, désinstaller, exporter et importer des listes d’applications… sans aller chasser les installeurs à la main.

> Objectif : gagner des heures à chaque fresh install (chez toi, chez des proches), avec un catalogue JSON unique et une UI claire.

---

## Sommaire

- [Pourquoi ce projet ?](#pourquoi-ce-projet-)
- [Fonctionnalités](#fonctionnalités)
- [Prérequis](#prérequis)
- [Structure du dépôt](#structure-du-dépôt)
- [Installation & premier lancement](#installation--premier-lancement)
- [Utilisation (pas à pas)](#utilisation-pas-à-pas)
- [Catalogue d’apps (`apps.json`)](#catalogue-dapps-appsjson)
  - [Schéma](#schéma)
  - [Exemples](#exemples)
  - [Catégories recommandées](#catégories-recommandées)
  - [Trouver un ID winget](#trouver-un-id-winget)
- [Import / Export (formats)](#import--export-formats)
- [Mise à jour / Désinstallation : subtilités](#mise-à-jour--désinstallation-subtilités)
- [Bonnes pratiques & sécurité](#bonnes-pratiques--sécurité)
- [Dépannage (tableau)](#dépannage-tableau)
- [FAQ](#faq)
- [Roadmap](#roadmap)
- [Contribution](#contribution)
- [Auteur](#auteur)

---

## Pourquoi ce projet ?

- Standardiser l’installation d’un socle logiciel (pour toi, famille/amis).
- Arrêter de télécharger les .exe un par un : winget s’occupe du fetch/instal/update.
- Un fichier JSON central pour tout le monde (porté sur clé USB, GitHub…).

---

## Fonctionnalités

- UI par catégories (TreeView) avec cases à cocher
- Installer la sélection (ignore ce qui est déjà présent)
- Mettre à jour la sélection (`winget upgrade --id <Pkg>`)
- Mettre à jour TOUT (`winget upgrade --all`)
- Désinstaller la sélection (`winget uninstall --id <Pkg>`)
- Exporter la sélection → JSON ré‑importable
- Importer une sélection → coche automatiquement les apps correspondantes
- Journal en temps réel (installations, updates, erreurs)
- Vérification winget au démarrage : si absent, ouverture de la page *App Installer* (Microsoft Store), puis fermeture propre du script

> ⚠️ Le script opère uniquement sur les *IDs winget* présents dans `apps.json` (voir plus bas).

---

## Prérequis

- Windows 10/11
- PowerShell
- winget (via *App Installer* du Microsoft Store)  
  → Le script détecte son absence et propose d’ouvrir la page du Store.

---

## Structure du dépôt

```
SetupNest/
├─ install-gui.ps1          # Script principal (GUI + actions winget)
├─ apps.json                # Catalogue d’apps (id, catégorie, défaut)
├─ start-SetupNest.cmd      # Double‑clic pour lancer la GUI
└─ README.md
```

### `start-SetupNest.cmd` (optionnel mais recommandé)
Permet un lancement double‑clic (utile chez des proches) :
```bat
@echo off
powershell.exe -ExecutionPolicy Bypass -NoLogo -NoProfile -File "%~dp0install-gui.ps1"
```

---

## Installation & premier lancement

### 1) Récupérer le projet
```powershell
git clone https://github.com/PercyaDJ/SetupNest.git
cd SetupNest
```
ou télécharger le ZIP depuis GitHub et extraire.

### 2) Autoriser les scripts PowerShell
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### 3) Lancer l’application
```powershell
.\install-gui.ps1
```
ou double‑cliquer sur `start-SetupNest.cmd` si présent.

---

## Utilisation

1. Déplie une catégorie ▸ et coche les applis à traiter.  
   *Astuce* : cocher une catégorie coche toutes ses applis.
2. Choisis une action :
   - Installer la sélection : installe ce qui manque.
   - Mettre à jour la sélection : update ciblé des applis cochées *déjà installées*.
   - Mettre à jour TOUT : update global (`winget upgrade --all`).
   - Désinstaller la sélection : désinstalle les applis cochées *déjà installées*.
   - Exporter sélection (JSON) : sauvegarde les apps cochées dans un fichier JSON.
   - Importer sélection (JSON) : coche automatiquement les apps dont l’ID figure dans le JSON.
3. Surveille le journal à droite (✅ déjà installé, ⏬ install, ⏫ update, 🗑️ uninstall, ❌ erreur).
4. Ferme en fin d’opérations. Certains paquets peuvent nécessiter un redémarrage.

---

## Catalogue d’apps (`apps.json`)

Le cœur du projet. Le script n’affiche et ne traite que les apps référencées ici.

### Schéma
```json
{
  "name": "Google Chrome",
  "id": "Google.Chrome",
  "category": "Navigateur",
  "default": true
}
```
- `name` : libellé affiché dans l’UI  
- `id` : ID winget du paquet (voir ci‑dessous)  
- `category` : l’une des catégories (ex. `Navigateur`, `Bureautique`, `Dev`, …)  
- `default` : `true` si cochée par défaut, sinon `false`

### Exemples
```json
[
  { "name": "Google Chrome", "id": "Google.Chrome", "category": "Navigateur", "default": true },
  { "name": "LibreOffice", "id": "TheDocumentFoundation.LibreOffice", "category": "Bureautique", "default": true },
  { "name": "Discord", "id": "Discord.Discord", "category": "Communication", "default": true },
  { "name": "VLC media player", "id": "VideoLAN.VLC", "category": "Multimédia", "default": true },
  { "name": "7-Zip", "id": "7zip.7zip", "category": "Outils", "default": true },
  { "name": "Bitwarden", "id": "Bitwarden.Bitwarden", "category": "Sécurité", "default": true },
  { "name": "GIMP", "id": "GIMP.GIMP", "category": "Création", "default": false },
  { "name": "Visual Studio Code", "id": "Microsoft.VisualStudioCode", "category": "Dev", "default": true },
  { "name": "Steam", "id": "Valve.Steam", "category": "Jeux", "default": false },
  { "name": "Nextcloud Desktop", "id": "Nextcloud.NextcloudDesktop", "category": "Cloud & Sync", "default": false }
]
```

### Catégories recommandées
`Navigateur`, `Bureautique`, `Communication`, `Multimédia`, `Outils`, `Sécurité`, `Création`, `Dev`, `Jeux`, `Cloud & Sync`  

### Trouver un ID winget

Sur une machine Windows avec winget :
```powershell
winget search "NomDuLogiciel"
```
Repère la colonne Id et utilise‑la dans `apps.json`.

---

## Import / Export (formats)

Le bouton Exporter sauvegarde la sélection cochée dans un fichier JSON.  
Le bouton Importer coche automatiquement les applis correspondantes dans l’UI.

Formats acceptés à l’import :

### A) Tableau d’IDs winget
```json
["Google.Chrome","VideoLAN.VLC","Microsoft.VisualStudioCode"]
```

### B) Tableau d’objets complets (compatible `apps.json`)
```json
[
  { "name": "VLC media player", "id": "VideoLAN.VLC", "category": "Multimédia", "default": true },
  { "name": "Visual Studio Code", "id": "Microsoft.VisualStudioCode", "category": "Dev", "default": true }
]
```

> Si un ID importé n’existe pas dans ton `apps.json`, il est ignoré (tu peux élargir ton catalogue et ré‑importer).

---

## Mise à jour / Désinstallation : subtilités

- Update sélection : ne concerne que les applis cochées et déjà installées.  
- Update all : `winget upgrade --all` met à jour *tout* ce que winget sait gérer, même si non listé dans `apps.json`.  
- Uninstall sélection : ne désinstalle que les applis cochées et déjà installées.  
- Certains paquets peuvent avoir des installers interactifs qui affichent leurs propres dialogues (rare).

---

## Bonnes pratiques & sécurité

- Lancer la GUI en tant qu’administrateur pour éviter les blocages UAC sur certains paquets.
- Conserver `apps.json` dans un contrôle de version (Git) pour tracer les changements de catalogue.
- Ne pas multiplier les catégories (max ~10).  
- Pour un usage entreprise/AD : privilégier une version CLI séparée (sans GUI), signature de scripts, GPO, logs centralisés. *(Hors périmètre de ce README grand public, mais en roadmap.)*

---

## Dépannage

| Symptôme | Cause probable | Correctif |
|---|---|---|
| Message “winget n’est pas disponible” au lancement | App Installer non installée | Installer *App Installer* via le Microsoft Store (la GUI ouvre la page), puis relancer |
| Une app ne s’installe pas | `id` erroné / package non silencieux / droits | Vérifier `winget search "Nom"`, lancer la GUI en admin |
| Update (“sélection”) ne fait rien | App non installée ou déjà à jour | C’est normal ; installer d’abord, ou utiliser Update all |
| Update all ne fait rien | Aucune mise à jour dispo | Normal |
| Import JSON ne coche rien | IDs non présents dans ton `apps.json` | Ajouter ces apps à `apps.json`, puis ré‑importer |
| “JSON invalide” | Virgule traînante, crochets/accolades | Valider le JSON (outil en ligne), corriger puis relancer |

---

## FAQ

Dois‑je être admin ?  
Souvent oui, selon les paquets. Lancer PowerShell/GUI en admin est conseillé.

Puis‑je gérer plusieurs profils (bureau, dev, gaming) ?  
Oui, maintiens plusieurs fichiers (`apps-bureau.json`, `apps-dev.json`…), et renomme‑les en `apps.json` selon le besoin. *(Un paramètre CLI `-Profile` est envisagé dans la roadmap.)*

Pourquoi winget et pas Chocolatey ?  
winget est natif Windows 10/11, maintenu par Microsoft et couvre l’essentiel des paquets grand public.

Où sont les logs ?  
Le journal s’affiche dans la GUI. L’export vers fichier local (`C:\ProgramData\SetupNest\install.log`) est prévu en roadmap.

---

## Roadmap

- Profils multiples (sélection du JSON depuis l’UI / paramètre CLI)
- Export automatique des logs vers fichier
- Mode CLI (sans GUI) et packaging pour usage pro
- Version entreprise/AD : GPO, signature du script, dépôt central des JSON, logs centralisés

---

## Contribution

- Fork · branche · PR ou ouvre une *issue* pour proposer des applis/améliorations.
- Merci de conserver un schéma JSON simple et des catégories cohérentes.
- Ajoute un extrait `apps.json` dans tes PR si tu ajoutes des apps.

---

## Auteur

**Percya** Parce qu’on préfère boire un café pendant que les installs se font toutes seules. ☕
