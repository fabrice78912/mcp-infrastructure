#!/bin/bash
set -e

echo "🧪 Testing Terraform configuration locally..."
echo ""

# Charger les variables d'environnement
if [ -f .env.local ]; then
    source .env.local
    echo "✅ Loaded environment variables from .env.local"
else
    echo "❌ .env.local not found!"
    echo ""
    echo "Please create .env.local from the template:"
    echo "  cp .env.local.example .env.local"
    echo "  # Edit .env.local with your values"
    echo ""
    exit 1
fi

# Vérifier que les variables sont définies
if [ -z "$IBM_MQ_HOST" ]; then
    echo "❌ IBM_MQ_HOST is not set in .env.local"
    exit 1
fi

echo ""

# Se placer dans dev
cd environments/dev

# Formater
echo "📝 Formatting code..."
terraform fmt -recursive
echo "✅ Code formatted"
echo ""

# Valider
echo "✔️  Validating configuration..."
terraform validate
echo "✅ Configuration is valid"
echo ""

# Plan
echo "📊 Creating Terraform plan..."
terraform plan \
  -var="ibm_mq_host=$IBM_MQ_HOST" \
  -var="ibm_mq_port=$IBM_MQ_PORT" \
  -var="ibm_mq_channel=$IBM_MQ_CHANNEL" \
  -var="ibm_mq_password=$IBM_MQ_PASSWORD" \
  -var="mdmae_url=$MDMAE_URL" \
  -out=tfplan.local

echo ""
echo "========================================="
echo "✅ All tests passed!"
echo "========================================="
echo ""
echo "📄 Plan saved to: tfplan.local"
echo ""
echo "Next steps:"
echo "  • Review the plan above"
echo "  • If everything looks good, commit your changes"
echo "  • Push to GitHub and deploy via GitHub Actions"
echo ""
echo "⚠️  To apply locally (not recommended):"
echo "  cd environments/dev"
echo "  terraform apply tfplan.local"
echo ""