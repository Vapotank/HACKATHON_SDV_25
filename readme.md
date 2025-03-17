# Installation et Configuration Automatisée de la Supervision Réseau

Ce script permet d'automatiser l'installation et la configuration des outils de supervision et de sécurité sur un serveur Debian.

## Outils installés
- **Zabbix** : Supervision et monitoring
- **Grafana** : Visualisation des métriques
- **Fail2ban** : Protection contre les attaques bruteforce
- **Lynis** : Audit de sécurité
- **Vulners** : Détection des vulnérabilités CVE
- **ELK (Elasticsearch, Logstash, Kibana)** : Collecte et visualisation des logs

## Prérequis
- Un serveur Debian récent
- Accès root ou utilisateur avec privilèges sudo

## Installation
1. **Télécharger le script**
   ```bash
   wget https://github.com/votre-repo/install_monitoring.sh -O install_monitoring.sh
   ```
2. **Rendre le script exécutable**
   ```bash
   chmod +x install_monitoring.sh
   ```
3. **Lancer le script**
   ```bash
   sudo ./install_monitoring.sh
   ```

## Vérification de l'installation
- **Zabbix** : Accédez à `http://<votre-ip>/zabbix`
- **Grafana** : Accédez à `http://<votre-ip>:3000`
- **Kibana** : Accédez à `http://<votre-ip>:5601`
- **Fail2ban** : Vérifiez les logs avec `sudo journalctl -u fail2ban --no-pager`
- **Audit de sécurité** : Lancez `sudo lynis audit system`
- **Détection CVE** : Exécutez `vulners -s system`

## Logs et Debug
Toutes les actions sont enregistrées dans `/var/log/auto_monitoring.log`.

## Contribution
N'hésitez pas à proposer des améliorations ou à signaler des bugs via des issues sur GitHub.

## Licence
Ce projet est sous licence MIT.

