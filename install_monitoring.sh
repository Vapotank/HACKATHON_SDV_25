#!/bin/bash

# Script interactif pour l'installation et la configuration complète de Zabbix, Grafana, Fail2ban, Lynis, Vulners, et ELK sur Debian

log_file="/var/log/auto_monitoring.log"
exec > >(tee -a "$log_file") 2>&1

echo "--- Début de l'installation ---"

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

update_system() {
    echo "--- Mise à jour du système ---"
    apt update && apt upgrade -y || die "Échec de la mise à jour du système"
    apt install -y gnupg gnupg2 python3-venv python3-pip || die "Échec de l'installation des paquets nécessaires"
}

fix_dependencies() {
    echo "--- Ajout des paquets nécessaires pour Zabbix sur Debian 12 ---"
    echo "deb http://security.debian.org/debian-security bullseye-security main" | tee -a /etc/apt/sources.list
    apt update
    apt install -y libssl1.1 libldap-2.4-2 || die "Échec de l'installation des dépendances manquantes"
}

install_zabbix() {
    if ask_user "Voulez-vous installer Zabbix ?"; then
        fix_dependencies
        echo "--- Installation de Zabbix ---"
        wget -O /tmp/zabbix-release.deb https://repo.zabbix.com/zabbix/6.0/debian/pool/main/z/zabbix-release/zabbix-release_6.0-4+debian11_all.deb || die "Échec du téléchargement du dépôt Zabbix"
        dpkg -i /tmp/zabbix-release.deb || die "Échec de l'installation du dépôt Zabbix"
        apt update
        apt install -y zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf zabbix-agent || die "Échec de l'installation de Zabbix"
    else
        echo "Zabbix ignoré."
    fi
}

install_grafana() {
    if ask_user "Voulez-vous installer Grafana ?"; then
        echo "--- Installation de Grafana ---"
        wget -q -O - https://packages.grafana.com/gpg.key | apt-key add - || die "Échec de l'ajout de la clé GPG"
        echo "deb https://packages.grafana.com/oss/deb stable main" > /etc/apt/sources.list.d/grafana.list
        apt update && apt install -y grafana || die "Échec de l'installation de Grafana"
        systemctl enable --now grafana-server
    else
        echo "Grafana ignoré."
    fi
}

install_fail2ban() {
    if ask_user "Voulez-vous installer et configurer Fail2ban ?"; then
        echo "--- Installation et configuration de Fail2ban ---"
        apt install -y fail2ban || die "Échec de l'installation de Fail2ban"
        cat <<EOF > /etc/fail2ban/jail.local
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
[sshd]
enabled = true
EOF
        systemctl restart fail2ban
    else
        echo "Fail2ban ignoré."
    fi
}

install_lynis() {
    if ask_user "Voulez-vous installer Lynis pour l'audit de sécurité ?"; then
        echo "--- Installation de Lynis ---"
        apt install -y lynis || die "Échec de l'installation de Lynis"
    else
        echo "Lynis ignoré."
    fi
}

install_vulners() {
    if ask_user "Voulez-vous installer Vulners pour la détection des CVE ?"; then
        echo "--- Installation de Vulners ---"
        python3 -m venv /opt/vulners-venv
        source /opt/vulners-venv/bin/activate
        pip install vulners || die "Échec de l'installation de Vulners-cli"
        deactivate
    else
        echo "Vulners ignoré."
    fi
}

install_elk() {
    if ask_user "Voulez-vous installer la stack ELK (Elasticsearch, Logstash, Kibana) ?"; then
        echo "--- Installation de la stack ELK ---"
        wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | apt-key add - || die "Échec de l'ajout de la clé GPG Elastic"
        echo "deb https://artifacts.elastic.co/packages/7.x/apt stable main" > /etc/apt/sources.list.d/elastic-7.x.list
        apt update && apt install -y elasticsearch logstash kibana || die "Échec de l'installation de la stack ELK"
        systemctl enable --now elasticsearch logstash kibana
    else
        echo "ELK ignoré."
    fi
}

detect_ip() {
    echo "--- Détection de l'adresse IP du serveur ---"
    ip addr show | grep 'inet ' | awk '{print $2}'
}

main() {
    update_system
    install_zabbix
    install_grafana
    install_fail2ban
    install_lynis
    install_vulners
    install_elk
    detect_ip
    echo "Installation terminée !"
}

main
