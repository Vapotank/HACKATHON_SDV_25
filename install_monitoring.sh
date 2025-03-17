#!/bin/bash
# Désactivation de errexit pour permettre la poursuite en cas d'erreur
set -o pipefail
set -o errtrace  # Propagation des erreurs dans les fonctions et traps

################################################################################
# Script d'installation complet : Zabbix, Grafana, Fail2ban, Lynis, Vulners,
# ELK (Elasticsearch, Logstash, Kibana), Suricata (optionnel)
#
# Ce script enregistre les erreurs rencontrées dans un tableau global ERRORS et
# tente de les corriger à la fin de l'exécution via la fonction repair_errors.
#
# Auteur  : VAPOTANK (amélioré pour gestion d'erreurs)
# Date    : 2025-03-17
# Usage   : sudo ./install_monitoring.sh
#
# Codes de sortie utilisés :
#    1 : Erreur générique
#    2 : Erreur APT/dépendance
#    3 : Erreur MySQL/MariaDB
#    4 : Erreur Zabbix (ex. schéma absent)
#    5 : Erreur de configuration système
################################################################################

LOG_FILE="/var/log/auto_monitoring.log"
declare -a ERRORS=()  # Tableau global pour enregistrer les erreurs

# Fonctions de log
log_info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $1" | tee -a "$LOG_FILE" >&2
}

# Enregistre une erreur sans arrêter le script
record_error() {
    ERRORS+=("$1")
    log_error "$1"
}

# Fonction pour exécuter une commande et enregistrer une erreur en cas d'échec
run_cmd() {
    log_info "Exécution : $*"
    "$@"
    local code=$?
    if [ $code -ne 0 ]; then
        record_error "La commande '$*' a échoué avec le code $code."
    fi
    return $code
}

########################
# ROLLBACK / REPARATION#
########################

rollback() {
    log_info "[ROLLBACK] Début du rollback granulaire..."
    if [ -f /etc/apt/sources.list.bak ]; then
        mv /etc/apt/sources.list.bak /etc/apt/sources.list
        log_info "[ROLLBACK] /etc/apt/sources.list restauré."
    fi
    rm -f "$GRAFANA_KEY" "$ELASTIC_KEY"
    rm -f /etc/apt/sources.list.d/grafana.list /etc/apt/sources.list.d/elastic-7.x.list
    log_info "[ROLLBACK] Fichiers de dépôt et clés supprimés."
    systemctl stop zabbix-server zabbix-agent apache2 2>/dev/null || true
    systemctl disable zabbix-server zabbix-agent apache2 2>/dev/null || true
    apt-get remove -y zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf zabbix-agent zabbix-sql-scripts 2>/dev/null || true
    rm -rf /run/zabbix
    log_info "[ROLLBACK] Rollback terminé. Veuillez vérifier manuellement l'état du système."
}

