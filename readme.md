---
## 🛠️ Mise à jour en cours
# 📌 Projet de Monitoring & Gestion de Serveurs 

Ce projet propose une solution complète pour déployer et gérer un environnement de surveillance et de sécurité sur des serveurs. Il regroupe plusieurs scripts permettant d'installer et de configurer des services de monitoring, de gestion et d'audit.

---

## 🛠️ Services Installés et Fonctionnalités

### 1. **Zabbix (Server, Frontend et Agent)**
- **Fonctionnalité :** Supervision complète du réseau et des serveurs.
- **Installation :**
  - **Script concerné :** `install_monitoring.sh` (installation de Zabbix Server, Frontend, et Agent sur Debian)
  - **Configuration :**
    - Création d'une base de données Zabbix sur MariaDB.
    - Paramétrage des fichiers de configuration pour le serveur et l'agent.
    - Accès web via l'URL `http://<IP>/zabbix` (identifiants par défaut : Admin / `zabbix`).

### 2. **Grafana**
- **Fonctionnalité :** Visualisation des données de monitoring avec des dashboards interactifs.
- **Installation :**
  - **Script concerné :** `install_monitoring.sh`
  - **Configuration :**
    - Installation via dépôt Grafana.
    - Paramétrage des identifiants d'administration (par défaut : `admin` / `admin123`).
    - Accès via `http://<IP>:3000`.

### 3. **ELK Stack (Elasticsearch, Logstash, Kibana)**
- **Fonctionnalité :** Centralisation, recherche et visualisation des logs.
- **Installation :**
  - **Script concerné :** `install_monitoring.sh`
  - **Configuration :**
    - Installation d'Elasticsearch, Logstash et Kibana.
    - Option de sécurité activée pour Elasticsearch (les mots de passe générés sont stockés dans un fichier temporaire).
    - Accès à Kibana via `http://<IP>:5601`.

### 4. **Filebeat (Agent ELK)**
- **Fonctionnalité :** Collecte et envoi des logs vers Elasticsearch ou Logstash.
- **Installation :**
  - **Script concerné :**
    - Pour les serveurs Linux/Debian : `elk_agent_install.sh` ou via le script interactif d’installation d'agents.
    - Pour Windows : `Install_Filebeat.ps1`
  - **Configuration :**
    - Fichier `/etc/filebeat/filebeat.yml` (ou équivalent pour Windows) configuré pour pointer vers le serveur central.
    - Authentification pour Elasticsearch (par défaut : utilisateur `elastic` / mot de passe `FtGlIjDf9TBUxF5hjbZa`).

### 5. **Zabbix Agent**
- **Fonctionnalité :** Collecte des métriques sur les serveurs clients pour la supervision par Zabbix.
- **Installation :**
  - **Script concerné :**
    - Pour Debian : `zabbix_agent_install.sh` ou via le script interactif d’installation d'agents.
    - Pour Windows : `Install_ZabbixAgent.ps1`
  - **Configuration :**
    - Fichier `/etc/zabbix/zabbix_agentd.conf` mis à jour pour pointer vers le serveur Zabbix (par défaut `192.168.1.41` ou modifiable).

### 6. **Suricata (IDS/IPS)**
- **Fonctionnalité :** Détection d'intrusions et protection contre les attaques réseau.
- **Installation :**
  - **Script concerné :** `install_monitoring.sh`
  - **Configuration :** Optionnelle, avec intégration à ELK via Filebeat.

### 7. **Fail2ban**
- **Fonctionnalité :** Protection contre les attaques par force brute (notamment SSH).
- **Installation :**
  - **Script concerné :** `install_monitoring.sh`
  - **Configuration :** Paramètres de blocage, délai et nombre de tentatives définis.

### 8. **Lynis et Vulners**
- **Fonctionnalité :** Audit de sécurité et détection des vulnérabilités.
- **Installation :**
  - **Script concerné :** `install_monitoring.sh` pour Lynis et Vulners.
  - **Configuration :** Installation d'un environnement virtuel Python pour Vulners.

### 9. **Script de Gestion & Audit – `manage_system.sh`**
- **Fonctionnalité :** 
  - Audit interactif des logs locaux et distants.
  - Exécution d'audits de sécurité via Lynis.
  - Analyse des vulnérabilités via Vulners.
  - Affichage d'un historique des audits.
- **Utilisation :**
  - Exécution en mode interactif, avec un menu en ASCII pour la navigation.
  - Permet de choisir entre différentes actions (vérification de logs, audits, etc.).

---

## 🚀 Déploiement et Instructions d'Installation

### 1. **Pré-requis**
- Serveur sous **Debian 12 (Bookworm)** ou Windows (pour les agents spécifiques).
- Accès root (ou via `sudo`).
- Connexion réseau entre le serveur central et les machines clientes.
- Pour les outils Python (Vulners) :
  ```bash
  sudo apt install python3 python3-pip -y
  python3 -m venv /opt/vulners-venv
  source /opt/vulners-venv/bin/activate
  pip install --upgrade pip vulners
  deactivate
  ```

### 2. **Installation sur le Serveur Central**
1. **Exécuter le script d'installation complet**  
   Utilisez le script `install_monitoring.sh` pour installer et configurer :
   - Zabbix (Server, Frontend, Agent)
   - Grafana
   - ELK Stack (Elasticsearch, Logstash, Kibana)
   - Suricata, Fail2ban, Lynis et Vulners  
   Exemple :
   ```bash
   sudo chmod +x install_monitoring.sh
   sudo ./install_monitoring.sh
   ```
2. **Vérification des services**  
   Une fois l'installation terminée, vérifiez le statut des services avec :
   ```bash
   sudo systemctl status elasticsearch kibana filebeat zabbix-agent zabbix-server
   ```

