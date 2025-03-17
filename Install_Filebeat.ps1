<#
.SYNOPSIS
    Script PowerShell pour installer et configurer Filebeat sur Windows

.DESCRIPTION
    - Télécharge l’archive ZIP de Filebeat
    - Extrait dans C:\Program Files\Filebeat
    - Configure la sortie vers Elasticsearch ou Logstash
    - Installe et démarre le service Windows

.PARAMETER ElasticsearchHost
    Adresse de votre cluster Elasticsearch (par ex : 192.168.1.56:9200).

.PARAMETER LogstashHost
    Adresse de Logstash (par ex : 192.168.1.56:5044).

.PARAMETER UseLogstash
    Booléen pour choisir si on envoie les logs directement vers ES ou via Logstash.

.EXAMPLE
    .\Install_Filebeat.ps1 -ElasticsearchHost "192.168.1.56:9200" -UseLogstash $False
#>

param(
    [string]$ElasticsearchHost = "192.168.1.56:9200",
    [string]$LogstashHost = "192.168.1.56:5044",
    [bool]$UseLogstash = $false
)

Write-Host "=== Installation de Filebeat (ELK Agent) sur Windows ===" -ForegroundColor Cyan

# 1) Définir l’URL de téléchargement du ZIP (voir https://www.elastic.co/fr/downloads/beats/filebeat)
#    Exemple : version 7.17.14
$FilebeatVersion = "7.17.14"
$FilebeatUrl = "https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-$FilebeatVersion-windows-x86_64.zip"
$TempZip = "$env:TEMP\filebeat.zip"
$InstallPath = "C:\Program Files\Filebeat"

# Sécuriser les connexions TLS
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Write-Host "Téléchargement de Filebeat version $FilebeatVersion..."
Invoke-WebRequest -Uri $FilebeatUrl -OutFile $TempZip -UseBasicParsing

if (!(Test-Path $TempZip)) {
    Write-Host "Erreur : Impossible de télécharger l'archive Filebeat." -ForegroundColor Red
    exit 1
}

# 2) Extraire dans C:\Program Files\Filebeat
Write-Host "Extraction de l'archive Filebeat..."
Expand-Archive -Path $TempZip -DestinationPath $InstallPath -Force

# Filebeat peut se trouver dans un sous-dossier filebeat-x.x.x-windows-x86_64
# On vérifie et on déplace si nécessaire
$SubFolder = Join-Path $InstallPath "filebeat-$FilebeatVersion-windows-x86_64"
if (Test-Path $SubFolder) {
    # On veut que l'exécutable filebeat.exe soit directement dans $InstallPath
    Get-ChildItem $SubFolder -Recurse | Move-Item -Destination $InstallPath -Force
    Remove-Item $SubFolder -Force -Recurse
}

Write-Host "Configuration de Filebeat..."

# 3) Configurer la sortie ES / Logstash dans filebeat.yml
$filebeatYml = Join-Path $InstallPath "filebeat.yml"

if (!(Test-Path $filebeatYml)) {
    Write-Host "Erreur : Fichier de configuration introuvable : $filebeatYml" -ForegroundColor Red
    exit 1
}

if ($UseLogstash -eq $true) {
    # Décommenter output.logstash et commenter output.elasticsearch
    (Get-Content $filebeatYml) |
        ForEach-Object {
            $_ -replace '^(output.elasticsearch:)', '#$1' `
               -replace '^(  hosts: \["localhost:9200"\])', '#$1' `
               -replace '^#(output.logstash:)', '$1' `
               -replace '^#(  hosts: \["localhost:5044"\])', "  hosts: [`"$LogstashHost`"]"
        } | Set-Content $filebeatYml

    Write-Host "Filebeat enverra les logs vers Logstash : $LogstashHost"
}
else {
    # Décommenter output.elasticsearch et commenter output.logstash
    (Get-Content $filebeatYml) |
        ForEach-Object {
            $_ -replace '^#(output.elasticsearch:)', '$1' `
               -replace '^#(  hosts: \["localhost:9200"\])', "  hosts: [`"$ElasticsearchHost`"]" `
               -replace '^(output.logstash:)', '#$1' `
               -replace '^(  hosts: \["localhost:5044"\])', '#$1'
        } | Set-Content $filebeatYml

    Write-Host "Filebeat enverra les logs vers Elasticsearch : $ElasticsearchHost"
}

# 4) Installer Filebeat en tant que service Windows
Write-Host "Installation de Filebeat en tant que service..."
Set-Location $InstallPath
.\install-service-filebeat.ps1

Start-Service filebeat
Set-Service filebeat -StartupType Automatic

Write-Host "✅ Filebeat installé et configuré avec succès !" -ForegroundColor Green
Write-Host "=== Fin de l'installation de Filebeat ==="
