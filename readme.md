# 📌 Projet de Monitoring & Gestion de Serveurs

Ce projet propose une **solution complète** pour déployer et gérer un environnement de surveillance et de sécurité sur des serveurs. Il regroupe plusieurs scripts permettant d'installer et de configurer des services de monitoring, de gestion et d'audit, incluant **Zabbix**, **ELK**, **Grafana**, **Fail2ban**, **Lynis**, **Vulners** et plus encore.

---

## 🛠️ Services Installés et Fonctionnalités

### 1. **Zabbix (Server, Frontend et Agent)**
- **Fonctionnalité :** Supervision complète du réseau et des serveurs.
- **Installation :**
  - **Script concerné :** `install_monitoring.sh` (installation de Zabbix Server, Frontend, et Agent sur Debian).
  - **Configuration :**
    - Création d'une base de données Zabbix sur MariaDB.
    - Paramétrage des fichiers de configuration pour le serveur et l'agent.
    - Accès web via l'URL `http://<IP>/zabbix` (identifiants par défaut : Admin / `zabbix`).

### 2. **Grafana**
- **Fonctionnalité :** Visualisation des données de monitoring via des dashboards interactifs.
- **Installation :**
  - **Script concerné :** `install_monitoring.sh`
  - **Configuration :**
    - Installation via le dépôt Grafana.
    - Paramétrage des identifiants d'administration (par défaut : `admin` / `admin123`).
    - Accès via `http://<IP>:3000`.

### 3. **ELK Stack (Elasticsearch, Logstash, Kibana)**
- **Fonctionnalité :** Centralisation, recherche et visualisation des logs.
- **Installation :**
  - **Script concerné :** `install_monitoring.sh`
  - **Configuration :**
    - Installation d’Elasticsearch, Logstash et Kibana.
    - Option de sécurité activée pour Elasticsearch (les mots de passe générés sont stockés dans un fichier temporaire).
    - Accès à Kibana via `http://<IP>:5601`.

### 4. **Filebeat (Agent ELK)**
- **Fonctionnalité :** Collecte et envoi des logs vers Elasticsearch ou Logstash.
- **Installation :**
  - **Script concerné :** 
    - Pour Debian : `elk_agent_install.sh` ou via le script interactif `install_agent_noninteractive.sh`.
    - Pour Windows : `Install_Filebeat.ps1`.
  - **Configuration :**
    - Fichier `/etc/filebeat/filebeat.yml` (ou équivalent sous Windows) pointant vers le serveur central (Elasticsearch/Logstash).
    - Authentification par défaut : utilisateur `elastic` / mot de passe `!!!`.

### 5. **Zabbix Agent**
- **Fonctionnalité :** Collecte des métriques sur les serveurs clients pour la supervision par Zabbix.
- **Installation :**
  - **Script concerné :** 
    - Pour Debian : `zabbix_agent_install.sh` ou via le script interactif `install_agent_noninteractive.sh`.
    - Pour Windows : `Install_ZabbixAgent.ps1`.
  - **Configuration :**
    - Fichier `/etc/zabbix/zabbix_agentd.conf` pour pointer vers le serveur Zabbix (par défaut `192.168.1.41` ou modifiable).

### 6. **Suricata (IDS/IPS)**
- **Fonctionnalité :** Détection d’intrusions et protection contre les attaques réseau.
- **Installation :**
  - **Script concerné :** `install_monitoring.sh`
  - **Configuration :** Optionnelle, avec intégration à ELK via Filebeat.

### 7. **Fail2ban**
- **Fonctionnalité :** Protection contre les attaques par force brute (ex. SSH).
- **Installation :**
  - **Script concerné :** `install_monitoring.sh`
  - **Configuration :** Paramètres de bannissement, délai et nombre de tentatives.

### 8. **Lynis et Vulners**
- **Fonctionnalité :** Audit de sécurité (Lynis) et détection de vulnérabilités (Vulners).
- **Installation :**
  - **Script concerné :** `install_monitoring.sh` (installe Lynis et prépare l’environnement pour Vulners).
  - **Configuration :**  
    - Un environnement virtuel Python (`/opt/vulners-venv`) est créé pour Vulners si vous l’activez.

### 9. **Script de Gestion & Audit – `manage_system.sh`**
- **Fonctionnalité :** 
  - Audit interactif des logs (locaux/distants).
  - Audits de sécurité (Lynis) et détection de vulnérabilités (Vulners).
  - Affichage d’un historique des audits précédents.
- **Modifications récentes :**
  - **Installation automatique de Lynis** sur la machine distante si `lynis` n’est pas présent (option 4).
  - **Installation automatique de Vulners** dans un venv `/opt/vulners-venv` si non existant (option 6).

---

## 🚀 Déploiement et Instructions d’Installation

### 1. **Pré-requis**
- Serveur sous **Debian 12 (Bookworm)** ou Windows (pour les scripts d’agents Windows).
- Accès root (`sudo`) sur les machines cibles.
- Connexion réseau entre le serveur central et les machines clientes.
- Pour Vulners (local) :
  ```bash
  sudo apt install python3 python3-pip -y
  python3 -m venv /opt/vulners-venv
  source /opt/vulners-venv/bin/activate
  pip install --upgrade pip vulners
  deactivate
  ```
  (Cette étape peut être faite automatiquement via `manage_system.sh` côté distant.)

