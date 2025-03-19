#!/bin/bash
###############################################################################
#
# Auteur  : VAPOTANK
# Date    : 2025-03-17
# 
###############################################################################

# ==========================================================
# 🛠️ Système de Gestion & Monitoring 🛠️
# ==========================================================
# Ce script permet d'auditer et de gérer les services de monitoring
# Intègre Lynis, Vulners, logs système et vérification de vulnérabilités
# ==========================================================

LOG_DIR="/var/log/monitoring"
VULNERS_API_KEY="DIGNQ4NM6A55C5NZ0L6LTZCARDNAEWI25QY4VM3OB5AZPWDTW65ZVTY3BVBBJ2TF"

mkdir -p "$LOG_DIR"

# ==========================================================
# 🎨 Fonction d'affichage du menu en ASCII
# ==========================================================
show_menu() {
    clear
    echo -e "\e[36m"
    echo " ██████╗  █████╗ ████████╗ █████╗ ███╗   ██╗███████╗████████╗ "
    echo " ██╔══██╗██╔══██╗╚══██╔══╝██╔══██╗████╗  ██║██╔════╝╚══██╔══╝ "
    echo " ██████╔╝███████║   ██║   ███████║██╔██╗ ██║█████╗     ██║    "
    echo " ██╔═══╝ ██╔══██║   ██║   ██╔══██║██║╚██╗██║██╔══╝     ██║    "
    echo " ██║     ██║  ██║   ██║   ██║  ██║██║ ╚████║███████╗   ██║    "
    echo " ╚═╝     ╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═══╝╚══════╝   ╚═╝    "
    echo -e "\e[0m"
    echo "=========================================================="
    echo " 1️⃣  Vérifier les logs système (local)"
    echo " 2️⃣  Vérifier les logs d'un autre serveur"
    echo " 3️⃣  Lancer un audit de sécurité (Lynis - local)"
    echo " 4️⃣  Lancer un audit de sécurité (Lynis - distant)"
    echo " 5️⃣  Vérifier les vulnérabilités (Vulners - local)"
    echo " 6️⃣  Vérifier les vulnérabilités (Vulners - distant)"
    echo " 7️⃣  Afficher les audits précédents"
    echo " 8️⃣  Quitter"
    echo "=========================================================="
}

# ==========================================================
# 📝 Vérifier les logs système (local)
# ==========================================================
check_logs_local() {
    echo "📌 Vérification des logs locaux..."
    journalctl -n 50 --no-pager > "$LOG_DIR/system_logs.txt"
    cat "$LOG_DIR/system_logs.txt"
    echo "✅ Logs enregistrés dans $LOG_DIR/system_logs.txt"
    read -p "🔄 Appuyez sur Entrée pour revenir au menu..."
}

# ==========================================================
# 📝 Vérifier les logs d'un autre serveur (SSH)
# ==========================================================
check_logs_remote() {
    read -p "🖥️  Adresse IP du serveur distant : " SERVER_IP
    echo "📌 Vérification des logs sur $SERVER_IP..."
    ssh root@$SERVER_IP "journalctl -n 50 --no-pager" > "$LOG_DIR/remote_logs_$SERVER_IP.txt"
    cat "$LOG_DIR/remote_logs_$SERVER_IP.txt"
    echo "✅ Logs enregistrés dans $LOG_DIR/remote_logs_$SERVER_IP.txt"
    read -p "🔄 Appuyez sur Entrée pour revenir au menu..."
}

# ==========================================================
# 🔍 Lancer un audit de sécurité avec Lynis
# ==========================================================
run_lynis_audit() {
    echo "📌 Exécution d'un audit de sécurité avec Lynis..."
    lynis audit system > "$LOG_DIR/lynis_audit.txt"
    cat "$LOG_DIR/lynis_audit.txt"
    echo "✅ Audit enregistré dans $LOG_DIR/lynis_audit.txt"
    read -p "🔄 Appuyez sur Entrée pour revenir au menu..."
}

