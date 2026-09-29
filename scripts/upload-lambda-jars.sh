#!/bin/bash

################################################################################
# Script d'upload des JARs Lambda vers S3
#
# Ce script upload tous les JARs Lambda depuis le répertoire de build
# vers le bucket S3 utilisé par Terraform pour les déploiements Lambda.
#
# Usage: ./upload-lambda-jars.sh [chemin-vers-jars]
################################################################################

set -e

# Couleurs
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }

# Configuration
S3_BUCKET="bnc-mcp-lambda-artifacts"
REGION="ca-central-1"

# Liste des JARs attendus
EXPECTED_JARS=(
    "ValidationLambda.jar"
    "MatchingLambda.jar"
    "UpdateProfileLambda.jar"
    "PublishEventLambda.jar"
    "HumanReviewLambda.jar"
    "FccSenderLambda.jar"
    "FccResponseProcessorLambda.jar"
)

echo -e "\n${BLUE}========================================${NC}"
echo -e "${BLUE}Upload des JARs Lambda vers S3${NC}"
echo -e "${BLUE}========================================${NC}\n"

# Déterminer le répertoire source
if [ -n "$1" ]; then
    JAR_DIR="$1"
else
    # Essayer de deviner le chemin
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    POSSIBLE_PATHS=(
        "$SCRIPT_DIR/../../mcp-orchestration/target"
        "$HOME/Documents/mcp-local/mcp-orchestration/target"
        "$HOME/Downloads/mcp-local/mcp-orchestration/target"
        "$(pwd)/target"
    )

    JAR_DIR=""
    for path in "${POSSIBLE_PATHS[@]}"; do
        if [ -d "$path" ]; then
            # Vérifier s'il contient des JARs
            if ls "$path"/*.jar 1> /dev/null 2>&1; then
                JAR_DIR="$path"
                print_info "Répertoire trouvé automatiquement: $JAR_DIR"
                break
            fi
        fi
    done

    if [ -z "$JAR_DIR" ]; then
        print_error "Impossible de trouver le répertoire contenant les JARs"
        echo ""
        echo "Usage: $0 [chemin-vers-jars]"
        echo ""
        echo "Exemple:"
        echo "  $0 ~/Documents/mcp-local/mcp-orchestration/target"
        exit 1
    fi
fi

# Vérifier que le répertoire existe
if [ ! -d "$JAR_DIR" ]; then
    print_error "Le répertoire $JAR_DIR n'existe pas"
    exit 1
fi

print_info "Répertoire source: $JAR_DIR"
echo ""

# Vérifier la connexion AWS
print_info "Vérification de la connexion AWS..."
if ! aws sts get-caller-identity > /dev/null 2>&1; then
    print_error "Impossible de se connecter à AWS. Vérifiez vos credentials."
    exit 1
fi
print_success "Connexion AWS OK"

# Vérifier que le bucket existe
print_info "Vérification du bucket S3: ${S3_BUCKET}..."
if ! aws s3 ls "s3://${S3_BUCKET}" --region ${REGION} > /dev/null 2>&1; then
    print_error "Le bucket s3://${S3_BUCKET} n'existe pas ou n'est pas accessible"
    exit 1
fi
print_success "Bucket S3 accessible"
echo ""

# Scanner les JARs présents
print_info "Recherche des JARs dans ${JAR_DIR}..."
FOUND_JARS=()
MISSING_JARS=()

for jar in "${EXPECTED_JARS[@]}"; do
    if [ -f "$JAR_DIR/$jar" ]; then
        FOUND_JARS+=("$jar")
        print_success "Trouvé: $jar"
    else
        MISSING_JARS+=("$jar")
        print_warning "Manquant: $jar"
    fi
done

echo ""

if [ ${#FOUND_JARS[@]} -eq 0 ]; then
    print_error "Aucun JAR Lambda trouvé dans $JAR_DIR"
    exit 1
fi

if [ ${#MISSING_JARS[@]} -gt 0 ]; then
    print_warning "JARs manquants: ${MISSING_JARS[*]}"
    echo ""
    read -p "Continuer avec les JARs trouvés seulement? (y/n) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Upload annulé"
        exit 0
    fi
fi

echo ""
print_info "Upload de ${#FOUND_JARS[@]} JAR(s) vers s3://${S3_BUCKET}..."
echo ""

UPLOADED=0
FAILED=0

for jar in "${FOUND_JARS[@]}"; do
    JAR_PATH="$JAR_DIR/$jar"
    JAR_SIZE=$(du -h "$JAR_PATH" | cut -f1)

    print_info "Upload de $jar ($JAR_SIZE)..."

    if aws s3 cp "$JAR_PATH" "s3://${S3_BUCKET}/$jar" --region ${REGION} > /dev/null 2>&1; then
        print_success "$jar uploadé avec succès"
        ((UPLOADED++))
    else
        print_error "Échec de l'upload de $jar"
        ((FAILED++))
    fi
done

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Résumé${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "  JARs uploadés: ${UPLOADED}"
echo "  JARs échoués:  ${FAILED}"
echo "  Bucket:        s3://${S3_BUCKET}"
echo "  Région:        ${REGION}"
echo ""

# Lister le contenu du bucket
print_info "Contenu actuel du bucket S3:"
echo ""
aws s3 ls "s3://${S3_BUCKET}/" --region ${REGION} --human-readable

echo ""

if [ $FAILED -eq 0 ]; then
    print_success "Tous les JARs ont été uploadés avec succès!"
    echo ""
    print_info "Vous pouvez maintenant lancer le déploiement Terraform:"
    echo ""
    echo "  # Via GitHub Actions:"
    echo "  Actions → Deploy MCP Infrastructure → Run workflow → apply"
    echo ""
    echo "  # Ou via CLI:"
    echo "  cd environments/dev"
    echo "  terraform apply -var-file=dev.tfvars"
    echo ""
else
    print_error "Certains uploads ont échoué. Vérifiez les erreurs ci-dessus."
    exit 1
fi