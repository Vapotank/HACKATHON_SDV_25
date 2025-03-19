#!/bin/bash
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

# Paramètre du serveur central (à modifier si besoin)
SERVER_IP="192.168.1.41"

# Demande de l'IP ou nom d'hôte de la machine cible
read -rp "Entrez l'IP ou le nom d'hôte de la machine cible : " TARGET_IP
if [ -z "$TARGET_IP" ]; then
  error_exit "L'IP ou le nom d'hôte est requis."
fi

echo ""

# Choix du système d'exploitation de la cible
echo "Sélectionnez le système d'exploitation de la machine cible :"
echo "  1) Debian/Ubuntu"
echo "  2) Windows"
read -rp "Votre choix (1/2) : " os_choice

case "$os_choice" in
  1)
    OS_TYPE="debian"
    ;;
  2)
    OS_TYPE="windows"
    ;;
  *)
    error_exit "Option d'OS invalide."
    ;;
esac

echo ""

# Choix du type d'agent à installer
echo "Sélectionnez le type d'agent à installer :"
echo "  1) Filebeat (Agent ELK)"
echo "  2) Agent Zabbix"
read -rp "Votre choix (1/2) : " agent_choice

case "$agent_choice" in
  1)
    AGENT_TYPE="filebeat"
    ;;
  2)
    AGENT_TYPE="zabbix"
    ;;
  *)
    error_exit "Option d'agent invalide."
    ;;
esac

echo ""
echo "============================================="
echo "Début de l'installation à distance sur $TARGET_IP..."
echo "OS cible       : $OS_TYPE"
echo "Agent choisi   : $AGENT_TYPE"
echo "Serveur central: $SERVER_IP"
echo "============================================="
echo ""

# Fonction pour installer Filebeat sur une machine Debian
install_filebeat_debian() {
    echo -e "\e[32mInstallation de Filebeat sur Debian ($TARGET_IP)...\e[0m"
    ssh root@"$TARGET_IP" bash -s <<'EOF'
set -euo pipefail
echo "=== Installation de Filebeat ==="
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | apt-key add - || { echo "Échec de l'ajout de la clé GPG"; exit 1; }
echo "deb https://artifacts.elastic.co/packages/7.x/apt stable main" > /etc/apt/sources.list.d/elastic-7.x.list
apt update -y || { echo "Échec de la mise à jour"; exit 1; }
apt install -y filebeat || { echo "Échec de l'installation de Filebeat"; exit 1; }
# Configuration de Filebeat pour remonter vers le serveur central
sed -i 's|#output.elasticsearch:|output.elasticsearch:|g' /etc/filebeat/filebeat.yml
sed -i 's|#  hosts: \["localhost:9200"\]|  hosts: ["'"$SERVER_IP"':9200"]|g' /etc/filebeat/filebeat.yml
systemctl enable filebeat
systemctl restart filebeat
echo "✅ Filebeat installé et démarré avec succès."
EOF
    if [ $? -eq 0 ]; then
      echo -e "\e[32mInstallation de Filebeat réussie sur $TARGET_IP.\e[0m"
    else
      error_exit "Installation de Filebeat échouée sur $TARGET_IP"
    fi
}

# Fonction pour installer l'agent Zabbix sur une machine Debian
install_zabbix_debian() {
    echo -e "\e[32mInstallation de l'agent Zabbix sur Debian ($TARGET_IP)...\e[0m"
    ssh root@"$TARGET_IP" bash -s <<'EOF'
set -euo pipefail
echo "=== Installation de l'Agent Zabbix ==="
wget -O /tmp/zabbix-release.deb https://repo.zabbix.com/zabbix/6.0/debian/pool/main/z/zabbix-release/zabbix-release_6.0-4+debian11_all.deb || { echo "Téléchargement du dépôt Zabbix échoué"; exit 1; }
dpkg -i /tmp/zabbix-release.deb || { echo "Installation du dépôt Zabbix échouée"; exit 1; }
apt update -y
apt install -y zabbix-agent || { echo "Installation de l'agent Zabbix échouée"; exit 1; }
# Configuration de l'agent pour remonter vers le serveur central
ZABBIX_SERVER_IP="'"$SERVER_IP"'"
AGENT_HOSTNAME="$(hostname)"
sed -i "s|^Server=.*|Server=${ZABBIX_SERVER_IP}|" /etc/zabbix/zabbix_agentd.conf
sed -i "s|^ServerActive=.*|ServerActive=${ZABBIX_SERVER_IP}|" /etc/zabbix/zabbix_agentd.conf
sed -i "s|^Hostname=.*|Hostname=${AGENT_HOSTNAME}|" /etc/zabbix/zabbix_agentd.conf
systemctl enable zabbix-agent
systemctl restart zabbix-agent
echo "✅ Agent Zabbix installé et configuré avec succès."
EOF
    if [ $? -eq 0 ]; then
      echo -e "\e[32mInstallation de l'agent Zabbix réussie sur $TARGET_IP.\e[0m"
    else
      error_exit "Installation de l'agent Zabbix échouée sur $TARGET_IP"
    fi
}

# Instructions pour l'installation sur Windows (affichage des commandes à copier-coller)
install_filebeat_windows_instructions() {
    echo -e "\e[33mPour installer Filebeat sur Windows, ouvrez une session PowerShell en mode Administrateur et exécutez les commandes suivantes :\e[0m"
    cat << EOF
Invoke-WebRequest -Uri "https://votre-domaine/Install_Filebeat.ps1" -OutFile "C:\Temp\Install_Filebeat.ps1"
# Ce script est préconfiguré pour remonter vers le serveur $SERVER_IP:9200
powershell -ExecutionPolicy Bypass -File C:\Temp\Install_Filebeat.ps1
EOF
}

install_zabbix_windows_instructions() {
    echo -e "\e[33mPour installer l'agent Zabbix sur Windows, ouvrez une session PowerShell en mode Administrateur et exécutez les commandes suivantes :\e[0m"
    cat << EOF
Invoke-WebRequest -Uri "https://votre-domaine/Install_ZabbixAgent.ps1" -OutFile "C:\Temp\Install_ZabbixAgent.ps1"
# Ce script est préconfiguré pour remonter vers le serveur $SERVER_IP
powershell -ExecutionPolicy Bypass -File C:\Temp\Install_ZabbixAgent.ps1
EOF
}

# Exécution en fonction des choix
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
echo -e "\e[32mInstallation et configuration terminées. L'agent remontera automatiquement vers le serveur $SERVER_IP.\e[0m"
