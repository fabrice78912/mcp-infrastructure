# Guide de Destruction et Recréation de l'Infrastructure MCP

Ce guide explique comment détruire complètement l'infrastructure MCP et la recréer depuis zéro.

## 📋 Table des matières

- [Prérequis](#prérequis)
- [Étape 1: Destruction via GitHub Actions](#étape-1-destruction-via-github-actions)
- [Étape 2: Vérification des JARs Lambda](#étape-2-vérification-des-jars-lambda)
- [Étape 3: Recréation via GitHub Actions](#étape-3-recréation-via-github-actions)
- [Étape 4: Configuration Post-Déploiement](#étape-4-configuration-post-déploiement)
- [Méthode Alternative: Ligne de Commande](#méthode-alternative-ligne-de-commande)
- [Troubleshooting](#troubleshooting)

---

## Prérequis

Avant de commencer, assurez-vous d'avoir:

- ✅ Accès au repository GitHub avec permissions d'exécuter les workflows
- ✅ Les JARs Lambda disponibles localement ou dans S3
- ✅ Les credentials AWS configurés (si utilisation CLI)
- ✅ Les valeurs des secrets (IBM MQ, MDMAE) à portée de main

---

## Étape 1: Destruction via GitHub Actions

### 1.1 Accéder au Workflow

1. Aller sur GitHub: `https://github.com/[votre-org]/mcp-infrastructure`
2. Cliquer sur l'onglet **"Actions"**
3. Sélectionner le workflow **"Deploy MCP Infrastructure"**

### 1.2 Lancer la Destruction

1. Cliquer sur **"Run workflow"** (bouton droit)
2. Sélectionner les paramètres:
   - **Environment**: `dev` (ou `prod`)
   - **Action**: `destroy`
3. Cliquer sur **"Run workflow"** (bouton vert)

### 1.3 Suivre l'Exécution

Le workflow va détruire (dans l'ordre):

```
✓ API Gateway (et tous ses endpoints)
✓ Step Functions State Machine
✓ Lambda Functions (7 fonctions)
✓ DynamoDB Table (avec toutes les données!)
✓ SQS Queues
✓ Secrets Manager (secrets vides recréés)
✓ VPC, Subnets, Security Groups
✓ IAM Roles et Policies
✓ CloudWatch Log Groups
```

**⚠️ ATTENTION**: Cette opération est **irréversible**. Toutes les données seront perdues!

**Durée estimée**: 2-3 minutes

### 1.4 Vérifier la Destruction

Le workflow affichera `Destroy complete! Resources: X destroyed.`

Vous pouvez vérifier dans la console AWS que les ressources ont été supprimées.

---

## Étape 2: Vérification des JARs Lambda

Avant de recréer l'infrastructure, **VÉRIFIEZ** que les JARs Lambda sont présents dans S3:

### Option A: Via AWS Console

1. Aller dans S3: `https://s3.console.aws.amazon.com/s3/buckets/bnc-mcp-lambda-artifacts`
2. Vérifier la présence de tous les JARs:
   - `ValidationLambda.jar`
   - `MatchingLambda.jar`
   - `UpdateProfileLambda.jar`
   - `PublishEventLambda.jar`
   - `HumanReviewLambda.jar`
   - `FccSenderLambda.jar`
   - `FccResponseProcessorLambda.jar`

### Option B: Via AWS CLI

```bash
aws s3 ls s3://bnc-mcp-lambda-artifacts/ --region ca-central-1
```

### Option C: Upload si nécessaire

Si les JARs sont manquants:

```bash
# Upload depuis votre répertoire local
cd /chemin/vers/mcp-orchestration/target

aws s3 cp ValidationLambda.jar s3://bnc-mcp-lambda-artifacts/ --region ca-central-1
aws s3 cp MatchingLambda.jar s3://bnc-mcp-lambda-artifacts/ --region ca-central-1
aws s3 cp UpdateProfileLambda.jar s3://bnc-mcp-lambda-artifacts/ --region ca-central-1
aws s3 cp PublishEventLambda.jar s3://bnc-mcp-lambda-artifacts/ --region ca-central-1
aws s3 cp HumanReviewLambda.jar s3://bnc-mcp-lambda-artifacts/ --region ca-central-1
aws s3 cp FccSenderLambda.jar s3://bnc-mcp-lambda-artifacts/ --region ca-central-1
aws s3 cp FccResponseProcessorLambda.jar s3://bnc-mcp-lambda-artifacts/ --region ca-central-1
```

Ou utilisez le script d'upload groupé:

```bash
cd /chemin/vers/mcp-orchestration/target
for jar in *Lambda.jar; do
  aws s3 cp "$jar" s3://bnc-mcp-lambda-artifacts/ --region ca-central-1
done
```

---

## Étape 3: Recréation via GitHub Actions

### 3.1 Lancer le Déploiement

1. Retourner dans **Actions** > **"Deploy MCP Infrastructure"**
2. Cliquer sur **"Run workflow"**
3. Sélectionner:
   - **Environment**: `dev` (ou `prod`)
   - **Action**: `apply`
4. Cliquer sur **"Run workflow"**

### 3.2 Suivre la Création

Le workflow va créer:

```
✓ VPC et Subnets
✓ Security Groups
✓ IAM Roles et Policies
✓ DynamoDB Table (vide)
✓ SQS Queues
✓ Secrets Manager (secrets vides)
✓ Lambda Functions (7 fonctions)
✓ Step Functions State Machine
✓ API Gateway (nouveau ID!)
✓ CloudWatch Log Groups
```

**Durée estimée**: 5-7 minutes

### 3.3 Récupérer les Outputs

À la fin du workflow, télécharger l'artifact **"terraform-outputs-dev-XXXX"** qui contient:

- `api_gateway_id`: Le **NOUVEAU** ID de l'API Gateway
- `api_gateway_url`: La **NOUVELLE** URL de l'endpoint
- `state_machine_arns`: Les ARNs des state machines
- `lambda_function_arns`: Les ARNs des Lambda functions

**⚠️ IMPORTANT**: L'URL de l'API Gateway sera **différente** de l'ancienne!

---

## Étape 4: Configuration Post-Déploiement

Après le déploiement, l'infrastructure est créée mais **NON CONFIGURÉE**. Vous devez:

### Option A: Script Automatisé (RECOMMANDÉ)

Utilisez le script de configuration automatique:

```bash
cd /chemin/vers/mcp-infrastructure
./scripts/post-deploy-setup.sh dev
```

Le script va:
1. ✅ Vérifier la présence des JARs dans S3
2. ✅ Vous demander les valeurs des secrets (interactif)
3. ✅ Configurer AWS Secrets Manager
4. ✅ Créer le client de test TEST123 dans DynamoDB
5. ✅ Récupérer l'URL de l'API Gateway
6. ✅ Tester l'endpoint automatiquement

**Durée**: 3-5 minutes (selon votre vitesse de saisie)

### Option B: Configuration Manuelle

Si vous préférez configurer manuellement:

#### 4.1 Configurer les Secrets

**Secret IBM MQ**:

```bash
aws secretsmanager put-secret-value \
  --secret-id dev/mcp/ibmmq \
  --secret-string '{
    "host": "mq.example.com",
    "port": "1414",
    "channel": "DEV.CHANNEL",
    "queueManager": "QM1",
    "username": "mquser",
    "password": "VOTRE_PASSWORD"
  }' \
  --region ca-central-1
```

**Secret MDMAE**:

```bash
aws secretsmanager put-secret-value \
  --secret-id dev/mcp/mdmae \
  --secret-string '{
    "url": "https://mdmae.example.com/api",
    "apiKey": "VOTRE_API_KEY"
  }' \
  --region ca-central-1
```

#### 4.2 Charger les Données de Test

```bash
aws dynamodb put-item \
  --table-name dev-ClientProfile \
  --item '{
    "clientId": {"S": "TEST123"},
    "firstName": {"S": "Jean"},
    "lastName": {"S": "Tremblay"},
    "dateOfBirth": {"S": "1990-01-01"},
    "email": {"S": "jean.tremblay@example.com"},
    "address": {"S": "123 Rue Principale, Montreal, QC H1A 1A1"},
    "phoneNumber": {"S": "+1-514-555-0100"}
  }' \
  --region ca-central-1
```

#### 4.3 Récupérer l'URL de l'API

```bash
cd environments/dev
terraform output api_gateway_url
```

Ou depuis AWS Console:
1. API Gateway > APIs > dev-mcp-api
2. Stages > dev
3. Copier l'**Invoke URL**

#### 4.4 Tester l'Endpoint

```bash
# Remplacer [API-ID] par le vrai ID
curl -X PUT "https://[API-ID].execute-api.ca-central-1.amazonaws.com/dev/api/clients/TEST123/nom" \
  -H "Content-Type: application/json" \
  -d '{
    "newLastName": "Leblanc",
    "reason": "MARIAGE"
  }'
```

Réponse attendue:

```json
{
  "message": "Client name update initiated",
  "executionArn": "arn:aws:states:ca-central-1:...:execution:dev-mcp-client_name_update:..."
}
```

---

## Méthode Alternative: Ligne de Commande

Si vous préférez ne pas utiliser GitHub Actions:

### Destruction

```bash
cd environments/dev

terraform destroy \
  -var="ibm_mq_host=dummy" \
  -var="ibm_mq_port=1414" \
  -var="ibm_mq_channel=dummy" \
  -var="ibm_mq_password=dummy" \
  -var="mdmae_url=http://localhost" \
  -auto-approve
```

### Recréation

```bash
cd environments/dev

# Init
terraform init

# Plan
terraform plan -var-file=dev.tfvars -out=tfplan

# Apply
terraform apply tfplan

# Post-configuration
cd ../..
./scripts/post-deploy-setup.sh dev
```

---

## Troubleshooting

### ❌ Erreur: "Lambda function code not found in S3"

**Cause**: Les JARs Lambda ne sont pas dans S3

**Solution**:
```bash
aws s3 ls s3://bnc-mcp-lambda-artifacts/
# Si vide, uploader les JARs (voir Étape 2)
```

### ❌ Erreur: "Secret not found"

**Cause**: Les secrets n'ont pas été configurés après le deploy

**Solution**:
```bash
# Relancer le script de configuration
./scripts/post-deploy-setup.sh dev

# Ou configurer manuellement (voir Étape 4.1)
```

### ❌ API Gateway retourne 403

**Cause**: Mauvaise URL ou mauvais déploiement

**Solution**:
```bash
# Vérifier l'URL actuelle
cd environments/dev
terraform output api_gateway_url

# Forcer un nouveau déploiement
terraform apply -target=module.api_gateway -replace=module.api_gateway.aws_api_gateway_deployment.main -auto-approve
```

### ❌ Step Functions échoue avec "Client introuvable"

**Cause**: DynamoDB est vide

**Solution**:
```bash
# Charger le client de test
aws dynamodb put-item \
  --table-name dev-ClientProfile \
  --item '{"clientId":{"S":"TEST123"},"firstName":{"S":"Jean"},"lastName":{"S":"Tremblay"},"dateOfBirth":{"S":"1990-01-01"},"email":{"S":"test@example.com"}}' \
  --region ca-central-1
```

### ❌ Lambda functions en erreur dans CloudWatch

**Cause**: Secrets vides ou mal configurés

**Solution**:
```bash
# Vérifier les secrets
aws secretsmanager get-secret-value --secret-id dev/mcp/ibmmq --region ca-central-1
aws secretsmanager get-secret-value --secret-id dev/mcp/mdmae --region ca-central-1

# Reconfigurer si nécessaire
./scripts/post-deploy-setup.sh dev
```

---

## 🔄 Workflow Complet Résumé

```
┌─────────────────────────────────────────────────────────────┐
│ 1. DESTROY via GitHub Actions                               │
│    → Environment: dev                                        │
│    → Action: destroy                                         │
│    → Durée: 2-3 minutes                                      │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 2. VÉRIFIER les JARs Lambda dans S3                         │
│    → aws s3 ls s3://bnc-mcp-lambda-artifacts/               │
│    → Si manquants: uploader depuis le build Java            │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 3. APPLY via GitHub Actions                                 │
│    → Environment: dev                                        │
│    → Action: apply                                           │
│    → Durée: 5-7 minutes                                      │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 4. CONFIGURER avec le script post-deploy                    │
│    → ./scripts/post-deploy-setup.sh dev                     │
│    → Remplir les secrets (interactif)                       │
│    → Charger les données de test                            │
│    → Tester l'endpoint                                       │
│    → Durée: 3-5 minutes                                      │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 5. ✅ INFRASTRUCTURE OPÉRATIONNELLE                          │
└─────────────────────────────────────────────────────────────┘
```

---

## 📝 Checklist Post-Recréation

Avant de considérer l'infrastructure comme opérationnelle, vérifier:

- [ ] Tous les JARs Lambda sont dans S3
- [ ] Le workflow GitHub Actions `apply` s'est terminé avec succès
- [ ] Les secrets IBM MQ et MDMAE sont configurés
- [ ] Le client TEST123 existe dans DynamoDB
- [ ] L'API Gateway répond (HTTP 200)
- [ ] Une exécution Step Functions se termine avec succès
- [ ] Les CloudWatch Logs montrent les exécutions Lambda
- [ ] La nouvelle URL de l'API est documentée/partagée avec l'équipe

---

## 📞 Support

En cas de problème:

1. Vérifier les logs CloudWatch des Lambda functions
2. Vérifier les logs d'exécution Step Functions
3. Consulter ce guide de troubleshooting
4. Contacter l'équipe DevOps

---

**Dernière mise à jour**: 2026-09-29