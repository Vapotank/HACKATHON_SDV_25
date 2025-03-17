#!/bin/bash
set -o errexit
set -o pipefail
set -o errtrace  # Propager les erreurs dans les fonctions et traps

################################################################################
# Script d'installation complet : Zabbix, Grafana, Fail2ban, Lynis, Vulners,
# ELK (Elasticsearch, Logstash, Kibana), Suricata (optionnel)
#
# - Journalisation détaillée et vérification des codes de sortie pour chaque commande
# - Gestion automatique des erreurs et rollback granulaire
# - Vérification et importation automatique du schéma Zabbix si absent
#
# Auteur  : VAPOTANK (amélioré)
# Date    : 2025-03-17
# Usage   : sudo ./install_monitoring.sh
#
# Codes de sortie utilisés :
#    1 : Erreur générique
#    2 : Erreur APT/dépendance
#    3 : Erreur MySQL/MariaDB
#    4 : Erreur Zabbix (par exemple, schéma non importé)
#    5 : Erreur de configuration système
################################################################################

LOG_FILE="/var/log/auto_monitoring.log"

# Fonctions de log
log_info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $1" | tee -a "$LOG_FILE" >&2
}

# Fonction de gestion des erreurs et sortie
error_exit() {
    local exit_code=$1
    shift
    log_error "$*"
    log_error "Conseil : Consultez $LOG_FILE pour plus de détails."
    rollback
    exit "$exit_code"
}

# Vérifie le code de sortie de la dernière commande
check_exit() {
    local cmd="$1"
    local code=$?
    if [ $code -ne 0 ]; then
        error_exit "$code" "La commande '$cmd' a échoué avec le code $code."
    fi
}

########################
# ROLLBACK / ERREUR    #
########################

rollback() {
    log_info "[ROLLBACK] Début du rollback granulaire..."
    if [ -f /etc/apt/sources.list.bak ]; then
        mv /etc/apt/sources.list.bak /etc/apt/sources.list
        log_info "[ROLLBACK] Fichier /etc/apt/sources.list restauré."
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

trap 'error_exit 1 "Une erreur inattendue est survenue."' ERR

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

export DEBIAN_FRONTEND=noninteractive

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

# Tente d'importer le schéma depuis un fichier connu
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
         sudo zcat "$schema_file" | mysql -u "${ZABBIX_DB_USER}" -p"${ZABBIX_DB_PASS}" "${ZABBIX_DB}" || error_exit 4 "Importation du schéma Zabbix a échoué."
         log_info "Schéma Zabbix importé avec succès."
    else
         error_exit 4 "Aucun fichier de schéma Zabbix trouvé. Veuillez installer zabbix-sql-scripts ou vérifier la documentation."
    fi
}

# Vérifie si la table 'users' (ou une table clé) existe
check_zabbix_schema() {
   log_info "Vérification de l'importation du schéma Zabbix..."
   local table_count
   table_count=$(mysql -u "${ZABBIX_DB_USER}" -p"${ZABBIX_DB_PASS}" "${ZABBIX_DB}" -e "SHOW TABLES LIKE 'users';" | wc -l)
   # La première ligne est l'en-tête ; si count < 2, aucune table trouvée.
   if [ "$table_count" -lt 2 ]; then
       log_info "Aucune table Zabbix détectée. Importation du schéma..."
       import_zabbix_schema
   else
       log_info "Le schéma Zabbix semble déjà importé."
   fi
}

########################
# INSTALLATION DE BASE #
########################
install_base_packages() {
    log_info "Mise à jour du système et installation des dépendances de base..."
    apt update || error_exit 2 "apt update a échoué."
    apt upgrade -y || error_exit 2 "apt upgrade a échoué."
    apt install -y gnupg gnupg2 python3 python3-pip python3-venv \
                   curl wget lsb-release apt-transport-https \
                   software-properties-common iptables ufw mariadb-server || \
                   error_exit 2 "Installation des packages de base a échoué."
    log_info "Packages de base installés avec succès."
}

########################
# REPOS & CLÉS GPG     #
########################
setup_grafana_repo() {
    log_info "Configuration du dépôt Grafana..."
    mkdir -p "$KEYRINGS_DIR" || error_exit 5 "Impossible de créer le dossier $KEYRINGS_DIR."
    wget -qO "$GRAFANA_KEY" https://packages.grafana.com/gpg.key || error_exit 2 "Téléchargement de la clé Grafana a échoué."
    cat <<EOF > /etc/apt/sources.list.d/grafana.list
deb [signed-by=$GRAFANA_KEY] https://packages.grafana.com/oss/deb stable main
EOF
    check_exit "Création du dépôt Grafana"
    log_info "Dépôt Grafana configuré."
}

