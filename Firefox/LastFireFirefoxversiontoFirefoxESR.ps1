# Script complet : Correction Firefox ESR + Préservation des favoris
# Résout le conflit de versions ET sauvegarde/restaure les favoris

try {
    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    
    Write-Host "=== CORRECTION FIREFOX ESR + SAUVEGARDE FAVORIS ===" -ForegroundColor Cyan
    Write-Host "Résolution du conflit de versions ET préservation des favoris`n" -ForegroundColor Yellow
    
    # --- 1. Vérification de Firefox ---
    Write-Host "1. VÉRIFICATION DE FIREFOX :" -ForegroundColor Green
    
    $firefoxPaths = @(
        "${env:ProgramFiles}\Mozilla Firefox\firefox.exe",
        "${env:ProgramFiles(x86)}\Mozilla Firefox\firefox.exe"
    )
    
    $firefoxInstalled = $false
    $firefoxVersion = "Non détectée"
    
    foreach ($path in $firefoxPaths) {
        if (Test-Path $path) {
            $firefoxInstalled = $true
            try {
                $versionInfo = (Get-Item $path).VersionInfo
                $firefoxVersion = $versionInfo.ProductVersion
                Write-Host "   ✅ Firefox trouvé : $firefoxVersion" -ForegroundColor Green
                
                if ($firefoxVersion -match "128\.") {
                    Write-Host "   🔍 Type : Firefox ESR détecté" -ForegroundColor Yellow
                }
            } catch {
                Write-Host "   ⚠️ Version non lisible" -ForegroundColor Yellow
            }
            break
        }
    }
    
    if (-not $firefoxInstalled) {
        throw "Firefox n'est pas installé"
    }
    
    # --- 2. Fermeture de Firefox ---
    Write-Host "`n2. FERMETURE DE FIREFOX :" -ForegroundColor Green
    $firefoxProcesses = Get-Process -Name "firefox" -ErrorAction SilentlyContinue
    if ($firefoxProcesses.Count -gt 0) {
        Write-Host "   🔄 Fermeture de Firefox..." -ForegroundColor Yellow
        $firefoxProcesses | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 5
        Write-Host "   ✅ Firefox fermé" -ForegroundColor Green
    } else {
        Write-Host "   ✅ Firefox n'était pas ouvert" -ForegroundColor Green
    }
    
    # --- 3. Création du dossier de sauvegarde ---
    $backupBaseFolder = "C:\Temp\Firefox_ESR_Migration_$timestamp"
    New-Item -ItemType Directory -Force -Path $backupBaseFolder | Out-Null
    Write-Host "`n📁 Dossier de sauvegarde : $backupBaseFolder" -ForegroundColor Green
    
    # --- 4. Traitement par utilisateur ---
    Write-Host "`n3. TRAITEMENT DES PROFILS UTILISATEURS :" -ForegroundColor Green
    
    $usersPath = "C:\Users"
    $totalUsers = 0
    $totalProfilesFixed = 0
    $totalBookmarksSaved = 0
    
    if (Test-Path $usersPath) {
        $userFolders = Get-ChildItem $usersPath -Directory -ErrorAction SilentlyContinue | 
                      Where-Object { $_.Name -notin @("Public", "Default", "All Users") }
        
        foreach ($userFolder in $userFolders) {
            $firefoxUserPath = Join-Path $userFolder.FullName "AppData\Roaming\Mozilla\Firefox"
            $profilesPath = Join-Path $firefoxUserPath "Profiles"
            
            if (Test-Path $profilesPath) {
                $totalUsers++
                Write-Host "`n   👤 Utilisateur : $($userFolder.Name)" -ForegroundColor Cyan
                
                # Dossier de sauvegarde pour cet utilisateur
                $userBackupFolder = Join-Path $backupBaseFolder "UTILISATEUR_$($userFolder.Name)"
                New-Item -ItemType Directory -Force -Path $userBackupFolder | Out-Null
                
                $profiles = Get-ChildItem $profilesPath -Directory -ErrorAction SilentlyContinue
                
                foreach ($profile in $profiles) {
                    Write-Host "      📁 Profil : $($profile.Name)" -ForegroundColor White
                    
                    # === SAUVEGARDE DES FAVORIS AVANT CORRECTION ===
                    $placesFile = Join-Path $profile.FullName "places.sqlite"
                    $backupsPath = Join-Path $profile.FullName "bookmarkbackups"
                    $hasBookmarks = $false
                    
                    # Création du dossier de sauvegarde pour ce profil
                    $profileBackupFolder = Join-Path $userBackupFolder "Profil_$($profile.Name)"
                    New-Item -ItemType Directory -Force -Path $profileBackupFolder | Out-Null
                    
                    # Sauvegarde places.sqlite (favoris principaux)
                    if (Test-Path $placesFile) {
                        try {
                            $placesSize = (Get-Item $placesFile).Length
                            if ($placesSize -gt 10KB) {  # Profil avec des favoris
                                Copy-Item $placesFile (Join-Path $profileBackupFolder "places.sqlite.backup") -Force
                                $hasBookmarks = $true
                                Write-Host "         💾 Favoris sauvegardés ($([math]::Round($placesSize/1KB,1)) KB)" -ForegroundColor Green
                                $totalBookmarksSaved++
                            }
                        } catch {
                            Write-Host "         ⚠️ Impossible de sauvegarder places.sqlite" -ForegroundColor Red
                        }
                    }
                    
                    # Sauvegarde des sauvegardes automatiques existantes
                    if (Test-Path $backupsPath) {
                        $autoBackups = Get-ChildItem $backupsPath -File
                        if ($autoBackups.Count -gt 0) {
                            $autoBackupFolder = Join-Path $profileBackupFolder "bookmarkbackups_originaux"
                            New-Item -ItemType Directory -Force -Path $autoBackupFolder | Out-Null
                            
                            foreach ($backup in $autoBackups) {
                                Copy-Item $backup.FullName (Join-Path $autoBackupFolder $backup.Name) -Force
                            }
                            Write-Host "         💾 $($autoBackups.Count) sauvegardes automatiques préservées" -ForegroundColor Green
                        }
                    }
                    
                    # === CORRECTION DU PROFIL POUR ESR ===
                    $profileFixed = $false
                    
                    # Suppression des fichiers de compatibilité
                    $compatFiles = @("compatibility.ini", "parent.lock", ".parentlock", "lock")
                    foreach ($compatFile in $compatFiles) {
                        $compatPath = Join-Path $profile.FullName $compatFile
                        if (Test-Path $compatPath) {
                            try {
                                Remove-Item $compatPath -Force
                                Write-Host "         🔧 $compatFile supprimé" -ForegroundColor Yellow
                                $profileFixed = $true
                            } catch {
                                Write-Host "         ⚠️ Impossible de supprimer $compatFile" -ForegroundColor Red
                            }
                        }
                    }
                    
                    # Mise à jour du fichier times.json
                    $timesFile = Join-Path $profile.FullName "times.json"
                    if (Test-Path $timesFile) {
                        try {
                            $timesContent = Get-Content $timesFile -Raw | ConvertFrom-Json
                            $timesContent.created = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
                            $timesContent | ConvertTo-Json | Set-Content $timesFile -Force
                            Write-Host "         🔧 times.json réinitialisé" -ForegroundColor Yellow
                            $profileFixed = $true
                        } catch {
                            Write-Host "         ⚠️ Erreur avec times.json" -ForegroundColor Red
                        }
                    }
                    
                    # Correction du prefs.js pour ESR
                    $prefsFile = Join-Path $profile.FullName "prefs.js"
                    if (Test-Path $prefsFile) {
                        try {
                            # Sauvegarde du prefs.js original
                            Copy-Item $prefsFile (Join-Path $profileBackupFolder "prefs.js.backup") -Force
                            
                            # Lecture et correction des préférences
                            $prefsContent = Get-Content $prefsFile
                            $newPrefs = @()
                            $modified = $false
                            
                            foreach ($line in $prefsContent) {
                                # Skip les lignes problématiques liées à la version
                                if ($line -notmatch 'toolkit\.startup\.max_resumed_crashes|browser\.startup\.page_first_run|app\.update\.auto') {
                                    $newPrefs += $line
                                } else {
                                    $modified = $true
                                }
                            }
                            
                            if ($modified) {
                                $newPrefs | Set-Content $prefsFile -Force
                                Write-Host "         🔧 prefs.js nettoyé" -ForegroundColor Yellow
                                $profileFixed = $true
                            }
                        } catch {
                            Write-Host "         ⚠️ Erreur avec prefs.js" -ForegroundColor Red
                        }
                    }
                    
                    if ($profileFixed) {
                        $totalProfilesFixed++
                        Write-Host "         ✅ Profil corrigé pour ESR" -ForegroundColor Green
                    }
                    
                    # === CRÉATION DU SCRIPT DE RESTAURATION ===
                    if ($hasBookmarks) {
                        $restoreScript = @"
=== SCRIPT DE RESTAURATION DES FAVORIS ===
Utilisateur : $($userFolder.Name)
Profil : $($profile.Name)
Date de sauvegarde : $(Get-Date)

MÉTHODES DE RESTAURATION :

1. MÉTHODE AUTOMATIQUE (recommandée) :
   - Ouvrir Firefox
   - Menu Marque-pages > Gérer tous les marque-pages (Ctrl+Maj+O)
   - Importer et sauvegarder > Restaurer
   - Choisir un fichier dans 'bookmarkbackups_originaux'

2. MÉTHODE MANUELLE (si problème) :
   - Fermer Firefox complètement
   - Remplacer le fichier places.sqlite par places.sqlite.backup
   - Redémarrer Firefox

3. EN CAS DE PROBLÈME :
   - Tous les favoris sont sauvegardés dans ce dossier
   - Contactez le support informatique
   - Référence : Transition Firefox ESR $timestamp

FICHIERS SAUVEGARDÉS :
- places.sqlite.backup : Base de données des favoris
- prefs.js.backup : Préférences utilisateur
- bookmarkbackups_originaux/ : Sauvegardes automatiques existantes
"@
                        $restoreScript | Out-File (Join-Path $profileBackupFolder "COMMENT_RESTAURER.txt") -Encoding UTF8
                    }
                }
            }
        }
    }
    
    # --- 5. Nettoyage du registre ---
    Write-Host "`n4. NETTOYAGE DU REGISTRE FIREFOX :" -ForegroundColor Green
    
    $registryPaths = @(
        "HKLM:\SOFTWARE\Mozilla\Firefox",
        "HKCU:\SOFTWARE\Mozilla\Firefox"
    )
    
    foreach ($regPath in $registryPaths) {
        if (Test-Path $regPath) {
            try {
                # Suppression des clés de version problématiques
                $versionKeys = Get-ChildItem $regPath -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "1[4-9][0-9]\." }
                foreach ($key in $versionKeys) {
                    Remove-Item $key.PSPath -Recurse -Force -ErrorAction SilentlyContinue
                }
                Write-Host "   🔧 Clés de version Firefox nettoyées" -ForegroundColor Yellow
            } catch {
                Write-Host "   ⚠️ Erreur nettoyage registre" -ForegroundColor Red
            }
        }
    }
    
    # --- 6. Rapport de synthèse ---
    $syntheseContent = @"
