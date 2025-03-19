#!/bin/bash

###############################################################################
#
# Auteur  : VAPOTANK
# Date    : 2025-03-17
# 
###############################################################################
set -euo pipefail

# =============================================
#        Remote Agent Installer (Interactif)
# =============================================
cat << "HEADER"
   ___           _        _    _   _      _      
  / _ \__ _ _ __| |__    / \  | \ | | ___| |_    
 / /_)/ _` | '__| '_ \  / _ \ |  \| |/ _ \ __|   
/ ___/ (_| | |  | |_) |/ ___ \| |\  |  __/ |_    
\/    \__,_|_|  |_.__//_/   \_\_| \_|\___|\__|   
                                                
Remote Agent Installer - Interactif
HEADER
echo "============================================="
echo ""

# Fonction d'affichage d'erreur et sortie
error_exit() {
  echo -e "\e[31m[ERREUR] $1\e[0m" >&2
  exit 1
}

# Définir ici l'IP/nom du serveur central (pour Filebeat ou Zabbix Agent)
SERVER_IP="192.168.1.41"

# Demande de l'IP ou nom d'hôte de la machine cible
read -rp "Entrez l'IP ou le nom d'hôte de la machine cible : " TARGET_IP
[ -z "$TARGET_IP" ] && error_exit "L'IP ou le nom d'hôte est requis."
echo ""

# Choix du système d'exploitation de la cible
echo "Sélectionnez le système d'exploitation de la machine cible :"
echo "  1) Debian/Ubuntu"
echo "  2) Windows"
read -rp "Votre choix (1/2) : " os_choice
case "$os_choice" in
  1) OS_TYPE="debian" ;;
  2) OS_TYPE="windows" ;;
  *) error_exit "Option d'OS invalide." ;;
esac
echo ""

# Choix du type d'agent à installer
echo "Sélectionnez le type d'agent à installer :"
echo "  1) Filebeat (Agent ELK)"
echo "  2) Agent Zabbix"
read -rp "Votre choix (1/2) : " agent_choice
case "$agent_choice" in
  1) AGENT_TYPE="filebeat" ;;
  2) AGENT_TYPE="zabbix" ;;
  *) error_exit "Type d'agent invalide." ;;
esac
echo ""
echo "============================================="
echo "Début de l'installation à distance sur $TARGET_IP..."
echo "OS cible       : $OS_TYPE"
echo "Agent choisi   : $AGENT_TYPE"
echo "Serveur central: $SERVER_IP"
echo "============================================="
echo ""

#####################################
# FONCTION : INSTALLER FILEBEAT     #
#####################################
install_filebeat_debian() {
    echo -e "\e[32mInstallation de Filebeat sur Debian ($TARGET_IP)...\e[0m"
    ssh root@"$TARGET_IP" bash -s <<EOF
set -euo pipefail
echo "=== Installation de Filebeat ==="

# 1) Import de la clé GPG dans /etc/apt/trusted.gpg.d/
wget -qO /etc/apt/trusted.gpg.d/elastic.gpg https://artifacts.elastic.co/GPG-KEY-elasticsearch || {
  echo "Échec de l'importation de la clé GPG Elastic"; exit 1;
}

# 2) Ajout du dépôt Elastic
echo "deb https://artifacts.elastic.co/packages/7.x/apt stable main" > /etc/apt/sources.list.d/elastic-7.x.list

# 3) Installation du paquet
apt update -y || { echo "Échec de la mise à jour"; exit 1; }
apt install -y filebeat || { echo "Échec de l'installation de Filebeat"; exit 1; }

# 4) Configuration de /etc/filebeat/filebeat.yml
cat <<CONFIG > /etc/filebeat/filebeat.yml
filebeat.inputs:
- type: log
  enabled: true
  paths:
    - /var/log/*.log

output.elasticsearch:
  hosts: ["${SERVER_IP}:9200"]
  username: "elastic"
  password: "FtGlIjDf9TBUxF5hjbZa"
CONFIG

# 5) Démarrage du service
systemctl enable filebeat
systemctl restart filebeat
echo "✅ Filebeat installé et configuré pour remonter vers ${SERVER_IP}:9200."
EOF

    exit_code=$?
    if [ "$exit_code" -eq 0 ]; then
      echo -e "\e[32mInstallation de Filebeat réussie sur $TARGET_IP.\e[0m"
    else
      error_exit "Installation de Filebeat échouée sur $TARGET_IP"
    fi
}

#####################################
# FONCTION : INSTALLER ZABBIX AGENT #
#####################################
install_zabbix_debian() {
    echo -e "\e[32mInstallation de l'agent Zabbix sur Debian ($TARGET_IP)...\e[0m"
    ssh root@"$TARGET_IP" bash -s <<EOF
export DEBIAN_FRONTEND=noninteractive
set -euo pipefail

echo "=== Installation de l'Agent Zabbix ==="

systemctl stop zabbix-agent 2>/dev/null || true
systemctl disable zabbix-agent 2>/dev/null || true
systemctl mask zabbix-agent 2>/dev/null || true

wget -O /tmp/zabbix-release.deb https://repo.zabbix.com/zabbix/6.0/debian/pool/main/z/zabbix-release/zabbix-release_6.0-4+debian11_all.deb || {
  echo "Échec du téléchargement du dépôt Zabbix"; exit 1;
}
dpkg -i /tmp/zabbix-release.deb || { echo "Installation du dépôt Zabbix échouée"; exit 1; }

if ! grep -q "bullseye-security" /etc/apt/sources.list; then
  echo "deb http://security.debian.org/debian-security bullseye-security main" >> /etc/apt/sources.list
fi

apt update -y
apt-get install -y libssl1.1 libldap-2.4-2 || echo "[INFO] Dépendances déjà satisfaites ou indisponibles."
apt install -y zabbix-agent || { echo "Installation de l'agent Zabbix échouée"; exit 1; }

# -- Créer le répertoire d'inclusion s'il n'existe pas --
mkdir -p /etc/zabbix/zabbix_agentd.conf.d

# -- Fichier de log et répertoires --
mkdir -p /var/log/zabbix /run/zabbix
chown zabbix:zabbix /var/log/zabbix /run/zabbix

rm -f /var/log/zabbix/zabbix_agentd.log
touch /var/log/zabbix/zabbix_agentd.log
chown zabbix:zabbix /var/log/zabbix/zabbix_agentd.log
chmod 644 /var/log/zabbix/zabbix_agentd.log

rm -f /etc/zabbix/zabbix_agentd.conf
cat <<ZABBIXCONFIG > /etc/zabbix/zabbix_agentd.conf
PidFile=/run/zabbix/zabbix_agentd.pid
LogFile=/var/log/zabbix/zabbix_agentd.log
LogFileSize=0
Server=${SERVER_IP}
ServerActive=${SERVER_IP}
Hostname=\$(hostname -f)
HostMetadata=TEAM=IT
StartAgents=3
Include=/etc/zabbix/zabbix_agentd.conf.d/*.conf
ZABBIXCONFIG

systemctl unmask zabbix-agent
systemctl enable zabbix-agent
systemctl start zabbix-agent

echo "✅ Agent Zabbix installé et configuré pour remonter vers ${SERVER_IP} (checks passifs et actifs)."
EOF

    exit_code=$?
    if [ "$exit_code" -eq 0 ]; then
      echo -e "\e[32mInstallation de l'agent Zabbix réussie sur $TARGET_IP.\e[0m"
    else
      error_exit "Installation de l'agent Zabbix échouée sur $TARGET_IP"
    fi
}


######################################################
# FONCTIONS WINDOWS (instructions, pas de script)    #
######################################################
install_filebeat_windows_instructions() {
    echo -e "\e[33mPour installer Filebeat sur Windows, ouvrez une session PowerShell en mode Administrateur et exécutez :\e[0m"
    cat << EOF
Invoke-WebRequest -Uri "https://votre-domaine/Install_Filebeat.ps1" -OutFile "C:\Temp\Install_Filebeat.ps1"
powershell -ExecutionPolicy Bypass -File C:\Temp\Install_Filebeat.ps1
EOF
}

install_zabbix_windows_instructions() {
    echo -e "\e[33mPour installer l'agent Zabbix sur Windows, ouvrez une session PowerShell en mode Administrateur et exécutez :\e[0m"
    cat << EOF
Invoke-WebRequest -Uri "https://votre-domaine/Install_ZabbixAgent.ps1" -OutFile "C:\Temp\Install_ZabbixAgent.ps1"
powershell -ExecutionPolicy Bypass -File C:\Temp\Install_ZabbixAgent.ps1
EOF
}

# Exécution selon les choix
if [ "$OS_TYPE" = "debian" ]; then
  if [ "$AGENT_TYPE" = "filebeat" ]; then
    install_filebeat_debian
  elif [ "$AGENT_TYPE" = "zabbix" ]; then
    install_zabbix_debian
  else
    error_exit "Type d'agent inconnu."
  fi
elif [ "$OS_TYPE" = "windows" ]; then
  if [ "$AGENT_TYPE" = "filebeat" ]; then
    install_filebeat_windows_instructions
  elif [ "$AGENT_TYPE" = "zabbix" ]; then
    install_zabbix_windows_instructions
  else
    error_exit "Type d'agent inconnu."
  fi
else
  error_exit "Type d'OS inconnu."
fi

echo ""
echo -e "\e[32mInstallation et configuration terminées.\nL'agent remontera automatiquement (Zabbix) ou enverra ses logs (Filebeat) vers le serveur ${SERVER_IP}.\e[0m"
