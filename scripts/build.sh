#!/usr/bin/env bash

set -euo pipefail

# Script para convertir archivos Org-Mode a Markdown usando Pandoc
# Uso: ./scripts/convert-org-to-md.sh [input_dir] [output_dir]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

INPUT_DIR="${1:-$PROJECT_ROOT/articles}"
OUTPUT_DIR="${2:-$PROJECT_ROOT/build}"

echo "📁 Input directory: $INPUT_DIR"
echo "📁 Output directory: $OUTPUT_DIR"
echo ""

# Verificar que Pandoc esté instalado
if ! command -v pandoc &>/dev/null; then
    echo "❌ Error: Pandoc no está instalado"
    echo "   Instálalo con: brew install pandoc (macOS) o apt-get install pandoc (Linux)"
    exit 1
fi

# Crear directorio de salida si no existe
mkdir -p "$OUTPUT_DIR"

# Contador de archivos convertidos

for file in "$INPUT_DIR"/*.org; do
    if [ -f "$file" ]; then
        filename=$(basename "$file" .org)
        output_file="$OUTPUT_DIR/${filename}.md"
        echo "🔄 Convirtiendo: $filename.org -> $filename.md"
        pandoc "$file" -f org -t gfm --shift-heading-level-by=1 --standalone -o "$output_file"
        echo "Converted: $file -> build/${filename}.md"
    fi
done
