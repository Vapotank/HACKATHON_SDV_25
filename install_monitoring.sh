#!/bin/bash

################################################################################
# Script d'installation complet : Zabbix, Grafana, Fail2ban, Lynis, Vulners,
# ELK (Elasticsearch, Logstash, Kibana), Suricata (optionnel),
# avec installation automatique des dépendances (iptables, ufw, python3, pip, etc.)
#
# Auteur  : ChatGPT
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

########################
# 1) MISE À JOUR / BASE
########################
install_base_packages() {
    echo "--- Mise à jour du système et installation des dépendances de base ---"
    apt update && apt upgrade -y || die "Échec de la mise à jour du système"

    # Paquets de base
    apt install -y \
        gnupg gnupg2 \
        python3 python3-pip python3-venv \
        curl wget lsb-release apt-transport-https \
        software-properties-common \
        iptables ufw \
        || die "Échec installation paquets de base"
}

########################
# 2) CONFIG FIREWALL   #
########################
configure_firewall() {
    if ask_user "Voulez-vous configurer un firewall UFW avec quelques règles de base ?"; then
        echo "--- Configuration du firewall (UFW) ---"
        apt install -y ufw || die "Échec de l'installation d'ufw"

        # Autoriser SSH, HTTP, HTTPS, Zabbix, Kibana, Grafana...
        ufw default deny incoming
        ufw default allow outgoing
        ufw allow ssh
        ufw allow 80/tcp    # HTTP
        ufw allow 443/tcp   # HTTPS
        ufw allow 10050/tcp # Zabbix agent
        ufw allow 10051/tcp # Zabbix server
        ufw allow 3000/tcp  # Grafana
        ufw allow 5601/tcp  # Kibana
        ufw allow 5044/tcp  # Logstash (si besoin)
        ufw enable
        echo "✅ Firewall UFW activé."
    else
        echo "Firewall ignoré."
    fi
}

########################
# 3) INSTALL MARIADB   #
########################
install_mariadb() {
    echo "--- Installation de MariaDB (MySQL) ---"
    apt install -y mariadb-server || die "Échec de l'installation de MariaDB"
    systemctl enable --now mariadb

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
    echo "--- Vérification de libssl1.1 / libldap-2.4-2 pour Debian 12 ---"
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
        fix_dependencies_zabbix

        echo "--- Installation de Zabbix Server + Agent ---"
        wget -O /tmp/zabbix-release.deb \
          https://repo.zabbix.com/zabbix/6.0/debian/pool/main/z/zabbix-release/zabbix-release_6.0-4+debian11_all.deb \
          || die "Échec du téléchargement du dépôt Zabbix"
        dpkg -i /tmp/zabbix-release.deb || die "Échec de l'installation du dépôt Zabbix"
        apt update
        apt install -y zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf zabbix-agent \
           || die "Échec installation Zabbix"

        echo "--- Import du schéma Zabbix dans la base ---"
        zcat /usr/share/doc/zabbix-server-mysql/create.sql.gz | \
            mysql -u "${ZABBIX_DB_USER}" -p"${ZABBIX_DB_PASS}" "${ZABBIX_DB}" || \
            echo "Peut-être déjà importé ou échec d'import..."

        echo "--- Configuration Zabbix (php.ini) ---"
        sed -i "s|.*date.timezone =.*|php_value date.timezone ${ZABBIX_SERVER_TIMEZONE}|" /etc/apache2/conf-available/zabbix.conf || true

        echo "--- Configuration du fichier Zabbix Server ---"
        sed -i "s|^# DBPassword=.*|DBPassword=${ZABBIX_DB_PASS}|" /etc/zabbix/zabbix_server.conf
        sed -i "s|^# DBUser=.*|DBUser=${ZABBIX_DB_USER}|" /etc/zabbix/zabbix_server.conf
        sed -i "s|^# DBName=.*|DBName=${ZABBIX_DB}|" /etc/zabbix/zabbix_server.conf

        systemctl enable zabbix-server zabbix-agent apache2
        systemctl restart zabbix-server zabbix-agent apache2

        echo "✅ Zabbix installé ! Accès : http://<IP>/zabbix (Admin / zabbix par défaut)"
    else
        echo "Zabbix ignoré."
    fi
}

