#!/bin/bash

#######################################################################
# Script de build pour créer le ZIP de la Lambda Swagger UI
# Usage: ./build-swagger-ui-lambda.sh
#######################################################################

set -e  # Exit on error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$SCRIPT_DIR/swagger-ui-lambda"
OUTPUT_ZIP="$SCRIPT_DIR/swagger-ui-lambda.zip"

echo "Building Swagger UI Lambda deployment package..."

# Vérifier que le répertoire source existe
if [ ! -d "$SOURCE_DIR" ]; then
    echo "Error: Source directory not found: $SOURCE_DIR"
    exit 1
fi

# Vérifier que index.py existe
if [ ! -f "$SOURCE_DIR/index.py" ]; then
    echo "Error: index.py not found in $SOURCE_DIR"
    exit 1
fi

# Créer le ZIP
cd "$SOURCE_DIR"
zip -r "$OUTPUT_ZIP" index.py

echo "✓ Lambda deployment package created: $OUTPUT_ZIP"
ls -lh "$OUTPUT_ZIP"
