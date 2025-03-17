<#
.SYNOPSIS
    Script PowerShell pour installer et configurer l’agent Zabbix sur Windows

.DESCRIPTION
    - Télécharge le MSI de l’agent Zabbix
    - Installe en mode silencieux
    - Configure le fichier zabbix_agentd.conf
    - Démarre le service Zabbix Agent

.PARAMETER ZabbixServer
    Adresse (IP ou DNS) de votre serveur Zabbix.

.PARAMETER Hostname
    Nom d’hôte sous lequel cette machine sera vue dans Zabbix.

.EXAMPLE
    .\Install_ZabbixAgent.ps1 -ZabbixServer "192.168.1.56" -Hostname "WindowsClient"
#>

param(
    [string]$ZabbixServer = "192.168.1.56",
    [string]$Hostname = "WinAgent"
)

Write-Host "=== Installation de l'agent Zabbix sur Windows ===" -ForegroundColor Cyan

# 1) Définir l’URL de téléchargement du MSI (adapter la version si nécessaire)
#    Voir https://www.zabbix.com/download_agents pour la dernière version.
$ZabbixAgentUrl = "https://cdn.zabbix.com/zabbix/binaries/stable/6.0/6.0.18/zabbix_agent-6.0.18-windows-amd64-openssl.msi"
$TempMsi = "$env:TEMP\zabbix_agent.msi"

# Sécuriser les connexions TLS
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Write-Host "Téléchargement de l’agent Zabbix..." 
Invoke-WebRequest -Uri $ZabbixAgentUrl -OutFile $TempMsi -UseBasicParsing

if (!(Test-Path $TempMsi)) {
    Write-Host "Erreur : Impossible de télécharger l'agent Zabbix." -ForegroundColor Red
    exit 1
}

# 2) Installation du MSI en silencieux
Write-Host "Installation silencieuse de l'agent..."
Start-Process msiexec.exe -Wait -ArgumentList "/i `"$TempMsi`" /qn"

# 3) Modifier la configuration (par défaut : C:\Program Files\Zabbix Agent\zabbix_agentd.conf)
$ConfigFile = "C:\Program Files\Zabbix Agent\zabbix_agentd.conf"

if (!(Test-Path $ConfigFile)) {
    Write-Host "Fichier de configuration introuvable : $ConfigFile" -ForegroundColor Red
    exit 1
}

# Configurer la ligne Server=
(Get-Content $ConfigFile) |
    ForEach-Object { $_ -replace '^Server=.*', "Server=$ZabbixServer" } |
    ForEach-Object { $_ -replace '^ServerActive=.*', "ServerActive=$ZabbixServer" } |
    ForEach-Object { $_ -replace '^Hostname=.*', "Hostname=$Hostname" } |
    Set-Content $ConfigFile

# 4) Redémarrer et activer le service
Write-Host "Activation et démarrage du service Zabbix Agent..."
Start-Service "Zabbix Agent"
Set-Service "Zabbix Agent" -StartupType Automatic

Write-Host "✅ Agent Zabbix installé et configuré !" -ForegroundColor Green
Write-Host "    Serveur Zabbix  : $ZabbixServer"
Write-Host "    Hostname (agent): $Hostname"
Write-Host "=== Fin de l'installation de l'agent Zabbix ==="