setup_elastic_repo() {
    log_info "Configuration du dépôt Elastic..."
    mkdir -p "$KEYRINGS_DIR" || error_exit 5 "Impossible de créer le dossier $KEYRINGS_DIR."
    wget -qO "$ELASTIC_KEY" https://artifacts.elastic.co/GPG-KEY-elasticsearch || error_exit 2 "Téléchargement de la clé Elastic a échoué."
    cat <<EOF > /etc/apt/sources.list.d/elastic-7.x.list
deb [signed-by=$ELASTIC_KEY] https://artifacts.elastic.co/packages/7.x/apt stable main
EOF
    check_exit "Création du dépôt Elastic"
    log_info "Dépôt Elastic configuré."
}

########################
# CONFIGURATION FIREWALL
########################
configure_firewall() {
    if ask_user "Configurer le firewall UFW avec des règles de base ?"; then
        if ! already_installed ufw; then
            apt install -y ufw || error_exit 2 "L'installation d'UFW a échoué."
        fi
        ufw default deny incoming || error_exit 5 "La configuration de la politique entrante a échoué."
        ufw default allow outgoing || error_exit 5 "La configuration de la politique sortante a échoué."
        ufw allow ssh || error_exit 5 "L'ouverture du port SSH a échoué."
        ufw allow 80/tcp || error_exit 5 "L'ouverture du port 80 a échoué."
        ufw allow 443/tcp || error_exit 5 "L'ouverture du port 443 a échoué."
        ufw allow 10050/tcp || error_exit 5 "L'ouverture du port Zabbix Agent a échoué."
        ufw allow 10051/tcp || error_exit 5 "L'ouverture du port Zabbix Server a échoué."
        ufw allow 3000/tcp || error_exit 5 "L'ouverture du port Grafana a échoué."
        ufw allow 5601/tcp || error_exit 5 "L'ouverture du port Kibana a échoué."
        ufw allow 5044/tcp || error_exit 5 "L'ouverture du port Logstash a échoué."
        echo "y" | ufw enable || error_exit 5 "L'activation d'UFW a échoué."
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
        log_info "Connexion à MySQL en tant que root réussie avec le mot de passe fourni."
    else
        error_exit 3 "Impossible de se connecter à MySQL en tant que root avec le mot de passe '${MYSQL_ROOT_PASSWORD}'."
    fi

    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
FLUSH PRIVILEGES;
EOF
    check_exit "Modification du mot de passe root"
    
    log_info "Création de la base et de l'utilisateur Zabbix..."
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" <<EOF
CREATE DATABASE IF NOT EXISTS ${ZABBIX_DB} CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER IF NOT EXISTS '${ZABBIX_DB_USER}'@'localhost' IDENTIFIED BY '${ZABBIX_DB_PASS}';
GRANT ALL PRIVILEGES ON ${ZABBIX_DB}.* TO '${ZABBIX_DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF
    check_exit "Création de la base et de l'utilisateur Zabbix"
    log_info "Configuration de MariaDB terminée."
}

########################
# DÉPENDANCES ZABBIX   #
########################
fix_dependencies_zabbix() {
    if ! grep -q "bullseye-security" /etc/apt/sources.list; then
        echo "deb http://security.debian.org/debian-security bullseye-security main" >> /etc/apt/sources.list
        check_exit "Ajout du dépôt bullseye-security"
    fi
    apt update || error_exit 2 "apt update (bullseye-security) a échoué."
    apt install -y libssl1.1 libldap-2.4-2 || log_info "Installation partielle des dépendances Zabbix (libssl, libldap)"
}

