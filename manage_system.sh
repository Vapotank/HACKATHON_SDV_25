#!/bin/bash

# ================================================
#  Système de Gestion & Monitoring - VAPOTANK 
# ================================================
# Version : 1.1 (2025-03-18)
# Fonctionnalités :
#  ✅ Vérification des logs système et distant
#  ✅ Audit de sécurité (Lynis) local et distant
#  ✅ Vérification des vulnérabilités (Vulners) local et distant
#  ✅ Affichage des audits précédents
#  ✅ Gestion complète des services de monitoring
#  ✅ Support pour ELK, Zabbix et Grafana
# ================================================

LOG_DIR="/var/log/monitoring"
mkdir -p "$LOG_DIR"

# ================================================
# 🎨 Affichage du logo ASCII
# ================================================
afficher_banniere() {
    clear
    export LC_ALL=en_US.UTF-8
    export LANG=en_US.UTF-8

    echo -e "\e[1;34m"
    cat << "EOF"
  ███╗   ███╗ ██████╗ ███╗   ██╗ █████╗ ██████╗ ███████╗
  ████╗ ████║██╔═══██╗████╗  ██║██╔══██╗██╔══██╗██╔════╝
  ██╔████╔██║██║   ██║██╔██╗ ██║███████║██████╔╝█████╗  
  ██║╚██╔╝██║██║   ██║██║╚██╗██║██╔══██║██╔═══╝ ██╔══╝  
  ██║ ╚═╝ ██║╚██████╔╝██║ ╚████║██║  ██║██║     ███████╗
  ╚═╝     ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝     ╚══════╝
EOF
    echo -e "\e[0m"
}

# ================================================
# 🛠️  Fonctions Utilitaires
# ================================================
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

# ================================================
# 📂 Vérification des logs (local & distant)
# ================================================
verifier_logs() {
    echo "📌 Vérification des logs système..."
    journalctl -xe --no-pager | tail -n 30
}

verifier_logs_distant() {
    read -p "🔹 Entrez l'adresse IP du serveur distant : " serveur
    echo "📌 Vérification des logs sur $serveur..."
    ssh "$serveur" "journalctl -xe --no-pager | tail -n 30"
}

# ================================================
# 🔍 Audit de Sécurité (local & distant)
# ================================================
auditer_securite() {
    echo "📌 Lancement de Lynis..."
    lynis audit system | tee "$LOG_DIR/audit_$(date +%F_%H%M).log"
    echo "✅ Audit terminé."
}

auditer_securite_distant() {
    read -p "🔹 Entrez l'adresse IP du serveur distant : " serveur
    echo "📌 Audit de sécurité distant via SSH sur $serveur..."
    ssh "$serveur" "lynis audit system" | tee "$LOG_DIR/audit_distant_$(date +%F_%H%M).log"
    echo "✅ Audit distant terminé."
}

# ================================================
# 🔎 Vérification des vulnérabilités (Vulners)
# ================================================
verifier_cve() {
    echo "📌 Vérification des vulnérabilités avec Vulners..."
    source /opt/vulners-venv/bin/activate
    python3 -c "import vulners; v = vulners.Vulners(api_key='DIGNQ4NM6A55C5NZ0L6LTZCARDNAEWI25QY4VM3OB5AZPWDTW65ZVTY3BVBBJ2TF'); print(v.software_audit())"
    deactivate
    echo "✅ Vérification des CVE terminée."
}

verifier_cve_distant() {
    read -p "🔹 Entrez l'adresse IP du serveur distant : " serveur
    echo "📌 Vérification des vulnérabilités sur $serveur..."
    ssh "$serveur" "source /opt/vulners-venv/bin/activate && python3 -c \"import vulners; v = vulners.Vulners(api_key='DIGNQ4NM6A55C5NZ0L6LTZCARDNAEWI25QY4VM3OB5AZPWDTW65ZVTY3BVBBJ2TF'); print(v.software_audit())\" && deactivate"
    echo "✅ Vérification des CVE distante terminée."
}

# ================================================
# 📜 Afficher les audits précédents
# ================================================
afficher_audits() {
    echo "📌 Affichage des audits précédents..."
    ls -lt "$LOG_DIR" | grep "audit_" | awk '{print $9}'
    read -p "🔹 Entrez le nom du fichier à afficher : " fichier
    cat "$LOG_DIR/$fichier"
}

# ================================================
# 🏗️ Menu Principal
# ================================================
while true; do
    afficher_banniere
    echo "================================================="
    echo " 1️⃣  Vérifier les logs système (local)"
    echo " 2️⃣  Vérifier les logs d'un autre serveur"
    echo " 3️⃣  Lancer un audit de sécurité (Lynis - local)"
    echo " 4️⃣  Lancer un audit de sécurité (Lynis - distant)"
    echo " 5️⃣  Vérifier les vulnérabilités (Vulners - local)"
    echo " 6️⃣  Vérifier les vulnérabilités (Vulners - distant)"
    echo " 7️⃣  Afficher les audits précédents"
    echo " 8️⃣  Quitter"
    echo "================================================="
    read -p "➡️  Choisissez une option : " choix

    case $choix in
        1) verifier_logs ;;
        2) verifier_logs_distant ;;
        3) auditer_securite ;;
        4) auditer_securite_distant ;;
        5) verifier_cve ;;
        6) verifier_cve_distant ;;
        7) afficher_audits ;;
        8) echo "👋 Au revoir !"; exit 0 ;;
        *) echo "❌ Option invalide. Réessayez." ;;
    esac
    read -p "🔄 Appuyez sur Entrée pour revenir au menu..."
done