repair_errors() {
    log_info "Tentative de réparation automatique des erreurs..."
    # Exemple 1 : Import du schéma Zabbix si absent
    local table_count
    table_count=$(mysql -u "${ZABBIX_DB_USER}" -p"${ZABBIX_DB_PASS}" "${ZABBIX_DB}" -e "SHOW TABLES LIKE 'users';" | wc -l)
    if [ "$table_count" -lt 2 ]; then
        log_info "Le schéma Zabbix est absent. Tentative d'importation..."
        import_zabbix_schema
    fi
    # Exemple 2 : Redémarrage du service Zabbix Server si inactif
    if ! systemctl is-active --quiet zabbix-server; then
        log_info "Zabbix Server n'est pas actif. Tentative de redémarrage..."
        run_cmd systemctl restart zabbix-server
    fi

    if systemctl is-active --quiet zabbix-server; then
        log_info "Zabbix Server fonctionne après réparation."
    else
        log_error "La réparation automatique de Zabbix Server a échoué."
    fi

    # Afficher le résumé des erreurs enregistrées
    if [ ${#ERRORS[@]} -gt 0 ]; then
        log_error "Erreurs restantes après tentative de réparation :"
        for err in "${ERRORS[@]}"; do
            log_error "$err"
        done
    else
        log_info "Aucune erreur restante après réparation."
    fi
}

########################
# VARIABLES DE CONFIG  #
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

# Dossier pour les clés GPG
KEYRINGS_DIR="/etc/apt/keyrings"
GRAFANA_KEY="$KEYRINGS_DIR/grafana.gpg"
ELASTIC_KEY="$KEYRINGS_DIR/elastic.gpg"

########################
# FONCTIONS UTILES     #
########################

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

########################
# IMPORTATION DU SCHÉMA #
########################

import_zabbix_schema() {
    local schema_file=""
    for file in /usr/share/doc/zabbix-server-mysql/schema.sql.gz /usr/share/doc/zabbix-server-mysql/create.sql.gz; do
         if [ -f "$file" ]; then
              schema_file="$file"
              break
         fi
    done
    if [ -n "$schema_file" ]; then
         log_info "Fichier de schéma trouvé : $schema_file. Importation en cours..."
         sudo zcat "$schema_file" | mysql -u "${ZABBIX_DB_USER}" -p"${ZABBIX_DB_PASS}" "${ZABBIX_DB}"
         if [ $? -eq 0 ]; then
             log_info "Schéma Zabbix importé avec succès."
         else
             record_error "L'importation du schéma Zabbix a échoué."
         fi
    else
         record_error "Aucun fichier de schéma Zabbix trouvé. Vérifiez l'installation de zabbix-server-mysql."
    fi
}

check_zabbix_schema() {
   log_info "Vérification de l'importation du schéma Zabbix..."
   local table_count
   table_count=$(mysql -u "${ZABBIX_DB_USER}" -p"${ZABBIX_DB_PASS}" "${ZABBIX_DB}" -e "SHOW TABLES LIKE 'users';" | wc -l)
   # La première ligne est l'en-tête ; si count < 2, aucune table trouvée.
   if [ "$table_count" -lt 2 ]; then
       log_info "Le schéma Zabbix semble absent. Importation..."
       import_zabbix_schema
   else
       log_info "Le schéma Zabbix est présent."
   fi
}

########################
# INSTALLATION DE BASE #
########################
install_base_packages() {
    log_info "Mise à jour du système et installation des dépendances de base..."
    run_cmd apt update
    run_cmd apt upgrade -y
    run_cmd apt install -y gnupg gnupg2 python3 python3-pip python3-venv \
                   curl wget lsb-release apt-transport-https \
                   software-properties-common iptables ufw mariadb-server
    log_info "Packages de base installés avec succès."
}

########################
# REPOS & CLÉS GPG     #
########################
setup_grafana_repo() {
    log_info "Configuration du dépôt Grafana..."
    run_cmd mkdir -p "$KEYRINGS_DIR"
    run_cmd wget -qO "$GRAFANA_KEY" https://packages.grafana.com/gpg.key
    cat <<EOF > /etc/apt/sources.list.d/grafana.list
deb [signed-by=$GRAFANA_KEY] https://packages.grafana.com/oss/deb stable main
EOF
    log_info "Dépôt Grafana configuré."
}

setup_elastic_repo() {
    log_info "Configuration du dépôt Elastic..."
    run_cmd mkdir -p "$KEYRINGS_DIR"
    run_cmd wget -qO "$ELASTIC_KEY" https://artifacts.elastic.co/GPG-KEY-elasticsearch
    cat <<EOF > /etc/apt/sources.list.d/elastic-7.x.list
deb [signed-by=$ELASTIC_KEY] https://artifacts.elastic.co/packages/7.x/apt stable main
EOF
    log_info "Dépôt Elastic configuré."
}

########################
# CONFIGURATION FIREWALL
########################
configure_firewall() {
    if ask_user "Configurer le firewall UFW avec des règles de base ?"; then
        if ! already_installed ufw; then
            run_cmd apt install -y ufw
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
    else
        log_info "Configuration du firewall ignorée."
    fi
}

########################
# CONFIGURATION MARIADB#
########################
configure_mariadb() {
    log_info "Configuration du mot de passe root MySQL..."
    if mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT 1" &>/dev/null; then
        log_info "Connexion à MySQL en tant que root réussie."
    else
        record_error "Impossible de se connecter à MySQL en tant que root avec le mot de passe '${MYSQL_ROOT_PASSWORD}'."
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

########################
# DÉPENDANCES ZABBIX   #
########################
fix_dependencies_zabbix() {
    if ! grep -q "bullseye-security" /etc/apt/sources.list; then
        echo "deb http://security.debian.org/debian-security bullseye-security main" >> /etc/apt/sources.list
    fi
    run_cmd apt update
    run_cmd apt install -y libssl1.1 libldap-2.4-2
}

########################
# INSTALLATION DE ZABBIX
########################
install_zabbix() {
    if ask_user "Installer Zabbix Server + Agent ?"; then
        if ! already_installed zabbix-server-mysql; then
            fix_dependencies_zabbix
            log_info "Téléchargement et installation de Zabbix..."
            run_cmd wget -O /tmp/zabbix-release.deb https://repo.zabbix.com/zabbix/6.0/debian/pool/main/z/zabbix-release/zabbix-release_6.0-4+debian11_all.deb
            run_cmd dpkg -i /tmp/zabbix-release.deb
            run_cmd apt update
            run_cmd apt install -y zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf zabbix-agent
            run_cmd apt install -y zabbix-sql-scripts
        fi

        # Vérification et import du schéma si nécessaire
        check_zabbix_schema

        log_info "Mise à jour de la configuration de Zabbix..."
        run_cmd sed -i "s|.*date.timezone =.*|php_value date.timezone ${ZABBIX_SERVER_TIMEZONE}|" /etc/apache2/conf-available/zabbix.conf
        run_cmd sed -i "s|^# DBPassword=.*|DBPassword=${ZABBIX_DB_PASS}|" /etc/zabbix/zabbix_server.conf
        run_cmd sed -i "s|^# DBUser=.*|DBUser=${ZABBIX_DB_USER}|" /etc/zabbix/zabbix_server.conf
        run_cmd sed -i "s|^# DBName=.*|DBName=${ZABBIX_DB}|" /etc/zabbix/zabbix_server.conf
        if ! grep -q "^DBHost=" /etc/zabbix/zabbix_server.conf; then
            echo "DBHost=localhost" | sudo tee -a /etc/zabbix/zabbix_server.conf >/dev/null
            log_info "DBHost ajouté dans zabbix_server.conf."
        fi

        run_cmd sudo mkdir -p /run/zabbix
        run_cmd sudo chown -R zabbix:zabbix /run/zabbix

        run_cmd systemctl daemon-reload
        run_cmd systemctl enable zabbix-server zabbix-agent apache2
        run_cmd systemctl restart zabbix-server zabbix-agent apache2
        sleep 5

        if systemctl is-active --quiet zabbix-server; then
            log_info "Zabbix installé et démarré correctement. Accédez à http://<IP>/zabbix (Admin / zabbix)."
        else
            record_error "Zabbix Server ne démarre pas. Consultez 'sudo systemctl status zabbix-server' et 'sudo journalctl -xeu zabbix-server.service'."
        fi
    fi
}

########################
# INSTALLATION DE GRAFANA
########################
install_grafana() {
    if ask_user "Installer Grafana ?"; then
        if ! already_installed grafana; then
            setup_grafana_repo
            run_cmd apt update
            run_cmd apt install -y grafana
            run_cmd systemctl enable --now grafana-server
        fi
        run_cmd sed -i "s/^;admin_user = .*/admin_user = ${GRAFANA_ADMIN_USER}/" /etc/grafana/grafana.ini
        run_cmd sed -i "s/^;admin_password = .*/admin_password = ${GRAFANA_ADMIN_PASS}/" /etc/grafana/grafana.ini
        run_cmd systemctl restart grafana-server
        log_info "Grafana installé : http://<IP>:3000 (user=${GRAFANA_ADMIN_USER}, pass=${GRAFANA_ADMIN_PASS})."
    fi
}

########################
# INSTALLATION FAIL2BAN
########################
install_fail2ban() {
    if ask_user "Installer et configurer Fail2ban ?"; then
        if ! already_installed fail2ban; then
            run_cmd apt install -y fail2ban
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
        log_info "Fail2ban configuré."
        run_cmd systemctl enable --now fail2ban
    fi
}

########################
# INSTALLATION DE LYNIS
########################
install_lynis() {
    if ask_user "Installer Lynis pour l'audit ?"; then
        if ! already_installed lynis; then
            run_cmd apt install -y lynis
        fi
        log_info "Lynis installé."
    fi
}

########################
# INSTALLATION DE VULNERS
########################
install_vulners() {
    if ask_user "Installer Vulners ?"; then
        if [ ! -d "/opt/vulners-venv" ]; then
            run_cmd python3 -m venv /opt/vulners-venv
            run_cmd source /opt/vulners-venv/bin/activate
            run_cmd pip install --upgrade pip vulners
            run_cmd deactivate
        fi
        log_info "Vulners installé dans l'environnement /opt/vulners-venv."
    fi
}

########################
# INSTALLATION DE ELK
########################
install_elk() {
    if ask_user "Installer ELK ?"; then
        setup_elastic_repo
        run_cmd apt update
        if ! already_installed elasticsearch; then
            run_cmd apt install -y elasticsearch
        fi
        if ! already_installed logstash; then
            run_cmd apt install -y logstash
        fi
        if ! already_installed kibana; then
            run_cmd apt install -y kibana
        fi

        run_cmd systemctl enable elasticsearch logstash kibana
        run_cmd systemctl start elasticsearch logstash kibana

        if [ "$ENABLE_ELASTIC_SECURITY" = true ]; then
            log_info "Activation de la sécurité xpack pour Elasticsearch..."
            run_cmd sed -i '/^#\?xpack.security.enabled:/d' /etc/elasticsearch/elasticsearch.yml
            echo "xpack.security.enabled: true" | tee -a /etc/elasticsearch/elasticsearch.yml >/dev/null
            run_cmd systemctl restart elasticsearch
            sleep 10
            log_info "Génération des mots de passe pour Elasticsearch..."
            run_cmd /usr/share/elasticsearch/bin/elasticsearch-setup-passwords auto -b > "$ES_PASSWORDS_FILE" 2>/dev/null
            cat "$ES_PASSWORDS_FILE" 2>/dev/null
            NEW_ELASTIC_PASS=$(grep "PASSWORD elastic =" "$ES_PASSWORDS_FILE" | awk '{print $4}')
            if [ -n "$NEW_ELASTIC_PASS" ]; then
                run_cmd sed -i "s|^#\?elasticsearch.username:.*|elasticsearch.username: \"$KIBANA_ELASTIC_USER\"|" /etc/kibana/kibana.yml
                run_cmd sed -i "s|^#\?elasticsearch.password:.*|elasticsearch.password: \"$NEW_ELASTIC_PASS\"|" /etc/kibana/kibana.yml
                run_cmd sed -i "s|^#\?elasticsearch.hosts:.*|elasticsearch.hosts: [\"http://localhost:9200\"]|" /etc/kibana/kibana.yml
                run_cmd systemctl restart kibana
            else
                record_error "Impossible de récupérer le mot de passe pour l'utilisateur elastic."
            fi
            log_info "Sécurité Elasticsearch activée."
        fi
        log_info "ELK installé : Accès Kibana via http://<IP>:5601"
    fi
}

########################
# INSTALLATION DE SURICATA
########################
install_suricata() {
    if ask_user "Installer Suricata (IDS/IPS) ?"; then
        if ! already_installed suricata; then
            run_cmd apt install -y suricata
            run_cmd systemctl enable suricata
            run_cmd systemctl stop suricata
            run_cmd systemctl start suricata
            log_info "Suricata installé."
        fi

        if ask_user "Intégrer Suricata à ELK via Filebeat ?"; then
            if ! already_installed filebeat; then
                run_cmd apt install -y filebeat
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
            log_info "Fichier de configuration Filebeat créé."
            run_cmd systemctl enable filebeat
            run_cmd systemctl restart filebeat
            log_info "Intégration Suricata → ELK via Filebeat activée."
        fi
    fi
}

########################
# DÉTECTION D'IP       #
########################
detect_ip() {
    log_info "Détection de l'adresse IP du serveur :"
    ip addr show | grep 'inet ' | awk '{print $2}' | tee -a "$LOG_FILE"
}

########################
# MAIN                 #
########################
main() {
    log_info "=== Début de l'installation du monitoring complet ==="
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
    log_info "=== Installation terminée ! ==="
    log_info "---------------------------------"
    log_info "Infos / Credentials :"
    log_info "  - MySQL root      : $MYSQL_ROOT_PASSWORD"
    log_info "  - Zabbix DB       : $ZABBIX_DB (user=$ZABBIX_DB_USER / pass=$ZABBIX_DB_PASS)"
    log_info "  - Zabbix Frontend : http://<IP>/zabbix (Admin / zabbix)"
    log_info "  - Grafana         : http://<IP>:3000 (user=$GRAFANA_ADMIN_USER / pass=$GRAFANA_ADMIN_PASS)"
    log_info "  - ELK / Kibana    : http://<IP>:5601"
    log_info "    -> Mots de passe ES (si activée) dans : $ES_PASSWORDS_FILE"
    log_info "Logs d'installation : $LOG_FILE"

    # Si des erreurs ont été enregistrées, tenter la réparation
    if [ ${#ERRORS[@]} -gt 0 ]; then
        log_error "Des erreurs ont été rencontrées pendant l'installation. Tentative de réparation..."
        repair_errors
    else
        log_info "Aucune erreur majeure rencontrée."
    fi
}

main
