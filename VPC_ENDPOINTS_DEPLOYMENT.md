# VPC Endpoints Deployment Guide

Ce document explique comment déployer les VPC endpoints pour permettre aux Lambda functions dans le VPC d'accéder aux services AWS (DynamoDB, S3, Step Functions) sans avoir besoin d'un NAT gateway ou d'internet gateway.

---

## 🎯 Problème résolu

Avant cette mise à jour, les Lambda functions dans le VPC ne pouvaient pas accéder à DynamoDB, causant l'erreur:
```
Connect to dynamodb.ca-central-1.amazonaws.com:443 failed: Connect timed out
```

## ✅ Solution implémentée

Nous avons configuré 3 VPC endpoints:

1. **DynamoDB Gateway Endpoint** - Permet l'accès à DynamoDB depuis le VPC
2. **S3 Gateway Endpoint** - Permet l'accès à S3 depuis le VPC (pour les artifacts Lambda)
3. **Step Functions Interface Endpoint** - Permet l'accès à Step Functions depuis le VPC

---

## 📋 Changements Terraform

### Modules VPC (`modules/vpc/main.tf`)

```hcl
# Route table pour les subnets privés
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  ...
}

# Gateway endpoints (DynamoDB et S3)
resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id          = aws_vpc.main.id
  service_name    = "com.amazonaws.ca-central-1.dynamodb"
  route_table_ids = [aws_route_table.private.id]
  ...
}

# Interface endpoint (Step Functions)
resource "aws_vpc_endpoint" "stepfunctions" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.ca-central-1.states"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.0.id]
  private_dns_enabled = true
  ...
}
```

### Environment Dev (`environments/dev/main.tf`)

```hcl
module "vpc" {
  source = "../../modules/vpc"

  environment          = var.environment
  project_name         = var.project_name
  vpc_cidr             = "10.0.0.0/16"
  availability_zones   = ["ca-central-1a", "ca-central-1b"]
  private_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]

  # NOUVEAU: Activer les VPC endpoints
  enable_vpc_endpoints = true
}
```

---

## 🚀 Déploiement

### Option A: Déploiement manuel avec Terraform

```bash
cd /Users/fabricefoko/Documents/mcp-infrastructure/environments/dev

# Initialiser Terraform (si pas déjà fait)
terraform init

# Vérifier les changements
terraform plan

# Appliquer les changements
terraform apply

# Résultat attendu:
# + aws_vpc_endpoint.dynamodb[0]
# + aws_vpc_endpoint.s3[0]
# + aws_vpc_endpoint.stepfunctions[0]
# + aws_route_table.private
# + aws_route_table_association.private[0]
# + aws_route_table_association.private[1]
# + aws_security_group.vpc_endpoints[0]
```

### Option B: Déploiement automatique via GitHub Actions

**TODO**: Créer un workflow `.github/workflows/terraform-deploy.yml` qui:
1. Se déclenche sur push vers `main`
2. Exécute `terraform plan` pour review
3. Exécute `terraform apply` après approbation manuelle
4. Publie un résumé des changements

---

## 🧪 Validation post-déploiement

### 1. Vérifier les VPC endpoints créés

```bash
# Lister les VPC endpoints
aws ec2 describe-vpc-endpoints \
  --region ca-central-1 \
  --filters "Name=tag:Environment,Values=dev" \
  --query 'VpcEndpoints[*].[VpcEndpointId,ServiceName,State]' \
  --output table

# Résultat attendu:
# +----------------------+--------------------------------------+-----------+
# | VpcEndpointId        | ServiceName                          | State     |
# +----------------------+--------------------------------------+-----------+
# | vpce-xxxxx           | com.amazonaws.ca-central-1.dynamodb  | available |
# | vpce-yyyyy           | com.amazonaws.ca-central-1.s3        | available |
# | vpce-zzzzz           | com.amazonaws.ca-central-1.states    | available |
# +----------------------+--------------------------------------+-----------+
```

### 2. Vérifier les route tables

```bash
# Vérifier que les endpoints sont associés aux route tables
aws ec2 describe-route-tables \
  --region ca-central-1 \
  --filters "Name=tag:Name,Values=dev-mcp-private-rt" \
  --query 'RouteTables[0].Routes' \
  --output table

# Vous devriez voir des routes vers les VPC endpoints
```

### 3. Re-activer VPC config sur Lambda et tester

```bash
# Mettre à jour la Lambda pour utiliser le VPC
aws lambda update-function-configuration \
  --function-name dev-mcp-client_profile_reader \
  --vpc-config SubnetIds=subnet-xxxx,subnet-yyyy,SecurityGroupIds=sg-zzzz \
  --region ca-central-1

# Attendre que la mise à jour soit terminée
sleep 30

# Tester l'invocation
aws lambda invoke \
  --function-name dev-mcp-client_profile_reader \
  --cli-binary-format raw-in-base64-out \
  --payload '{"clientId":"12345","newLastName":"Tremblay","reason":"MARIAGE"}' \
  --region ca-central-1 \
  response.json

# Vérifier le résultat
cat response.json

# Résultat attendu:
# Erreur métier "Client introuvable" au lieu de timeout DynamoDB
```

---

## 💰 Coûts estimés

### VPC Endpoints Gateway (S3 et DynamoDB)
- **Coût**: GRATUIT (pas de frais pour les gateway endpoints)

### VPC Endpoint Interface (Step Functions)
- **Coût**: ~$0.01 USD/heure/AZ + $0.01 USD/GB de données transférées
- **Estimation mensuelle**: ~$15 USD/mois (2 AZ × $0.01/h × 730h)

### Économies
- **NAT Gateway évité**: ~$33 USD/mois/AZ
- **Économie nette**: ~$51 USD/mois (2 NAT gateways évités - 1 interface endpoint)

---

## 🔍 Troubleshooting

### Problème: Lambda timeout après déploiement VPC endpoints

**Vérifications**:
1. Les VPC endpoints sont bien en état "available"
2. Les route tables ont bien les routes vers les endpoints
3. Le security group des endpoints autorise le trafic HTTPS (port 443)
4. Les Lambda functions utilisent bien les subnets privés

**Solution**:
```bash
# Vérifier l'état des endpoints
aws ec2 describe-vpc-endpoints \
  --vpc-endpoint-ids vpce-xxxxx \
  --region ca-central-1 \
  --query 'VpcEndpoints[0].State'

# Vérifier les security groups
aws ec2 describe-security-groups \
  --group-ids sg-xxxxx \
  --region ca-central-1 \
  --query 'SecurityGroups[0].IpPermissions'
```

### Problème: Step Functions ne peut pas être invoqué depuis Lambda

**Cause possible**: L'interface endpoint Step Functions n'a pas le Private DNS activé

**Solution**:
```bash
# Vérifier le Private DNS
aws ec2 describe-vpc-endpoints \
  --filters "Name=service-name,Values=com.amazonaws.ca-central-1.states" \
  --region ca-central-1 \
  --query 'VpcEndpoints[0].PrivateDnsEnabled'

# Résultat attendu: true
```

---

## 📝 Prochaines étapes

1. ✅ VPC endpoints configurés dans Terraform
2. ⏳ **Appliquer les changements Terraform** (à faire maintenant)
3. ⏳ Re-activer VPC config sur toutes les Lambda functions
4. ⏳ Tester l'application end-to-end avec Step Functions
5. ⏳ Mettre à jour le workflow GitHub Actions pour déploiement automatique
6. ⏳ Tester en local avec Docker Compose et Swagger UI

---

**Status**: Configuration prête, en attente d'application Terraform