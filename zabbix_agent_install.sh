#!/bin/bash

###############################################################################
# Script d'installation et de configuration de l'agent Zabbix
# Auteur  : VAPOTANK
# Date    : 2025-03-17
# Objectif: Installer Zabbix Agent sur Debian et le configurer pour pointer
#           vers le serveur Zabbix souhaité.
###############################################################################

ZABBIX_SERVER_IP="192.168.1.56"   # <-- Modifier avec l'IP/hostname de TON serveur Zabbix
AGENT_HOSTNAME="AgentDebian"     # <-- Nom d'hôte de la machine cliente

# Couleurs
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo "=== Installation de l'Agent Zabbix ==="

# 1) Installer le dépôt Zabbix
wget -O /tmp/zabbix-release.deb https://repo.zabbix.com/zabbix/6.0/debian/pool/main/z/zabbix-release/zabbix-release_6.0-4+debian11_all.deb || {
    echo -e "${RED}Échec du téléchargement du dépôt Zabbix${NC}"
    exit 1
}
dpkg -i /tmp/zabbix-release.deb || {
    echo -e "${RED}Échec de l'installation du dépôt Zabbix${NC}"
    exit 1
}
apt update -y

# 2) Installer l'agent Zabbix
apt install -y zabbix-agent || {
    echo -e "${RED}Échec de l'installation de Zabbix Agent${NC}"
    exit 1
}

# 3) Configurer l'agent
sed -i "s|^Server=.*|Server=$ZABBIX_SERVER_IP|" /etc/zabbix/zabbix_agentd.conf
sed -i "s|^ServerActive=.*|ServerActive=$ZABBIX_SERVER_IP|" /etc/zabbix/zabbix_agentd.conf
sed -i "s|^Hostname=.*|Hostname=$AGENT_HOSTNAME|" /etc/zabbix/zabbix_agentd.conf

# 4) Redémarrer le service
systemctl enable zabbix-agent
systemctl restart zabbix-agent

echo -e "${GREEN}✅ Zabbix Agent installé et configuré avec succès !${NC}"
echo " Serveur Zabbix  : $ZABBIX_SERVER_IP"
echo " Nom d'hôte (Agent) : $AGENT_HOSTNAME"
echo "=== Fin de l'installation de l'Agent Zabbix ==="
