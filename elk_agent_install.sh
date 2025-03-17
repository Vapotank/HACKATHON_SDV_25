#!/bin/bash

###############################################################################
# Script d'installation et de configuration de Filebeat (Agent ELK)
# Auteur  : VAPOTANK
# Date    : 2025-03-17
# Objectif: Installer et configurer Filebeat sur Debian pour envoyer les logs
#           vers un cluster Elasticsearch ou un Logstash.
###############################################################################

ELASTICSEARCH_HOST="192.168.1.56"   # <-- IP/hostname de TON Elasticsearch
LOGSTASH_HOST=""                    # <-- Optionnel, si tu utilises Logstash
USE_LOGSTASH=false                 # <-- Mettre à true si tu veux envoyer via Logstash

# Couleurs
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo "=== Installation de Filebeat (Agent ELK) ==="

# 1) Installer la clé et le dépôt Elasticsearch
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | apt-key add - || {
    echo -e "${RED}Échec de l'ajout de la clé GPG Elasticsearch${NC}"
    exit 1
}
echo "deb https://artifacts.elastic.co/packages/7.x/apt stable main" > /etc/apt/sources.list.d/elastic-7.x.list
apt update -y

# 2) Installer Filebeat
apt install -y filebeat || {
    echo -e "${RED}Échec de l'installation de Filebeat${NC}"
    exit 1
}

# 3) Configuration de base
if [ "$USE_LOGSTASH" = "true" ]; then
    # Sortie vers Logstash
    sed -i 's|output.elasticsearch:|#output.elasticsearch:|g' /etc/filebeat/filebeat.yml
    sed -i 's|hosts: \["localhost:9200"\]|#hosts: \["localhost:9200"\]|g' /etc/filebeat/filebeat.yml
    
    sed -i 's|#output.logstash:|output.logstash:|g' /etc/filebeat/filebeat.yml
    sed -i "s|#  hosts: \[\"localhost:5044\"\]|  hosts: [\"$LOGSTASH_HOST:5044\"]|g" /etc/filebeat/filebeat.yml

    echo "Filebeat sera configuré pour envoyer les logs à Logstash ($LOGSTASH_HOST:5044)."
else
    # Sortie directe vers Elasticsearch
    sed -i 's|#output.elasticsearch:|output.elasticsearch:|g' /etc/filebeat/filebeat.yml
    sed -i "s|#  hosts: \[\"localhost:9200\"\]|  hosts: [\"$ELASTICSEARCH_HOST:9200\"]|g" /etc/filebeat/filebeat.yml
    echo "Filebeat sera configuré pour envoyer les logs à Elasticsearch ($ELASTICSEARCH_HOST:9200)."
fi

# 4) Activer et démarrer Filebeat
systemctl enable filebeat
systemctl start filebeat

echo -e "${GREEN}✅ Filebeat (Agent ELK) installé et configuré avec succès !${NC}"
echo " Elasticsearch : $ELASTICSEARCH_HOST"
echo " Logstash      : $LOGSTASH_HOST (USE_LOGSTASH=$USE_LOGSTASH)"
echo "=== Fin de l'installation de Filebeat ==="