########################
# 6) INSTALL GRAFANA   #
########################
install_grafana() {
    if ask_user "Voulez-vous installer Grafana ?"; then
        echo "--- Installation de Grafana ---"
        wget -q -O - https://packages.grafana.com/gpg.key | apt-key add - || die "Échec clé GPG Grafana"
        echo "deb https://packages.grafana.com/oss/deb stable main" > /etc/apt/sources.list.d/grafana.list
        apt update && apt install -y grafana || die "Échec installation Grafana"

        systemctl enable --now grafana-server

        echo "--- Configuration Admin Grafana ---"
        sed -i "s/^;admin_user = .*/admin_user = ${GRAFANA_ADMIN_USER}/" /etc/grafana/grafana.ini
        sed -i "s/^;admin_password = .*/admin_password = ${GRAFANA_ADMIN_PASS}/" /etc/grafana/grafana.ini

        systemctl restart grafana-server
        echo "✅ Grafana installé ! http://<IP>:3000 (user=${GRAFANA_ADMIN_USER}, pass=${GRAFANA_ADMIN_PASS})"
    else
        echo "Grafana ignoré."
    fi
}

########################
# 7) FAIL2BAN          #
########################
install_fail2ban() {
    if ask_user "Voulez-vous installer et configurer Fail2ban ?"; then
        echo "--- Installation de Fail2ban ---"
        apt install -y fail2ban || die "Échec installation Fail2ban"

        cat <<EOF > /etc/fail2ban/jail.local
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
[sshd]
enabled = true
EOF
        systemctl enable --now fail2ban
        echo "✅ Fail2ban installé."
    else
        echo "Fail2ban ignoré."
    fi
}

########################
# 8) LYNIS             #
########################
install_lynis() {
    if ask_user "Voulez-vous installer Lynis pour l'audit de sécurité ?"; then
        echo "--- Installation de Lynis ---"
        apt install -y lynis || die "Échec installation Lynis"
        echo "✅ Lynis installé."
    else
        echo "Lynis ignoré."
    fi
}

########################
# 9) VULNERS           #
########################
install_vulners() {
    if ask_user "Voulez-vous installer Vulners pour la détection de CVE ?"; then
        echo "--- Installation de Vulners CLI ---"
        python3 -m venv /opt/vulners-venv
        source /opt/vulners-venv/bin/activate
        pip install --upgrade pip
        pip install vulners || die "Échec installation Vulners"
        deactivate
        echo "✅ Vulners installé. Lancez : 'source /opt/vulners-venv/bin/activate && python3 -m vulners'"
    else
        echo "Vulners ignoré."
    fi
}