### 2. **Installation sur le Serveur Central**
1. **Exécuter le script complet** :  
   ```bash
   sudo chmod +x install_monitoring.sh
   sudo ./install_monitoring.sh
   ```
   - Installe et configure Zabbix Server + Frontend, Grafana, ELK (Elasticsearch, Logstash, Kibana), Suricata, Fail2ban, Lynis, Vulners…
2. **Vérifier les services** :  
   ```bash
   sudo systemctl status zabbix-server zabbix-agent elasticsearch kibana filebeat
   ```
   - S’assurer qu’ils sont **active (running)**.

### 3. **Installation des Agents sur les Machines Clients**
- **Linux (Debian/Ubuntu) :**  
  - Utilisez le script interactif `install_agent_noninteractive.sh` depuis le serveur de déploiement :  
    ```bash
    sudo chmod +x install_agent_noninteractive.sh
    sudo ./install_agent_noninteractive.sh
    ```
  - Sélectionnez l’IP cible, l’OS (Debian/Ubuntu) et l’agent (Filebeat ou Zabbix).
- **Windows :**  
  - Utilisez `Install_Filebeat.ps1` ou `Install_ZabbixAgent.ps1` dans une session PowerShell admin.

### 4. **Exemples de Vérifications**
- **Filebeat** :
  ```bash
  sudo filebeat test config
  sudo filebeat test output
  ```
- **Zabbix Agent** :
  ```bash
  sudo systemctl status zabbix-agent
  ```
- **Logs** :
  ```bash
  sudo journalctl -u filebeat -f
  sudo journalctl -u zabbix-agent -f
  ```

---

## 🔎 Vérification et Diagnostic Post-Déploiement

1. **Tests de Connectivité**  
   - Ping entre le serveur central et la machine cliente.
   - Vérification du port (ex. `nc -vz <IP_client> 10050` pour Zabbix Agent passif).
2. **Pare-feu**  
   - Vérifier `sudo ufw status` ou `sudo iptables -L -n -v` si un blocage est suspecté.
3. **Consultation des logs**  
   - `journalctl -xeu <nom_du_service>` pour repérer d’éventuelles erreurs.

---

## 📂 Liste des Scripts

### 🔹 `install_monitoring.sh`
- **Description :**  
  Installe et configure Zabbix, Grafana, ELK, Suricata, Fail2ban, Lynis et Vulners sur un serveur Debian.
- **Usage :**
  ```bash
  sudo chmod +x install_monitoring.sh
  sudo ./install_monitoring.sh
  ```

### 🔹 `manage_system.sh`
- **Description :**  
  Script **interactif** pour :
  - Vérifier les logs (locaux et distants),
  - Lancer des audits de sécurité Lynis (local/distants, avec installation auto si absent),
  - Vérifier les vulnérabilités avec Vulners (local/distants, installation auto si absent),
  - Afficher l’historique des audits précédents.
- **Usage :**
  ```bash
  sudo chmod +x manage_system.sh
  sudo ./manage_system.sh
  ```

### 🔹 `install_agent_noninteractive.sh`
- **Description :**  
  Installe à distance (via SSH) Filebeat ou l’agent Zabbix sur Debian/Ubuntu, ou propose des instructions PowerShell pour Windows.
- **Usage :**
  ```bash
  sudo chmod +x install_agent_noninteractive.sh
  sudo ./install_agent_noninteractive.sh
  ```

### 🔹 `elk_agent_install.sh`
- **Description :**  
  Script autonome pour installer Filebeat (Agent ELK) sur Debian.
- **Usage :**
  ```bash
  chmod +x elk_agent_install.sh
  sudo ./elk_agent_install.sh
  ```

### 🔹 `zabbix_agent_install.sh`
- **Description :**  
  Script autonome pour installer et configurer l’agent Zabbix sur Debian.
- **Usage :**
  ```bash
  chmod +x zabbix_agent_install.sh
  sudo ./zabbix_agent_install.sh
  ```

### 🔹 `Install_Filebeat.ps1` (Windows)
- **Description :**  
  Installe et configure Filebeat sur Windows.
- **Usage :**  
  ```powershell
  powershell -ExecutionPolicy Bypass -File Install_Filebeat.ps1
  ```

### 🔹 `Install_ZabbixAgent.ps1` (Windows)
- **Description :**  
  Installe et configure l’agent Zabbix sur Windows.
- **Usage :**  
  ```powershell
  powershell -ExecutionPolicy Bypass -File Install_ZabbixAgent.ps1
  ```

---

## 📌 Auteurs & Contributions
- **Créateur du Projet :**  
  *VAPOTANK – Projet Hackathon SDV 2025*  
- **Support & Issues :**  
  Ouvrir une issue ou contacter l’équipe DevOps via le dépôt du projet.

---

## ✅ Dernière Mise à Jour
**19 Mars 2025**