#!/usr/bin/env bash
set -o pipefail

################################################################################
# Script d'installation complet pour Debian 12 (Bookworm) :
# - Zabbix (Server + Frontend)
# - Grafana
# - Fail2ban, Lynis, Vulners
# - ELK (Elastic, Logstash, Kibana)
# - Suricata (optionnel)
#
# Principales corrections :
#  - Shebang : #!/usr/bin/env bash
#  - export DEBIAN_FRONTEND=noninteractive sur une ligne séparée
#  - Utilisation de apt-get -y install (pas apt)
#  - On installe explicitement ufw, mariadb-client, mariadb-server, etc. avant de les utiliser
#
# Auteur  : VAPOTANK / ChatGPT
# Date    : 2025-03-18
# Usage   : sudo ./install_monitoring.sh  (ou bash install_monitoring.sh)
################################################################################

LOG_FILE="/var/log/install_monitoring.log"
exec > >(tee -a "$LOG_FILE") 2>&1

########################
# VARIABLES GLOBALES   #
########################

export DEBIAN_FRONTEND=noninteractive  # Pour désactiver les prompts APT
APT_CMD="apt-get -y"                   # On utilisera cette variable pour apt-get -y

# -- MySQL / Zabbix
MYSQL_ROOT_PASSWORD="root123"
ZABBIX_DB="zabbix"
ZABBIX_DB_USER="zabbix"
ZABBIX_DB_PASS="zabbix_pass"
ZABBIX_SERVER_TIMEZONE="Europe/Paris"

# -- Grafana
GRAFANA_ADMIN_USER="admin"
GRAFANA_ADMIN_PASS="admin123"

# -- ELK
ENABLE_ELASTIC_SECURITY=true
ES_PASSWORDS_FILE="/tmp/es_passwords.txt"
KIBANA_ELASTIC_USER="elastic"

# Keyrings
KEYRING_DIR="/etc/apt/keyrings"
GRAFANA_KEY="$KEYRING_DIR/grafana.gpg"
ELASTIC_KEY="$KEYRING_DIR/elastic.gpg"

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

already_installed() {
  dpkg -s "$1" &>/dev/null
  return $?
}

########################
# 1) PACKAGES DE BASE  #
########################
install_base_packages() {
  echo "--- Mise à jour du système ---"
  $APT_CMD update && $APT_CMD upgrade

  echo "--- Installation des paquets de base ---"
  $APT_CMD install gnupg2 curl wget lsb-release apt-transport-https software-properties-common \
                   iptables ufw mariadb-server mariadb-client bash-completion \
                   python3 python3-pip python3-venv
}

########################
# 2) FIREWALL (UFW)    #
########################
configure_firewall() {
  if ask_user "Voulez-vous configurer un firewall UFW avec quelques règles de base ?"; then
    if ! already_installed ufw; then
      $APT_CMD install ufw || die "Échec de l'installation de ufw"
    fi
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow ssh
    ufw allow 80/tcp    # HTTP
    ufw allow 443/tcp   # HTTPS
    ufw allow 10050/tcp # Zabbix agent
    ufw allow 10051/tcp # Zabbix server
    ufw allow 3000/tcp  # Grafana
    ufw allow 5601/tcp  # Kibana
    ufw allow 5044/tcp  # Logstash
    ufw enable
    echo "✅ Firewall UFW activé."
  else
    echo "Firewall ignoré."
  fi
}

########################
# 3) CONFIG MARIADB    #
########################
configure_mariadb() {
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
  # Debian 12 : on ajoute bullseye-security si besoin pour libssl1.1
  if ! grep -q "bullseye-security" /etc/apt/sources.list; then
    echo "deb http://security.debian.org/debian-security bullseye-security main" >> /etc/apt/sources.list
  fi
  $APT_CMD update
  $APT_CMD install libssl1.1 libldap-2.4-2 || echo "[INFO] Dépendances Zabbix déjà satisfaites ou introuvables."
}

