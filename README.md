
# 🧰 Ninite perso – Installateur automatique d’applications (winget + GUI)

Ce projet est un équivalent “fait maison” de [Ninite](https://ninite.com/), basé sur :

- **PowerShell**
- **winget** (le gestionnaire de paquets Windows)
- Une **interface graphique (GUI)** avec catégories dépliables

Il permet d’installer rapidement une sélection d’applications sur :
- un **nouveau PC perso**,
- le **PC d’un proche**,
- ou n’importe quel Windows récent,  
sans avoir à télécharger chaque logiciel à la main.

---

## ✨ Fonctionnalités

- Interface graphique en Windows Forms avec un **TreeView** :
  - Catégories dépliables : Navigateur, Bureautique, Communication, Multimédia, Outils, Sécurité, Création, Dev, Jeux, Cloud & Sync, etc.
  - Applications listées sous chaque catégorie avec **cases à cocher**
  - Boutons **“Tout cocher”** / **“Tout décocher”**
  - Bouton **“Installer la sélection”**
- Installation silencieuse via **winget**
- Fichier unique `apps.json` pour gérer **tous les logiciels**
- Indication des applis “par défaut” à cocher automatiquement
- Journal d’installation dans une zone de log à droite
- Vérification de la présence de **winget** au démarrage :
  - Si `winget` n’est pas disponible, le script :
    - affiche un message explicatif,
    - propose d’ouvrir la page *App Installer* dans le Microsoft Store,
    - puis se ferme proprement.

---

## 🧱 Prérequis

- Windows 10 ou 11
- PowerShell (intégré à Windows)
- **winget** installé  
  → Si ce n’est pas le cas, le script t’indiquera comment installer *App Installer* via le Microsoft Store.

---

## 📁 Structure du projet

```text
ninite-perso/
├─ install-gui.ps1          # Script principal avec interface graphique (TreeView + winget)
├─ apps.json                # Liste de toutes les applis disponibles, classées par catégorie
├─ start-ninite-perso.cmd   # (Optionnel) Script pour lancer l’outil en double-cliquant
└─ README.md
```

### `install-gui.ps1`

- Vérifie que `winget` est présent (sinon explique comment l’installer).
- Charge les applis définies dans `apps.json`.
- Construit une interface graphique avec :
  - un **TreeView** (catégories / applis),
  - une zone de log,
  - des boutons d’action.

### `apps.json`

- Fichier de configuration au format JSON
- Contient la **liste des applications** installables
- Chaque entrée contient :
  - `name` : le nom affiché dans l’interface
  - `id` : l’ID winget du paquet
  - `category` : catégorie (Navigateur, Bureautique, Outils, Photo, etc.)
  - `default` : `true` si l’app est cochée par défaut

Exemple (extrait) :

```json
[
  {
    "name": "Google Chrome",
    "id": "Google.Chrome",
    "category": "Navigateur",
    "default": true
  },
  {
    "name": "LibreOffice",
    "id": "TheDocumentFoundation.LibreOffice",
    "category": "Bureautique",
    "default": true
  },
  {
    "name": "Discord",
    "id": "Discord.Discord",
    "category": "Communication",
    "default": true
  }
]
```

### `start-ninite-perso.cmd` (optionnel mais pratique)

Pour pouvoir lancer l’outil par simple double-clic (utile pour la famille / les amis), tu peux ajouter un fichier `start-ninite-perso.cmd` :

```bat
@echo off
:: Lance le script PowerShell avec GUI
powershell.exe -ExecutionPolicy Bypass -NoLogo -NoProfile -File "%~dp0install-gui.ps1"
```

---

## 🚀 Installation & premier lancement

### 1. Cloner ou télécharger le dépôt

```powershell
git clone https://github.com/<ton-user>/<ton-repo>.git
cd <ton-repo>
```

Ou télécharger le ZIP depuis GitHub et l’extraire.

### 2. (Optionnel) Autoriser l’exécution de scripts PowerShell

Si ce n’est pas déjà fait :

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

Accepter (`O` / `Y`) si une confirmation est demandée.

### 3. Lancer l’interface graphique

Deux options :

#### a) Via PowerShell

Depuis le dossier du projet :

```powershell
.\install-gui.ps1
```

#### b) En double-cliquant (si tu as créé `start-ninite-perso.cmd`)

- Double-cliquer sur `start-ninite-perso.cmd`.

Dans tous les cas, une fenêtre s’ouvre avec :
- les catégories,
- les applis sous chaque catégorie,
- les boutons d’action,
- un log à droite.

---

## 🕹️ Utilisation de l’outil

1. **Lancer le script** :

   ```powershell
   .\install-gui.ps1
   ```

   ou double-cliquer sur `start-ninite-perso.cmd`.

2. **Naviguer dans les catégories** :
   - Chaque catégorie (Navigateur, Bureautique, Communication, etc.) se présente comme un nœud dépliable.
   - Clique sur le petit triangle à gauche pour déplier/replier.

3. **Sélectionner les applications** :
   - Coche/décoche les applis à installer sous chaque catégorie.
   - Tu peux aussi cocher/décocher une catégorie entière :
     - cocher une catégorie coche toutes ses applis,
     - décocher la catégorie les décoche toutes.
   - Les applis avec `"default": true` dans `apps.json` sont **cochées par défaut**.

4. **Boutons rapides** :
   - **“Tout cocher”** → coche toutes les applis de toutes les catégories.
   - **“Tout décocher”** → décoche tout.

5. **Lancer les installations** :
   - Cliquer sur **“Installer la sélection”**.
   - Suivre le journal dans le panneau de droite :
     - ✅ déjà installé → l’app est ignorée
     - ⏬ installation en cours
     - ❌ erreur éventuelle (ex : ID incorrect, problème de source)

6. **Fermer** :
   - Une fois terminé, clic sur **“Fermer”**.
   - Pour certains logiciels, un **redémarrage** peut être recommandé.

---

## 🧩 Ajouter ou modifier des applications

Tout se passe dans `apps.json`.

### 1. Catégories recommandées

Tu peux t’en tenir à une dizaine de catégories “réelles” :

- `Navigateur`
- `Bureautique`
- `Communication`
- `Multimédia`
- `Outils`
- `Sécurité`
- `Création`
- `Dev`
- `Jeux`
- `Cloud & Sync`

Ces catégories apparaissent telles quelles dans l’interface (nœuds de l’arbre).

### 2. Trouver l’ID winget d’un logiciel

Dans PowerShell, sur une machine Windows avec winget :

```powershell
winget search "NomDuLogiciel"
```

Exemple :

```powershell
winget search "Google Chrome"
```

Regarde la colonne **Id**.  
C’est cette valeur qu’il faut mettre dans `id` dans le JSON.

Exemple :

```json
{
  "name": "Google Chrome",
  "id": "Google.Chrome",
  "category": "Navigateur",
  "default": true
}
```

### 3. Gérer les applis cochées par défaut

Le champ `default` permet de choisir ce qui est déjà coché quand tu ouvres l’outil :

- `true` → l’appli sera cochée automatiquement
- `false` → décochée par défaut

Exemple :

```json
{
  "name": "7-Zip",
  "id": "7zip.7zip",
  "category": "Outils",
  "default": true
}
```

---

## 🛠️ Dépannage

- **Message “winget n’est pas disponible”**  
  → Le script affiche un message et peut ouvrir la page *App Installer* dans le Microsoft Store.  
  Installe *App Installer*, puis relance le script.

- **Rien ne s’installe pour une app spécifique**  
  → Vérifier que l’ID dans `apps.json` correspond exactement à l’ID winget (`winget search ...`).

- **Erreur JSON / le script refuse de démarrer**  
  → Vérifier que `apps.json` contient un JSON valide :
    - Pas de virgule en trop à la fin
    - Crochets `[` `]` pour le tableau global
    - Accolades `{` `}` bien fermées

---

## 🔮 Pistes d’amélioration possibles

Idées pour faire évoluer le projet :

- Gestion de **profils** (ex : `Bureau`, `Gaming`, `Photo`, `Dev`) avec plusieurs fichiers JSON.
- Export automatique d’un **log dans un fichier** (`C:\ProgramData\ninite-perso\install.log`).
- Paramètres en ligne de commande :
  - Auto-install de certaines catégories
  - Mode silencieux complet sans GUI
- Ajout d’options de **désinstallation** (via `winget uninstall`).
- Version **entreprise / AD** :
  - script CLI sans GUI,
  - intégration dans des GPO,
  - logs centralisés.

---

## 📜 Licence

À adapter selon ton choix (MIT, GPL, etc.).  
Exemple (MIT) :

```text
MIT License

Copyright (c) 2025 <Ton Nom>

Permission is hereby granted, free of charge, to any person obtaining a copy
...
```

---

## 👤 Auteur

Projet maintenu par **<Ton Nom / Pseudo>**  
Pensé pour un usage perso / famille / amis afin d’éviter les soirées “install de programmes” à rallonge. 😄
