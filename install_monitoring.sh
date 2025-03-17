#!/bin/bash
set -o errexit
set -o pipefail

################################################################################
# Script d'installation complet : Zabbix, Grafana, Fail2ban, Lynis, Vulners,
# ELK (Elasticsearch, Logstash, Kibana), Suricata (optionnel),
# avec :
#  - Import des clés GPG dans /etc/apt/keyrings pour éviter les avertissements
#    "Key is stored in legacy trusted.gpg keyring".
#  - Mode non-interactif pour APT (DEBIAN_FRONTEND=noninteractive).
#  - Rollback minimal (si une étape échoue, on restaure les clés GPG et arrête).
#
# Auteur  : VAPOTANK (amélioré)
# Date    : 2025-03-17
# Usage   : sudo ./install_monitoring.sh
################################################################################

LOG_FILE="/var/log/auto_monitoring.log"
exec > >(tee -a "$LOG_FILE") 2>&1

########################
# VARIABLES DE CREDITS #
########################

MYSQL_ROOT_PASSWORD="root123"      # Mot de passe root MySQL
ZABBIX_DB="zabbix"
ZABBIX_DB_USER="zabbix"
ZABBIX_DB_PASS="zabbix_pass"

ZABBIX_SERVER_TIMEZONE="Europe/Paris"

GRAFANA_ADMIN_USER="admin"
GRAFANA_ADMIN_PASS="admin123"

ENABLE_ELASTIC_SECURITY=true
ES_PASSWORDS_FILE="/tmp/es_passwords.txt"
KIBANA_ELASTIC_USER="elastic"

# Dossier où on stockera les clés GPG
KEYRINGS_DIR="/etc/apt/keyrings"
GRAFANA_KEY="$KEYRINGS_DIR/grafana.gpg"
ELASTIC_KEY="$KEYRINGS_DIR/elastic.gpg"

########################
# ROLLBACK / ERREUR    #
########################

# Sauvegarde initiale du fichier apt sources
cp /etc/apt/sources.list /etc/apt/sources.list.bak 2>/dev/null || true

rollback() {
  echo "[ROLLBACK] Une erreur est survenue. Restauration de la configuration APT."
  mv /etc/apt/sources.list.bak /etc/apt/sources.list 2>/dev/null || true
  rm -f "$GRAFANA_KEY" "$ELASTIC_KEY" 2>/dev/null || true
  rm -f /etc/apt/sources.list.d/grafana.list 2>/dev/null || true
  rm -f /etc/apt/sources.list.d/elastic-7.x.list 2>/dev/null || true
  echo "[ROLLBACK] Terminé. Script arrêté."
  exit 1
}

trap rollback ERR

########################
# FONCTIONS UTILES     #
########################

die() {
    echo "[ERROR] $1" >&2
    exit 1
}

export DEBIAN_FRONTEND=noninteractive

