# Documentation du Makefile - Système de Test Local deces-ui

## Table des matières

1. [Vue d'ensemble](#vue-densemble)
2. [Architecture du système](#architecture-du-système)
3. [Prérequis système](#prérequis-système)
4. [Variables d'environnement](#variables-denvironnement)
5. [Installation et configuration](#installation-et-configuration)
6. [Phase de développement (échantillon)](#phase-de-développement-échantillon)
7. [Phase de validation (données complètes)](#phase-de-validation-données-complètes)
8. [Référence des cibles Makefile](#référence-des-cibles-makefile)
9. [Workflows recommandés](#workflows-recommandés)
10. [Troubleshooting](#troubleshooting)
11. [Bonnes pratiques](#bonnes-pratiques)

---

## Vue d'ensemble

Le [`Makefile`](Makefile:1) orchestre l'ensemble du processus de développement et de test de l'application **deces-ui**, un moteur de recherche des personnes décédées basé sur les données INSEE. Il gère :

- **Frontend** : Application Svelte avec rechargement à chaud
- **Backend** : API TypeScript pour le traitement des appariements
- **Elasticsearch** : Moteur d'indexation et de recherche des données de décès
- **Nginx** : Reverse proxy et serveur statique
- **Tests** : Suite de tests Playwright pour validation end-to-end

Le système supporte deux phases de développement distinctes :
1. **Phase rapide** : Utilisation d'échantillons de données archivés (.tar) pour des tests itératifs
2. **Phase complète** : Validation avec l'intégralité du jeu de données INSEE

---

## Architecture du système

### Composants principaux

```
┌─────────────────────────────────────────────────────────────┐
│                      Navigateur (localhost:8083)             │
└───────────────────────────────┬─────────────────────────────┘
                                │
                    ┌───────────▼──────────┐
                    │   Nginx (Port 8083)  │
                    │   Reverse Proxy      │
                    └─────┬─────────┬──────┘
                          │         │
        ┌─────────────────┘         └──────────────────┐
        │                                               │
┌───────▼────────┐                           ┌─────────▼─────────┐
│   Frontend     │                           │   Backend         │
│   (Svelte)     │                           │   (Port 8080)     │
│   Port 8083    │                           │   API TypeScript  │
└────────────────┘                           └─────────┬─────────┘
                                                       │
                                             ┌─────────▼─────────┐
                                             │  Elasticsearch    │
                                             │  (Port 9200)      │
                                             │  Index: deces     │
                                             └───────────────────┘
```

### Fichiers de configuration

- [`docker-compose-dev.yml`](docker-compose-dev.yml:1) : Environnement de développement avec rechargement à chaud
- [`docker-compose.yml`](docker-compose.yml:1) : Environnement de production (build statique)
- [`docker-compose-elasticsearch.yml`](docker-compose-elasticsearch.yml:1) : Configuration Elasticsearch isolée
- [`docker-compose-test.yml`](docker-compose-test.yml:1) : Environnement de test avec Playwright

---

## Prérequis système

### Logiciels requis

| Logiciel | Version minimale | Commande de vérification |
|----------|------------------|--------------------------|
| **Docker** | 20.10+ | `docker --version` |
| **Docker Compose** | 1.29+ | `docker-compose --version` |
| **Make** | 4.0+ | `make --version` |
| **Git** | 2.25+ | `git --version` |
| **Node.js** | 12.14+ | `node --version` |
| **curl** | 7.0+ | `curl --version` |
| **Bash** | 4.0+ | `bash --version` |

### Configuration système requise

#### Mémoire virtuelle Elasticsearch

Elasticsearch nécessite une augmentation de `vm.max_map_count` :

```bash
# Vérification
cat /etc/sysctl.conf | grep vm.max_map_count

# Configuration temporaire
sudo sysctl -w vm.max_map_count=262144

# Configuration permanente
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

> **Note** : Le [`Makefile`](Makefile:463) gère automatiquement cette vérification via la cible [`vm_max`](Makefile:463).

#### Espace disque requis

| Composant | Espace minimal | Phase |
|-----------|---------------|-------|
| Images Docker | 5 GB | Toujours |
| Elasticsearch (échantillon) | 2 GB | Développement |
| Elasticsearch (données complètes) | 50 GB | Validation |
| Logs et statistiques | 5 GB | Optionnel |

#### Mémoire RAM

- **Développement** : 8 GB minimum (16 GB recommandé)
- **Production** : 16 GB minimum (32 GB recommandé)

---

## Variables d'environnement

### Variables principales

Ces variables sont définies dans le [`Makefile`](Makefile:1) et peuvent être surchargées dans le fichier [`artifacts`](Makefile:169) (non versionné).

#### Frontend

```bash
export PORT=8083                          # Port de l'application
export FRONTEND_DEV_HOST=frontend-development
export FRONTEND_DEV_PORT=8083
export AB_THRESHOLD=100                   # Seuil A/B testing (%)
export GOOGLE_ANALYTICS_ID=               # ID Google Analytics (optionnel)
export GOOGLE_ADSENSE_ID=                 # ID Google Adsense (optionnel)
```

#### Backend

```bash
export BACKEND_PORT=8080                  # Port du backend
export BACKEND_HOST=backend
export BACKEND_JOB_CONCURRENCY=6          # Jobs parallèles
export BACKEND_CHUNK_CONCURRENCY=3        # Chunks parallèles
export BACKEND_TMP_MAX=150                # Requêtes max avant ban
export BACKEND_TMP_DURATION=14400         # Durée du ban (secondes)
export BACKEND_TMP_WINDOW=86400           # Fenêtre de reset (secondes)
export BACKEND_TOKEN_USER=${API_EMAIL}    # Utilisateur de l'API
export BACKEND_TOKEN_KEY=$(openssl rand -base64 16)
export BACKEND_TOKEN_PASSWORD=$(openssl rand -base64 16)
```

#### Elasticsearch

```bash
export ES_HOST=elasticsearch              # Hôte Elasticsearch
export ES_PORT=9200                       # Port Elasticsearch
export ES_TIMEOUT=60                      # Timeout de connexion (s)
export ES_RESTORE_TIMEOUT=480             # Timeout de restauration (s)
export ES_INDEX=deces                     # Nom de l'index
export ES_MAX_RESULTS=10000               # Résultats max par requête
export ES_DATA=${APP_PATH}/esdata         # Répertoire des données
export ES_MEM=512m                        # Mémoire allouée
export ES_JAVA_OPTS=-Xms${ES_MEM} -Xmx${ES_MEM}
export ES_VERSION=8.6.1                   # Version d'Elasticsearch
```

#### Fichiers de données

```bash
# Échantillon (développement)
export FILES_TO_PROCESS_TEST=deces-2020-m01.txt.gz
export FILES_TO_PROCESS_DEV=deces-2020-m[0-1][0-9].txt.gz

# Données complètes (production)
export FILES_TO_PROCESS='deces-([0-9]{4}|2025-m[0-9]{2}).txt.gz'
```

#### Stockage S3/Scaleway

```bash
export REPOSITORY_BUCKET=fichier-des-personnes-decedees-elasticsearch
export REPOSITORY_BUCKET_DEV=fichier-des-personnes-decedees-elasticsearch-dev
export STORAGE_ACCESS_KEY=                # Clé d'accès (dans artifacts)
export STORAGE_SECRET_KEY=                # Clé secrète (dans artifacts)
export SCW_REGION=fr-par                  # Région Scaleway
export SCW_ENDPOINT=s3.fr-par.scw.cloud   # Endpoint S3
```

### Fichier `artifacts`

Créez un fichier [`artifacts`](Makefile:169) à la racine du projet (ignoré par Git) :

```bash
# Credentials Scaleway/S3
export STORAGE_ACCESS_KEY=votre_access_key
export STORAGE_SECRET_KEY=votre_secret_key

# Email et tokens
export API_EMAIL=votre.email@example.com
export BACKEND_TOKEN_USER=${API_EMAIL}
export BACKEND_TOKEN_KEY=$(openssl rand -base64 16)
export BACKEND_TOKEN_PASSWORD=$(openssl rand -base64 16)

# Options avancées
export ES_MEM=2g                          # Plus de mémoire pour ES
export BACKEND_LOG_LEVEL=debug            # Logs détaillés
```

---

## Installation et configuration

### 1. Clonage du projet

```bash
# Cloner le dépôt principal
git clone https://github.com/matchid-project/deces-ui.git
cd deces-ui

# Créer le fichier artifacts
touch artifacts
chmod 600 artifacts
```

### 2. Configuration minimale

```bash
# Installer les outils et dépendances
make config
```

**Cette commande** ([`config`](Makefile:217)) :
- Clone le dépôt [`tools`](Makefile:199) si nécessaire
- Installe les dépendances système
- Configure Docker et Docker Compose
- Crée le réseau Docker

### 3. Création du réseau Docker

```bash
# Créer le réseau deces-ui
make network
```

Le réseau Docker [`deces-ui`](Makefile:102) permet la communication entre tous les conteneurs.

### 4. Vérification de la configuration

```bash
# Afficher les variables d'environnement
make show-env

# Vérifier la version de l'application
make version
```

---

## Phase de développement (échantillon)

Cette phase utilise un **échantillon des données** pour des tests rapides et itératifs.

### 1. Préparation des données

#### Option A : Restauration depuis une archive .tar

Si vous disposez d'une archive Elasticsearch pré-indexée :

```bash
# Structure attendue
backup/
└── esdata_<version>_<data_version>.tar

# Extraire l'archive
cd backup
tar -xzf esdata_<version>_<data_version>.tar -C ../esdata/
cd ..
```

#### Option B : Restauration depuis un snapshot S3

```bash
# Télécharger et restaurer un snapshot
make elasticsearch
make elasticsearch-restore
```

**Workflow de la restauration** ([`elasticsearch-restore`](Makefile:433)) :
1. Configure les credentials S3 dans Elasticsearch
2. Enregistre le repository S3
3. Restaure le snapshot depuis le bucket
4. Attend la fin de la restauration (timeout: 480s)

### 2. Démarrage de l'environnement de développement

```bash
# Démarrer tous les services (Elasticsearch, Backend dev, Frontend dev)
make dev
```

**Cette commande** ([`dev`](Makefile:332)) lance séquentiellement :
1. **Réseau Docker** : Crée [`deces-ui`](Makefile:102) si nécessaire
2. **Elasticsearch** : Démarre et attend la disponibilité
3. **Backend dev** : Clone et démarre en mode développement
4. **Frontend dev** : Build et démarre avec rechargement à chaud

### 3. Accès aux services

| Service | URL | Description |
|---------|-----|-------------|
| **Frontend** | http://localhost:8083 | Interface de recherche |
| **Backend API** | http://localhost:8083/deces/api/v1 | API backend |
| **Elasticsearch** | http://localhost:9200 | API Elasticsearch (interne) |

### 4. Développement avec rechargement à chaud

Le frontend utilise Rollup avec [`livereload`](package.json:28) :

```bash
# Les modifications dans src/ sont automatiquement compilées
# Le navigateur se recharge automatiquement

# Vérifier les logs du frontend
docker logs -f deces-ui-frontend-development
```

### 5. Tests en mode développement

```bash
# Tester l'API backend
make local-test-api

# Lancer les tests UI (Playwright)
make frontend-test
```

### 6. Arrêt des services

```bash
# Arrêter tous les services de développement
make dev-stop
```

---

## Phase de validation (données complètes)

Cette phase utilise **l'intégralité des données INSEE** pour la validation finale.

### 1. Préparation des versions de données

```bash
# Générer les fichiers de version
make ${DATAPREP_VERSION_FILE}
make ${DATA_VERSION_FILE}
```

Ces commandes ([`${DATAPREP_VERSION_FILE}`](Makefile:490) et [`${DATA_VERSION_FILE}`](Makefile:496)) :
- Calculent les checksums des recettes de traitement
- Interrogent le catalogue data.gouv.fr
- Génèrent les fichiers `.dataprep.sha1` et `.data.sha1`

### 2. Restauration de l'index complet

```bash
# Restaurer le snapshot complet depuis S3
make elasticsearch
make elasticsearch-restore
```

**Différences avec la phase de développement** :
- Variable [`FILES_TO_PROCESS`](Makefile:152) : Tous les fichiers depuis 1970
- Temps de restauration : 30-60 minutes
- Espace disque : ~50 GB

### 3. Démarrage en mode production

```bash
# Build des images de production
make build

# Démarrage complet
make start
```

**Cette commande** ([`start`](Makefile:396)) lance :
1. **Elasticsearch** : Avec l'index complet
2. **Backend** : En mode production (image Docker)
3. **Frontend** : Build statique via Nginx
4. Affiche les logs après 2 secondes

### 4. Tests de validation complète

#### Test API de base

```bash
# Vérifier le bon fonctionnement de l'API
make local-test-api
```

Cette commande envoie une requête de test ([`API_TEST_REQUEST`](Makefile:96)) et vérifie la réponse.

#### Tests backend complets

```bash
# Si le backend est configuré
cd deces-backend
make backend-test
```

#### Tests UI end-to-end

```bash
# Tests Playwright complets
make frontend-test
```

Les tests vérifient :
- Recherche simple ([`simpleSearch.js`](ui-test/simpleSearch.js))
- Recherche avancée ([`advancedSearch.js`](ui-test/advancedSearch.js))
- Appariement avec Wikidata ([`linkWikidata.js`](ui-test/linkWikidata.js))

### 5. Déploiement local complet

```bash
# Déploiement avec restauration asynchrone
make deploy-local
```

**Cette commande** ([`deploy-local`](Makefile:505)) :
1. Configure l'environnement minimal
2. Lance la restauration Elasticsearch en asynchrone
3. Vérifie la configuration Docker
4. Démarre tous les services
5. Lance les statistiques en arrière-plan
6. Teste l'API

### 6. Monitoring et logs

```bash
# Voir les logs en temps réel
docker-compose logs -f

# Logs d'un service spécifique
docker logs -f deces-ui-nginx
docker logs -f deces-ui-elasticsearch

# Statistiques en direct
make stats-live
```

### 7. Arrêt des services

```bash
# Arrêt complet
make stop

# Ou redémarrage
make restart
```

---

## Référence des cibles Makefile

### Configuration et installation

#### `config`
**Ligne** : [`217`](Makefile:217)  
**Description** : Installation complète des outils et dépendances.

```bash
make config
```

**Actions** :
- Clone le dépôt [`tools`](Makefile:113) depuis GitHub
- Installe les outils système nécessaires
- Configure Docker et Docker Compose
- Copie le fichier artifacts

#### `config-minimal`
**Ligne** : [`197`](Makefile:197)  
**Description** : Installation minimale (sans configuration avancée).

```bash
make config-minimal
```

**Usage** : Pour les environnements CI/CD ou les déploiements distants.

#### `config-stats`
**Ligne** : [`205`](Makefile:205)  
**Description** : Installation des dépendances pour les statistiques.

```bash
make config-stats
```

**Dépendances Perl installées** :
- `libdate-calc-perl`
- `libjson-xs-perl`
- `libmaxmind-db-reader-perl`
- `libgeoip2-perl`

#### `network`
**Ligne** : [`269`](Makefile:269)  
**Description** : Crée le réseau Docker [`deces-ui`](Makefile:102).

```bash
make network
```

### Elasticsearch

#### `elasticsearch-start`
**Ligne** : [`469`](Makefile:469)  
**Description** : Démarre Elasticsearch sans attendre.

```bash
make elasticsearch-start
```

**Configuration** :
- Version : [`8.6.1`](Makefile:148)
- Mémoire : [`512m`](Makefile:146) (configurable)
- Répertoire de données : [`esdata/node1`](Makefile:144)

#### `elasticsearch`
**Ligne** : [`474`](Makefile:474)  
**Description** : Démarre et attend qu'Elasticsearch soit prêt.

```bash
make elasticsearch
```

**Timeout** : [`60 secondes`](Makefile:140)

#### `elasticsearch-repository-creds`
**Ligne** : [`412`](Makefile:412)  
**Description** : Configure les credentials S3 dans Elasticsearch.

```bash
make elasticsearch-repository-creds
```

**Actions** :
- Injecte [`STORAGE_ACCESS_KEY`](Makefile:171) dans le keystore
- Injecte [`STORAGE_SECRET_KEY`](Makefile:172) dans le keystore
- Redémarre Elasticsearch

#### `elasticsearch-repository-config`
**Ligne** : [`424`](Makefile:424)  
**Description** : Configure le repository S3 pour les snapshots.

```bash
make elasticsearch-repository-config
```

**Prérequis** : `elasticsearch-repository-creds`

#### `elasticsearch-restore`
**Ligne** : [`433`](Makefile:433)  
**Description** : Restaure un snapshot de manière synchrone.

```bash
make elasticsearch-restore
```

**Durée** : Variable selon la taille des données (5-60 minutes)  
**Mode** : Bloquant avec `wait_for_completion=true`

#### `elasticsearch-restore-async`
**Ligne** : [`446`](Makefile:446)  
**Description** : Restaure un snapshot de manière asynchrone.

```bash
make elasticsearch-restore-async
```

**Avantage** : Permet de continuer les opérations pendant la restauration.

#### `elasticsearch-index-readiness`
**Ligne** : [`477`](Makefile:477)  
**Description** : Attend que l'index soit en état `green`.

```bash
make elasticsearch-index-readiness
```

**Timeout** : [`480 secondes`](Makefile:141)

#### `elasticsearch-clean`
**Ligne** : [`460`](Makefile:460)  
**Description** : Supprime Elasticsearch et toutes ses données.

```bash
make elasticsearch-clean
```

⚠️ **ATTENTION** : Cette commande supprime définitivement les données locales.

#### `elasticsearch-stop`
**Ligne** : [`408`](Makefile:408)  
**Description** : Arrête Elasticsearch.

```bash
make elasticsearch-stop
```

### Backend

#### `backend-config`
**Ligne** : [`272`](Makefile:272)  
**Description** : Clone et configure le backend.

```bash
make backend-config
```

**Actions** :
- Clone [`deces-backend`](Makefile:109) depuis GitHub
- Checkout de la branche [`dev`](Makefile:111)

#### `backend-dev`
**Ligne** : [`280`](Makefile:280)  
**Description** : Démarre le backend en mode développement.

```bash
make backend-dev
```

**Fonctionnalités** :
- Rechargement à chaud du code TypeScript
- Logs détaillés
- Debugger activé

#### `backend`
**Ligne** : [`298`](Makefile:298)  
**Description** : Démarre le backend en mode production.

```bash
make backend
```

**Prérequis** :
- [`backend-docker-check`](Makefile:294) : Vérifie la présence de l'image Docker
- [`proofs-mount`](Makefile:753) : Monte le système de preuves
- [`elasticsearch-index-readiness`](Makefile:477) : Attend l'index Elasticsearch

#### `backend-dev-stop`
**Ligne** : [`288`](Makefile:288)  
**Description** : Arrête le backend en mode développement.

```bash
make backend-dev-stop
```

#### `backend-stop`
**Ligne** : [`306`](Makefile:306)  
**Description** : Arrête le backend en mode production.

```bash
make backend-stop
```

#### `backend-clean-dir`
**Ligne** : [`311`](Makefile:311)  
**Description** : Supprime le répertoire du backend.

```bash
make backend-clean-dir
```

### Frontend

#### `frontend-dev`
**Ligne** : [`319`](Makefile:319)  
**Description** : Démarre le frontend en mode développement.

```bash
make frontend-dev
```

**Fichier de configuration** : [`docker-compose-dev.yml`](docker-compose-dev.yml:1)

**Fonctionnalités** :
- Rechargement à chaud (port [`35729`](docker-compose-dev.yml:60))
- Source maps activées
- Logs détaillés

#### `frontend-build`
**Ligne** : [`367`](Makefile:367)  
**Description** : Build le frontend pour la production.

```bash
make frontend-build
```

**Étapes** :
1. Crée l'archive source ([`FILE_FRONTEND_APP_VERSION`](Makefile:183))
2. Build avec Rollup dans Docker
3. Génère l'archive des assets compilés

#### `frontend`
**Ligne** : [`387`](Makefile:387)  
**Description** : Démarre le frontend en mode production (via Nginx).

```bash
make frontend
```

**Configuration** : [`docker-compose.yml`](docker-compose.yml:1)

#### `frontend-dev-stop`
**Ligne** : [`329`](Makefile:329)  
**Description** : Arrête le frontend en mode développement.

```bash
make frontend-dev-stop
```

#### `frontend-stop`
**Ligne** : [`384`](Makefile:384)  
**Description** : Arrête le frontend en mode production.

```bash
make frontend-stop
```

#### `frontend-clean-dist`
**Ligne** : [`369`](Makefile:369)  
**Description** : Nettoie les archives de distribution.

```bash
make frontend-clean-dist
```

### Build

#### `build`
**Ligne** : [`336`](Makefile:336)  
**Description** : Build complet du frontend et de Nginx.

```bash
make build
```

**Sous-commandes** :
1. [`clean-frontend`](Makefile:232) : Nettoie les builds précédents
2. [`frontend-build`](Makefile:367) : Build le frontend
3. [`nginx-build`](Makefile:379) : Build l'image Nginx

#### `nginx-build`
**Ligne** : [`379`](Makefile:379)  
**Description** : Build l'image Nginx avec le frontend.

```bash
make nginx-build
```

**Prérequis** : Archive de distribution du frontend

### Développement complet

#### `dev`
**Ligne** : [`332`](Makefile:332)  
**Description** : Lance l'environnement de développement complet.

```bash
make dev
```

**Séquence de démarrage** :
1. [`network`](Makefile:269) : Réseau Docker
2. [`frontend-stop`](Makefile:384) : Arrêt du frontend prod
3. [`elasticsearch`](Makefile:474) : Elasticsearch
4. [`backend-dev`](Makefile:280) : Backend dev
5. [`frontend-dev`](Makefile:319) : Frontend dev

#### `dev-stop`
**Ligne** : [`334`](Makefile:334)  
**Description** : Arrête l'environnement de développement.

```bash
make dev-stop
```

### Production

#### `start`
**Ligne** : [`396`](Makefile:396)  
**Description** : Démarre tous les services en mode production.

```bash
make start
```

**Séquence** :
1. [`elasticsearch`](Makefile:474)
2. [`backend`](Makefile:298)
3. [`frontend`](Makefile:387)
4. Affiche les logs

#### `stop`
**Ligne** : [`393`](Makefile:393)  
**Description** : Arrête tous les services.

```bash
make stop
```

#### `restart`
**Ligne** : [`484`](Makefile:484)  
**Description** : Redémarre tous les services.

```bash
make restart
```

**Équivalent à** : `make down && make up`

#### `up`
**Ligne** : [`480`](Makefile:480)  
**Description** : Alias pour [`start`](Makefile:396).

```bash
make up
```

#### `down`
**Ligne** : [`482`](Makefile:482)  
**Description** : Alias pour [`stop`](Makefile:393).

```bash
make down
```

### Tests

#### `local-test-api`
**Ligne** : [`519`](Makefile:519)  
**Description** : Teste l'API avec une requête de recherche.

```bash
make local-test-api
```

**Requête de test** ([`API_TEST_REQUEST`](Makefile:96)) :
```json
{
  "fuzzy": "false",
  "sort": [{"score": "desc"}],
  "page": 1,
  "size": 20,
  "scroll": "1m",
  "firstName": "jean"
}
```

**Timeout** : [`45 secondes`](Makefile:70)

#### `frontend-test`
**Ligne** : [`513`](Makefile:513)  
**Description** : Lance les tests UI avec Playwright.

```bash
make frontend-test
```

**Prérequis** : Service SMTP ([`smtp`](Makefile:507)) pour les tests d'email

**Tests exécutés** :
- [`simpleSearch.js`](ui-test/simpleSearch.js) : Recherche simple
- [`advancedSearch.js`](ui-test/advancedSearch.js) : Recherche avancée
- [`linkWikidata.js`](ui-test/linkWikidata.js) : Appariement Wikidata

#### `backend-test`
**Ligne** : [`516`](Makefile:516)  
**Description** : Lance les tests du backend.

```bash
make backend-test
```

#### `smtp`
**Ligne** : [`507`](Makefile:507)  
**Description** : Démarre un serveur SMTP de test.

```bash
make smtp
```

**Usage** : Pour tester les fonctionnalités d'envoi d'email  
**Port** : [`1025`](Makefile:63)

#### `smtp-stop`
**Ligne** : [`510`](Makefile:510)  
**Description** : Arrête le serveur SMTP de test.

```bash
make smtp-stop
```

### Déploiement

#### `deploy-local`
**Ligne** : [`505`](Makefile:505)  
**Description** : Déploiement complet en local.

```bash
make deploy-local
```

**Séquence** :
1. [`config-minimal`](Makefile:197)
2. [`show-env`](Makefile:502) : Affiche les variables
3. [`stats-background`](Makefile:732) : Lance les stats
4. [`elasticsearch-restore-async`](Makefile:446) : Restauration asynchrone
5. [`docker-check`](Makefile:252) : Vérifie les images
6. [`up`](Makefile:480) : Démarre les services
7. [`local-test-api`](Makefile:519) : Teste l'API

### Statistiques

#### `stats-full`
**Ligne** : [`716`](Makefile:716)  
**Description** : Génère les statistiques complètes depuis les logs.

```bash
make stats-full
```

**Durée** : 1-4 heures selon le volume de logs

**Étapes** :
1. Restaure les logs depuis S3
2. Parse tous les logs
3. Génère les statistiques
4. Sauvegarde sur S3

#### `stats-update`
**Ligne** : [`722`](Makefile:722)  
**Description** : Met à jour les statistiques (derniers 35 jours).

```bash
make stats-update
```

**Plus rapide que** : `stats-full`

#### `stats-live`
**Ligne** : [`726`](Makefile:726)  
**Description** : Génère les statistiques du jour en cours.

```bash
make stats-live
```

**Usage** : Pour le monitoring en temps réel

#### `stats-background`
**Ligne** : [`732`](Makefile:732)  
**Description** : Lance les statistiques en arrière-plan.

```bash
make stats-background
```

**Fonctionnement** :
- Attente initiale de 180 secondes
- Mise à jour toutes les 300 secondes (5 minutes)
- Logs dans `.stats-live`

#### `stats-catalog`
**Ligne** : [`729`](Makefile:729)  
**Description** : Génère le catalogue des statistiques.

```bash
make stats-catalog
```

### Backup et restauration

#### `backup-dir`
**Ligne** : [`402`](Makefile:402)  
**Description** : Crée le répertoire de backup.

```bash
make backup-dir
```

**Répertoire** : [`backup/`](Makefile:126)

#### `backup-dir-clean`
**Ligne** : [`405`](Makefile:405)  
**Description** : Supprime le répertoire de backup.

```bash
make backup-dir-clean
```

#### `logs-restore`
**Ligne** : [`664`](Makefile:664)  
**Description** : Restaure les logs depuis S3.

```bash
make logs-restore
```

**Bucket source** : [`LOG_BUCKET`](Makefile:40)

#### `stats-restore`
**Ligne** : [`709`](Makefile:709)  
**Description** : Restaure les statistiques depuis S3.

```bash
make stats-restore
```

#### `stats-backup`
**Ligne** : [`702`](Makefile:702)  
**Description** : Sauvegarde les statistiques sur S3.

```bash
make stats-backup
```

#### `proofs-restore`
**Ligne** : [`738`](Makefile:738)  
**Description** : Restaure les données de preuves.

```bash
make proofs-restore
```

**Bucket** : [`PROOFS_BUCKET`](Makefile:43)

#### `proofs-backup`
**Ligne** : [`746`](Makefile:746)  
**Description** : Sauvegarde les données de preuves.

```bash
make proofs-backup
```

#### `proofs-mount`
**Ligne** : [`753`](Makefile:753)  
**Description** : Monte le système de synchronisation des preuves.

```bash
make proofs-mount
```

**Fonctionnement** :
- Restauration initiale
- Sauvegarde automatique toutes les 30 secondes
- Process en arrière-plan

#### `proofs-umount`
**Ligne** : [`758`](Makefile:758)  
**Description** : Démonte le système de preuves.

```bash
make proofs-umount
```

### Nettoyage

#### `clean-data`
**Ligne** : [`228`](Makefile:228)  
**Description** : Supprime Elasticsearch et les données.

```bash
make clean-data
```

⚠️ **ATTENTION** : Suppression définitive des données locales

#### `clean-frontend`
**Ligne** : [`232`](Makefile:232)  
**Description** : Nettoie les builds frontend.

```bash
make clean-frontend
```

#### `clean-backend`
**Ligne** : [`234`](Makefile:234)  
**Description** : Supprime le répertoire backend.

```bash
make clean-backend
```

#### `clean-config`
**Ligne** : [`239`](Makefile:239)  
**Description** : Supprime la configuration et les outils.

```bash
make clean-config
```

#### `clean-local`
**Ligne** : [`242`](Makefile:242)  
**Description** : Nettoyage complet local.

```bash
make clean-local
```

**Équivalent à** :
```bash
make clean-data clean-frontend clean-backend clean-config
```

#### `clean`
**Ligne** : [`244`](Makefile:244)  
**Description** : Nettoyage complet (local + distant).

```bash
make clean
```

#### `rollup-clean`
**Ligne** : [`338`](Makefile:338)  
**Description** : Nettoie les fichiers compilés par Rollup.

```bash
make rollup-clean
```

**Fichiers supprimés** :
- `public/build/`
- `public/sw.js*`
- `public/workbox*`

### Utilitaires

#### `version`
**Ligne** : [`194`](Makefile:194)  
**Description** : Affiche la version de l'application.

```bash
make version
```

**Format** : `<tag>-<hash>` (ex: `v1.2.3-a1b2c3`)

#### `show-env`
**Ligne** : [`502`](Makefile:502)  
**Description** : Affiche les variables d'environnement liées au stockage.

```bash
make show-env
```

#### `update`
**Ligne** : [`317`](Makefile:317)  
**Description** : Met à jour le frontend depuis Git.

```bash
make update
```

---

## Workflows recommandés

### Workflow 1 : Première installation

```bash
# 1. Cloner le projet
git clone https://github.com/matchid-project/deces-ui.git
cd deces-ui

# 2. Créer le fichier artifacts
cat > artifacts << 'EOF'
export STORAGE_ACCESS_KEY=votre_access_key
export STORAGE_SECRET_KEY=votre_secret_key
export API_EMAIL=votre.email@example.com
EOF
chmod 600 artifacts

# 3. Configuration complète
make config

# 4. Créer le réseau
make network

# 5. Démarrer Elasticsearch
make elasticsearch

# 6. Restaurer les données (échantillon)
make elasticsearch-restore

# 7. Démarrer l'environnement de développement
make dev

# 8. Tester l'application
# Ouvrir http://localhost:8083 dans le navigateur

# 9. Tester l'API
make local-test-api
```

### Workflow 2 : Développement quotidien

```bash
# Démarrage du matin
make dev

# Développement...
# Les modifications dans src/ sont automatiquement compilées

# Tester une fonctionnalité
make local-test-api

# Arrêt du soir
make dev-stop
```

### Workflow 3 : Test avec données complètes

```bash
# 1. S'assurer d'avoir les credentials S3
cat artifacts

# 2. Générer les fichiers de version
touch deces-dataprep  # Si pas déjà cloné
make ${DATAPREP_VERSION_FILE}
make ${DATA_VERSION_FILE}

# 3. Démarrer Elasticsearch
make elasticsearch

# 4. Restaurer l'index complet (patience...)
make elasticsearch-restore
# Durée estimée : 30-60 minutes

# 5. Attendre que l'index soit prêt
make elasticsearch-index-readiness

# 6. Build de production
make build

# 7. Démarrer en mode production
make start

# 8. Tests complets
make frontend-test
make backend-test

# 9. Arrêt
make stop
```

### Workflow 4 : Développement backend

```bash
# 1. Démarrer Elasticsearch et backend dev
make elasticsearch
make backend-dev

# 2. Démarrer le frontend dev
make frontend-dev

# 3. Développement backend dans deces-backend/
cd deces-backend
# Modifications dans backend/src/

# 4. Tests backend
make backend-test

# 5. Arrêt
cd ..
make dev-stop
```

### Workflow 5 : Création d'une archive de données

Si vous souhaitez créer une archive .tar d'un échantillon de données :

```bash
# 1. Indexer les données souhaitées
# (voir deces-dataprep)

# 2. S'assurer qu'Elasticsearch est démarré
make elasticsearch

# 3. Attendre que l'index soit prêt
make elasticsearch-index-readiness

# 4. Créer le répertoire de backup
make backup-dir

# 5. Créer l'archive
cd esdata
tar -czf ../backup/esdata_sample_$(date +%Y%m%d).tar.gz node1/
cd ..

# 6. Vérifier l'archive
ls -lh backup/
```

### Workflow 6 : Restauration depuis une archive locale

```bash
# 1. S'assurer qu'Elasticsearch est arrêté
make elasticsearch-stop

# 2. Nettoyer les données existantes
make elasticsearch-clean

# 3. Créer le répertoire de données
mkdir -p esdata/node1
sudo chown -R 1000:1000 esdata/node1

# 4. Extraire l'archive
cd backup
tar -xzf esdata_sample_20241002.tar.gz -C ../esdata/
cd ..

# 5. Démarrer Elasticsearch
make elasticsearch

# 6. Vérifier que l'index est disponible
docker exec -it deces-ui-elasticsearch curl -s localhost:9200/_cat/indices
```

### Workflow 7 : Debug d'un problème

```bash
# 1. Vérifier l'état des conteneurs
docker ps -a

# 2. Vérifier les logs
docker logs deces-ui-elasticsearch
docker logs deces-ui-nginx
docker logs deces-ui-frontend-development

# 3. Tester Elasticsearch directement
docker exec -it deces-ui-elasticsearch curl -s localhost:9200/
docker exec -it deces-ui-elasticsearch curl -s localhost:9200/_cat/indices

# 4. Tester l'API
curl -s http://localhost:8083/deces/api/v1/search \
  -H "Content-Type: application/json" \
  -d '{"firstName":"jean","size":1}' | jq

# 5. Vérifier le réseau
docker network inspect deces-ui

# 6. Redémarrage complet si nécessaire
make restart
```

### Workflow 8 : Mise à jour du projet

```bash
# 1. Arrêter les services
make stop

# 2. Mettre à jour le code
git pull origin master

# 3. Mettre à jour les dépendances
make config

# 4. Rebuild si nécessaire
make build

# 5. Redémarrer
make start
```

---

## Troubleshooting

### Problème : Elasticsearch ne démarre pas

**Symptôme** :
```
waiting for elasticsearch API to start 60
waiting for elasticsearch API to start 59
...
```

**Solutions** :

1. **Vérifier `vm.max_map_count`** :
```bash
cat /proc/sys/vm/max_map_count
# Doit être >= 262144

# Si inférieur
sudo sysctl -w vm.max_map_count=262144
```

2. **Vérifier les permissions** :
```bash
ls -la esdata/node1/
# Doit être owned by 1000:1000

# Corriger si nécessaire
sudo chown -R 1000:1000 esdata/node1/
```

3. **Vérifier la mémoire disponible** :
```bash
free -h
# Minimum 2 GB disponibles

# Augmenter la mémoire ES si nécessaire
echo "export ES_MEM=1g" >> artifacts
```

4. **Vérifier les logs Elasticsearch** :
```bash
docker logs deces-ui-elasticsearch
```

5. **Nettoyer et redémarrer** :
```bash
make elasticsearch-clean
make elasticsearch
```

### Problème : Frontend ne charge pas

**Symptôme** :
```
curl http://localhost:8083
# Timeout ou connexion refusée
```

**Solutions** :

1. **Vérifier que Nginx est démarré** :
```bash
docker ps | grep nginx
```

2. **Vérifier les logs Nginx** :
```bash
docker logs deces-ui-nginx-development
# ou
docker logs deces-ui-nginx
```

3. **Vérifier le port** :
```bash
netstat -tuln | grep 8083
# Doit montrer un listener
```

4. **Vérifier le réseau Docker** :
```bash
docker network inspect deces-ui
# Vérifier que nginx et frontend sont connectés
```

5. **Redémarrer le frontend** :
```bash
make frontend-dev-stop
make frontend-dev
```

### Problème : Backend API ne répond pas

**Symptôme** :
```
make local-test-api
# Timeout ou erreur
```

**Solutions** :

1. **Vérifier que le backend est démarré** :
```bash
docker ps | grep backend
```

2. **Vérifier les logs backend** :
```bash
docker logs deces-backend
```

3. **Tester directement le backend** :
```bash
curl -s http://localhost:8080/api/v1/search \
  -H "Content-Type: application/json" \
  -d '{"firstName":"jean","size":1}'
```

4. **Vérifier la connexion à Elasticsearch** :
```bash
# Depuis le conteneur backend
docker exec -it deces-backend curl -s elasticsearch:9200/
```

5. **Redémarrer le backend** :
```bash
make backend-dev-stop
make backend-dev
```

### Problème : Restauration Elasticsearch échoue

**Symptôme** :
```
make elasticsearch-restore
# Error ou timeout
```

**Solutions** :

1. **Vérifier les credentials S3** :
```bash
make show-env
# Vérifier STORAGE_ACCESS_KEY et STORAGE_SECRET_KEY
```

2. **Vérifier la connexion S3** :
```bash
# Test manuel
curl -s https://s3.fr-par.scw.cloud/
```

3. **Vérifier le repository** :
```bash
docker exec -it deces-ui-elasticsearch \
  curl -s localhost:9200/_snapshot/matchid
```

4. **Lister les snapshots disponibles** :
```bash
docker exec -it deces-ui-elasticsearch \
  curl -s localhost:9200/_snapshot/matchid/_all
```

5. **Supprimer et recréer le repository** :
```bash
rm elasticsearch-repository-*
make elasticsearch-repository-config
make elasticsearch-restore
```

### Problème : Pas assez d'espace disque

**Symptôme** :
```
No space left on device
```

**Solutions** :

1. **Vérifier l'espace disponible** :
```bash
df -h
```

2. **Nettoyer les images Docker inutilisées** :
```bash
docker system prune -a --volumes
# ATTENTION : Supprime toutes les images/volumes non utilisés
```

3. **Nettoyer les données de développement** :
```bash
make clean-data
# Puis restaurer uniquement l'échantillon nécessaire
```

4. **Nettoyer les builds** :
```bash
make clean-frontend
make rollup-clean
```

5. **Vérifier les logs** :
```bash
du -sh log/
# Si trop volumineux :
rm -rf log/mirror/*
```

### Problème : Tests Playwright échouent

**Symptôme** :
```
make frontend-test
# Erreurs de timeout ou éléments non trouvés
```

**Solutions** :

1. **Vérifier que les services sont démarrés** :
```bash
make dev
# Attendre que tout soit prêt
```

2. **Vérifier la version de Playwright** :
```bash
docker run --rm mcr.microsoft.com/playwright:latest --version
```

3. **Exécuter les tests individuellement** :
```bash
cd ui-test
yarn test simpleSearch.js
```

4. **Vérifier les logs des tests** :
```bash
docker logs deces-ui-ui-test
```

5. **Mode debug** :
```bash
# Ajouter des screenshots dans les tests
# ou lancer avec --headed
```

### Problème : Rechargement à chaud ne fonctionne pas

**Symptôme** : Modifications dans `src/` ne sont pas reflétées dans le navigateur.

**Solutions** :

1. **Vérifier les logs Rollup** :
```bash
docker logs -f deces-ui-frontend-development
# Doit montrer "LiveReload enabled"
```

2. **Vérifier le port LiveReload** :
```bash
netstat -tuln | grep 35729
```

3. **Forcer la reconstruction** :
```bash
make frontend-dev-stop
rm -rf node_modules
make frontend-dev
```

4. **Vider le cache du navigateur** :
```
Ctrl+Shift+R (Chrome/Firefox)
```

5. **Vérifier les volumes Docker** :
```bash
docker inspect deces-ui-frontend-development | grep -A 20 Mounts
# Les volumes src/ doivent être montés
```

### Problème : Erreur de permission

**Symptôme** :
```
Permission denied
```

**Solutions** :

1. **Pour esdata/** :
```bash
sudo chown -R 1000:1000 esdata/
```

2. **Pour artifacts** :
```bash
chmod 600 artifacts
```

3. **Pour les scripts** :
```bash
chmod +x stats/src/*.pl
```

### Problème : Réseau Docker inexistant

**Symptôme** :
```
network deces-ui not found
```

**Solution** :
```bash
make network
```

### Problème : Conflit de ports

**Symptôme** :
```
Bind for 0.0.0.0:8083 failed: port is already allocated
```

**Solutions** :

1. **Identifier le processus utilisant le port** :
```bash
sudo lsof -i :8083
# ou
sudo netstat -tulpn | grep 8083
```

2. **Arrêter le processus** :
```bash
sudo kill <PID>
```

3. **Changer le port** :
```bash
echo "export PORT=8084" >> artifacts
make restart
```

### Problème : Erreur lors du build

**Symptôme** :
```
make build
# Error during build
```

**Solutions** :

1. **Nettoyer les builds précédents** :
```bash
make clean-frontend
```

2. **Vérifier les logs Docker** :
```bash
docker-compose -f docker-compose-build.yml logs
```

3. **Build avec verbose** :
```bash
docker-compose -f docker-compose-build.yml build --no-cache --progress=plain
```

4. **Vérifier l'espace disque** :
```bash
df -h
```

### Problème : Configuration proxy

Si vous êtes derrière un proxy d'entreprise :

**Solution** :

1. **Ajouter au fichier artifacts** :
```bash
export http_proxy=http://proxy.example.com:3128
export https_proxy=http://proxy.example.com:3128
export no_proxy=localhost,127.0.0.1,elasticsearch,backend,frontend
```

2. **Configurer Docker** :
```bash
# ~/.docker/config.json
{
  "proxies": {
    "default": {
      "httpProxy": "http://proxy.example.com:3128",
      "httpsProxy": "http://proxy.example.com:3128",
      "noProxy": "localhost,127.0.0.1"
    }
  }
}
```

3. **Redémarrer Docker** :
```bash
sudo systemctl restart docker
```

---

## Bonnes pratiques

### Développement

1. **Toujours utiliser le mode dev pour le développement** :
   ```bash
   make dev  # Pas make start
   ```

2. **Tester l'API après chaque changement significatif** :
   ```bash
   make local-test-api
   ```

3. **Commiter régulièrement les modifications** :
   ```bash
   git add .
   git commit -m "Description claire des modifications"
   ```

4. **Utiliser des branches pour les nouvelles fonctionnalités** :
   ```bash
   git checkout -b feature/nouvelle-fonctionnalite
   ```

5. **Nettoyer les builds avant de commiter** :
   ```bash
   make clean-frontend
   ```

### Gestion des données

1. **Utiliser l'échantillon pour le développement** :
   - Plus rapide à restaurer
   - Moins d'espace disque
   - Suffisant pour la plupart des tests

2. **Sauvegarder régulièrement les snapshots** :
   ```bash
   # Créer un snapshot local avant des modifications importantes
   cd esdata
   tar -czf ../backup/esdata_backup_$(date +%Y%m%d_%H%M).tar.gz node1/
   ```

3. **Ne jamais commiter les données sensibles** :
   - Le fichier `artifacts` est dans `.gitignore`
   - Ne jamais commit `esdata/`
   - Vérifier avec `git status` avant de push

4. **Documenter les versions de données** :
   ```bash
   # Toujours noter quelle version de données est utilisée
   cat .data.sha1
   cat .dataprep.sha1
   ```

### Performance

1. **Allouer suffisamment de mémoire à Elasticsearch** :
   ```bash
   # Dans artifacts pour le développement
   export ES_MEM=2g
   
   # Pour la production
   export ES_MEM=4g
   ```

2. **Limiter les logs en production** :
   ```bash
   export BACKEND_LOG_LEVEL=error
   ```

3. **Utiliser la restauration asynchrone en production** :
   ```bash
   make elasticsearch-restore-async
   ```

4. **Monitorer les ressources** :
   ```bash
   docker stats
   ```

### Sécurité

1. **Protéger le fichier artifacts** :
   ```bash
   chmod 600 artifacts
   ```

2. **Utiliser des clés fortes** :
   ```bash
   export BACKEND_TOKEN_KEY=$(openssl rand -base64 32)
   export BACKEND_TOKEN_PASSWORD=$(openssl rand -base64 32)
   ```

3. **Ne jamais exposer Elasticsearch directement** :
   - Toujours passer par le backend ou Nginx
   - Pas de port 9200 exposé publiquement

4. **Mettre à jour régulièrement** :
   ```bash
   git pull
   make config
   ```

### Tests

1. **Exécuter tous les tests avant de pousser** :
   ```bash
   make frontend-test
   make backend-test
   make local-test-api
   ```

2. **Tester dans un environnement propre** :
   ```bash
   make clean-local
   make config
   make dev
   make frontend-test
   ```

3. **Documenter les cas de test** :
   - Ajouter des commentaires dans les tests
   - Créer des fichiers de test pour chaque fonctionnalité

### Documentation

1. **Maintenir le README à jour** :
   - Documenter les nouvelles fonctionnalités
   - Mettre à jour les exemples

2. **Commenter les modifications importantes** :
   ```bash
   git commit -m "feat: ajout de la recherche par date
   
   - Nouveau champ de recherche dans l'interface
   - Indexation des dates dans Elasticsearch
   - Tests ajoutés"
   ```

3. **Documenter les variables d'environnement** :
   - Ajouter dans cette documentation
   - Exemple de valeur
   - Impact de la modification

### Workflow Git

1. **Branches** :
   - `master` : Production stable
   - `dev` : Développement actif
   - `feature/*` : Nouvelles fonctionnalités
   - `fix/*` : Corrections de bugs

2. **Commits** :
   ```bash
   # Format recommandé
   git commit -m "type(scope): description
   
   Corps détaillé du commit si nécessaire
   
   Closes #123"
   ```

   Types courants :
   - `feat` : Nouvelle fonctionnalité
   - `fix` : Correction de bug
   - `docs` : Documentation
   - `style` : Formatage, sans changement de code
   - `refactor` : Refactorisation
   - `test` : Ajout de tests
   - `chore` : Maintenance

3. **Pull Requests** :
   - Description claire des changements
   - Screenshots si UI
   - Résultats des tests
   - Références aux issues

### Monitoring

1. **Vérifier régulièrement les logs** :
   ```bash
   docker-compose logs --tail=100 -f
   ```

2. **Surveiller l'utilisation des ressources** :
   ```bash
   docker stats --no-stream
   ```

3. **Vérifier l'état d'Elasticsearch** :
   ```bash
   curl -s localhost:9200/_cat/health
   curl -s localhost:9200/_cat/indices
   ```

### Backup

1. **Stratégie de backup recommandée** :
   - Snapshots Elasticsearch quotidiens
   - Archives locales hebdomadaires
   - Backup des configurations mensuels

2. **Script de backup automatique** :
   ```bash
   #!/bin/bash
   # backup-daily.sh
   
   DATE=$(date +%Y%m%d)
   
   # Snapshot Elasticsearch
   make elasticsearch-backup
   
   # Archive locale
   cd esdata
   tar -czf ../backup/esdata_${DATE}.tar.gz node1/
   cd ..
   
   # Nettoyer les vieux backups (> 7 jours)
   find backup/ -name "esdata_*.tar.gz" -mtime +7 -delete
   ```

3. **Test de restauration** :
   ```bash
   # Tester la restauration chaque mois
   make elasticsearch-clean
   make elasticsearch-restore
   make elasticsearch-index-readiness
   ```

### Optimisation

1. **Indexation Elasticsearch** :
   - Utiliser les bonnes pratiques d'indexation
   - Optimiser les mappings
   - Utiliser les analyzers appropriés

2. **Performance frontend** :
   - Minifier les assets en production
   - Utiliser le service worker
   - Optimiser les images

3. **Performance backend** :
   - Mettre en cache les requêtes fréquentes
   - Optimiser les requêtes Elasticsearch
   - Utiliser la pagination

### Maintenance

1. **Nettoyage régulier** :
   ```bash
   # Tous les mois
   docker system prune -a
   make clean-frontend
   ```

2. **Mise à jour des dépendances** :
   ```bash
   # Vérifier les mises à jour de sécurité
   npm audit
   npm audit fix
   ```

3. **Vérification de l'intégrité** :
   ```bash
   # Vérifier les checksums des données
   make version
   cat .data.sha1
   cat .dataprep.sha1
   ```

---

## Annexes

### Structure des répertoires

```
deces-ui/
├── backup/                      # Archives de backup
├── deces-backend/               # Backend TypeScript (clone)
├── deces-dataprep/             # Scripts de préparation des données (clone)
├── esdata/                      # Données Elasticsearch
│   └── node1/                  # Node Elasticsearch
├── k8s/                        # Configurations Kubernetes
├── log/                        # Logs de l'application
│   ├── mirror/                 # Logs Nginx
│   └── db/                     # Base de stats
├── nginx/                      # Configuration Nginx
├── public/                     # Assets frontend
│   ├── build/                  # Build Rollup (généré)
│   ├── css/                    # Styles
│   └── js/                     # Scripts
├── src/                        # Code source Svelte
│   ├── components/             # Composants Svelte
│   ├── App.svelte             # Composant racine
│   └── main.js                # Point d'entrée
├── stats/                      # Statistiques
│   └── public/                 # Stats générées
├── tools/                      # Outils communs (clone)
├── ui-test/                    # Tests Playwright
├── artifacts                   # Configuration locale (non versionné)
├── docker-compose*.yml         # Configurations Docker
├── Makefile                    # Orchestration
├── package.json                # Dépendances npm
├── rollup.config.js           # Configuration Rollup
└── README.md                   # Documentation
```

### Ports utilisés

| Service | Port | Usage |
|---------|------|-------|
| Frontend (dev) | 8083 | Interface web développement |
| Frontend (prod) | 8083 | Interface web production |
| LiveReload | 35729 | Rechargement à chaud |
| Backend | 8080 | API backend |
| Elasticsearch | 9200 | API Elasticsearch (interne) |
| SMTP (test) | 1025 | Serveur mail de test |

### Variables d'environnement complètes

Voir le fichier [`Makefile`](Makefile:1) lignes 8-175 pour la liste exhaustive.

### Liens utiles

- **GitHub** : https://github.com/matchid-project/deces-ui
- **Documentation matchID** : https://matchid.io
- **Site de production** : https://deces.matchid.io
- **Data.gouv.fr** : https://www.data.gouv.fr/fr/datasets/fichier-des-personnes-decedees/
- **INSEE** : https://www.insee.fr/fr/information/4190491

### Commandes Docker utiles

```bash
# Lister les conteneurs
docker ps -a

# Logs d'un conteneur
docker logs -f <container_name>

# Shell dans un conteneur
docker exec -it <container_name> bash

# Inspecter un conteneur
docker inspect <container_name>

# Statistiques des ressources
docker stats

# Nettoyer tout
docker system prune -a --volumes

# Lister les réseaux
docker network ls

# Inspecter un réseau
docker network inspect deces-ui
```

### Résolution des problèmes courants

| Problème | Commande de diagnostic | Solution |
|----------|------------------------|----------|
| Elasticsearch ne démarre pas | `docker logs deces-ui-elasticsearch` | Vérifier `vm.max_map_count` et permissions |
| Frontend inaccessible | `docker ps \| grep nginx` | Vérifier que Nginx est démarré |
| API ne répond pas | `make local-test-api` | Vérifier backend et Elasticsearch |
| Pas d'espace disque | `df -h` | Nettoyer avec `docker system prune` |
| Conflit de ports | `sudo lsof -i :8083` | Changer `PORT` dans artifacts |
| Tests échouent | `docker logs deces-ui-ui-test` | Vérifier que les services sont démarrés |

---

## Glossaire

- **Snapshot** : Sauvegarde complète de l'index Elasticsearch
- **Repository** : Emplacement de stockage des snapshots (S3/Scaleway)
- **Index** : Base de données Elasticsearch (ici : `deces`)
- **Node** : Instance Elasticsearch
- **Shard** : Partition d'un index Elasticsearch
- **Rechargement à chaud** : Compilation et rafraîchissement automatique du code
- **LiveReload** : Protocole de rechargement à chaud pour le développement
- **Reverse proxy** : Serveur intermédiaire (ici : Nginx) qui route les requêtes
- **Appariement** : Processus de matching entre deux jeux de données
- **Fuzzy search** : Recherche approximative (tolérante aux fautes de frappe)
- **Aggregation** : Regroupement et calcul statistique dans Elasticsearch

---

## Changelog de cette documentation

### Version 1.0.0 (2024-10-02)
- Documentation initiale complète du Makefile
- Description des phases de développement et validation
- Workflows recommandés
- Section troubleshooting détaillée
- Bonnes pratiques

---

## Contributeurs

Documentation maintenue par l'équipe matchID :
- Pour les questions : matchid.project@gmail.com
- Pour les issues : https://github.com/matchid-project/deces-ui/issues

---

**Note** : Cette documentation couvre la version [`v1.2.3`](package.json:3) du projet deces-ui. Pour les versions ultérieures, consultez le fichier [`README.md`](README.md:1) et le [`Makefile`](Makefile:1) pour les éventuelles modifications.