########################
# 5) INSTALL ZABBIX    #
########################
install_zabbix() {
  if ask_user "Voulez-vous installer Zabbix Server + Agent ?"; then
    fix_dependencies_zabbix

    echo "--- Installation Zabbix Server + Agent ---"
    wget -O /tmp/zabbix-release.deb https://repo.zabbix.com/zabbix/7.0/debian/pool/main/z/zabbix-release/zabbix-release_7.0-1+debian12_all.deb || die "Téléchargement Zabbix raté"
    dpkg -i /tmp/zabbix-release.deb || die "Installation repo Zabbix ratée"
    $APT_CMD update
    $APT_CMD install zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf zabbix-agent || die "Échec installation Zabbix"

    echo "--- Import du schéma Zabbix ---"
    zcat /usr/share/doc/zabbix-server-mysql/create.sql.gz | mysql -u "$ZABBIX_DB_USER" -p"$ZABBIX_DB_PASS" "$ZABBIX_DB" || echo "[INFO] Échec ou déjà importé."

    echo "--- Configuration PHP/Zabbix ---"
    sed -i "s|.*date.timezone =.*|php_value date.timezone ${ZABBIX_SERVER_TIMEZONE}|" /etc/apache2/conf-available/zabbix.conf || true

    sed -i "s|^# DBPassword=.*|DBPassword=${ZABBIX_DB_PASS}|" /etc/zabbix/zabbix_server.conf
    sed -i "s|^# DBUser=.*|DBUser=${ZABBIX_DB_USER}|" /etc/zabbix/zabbix_server.conf
    sed -i "s|^# DBName=.*|DBName=${ZABBIX_DB}|" /etc/zabbix/zabbix_server.conf

    systemctl enable zabbix-server zabbix-agent apache2
    systemctl restart zabbix-server zabbix-agent apache2

    echo "✅ Zabbix installé. Accès : http://<IP>/zabbix (Admin / zabbix)"
  else
    echo "Zabbix ignoré."
  fi
}

########################
# 6) INSTALL GRAFANA   #
########################
setup_grafana_repo() {
  echo "--- Import clé GPG Grafana + config dépôt [signed-by] ---"
  mkdir -p "$KEYRING_DIR"
  curl -fsSL https://packages.grafana.com/gpg.key | gpg --dearmor -o "$GRAFANA_KEY"
  chmod 644 "$GRAFANA_KEY"

  cat <<EOF > /etc/apt/sources.list.d/grafana.list
deb [signed-by=$GRAFANA_KEY] https://packages.grafana.com/oss/deb stable main
EOF
}

install_grafana() {
  if ask_user "Voulez-vous installer Grafana ?"; then
    setup_grafana_repo
    $APT_CMD update
    $APT_CMD install grafana || die "Échec installation Grafana"

    systemctl enable --now grafana-server
    sed -i "s/^;admin_user = .*/admin_user = ${GRAFANA_ADMIN_USER}/" /etc/grafana/grafana.ini
    sed -i "s/^;admin_password = .*/admin_password = ${GRAFANA_ADMIN_PASS}/" /etc/grafana/grafana.ini
    systemctl restart grafana-server

    echo "✅ Grafana installé. http://<IP>:3000 (user=${GRAFANA_ADMIN_USER}, pass=${GRAFANA_ADMIN_PASS})"
  else
    echo "Grafana ignoré."
  fi
}

########################
# 7) FAIL2BAN          #
########################
install_fail2ban() {
  if ask_user "Voulez-vous installer Fail2ban ?"; then
    $APT_CMD install fail2ban || die "Échec installation Fail2ban"

    cat <<EOF > /etc/fail2ban/jail.local
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
[sshd]
enabled = true
logpath = /var/log/auth.log
EOF

    systemctl enable --now fail2ban || echo "[WARNING] fail2ban.service introuvable ?"
    echo "✅ Fail2ban installé."
  else
    echo "Fail2ban ignoré."
  fi
}

########################
# 8) LYNIS             #
########################
install_lynis() {
  if ask_user "Voulez-vous installer Lynis ?"; then
    $APT_CMD install lynis || die "Échec installation Lynis"
    echo "✅ Lynis installé."
  else
    echo "Lynis ignoré."
  fi
}

