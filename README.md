# ninjaOneScriptPS

Bibliothèque de scripts PowerShell utilisés en production sur la plateforme
**NinjaOne RMM** pour l'administration à distance d'un parc de postes Windows.

## Contexte

[NinjaOne](https://www.ninjaone.com/) est une plateforme RMM (*Remote Monitoring
& Management*) qui permet, depuis une console web centralisée, d'inventorier,
superviser et exécuter des scripts sur des endpoints Windows / macOS / Linux.
Les scripts contenus dans ce dépôt sont conçus pour être déployés via
**Administration → Library → Automation → Scripts**, puis exécutés
manuellement ou via une *policy* sur les postes ciblés.

Chaque script est écrit en PowerShell 5.1+ (compatible Windows 10 / 11 et
Windows Server 2016+). Sauf mention contraire, ils sont pensés pour tourner
sous le contexte **SYSTEM** — c'est le mode d'exécution par défaut de
NinjaOne pour les scripts administratifs.

## Structure du dépôt

```
.
├── Dropbox/
│   ├── block.ps1                          # Blocage complet de Dropbox (firewall + autostart)
│   └── unblock.ps1                        # Rollback des règles firewall Dropbox
├── Firefox/
│   ├── SaveFavorisFirefox.ps1             # Sauvegarde des favoris Firefox par utilisateur
│   └── LastFireFirefoxversiontoFirefoxESR.ps1  # Migration Firefox stable → ESR
├── FirefoxESR                              # Doublon (sans extension) du script de migration ESR
├── Windows/
│   └── lockscreen_img                      # Déploiement d'un fond d'écran de verrouillage entreprise
└── questionnaireAPIReturnResponse          # Notification interactive utilisateur avec retour vers une API
```

Note : plusieurs fichiers sont enregistrés sans extension `.ps1` (héritage du
copier-coller depuis la console NinjaOne, qui ne demande pas d'extension).
Le contenu reste du PowerShell valide.

## Scripts inclus

### `Dropbox/block.ps1`

**But** : bloquer entièrement Dropbox sur un poste dans le cadre d'une
migration vers SharePoint.
**Cible** : postes Windows (workstations).
**Contexte d'exécution** : SYSTEM.
**Paramètres** : aucun.
**Effets** :
- Détecte tous les binaires `Dropbox.exe` (installations *per-user* dans
  `C:\Users\*\AppData\Local\Dropbox`, installations *machine-wide* dans
  `Program Files`, et processus actifs à chemin non standard).
- Crée une règle **Windows Defender Firewall** sortante `Block` par binaire
  détecté (nom de règle : `BLOCK - Dropbox (Migration SP)`).
- Termine le processus `Dropbox` s'il est actif.
- Supprime l'entrée `Dropbox` de `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`
  pour tous les profils utilisateur (y compris les profils déconnectés, via
  chargement temporaire de leur ruche `NTUSER.DAT`).
- Retourne un code de sortie non nul en cas d'erreur (compatible avec la
  gestion des statuts dans NinjaOne).

### `Dropbox/unblock.ps1`

**But** : rollback du script précédent.
**Cible** : postes Windows.
**Contexte d'exécution** : SYSTEM.
**Paramètres** : aucun.
**Effets** :
- Supprime les règles firewall créées par `block.ps1`.
- N'inscrit **pas** le démarrage automatique de Dropbox — le client Dropbox
  le recrée seul au prochain lancement manuel par l'utilisateur.

### `Firefox/SaveFavorisFirefox.ps1`

**But** : sauvegarde manuelle et détaillée des favoris Firefox de tous les
utilisateurs présents sur un poste, avec production d'un rapport lisible et
d'un guide de restauration.
**Cible** : postes Windows multi-utilisateurs.
**Contexte d'exécution** : SYSTEM (nécessaire pour lire les profils de tous
les utilisateurs).
**Paramètres** : aucun.
**Effets** :
- Parcourt `C:\Users\*\AppData\Roaming\Mozilla\Firefox\Profiles`.
- Copie `places.sqlite`, `favicons.sqlite`, `prefs.js` et les
  `bookmarkbackups/*.jsonlz4` de chaque profil vers un dossier horodaté sur
  le bureau du premier utilisateur trouvé (fallback : `C:\Temp`).
- Classe automatiquement chaque profil par statut (`ACTIF` / `UTILISE` /
  `VIDE`) selon la taille de `places.sqlite`.
