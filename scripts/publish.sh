#!/usr/bin/env bash

set -euo pipefail

# Script para publicar artículos Markdown a Dev.to
# Uso: ./scripts/publish-to-devto.sh [markdown_dir]
# Requiere: DEVTO_API_KEY como variable de entorno

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

MARKDOWN_DIR="${1:-$PROJECT_ROOT/build}"

echo "📁 Publishing from: $MARKDOWN_DIR"
echo ""

# Verificar que la API key esté configurada
if [ -z "${DEVTO_API_KEY:-}" ]; then
    echo "❌ Error: DEVTO_API_KEY no está configurada"
    echo "   Exporta la variable: export DEVTO_API_KEY='tu-api-key'"
    echo "   Obtén tu API key desde: https://dev.to/settings/extensions"
    exit 1
fi

# Verificar que curl y jq estén instalados
if ! command -v curl &> /dev/null; then
    echo "❌ Error: curl no está instalado"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "❌ Error: jq no está instalado"
    echo "   Instálalo con: brew install jq (macOS) o apt-get install jq (Linux)"
    exit 1
fi

# Verificar que existan archivos markdown
if [ ! -d "$MARKDOWN_DIR" ]; then
    echo "❌ Error: El directorio $MARKDOWN_DIR no existe"
    exit 1
fi

published=0
failed=0

# Publicar cada archivo markdown
for file in "$MARKDOWN_DIR"/*.md; do
    if [ -f "$file" ]; then
        filename=$(basename "$file" .md)
        
        echo "📤 Publicando: $filename"
        
        # Leer el contenido del archivo
        article_content=$(cat "$file")
        
        # Crear payload JSON para dev.to API
        payload=$(jq -n \
            --arg content "$article_content" \
            --arg title "$filename" \
            '{
                article: {
                    title: $title,
                    body_markdown: $content,
                    published: false,
                    tags: ["tutorial"]
                }
            }')
        
        # Publicar a dev.to
        response=$(curl -s -w "\n%{http_code}" -X POST "https://dev.to/api/articles" \
            -H "Content-Type: application/json" \
            -H "api-key: $DEVTO_API_KEY" \
            -d "$payload")
        
        # Separar el código de estado HTTP de la respuesta
        http_code=$(echo "$response" | tail -n1)
        response_body=$(echo "$response" | sed '$d')
        
        if [ "$http_code" -eq 201 ]; then
            article_url=$(echo "$response_body" | jq -r '.url // "N/A"')
            echo "   ✅ Publicado como borrador: $article_url"
            ((published++))
        else
            echo "   ❌ Error al publicar (HTTP $http_code)"
            echo "   Response: $response_body"
            ((failed++))
        fi
        echo ""
    fi
done

echo ""
echo "📊 Resumen:"
echo "   ✅ Publicados: $published"
if [ $failed -gt 0 ]; then
    echo "   ❌ Fallidos: $failed"
    exit 1
else
    echo "   🎉 Todos los artículos publicados exitosamente"
fi
