#!/bin/bash

################################################################################
# Script d'installation complet : Zabbix, Grafana, Fail2ban, Lynis, Vulners,
# ELK (Elasticsearch, Logstash, Kibana), Suricata (optionnel),
# avec correction des erreurs liées à l'import SQL Zabbix, fail2ban (auth.log),
# et vérification si déjà installé. Firewall UFW optionnel.
#
# Auteur  : VAPOTANK
# Date    : 2025-03-17
# Usage   : sudo ./install_monitoring.sh
################################################################################

LOG_FILE="/var/log/auto_monitoring.log"
exec > >(tee -a "$LOG_FILE") 2>&1

########################
# VARIABLES DE CREDITS #
########################

# -- MySQL (MariaDB) --
MYSQL_ROOT_PASSWORD="root123"      # Mot de passe root MySQL
ZABBIX_DB="zabbix"                 # Nom de la base Zabbix
ZABBIX_DB_USER="zabbix"            # User Zabbix
ZABBIX_DB_PASS="zabbix_pass"       # Mot de passe user Zabbix

# -- Zabbix Frontend --
ZABBIX_SERVER_TIMEZONE="Europe/Paris"

# -- Grafana Admin --
GRAFANA_ADMIN_USER="admin"
GRAFANA_ADMIN_PASS="admin123"

# -- Elasticsearch / Kibana --
ENABLE_ELASTIC_SECURITY=true        # Passe à false pour garder ES sans mot de passe
ES_PASSWORDS_FILE="/tmp/es_passwords.txt"  # Fichier où on stockera les mots de passe générés
KIBANA_ELASTIC_USER="elastic"       # Par défaut, on utilisera l'utilisateur "elastic" dans Kibana

########################
# FONCTIONS UTILES     #
########################

die() {
    echo "[ERROR] $1" >&2
    exit 1
}

ask_user() {
    read -p "$1 (y/n): " response
    case "$response" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

# Teste si le paquet est déjà installé (Debian/Ubuntu)
already_installed() {
    dpkg -s "$1" &>/dev/null
    return $?
}

########################
# 1) PACKAGES DE BASE  #
########################
install_base_packages() {
    echo "--- Mise à jour du système et installation des dépendances de base ---"
    apt update && apt upgrade -y || die "Échec de la mise à jour du système"
    apt install -y gnupg gnupg2 python3 python3-pip python3-venv \
                   curl wget lsb-release apt-transport-https \
                   software-properties-common iptables ufw \
        || die "Échec installation paquets de base"
}

########################
# 2) FIREWALL (UFW)    #
########################
configure_firewall() {
    if ask_user "Voulez-vous configurer un firewall UFW avec quelques règles de base ?"; then
        # Vérifie si UFW est déjà installé
        if already_installed ufw; then
            echo "UFW déjà installé, on vérifie juste la config..."
        else
            apt install -y ufw || die "Échec de l'installation d'ufw"
        fi

        ufw default deny incoming
        ufw default allow outgoing
        ufw allow ssh
        ufw allow 80/tcp
        ufw allow 443/tcp
        ufw allow 10050/tcp  # Zabbix Agent
        ufw allow 10051/tcp  # Zabbix Server
        ufw allow 3000/tcp   # Grafana
        ufw allow 5601/tcp   # Kibana
        ufw allow 5044/tcp   # Logstash
        ufw enable
        echo "✅ Firewall UFW configuré et activé."
    else
        echo "Firewall ignoré."
    fi
}

########################
# 3) MARIADB           #
########################
install_mariadb() {
    if already_installed mariadb-server; then
        echo "MariaDB est déjà installé. On saute l'installation."
    else
        echo "--- Installation de MariaDB (MySQL) ---"
        apt install -y mariadb-server || die "Échec de l'installation de MariaDB"
        systemctl enable --now mariadb
    fi

    echo "--- Configuration du mot de passe root MySQL ---"
    mysql -u root <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
FLUSH PRIVILEGES;
EOF

    echo "--- Création base et user Zabbix ---"
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" <<EOF
CREATE DATABASE IF NOT EXISTS ${ZABBIX_DB} CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER IF NOT EXISTS '${ZABBIX_DB_USER}'@'localhost' IDENTIFIED BY '${ZABBIX_DB_PASS}';
GRANT ALL PRIVILEGES ON ${ZABBIX_DB}.* TO '${ZABBIX_DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF
}

########################
# 4) FIX DEP ZABBIX    #
########################
fix_dependencies_zabbix() {
    # Ajouter bullseye-security si besoin (pour libssl1.1 etc.)
    if ! grep -q "bullseye-security" /etc/apt/sources.list ; then
        echo "deb http://security.debian.org/debian-security bullseye-security main" >> /etc/apt/sources.list
    fi
    apt update
    apt install -y libssl1.1 libldap-2.4-2 || echo "Dépendances Zabbix déjà satisfaites ou introuvables."
}

########################
# 5) INSTALL ZABBIX    #
########################
install_zabbix() {
    if ask_user "Voulez-vous installer Zabbix Server + Agent ?"; then

        # Vérifier si zabbix-server-mysql est déjà installé
        if already_installed zabbix-server-mysql; then
            echo "Zabbix Server déjà installé, on saute la partie installation."
        else
            fix_dependencies_zabbix

            echo "--- Installation de Zabbix Server + Agent ---"
            wget -O /tmp/zabbix-release.deb \
              https://repo.zabbix.com/zabbix/6.0/debian/pool/main/z/zabbix-release/zabbix-release_6.0-4+debian11_all.deb \
              || die "Échec du téléchargement du dépôt Zabbix"
            dpkg -i /tmp/zabbix-release.deb || die "Échec de l'installation du dépôt Zabbix"
            apt update
            apt install -y zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf zabbix-agent \
               || die "Échec installation Zabbix"

            # Installer le package zabbix-sql-scripts pour l'import
            apt install -y zabbix-sql-scripts

            # Import du schéma
            SCHEMA_FILE=$(find /usr/share/zabbix-sql-scripts -name "schema.sql.gz" -o -name "create.sql.gz" 2>/dev/null | head -n 1)
       