- Génère `INFOS_PROFIL.txt` par profil et `GUIDE_RESTAURATION.txt` global.
- Ouvre le dossier dans l'Explorateur à la fin.

Remarque : le script contient un `Read-Host` en fin d'exécution — il attend
une pression sur Entrée avant de rendre la main. Utile en exécution
interactive locale, à surveiller si on l'appelle depuis un pipeline
totalement non-interactif.

### `Firefox/LastFireFirefoxversiontoFirefoxESR.ps1`

**But** : résoudre le conflit qui apparaît quand on remplace une installation
Firefox stable (ex. 140.x) par Firefox **ESR** (ex. 128.x) — Firefox refuse
alors de démarrer avec un profil créé par une version plus récente
(« Vous avez démarré une ancienne version de Firefox »).
**Cible** : postes Windows sur lesquels on migre de Firefox stable vers
Firefox ESR.
**Contexte d'exécution** : SYSTEM.
**Paramètres** : aucun.
**Effets** :
1. Détecte la version installée de Firefox.
2. Termine tous les processus `firefox.exe` en cours.
3. Pour chaque profil de chaque utilisateur :
   - Sauvegarde `places.sqlite`, `prefs.js` et le dossier `bookmarkbackups`
     vers `C:\Temp\Firefox_ESR_Migration_<timestamp>`.
   - Supprime les fichiers de verrouillage / compatibilité :
     `compatibility.ini`, `parent.lock`, `.parentlock`, `lock`.
   - Réinitialise `times.json` (timestamp de création du profil).
   - Nettoie dans `prefs.js` les préférences qui bloquent le downgrade
     (`toolkit.startup.max_resumed_crashes`, `browser.startup.page_first_run`,
     `app.update.auto`).
4. Purge du registre les clés `HKLM\SOFTWARE\Mozilla\Firefox\*` et
   `HKCU\SOFTWARE\Mozilla\Firefox\*` dont le nom correspond à une version
   140-199 (regex `1[4-9][0-9]\.`).
5. Produit un rapport `RAPPORT_MIGRATION_ESR.txt` et un fichier
   `COMMENT_RESTAURER.txt` par profil qui contenait des favoris.

Attention : ce script **modifie irréversiblement** `prefs.js` et le registre
Firefox. Une sauvegarde complète est effectuée en amont, mais toute
exécution sur un poste doit être précédée d'un test.

### `FirefoxESR` (racine)

Copie identique du script `Firefox/LastFireFirefoxversiontoFirefoxESR.ps1`,
conservée sans extension à la racine pour import direct dans NinjaOne. Les
deux fichiers ont exactement le même contenu.

### `Windows/lockscreen_img`

**But** : imposer sur tous les postes un fond d'écran de verrouillage
entreprise unifié, en désactivant *Windows Spotlight*.
**Cible** : postes Windows 10 / 11 (Pro, Enterprise ou Éducation — la
politique `PersonalizationCSP` n'est pas honorée par les éditions Home).
**Contexte d'exécution** : Administrateur (`#Requires -RunAsAdministrator`).
**Paramètres** :
- `-ImageUrl <string>` : URL HTTP(S) publique de l'image à télécharger.
  Valeur par défaut du dépôt : `https://url/tools/screen.png` (placeholder
  à remplacer avant déploiement réel).
- `-LogPath <string>` : dossier où déposer le transcript. Défaut : `$env:TEMP`.
**Effets** :
- Télécharge l'image et la place dans `C:\Windows\System32\LockScreen.jpg`.
- Écrit sous
  `HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent` les DWORD :
  `DisableWindowsSpotlightFeatures`, `DisableWindowsSpotlightOnActionCenter`,
  `DisableWindowsSpotlightOnSettings`,
  `DisableWindowsSpotlightWindowsWelcomeExperience`, `DisableSoftLanding`.
- Configure sous
  `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP` :
  `LockScreenImageStatus=1`, `LockScreenImagePath`, `LockScreenImageUrl`.
- Pour chaque utilisateur (charge la ruche `NTUSER.DAT` si le profil n'est
  pas chargé) : écrit dans `ContentDeliveryManager` les DWORD
  `RotatingLockScreenEnabled=0`, `RotatingLockScreenOverlayEnabled=0`, etc.
- Exécute `gpupdate /force` et redémarre les services `Themes` et `UxSms`.

### `questionnaireAPIReturnResponse`

**But** : afficher une popup de notification native (WinForms) sur la session
de tous les utilisateurs connectés, avec possibilité d'y joindre un
formulaire de réponse renvoyé à une API HTTP interne.
**Cible** : postes Windows avec au moins une session utilisateur active.
**Contexte d'exécution** : SYSTEM (le script bascule ensuite vers le
contexte utilisateur via une tâche planifiée avec `LogonType Interactive`).
**Paramètres** (passés par NinjaOne au format `{key:value,...}`) :
- `title` : titre de la notification.
- `message` : corps du message.
- `token` : jeton opaque renvoyé à l'API avec la réponse (identifie le ticket).
- `showForm` : `true` pour afficher un champ de saisie et un bouton
  d'envoi, `false` pour une simple notification.
