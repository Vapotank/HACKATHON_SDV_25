#!/bin/bash

###############################################################################
# Script de Gestion & Maintenance Avancée
# Auteur  : VAPOTANK
# Date    : 2025-03-17
# Objectif: Gérer et superviser automatiquement les services (Zabbix, Grafana,
#           Fail2ban, ELK, MariaDB), nettoyer les logs, auditer la sécurité,
#           vérifier les vulnérabilités et mettre à jour le système.
###############################################################################

# Couleurs ANSI
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
MAGENTA='\033[1;35m'
CYAN='\033[1;36m'
BOLD='\033[1m'
NC='\033[0m' # Pas de couleur

# ASCII Art
banner() {
  echo -e "${BLUE}"
  echo "   __  ___                      __           "
  echo "  /  |/  /___ _____  ____  ____/ /___ _____ "
  echo " / /|_/ / __  / __ \/ __ \/ __  / __  / __  \\"
  echo "/ /  / / /_/ / /_/ / /_/ / /_/ / /_/ / /_/ /"
  echo "/_/  /_/\__,_/ .___/\____/\__,_/\__,_/\__,_/"
  echo "           /_/  "
  echo -e "${NC}"
  echo -e "${MAGENTA}${BOLD}  Système de Gestion & Maintenance  ${NC}"
  echo "---------------------------------------------"
}

LOG_FILE="/var/log/system_management.log"
exec > >(tee -a "$LOG_FILE") 2>&1

SERVICES=("zabbix-server" "zabbix-agent" "grafana-server" "fail2ban" "elasticsearch" "logstash" "kibana" "mariadb")

# Vérification et redémarrage des services
check_services() {
    echo -e "${CYAN}📌 Vérification des services...${NC}"
    for service in "${SERVICES[@]}"; do
        systemctl is-active --quiet "$service"
        if [ $? -ne 0 ]; then
            echo -e "${RED}❌ $service est arrêté ! Tentative de redémarrage...${NC}"
            systemctl restart "$service"
            systemctl is-active --quiet "$service" && \
              echo -e "${GREEN}✅ $service redémarré avec succès !${NC}" || \
              echo -e "${RED}🚨 Échec du redémarrage de $service !${NC}"
        else
            echo -e "${GREEN}✅ $service fonctionne normalement.${NC}"
        fi
    done
}

# Vérifier et corriger MySQL/MariaDB
check_mysql() {
    echo -e "${CYAN}📌 Vérification de MariaDB/MySQL...${NC}"
    systemctl is-active --quiet mariadb
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ MariaDB est arrêté ! Tentative de redémarrage...${NC}"
        systemctl restart mariadb
        systemctl is-active --quiet mariadb && \
          echo -e "${GREEN}✅ MariaDB redémarré avec succès !${NC}" || \
          echo -e "${RED}🚨 Échec du redémarrage de MariaDB !${NC}"
    else
        echo -e "${GREEN}✅ MariaDB fonctionne normalement.${NC}"
    fi
}

# Vérifier et réparer Zabbix
check_zabbix() {
    echo -e "${CYAN}📌 Vérification de Zabbix...${NC}"
    # On suppose mot de passe 'azerty' pour l'utilisateur zabbix
    DB_COUNT=$(mysql -u zabbix -pazerty -e "USE zabbix; SHOW TABLES;" 2>/dev/null | wc -l)
    if [ "$DB_COUNT" -lt 10 ]; then
        echo -e "${YELLOW}⚠️ Base Zabbix semble incomplète. Tentative de réimportation...${NC}"
        CREATE_SQL=$(find /usr/share -name "create.sql.gz" 2>/dev/null | head -n 1)
        if [ -f "$CREATE_SQL" ]; then
            zcat "$CREATE_SQL" | mysql -u zabbix -pazerty zabbix && \
              echo -e "${GREEN}✅ Importation réussie !${NC}" || \
              echo -e "${RED}❌ Échec de l'importation !${NC}"
        else
            echo -e "${RED}🚨 Fichier create.sql.gz introuvable !${NC}"
        fi
    else
        echo -e "${GREEN}✅ Base de données Zabbix complète.${NC}"
    fi
}

