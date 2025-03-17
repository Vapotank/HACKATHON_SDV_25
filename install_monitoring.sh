#!/bin/bash
set -o pipefail
set -o errtrace

################################################################################
# Script d'installation pour Debian 12 (Bookworm) : Zabbix 7.0 (Serveur + Frontend),
# Grafana, ELK, Suricata, etc.
# Gestion des clés GPG et dépôts pour éviter les erreurs apt-get update.
# L'installation de l'agent Zabbix est retirée.
#
# Auteur  : VAPOTANK (modifié pour Debian 12 et Zabbix 7.0)
# Date    : 2025-03-18
# Usage   : sudo ./install_monitoring.sh
################################################################################

LOG_FILE="/var/log/auto_monitoring.log"
declare -a ERRORS=()

# ------------------------------------------------------------------------------
#                            FONCTIONS DE LOG
# ------------------------------------------------------------------------------
log_info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $1" | tee -a "$LOG_FILE"
}
log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $1" | tee -a "$LOG_FILE" >&2
}
record_error() {
    ERRORS+=("$1")
    log_error "$1"
}
run_cmd() {
    log_info "Exécution : $*"
    "$@"
    local code=$?
    if [ $code -ne 0 ]; then
        record_error "La commande '$*' a échoué avec le code $code."
    fi
    return $code
}

