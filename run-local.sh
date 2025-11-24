#!/bin/bash

set -e  # Arrêter en cas d'erreur

echo "🚀 Démarrage de deces-ui en local avec données pré-indexées"

# ============================================
# 1. Configuration initiale (première fois)
# ============================================
if [ ! -d "tools" ]; then
    echo "📦 Installation de la configuration..."
    make config
fi

if ! docker network inspect deces-ui &>/dev/null; then
    echo "🌐 Création du réseau Docker..."
    make network
fi

# ============================================
# 2. Préparation des données Elasticsearch
# ============================================
echo "🗄️  Préparation des données Elasticsearch..."

# Arrêter Elasticsearch s'il est en cours
echo "⏸️  Arrêt d'Elasticsearch si actif..."
make elasticsearch-stop 2>/dev/null || true

# Nettoyer les anciennes données
echo "🧹 Nettoyage des anciennes données..."
make elasticsearch-clean 2>/dev/null || true

# Créer le répertoire de destination
echo "📁 Création du répertoire esdata..."
mkdir -p esdata/

# Extraire l'archive
echo "📦 Extraction de l'archive..."
if ls ../backup/backup/esdata_*.tar 1> /dev/null 2>&1; then
    tar -xf ../backup/backup/esdata_*.tar -C ./
    echo "✅ Archive extraite avec succès"
else
    echo "❌ Erreur : Aucune archive esdata_*.tar trouvée dans ../backup/backup/"
    exit 1
fi

# Définir les permissions pour Elasticsearch
echo "🔐 Configuration des permissions..."
sudo chown -R 1000:1000 esdata/

# ============================================
# 3. Démarrage des services
# ============================================
echo "🚀 Démarrage de l'environnement de développement..."
make dev

# ============================================
# 4. Vérification
# ============================================
echo ""
echo "⏳ Attente du démarrage complet (30 secondes)..."
sleep 30

echo ""
echo "🔍 Vérification de l'index Elasticsearch..."
docker exec -it deces-ui-elasticsearch curl -s localhost:9200/_cat/indices 2>/dev/null || echo "⚠️  Elasticsearch pas encore prêt"

echo ""
echo "✅ Démarrage terminé !"
echo ""
echo "📊 Services disponibles :"
echo "   - Interface web : http://localhost:8083"
echo "   - Backend API : http://localhost:8083/deces/api/v1"
echo "   - Elasticsearch : http://localhost:9200 (interne)"
echo ""
echo "🧪 Pour tester l'API : make local-test-api"
echo "🛑 Pour arrêter : make dev-stop"
