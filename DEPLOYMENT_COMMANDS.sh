#!/bin/bash
# ═══════════════════════════════════════════════════════════════════
# Commandes de déploiement pour l'infrastructure MCP
# ═══════════════════════════════════════════════════════════════════
#
# ⚠️  NE PAS EXÉCUTER CE SCRIPT DIRECTEMENT !
# ⚠️  Copiez les commandes et exécutez-les manuellement étape par étape
#
# ═══════════════════════════════════════════════════════════════════

set -e  # Arrêter en cas d'erreur

# ═══════════════════════════════════════════════════════════════════
# PHASE 0 : VÉRIFICATION DES PRÉREQUIS
# ═══════════════════════════════════════════════════════════════════

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║  PHASE 0 : Vérification des prérequis                         ║"
echo "╚═══════════════════════════════════════════════════════════════╝"

# Vérifier AWS CLI
echo "Vérification AWS CLI..."
aws --version || { echo "❌ AWS CLI non installé"; exit 1; }

# Vérifier Terraform
echo "Vérification Terraform..."
terraform --version || { echo "❌ Terraform non installé"; exit 1; }

# Vérifier la configuration AWS
echo "Vérification connexion AWS..."
aws sts get-caller-identity || { echo "❌ AWS non configuré"; exit 1; }

echo "✅ Tous les prérequis sont satisfaits"
echo ""

# ═══════════════════════════════════════════════════════════════════
# PHASE 1 : BOOTSTRAP (INFRASTRUCTURE DE BASE)
# ═══════════════════════════════════════════════════════════════════

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║  PHASE 1 : Bootstrap (Infrastructure de base)                 ║"
echo "╚═══════════════════════════════════════════════════════════════╝"

cd bootstrap

# IMPORTANT : Modifier terraform.tfvars AVANT de continuer
echo ""
echo "⚠️  IMPORTANT !"
echo "⚠️  Avant de continuer, modifiez bootstrap/terraform.tfvars"
echo "⚠️  et mettez à jour la variable github_repo avec votre organisation/repo"
echo ""
read -p "Appuyez sur ENTRÉE quand c'est fait..."

# Initialiser Terraform
echo "Initialisation Terraform..."
terraform init

# Valider la configuration
echo "Validation de la configuration..."
terraform validate

# Planifier le déploiement
echo "Planification du déploiement..."
terraform plan -out=bootstrap.tfplan

# Demander confirmation
echo ""
read -p "Voulez-vous appliquer ce plan ? (yes/no) " -r
if [[ $REPLY =~ ^[Yy]es$ ]]; then
    terraform apply bootstrap.tfplan
else
    echo "Déploiement annulé"
    exit 1
fi

# Afficher les outputs
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "Bootstrap terminé ! Voici les ressources créées :"
echo "═══════════════════════════════════════════════════════════════"
terraform output

# Sauvegarder le Role ARN
GITHUB_ROLE_ARN=$(terraform output -raw github_actions_role_arn)
echo ""
echo "📝 Role ARN pour GitHub Actions :"
echo "$GITHUB_ROLE_ARN"
echo ""
echo "Copiez ce Role ARN, vous en aurez besoin pour GitHub Actions"
read -p "Appuyez sur ENTRÉE pour continuer..."

cd ..

# ═══════════════════════════════════════════════════════════════════
# PHASE 2 : VÉRIFICATION DES RESSOURCES BOOTSTRAP
# ═══════════════════════════════════════════════════════════════════

echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║  PHASE 2 : Vérification des ressources créées                 ║"
echo "╚═══════════════════════════════════════════════════════════════╝"

# Vérifier les buckets S3
echo "Buckets S3 créés :"
aws s3 ls | grep mcp

# Vérifier les tables DynamoDB
echo ""
echo "Tables DynamoDB créées :"
aws dynamodb list-tables --query 'TableNames[?contains(@, `terraform-lock`)]' --output table

# Vérifier le rôle IAM
echo ""
echo "Rôle IAM créé :"
aws iam get-role --role-name mcp-github-actions-role --query 'Role.Arn' --output text

echo ""
echo "✅ Toutes les ressources bootstrap sont créées"
echo ""

# ═══════════════════════════════════════════════════════════════════
# PHASE 3 : DÉPLOIEMENT INFRASTRUCTURE DEV
# ═══════════════════════════════════════════════════════════════════

echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║  PHASE 3 : Déploiement infrastructure DEV                     ║"
echo "╚═══════════════════════════════════════════════════════════════╝"

cd environments/dev

# Initialiser (connexion au backend S3)
echo "Initialisation Terraform (connexion au backend S3)..."
terraform init

# Valider
echo "Validation de la configuration..."
terraform validate

# Planifier
echo "Planification du déploiement DEV..."
terraform plan -out=dev.tfplan

# Demander confirmation
echo ""
echo "⚠️  Ceci va créer ~50+ ressources AWS dans l'environnement DEV"
read -p "Voulez-vous continuer ? (yes/no) " -r
if [[ $REPLY =~ ^[Yy]es$ ]]; then
    terraform apply dev.tfplan
else
    echo "Déploiement annulé"
    exit 1
fi

# Afficher les outputs
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "Infrastructure DEV déployée ! Voici les informations :"
echo "═══════════════════════════════════════════════════════════════"
terraform output

# Sauvegarder l'URL de l'API Gateway
API_GATEWAY_URL=$(terraform output -raw api_gateway_url 2>/dev/null || echo "N/A")
echo ""
echo "📝 URL de l'API Gateway :"
echo "$API_GATEWAY_URL"

cd ../..

# ═══════════════════════════════════════════════════════════════════
# PHASE 4 : VÉRIFICATION FINALE
# ═══════════════════════════════════════════════════════════════════

echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║  PHASE 4 : Vérification finale                                ║"
echo "╚═══════════════════════════════════════════════════════════════╝"

# Lambda functions
echo "Lambda Functions créées :"
aws lambda list-functions --query 'Functions[?starts_with(FunctionName, `dev-mcp`)].FunctionName' --output table

# Step Functions
echo ""
echo "Step Functions créées :"
aws stepfunctions list-state-machines --query 'stateMachines[?starts_with(name, `dev-mcp`)].name' --output table

# API Gateway
echo ""
echo "API Gateway :"
aws apigateway get-rest-apis --query 'items[?starts_with(name, `dev-mcp`)].{Name:name,ID:id}' --output table

# ═══════════════════════════════════════════════════════════════════
# RÉSUMÉ FINAL
# ═══════════════════════════════════════════════════════════════════

echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║                                                               ║"
echo "║              ✅ DÉPLOIEMENT TERMINÉ AVEC SUCCÈS               ║"
echo "║                                                               ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""
echo "🎉 L'infrastructure MCP a été déployée avec succès !"
echo ""
echo "📋 Prochaines étapes :"
echo ""
echo "1. Mettre à jour GitHub Actions avec le Role ARN :"
echo "   $GITHUB_ROLE_ARN"
echo ""
echo "2. Configurer les secrets GitHub (IBM MQ, MDMAE, etc.)"
echo ""
echo "3. Déployer le code Lambda avec le workflow deploy-lambda.yml"
echo ""
echo "4. Tester l'API Gateway :"
echo "   curl -X GET $API_GATEWAY_URL/api/health"
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "📚 Documentation :"
echo "   - QUICK_START.md        Guide de démarrage rapide"
echo "   - BOOTSTRAP_GUIDE.md    Guide détaillé du bootstrap"
echo "   - DEPLOYMENT_FLOW.md    Flow complet de déploiement"
echo ""
echo "═══════════════════════════════════════════════════════════════"