ask_user() {
    read -p "$1 (y/n): " response
    case "$response" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

already_installed() {
    dpkg -s "$1" &>/dev/null
    return $?
}

########################
# 1) PACKAGES DE BASE  #
########################
install_base_packages() {
    echo "--- Mise à jour du système et installation des dépendances de base ---"
    apt update && apt upgrade -y
    apt install -y gnupg gnupg2 python3 python3-pip python3-venv \
                   curl wget lsb-release apt-transport-https \
                   software-properties-common iptables ufw mariadb-server
}

########################
# 2) IMPORT GPG/GRAFANA
########################
setup_grafana_repo() {
    echo "--- Configuration du dépôt Grafana (clé GPG dans /etc/apt/keyrings) ---"
    mkdir -p "$KEYRINGS_DIR"
    wget -qO "$GRAFANA_KEY" https://packages.grafana.com/gpg.key
    cat <<EOF > /etc/apt/sources.list.d/grafana.list
deb [signed-by=$GRAFANA_KEY] https://packages.grafana.com/oss/deb stable main
EOF
}

########################
# 3) IMPORT GPG/ELASTIC
########################
setup_elastic_repo() {
    echo "--- Configuration du dépôt Elastic (clé GPG dans /etc/apt/keyrings) ---"
    mkdir -p "$KEYRINGS_DIR"
    wget -qO "$ELASTIC_KEY" https://artifacts.elastic.co/GPG-KEY-elasticsearch
    cat <<EOF > /etc/apt/sources.list.d/elastic-7.x.list
deb [signed-by=$ELASTIC_KEY] https://artifacts.elastic.co/packages/7.x/apt stable main
EOF
}

########################
# FIREWALL (UFW)       #
########################
configure_firewall() {
    if ask_user "Voulez-vous configurer un firewall UFW avec quelques règles de base ?"; then
        if ! already_installed ufw; then
            apt install -y ufw
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
# MARIADB CONFIG       #
########################
configure_mariadb() {
    echo "--- Configuration du mot de passe root MySQL ---"
    # Tente de se connecter en tant que root sans mot de passe
    if mysql -u root -e "SELECT 1" &>/dev/null; then
        mysql -u root <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
FLUSH PRIVILEGES;
EOF
    # Si la connexion échoue, essaie d'utiliser les credentials de debian-sys-maint
    elif [ -f /etc/mysql/debian.cnf ]; then
        echo "Utilisation des identifiants debian-sys-maint pour configurer root"
        DEBIAN_ROOT_PASS=$(awk '/password/ {print $3; exit}' /etc/mysql/debian.cnf)
        mysql --defaults-file=/etc/mysql/debian.cnf <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
FLUSH PRIVILEGES;
EOF
    else
        die "Impossible de se connecter à MySQL en tant que root. Veuillez vérifier la configuration actuelle."
    fi

    echo "--- Création base et user Zabbix ---"
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" <<EOF
CREATE DATABASE IF NOT EXISTS ${ZABBIX_DB} CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER IF NOT EXISTS '${ZABBIX_DB_USER}'@'localhost' IDENTIFIED BY '${ZABBIX_DB_PASS}';
GRANT ALL PRIVILEGES ON ${ZABBIX_DB}.* TO '${ZABBIX_DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF
}


########################
# ZABBIX DEPENDANCES   #
########################
fix_dependencies_zabbix() {
    if ! grep -q "bullseye-security" /etc/apt/sources.list ; then
        echo "deb http://security.debian.org/debian-security bullseye-security main" >> /etc/apt/sources.list
    fi
    apt update
    apt install -y libssl1.1 libldap-2.4-2 || true
}

########################
# INSTALL ZABBIX       #
########################
install_zabbix() {
    if ask_user "Voulez-vous installer Zabbix Server + Agent ?"; then
        if ! already_installed zabbix-server-mysql; then
            fix_dependencies_zabbix

            echo "--- Installation de Zabbix Server + Agent ---"
            wget -O /tmp/zabbix-release.deb \
              https://repo.zabbix.com/zabbix/6.0/debian/pool/main/z/zabbix-release/zabbix-release_6.0-4+debian11_all.deb
            dpkg -i /tmp/zabbix-release.deb
            apt update
            apt install -y zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf zabbix-agent
            apt install -y zabbix-sql-scripts

            # Import du schéma SQL
            SCHEMA_FILE=$(find /usr/share/zabbix-sql-scripts -name "schema.sql.gz" -o -name "create.sql.gz" 2>/dev/null | head -n 1)
            if [ -n "$SCHEMA_FILE" ]; then
              zcat "$SCHEMA_FILE" | mysql -u "${ZABBIX_DB_USER}" -p"${ZABBIX_DB_PASS}" "${ZABBIX_DB}" || \
                echo "Échec import schéma. Vérifiez user/pass MySQL."
            fi
        fi

        # Configuration PHP et Zabbix
        sed -i "s|.*date.timezone =.*|php_value date.timezone ${ZABBIX_SERVER_TIMEZONE}|" /etc/apache2/conf-available/zabbix.conf || true
        sed -i "s|^# DBPassword=.*|DBPassword=${ZABBIX_DB_PASS}|" /etc/zabbix/zabbix_server.conf
        sed -i "s|^# DBUser=.*|DBUser=${ZABBIX_DB_USER}|" /etc/zabbix/zabbix_server.conf
        sed -i "s|^# DBName=.*|DBName=${ZABBIX_DB}|" /etc/zabbix/zabbix_server.conf

        # Création du répertoire pour le fichier PID de Zabbix
        mkdir -p /run/zabbix
        chown zabbix:zabbix /run/zabbix

        # Recharger la configuration systemd et démarrer les services
        systemctl daemon-reload
        systemctl enable zabbix-server zabbix-agent apache2
        systemctl restart zabbix-server zabbix-agent apache2

        # Vérification du démarrage de Zabbix Server
        if systemctl is-active --quiet zabbix-server; then
            echo "✅ Zabbix installé et démarré correctement. http://<IP>/zabbix (Admin / zabbix)."
        else
            echo "[ERROR] Zabbix Server ne démarre pas. Veuillez consulter 'systemctl status zabbix-server' et 'journalctl -xeu zabbix-server.service'."
        fi
    fi
}

########################
# INSTALL GRAFANA      #
########################
install_grafana() {
    if ask_user "Voulez-vous installer Grafana ?"; then
        if ! already_installed grafana; then
            setup_grafana_repo
            apt update
            apt install -y grafana
            systemctl enable --now grafana-server
        fi
        sed -i "s/^;admin_user = .*/admin_user = ${GRAFANA_ADMIN_USER}/" /etc/grafana/grafana.ini
        sed -i "s/^;admin_password = .*/admin_password = ${GRAFANA_ADMIN_PASS}/" /etc/grafana/grafana.ini
        systemctl restart grafana-server
        echo "✅ Grafana installé : http://<IP>:3000 (user=${GRAFANA_ADMIN_USER}, pass=${GRAFANA_ADMIN_PASS})."
    fi
}

########################
# INSTALL FAIL2BAN     #
########################
install_fail2ban() {
    if ask_user "Voulez-vous installer et configurer Fail2ban ?"; then
        if ! already_installed fail2ban; then
            apt install -y fail2ban
        fi
        cat <<EOF > /etc/fail2ban/jail.local
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
[sshd]
enabled = true
logpath = /var/log/auth.log
EOF
        systemctl enable --now fail2ban
        echo "✅ Fail2ban ok."
    fi
}

########################
# INSTALL LYNIS        #
########################
install_lynis() {
    if ask_user "Voulez-vous installer Lynis pour l'audit ?"; then
        if ! already_installed lynis; then
            apt install -y lynis
        fi
        echo "✅ Lynis installé."
    fi
}

########################
# INSTALL VULNERS      #
########################
install_vulners() {
    if ask_user "Voulez-vous installer Vulners ?"; then
        if [ ! -d "/opt/vulners-venv" ]; then
            python3 -m venv /opt/vulners-venv
            source /opt/vulners-venv/bin/activate
            pip install --upgrade pip vulners
            deactivate
        fi
        echo "✅ Vulners installé. (env /opt/vulners-venv)"
    fi
}

########################
# INSTALL ELK          #
########################
install_elk() {
    if ask_user "Voulez-vous installer ELK ?"; then
        setup_elastic_repo
        apt update
        if ! already_installed elasticsearch; then
            apt install -y elasticsearch
        fi
        if ! already_installed logstash; then
            apt install -y logstash
        fi
        if ! already_installed kibana; then
            apt install -y kibana
        fi

        systemctl enable elasticsearch logstash kibana
        systemctl start elasticsearch logstash kibana

        if [ "$ENABLE_ELASTIC_SECURITY" = true ]; then
            echo "Activation xpack security..."
            sed -i '/^#\?xpack.security.enabled:/d' /etc/elasticsearch/elasticsearch.yml
            echo "xpack.security.enabled: true" >> /etc/elasticsearch/elasticsearch.yml
            systemctl restart elasticsearch
            sleep 10
            echo "Génération des mots de passe ES..."
            /usr/share/elasticsearch/bin/elasticsearch-setup-passwords auto -b > "$ES_PASSWORDS_FILE" 2>/dev/null
            cat "$ES_PASSWORDS_FILE"
            NEW_ELASTIC_PASS=$(grep "PASSWORD elastic =" "$ES_PASSWORDS_FILE" | awk '{print $4}')
            if [ -n "$NEW_ELASTIC_PASS" ]; then
                sed -i "s|^#\?elasticsearch.username:.*|elasticsearch.username: \"$KIBANA_ELASTIC_USER\"|" /etc/kibana/kibana.yml
                sed -i "s|^#\?elasticsearch.password:.*|elasticsearch.password: \"$NEW_ELASTIC_PASS\"|" /etc/kibana/kibana.yml
                sed -i "s|^#\?elasticsearch.hosts:.*|elasticsearch.hosts: [\"http://localhost:9200\"]|" /etc/kibana/kibana.yml
                systemctl restart kibana
            fi
            echo "✅ Sécurité ES activée."
        fi

        echo "✅ ELK installé : http://<IP>:5601"
    fi
}

########################
# INSTALL SURICATA     #
########################
install_suricata() {
    if ask_user "Voulez-vous installer Suricata (IDS/IPS) ?"; then
        if ! already_installed suricata; then
            apt install -y suricata
            systemctl enable suricata
            systemctl stop suricata
            systemctl start suricata
            echo "✅ Suricata installé."
        fi

        if ask_user "Intégrer Suricata à ELK (Filebeat) ?"; then
            if ! already_installed filebeat; then
                apt install -y filebeat
            fi
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
    install_base_packages
    configure_firewall
    configure_mariadb
    install_zabbix
    install_grafana
    install_fail2ban
    install_lynis
    install_vulners
    install_elk
    install_suricata
    detect_ip
    echo "=== Installation terminée ! ==="
    echo "---------------------------------"
    echo "Infos / Credentials :"
    echo "  - MySQL root      : $MYSQL_ROOT_PASSWORD"
    echo "  - Zabbix DB       : $ZABBIX_DB (user=$ZABBIX_DB_USER / pass=$ZABBIX_DB_PASS)"
    echo "  - Zabbix Frontend : http://<IP>/zabbix (Admin / zabbix)"
    echo "  - Grafana         : http://<IP>:3000 (user=$GRAFANA_ADMIN_USER / pass=$GRAFANA_ADMIN_PASS)"
    echo "  - ELK / Kibana    : http://<IP>:5601"
    echo "    -> Mots de passe ES (si activée) dans : $ES_PASSWORDS_FILE"
    echo "Logs d'installation : $LOG_FILE"
}

main
