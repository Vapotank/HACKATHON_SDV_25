#!/bin/bash

LOG_FILE="/var/log/system_management.log"
exec > >(tee -a "$LOG_FILE") 2>&1

SERVICES=("zabbix-server" "zabbix-agent" "grafana-server" "fail2ban" "elasticsearch" "logstash" "kibana" "mariadb")

# Fonction de vérification et redémarrage des services
check_services() {
    echo "📌 Vérification des services..."
    for service in "${SERVICES[@]}"; do
        systemctl is-active --quiet "$service"
        if [ $? -ne 0 ]; then
            echo "❌ $service est arrêté ! Redémarrage..."
            systemctl restart "$service"
            systemctl is-active --quiet "$service" && echo "✅ $service redémarré avec succès !" || echo "🚨 Échec du redémarrage de $service !"
        else
            echo "✅ $service fonctionne normalement."
        fi
    done
}

# Vérifier si MySQL/MariaDB tourne
check_mysql() {
    echo "📌 Vérification de MariaDB/MySQL..."
    systemctl is-active --quiet mariadb
    if [ $? -ne 0 ]; then
        echo "❌ MariaDB est arrêté ! Redémarrage..."
        systemctl restart mariadb
        systemctl is-active --quiet mariadb && echo "✅ MariaDB redémarré avec succès !" || echo "🚨 Échec du redémarrage de MariaDB !"
    else
        echo "✅ MariaDB fonctionne normalement."
    fi
}

# Vérifier et corriger Zabbix
check_zabbix() {
    echo "📌 Vérification de Zabbix..."
    DB_COUNT=$(mysql -u zabbix -pzabbix_pass -e "USE zabbix; SHOW TABLES;" 2>/dev/null | wc -l)
    if [ "$DB_COUNT" -lt 10 ]; then
        echo "⚠️ Base Zabbix semble incomplète. Réimportation du schéma..."
        zcat /usr/share/zabbix-server-mysql/create.sql.gz | mysql -u zabbix -pzabbix_pass zabbix
    fi
}

# Vérification de Kibana et ELK
check_elk() {
    echo "📌 Vérification de la stack ELK..."
    systemctl is-active --quiet elasticsearch
    if [ $? -ne 0 ]; then
        echo "❌ Elasticsearch est arrêté ! Redémarrage..."
        systemctl restart elasticsearch
    fi

    systemctl is-active --quiet kibana
    if [ $? -ne 0 ]; then
        echo "❌ Kibana est arrêté ! Redémarrage..."
        systemctl restart kibana
    fi
}

# Vérifier et nettoyer les logs
clean_logs() {
    echo "📌 Nettoyage des logs..."
    find /var/log -type f -name "*.log" -size +100M -exec truncate -s 0 {} \;
    echo "✅ Logs nettoyés."
}

# Audit de sécurité avec Lynis
run_lynis() {
    echo "📌 Audit de sécurité avec Lynis..."
    lynis audit system > /var/log/lynis_audit.log
    echo "✅ Audit terminé. Résultats dans /var/log/lynis_audit.log"
}

# Vérification des vulnérabilités avec Vulners
run_vulners() {
    echo "📌 Vérification des vulnérabilités avec Vulners..."
    source /opt/vulners-venv/bin/activate
    python3 -c "import vulners; v = vulners.Vulners(api_key='TA_CLE_API_ICI'); print(v.audit(os=True))"
    deactivate
    echo "✅ Vérification des CVE terminée."
}

# Mettre à jour le système et les paquets de sécurité
update_system() {
    echo "📌 Mise à jour du système..."
    apt update && apt upgrade -y
    apt install --only-upgrade zabbix-server-mysql zabbix-agent grafana fail2ban elasticsearch logstash kibana mariadb-server -y
    echo "✅ Mise à jour terminée."
}

# Menu principal
while true; do
    clear
    echo "========================================="
    echo "🔧 Système de Gestion & Maintenance 🔧"
    echo "========================================="
    echo "1️⃣ Vérifier et redémarrer les services"
    echo "2️⃣ Vérifier et réparer MySQL/MariaDB"
    echo "3️⃣ Vérifier et réparer Zabbix"
    echo "4️⃣ Vérifier et réparer ELK (Elasticsearch/Kibana)"
    echo "5️⃣ Nettoyer les logs du serveur"
    echo "6️⃣ Lancer un audit de sécurité (Lynis)"
    echo "7️⃣ Vérifier les vulnérabilités (Vulners)"
    echo "8️⃣ Mettre à jour le système et les logiciels"
    echo "9️⃣ Quitter"
    read -p "➡️ Choisissez une option : " choice

    case $choice in
        1) check_services ;;
        2) check_mysql ;;
        3) check_zabbix ;;
        4) check_elk ;;
        5) clean_logs ;;
        6) run_lynis ;;
        7) run_vulners ;;
        8) update_system ;;
        9) echo "🔴 Fermeture du gestionnaire."; exit 0 ;;
        *) echo "❌ Option invalide, veuillez réessayer." ;;
    esac
    echo "🔄 Appuyez sur Entrée pour revenir au menu..."
    read
done