########################
# 10) ELK              #
########################
install_elk() {
    if ask_user "Voulez-vous installer la stack ELK (Elasticsearch, Logstash, Kibana) ?"; then
        echo "--- Installation ELK ---"
        wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | apt-key add - || die "Échec clé GPG Elastic"
        echo "deb https://artifacts.elastic.co/packages/7.x/apt stable main" > /etc/apt/sources.list.d/elastic-7.x.list
        apt update && apt install -y elasticsearch logstash kibana || die "Échec installation ELK"

        systemctl enable elasticsearch logstash kibana
        systemctl start elasticsearch logstash kibana

        echo "✅ ELK installé."

        # Activer la sécurité Elasticsearch ?
        if [ "$ENABLE_ELASTIC_SECURITY" = true ]; then
            echo "--- Activation de la sécurité Elasticsearch ---"
            sed -i '/^#\?xpack.security.enabled:/d' /etc/elasticsearch/elasticsearch.yml
            echo "xpack.security.enabled: true" >> /etc/elasticsearch/elasticsearch.yml

            systemctl restart elasticsearch
            echo "Patientez 10s le temps du redémarrage..."
            sleep 10

            echo "Génération automatique des mots de passe..."
            /usr/share/elasticsearch/bin/elasticsearch-setup-passwords auto -b > "$ES_PASSWORDS_FILE" 2>/dev/null

            echo "==== Mots de passe Elasticsearch générés (stockés dans $ES_PASSWORDS_FILE) ===="
            cat "$ES_PASSWORDS_FILE"

            # Extraire pass de 'elastic'
            NEW_ELASTIC_PASS=$(grep "PASSWORD elastic =" "$ES_PASSWORDS_FILE" | awk '{print $4}')
            if [ -n "$NEW_ELASTIC_PASS" ]; then
                echo "Mot de passe elastic : $NEW_ELASTIC_PASS"

                # Kibana config
                sed -i "s|^#\?elasticsearch.username:.*|elasticsearch.username: \"$KIBANA_ELASTIC_USER\"|" /etc/kibana/kibana.yml
                sed -i "s|^#\?elasticsearch.password:.*|elasticsearch.password: \"$NEW_ELASTIC_PASS\"|" /etc/kibana/kibana.yml
                sed -i "s|^#\?elasticsearch.hosts:.*|elasticsearch.hosts: [\"http://localhost:9200\"]|" /etc/kibana/kibana.yml
                systemctl restart kibana
            else
                echo "[WARNING] Impossible de trouver 'elastic' dans $ES_PASSWORDS_FILE"
            fi
            echo "✅ Sécurité Elasticsearch activée. Voir $ES_PASSWORDS_FILE."
        fi

        echo "✅ Accès Kibana : http://<IP>:5601"
    else
        echo "ELK ignoré."
    fi
}

########################
# 11) SURICATA (IDS)   #
########################
install_suricata() {
    if ask_user "Voulez-vous installer Suricata (IDS/IPS) ?"; then
        echo "--- Installation de Suricata ---"
        apt install -y suricata || die "Échec installation Suricata"
        systemctl enable suricata
        systemctl stop suricata

        # Personnaliser suricata.yaml si besoin (HOME_NET, etc.)
        systemctl start suricata
        echo "✅ Suricata installé et démarré."

        if ask_user "Voulez-vous intégrer Suricata à ELK via Filebeat ?"; then
            apt install -y filebeat || echo "Filebeat déjà installé ?"
            cat <<EOF > /etc/filebeat/filebeat.yml
filebeat.inputs:
- type: filestream
  id: suricata-logs
  enabled: true
  paths:
    - /var/log/suricata/*.log
  fields:
    type: suricata
  fields_under_root: true

output.elasticsearch:
  hosts: ["localhost:9200"]
EOF
            systemctl enable filebeat
            systemctl restart filebeat
            echo "✅ Suricata → ELK via Filebeat activé."
        fi
    else
        echo "Suricata ignoré."
    fi
}

########################
# DETECT IP            #
########################
detect_ip() {
    echo "--- Détection de l'adresse IP du serveur ---"
    ip addr show | grep 'inet ' | awk '{print $2}'
}

########################
# MAIN                 #
########################
main() {
    echo "=== Début de l'installation du monitoring complet ==="
    install_base_packages        # Step 1
    configure_firewall           # Step 2 (optionnel)
    install_mariadb             # Step 3
    install_zabbix              # Step 5
    install_grafana             # Step 6
    install_fail2ban            # Step 7
    install_lynis               # Step 8
    install_vulners             # Step 9
    install_elk                 # Step 10
    install_suricata            # Step 11
    detect_ip
    echo "=== Installation terminée ! ==="
    echo "---------------------------------"
    echo "Infos / Credentials :"
    echo "  - MySQL root      : $MYSQL_ROOT_PASSWORD"
    echo "  - Zabbix DB       : $ZABBIX_DB (user=$ZABBIX_DB_USER / pass=$ZABBIX_DB_PASS)"
    echo "  - Zabbix Frontend : http://<IP>/zabbix (Admin / zabbix)"
    echo "  - Grafana         : http://<IP>:3000 (user=$GRAFANA_ADMIN_USER / pass=$GRAFANA_ADMIN_PASS)"
    echo "  - ELK / Kibana    : http://<IP>:5601"
    echo "    -> Mots de passe générés (si sécurité ES activée) dans : $ES_PASSWORDS_FILE"
    echo "Logs d'installation : $LOG_FILE"
}

main