**Effets** :
- Nettoie les anciennes tâches planifiées orphelines (`ClientNotif*`) plus
  vieilles que 10 minutes, ainsi que les scripts `notify_*.ps1` et
  `notify_*.vbs` de plus d'une heure dans `C:\ClientIT\Notifications`.
- Récupère la liste des utilisateurs connectés via `quser`.
- Pour chaque utilisateur, dépose un script `.ps1` (l'UI WinForms complète)
  et un lanceur `.vbs` (pour supprimer la fenêtre PowerShell), puis crée
  une tâche planifiée qui exécute `wscript.exe` sous l'identité de
  l'utilisateur — c'est la méthode standard pour afficher une UI depuis un
  script SYSTEM.
- Si `showForm=true` : la réponse est envoyée en `POST
  application/x-www-form-urlencoded` vers `<ApiBaseUrl>?token=<token>` avec
  `response=<texte>` dans le corps. L'URL est configurable dans le script.
- Nettoie les tâches planifiées et fichiers temporaires 15 secondes après
  le lancement.

Remarque : la configuration en tête de script (`ScriptFolder`, `TaskPrefix`,
`ApiBaseUrl`) contient des références à un contexte de déploiement client
(chemins et libellés génériques `Client*`). Ces valeurs sont à adapter à votre
environnement avant réutilisation.

## Utilisation dans NinjaOne

1. Console NinjaOne → **Administration → Library → Automation**.
2. **Add → Script** → langage : **PowerShell**.
3. Copier le contenu du fichier `.ps1` souhaité dans l'éditeur.
4. Sélectionner le **Run As** approprié (SYSTEM pour la majorité, ou
   *Current logged on user* selon le cas).
5. Pour les scripts qui acceptent des arguments (ex.
   `questionnaireAPIReturnResponse`), activer *Preset Parameters* et
   passer les valeurs au format attendu par le script.
6. Assigner le script à une *policy* ou déclencher un *Run script* ponctuel
   sur un ou plusieurs *devices*.

## Sécurité et bonnes pratiques observées

- Aucun credential, aucun token, aucune clé d'API n'est stocké en clair
  dans les scripts de ce dépôt.
- Les URL apparaissant dans le code (`https://url/...`) sont des
  placeholders génériques à remplacer avant tout déploiement.
- Les scripts qui manipulent des ruches utilisateurs (`NTUSER.DAT`)
  utilisent systématiquement `reg load` / `reg unload` avec un alias dédié
  et forcent `[GC]::Collect()` avant unload pour éviter les handles
  résiduels.
- Les règles firewall créées portent un nom explicite et unique, ce qui
  permet un rollback fiable (`Remove-NetFirewallRule -DisplayName ...`).
- Les scripts qui modifient des fichiers utilisateurs (Firefox) réalisent
  systématiquement une sauvegarde préalable horodatée avant toute
  modification.
- Les codes de sortie (`exit 0` / `exit 1`) sont utilisés là où c'est
  pertinent pour remonter le statut à NinjaOne.

## Prérequis

- PowerShell 5.1 ou supérieur (fourni par défaut sur Windows 10 / 11 et
  Windows Server 2016+).
- Modules `NetSecurity` (pour les scripts firewall) et `ScheduledTasks`
  (pour la création de tâches planifiées) — fournis par Windows.
- Droits **SYSTEM** ou **Administrateur** selon les scripts (voir chaque
  fiche ci-dessus).

## Licence

Distribué sous licence MIT — voir le fichier [`LICENSE`](./LICENSE).

## Auteur

Jérôme Fafchamps — [@replicatorbe](https://github.com/replicatorbe)
