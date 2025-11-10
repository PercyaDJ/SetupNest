
# 🧰 Ninite perso – Installateur automatique d’applications (winget + GUI)

Ce projet est un équivalent “fait maison” de [Ninite](https://ninite.com/), basé sur :

- **PowerShell**
- **winget** (le gestionnaire de paquets Windows)
- Une **interface graphique (GUI)** avec des cases à cocher

Il permet d’installer rapidement une sélection d’applications sur :
- un **nouveau PC perso**,
- le **PC d’un proche**,
- ou n’importe quel Windows récent,  
sans avoir à télécharger chaque logiciel à la main.

---

## ✨ Fonctionnalités

- Interface graphique en Windows Forms :
  - Liste d’applications à **cocher/décocher**
  - Zone de **recherche / filtre** (par nom ou catégorie)
  - Boutons **“Tout cocher”** / **“Tout décocher”**
  - Bouton **“Installer la sélection”**
- Installation silencieuse via **winget**
- Fichier unique `apps.json` pour gérer **tous les logiciels**
- Indication des applis “par défaut” à cocher automatiquement
- Journal d’installation dans une zone de log à droite

---

## 🧱 Prérequis

- Windows 10 ou 11
- PowerShell (intégré à Windows)
- **winget** installé  
  → Si ce n’est pas le cas, installer *App Installer* depuis le Microsoft Store.

---

## 📁 Structure du projet

```text
ninite-perso/
├─ install-gui.ps1    # Script principal avec interface graphique
├─ apps.json          # Liste de toutes les applis disponibles
└─ README.md
```

### `install-gui.ps1`

- Lance une fenêtre graphique
- Charge les applis définies dans `apps.json`
- Permet de :
  - filtrer la liste,
  - cocher/décocher les apps,
  - lancer l’installation via winget.

### `apps.json`

- Fichier de configuration au format JSON
- Contient la **liste des applications** installables
- Chaque entrée contient :
  - `name` : le nom affiché dans l’interface
  - `id` : l’ID winget du paquet
  - `category` : catégorie (Navigateur, Outils, Photo, etc.)
  - `default` : `true` si l’app est cochée par défaut

Exemple :

```json
[
  {
    "name": "Google Chrome",
    "id": "Google.Chrome",
    "category": "Navigateur",
    "default": true
  },
  {
    "name": "VLC media player",
    "id": "VideoLAN.VLC",
    "category": "Multimédia",
    "default": true
  },
  {
    "name": "Discord",
    "id": "Discord.Discord",
    "category": "Communication",
    "default": false
  }
]
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

Depuis le dossier du projet :

```powershell
.\install-gui.ps1
```

Une fenêtre s’ouvre avec :
- la liste des applications,
- la zone de recherche,
- les boutons d’action,
- un log à droite.

---

## 🕹️ Utilisation de l’outil

1. **Lancer le script** :

   ```powershell
   .\install-gui.ps1
   ```

2. **Filtrer la liste** :
   - Utiliser le champ **“Filtrer”** pour réduire la la liste (par exemple taper `navigateur`, `photo`, `chrome`, etc.)
   - Le filtre fonctionne sur :
     - le `name`
     - la `category`

3. **Sélectionner les applications** :
   - Cocher/décocher les applis à installer
   - Bouton **“Tout cocher”** pour tout sélectionner
   - Bouton **“Tout décocher”** pour repartir de zéro

4. **Lancer les installations** :
   - Cliquer sur **“Installer la sélection”**
   - Suivre le journal dans le panneau de droite :
     - ✅ déjà installé → l’app est ignorée
     - ⏬ installation en cours
     - ❌ erreur éventuelle (ex : ID incorrect, problème de source)

5. **Fermer** :
   - Une fois terminé, cliquer sur **“Fermer”**
   - Pour certains logiciels, un **redémarrage** peut être recommandé.

---

## 🧩 Ajouter ou modifier des applications

Tout se passe dans `apps.json`.

### 1. Trouver l’ID winget d’un logiciel

Dans PowerShell :

```powershell
winget search "NomDuLogiciel"
```

Exemple :

```powershell
winget search "Google Chrome"
```

Tu verras une table avec une colonne **Id**.  
C’est cette valeur qu’il faut mettre dans `id` dans le JSON.

Exemple de résultats typiques :

```text
Name           Id               Source
------------   ---------------  ------
Google Chrome  Google.Chrome    winget
```

Dans `apps.json` :

```json
{
  "name": "Google Chrome",
  "id": "Google.Chrome",
  "category": "Navigateur",
  "default": true
}
```

### 2. Définir les catégories

Tu peux organiser tes applis par grandes catégories :

- `Navigateur`
- `Outils`
- `Multimédia`
- `Communication`
- `Photo`
- `Dev`
- etc.

La catégorie est utilisée dans le filtre :  
si tu tapes `photo`, toutes les applis avec `"category": "Photo"` ressortent.

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
  → Installer *App Installer* depuis le Microsoft Store, puis relancer le script.

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

- Gestion de **profils** (ex : `Bureau`, `Gaming`, `Photo`, `Dev`)  
- Export automatique d’un **log dans un fichier** (`install-log.txt`)
- Paramètres en ligne de commande :
  - Auto-install de certaines catégories
  - Mode silencieux complet sans GUI
- Ajout d’options de **désinstallation** (via `winget uninstall`)

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
Adapté pour un usage perso / famille / amis afin d’éviter les soirées “install de programmes” à rallonge. 😄
