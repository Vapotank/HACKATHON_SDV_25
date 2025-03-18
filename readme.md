Voici un **README.md** mis à jour pour tous les scripts inclus dans ton projet :

---

# 🛠️ Projet de Monitoring & Gestion des Services

## 📌 Description
Ce projet permet l’installation, la configuration et la gestion des outils de monitoring sur un serveur Debian/Ubuntu et Windows. Il intègre :
- **Zabbix Server & Agent** 🖥️
- **Grafana** 📊
- **ELK Stack (Elasticsearch, Logstash, Kibana)** 📡
- **Suricata IDS** 🔍
- **Fail2Ban** 🚧
- **Lynis & Vulners pour l’audit de sécurité et l’analyse des vulnérabilités** 🔒
- **Un script interactif de gestion des services et des audits** ⚙️

---

## 🚀 Installation

### 🐧 **Installation sur Linux (Debian/Ubuntu)**
Cloner le dépôt et exécuter le script d’installation :
```bash
git clone https://github.com/Vapotank/HACKATHON_SDV_25
cd HACKATHON_SDV_25
chmod +x install_monitoring.sh
sudo ./install_monitoring.sh
```

### 🖥 **Installation sur Windows**
Pour installer l’agent Zabbix et Filebeat sur Windows, télécharger et exécuter les scripts `.ps1` en mode administrateur :

```powershell
Set-ExecutionPolicy Unrestricted -Scope Process
.\Install_ZabbixAgent.ps1
.\Install_Filebeat.ps1
```

---

## 📂 Contenu des Scripts

### 🔹 **Installation & Configuration**
| Script | Description |
|--------|------------|
| `install_monitoring.sh` | Installation complète de Zabbix, ELK, Grafana, Suricata et autres outils sur Debian/Ubuntu |
| `install_zabbix_agent.sh` | Installation et configuration de l’agent Zabbix sur une machine cliente Linux |
| `install_elk_agent.sh` | Installation de Filebeat pour envoyer les logs système à ELK |
| `Install_ZabbixAgent.ps1` | Installation de l’agent Zabbix sur Windows |
| `Install_Filebeat.ps1` | Installation de Filebeat sur Windows |

### 🔹 **Gestion & Monitoring**
| Script | Description |
|--------|------------|
| `manage_system.sh` | Script interactif pour gérer et surveiller les services (Zabbix, ELK, Grafana, Fail2Ban, Suricata) |

---

## 🖥️ **Fonctionnalités du Script de Management (`manage_system.sh`)**
Le script permet de :
- **🔍 Vérifier les logs système (local & distant)**
- **🛡 Auditer la sécurité avec Lynis (local & distant)**
- **📊 Vérifier les vulnérabilités avec Vulners (local & distant)**
- **📂 Visualiser les précédents audits**
- **⚙️ Gérer les services (Zabbix, ELK, Suricata, etc.)**
- **🖥️ Exécuter les audits et analyses CVE sur des serveurs distants !**

### 📜 **Utilisation**
Exécuter le script :
```bash
chmod +x manage_system.sh
./manage_system.sh
```
Le menu interactif vous guidera à travers les options.

---

## 🔧 **Dépannage**
### **1️⃣ Accès à Kibana impossible ?**
- Vérifier si le service tourne :
  ```bash
  systemctl status kibana
  ```
- Modifier la configuration pour autoriser l’accès :
  ```bash
  sudo nano /etc/kibana/kibana.yml
  ```
  Ajouter/modifier :
  ```yaml
  server.host: "0.0.0.0"
  ```

### **2️⃣ Zabbix ne détecte pas l’agent**
- Vérifier la connexion :
  ```bash
  systemctl status zabbix-agent
  ```

### **3️⃣ Grafana ne peut pas se connecter à Zabbix**
- Vérifier l’URL de l’API dans Grafana : `http://<IP>/zabbix/api_jsonrpc.php`

---

## 👨‍💻 **Contributeurs**
Projet développé par **VAPOTANK** et l’équipe Hackathon SDV 25 🚀

---

## 🔗 **Liens Utiles**
- 📘 [Zabbix Documentation](https://www.zabbix.com/documentation)
- 📘 [Grafana Documentation](https://grafana.com/docs/)
- 📘 [Elastic Stack Documentation](https://www.elastic.co/guide/)

---

## 📢 **Contact**
Pour toute question ou amélioration, ouvrez une **issue** sur GitHub ! 🚀

---