########################
# 9) VULNERS           #
########################
install_vulners() {
  if ask_user "Voulez-vous installer Vulners (scanner CVE) ?"; then
    echo "--- Installation Vulners CLI ---"
    python3 -m venv /opt/vulners-venv
    source /opt/vulners-venv/bin/activate
    pip install --upgrade pip
    pip install vulners || die "Échec installation Vulners"
    deactivate
    echo "✅ Vulners installé. (env /opt/vulners-venv)."
  else
    echo "Vulners ignoré."
  fi
}

########################
# 10) ELK              #
########################
setup_elastic_repo() {
  echo "--- Import clé GPG Elastic + config dépôt [signed-by] ---"
  mkdir -p "$KEYRING_DIR"
  curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor -o "$ELASTIC_KEY"
  chmod 644 "$ELASTIC_KEY"

  cat <<EOF > /etc/apt/sources.list.d/elastic-7.x.list
deb [signed-by=$ELASTIC_KEY] https://artifacts.elastic.co/packages/7.x/apt stable main
EOF
}

install_elk() {
  if ask_user "Voulez-vous installer la stack ELK (Elasticsearch, Logstash, Kibana) ?"; then
    setup_elastic_repo
    $APT_CMD update
    $APT_CMD install elasticsearch logstash kibana || die "Échec installation ELK"

    systemctl enable elasticsearch logstash kibana
    systemctl start elasticsearch logstash kibana
    echo "✅ ELK installé."

    if [ "$ENABLE_ELASTIC_SECURITY" = true ]; then
      echo "--- Activation sécurité Elasticsearch ---"
      sed -i '/^#\?xpack.security.enabled:/d' /etc/elasticsearch/elasticsearch.yml
      echo "xpack.security.enabled: true" >> /etc/elasticsearch/elasticsearch.yml

      systemctl restart elasticsearch
      echo "Patientez 5s le temps du redémarrage..."
      sleep 5

      /usr/share/elasticsearch/bin/elasticsearch-setup-passwords auto -b > "$ES_PASSWORDS_FILE" 2>/dev/null
      cat "$ES_PASSWORDS_FILE"
      NEW_ELASTIC_PASS=$(grep "PASSWORD elastic =" "$ES_PASSWORDS_FILE" | awk '{print $4}')
      if [ -n "$NEW_ELASTIC_PASS" ]; then
        sed -i "s|^#\?elasticsearch.username:.*|elasticsearch.username: \"$KIBANA_ELASTIC_USER\"|" /etc/kibana/kibana.yml
        sed -i "s|^#\?elasticsearch.password:.*|elasticsearch.password: \"$NEW_ELASTIC_PASS\"|" /etc/kibana/kibana.yml
        sed -i "s|^#\?elasticsearch.hosts:.*|elasticsearch.hosts: [\"http://localhost:9200\"]|" /etc/kibana/kibana.yml
        systemctl restart kibana
        echo "✅ Sécurité Elasticsearch activée. Voir $ES_PASSWORDS_FILE."
      else
        echo "[WARNING] Pas trouvé le mot de passe 'elastic' dans $ES_PASSWORDS_FILE"
      fi
    fi

    echo "✅ Accès Kibana : http://<IP>:5601"
  else
    echo "ELK ignoré."
  fi
}

########################
# 11) SURICATA         #
########################
install_suricata() {
  if ask_user "Voulez-vous installer Suricata (IDS/IPS) ?"; then
    $APT_CMD install suricata || die "Échec installation Suricata"
    systemctl enable suricata
    systemctl start suricata
    echo "✅ Suricata installé."

    if ask_user "Intégrer Suricata à ELK via Filebeat ?"; then
      $APT_CMD install filebeat
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
  ip -4 addr show | grep 'inet ' | awk '{print $2}'
}

########################
# MAIN                 #
########################
main() {
  echo "=== Début de l'installation du monitoring complet ==="

  install_base_packages
  systemctl enable --now mariadb  # Démarrer mariadb
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
