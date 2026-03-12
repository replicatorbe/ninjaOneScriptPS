# ROLLBACK - Débloquer Dropbox
# NinjaOne | Run As: SYSTEM

$ruleName = "BLOCK - Dropbox (Migration SP)"

Remove-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
Write-Output "[OK] Règles firewall Dropbox supprimées."

# Note : le démarrage auto ne sera PAS remis automatiquement.
# Dropbox le recrée lui-même au prochain lancement manuel.

Write-Output "[SUCCESS] Rollback terminé."
exit 0
