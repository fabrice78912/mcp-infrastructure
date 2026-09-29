#!/bin/bash
# Script de création du backend Terraform (S3 + DynamoDB)
# Usage: ./scripts/create-backend.sh <environment>

set -e

ENVIRONMENT=$1
REGION="ca-central-1"

if [ -z "$ENVIRONMENT" ]; then
  echo "Usage: $0 <environment>"
  echo "Example: $0 dev"
  exit 1
fi

if [ "$ENVIRONMENT" != "dev" ] && [ "$ENVIRONMENT" != "prod" ]; then
  echo "Environment must be 'dev' or 'prod'"
  exit 1
fi

BUCKET_NAME="mcp-terraform-state-${ENVIRONMENT}"
DYNAMODB_TABLE="mcp-terraform-lock-${ENVIRONMENT}"

echo "========================================="
echo "Creating Terraform backend for: $ENVIRONMENT"
echo "========================================="
echo ""

# Créer le bucket S3
echo "📦 Creating S3 bucket: $BUCKET_NAME"
if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
  echo "  ✅ Bucket already exists"
else
  aws s3api create-bucket \
    --bucket "$BUCKET_NAME" \
    --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION"

  echo "  ✅ Bucket created"
fi

# Activer le versioning
echo "📝 Enabling versioning on S3 bucket"
aws s3api put-bucket-versioning \
  --bucket "$BUCKET_NAME" \
  --versioning-configuration Status=Enabled

# Activer l'encryption
echo "🔒 Enabling encryption on S3 bucket"
aws s3api put-bucket-encryption \
  --bucket "$BUCKET_NAME" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

# Bloquer l'accès public
echo "🚫 Blocking public access"
aws s3api put-public-access-block \
  --bucket "$BUCKET_NAME" \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# Créer la table DynamoDB pour le lock
echo "🔐 Creating DynamoDB table: $DYNAMODB_TABLE"
if aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" --region "$REGION" 2>/dev/null; then
  echo "  ✅ Table already exists"
else
  aws dynamodb create-table \
    --table-name "$DYNAMODB_TABLE" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "$REGION"

  echo "  ✅ Table created"

  # Attendre que la table soit active
  echo "  ⏳ Waiting for table to be active..."
  aws dynamodb wait table-exists --table-name "$DYNAMODB_TABLE" --region "$REGION"
  echo "  ✅ Table is active"
fi

echo ""
echo "========================================="
echo "✅ Backend created successfully!"
echo "========================================="
echo ""
echo "Backend configuration:"
echo "  Bucket:         $BUCKET_NAME"
echo "  DynamoDB Table: $DYNAMODB_TABLE"
echo "  Region:         $REGION"
echo ""
echo "You can now initialize Terraform:"
echo "  cd environments/$ENVIRONMENT"
echo "  terraform init"
echo ""