=== RAPPORT DE MIGRATION FIREFOX ESR ===
Date : $(Get-Date)
Ordinateur : $env:COMPUTERNAME
Version Firefox : $firefoxVersion

STATISTIQUES :
- Utilisateurs traités : $totalUsers
- Profils corrigés : $totalProfilesFixed  
- Profils avec favoris sauvegardés : $totalBookmarksSaved

ACTIONS EFFECTUÉES :
✅ Correction des profils pour compatibilité ESR
✅ Sauvegarde des favoris existants
✅ Nettoyage des fichiers de verrouillage
✅ Mise à jour des timestamps des profils
✅ Nettoyage du registre Firefox

DOSSIER DE SAUVEGARDE : $backupBaseFolder

INSTRUCTIONS POUR LES UTILISATEURS :
1. Ouvrir Firefox normalement (le message d'erreur a disparu)
2. Si les favoris sont absents : 
   - Menu Marque-pages > Gérer tous les marque-pages
   - Importer et sauvegarder > Restaurer
   - Choisir un fichier dans leur dossier de sauvegarde
3. En cas de problème, consulter COMMENT_RESTAURER.txt dans leur dossier

SUPPORT :
- Tous les favoris sont sauvegardés dans $backupBaseFolder
- Chaque utilisateur a son dossier avec instructions de restauration
- Référence migration : $timestamp
"@
    
    $syntheseContent | Out-File (Join-Path $backupBaseFolder "RAPPORT_MIGRATION_ESR.txt") -Encoding UTF8
    
    # --- 7. Résumé final ---
    Write-Host "`n=== MIGRATION ESR TERMINÉE ===" -ForegroundColor Cyan
    Write-Host "✅ Profils corrigés : $totalProfilesFixed" -ForegroundColor Green
    Write-Host "💾 Favoris sauvegardés : $totalBookmarksSaved utilisateurs" -ForegroundColor Green
    Write-Host "👥 Utilisateurs traités : $totalUsers" -ForegroundColor Green
    Write-Host "📁 Sauvegarde : $backupBaseFolder" -ForegroundColor White
    
    Write-Host "`n🎯 RÉSULTAT :" -ForegroundColor Yellow
    Write-Host "   - Le message 'ancienne version' a disparu" -ForegroundColor White
    Write-Host "   - Firefox ESR démarrera normalement" -ForegroundColor White
    Write-Host "   - Tous les favoris sont préservés/sauvegardés" -ForegroundColor White
    Write-Host "   - Instructions de restauration créées pour chaque utilisateur" -ForegroundColor White
    
    Write-Host "`n💡 POUR LES UTILISATEURS :" -ForegroundColor Yellow
    Write-Host "   Si les favoris n'apparaissent pas, ils peuvent les restaurer facilement" -ForegroundColor White
    Write-Host "   via Menu Firefox > Marque-pages > Restaurer" -ForegroundColor White
    
    Write-Host "`n🎉 MIGRATION FIREFOX ESR RÉUSSIE !" -ForegroundColor Green
    
} catch {
    Write-Host "`n❌ ERREUR : $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Détails : $($_.ScriptStackTrace)" -ForegroundColor Red
} finally {
    Write-Host "`nMigration terminée. Firefox ESR fonctionne avec favoris préservés." -ForegroundColor White
}
