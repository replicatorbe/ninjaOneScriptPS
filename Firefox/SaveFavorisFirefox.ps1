# Script de sauvegarde Firefox avec identification des utilisateurs
try {
    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    
    Write-Host "=== SAUVEGARDE FIREFOX AVEC IDENTIFICATION ===" -ForegroundColor Cyan
    Write-Host "Analyse des profils par utilisateur...`n" -ForegroundColor Yellow
    
    # --- Recherche organisée par utilisateur ---
    $userProfiles = @()
    $usersPath = "C:\Users"
    
    if (Test-Path $usersPath) {
        $userFolders = Get-ChildItem $usersPath -Directory -ErrorAction SilentlyContinue | 
                      Where-Object { $_.Name -notin @("Public", "Default", "All Users") }
        
        foreach ($userFolder in $userFolders) {
            $firefoxPath = Join-Path $userFolder.FullName "AppData\Roaming\Mozilla\Firefox\Profiles"
            if (Test-Path $firefoxPath) {
                $profiles = Get-ChildItem $firefoxPath -Directory -ErrorAction SilentlyContinue
                
                if ($profiles.Count -gt 0) {
                    Write-Host "👤 Utilisateur : $($userFolder.Name)" -ForegroundColor Green
                    
                    foreach ($profile in $profiles) {
                        # Analyse du profil pour obtenir des infos
                        $placesFile = Join-Path $profile.FullName "places.sqlite"
                        $prefsFile = Join-Path $profile.FullName "prefs.js"
                        $backupsPath = Join-Path $profile.FullName "bookmarkbackups"
                        
                        $profileInfo = @{
                            UserName = $userFolder.Name
                            ProfileName = $profile.Name
                            ProfilePath = $profile.FullName
                            LastUsed = $profile.LastWriteTime
                            HasBookmarks = (Test-Path $placesFile)
                            HasBackups = (Test-Path $backupsPath)
                            BookmarksSize = if (Test-Path $placesFile) { (Get-Item $placesFile).Length } else { 0 }
                            BackupCount = if (Test-Path $backupsPath) { (Get-ChildItem $backupsPath -File).Count } else { 0 }
                        }
                        
                        # Essaie de déterminer si c'est le profil principal
                        $isDefault = $profile.Name -like "*default*"
                        $isRecent = $profile.LastWriteTime -gt (Get-Date).AddDays(-30)
                        
                        $status = if ($profileInfo.BookmarksSize -gt 50KB -and $isRecent) { "🟢 ACTIF" }
                                 elseif ($profileInfo.BookmarksSize -gt 10KB) { "🟡 UTILISÉ" }
                                 else { "⚪ VIDE/ANCIEN" }
                        
                        Write-Host "    📁 $($profile.Name) $status" -ForegroundColor White
                        Write-Host "       Dernière utilisation: $($profile.LastWriteTime.ToString('dd/MM/yyyy HH:mm'))" -ForegroundColor Gray
                        Write-Host "       Favoris: $([math]::Round($profileInfo.BookmarksSize / 1KB, 1)) KB | Sauvegardes: $($profileInfo.BackupCount)" -ForegroundColor Gray
                        
                        $userProfiles += $profileInfo
                    }
                    Write-Host ""
                }
            }
        }
    }
    
    if ($userProfiles.Count -eq 0) {
        throw "Aucun profil Firefox trouvé sur ce système"
    }
    
    # --- Détermination du dossier de destination ---
    $destFolder = $null
    $realUsers = Get-ChildItem "C:\Users" -Directory | Where-Object { 
        $_.Name -notin @("Public", "Default", "All Users") -and 
        (Test-Path (Join-Path $_.FullName "Desktop"))
    }
    
    if ($realUsers.Count -gt 0) {
        $firstUser = $realUsers[0]
        $destFolder = Join-Path $firstUser.FullName "Desktop\Firefox_Favoris_PAR_UTILISATEUR_$timestamp"
    } else {
        $destFolder = "C:\Temp\Firefox_Favoris_PAR_UTILISATEUR_$timestamp"
    }
    
    New-Item -ItemType Directory -Force -Path $destFolder | Out-Null
    Write-Host "🎯 Dossier de sauvegarde : $destFolder`n" -ForegroundColor Green
    
    $totalFiles = 0
    
    # --- Sauvegarde organisée par utilisateur ---
    foreach ($userGroup in ($userProfiles | Group-Object UserName)) {
        $userName = $userGroup.Name
        $profiles = $userGroup.Group
        
        Write-Host "💾 Sauvegarde pour : $userName" -ForegroundColor Cyan
        
        # Dossier par utilisateur
        $userBackupFolder = Join-Path $destFolder "UTILISATEUR_$userName"
        New-Item -ItemType Directory -Force -Path $userBackupFolder | Out-Null
        
        foreach ($profileInfo in $profiles) {
            $profile = Get-Item $profileInfo.ProfilePath
            
            # Nom de dossier descriptif
            $profileType = if ($profile.Name -like "*default-release*") { "Principal_Actuel" }
                          elseif ($profile.Name -like "*default*") { "Principal_Ancien" }
                          else { "Secondaire" }
            
            $status = if ($profileInfo.BookmarksSize -gt 50KB) { "ACTIF" }
                     elseif ($profileInfo.BookmarksSize -gt 10KB) { "UTILISE" }
                     else { "VIDE" }
            
            $profileBackupName = "${profileType}_${status}_$($profile.Name)"
            $profileBackup = Join-Path $userBackupFolder $profileBackupName
            New-Item -ItemType Directory -Force -Path $profileBackup | Out-Null
            
            Write-Host "    📂 $profileBackupName" -ForegroundColor Yellow
            
            # Sauvegarde des fichiers
            $savedFiles = @()
            
            # places.sqlite
            $placesFile = Join-Path $profile.FullName "places.sqlite"
            if (Test-Path $placesFile) {
                try {
                    Copy-Item $placesFile (Join-Path $profileBackup "places.sqlite") -Force
                    $size = [math]::Round((Get-Item $placesFile).Length / 1KB, 1)
                    $savedFiles += "places.sqlite ($size KB)"
                    $totalFiles++
                } catch {
                    Write-Host "        ⚠️ places.sqlite inaccessible" -ForegroundColor Red
                }
            }
            
            # Sauvegardes automatiques
            $backupsPath = Join-Path $profile.FullName "bookmarkbackups"
            if (Test-Path $backupsPath) {
                $backupFiles = Get-ChildItem $backupsPath -File | Sort-Object LastWriteTime -Descending
                if ($backupFiles.Count -gt 0) {
                    $autoBackupFolder = Join-Path $profileBackup "Sauvegardes_Automatiques"
                    New-Item -ItemType Directory -Force -Path $autoBackupFolder | Out-Null
                    
                    foreach ($file in $backupFiles) {
                        Copy-Item $file.FullName (Join-Path $autoBackupFolder $file.Name) -Force
                    }
                    $savedFiles += "$($backupFiles.Count) sauvegardes automatiques"
                    $totalFiles += $backupFiles.Count
                }
            }
            
            # Autres fichiers
            $otherFiles = @("favicons.sqlite", "prefs.js")
            foreach ($fileName in $otherFiles) {
                $filePath = Join-Path $profile.FullName $fileName
                if (Test-Path $filePath) {
                    try {
                        Copy-Item $filePath (Join-Path $profileBackup $fileName) -Force
                        $savedFiles += $fileName
                        $totalFiles++
                    } catch {
                        # Ignore silencieusement
                    }
                }
            }
            
            # Informations sur ce profil
            $profileInfoContent = @"
=== PROFIL FIREFOX ===
Utilisateur : $userName
Nom du profil : $($profile.Name)
Type : $profileType
Statut : $status
Dernière utilisation : $($profile.LastWriteTime.ToString('dd/MM/yyyy à HH:mm'))
Taille des favoris : $([math]::Round($profileInfo.BookmarksSize / 1KB, 1)) KB
Nombre de sauvegardes : $($profileInfo.BackupCount)

FICHIERS SAUVEGARDÉS :
$($savedFiles | ForEach-Object { "- $_" } | Out-String)

POUR RESTAURER CES FAVORIS :
1. Ouvrir Firefox avec le compte '$userName'
2. Menu Marque-pages > Gérer tous les marque-pages (Ctrl+Maj+O)
3. Importer et sauvegarder > Restaurer
4. Choisir un fichier du dossier 'Sauvegardes_Automatiques'
"@
            $profileInfoContent | Out-File (Join-Path $profileBackup "INFOS_PROFIL.txt") -Encoding UTF8
            
            Write-Host "        ✅ $($savedFiles.Count) fichiers sauvegardés" -ForegroundColor Green
        }
        Write-Host ""
    }
    
    # --- Rapport de synthèse ---
    $syntheseContent = @"
=== RAPPORT DE SAUVEGARDE FIREFOX ===
Date : $(Get-Date)
Ordinateur : $env:COMPUTERNAME
Total fichiers sauvegardés : $totalFiles

🎯 GUIDE DE RESTAURATION RAPIDE :

$($userProfiles | Group-Object UserName | ForEach-Object {
    $userName = $_.Name
    $userProfiles = $_.Group | Sort-Object BookmarksSize -Descending
    $mainProfile = $userProfiles[0]
    
    $recommendation = if ($mainProfile.BookmarksSize -gt 50KB) {
        "👤 $userName : UTILISATEUR ACTIF"
        "   📁 Profil recommandé : $($mainProfile.ProfileName)"
        "   📊 Favoris : $([math]::Round($mainProfile.BookmarksSize / 1KB, 1)) KB"
        "   🔄 Dossier à restaurer : UTILISATEUR_$userName\Principal_*"
    } else {
        "👤 $userName : Profil peu utilisé ($([math]::Round($mainProfile.BookmarksSize / 1KB, 1)) KB)"
    }
    
    $recommendation
    ""
} | Out-String)

📋 LÉGENDE :
- Principal_Actuel : Profil Firefox moderne (recommandé)
- Principal_Ancien : Ancien profil Firefox
- ACTIF : Plus de 50 KB de favoris (utilisateur régulier)
- UTILISE : 10-50 KB de favoris (utilisation occasionnelle)
- VIDE : Moins de 10 KB (peu ou pas utilisé)

🔧 MÉTHODES DE RESTAURATION :
1. SIMPLE : Firefox > Marque-pages > Restaurer > Choisir fichier .jsonlz4
2. COMPLÈTE : Remplacer places.sqlite (Firefox fermé)
"@
    
    $syntheseContent | Out-File (Join-Path $destFolder "GUIDE_RESTAURATION.txt") -Encoding UTF8
    
    # Résumé final
    Write-Host "=== SAUVEGARDE TERMINÉE ===" -ForegroundColor Cyan
    Write-Host "✅ $totalFiles fichiers sauvegardés" -ForegroundColor Green
    Write-Host "👥 $($userProfiles | Group-Object UserName | Measure-Object | Select-Object -ExpandProperty Count) utilisateurs traités" -ForegroundColor Green
    Write-Host "📁 Dossier : $destFolder" -ForegroundColor White
    Write-Host "`n📖 Consultez 'GUIDE_RESTAURATION.txt' pour savoir quoi restaurer pour chaque utilisateur !" -ForegroundColor Yellow
    
    # Ouverture du dossier
    try {
        Start-Process "explorer.exe" -ArgumentList $destFolder -ErrorAction SilentlyContinue
    } catch {
        Write-Host "Dossier créé : $destFolder" -ForegroundColor Green
    }
    
} catch {
    Write-Host "`n❌ ERREUR : $($_.Exception.Message)" -ForegroundColor Red
} finally {
    Write-Host "`nAppuyez sur Entrée pour fermer..." -ForegroundColor White
    Read-Host
}
