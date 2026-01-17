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
if ! command -v curl &>/dev/null; then
    echo "❌ Error: curl no está instalado"
    exit 1
fi

if ! command -v jq &>/dev/null; then
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

        # Extraer metadatos del archivo (frontmatter YAML si existe)
        if grep -q "^---$" "$file"; then
            # Extraer título del frontmatter o usar filename
            title=$(awk '/^---$/,/^---$/ {if ($1 == "title:") {$1=""; print $0; exit}}' "$file" | sed 's/^[[:space:]]*//' | sed 's/^["'\'']\(.*\)["'\'']$/\1/')
            [ -z "$title" ] && title="$filename"

            # Extraer tags del frontmatter (pueden estar como keywords o tags)
            tags=$(awk '/^---$/,/^---$/ {if ($1 == "keywords:" || $1 == "tags:") {$1=""; print $0; exit}}' "$file" | sed 's/^[[:space:]]*//' | sed 's/^["'\'']\(.*\)["'\'']$/\1/')

            # Remover frontmatter del contenido
            article_content=$(sed '/^---$/,/^---$/d' "$file" | sed '/^$/d' | sed '1{/^$/d}')
        else
            title="$filename"
            tags=""
            article_content=$(cat "$file")
        fi

        # Si no hay tags, usar "tutorial" por defecto
        [ -z "$tags" ] && tags="tutorial"

        # Convertir tags a array JSON (separados por coma o espacio)
        IFS=',' read -ra tag_array <<<"$tags"
        tags_json="["
        for tag in "${tag_array[@]}"; do
            # Limpiar espacios y convertir a lowercase (Dev.to requirement)
            clean_tag=$(echo "$tag" | xargs | tr '[:upper:]' '[:lower:]')
            tags_json+="\"$clean_tag\","
        done
        tags_json="${tags_json%,}]" # Remover última coma y cerrar array

        # Crear payload JSON para dev.to API
        payload=$(jq -n \
            --arg content "$article_content" \
            --arg title "$title" \
            --argjson tags "$tags_json" \
            '{
                article: {
                    title: $title,
                    body_markdown: $content,
                    published: false,
                    tags: $tags
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
            echo "   📋 Tags: $tags_json"
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
