# ============================================================
# BLOCK DROPBOX - Migration SharePoint
# NinjaOne | Run As: SYSTEM
# ============================================================

$ruleName = "BLOCK - Dropbox (Migration SP)"
$errors   = 0

# ── 1. Collecte des chemins Dropbox ──────────────────────────
$paths = [System.Collections.Generic.List[string]]::new()

# Scan tous les profils users (couvre 99% des installs Dropbox per-user)
Get-ChildItem "C:\Users\*\AppData\Local\Dropbox\client\Dropbox.exe" `
    -ErrorAction SilentlyContinue | ForEach-Object { $paths.Add($_.FullName) }

# Chemins système (install machine-wide, rare mais possible)
@(
    "$env:PROGRAMFILES\Dropbox\Client\Dropbox.exe",
    "${env:PROGRAMFILES(X86)}\Dropbox\Client\Dropbox.exe"
) | ForEach-Object {
    if ((Test-Path $_) -and ($_ -notin $paths)) { $paths.Add($_) }
}

# Process actif avec path non standard
Get-Process "Dropbox" -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.Path -and ($_.Path -notin $paths)) { $paths.Add($_.Path) }
}

if ($paths.Count -eq 0) {
    Write-Output "[INFO] Dropbox non détecté sur cette machine."
} else {
    Write-Output "[INFO] $($paths.Count) chemin(s) Dropbox trouvé(s)."
}

# ── 2. Règle Firewall ─────────────────────────────────────────
# Purge les règles existantes pour éviter les doublons
Remove-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue

foreach ($p in $paths) {
    try {
        New-NetFirewallRule `
            -DisplayName $ruleName `
            -Direction   Outbound `
            -Program     $p `
            -Action      Block `
            -Profile     Any `
            -Enabled     True | Out-Null
        Write-Output "[OK] Firewall bloqué : $p"
    } catch {
        Write-Output "[ERR] Firewall échec pour $p >> $_"
        $errors++
    }
}

# ── 3. Kill process ───────────────────────────────────────────
Stop-Process -Name "Dropbox" -Force -ErrorAction SilentlyContinue
Write-Output "[OK] Process Dropbox arrêté (si actif)."

# ── 4. Autostart - profils actuellement connectés ────────────
Get-ChildItem "Registry::HKEY_USERS" -ErrorAction SilentlyContinue |
    Where-Object { $_.PSChildName -match "^S-1-5-21" } |
    ForEach-Object {
        $key = "Registry::HKEY_USERS\$($_.PSChildName)\Software\Microsoft\Windows\CurrentVersion\Run"
        if (Test-Path $key) {
            $prop = Get-ItemProperty $key -ErrorAction SilentlyContinue
            if ($prop.Dropbox) {
                Remove-ItemProperty $key -Name "Dropbox" -ErrorAction SilentlyContinue
                Write-Output "[OK] Autostart supprimé (user connecté - SID : $($_.PSChildName))"
            }
        }
    }

# ── 5. Autostart - profils déconnectés (chargement hive temp) ─
$loadedSIDs = (Get-ChildItem "Registry::HKEY_USERS" -ErrorAction SilentlyContinue |
    Where-Object { $_.PSChildName -match "^S-1-5-21" }).PSChildName

Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList" |
    Where-Object { $_.PSChildName -match "^S-1-5-21" -and $_.PSChildName -notin $loadedSIDs } |
    ForEach-Object {
        $profilePath = (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).ProfileImagePath
        if (-not $profilePath) { return }

        $ntuser = Join-Path $profilePath "NTUSER.DAT"
        if (-not (Test-Path $ntuser)) { return }

        $hiveAlias = "TempHive_DropboxBlock"
        reg load "HKU\$hiveAlias" $ntuser 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { return }

        $runKey = "Registry::HKEY_USERS\$hiveAlias\Software\Microsoft\Windows\CurrentVersion\Run"
        if (Test-Path $runKey) {
            $prop = Get-ItemProperty $runKey -ErrorAction SilentlyContinue
            if ($prop.Dropbox) {
                Remove-ItemProperty $runKey -Name "Dropbox" -ErrorAction SilentlyContinue
                Write-Output "[OK] Autostart supprimé (profil déconnecté : $profilePath)"
            }
        }

        [GC]::Collect()
        Start-Sleep -Milliseconds 300
        reg unload "HKU\$hiveAlias" 2>&1 | Out-Null
    }

# ── Résumé ────────────────────────────────────────────────────
Write-Output "──────────────────────────────────────"
if ($errors -gt 0) {
    Write-Output "[WARN] Terminé avec $errors erreur(s) - vérifier les logs."
    exit 1
} else {
    Write-Output "[SUCCESS] Dropbox bloqué avec succès."
    exit 0
}
