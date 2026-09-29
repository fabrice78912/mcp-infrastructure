#!/bin/bash

################################################################################
# Script de configuration post-déploiement MCP Infrastructure
#
# Ce script configure l'environnement après un terraform apply :
# 1. Vérifie/Upload les JARs Lambda vers S3
# 2. Remplit les secrets AWS Secrets Manager
# 3. Charge les données de test dans DynamoDB
# 4. Teste l'endpoint API Gateway
#
# Usage: ./post-deploy-setup.sh [dev|prod]
################################################################################

set -e  # Exit on error

# Couleurs pour l'output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Fonctions utilitaires
print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# Validation des paramètres
if [ -z "$1" ]; then
    print_error "Usage: $0 [dev|prod]"
    exit 1
fi

ENV=$1
REGION="ca-central-1"
S3_BUCKET="bnc-mcp-lambda-artifacts"

if [[ "$ENV" != "dev" && "$ENV" != "prod" ]]; then
    print_error "Environment doit être 'dev' ou 'prod'"
    exit 1
fi

print_header "Configuration Post-Déploiement - Environnement: $ENV"

################################################################################
# 1. VÉRIFICATION ET UPLOAD DES JARS LAMBDA
################################################################################

print_header "1. Vérification des JARs Lambda dans S3"

LAMBDA_JARS=(
    "ValidationLambda.jar"
    "MatchingLambda.jar"
    "UpdateProfileLambda.jar"
    "PublishEventLambda.jar"
    "HumanReviewLambda.jar"
    "FccSenderLambda.jar"
    "FccResponseProcessorLambda.jar"
)

MISSING_JARS=()

for jar in "${LAMBDA_JARS[@]}"; do
    if aws s3 ls "s3://${S3_BUCKET}/${jar}" --region ${REGION} > /dev/null 2>&1; then
        print_success "${jar} présent dans S3"
    else
        print_warning "${jar} manquant dans S3"
        MISSING_JARS+=("$jar")
    fi
done