### 3. **Installation et Configuration des Agents sur les Machines Clients**
- **Linux/Debian Clients :**
  - Vous pouvez déployer les agents Filebeat ou Zabbix via le script interactif d'installation d'agents (`install_agent_noninteractive.sh`).
  - Exécutez le script depuis le serveur de déploiement :
    ```bash
    sudo chmod +x install_agent_noninteractive.sh
    sudo ./install_agent_noninteractive.sh
    ```
  - Suivez le menu interactif pour saisir l'IP cible, choisir le système (Debian/Ubuntu) et le type d'agent (Filebeat ou Zabbix).  
  - **Filebeat** sera automatiquement configuré pour envoyer les logs (ainsi qu'une configuration minimale d'input) vers Elasticsearch sur le serveur central avec authentification.
  
- **Windows Clients :**
  - Utilisez les scripts PowerShell fournis (`Install_Filebeat.ps1` et `Install_ZabbixAgent.ps1`).
  - Le script interactif affiche les commandes à copier-coller dans une session PowerShell en mode administrateur.  
  - Assurez-vous que le téléchargement depuis votre domaine est accessible pour récupérer les scripts.

### 4. **Instructions pour le Redeploiement sur d'autres Infrastructures**
Pour adapter le déploiement à une nouvelle infrastructure :
- **Modifier les paramètres suivants** dans les scripts (souvent en haut des fichiers) :
  - **SERVER_IP** : Adresse IP du serveur central de monitoring (par exemple, dans `install_monitoring.sh` et `install_agent_noninteractive.sh`).
  - **Identifiants et ports** : Pour Elasticsearch, Grafana, Zabbix et autres services.  
  - **Dépôts et clés GPG** : Vérifiez que les URL et clés pour les dépôts sont toujours valides pour la nouvelle infrastructure.
- **Vérifier les prérequis système** (versions de Debian, accès réseau, etc.).
- **Adapter les chemins et configurations spécifiques** (ex. chemins de logs ou paramètres personnalisés dans les fichiers de configuration).
- **Tester chaque service individuellement** après déploiement pour s'assurer que la communication entre les agents et le serveur central est opérationnelle.

---

## 🔎 Vérification et Diagnostic

Après chaque déploiement, procédez aux vérifications suivantes :

1. **Test de Configuration et de Sortie pour Filebeat**  
   ```bash
   sudo filebeat test config
   sudo filebeat test output
   ```
2. **Vérification des Services**  
   Utilisez `systemctl status` pour chaque service :
   ```bash
   sudo systemctl status filebeat
   sudo systemctl status elasticsearch
   sudo systemctl status kibana
   sudo systemctl status zabbix-server
   sudo systemctl status zabbix-agent
   ```
3. **Consultation des Logs**  
   Pour Filebeat :
   ```bash
   sudo journalctl -u filebeat -f
   ```
   Pour Elasticsearch, Zabbix et autres, consultez les logs dans `/var/log/`.

---

## 📂 Liste des Scripts Disponibles

### 🔹 `install_monitoring.sh`
- **Description :**  
  Script complet pour installer et configurer Zabbix, Grafana, ELK (Elasticsearch, Logstash, Kibana), Suricata, Fail2ban, Lynis et Vulners sur un serveur Debian.
- **Utilisation :**
  ```bash
  sudo chmod +x install_monitoring.sh
  sudo ./install_monitoring.sh
  ```

### 🔹 `manage_system.sh`
- **Description :**  
  Script interactif pour la gestion et l’audit du système :
  - Vérification des logs locaux et distants
  - Exécution d'audits de sécurité avec Lynis
  - Analyse de vulnérabilités avec Vulners
  - Affichage des audits précédents
- **Utilisation :**
  ```bash
  sudo chmod +x manage_system.sh
  sudo ./manage_system.sh
  ```

### 🔹 `elk_agent_install.sh` et `zabbix_agent_install.sh`
- **Description :**  
  Scripts pour installer et configurer respectivement Filebeat et l'agent Zabbix sur une machine Debian.
- **Utilisation :**
  ```bash
  sudo chmod +x elk_agent_install.sh
  sudo ./elk_agent_install.sh

  sudo chmod +x zabbix_agent_install.sh
  sudo ./zabbix_agent_install.sh
  ```

### 🔹 `Install_Filebeat.ps1` et `Install_ZabbixAgent.ps1`
- **Description :**  
  Scripts PowerShell pour installer et configurer Filebeat et l'agent Zabbix sur Windows.
- **Utilisation :**  
  Exécutez-les dans une session PowerShell en mode administrateur :
  ```powershell
  powershell -ExecutionPolicy Bypass -File Install_Filebeat.ps1
  powershell -ExecutionPolicy Bypass -File Install_ZabbixAgent.ps1
  ```

### 🔹 `install_agent_noninteractive.sh`
- **Description :**  
  Script interactif pour installer à distance Filebeat ou l’agent Zabbix sur une machine cible (Debian ou Windows).  
  Pour Debian, il se connecte via SSH, installe le paquet et recrée la configuration de manière automatique (incluant les inputs pour Filebeat et l'authentification pour Elasticsearch).  
  Pour Windows, il affiche les commandes à copier dans une session PowerShell.
- **Utilisation :**
  ```bash
  sudo chmod +x install_agent_noninteractive.sh
  sudo ./install_agent_noninteractive.sh
  ```

---

## 📌 Auteurs & Contributions

- **Créateur du Projet :**  
  *Projet Hackathon SDV 2025*  
- **Contributions & Support :**  
  Pour signaler des problèmes, ouvrir une issue ou contacter l'équipe DevOps via le dépôt du projet.

---

## ✅ Dernière Mise à Jour
**19 Mars 2025**

---
