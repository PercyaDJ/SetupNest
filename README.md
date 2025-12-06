# SetupNest - L'Installateur Windows Ultime

Un installateur graphique moderne pour Windows, basé sur **winget**, qui permet d’installer, mettre à jour, désinstaller et migrer vos applications préférées en quelques clics.

> **Objectif** : Gagner des heures à chaque réinstallation de PC avec un outil tout-en-un, portable et élégant.

![Logo SetupNest](logo.png)

---

## ✨ Fonctionnalités

*   **Zero-Config** : Un seul exécutable `SetupNest.exe` portable.
*   **Catalogue JSON** : Une liste unique (`apps.json`) modifiable pour définir vos apps favorites.
*   **Auto-Download** : Si le catalogue ou l'icône manquent, l'outil les télécharge automatiquement depuis GitHub.
*   **Interface Moderne** : 
    *   Thème sombre et icônes claires.
    *   Feedback visuel : `[OK]` (Installé) / `[MAJ]` (Update dispo).
    *   Ne gèle jamais (multithreading).
*   **Actions Winget Complètes** :
    *   Installation par lot.
    *   Mise à jour ciblée (uniquement la sélection) ou Globale (tout le PC).
    *   Désinstallation.
    *   Export/Import de votre sélection.

---

## 🚀 Utilisation (Mode "Grand Public")

L'outil est conçu pour être utilisé sans connaissances techniques.

### 1. Télécharger
Récupérez simplement le fichier **[`SetupNest.exe`](SetupNest.exe)** (dans les Releases ou sur le dépôt).

### 2. Lancer
Double-cliquez sur `SetupNest.exe`.
*   Acceptez la demande d'administration (nécessaire pour installer des logiciels).
*   *Note de sécurité* : Comme le logiciel est "signé maison", Windows peut afficher un avertissement bleu au premier lancement. Cliquez sur "Informations complémentaires" > "Exécuter quand même".

### 3. Installer vos apps
1.  Cochez les cases des logiciels que vous voulez.
2.  Cliquez sur **Installer la sélection**.
3.  Laissez faire ! Le journal à droite vous montre l'avancement.

---

## 🛠️ Pour les "Bricoleurs" (Configuration)

### Le fichier `apps.json`
L'outil se base sur ce fichier pour savoir quelles applications proposer.
S'il n'est pas présent à côté de l'EXE, il sera téléchargé automatiquement. Pour personnaliser votre liste, créez/modifiez ce fichier à côté de l'EXE.

#### Format
```json
[
  { "name": "Google Chrome", "id": "Google.Chrome", "category": "Navigateur", "default": true },
  { "name": "VLC", "id": "VideoLAN.VLC", "category": "Multimédia", "default": true }
]
```
*   `id` : L'identifiant unique winget (trouvez-le via `winget search "NomApp"` dans un terminal).
*   `default` : `true` pour que la case soit cochée au démarrage.

---

## 🏗️ Refaire l'Exécutable (Build)

Vous avez modifié le code `install-gui.ps1` et vous voulez recréer votre propre `SetupNest.exe` ? C'est prévu !

### Prérequis
*   Windows 10/11
*   Aucun outil externe (le script utilise le compilateur C# intégré à Windows).

### Procédure
1.  Ouvrez le dossier du projet.
2.  Faites un clic droit sur le fichier **`build_setupnest.ps1`**.
3.  Choisissez **"Exécuter avec PowerShell"**.

Le script va :
1.  Lire le code de `install-gui.ps1`.
2.  Lire l'icône `logo.ico`.
3.  Compiler le tout en un nouvel exécutable `SetupNest.exe`.
4.  Appliquer une signature numérique (certificat auto-signé "SetupNest").

> **Note** : Le nouvel exécutable remplacera l'ancien.

---

## 📂 Structure du projet

```
SetupNest/
├── SetupNest.exe        # L'application finale (à distribuer)
├── apps.json            # Le catalogue d'applications (source de vérité)
├── install-gui.ps1      # Le code source de l'interface (PowerShell)
├── build_setupnest.ps1  # Le script pour recréer l'EXE
├── logo.ico             # L'icône de l'application
└── README.md            # Ce fichier
```

---

## ⚠️ Dépannage

| Problème | Solution |
|---|---|
| **"Winget n'est pas disponible"** | L'outil vous proposera d'installer "App Installer" du Microsoft Store. Faites-le et relancez. |
| **Avertissement "Windows a protégé votre PC"** | C'est normal (certificat auto-signé). Cliquez sur "Infos complé." -> "Éxécuter". |
| **L'app ne se lance pas** | Vérifiez que vous avez bien le Framework .NET (installé par défaut sur Windows récents). |

---

**Auteur** : Percya
*Simplifiez vos installations.*