########################
# INSTALLATION DE ZABBIX
########################
install_zabbix() {
    if ask_user "Installer Zabbix Server + Agent ?"; then
        if ! already_installed zabbix-server-mysql; then
            fix_dependencies_zabbix
            log_info "Téléchargement et installation de Zabbix..."
            wget -O /tmp/zabbix-release.deb https://repo.zabbix.com/zabbix/6.0/debian/pool/main/z/zabbix-release/zabbix-release_6.0-4+debian11_all.deb || error_exit 2 "Téléchargement de zabbix-release a échoué."
            dpkg -i /tmp/zabbix-release.deb || error_exit 2 "Installation de zabbix-release a échoué."
            apt update || error_exit 2 "apt update après installation de zabbix-release a échoué."
            apt install -y zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf zabbix-agent || error_exit 4 "Installation des packages Zabbix a échoué."
            apt install -y zabbix-sql-scripts || error_exit 4 "Installation de zabbix-sql-scripts a échoué."
        fi

        # Vérification et import du schéma si nécessaire
        check_zabbix_schema

        # Mise à jour de la configuration PHP (pour Zabbix Frontend)
        sed -i "s|.*date.timezone =.*|php_value date.timezone ${ZABBIX_SERVER_TIMEZONE}|" /etc/apache2/conf-available/zabbix.conf || log_error "Modification du timezone PHP pour Zabbix a échoué."
        sed -i "s|^# DBPassword=.*|DBPassword=${ZABBIX_DB_PASS}|" /etc/zabbix/zabbix_server.conf || log_error "Configuration DBPassword dans zabbix_server.conf a échoué."
        sed -i "s|^# DBUser=.*|DBUser=${ZABBIX_DB_USER}|" /etc/zabbix/zabbix_server.conf || log_error "Configuration DBUser dans zabbix_server.conf a échoué."
        sed -i "s|^# DBName=.*|DBName=${ZABBIX_DB}|" /etc/zabbix/zabbix_server.conf || log_error "Configuration DBName dans zabbix_server.conf a échoué."
        if ! grep -q "^DBHost=" /etc/zabbix/zabbix_server.conf; then
            echo "DBHost=localhost" | sudo tee -a /etc/zabbix/zabbix_server.conf >/dev/null
            log_info "Configuration DBHost ajoutée dans zabbix_server.conf."
        fi

        sudo mkdir -p /run/zabbix || error_exit 5 "Impossible de créer le répertoire /run/zabbix."
        sudo chown -R zabbix:zabbix /run/zabbix || error_exit 5 "Impossible de changer la propriété de /run/zabbix."

        systemctl daemon-reload
        systemctl enable zabbix-server zabbix-agent apache2
        systemctl restart zabbix-server zabbix-agent apache2
        sleep 5

        if systemctl is-active --quiet zabbix-server; then
            log_info "Zabbix installé et démarré correctement. Accédez à http://<IP>/zabbix (Admin / zabbix)."
        else
            error_exit 4 "Zabbix Server ne démarre pas. Consultez 'sudo systemctl status zabbix-server' et 'sudo journalctl -xeu zabbix-server.service'."
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
            apt update || error_exit 2 "apt update pour Grafana a échoué."
            apt install -y grafana || error_exit 2 "Installation de Grafana a échoué."
            systemctl enable --now grafana-server || error_exit 5 "Démarrage de Grafana a échoué."
        fi
        sed -i "s/^;admin_user = .*/admin_user = ${GRAFANA_ADMIN_USER}/" /etc/grafana/grafana.ini || log_error "Mise à jour de admin_user dans grafana.ini a échoué."
        sed -i "s/^;admin_password = .*/admin_password = ${GRAFANA_ADMIN_PASS}/" /etc/grafana/grafana.ini || log_error "Mise à jour de admin_password dans grafana.ini a échoué."
        systemctl restart grafana-server || log_error "Redémarrage de Grafana a échoué."
        log_info "Grafana installé : http://<IP>:3000 (user=${GRAFANA_ADMIN_USER}, pass=${GRAFANA_ADMIN_PASS})."
    fi
}

########################
# INSTALLATION FAIL2BAN
########################
install_fail2ban() {
    if ask_user "Installer et configurer Fail2ban ?"; then
        if ! already_installed fail2ban; then
            apt install -y fail2ban || error_exit 2 "Installation de Fail2ban a échoué."
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
        check_exit "Configuration de Fail2ban"
        systemctl enable --now fail2ban || error_exit 5 "Activation de Fail2ban a échoué."
        log_info "Fail2ban configuré avec succès."
    fi
}

