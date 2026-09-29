# ⚡ Quick Start - Déploiement Infrastructure MCP

Guide de démarrage rapide pour déployer l'infrastructure MCP sur AWS.

## 📋 Prérequis (5 minutes)

```bash
# 1. Vérifier les outils
aws --version       # ✅ Requis: 2.x.x
terraform --version # ✅ Requis: 1.9.0+

# 2. Configurer AWS
aws configure
# Entrer: Access Key ID, Secret Key, Region (ca-central-1)

# 3. Vérifier la connexion
aws sts get-caller-identity
```

---

## 🚀 Déploiement (10-15 minutes)

### Phase 1 : Bootstrap (PREMIÈRE FOIS SEULEMENT)

```bash
# 1. Modifier le repo GitHub
cd bootstrap
vim terraform.tfvars  # Modifier: github_repo = "votre-org/mcp-infrastructure"

# 2. Déployer
terraform init
terraform apply  # Taper: yes

# 3. Noter le Role ARN
terraform output github_actions_role_arn
# Output: arn:aws:iam::123456789:role/mcp-github-actions-role
```

**Ressources créées :**
- ✅ 2 buckets S3 (state dev/prod)
- ✅ 2 tables DynamoDB (locking)
- ✅ 1 bucket S3 (artifacts Lambda)
- ✅ 1 rôle IAM (GitHub Actions)

---

### Phase 2 : Infrastructure DEV

```bash
cd ../environments/dev

# 1. Initialiser (connecte au backend S3)
terraform init

# 2. Planifier
terraform plan

# 3. Déployer
terraform apply  # Taper: yes
```

**Ressources créées :**
- ✅ VPC + Subnets
- ✅ Lambda Functions (7+)
- ✅ Step Functions
- ✅ API Gateway
- ✅ DynamoDB tables
- ✅ MSK, SQS, CloudWatch, etc.

**Durée :** ~5-10 minutes

---

## 🐙 Configuration GitHub Actions (5 minutes)

### 1. Mettre à jour le workflow

Éditer `.github/workflows/terraform-deploy.yml` :

```yaml
- name: Configure AWS credentials
  uses: aws-actions/configure-aws-credentials@v4
  with:
    # Utiliser le Role ARN du bootstrap
    role-to-assume: arn:aws:iam::123456789:role/mcp-github-actions-role
    role-session-name: GitHubActions-${{ github.run_id }}
    aws-region: ca-central-1
```

### 2. Configurer les secrets GitHub

Repository → Settings → Secrets and variables → Actions

**Secrets nécessaires :**
```
DEV_IBM_MQ_HOST       = mq-dev.example.com
DEV_IBM_MQ_PASSWORD   = ***
DEV_MDMAE_URL         = https://mdmae-dev.example.com
```

**Secrets NON nécessaires (grâce à OIDC) :**
```
❌ AWS_ACCESS_KEY_ID       (plus besoin)
❌ AWS_SECRET_ACCESS_KEY   (plus besoin)
```

### 3. Tester le workflow

```bash
# Commit et push
git add .
git commit -m "Add bootstrap infrastructure"
git push origin main

# Dans GitHub:
# Actions → Deploy MCP Infrastructure → Run workflow
# Environment: dev
# Action: plan
```

---

## ✅ Vérification (2 minutes)

### Console AWS

```bash
# Ouvrir la console
open https://ca-central-1.console.aws.amazon.com/console/home

# Vérifier:
# - Lambda: https://console.aws.amazon.com/lambda
# - Step Functions: https://console.aws.amazon.com/states
# - API Gateway: https://console.aws.amazon.com/apigateway
# - DynamoDB: https://console.aws.amazon.com/dynamodb
```

### AWS CLI

```bash
# Lambda functions
aws lambda list-functions --query 'Functions[?starts_with(FunctionName, `dev-mcp`)].FunctionName'

# Step Functions
aws stepfunctions list-state-machines --query 'stateMachines[?starts_with(name, `dev-mcp`)].name'

# API Gateway URL
cd environments/dev
terraform output api_gateway_url
```

---

## 🧪 Test rapide

```bash
# Récupérer l'URL de l'API
API_URL=$(cd environments/dev && terraform output -raw api_gateway_url)

# Tester un endpoint (exemple)
curl -X GET "${API_URL}/api/health"

# Ou tester le workflow complet
curl -X PUT "${API_URL}/api/clients/TEST123/nom" \
  -H "Content-Type: application/json" \
  -d '{"newName": "Test User"}'
```

---

## 📊 Commandes utiles

### Terraform

```bash
# Voir les ressources
terraform state list

# Voir les outputs
terraform output

# Mettre à jour
terraform plan
terraform apply

# Détruire (⚠️ DANGER)
terraform destroy
```

### AWS CLI

```bash
# Lister les Lambda
aws lambda list-functions

# Voir les logs d'une Lambda
aws logs tail /aws/lambda/dev-mcp-client_profile_reader --follow

# Invoquer une Lambda
aws lambda invoke --function-name dev-mcp-client_profile_reader \
  --payload '{"clientId":"12345"}' output.json

# Voir l'exécution d'une Step Function
aws stepfunctions list-executions \
  --state-machine-arn arn:aws:states:...
```

---

## 🔧 Dépannage

### Erreur : Bucket already exists

```bash
# Importer le bucket existant
cd bootstrap
terraform import aws_s3_bucket.terraform_state_dev mcp-terraform-state-dev
terraform import aws_s3_bucket.terraform_state_prod mcp-terraform-state-prod
```

### Erreur : Access Denied

```bash
# Vérifier les permissions
aws iam get-user
aws iam list-attached-user-policies --user-name $(aws iam get-user --query 'User.UserName' --output text)
```

### Erreur : Lambda JAR not found

```bash
# Les JARs seront uploadés par le workflow deploy-lambda.yml
# Pour le moment, les Lambdas sont créées mais sans code
```

---

## 📚 Documentation complète

- **BOOTSTRAP_GUIDE.md** - Guide détaillé du bootstrap
- **bootstrap/README.md** - Documentation du module bootstrap
- **DEPLOYMENT_FLOW.md** - Flow complet de déploiement

---

## 🎯 Checklist

**Bootstrap (une fois) :**
- [ ] AWS CLI configuré
- [ ] `bootstrap/terraform.tfvars` modifié
- [ ] `cd bootstrap && terraform apply`
- [ ] Role ARN récupéré
- [ ] `.github/workflows/terraform-deploy.yml` mis à jour

**Infrastructure DEV :**
- [ ] `cd environments/dev && terraform init`
- [ ] `terraform apply`
- [ ] Ressources vérifiées dans AWS Console
- [ ] API Gateway URL récupérée
- [ ] Test endpoint réussi

**GitHub Actions :**
- [ ] Secrets configurés
- [ ] Workflow testé
- [ ] Déploiement automatique fonctionnel

---

## ⏱️ Temps total estimé

| Phase | Durée |
|-------|-------|
| Configuration AWS CLI | 5 min |
| Bootstrap | 5 min |
| Infrastructure DEV | 10 min |
| GitHub Actions | 5 min |
| Vérification | 5 min |
| **TOTAL** | **~30 minutes** |

---

**✅ Vous êtes prêt ! Bonne chance avec le déploiement !**