if [ ${#MISSING_JARS[@]} -gt 0 ]; then
    print_warning "JARs manquants: ${MISSING_JARS[*]}"
    echo ""
    read -p "Voulez-vous uploader les JARs depuis un répertoire local? (y/n) " -n 1 -r
    echo ""

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        read -p "Chemin du répertoire contenant les JARs: " JAR_DIR

        if [ ! -d "$JAR_DIR" ]; then
            print_error "Le répertoire $JAR_DIR n'existe pas"
            exit 1
        fi

        for jar in "${MISSING_JARS[@]}"; do
            if [ -f "$JAR_DIR/$jar" ]; then
                print_info "Upload de $jar vers S3..."
                aws s3 cp "$JAR_DIR/$jar" "s3://${S3_BUCKET}/$jar" --region ${REGION}
                print_success "$jar uploadé avec succès"
            else
                print_error "$jar non trouvé dans $JAR_DIR"
            fi
        done
    else
        print_error "Les JARs doivent être uploadés manuellement avant de continuer"
        echo "Commande: aws s3 cp <fichier.jar> s3://${S3_BUCKET}/ --region ${REGION}"
        exit 1
    fi
fi

################################################################################
# 2. CONFIGURATION DES SECRETS AWS SECRETS MANAGER
################################################################################

print_header "2. Configuration des Secrets Manager"

echo "Configuration des secrets pour l'environnement ${ENV}"
echo ""

# Secret IBM MQ
print_info "Configuration du secret IBM MQ (${ENV}/mcp/ibmmq)..."
echo ""
echo "Entrez les informations IBM MQ:"
read -p "  Host: " IBM_MQ_HOST
read -p "  Port [1414]: " IBM_MQ_PORT
IBM_MQ_PORT=${IBM_MQ_PORT:-1414}
read -p "  Channel: " IBM_MQ_CHANNEL
read -p "  Queue Manager: " IBM_MQ_QUEUE_MANAGER
read -p "  Username: " IBM_MQ_USERNAME
read -sp "  Password: " IBM_MQ_PASSWORD
echo ""

IBM_MQ_SECRET=$(cat <<EOF
{
  "host": "${IBM_MQ_HOST}",
  "port": "${IBM_MQ_PORT}",
  "channel": "${IBM_MQ_CHANNEL}",
  "queueManager": "${IBM_MQ_QUEUE_MANAGER}",
  "username": "${IBM_MQ_USERNAME}",
  "password": "${IBM_MQ_PASSWORD}"
}
EOF
)

aws secretsmanager put-secret-value \
    --secret-id "${ENV}/mcp/ibmmq" \
    --secret-string "${IBM_MQ_SECRET}" \
    --region ${REGION} > /dev/null 2>&1

print_success "Secret IBM MQ configuré"

# Secret MDMAE
echo ""
print_info "Configuration du secret MDMAE (${ENV}/mcp/mdmae)..."
echo ""
echo "Entrez les informations MDMAE:"
read -p "  URL: " MDMAE_URL
read -sp "  API Key: " MDMAE_API_KEY
echo ""

MDMAE_SECRET=$(cat <<EOF
{
  "url": "${MDMAE_URL}",
  "apiKey": "${MDMAE_API_KEY}"
}
EOF
)

aws secretsmanager put-secret-value \
    --secret-id "${ENV}/mcp/mdmae" \
    --secret-string "${MDMAE_SECRET}" \
    --region ${REGION} > /dev/null 2>&1

print_success "Secret MDMAE configuré"

################################################################################
# 3. CHARGEMENT DES DONNÉES DE TEST DANS DYNAMODB
################################################################################

print_header "3. Chargement des données de test DynamoDB"

TABLE_NAME="${ENV}-ClientProfile"

# Vérifier que la table existe
if ! aws dynamodb describe-table --table-name ${TABLE_NAME} --region ${REGION} > /dev/null 2>&1; then
    print_error "La table DynamoDB ${TABLE_NAME} n'existe pas!"
    print_info "Assurez-vous que terraform apply a été exécuté avec succès"
    exit 1
fi

print_info "Insertion du client de test TEST123..."

aws dynamodb put-item \
    --table-name ${TABLE_NAME} \
    --item '{
        "clientId": {"S": "TEST123"},
        "firstName": {"S": "Jean"},
        "lastName": {"S": "Tremblay"},
        "dateOfBirth": {"S": "1990-01-01"},
        "email": {"S": "jean.tremblay@example.com"},
        "address": {"S": "123 Rue Principale, Montreal, QC H1A 1A1"},
        "phoneNumber": {"S": "+1-514-555-0100"},
        "createdAt": {"S": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"},
        "updatedAt": {"S": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}
    }' \
    --region ${REGION} > /dev/null 2>&1

print_success "Client TEST123 créé dans DynamoDB"

# Vérification
ITEM_COUNT=$(aws dynamodb scan --table-name ${TABLE_NAME} --select COUNT --region ${REGION} --output json | jq -r '.Count')
print_info "Nombre total d'items dans la table: ${ITEM_COUNT}"

################################################################################
# 4. RÉCUPÉRATION DES OUTPUTS TERRAFORM
################################################################################

print_header "4. Récupération des informations de déploiement"

# Aller dans le répertoire terraform
TERRAFORM_DIR="$(dirname "$0")/../environments/${ENV}"

if [ ! -d "$TERRAFORM_DIR" ]; then
    print_error "Le répertoire Terraform $TERRAFORM_DIR n'existe pas"
    exit 1
fi

cd "$TERRAFORM_DIR"

# Récupérer l'URL de l'API Gateway
API_URL=$(terraform output -raw api_gateway_url 2>/dev/null || echo "")

if [ -z "$API_URL" ]; then
    print_warning "Impossible de récupérer l'URL de l'API Gateway depuis terraform output"
    print_info "Récupération depuis AWS..."

    API_ID=$(terraform output -raw api_gateway_id 2>/dev/null || echo "")

    if [ -n "$API_ID" ]; then
        API_URL="https://${API_ID}.execute-api.${REGION}.amazonaws.com/${ENV}/api/clients/{clientId}/nom"
        print_success "URL API Gateway: ${API_URL}"
    else
        print_error "Impossible de récupérer l'ID de l'API Gateway"
    fi
else
    print_success "URL API Gateway: ${API_URL}"
fi

################################################################################
# 5. TEST DE L'ENDPOINT API GATEWAY
################################################################################

print_header "5. Test de l'endpoint API Gateway"

if [ -z "$API_URL" ]; then
    print_warning "Impossible de tester l'API - URL non disponible"
else
    # Remplacer {clientId} par TEST123
    TEST_URL="${API_URL//\{clientId\}/TEST123}"

    print_info "Test de l'endpoint: PUT ${TEST_URL}"
    echo ""

    # Faire un appel de test
    RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT "${TEST_URL}" \
        -H "Content-Type: application/json" \
        -d '{"newLastName":"Leblanc","reason":"MARIAGE"}')

    HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
    BODY=$(echo "$RESPONSE" | head -n -1)

    echo "Response:"
    echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
    echo ""

    if [ "$HTTP_CODE" == "200" ]; then
        print_success "API Gateway répond correctement (HTTP ${HTTP_CODE})"

        # Extraire l'execution ARN
        EXECUTION_ARN=$(echo "$BODY" | jq -r '.executionArn // empty')

        if [ -n "$EXECUTION_ARN" ]; then
            print_success "Execution Step Functions créée: ${EXECUTION_ARN}"

            print_info "Vérification du statut de l'exécution dans 5 secondes..."
            sleep 5

            EXEC_STATUS=$(aws stepfunctions describe-execution \
                --execution-arn "${EXECUTION_ARN}" \
                --region ${REGION} \
                --output json 2>/dev/null | jq -r '.status // "UNKNOWN"')

            case "$EXEC_STATUS" in
                "RUNNING")
                    print_info "Exécution en cours..."
                    ;;
                "SUCCEEDED")
                    print_success "Exécution terminée avec succès!"
                    ;;
                "FAILED")
                    print_error "Exécution échouée"
                    aws stepfunctions describe-execution \
                        --execution-arn "${EXECUTION_ARN}" \
                        --region ${REGION} \
                        --output json | jq '{error, cause}'
                    ;;
                *)
                    print_warning "Statut inconnu: ${EXEC_STATUS}"
                    ;;
            esac
        fi
    else
        print_error "Erreur API Gateway (HTTP ${HTTP_CODE})"
    fi
fi

################################################################################
# 6. RÉSUMÉ
################################################################################

print_header "Configuration Terminée!"

echo ""
print_success "Infrastructure ${ENV} configurée avec succès!"
echo ""
echo "Informations importantes:"
echo "  - Environment: ${ENV}"
echo "  - Region: ${REGION}"
echo "  - API Gateway URL: ${API_URL}"
echo "  - DynamoDB Table: ${TABLE_NAME}"
echo "  - Test Client: TEST123"
echo ""
echo "Pour tester l'API manuellement:"
echo ""
echo "  curl -X PUT \"${TEST_URL}\" \\"
echo "    -H \"Content-Type: application/json\" \\"
echo "    -d '{\"newLastName\":\"Dupont\",\"reason\":\"MARIAGE\"}'"
echo ""
print_info "Script terminé avec succès!"