# ------------------------------------------------------------------------------
#                       FONCTION DE RÉPARATION
# ------------------------------------------------------------------------------
repair_errors() {
    log_info "Tentative de réparation automatique des erreurs..."
    if systemctl is-active --quiet zabbix-server; then
        log_info "Zabbix Server semble actif."
    else
        log_info "Zabbix Server inactif. Tentative de redémarrage..."
        run_cmd systemctl restart zabbix-server
        if systemctl is-active --quiet zabbix-server; then
            log_info "Zabbix Server fonctionne après réparation."
        else
            log_error "La réparation automatique de Zabbix Server a échoué."
        fi
    fi

    if [ ${#ERRORS[@]} -gt 0 ]; then
        log_error "Erreurs restantes après tentative de réparation :"
        for err in "${ERRORS[@]}"; do
            log_error "$err"
        done
    else
        log_info "Aucune erreur restante après réparation."
    fi
}

# ------------------------------------------------------------------------------
#                       VARIABLES DE CONFIGURATION
# ------------------------------------------------------------------------------
MYSQL_ROOT_PASSWORD="root123"
ZABBIX_DB="zabbix"
ZABBIX_DB_USER="zabbix"
ZABBIX_DB_PASS="zabbix_pass"
ZABBIX_SERVER_TIMEZONE="Europe/Paris"

GRAFANA_ADMIN_USER="admin"
GRAFANA_ADMIN_PASS="admin123"

ENABLE_ELASTIC_SECURITY=true
ES_PASSWORDS_FILE="/tmp/es_passwords.txt"
KIBANA_ELASTIC_USER="elastic"

# Répertoire pour stocker les clés GPG
KEYRING_DIR="/usr/share/keyrings"

# ------------------------------------------------------------------------------
#                       FONCTIONS UTILES
# ------------------------------------------------------------------------------
ask_user() {
    local input
    read -p "$1 (y/n): " input
    case "$input" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}
already_installed() {
    dpkg -s "$1" &>/dev/null
    return $?
}

# ------------------------------------------------------------------------------
#                IMPORT DES CLÉS GPG & CONFIGURATION DES DÉPÔTS
# ------------------------------------------------------------------------------
import_grafana_key() {
    log_info "Import de la clé GPG Grafana et configuration du dépôt pour Debian 12..."
    mkdir -p "$KEYRING_DIR"
    run_cmd curl -fsSL https://packages.grafana.com/gpg.key \
         | gpg --dearmor \
         | tee "${KEYRING_DIR}/grafana-archive-keyring.gpg" >/dev/null
    cat <<EOF >/etc/apt/sources.list.d/grafana.list
deb [signed-by=${KEYRING_DIR}/grafana-archive-keyring.gpg] https://packages.grafana.com/oss/deb stable main
EOF
}
import_elastic_key() {
    log_info "Import de la clé GPG Elastic et configuration du dépôt pour Debian 12..."
    mkdir -p "$KEYRING_DIR"
    run_cmd curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch \
         | gpg --dearmor \
         | tee "${KEYRING_DIR}/elastic-archive-keyring.gpg" >/dev/null
    cat <<EOF >/etc/apt/sources.list.d/elastic-7.x.list
deb [signed-by=${KEYRING_DIR}/elastic-archive-keyring.gpg] https://artifacts.elastic.co/packages/7.x/apt stable main
EOF
}
import_zabbix_repo() {
    log_info "Installation du repository Zabbix 7.0 pour Debian 12..."
    # Téléchargement du paquet release pour Zabbix 7.0.
    run_cmd wget -4 -O /tmp/zabbix-release.deb \
      https://repo.zabbix.com/zabbix/7.0/debian/pool/main/z/zabbix-release/zabbix-release_7.0-1+debian12_all.deb
    if [ $? -eq 0 ]; then
        run_cmd dpkg -i /tmp/zabbix-release.deb
    else
        record_error "Échec du téléchargement de zabbix-release pour Debian 12 (7.0)."
    fi
}

# ------------------------------------------------------------------------------
#                         INSTALLATION DE BASE
# ------------------------------------------------------------------------------
install_base_packages() {
    log_info "=== Import des clés GPG & configuration des dépôts ==="
    run_cmd apt-get install -y gnupg curl wget lsb-release apt-transport-https software-properties-common

    # Retirer d'éventuelles références à Bullseye
    if [ -f /etc/apt/sources.list ]; then
        sed -i '/bullseye-security/d' /etc/apt/sources.list
        sed -i '/bullseye/d' /etc/apt/sources.list
    fi

    # Ajout du dépôt bookworm-security
    if ! grep -q "bookworm-security" /etc/apt/sources.list; then
        echo "deb http://security.debian.org/debian-security bookworm-security main contrib non-free-firmware" \
            >> /etc/apt/sources.list
    fi

    import_grafana_key
    import_elastic_key
    import_zabbix_repo

    for i in 1 2; do
        run_cmd apt-get update && break
        sleep 5
    done

    log_info "=== Installation des paquets de base ==="
    run_cmd apt-get upgrade -y
    run_cmd apt-get install -y python3 python3-pip python3-venv iptables ufw mariadb-server
    log_info "Paquets de base installés ou mis à jour avec succès."
}

# ------------------------------------------------------------------------------
#                          CONFIGURATION MARIADB
# ------------------------------------------------------------------------------
configure_mariadb() {
    log_info "Configuration du mot de passe root MySQL..."
    if ! mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT 1" &>/dev/null; then
        record_error "Impossible de se connecter à MySQL en tant que root (mot de passe = '${MYSQL_ROOT_PASSWORD}')."
    fi
    run_cmd mysql -u root -p"${MYSQL_ROOT_PASSWORD}" <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
FLUSH PRIVILEGES;
EOF
    log_info "Création de la base et de l'utilisateur Zabbix..."
    run_cmd mysql -u root -p"${MYSQL_ROOT_PASSWORD}" <<EOF
CREATE DATABASE IF NOT EXISTS ${ZABBIX_DB} CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER IF NOT EXISTS '${ZABBIX_DB_USER}'@'localhost' IDENTIFIED BY '${ZABBIX_DB_PASS}';
GRANT ALL PRIVILEGES ON ${ZABBIX_DB}.* TO '${ZABBIX_DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF
    log_info "Configuration de MariaDB terminée."
}

# ------------------------------------------------------------------------------
#              INSTALLATION DU SERVEUR ZABBIX (sans agent)
# ------------------------------------------------------------------------------
install_zabbix_server() {
    if ask_user "Installer Zabbix Server (sans agent) ?"; then
        if ! already_installed zabbix-server-mysql; then
            log_info "Installation des paquets zabbix-server-mysql et zabbix-frontend-php..."
            run_cmd apt-get update
            # On n'inclut pas zabbix-agent, zabbix-apache-conf ni zabbix-sql-scripts
            run_cmd apt-get install -y zabbix-server-mysql zabbix-frontend-php
        fi

        # Tentative d'import du schéma (vérifiez si un fichier existe dans /usr/share/doc/zabbix*)
        local schema_file
        schema_file="$(find /usr/share/doc/zabbix* -type f -name '*create.sql.gz' 2>/dev/null | head -n1)"
        if [ -n "$schema_file" ]; then
            log_info "Import du schéma Zabbix depuis : $schema_file"
            zcat "$schema_file" | mysql -u "${ZABBIX_DB_USER}" -p"${ZABBIX_DB_PASS}" "${ZABBIX_DB}"
        else
            record_error "Aucun fichier de schéma Zabbix trouvé. Veuillez importer le schéma manuellement."
        fi

        # Configuration Apache (si le fichier existe)
        if [ -f /etc/apache2/conf-available/zabbix.conf ]; then
            if ! grep -q "php_value date.timezone" /etc/apache2/conf-available/zabbix.conf; then
                echo "php_value date.timezone ${ZABBIX_SERVER_TIMEZONE}" >>/etc/apache2/conf-available/zabbix.conf
            else
                sed -i "s|php_value date.timezone .*|php_value date.timezone ${ZABBIX_SERVER_TIMEZONE}|" /etc/apache2/conf-available/zabbix.conf
            fi
        else
            record_error "Le fichier /etc/apache2/conf-available/zabbix.conf est introuvable. Veuillez créer ou adapter la configuration Apache."
        fi

        # Mise à jour de la configuration du serveur Zabbix (si le fichier existe)
        if [ -f /etc/zabbix/zabbix_server.conf ]; then
            sed -i "s|^# DBPassword=.*|DBPassword=${ZABBIX_DB_PASS}|" /etc/zabbix/zabbix_server.conf
            sed -i "s|^# DBUser=.*|DBUser=${ZABBIX_DB_USER}|" /etc/zabbix/zabbix_server.conf
            sed -i "s|^# DBName=.*|DBName=${ZABBIX_DB}|" /etc/zabbix/zabbix_server.conf
            if ! grep -q "^DBHost=" /etc/zabbix/zabbix_server.conf; then
                echo "DBHost=localhost" >> /etc/zabbix/zabbix_server.conf
            fi
        else
            record_error "Le fichier /etc/zabbix/zabbix_server.conf est introuvable. Veuillez le créer manuellement."
        fi

        # Création du répertoire /run/zabbix si l'utilisateur zabbix existe
        if id zabbix &>/dev/null; then
            mkdir -p /run/zabbix
            chown -R zabbix:zabbix /run/zabbix
        else
            record_error "L'utilisateur 'zabbix' n'existe pas. Vérifiez l'installation de zabbix-server-mysql."
        fi

        run_cmd systemctl daemon-reload
        run_cmd systemctl enable zabbix-server apache2
        run_cmd systemctl restart zabbix-server apache2

        sleep 3
        if systemctl is-active --quiet zabbix-server; then
            log_info "Zabbix Server est installé et démarré. Accédez à http://<IP>/zabbix (Admin / zabbix)."
        else
            record_error "Zabbix Server ne démarre pas. Veuillez consulter 'systemctl status zabbix-server'."
        fi
    fi
}

# ------------------------------------------------------------------------------
#                         INSTALLATION GRAFANA
# ------------------------------------------------------------------------------
install_grafana() {
    if ask_user "Installer Grafana ?"; then
        if ! already_installed grafana; then
            run_cmd apt-get update
            run_cmd apt-get install -y grafana
            run_cmd systemctl enable --now grafana-server
        fi
        if [ -f /etc/grafana/grafana.ini ]; then
            sed -i "s|^;admin_user = .*|admin_user = ${GRAFANA_ADMIN_USER}|" /etc/grafana/grafana.ini
            sed -i "s|^;admin_password = .*|admin_password = ${GRAFANA_ADMIN_PASS}|" /etc/grafana/grafana.ini
            run_cmd systemctl restart grafana-server
        else
            record_error "Le fichier /etc/grafana/grafana.ini est introuvable. Vérifiez l'installation de Grafana."
        fi
        log_info "Grafana installé : http://<IP>:3000 (user=${GRAFANA_ADMIN_USER}, pass=${GRAFANA_ADMIN_PASS})."
    fi
}

# ------------------------------------------------------------------------------
#                         INSTALLATION ELK
# ------------------------------------------------------------------------------
install_elk() {
    if ask_user "Installer ELK (Elasticsearch, Logstash, Kibana) ?"; then
        run_cmd apt-get update
        if ! already_installed elasticsearch; then
            run_cmd apt-get install -y elasticsearch
        fi
        if ! already_installed logstash; then
            run_cmd apt-get install -y logstash
        fi
        if ! already_installed kibana; then
            run_cmd apt-get install -y kibana
        fi
        run_cmd systemctl enable elasticsearch logstash kibana
        run_cmd systemctl start elasticsearch logstash kibana

        if [ "$ENABLE_ELASTIC_SECURITY" = true ]; then
            log_info "Activation de xpack.security sur Elasticsearch..."
            sed -i '/^#\?xpack.security.enabled:/d' /etc/elasticsearch/elasticsearch.yml
            echo "xpack.security.enabled: true" >> /etc/elasticsearch/elasticsearch.yml
            run_cmd systemctl restart elasticsearch
            sleep 10

            run_cmd /usr/share/elasticsearch/bin/elasticsearch-setup-passwords auto -b > "$ES_PASSWORDS_FILE" 2>/dev/null
            cat "$ES_PASSWORDS_FILE" 2>/dev/null

            local NEW_ELASTIC_PASS
            NEW_ELASTIC_PASS=$(grep "PASSWORD elastic =" "$ES_PASSWORDS_FILE" | awk '{print $4}')
            if [ -n "$NEW_ELASTIC_PASS" ]; then
                sed -i "s|^#\?elasticsearch.username:.*|elasticsearch.username: \"$KIBANA_ELASTIC_USER\"|" /etc/kibana/kibana.yml
                sed -i "s|^#\?elasticsearch.password:.*|elasticsearch.password: \"$NEW_ELASTIC_PASS\"|" /etc/kibana/kibana.yml
                sed -i "s|^#\?elasticsearch.hosts:.*|elasticsearch.hosts: [\"http://localhost:9200\"]|" /etc/kibana/kibana.yml
                run_cmd systemctl restart kibana
            else
                record_error "Impossible de récupérer le mot de passe elastic."
            fi
        fi
        log_info "ELK installé : Accédez à http://<IP>:5601"
    fi
}

# ------------------------------------------------------------------------------
#                         INSTALLATION SURICATA
# ------------------------------------------------------------------------------
install_suricata() {
    if ask_user "Installer Suricata (IDS/IPS) ?"; then
        if ! already_installed suricata; then
            run_cmd apt-get install -y suricata
            run_cmd systemctl enable suricata
            run_cmd systemctl restart suricata
            log_info "Suricata installé."
        fi
        if ask_user "Intégrer Suricata à ELK via Filebeat ?"; then
            if ! already_installed filebeat; then
                run_cmd apt-get install -y filebeat
            fi
            cat <<EOF >/etc/filebeat/filebeat.yml
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
  hosts: ["http://localhost:9200"]
EOF
            log_info "Fichier de configuration Filebeat créé."
            run_cmd systemctl enable filebeat
            run_cmd systemctl restart filebeat
            log_info "Intégration Suricata → ELK via Filebeat activée."
        fi
    fi
}

# ------------------------------------------------------------------------------
#                         CONFIGURATION DU FIREWALL (UFW)
# ------------------------------------------------------------------------------
configure_firewall() {
    if ask_user "Configurer le firewall UFW avec des règles de base ?"; then
        if ! already_installed ufw; then
            run_cmd apt-get install -y ufw
        fi
        run_cmd ufw default deny incoming
        run_cmd ufw default allow outgoing
        run_cmd ufw allow ssh
        run_cmd ufw allow 80/tcp
        run_cmd ufw allow 443/tcp
        run_cmd ufw allow 10050/tcp
        run_cmd ufw allow 10051/tcp
        run_cmd ufw allow 3000/tcp
        run_cmd ufw allow 5601/tcp
        run_cmd ufw allow 5044/tcp
        echo "y" | ufw enable
        log_info "Firewall UFW configuré et activé."
    fi
}

# ------------------------------------------------------------------------------
#                    INSTALLATION DES OUTILS SUPPLÉMENTAIRES
# ------------------------------------------------------------------------------
install_fail2ban() {
    if ask_user "Installer et configurer Fail2ban ?"; then
        if ! already_installed fail2ban; then
            run_cmd apt-get install -y fail2ban
        fi
        cat <<EOF >/etc/fail2ban/jail.local
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
[sshd]
enabled = true
logpath = /var/log/auth.log
EOF
        run_cmd systemctl enable --now fail2ban
        log_info "Fail2ban configuré."
    fi
}

install_lynis() {
    if ask_user "Installer Lynis pour l'audit ?"; then
        if ! already_installed lynis; then
            run_cmd apt-get install -y lynis
        fi
        log_info "Lynis installé."
    fi
}

install_vulners() {
    if ask_user "Installer Vulners ?"; then
        if [ ! -d "/opt/vulners-venv" ]; then
            run_cmd python3 -m venv /opt/vulners-venv
            source /opt/vulners-venv/bin/activate
            run_cmd pip install --upgrade pip vulners
            deactivate
        fi
        log_info "Vulners installé dans /opt/vulners-venv."
    fi
}

# ------------------------------------------------------------------------------
#                             DÉTECTION D'ADRESSES IP
# ------------------------------------------------------------------------------
detect_ip() {
    log_info "Adresses IP détectées :"
    ip addr show | grep 'inet ' | awk '{print $2}' | tee -a "$LOG_FILE"
}

# ------------------------------------------------------------------------------
#                                  MAIN
# ------------------------------------------------------------------------------
main() {
    log_info "=== Début de l'installation (Debian 12, Zabbix 7.0) ==="
    install_base_packages
    configure_mariadb
    configure_firewall
    install_zabbix_server
    install_grafana
    install_fail2ban
    install_lynis
    install_vulners
    install_elk
    install_suricata
    detect_ip

    log_info "=== Installation terminée ! ==="
    log_info "--------------------------------"
    log_info "Infos / Credentials :"
    log_info "  - MySQL root      : $MYSQL_ROOT_PASSWORD"
    log_info "  - Zabbix DB       : $ZABBIX_DB (user=$ZABBIX_DB_USER / pass=$ZABBIX_DB_PASS)"
    log_info "  - Zabbix Frontend : http://<IP>/zabbix (Admin / zabbix)"
    log_info "  - Grafana         : http://<IP>:3000 (user=$GRAFANA_ADMIN_USER / pass=$GRAFANA_ADMIN_PASS)"
    log_info "  - ELK / Kibana    : http://<IP>:5601"
    log_info "    -> Mots de passe ES (si activée) dans : $ES_PASSWORDS_FILE"
    log_info "Logs d'installation : $LOG_FILE"

    if [ ${#ERRORS[@]} -gt 0 ]; then
        log_error "Des erreurs ont été rencontrées. Tentative de réparation..."
        repair_errors
    else
        log_info "Aucune erreur majeure rencontrée."
    fi
}

main