# ==========================================================
# 🔍 Lancer un audit de sécurité sur un serveur distant
# ==========================================================
run_lynis_audit_remote() {
    read -p "🖥️  Adresse IP du serveur distant : " SERVER_IP
    echo "📌 Exécution d'un audit de sécurité sur $SERVER_IP..."
    ssh root@$SERVER_IP "lynis audit system" > "$LOG_DIR/lynis_audit_$SERVER_IP.txt"
    cat "$LOG_DIR/lynis_audit_$SERVER_IP.txt"
    echo "✅ Audit enregistré dans $LOG_DIR/lynis_audit_$SERVER_IP.txt"
    read -p "🔄 Appuyez sur Entrée pour revenir au menu..."
}

# ==========================================================
# 🛡️ Vérification des vulnérabilités avec Vulners
# ==========================================================
check_vulners_local() {
    echo "📌 Vérification des vulnérabilités avec Vulners..."
    source /opt/vulners-venv/bin/activate
    python3 -c "
import vulners, subprocess, json

v = vulners.VulnersApi(api_key='$VULNERS_API_KEY')

# Récupération de la version de l'OS
os_version = subprocess.getoutput('lsb_release -rs')

# Récupération des paquets installés et formatage en liste de dictionnaires
raw_packages = subprocess.getoutput('dpkg-query -W -f=\"${Package} ${Version}\\n\"').splitlines()
packages_list = [{\"name\": pkg.split()[0], \"version\": pkg.split()[1]} for pkg in raw_packages if len(pkg.split()) == 2]

# Exécution de l'audit Vulners
result = v.software_audit(os='Debian', version=os_version, packages=packages_list)
print(json.dumps(result, indent=4))  # Affichage formaté JSON
" > "$LOG_DIR/vulners_audit.txt"
    deactivate

    cat "$LOG_DIR/vulners_audit.txt"
    echo "✅ Audit enregistré dans $LOG_DIR/vulners_audit.txt"
    read -p "🔄 Appuyez sur Entrée pour revenir au menu..."
}



# ==========================================================
# 🛡️ Vérification des vulnérabilités sur un serveur distant
# ==========================================================
check_vulners_remote() {
    read -p "🖥️  Adresse IP du serveur distant : " SERVER_IP
    echo "📌 Vérification des vulnérabilités sur $SERVER_IP..."
    ssh root@$SERVER_IP "source /opt/vulners-venv/bin/activate && python3 -c '
import vulners, subprocess, json

v = vulners.VulnersApi(api_key=\"$VULNERS_API_KEY\")

os_version = subprocess.getoutput(\"lsb_release -rs\")

raw_packages = subprocess.getoutput(\"dpkg-query -W -f=\\\"${Package} ${Version}\\\\n\\\"\").splitlines()
packages_list = [{\"name\": pkg.split()[0], \"version\": pkg.split()[1]} for pkg in raw_packages if len(pkg.split()) == 2]

result = v.software_audit(os=\"Debian\", version=os_version, packages=packages_list)
print(json.dumps(result, indent=4))
' > /var/log/vulners_audit_$SERVER_IP.txt && deactivate"
    
    ssh root@$SERVER_IP "cat /var/log/vulners_audit_$SERVER_IP.txt"
    echo "✅ Audit enregistré sur le serveur distant dans /var/log/vulners_audit_$SERVER_IP.txt"
    read -p "🔄 Appuyez sur Entrée pour revenir au menu..."
}



# ==========================================================
# 📂 Affichage des audits précédents
# ==========================================================
show_previous_audits() {
    echo "📂 Liste des audits disponibles :"
    ls -1 "$LOG_DIR"
    read -p "📂 Entrez le nom du fichier à afficher : " FILE
    cat "$LOG_DIR/$FILE"
    read -p "🔄 Appuyez sur Entrée pour revenir au menu..."
}

# ==========================================================
# 🚀 Boucle principale
# ==========================================================
while true; do
    show_menu
    read -p "➡️  Choisissez une option : " choice
    case $choice in
        1) check_logs_local ;;
        2) check_logs_remote ;;
        3) run_lynis_audit ;;
        4) run_lynis_audit_remote ;;
        5) check_vulners_local ;;
        6) check_vulners_remote ;;
        7) show_previous_audits ;;
        8) exit 0 ;;
        *) echo "❌ Option invalide !" ;;
    esac
done