########################
# INSTALLATION DE LYNIS
########################
install_lynis() {
    if ask_user "Installer Lynis pour l'audit ?"; then
        if ! already_installed lynis; then
            apt install -y lynis || error_exit 2 "Installation de Lynis a échoué."
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
            python3 -m venv /opt/vulners-venv || error_exit 5 "Création de l'environnement virtuel Vulners a échoué."
            source /opt/vulners-venv/bin/activate || error_exit 5 "Activation de l'environnement virtuel Vulners a échoué."
            pip install --upgrade pip vulners || error_exit 2 "Installation de Vulners a échoué."
            deactivate
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
        apt update || error_exit 2 "apt update pour ELK a échoué."
        if ! already_installed elasticsearch; then
            apt install -y elasticsearch || error_exit 2 "Installation d'Elasticsearch a échoué."
        fi
        if ! already_installed logstash; then
            apt install -y logstash || error_exit 2 "Installation de Logstash a échoué."
        fi
        if ! already_installed kibana; then
            apt install -y kibana || error_exit 2 "Installation de Kibana a échoué."
        fi

        systemctl enable elasticsearch logstash kibana || error_exit 5 "Activation des services ELK a échoué."
        systemctl start elasticsearch logstash kibana || error_exit 5 "Démarrage des services ELK a échoué."

        if [ "$ENABLE_ELASTIC_SECURITY" = true ]; then
            log_info "Activation de la sécurité xpack pour Elasticsearch..."
            sed -i '/^#\?xpack.security.enabled:/d' /etc/elasticsearch/elasticsearch.yml
            echo "xpack.security.enabled: true" >> /etc/elasticsearch/elasticsearch.yml || error_exit 5 "Configuration de xpack.security a échoué."
            systemctl restart elasticsearch || error_exit 5 "Redémarrage d'Elasticsearch a échoué."
            sleep 10
            log_info "Génération des mots de passe pour Elasticsearch..."
            /usr/share/elasticsearch/bin/elasticsearch-setup-passwords auto -b > "$ES_PASSWORDS_FILE" 2>/dev/null || log_error "Échec de la génération des mots de passe ES."
            cat "$ES_PASSWORDS_FILE" 2>/dev/null
            NEW_ELASTIC_PASS=$(grep "PASSWORD elastic =" "$ES_PASSWORDS_FILE" | awk '{print $4}')
            if [ -n "$NEW_ELASTIC_PASS" ]; then
                sed -i "s|^#\?elasticsearch.username:.*|elasticsearch.username: \"$KIBANA_ELASTIC_USER\"|" /etc/kibana/kibana.yml
                sed -i "s|^#\?elasticsearch.password:.*|elasticsearch.password: \"$NEW_ELASTIC_PASS\"|" /etc/kibana/kibana.yml
                sed -i "s|^#\?elasticsearch.hosts:.*|elasticsearch.hosts: [\"http://localhost:9200\"]|" /etc/kibana/kibana.yml
                systemctl restart kibana || log_error "Redémarrage de Kibana a échoué."
            else
                log_error "Impossible de récupérer le mot de passe pour l'utilisateur elastic."
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
            apt install -y suricata || error_exit 2 "Installation de Suricata a échoué."
            systemctl enable suricata || error_exit 5 "Activation de Suricata a échoué."
            systemctl stop suricata || error_exit 5 "Impossible d'arrêter Suricata."
            systemctl start suricata || error_exit 5 "Démarrage de Suricata a échoué."
            log_info "Suricata installé."
        fi

        if ask_user "Intégrer Suricata à ELK via Filebeat ?"; then
            if ! already_installed filebeat; then
                apt install -y filebeat || error_exit 2 "Installation de Filebeat a échoué."
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
            check_exit "Création du fichier de configuration Filebeat"
            systemctl enable filebeat || error_exit 5 "Activation de Filebeat a échoué."
            systemctl restart filebeat || error_exit 5 "Redémarrage de Filebeat a échoué."
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
}

# Appel des fonctions pour vérifier le schéma Zabbix
check_zabbix_schema() {
    log_info "Vérification de l'importation du schéma Zabbix..."
    local table_count
    table_count=$(mysql -u "${ZABBIX_DB_USER}" -p"${ZABBIX_DB_PASS}" "${ZABBIX_DB}" -e "SHOW TABLES LIKE 'users';" | wc -l)
    if [ "$table_count" -lt 2 ]; then
        log_info "Aucune table Zabbix détectée (table 'users' absente). Importation du schéma..."
        import_zabbix_schema
    else
        log_info "Le schéma Zabbix est présent."
    fi
}

import_zabbix_schema() {
    local schema_file=""
    for file in /usr/share/doc/zabbix-server-mysql/schema.sql.gz /usr/share/doc/zabbix-server-mysql/create.sql.gz; do
         if [ -f "$file" ]; then
              schema_file="$file"
              break
         fi
    done
    if [ -n "$schema_file" ]; then
         log_info "Fichier de schéma trouvé : $schema_file. Importation..."
         sudo zcat "$schema_file" | mysql -u "${ZABBIX_DB_USER}" -p"${ZABBIX_DB_PASS}" "${ZABBIX_DB}" || error_exit 4 "L'importation du schéma Zabbix a échoué."
         log_info "Schéma Zabbix importé avec succès."
    else
         error_exit 4 "Aucun fichier de schéma Zabbix trouvé. Veuillez installer zabbix-sql-scripts ou vérifier la documentation."
    fi
}

main
