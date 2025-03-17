

---

# README - Scripts d’installation et de gestion du monitoring

Ce dépôt contient différents scripts permettant d’installer et de configurer une plateforme de supervision et de sécurité sur Debian (ou Windows, pour les scripts PowerShell). La stack inclut :

- **Zabbix** (Server + Agent)  
- **Grafana**  
- **Fail2ban**  
- **Lynis**  
- **Vulners**  
- **ELK** (Elasticsearch, Logstash, Kibana)  
- **Suricata** (IDS/IPS)  
- **Firewall UFW** et dépendances réseau

## Sommaire

1. [Scripts Linux (Debian)](#scripts-linux-debian)
    1. [install_monitoring.sh](#1-install_monitoringsh)  
    2. [manage_system.sh](#2-manage_systemsh)  
    3. [zabbix_agent_install.sh](#3-zabbix_agent_installsh)  
    4. [elk_agent_install.sh](#4-elk_agent_installsh-filebeat)

2. [Scripts Windows (PowerShell)](#scripts-windows-powershell)
    1. [Install_ZabbixAgent.ps1](#1-install_zabbixagentps1)  
    2. [Install_Filebeat.ps1](#2-install_filebeatps1)

3. [Configuration et identifiants](#configuration-et-identifiants)
4. [Contributions et remarques](#contributions-et-remarques)
5. [Licence](#licence)

---

## Scripts Linux (Debian)

### 1) `install_monitoring.sh`
**Objectif** : Installer automatiquement l’ensemble de la stack de supervision (Zabbix, Grafana, Fail2ban, ELK, Suricata…) sur un serveur Debian (11 ou 12).

**Fonctionnalités** :
- Mise à jour du système et installation des **dépendances** (iptables, ufw, python3, pip, etc.)
- Proposition d’installation interactive pour **Zabbix, Grafana, ELK, Suricata**, etc.
- Configuration automatique des **mots de passe** (MySQL root, base Zabbix, Grafana admin, Elasticsearch, etc.)
- Intégration Suricata → ELK via Filebeat si désiré
- Activation ou non du **firewall UFW** avec règles basiques (SSH, HTTP, HTTPS, Grafana, Kibana, etc.)

**Usage** :
1. Rendre le script exécutable :
    ```bash
    chmod +x install_monitoring.sh
    ```
2. Lancer le script en root (ou avec `sudo`) :
    ```bash
    sudo ./install_monitoring.sh
    ```
3. Répondre aux questions (y/n).  
4. À la fin, un récapitulatif affiche l’adresse IP et les identifiants.

---

### 2) `manage_system.sh`
**Objectif** : Script de **gestion & maintenance** avec **interface interactive**.

**Fonctionnalités** :
- Menu coloré (ASCII Art) pour **vérifier/redémarrer** les services (Zabbix, Grafana, Kibana, etc.)
- **Nettoyage des logs**, audit de sécurité (Lynis), vérification CVE (Vulners)
- **Mise à jour** du système
- Correction automatique de la base Zabbix si incomplète
- Vérification du statut de MySQL/MariaDB, Suricata, etc.

**Usage** :
1. Copier le script dans `manage_system.sh`
2. `chmod +x manage_system.sh`
3. `sudo ./manage_system.sh`
4. Choisir l’action dans le menu (1 à 9)

---

### 3) `zabbix_agent_install.sh`
**Objectif** : Installer et configurer **l’agent Zabbix** sur un serveur Debian.

**Fonctionnalités** :
- Installe le dépôt officiel Zabbix
- Installe le paquet `zabbix-agent`
- Configure la connexion (Server/ServerActive/Hostname)
- Démarre et active l’agent

**Usage** :
```bash
chmod +x zabbix_agent_install.sh
sudo ./zabbix_agent_install.sh
```
Adapter dans le script :
- `ZABBIX_SERVER_IP` (adresse du serveur Zabbix)
- `AGENT_HOSTNAME` (nom qui apparaîtra dans Zabbix)

---

### 4) `elk_agent_install.sh` (Filebeat)
**Objectif** : Installer **Filebeat** et l’envoyer vers **Elasticsearch** ou **Logstash**.

**Fonctionnalités** :
- Installation de la clé GPG et dépôt Elastic
- Configuration de `filebeat.yml` pour envoyer les logs
- Active et démarre Filebeat comme service

**Usage** :
```bash
chmod +x elk_agent_install.sh
sudo ./elk_agent_install.sh
```
Adapter dans le script :
- `ELASTICSEARCH_HOST` ou `LOGSTASH_HOST`
- `USE_LOGSTASH=true` si on veut passer par Logstash

---

## Scripts Windows (PowerShell)

### 1) `Install_ZabbixAgent.ps1`
**Objectif** : Installer et configurer **Zabbix Agent** sur Windows.

**Fonctionnalités** :
- Télécharge le MSI Zabbix (depuis cdn.zabbix.com)
- Installation silencieuse (`msiexec /qn`)
- Mise à jour du fichier `zabbix_agentd.conf` (Server, Hostname)
- Démarre et active le service Zabbix Agent

**Usage** :
1. Ouvrir PowerShell **en Administrateur**  
2. Exécuter :
   ```powershell
   .\Install_ZabbixAgent.ps1 -ZabbixServer "192.168.1.56" -Hostname "WinAgent"
   ```
3. Vérifier que le service `Zabbix Agent` tourne dans Services.msc

---

### 2) `Install_Filebeat.ps1`
**Objectif** : Installer et configurer **Filebeat** (ELK) sur Windows.

**Fonctionnalités** :
- Télécharge l’archive ZIP de Filebeat depuis le site Elastic
- Extrait dans `C:\Program Files\Filebeat`
- Configure la sortie (Elasticsearch ou Logstash) dans `filebeat.yml`
- Installe et démarre le service Windows

**Usage** :
1. Ouvrir PowerShell **en Administrateur**  
2. Exécuter :
   ```powershell
   .\Install_Filebeat.ps1 -ElasticsearchHost "192.168.1.56:9200" -UseLogstash $False
   ```
3. Si `-UseLogstash $True`, adapter `-LogstashHost "192.168.1.56:5044"`.

---

## Configuration et identifiants

- **MySQL/MariaDB**  
  - Par défaut, le script `install_monitoring.sh` définit le mot de passe root MySQL dans la variable `MYSQL_ROOT_PASSWORD`.
  - Base `zabbix` créée avec user `zabbix / zabbix_pass`.

- **Zabbix Frontend**  
  - Accessible à `http://<IP>/zabbix`.  
  - Identifiants initiaux : `Admin / zabbix`.

- **Grafana**  
  - Par défaut : `http://<IP>:3000`.  
  - Admin user/password configurés par `GRAFANA_ADMIN_USER` et `GRAFANA_ADMIN_PASS`.

- **Elasticsearch / Kibana**  
  - Si la sécurité est activée (`ENABLE_ELASTIC_SECURITY=true`), les mots de passe sont générés automatiquement par `elasticsearch-setup-passwords`.  
  - Stockés dans `/tmp/es_passwords.txt`.  
  - Kibana est accessible à `http://<IP>:5601`.

- **Suricata**  
  - Installé en mode IDS par défaut (logs dans `/var/log/suricata/`).  
  - Possibilité d’envoyer les logs dans ELK via Filebeat.

---

## Contributions et remarques

- Vous pouvez **modifier les scripts** pour adapter les versions (Debian 11/12, Ubuntu, etc.).
- Les **mots de passe en clair** sont là pour la démonstration. **En production**, modifiez-les et/ou stockez-les en lieu sûr.
- Pour un mode **IPS Suricata**, éditez `/etc/suricata/suricata.yaml` et configurez les règles iptables/nfqueue.

---

## Licence

Tous les scripts sont proposés **à titre d’exemple** sans aucune garantie. Utilisez-les à vos risques et **testez** toujours en environnement de préproduction.

---

**Fin du README**  