# Vérifier et réparer ELK
check_elk() {
    echo -e "${CYAN}📌 Vérification de la stack ELK...${NC}"
    for service in "elasticsearch" "kibana"; do
        systemctl is-active --quiet "$service"
        if [ $? -ne 0 ]; then
            echo -e "${RED}❌ $service est arrêté ! Tentative de redémarrage...${NC}"
            systemctl restart "$service"
        else
            echo -e "${GREEN}✅ $service fonctionne normalement.${NC}"
        fi
    done
}

# Nettoyage des logs
clean_logs() {
    echo -e "${CYAN}📌 Nettoyage des logs...${NC}"
    find /var/log -type f -name "*.log" -size +100M -exec truncate -s 0 {} \;
    echo -e "${GREEN}✅ Logs nettoyés.${NC}"
}

# Audit de sécurité avec Lynis
run_lynis() {
    echo -e "${CYAN}📌 Audit de sécurité avec Lynis...${NC}"
    lynis audit system > /var/log/lynis_audit.log
    echo -e "${GREEN}✅ Audit terminé. Résultats dans /var/log/lynis_audit.log${NC}"
}

# Vérification des vulnérabilités avec Vulners
run_vulners() {
    echo -e "${CYAN}📌 Vérification des vulnérabilités avec Vulners...${NC}"
    source /opt/vulners-venv/bin/activate
    python3 -c "
import vulners
v = vulners.VulnersApi(api_key='DIGNQ4NM6A55C5NZ0L6LTZCARDNAEWI25QY4VM3OB5AZPWDTW65ZVTY3BVBBJ2TF')
result = v.software_audit(os='debian')
print(result)"
    deactivate
    echo -e "${GREEN}✅ Vérification des CVE terminée.${NC}"
}

# Mise à jour du système et des services
update_system() {
    echo -e "${CYAN}📌 Mise à jour du système...${NC}"
    apt update && apt upgrade -y
    apt install --only-upgrade zabbix-server-mysql zabbix-agent grafana fail2ban elasticsearch logstash kibana mariadb-server -y
    echo -e "${GREEN}✅ Mise à jour terminée.${NC}"
}

# Menu principal interactif
while true; do
    clear
    banner
    echo -e "${MAGENTA}1)${NC} Vérifier et redémarrer les services"
    echo -e "${MAGENTA}2)${NC} Vérifier et réparer MySQL/MariaDB"
    echo -e "${MAGENTA}3)${NC} Vérifier et réparer Zabbix"
    echo -e "${MAGENTA}4)${NC} Vérifier et réparer ELK (Elasticsearch/Kibana)"
    echo -e "${MAGENTA}5)${NC} Nettoyer les logs du serveur"
    echo -e "${MAGENTA}6)${NC} Lancer un audit de sécurité (Lynis)"
    echo -e "${MAGENTA}7)${NC} Vérifier les vulnérabilités (Vulners)"
    echo -e "${MAGENTA}8)${NC} Mettre à jour le système et les logiciels"
    echo -e "${MAGENTA}9)${NC} Quitter"
    echo -ne "${BOLD}➡️ Choisissez une option : ${NC}"
    read choice

    case $choice in
        1) check_services ;;
        2) check_mysql ;;
        3) check_zabbix ;;
        4) check_elk ;;
        5) clean_logs ;;
        6) run_lynis ;;
        7) run_vulners ;;
        8) update_system ;;
        9) echo -e "${RED}🔴 Fermeture du gestionnaire.${NC}"; exit 0 ;;
        *) echo -e "${RED}❌ Option invalide, veuillez réessayer.${NC}" ;;
    esac
    echo -e "${YELLOW}🔄 Appuyez sur Entrée pour revenir au menu...${NC}"
    read
done
