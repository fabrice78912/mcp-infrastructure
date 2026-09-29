#!/bin/bash
# Script de build des packages Lambda (ZIP)
# Usage: ./scripts/build-lambda-packages.sh

set -e

echo "========================================="
echo "Building Lambda packages"
echo "========================================="
echo ""

# Chemin vers le projet MCP source
MCP_SOURCE="/Users/fabricefoko/Downloads/mcp-local"
LAMBDA_MODULE="modules/lambda/functions"

# Créer le dossier si nécessaire
mkdir -p "$LAMBDA_MODULE"

# Fonction pour builder une Lambda Java
build_java_lambda() {
  local project_name=$1
  local handler_class=$2
  local output_name=$3

  echo "🔨 Building $output_name from $project_name..."

  # Aller dans le projet source
  cd "$MCP_SOURCE/$project_name"

  # Build avec Maven
  ./mvnw clean package -DskipTests

  # Copier le JAR
  mkdir -p "/Users/fabricefoko/Documents/mcp-infrastructure/$LAMBDA_MODULE/$output_name"
  cp target/*.jar "/Users/fabricefoko/Documents/mcp-infrastructure/$LAMBDA_MODULE/$output_name/function.jar"

  echo "  ✅ Built $output_name"
}

# Build mcp-orchestration handlers
echo "📦 Building orchestration handlers..."
build_java_lambda "mcp-orchestration" "com.bnc.mcp.orchestration.handlers.ClientProfileReader" "client-profile-reader"
build_java_lambda "mcp-orchestration" "com.bnc.mcp.orchestration.handlers.NameValidator" "name-validator"
build_java_lambda "mcp-orchestration" "com.bnc.mcp.orchestration.handlers.MdmaeClient" "mdmae-client"
build_java_lambda "mcp-orchestration" "com.bnc.mcp.orchestration.handlers.FccSender" "fcc-sender"
build_java_lambda "mcp-orchestration" "com.bnc.mcp.orchestration.handlers.HumanReviewHandler" "human-review-handler"

# Build mcp-fcc-connector handlers
echo "📦 Building FCC connector handlers..."
build_java_lambda "mcp-fcc-connector" "com.bnc.mcp.fcc.connector.MqPoller" "mq-poller"
build_java_lambda "mcp-fcc-connector" "com.bnc.mcp.fcc.connector.FccResponseProcessor" "fcc-response-processor"

echo ""
echo "========================================="
echo "✅ All Lambda packages built!"
echo "========================================="
echo ""
echo "Lambda JARs location: $LAMBDA_MODULE/"
echo ""
echo "Note: Les JARs seront automatiquement zippés par Terraform lors du déploiement"
echo ""