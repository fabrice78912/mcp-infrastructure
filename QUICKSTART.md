# Quick Start Guide

Ce guide vous permet de déployer l'infrastructure MCP sur AWS en 15 minutes.

## ⚠️ État actuel du projet

L'infrastructure Terraform est **partiellement créée**. Voici ce qui a été fait et ce qu'il reste à faire:

### ✅ Fichiers créés

**Structure de base**:
- ✅ `.gitignore` - Ignorer les fichiers sensibles
- ✅ `README.md` - Documentation complète
- ✅ `.terraform-version` - Version Terraform 1.9.0
- ✅ `.github/workflows/terraform-deploy.yml` - GitHub Actions workflow

**Scripts**:
- ✅ `scripts/create-backend.sh` - Créer S3 + DynamoDB pour state
- ✅ `scripts/build-lambda-packages.sh` - Builder les JARs Lambda

**Modules Terraform créés**:
- ✅ `modules/iam/` - Rôles IAM (Lambda, Step Functions, EventBridge)
- ✅ `modules/dynamodb/` - Table ClientProfile

**Environnements**:
- ✅ `environments/dev/backend.tf` - Backend S3 dev
- ✅ `environments/dev/variables.tf` - Variables dev
- ✅ `environments/dev/main.tf` - Configuration complète dev
- ✅ `environments/dev/outputs.tf` - Outputs dev
- ✅ `environments/dev/terraform.tfvars.example` - Exemple de variables

### ❌ Modules Terraform manquants (à créer)

Les modules suivants sont **référencés** dans `environments/dev/main.tf` mais **pas encore créés**:

1. **`modules/secrets-manager/`** - Stocker secrets IBM MQ, MDMAE
2. **`modules/sqs/`** - Queues SQS pour réponses FCC
3. **`modules/vpc/`** - VPC, subnets, security groups pour MSK
4. **`modules/msk/`** - MSK Serverless cluster
5. **`modules/lambda/`** - 7 Lambda functions
6. **`modules/eventbridge/`** - Schedule pour MQ poller
7. **`modules/step-functions/`** - State machine ClientNameUpdate
8. **`modules/api-gateway/`** - REST API
9. **`modules/cloudwatch/`** - Log groups et alarmes

### ❌ Environnement prod (à créer)

- ❌ `environments/prod/` - Copie de dev avec valeurs prod

---

## 🚀 Prochaines étapes

### Option A: Je termine la création pour vous

Je peux continuer à créer tous les modules manquants (estimé: 30-45 minutes de travail).

**Avantages**:
- Infrastructure complète et prête à déployer
- Tous les modules interconnectés
- GitHub Actions fonctionnels

**Commandez-moi**: "Continue et termine tous les modules Terraform"

### Option B: Vous terminez vous-même

Vous pouvez créer les modules manquants en vous basant sur:
- Les modules déjà créés (IAM, DynamoDB) comme templates
- Le guide `DEPLOYMENT_AWS.md` (section Lambda)
- La structure définie dans `environments/dev/main.tf`

**Commande pour chaque module**:
```bash
mkdir -p modules/{nom_module}
cd modules/{nom_module}
touch main.tf variables.tf outputs.tf
```

### Option C: Déploiement minimal (DynamoDB seulement)

Pour tester rapidement, vous pouvez:

1. Commenter les modules manquants dans `environments/dev/main.tf`
2. Ne garder que DynamoDB et IAM
3. Déployer via GitHub Actions

---

## 🎯 Déploiement rapide (une fois les modules créés)

### Étape 1: Configurer GitHub Secrets

Allez dans **Settings > Secrets and variables > Actions** et ajoutez:

```
AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
AWS_REGION=ca-central-1

DEV_IBM_MQ_HOST=votre-url-ngrok.ngrok.io
DEV_IBM_MQ_PORT=1414
DEV_IBM_MQ_CHANNEL=DEV.APP.SVRCONN
DEV_IBM_MQ_PASSWORD=passw0rd
DEV_MDMAE_URL=http://localhost:8089
```

### Étape 2: Créer le backend S3

```bash
cd /Users/fabricefoko/Documents/mcp-infrastructure
./scripts/create-backend.sh dev
```

Résultat attendu:
```
✅ Backend created successfully!
  Bucket:         mcp-terraform-state-dev
  DynamoDB Table: mcp-terraform-lock-dev
  Region:         ca-central-1
```

### Étape 3: Initialiser Git et GitHub

```bash
cd /Users/fabricefoko/Documents/mcp-infrastructure
git init
git checkout -b dev

# Créer repo sur GitHub (github.com/new)
git remote add origin https://github.com/VOTRE_USERNAME/mcp-infrastructure.git

git add .
git commit -m "Initial Terraform infrastructure"
git push -u origin dev
```

### Étape 4: Déployer via GitHub Actions

1. Allez sur GitHub: **Actions > Deploy MCP Infrastructure**
2. Cliquez **Run workflow**
3. Sélectionnez:
   - Environment: `dev`
   - Action: `plan`
4. Cliquez **Run workflow**
5. Vérifiez le plan
6. Relancez avec Action: `apply`

### Étape 5: Tester l'API

Une fois déployé:

```bash
# Récupérer l'URL de l'API depuis les outputs
cd environments/dev
terraform output api_gateway_url

# Tester
curl -X PUT https://xxxxx.execute-api.ca-central-1.amazonaws.com/dev/api/clients/CL000001/nom \
  -H "Content-Type: application/json" \
  -d '{"nouveauNom": "TestAWS"}'
```

---

## 🛠 Dépannage

### Erreur: "Module not found"

**Cause**: Un module référencé dans `main.tf` n'existe pas encore.

**Solution**:
1. Vérifiez la liste des modules manquants ci-dessus
2. Créez le module manquant OU commentez temporairement dans `main.tf`

### Erreur: "Backend S3 bucket does not exist"

**Cause**: Le bucket S3 pour le state Terraform n'a pas été créé.

**Solution**:
```bash
./scripts/create-backend.sh dev
```

### IBM MQ non accessible depuis Lambda

**Cause**: IBM MQ tourne localement sur votre machine, non accessible depuis AWS.

**Solutions**:

**Option 1: ngrok (pour dev)**
```bash
brew install ngrok
ngrok tcp 1414

# Utilisez l'URL ngrok dans GitHub Secrets
# DEV_IBM_MQ_HOST=0.tcp.ngrok.io
# DEV_IBM_MQ_PORT=12345
```

**Option 2: Déployer IBM MQ sur AWS EC2**

**Option 3: Utiliser Amazon MQ** (service géré)

---

## 📊 Estimation des coûts

**Environnement dev**:
- DynamoDB: $2-3/mois
- Lambda: $5-10/mois
- Step Functions: $2-5/mois
- MSK Serverless: $5-10/mois
- CloudWatch: $1-2/mois
- **Total: ~$15-30/mois**

**IMPORTANT**: Pour minimiser les coûts:
- Détruire l'environnement quand non utilisé: `terraform destroy`
- Utiliser GitHub Actions avec `action: destroy` après les tests

---

## ❓ Besoin d'aide ?

**Pour que je termine les modules**:
> "Continue et crée tous les modules manquants"

**Pour des questions spécifiques**:
> "Comment créer le module SQS ?"
> "Explique-moi la structure du module Lambda"

**Pour déployer en prod**:
> "Crée l'environnement prod"

---

**Auteur**: Claude Code
**Date**: 2026-09-23
**Status**: Infrastructure Terraform partiellement créée - modules critiques manquants