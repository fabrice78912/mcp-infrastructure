# Ordre de déploiement - BNC MCP Infrastructure

## 📌 Table des matières

1. [Vue d'ensemble](#vue-densemble)
2. [Règle d'or du déploiement](#règle-dor-du-déploiement)
3. [Ordre chronologique complet](#ordre-chronologique-complet)
4. [Détails de chaque étape](#détails-de-chaque-étape)
5. [Ce que déploie chaque repo](#ce-que-déploie-chaque-repo)
6. [Orchestration : Infrastructure vs Service métier](#orchestration--infrastructure-vs-service-métier)
7. [Cas spécifiques de re-déploiement](#cas-spécifiques-de-re-déploiement)
8. [Checklist pour le développeur](#checklist-pour-le-développeur)

---

## Vue d'ensemble

Après avoir terminé le développement d'une nouvelle feature sur les 2 repos (`mcp-infrastructure` et `mcp-local`), voici l'ordre exact de déploiement pour rendre la feature disponible sur un environnement (ex: DEV).

### Les 2 repos impliqués

```
mcp-infrastructure/          → Définit QUOI déployer (ressources AWS)
├── modules/
│   ├── step_functions/      → Orchestration (workflow ASL JSON)
│   ├── dynamodb/
│   ├── api_gateway/
│   ├── lambda/              → Déclaration des Lambdas
│   └── ...

mcp-local/                   → Définit COMMENT traiter (code métier)
├── src/main/java/com/bnc/mcp/
│   ├── controllers/         → Lambda Controllers
│   ├── lambdas/             → Lambdas métier
│   ├── validators/
│   └── utils/
```

---

## Règle d'or du déploiement

### ⚠️ **TOUJOURS déployer l'infrastructure AVANT le code**

```
┌─────────────────────────────────────────────────────────────┐
│  mcp-infrastructure (Terraform)  →  PUIS  →  mcp-local (Java)│
└─────────────────────────────────────────────────────────────┘
```

**Pourquoi ?**

Le code Java a besoin que les ressources AWS existent déjà :

```
❌ MAUVAIS ORDRE (Code avant infrastructure)
   mcp-local déployé → Lambda essaie d'écrire dans DynamoDB
   → ERROR: Table "dev-mcp-address-history" does not exist

✅ BON ORDRE (Infrastructure avant code)
   mcp-infrastructure déployé → DynamoDB table créée
   → mcp-local déployé → Lambda écrit dans DynamoDB existante
   → SUCCESS
```

---

## Ordre chronologique complet

```
┌─────────────────────────────────────────────────────────────────┐
│ PHASE 1 : DÉVELOPPEMENT LOCAL (sur votre machine)              │
└─────────────────────────────────────────────────────────────────┘
  1. Développement sur mcp-infrastructure (Terraform)
  2. Développement sur mcp-local (Code Java)
  3. Tests locaux (Spring Boot wrapper / AWS SAM)
  4. Commits + Push sur branches feature

┌─────────────────────────────────────────────────────────────────┐
│ PHASE 2 : CODE REVIEW                                           │
└─────────────────────────────────────────────────────────────────┘
  5. Créer PR mcp-infrastructure → Code Review → Approuver
  6. Créer PR mcp-local → Code Review → Approuver

┌─────────────────────────────────────────────────────────────────┐
│ PHASE 3 : DÉPLOIEMENT INFRASTRUCTURE ⭐ PREMIER                 │
└─────────────────────────────────────────────────────────────────┘
  7. Merger PR mcp-infrastructure dans main
  8. GitHub Actions : terraform plan (env=dev)
  9. Vérifier le plan
  10. GitHub Actions : terraform apply (env=dev)
  ✅ Ressources AWS créées (Step Functions, DynamoDB, API Gateway, Lambdas placeholder)

┌─────────────────────────────────────────────────────────────────┐
│ PHASE 4 : DÉPLOIEMENT CODE JAVA ⭐ DEUXIÈME                     │
└─────────────────────────────────────────────────────────────────┘
  11. Merger PR mcp-local dans main
  12. GitHub Actions : Build JARs (mvn package)
  13. Upload JARs vers S3
  14. Update Lambda functions avec JARs
  ✅ Lambdas mises à jour avec vrai code

┌─────────────────────────────────────────────────────────────────┐
│ PHASE 5 : VÉRIFICATION & TESTS                                  │
└─────────────────────────────────────────────────────────────────┘
  15. Vérifier ressources AWS (CLI/Console)
  16. Tester endpoint API Gateway (Postman/curl)
  17. Vérifier exécution Step Functions
  18. Vérifier logs CloudWatch
  ✅ Feature disponible sur DEV !
```

---

## Détails de chaque étape

### PHASE 1 : Développement local

#### Étape 1 : Développement sur mcp-infrastructure

```bash
cd /Users/fabricefoko/Documents/mcp-infrastructure
git checkout -b feature/client-address-update

# Créer les fichiers Terraform
# ✅ modules/step_functions/state_machines/client-address-update.json
# ✅ modules/dynamodb/main.tf (ajouter table address-history)
# ✅ modules/api_gateway/main.tf (ajouter route PUT /clients/{id}/address)
# ✅ modules/lambda/variables.tf (ajouter controller lambda)

git add .
git commit -m "Add infrastructure for client address update workflow"
git push origin feature/client-address-update
```

#### Étape 2 : Développement sur mcp-local

```bash
cd /Users/fabricefoko/Documents/mcp-local
git checkout -b feature/client-address-update

# Créer les fichiers Java
# ✅ src/main/java/com/bnc/mcp/controllers/ClientAddressUpdateController.java
# ✅ src/main/java/com/bnc/mcp/lambdas/ValidateAddressLambda.java
# ✅ src/main/java/com/bnc/mcp/lambdas/CheckAddressHistoryLambda.java
# ✅ src/main/java/com/bnc/mcp/validators/AddressValidator.java
# ✅ Tests unitaires

# Build local pour vérifier compilation
mvn clean package

git add .
git commit -m "Add client address update workflow implementation"
git push origin feature/client-address-update
```

#### Étape 3 : Tests locaux

```bash
# Option A : Spring Boot wrapper (développement rapide)
cd /Users/fabricefoko/Documents/mcp-local
mvn spring-boot:run
# Test sur http://localhost:8080

# Option B : AWS SAM CLI (simulation API Gateway)
sam local start-api --template template.yaml
# Test sur http://localhost:3000
```

---

### PHASE 2 : Code Review

#### Étape 5-6 : Pull Requests

```
GitHub → mcp-infrastructure
  PR: feature/client-address-update → main
  Code Review → Approuvé ✅

GitHub → mcp-local
  PR: feature/client-address-update → main
  Code Review → Approuvé ✅
```

---

### PHASE 3 : Déploiement Infrastructure ⭐ PREMIER

#### Étape 7 : Merger PR mcp-infrastructure

```bash
git checkout main
git pull origin main
# Le merge est fait sur GitHub après approbation
```

#### Étape 8 : GitHub Actions - terraform plan

```
Repository: mcp-infrastructure
Actions → Terraform Deploy → Run workflow

Inputs:
  - Branch: main
  - Environment: dev
  - Action: plan
```

**Logs du workflow :**

```hcl
Terraform will perform the following actions:

  # module.step_functions.aws_sfn_state_machine.this["client-address-update"] will be created
  + resource "aws_sfn_state_machine" "client-address-update" {
      + arn        = (known after apply)
      + name       = "dev-client-address-update-state-machine"
      + definition = <<-EOT
          {
            "Comment": "Workflow de mise à jour d'adresse client BNC",
            "StartAt": "ValidateAddressData",
            "States": { ... }
          }
        EOT
    }

  # module.dynamodb.aws_dynamodb_table.this["address-history"] will be created
  + resource "aws_dynamodb_table" "address-history" {
      + name         = "dev-mcp-address-history"
      + billing_mode = "PAY_PER_REQUEST"
      + hash_key     = "PK"
      + range_key    = "SK"
    }

  # module.api_gateway.aws_api_gateway_resource.this["clients_clientId_address"] will be created
  + resource "aws_api_gateway_resource" "clients_clientId_address" {
      + path = "/clients/{clientId}/address"
    }

  # module.lambda.aws_lambda_function.this["client-address-update-controller"] will be created
  + resource "aws_lambda_function" "client-address-update-controller" {
      + function_name = "dev-client-address-update-controller"
      + handler       = "com.bnc.mcp.controllers.ClientAddressUpdateController::handleRequest"
      + runtime       = "java17"
      + filename      = "placeholder.zip"  # ← PLACEHOLDER temporaire
      + environment {
          + variables = {
              + STATE_MACHINE_ARN = (known after apply)
            }
        }
    }

Plan: 12 to add, 0 to change, 0 to destroy.
```

#### Étape 10 : GitHub Actions - terraform apply

```
Repository: mcp-infrastructure
Actions → Terraform Deploy → Run workflow

Inputs:
  - Branch: main
  - Environment: dev
  - Action: apply  ← APPLY pour déployer
```

**Logs du workflow :**

```
module.dynamodb.aws_dynamodb_table.this["address-history"]: Creating...
module.step_functions.aws_sfn_state_machine.this["client-address-update"]: Creating...
module.lambda.aws_lambda_function.this["client-address-update-controller"]: Creating...
module.lambda.aws_lambda_function.this["validate-address"]: Creating...

...

module.dynamodb.aws_dynamodb_table.this["address-history"]: Creation complete [id=dev-mcp-address-history]
module.step_functions.aws_sfn_state_machine.this["client-address-update"]: Creation complete [id=arn:aws:states:ca-central-1:123456789:stateMachine:dev-client-address-update-state-machine]
module.lambda.aws_lambda_function.this["client-address-update-controller"]: Creation complete [id=dev-client-address-update-controller]
module.api_gateway.aws_api_gateway_deployment.this: Creation complete [id=abc123]

Apply complete! Resources: 12 added, 0 changed, 0 destroyed.

Outputs:
  api_gateway_url = "https://xyz123.execute-api.ca-central-1.amazonaws.com/dev"
  state_machine_arn = "arn:aws:states:ca-central-1:123456789:stateMachine:dev-client-address-update-state-machine"
```

**✅ Résultat PHASE 3 :**
- ✅ Step Functions créé avec workflow défini (JSON ASL)
- ✅ DynamoDB table créée
- ✅ API Gateway route créée
- ✅ **Lambdas créées avec code PLACEHOLDER** (fichier zip vide)
- ✅ IAM roles créés
- ✅ CloudWatch Log Groups créés

**⚠️ À ce stade, les Lambdas existent mais n'ont PAS encore le vrai code Java !**

---

### PHASE 4 : Déploiement Code Java ⭐ DEUXIÈME

#### Étape 11 : Merger PR mcp-local

```bash
git checkout main
git pull origin main
```

#### Étape 12-14 : GitHub Actions - Build et déploiement JARs

**Workflow : `.github/workflows/deploy-lambdas.yml` dans mcp-local**

```yaml
name: Deploy Lambda Code

on:
  workflow_dispatch:
    inputs:
      environment:
        description: 'Environment'
        required: true
        type: choice
        options:
          - dev
          - prod

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Set up JDK 17
        uses: actions/setup-java@v3
        with:
          java-version: '17'
          distribution: 'corretto'

      - name: Build JARs
        run: mvn clean package

      - name: Upload to S3
        run: |
          aws s3 sync target/ s3://bnc-mcp-lambda-artifacts/${{ inputs.environment }}/ \
            --exclude "*" \
            --include "*.jar"

      - name: Update Lambda Functions
        run: |
          for jar in target/*.jar; do
            function_name="${{ inputs.environment }}-$(basename $jar .jar)"
            aws lambda update-function-code \
              --function-name $function_name \
              --s3-bucket bnc-mcp-lambda-artifacts \
              --s3-key ${{ inputs.environment }}/$(basename $jar)
          done
```

**Déclencher le workflow :**

```
Repository: mcp-local
Actions → Deploy Lambda Code → Run workflow

Inputs:
  - Environment: dev
```

**Logs du workflow :**

```
Building JARs...
[INFO] Building client-address-update-controller 1.0.0
[INFO] Building validate-address-lambda 1.0.0
[INFO] Building check-address-history-lambda 1.0.0
[INFO] Building update-core-system-lambda 1.0.0
[INFO] Building publish-to-msk-lambda 1.0.0
[INFO] BUILD SUCCESS
[INFO] Total time: 45.123 s

Uploading to S3...
upload: target/client-address-update-controller-1.0.0.jar → s3://bnc-mcp-lambda-artifacts/dev/
upload: target/validate-address-lambda-1.0.0.jar → s3://bnc-mcp-lambda-artifacts/dev/
upload: target/check-address-history-lambda-1.0.0.jar → s3://bnc-mcp-lambda-artifacts/dev/
upload: target/update-core-system-lambda-1.0.0.jar → s3://bnc-mcp-lambda-artifacts/dev/
upload: target/publish-to-msk-lambda-1.0.0.jar → s3://bnc-mcp-lambda-artifacts/dev/

Updating Lambda Functions...
Updated function: dev-client-address-update-controller
  CodeSha256: abc123def456...
  LastModified: 2024-01-15T10:30:00.000+0000
  Status: Active

Updated function: dev-validate-address-lambda
  CodeSha256: ghi789jkl012...
  LastModified: 2024-01-15T10:30:05.000+0000
  Status: Active

Updated function: dev-check-address-history-lambda
  CodeSha256: mno345pqr678...
  Status: Active

Updated function: dev-update-core-system-lambda
  CodeSha256: stu901vwx234...
  Status: Active

Updated function: dev-publish-to-msk-lambda
  CodeSha256: yz5678abc901...
  Status: Active

✅ All Lambda functions updated successfully!
```

**✅ Résultat PHASE 4 :**
- ✅ Tous les JARs buildés
- ✅ Tous les JARs uploadés sur S3
- ✅ **Toutes les Lambdas mises à jour avec le vrai code Java**

---

### PHASE 5 : Vérification & Tests

#### Étape 15 : Vérifier ressources AWS

```bash
# Vérifier Step Functions
aws stepfunctions list-state-machines \
  --query "stateMachines[?name=='dev-client-address-update-state-machine']"

# Vérifier Lambdas
aws lambda get-function --function-name dev-client-address-update-controller
aws lambda get-function --function-name dev-validate-address-lambda

# Vérifier API Gateway
aws apigateway get-rest-apis --query "items[?name=='dev-mcp-api']"

# Vérifier DynamoDB
aws dynamodb describe-table --table-name dev-mcp-address-history
```

#### Étape 16 : Tester endpoint API Gateway

```bash
# Obtenir l'URL de l'API Gateway
API_URL="https://xyz123.execute-api.ca-central-1.amazonaws.com/dev"

# Test avec curl
curl -X PUT "${API_URL}/api/clients/123456789/address" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${TOKEN}" \
  -d '{
    "street": "1234 Rue Sherbrooke",
    "city": "Montreal",
    "province": "QC",
    "postalCode": "H3A 1B1"
  }'

# Réponse attendue :
# HTTP/1.1 202 Accepted
# {
#   "message": "Address update request accepted",
#   "executionArn": "arn:aws:states:ca-central-1:123456789:execution:dev-client-address-update-state-machine:addr-update-123456789-1705315800000"
# }
```

#### Étape 17 : Vérifier exécution Step Functions

```bash
# AWS Console
# Step Functions → State machines → dev-client-address-update-state-machine → Executions

# Ou via CLI
aws stepfunctions describe-execution \
  --execution-arn "arn:aws:states:ca-central-1:123456789:execution:dev-client-address-update-state-machine:addr-update-123456789-1705315800000"
```

#### Étape 18 : Vérifier logs CloudWatch

```bash
# Logs Lambda Controller
aws logs tail /aws/lambda/dev-client-address-update-controller --follow

# Logs Step Functions
aws logs tail /aws/stepfunctions/dev-client-address-update-state-machine --follow

# Logs Lambdas métier
aws logs tail /aws/lambda/dev-validate-address-lambda --follow
```

---

## Ce que déploie chaque repo

### 1. mcp-infrastructure (Terraform) déploie :

| Ressource AWS | Description | Exemple |
|--------------|-------------|---------|
| **Step Functions State Machine** | Définition du workflow (orchestration) | `dev-client-address-update-state-machine` |
| **DynamoDB Tables** | Tables pour stockage de données | `dev-mcp-address-history` |
| **SQS Queues** | Files de messages | `dev-mcp-fraud-review-queue` |
| **API Gateway** | Routes HTTP, méthodes, intégrations | `PUT /clients/{clientId}/address` |
| **Lambda Functions (PLACEHOLDER)** | Déclaration des Lambdas SANS code | `dev-client-address-update-controller` (vide) |
| **IAM Roles & Policies** | Permissions pour Lambdas et Step Functions | `dev-lambda-execution-role` |
| **CloudWatch Log Groups** | Groupes de logs | `/aws/lambda/dev-client-address-update-controller` |
| **Secrets Manager** | Secrets (API keys, DB credentials) | `dev/mcp/core-system-api-key` |
| **VPC, Subnets, Security Groups** | Réseau pour Lambdas | `dev-mcp-vpc` |
| **MSK Kafka Cluster** | Kafka pour événements | `dev-mcp-kafka-cluster` |
| **EventBridge Rules** | Règles d'événements | `dev-mcp-daily-batch-rule` |

**Résumé :** Terraform déploie **TOUTE** l'infrastructure AWS, mais les Lambdas n'ont **PAS** encore de code fonctionnel (fichier placeholder.zip vide).

---

### 2. mcp-local (Code Java) déploie :

| Artéfact | Description | Exemple |
|----------|-------------|---------|
| **JAR - Lambda Controller** | Code du contrôleur API | `client-address-update-controller-1.0.0.jar` |
| **JAR - Lambda ValidateAddress** | Code de validation d'adresse | `validate-address-lambda-1.0.0.jar` |
| **JAR - Lambda CheckHistory** | Code de vérification historique | `check-address-history-lambda-1.0.0.jar` |
| **JAR - Lambda UpdateCore** | Code de mise à jour système central | `update-core-system-lambda-1.0.0.jar` |
| **JAR - Lambda PublishMSK** | Code de publication Kafka | `publish-to-msk-lambda-1.0.0.jar` |

**Actions du déploiement :**
1. **Build** : `mvn clean package` → Génère les JARs
2. **Upload** : Upload des JARs vers S3 (`s3://bnc-mcp-lambda-artifacts/dev/`)
3. **Update** : `aws lambda update-function-code` → Met à jour chaque Lambda avec son JAR

**Résumé :** Le déploiement mcp-local **NE CRÉE AUCUNE** ressource AWS. Il **met à jour** uniquement le code des Lambdas déjà créées par Terraform.

---

### Tableau comparatif : Qui déploie quoi ?

| Élément | mcp-infrastructure | mcp-local |
|---------|-------------------|-----------|
| **Step Functions (workflow ASL JSON)** | ✅ Déploie la définition | ❌ |
| **DynamoDB Tables** | ✅ Crée les tables | ❌ |
| **API Gateway (routes, méthodes)** | ✅ Crée l'API | ❌ |
| **Lambda Functions (ressource)** | ✅ Crée les Lambdas | ❌ |
| **Lambda Functions (code JAR)** | ❌ (placeholder vide) | ✅ Upload le code |
| **IAM Roles** | ✅ Crée les rôles | ❌ |
| **CloudWatch Logs** | ✅ Crée les log groups | ❌ |
| **Secrets Manager** | ✅ Crée les secrets | ❌ |
| **Code métier (validation, traitement)** | ❌ | ✅ Implémente |
| **Variables d'environnement Lambda** | ✅ Définit (STATE_MACHINE_ARN, etc.) | ❌ |

---

## Orchestration : Infrastructure vs Service métier

### Question : Où se fait la définition du workflow d'orchestration ?

**Réponse courte pour BNC : L'orchestration se fait UNIQUEMENT dans mcp-infrastructure.**

### Détails de la séparation

#### 1. **mcp-infrastructure : ORCHESTRATION (Step Functions)**

**Définit LE WORKFLOW (le "quoi" et "dans quel ordre")** :

```json
// modules/step_functions/state_machines/client-address-update.json
{
  "Comment": "Workflow de mise à jour d'adresse client",
  "StartAt": "ValidateAddressData",
  "States": {
    "ValidateAddressData": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:...:function:${env}-validate-address-lambda",
      "Next": "CheckAddressHistory"
    },
    "CheckAddressHistory": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:...:function:${env}-check-address-history-lambda",
      "Next": "IsAddressChangeSuspicious"
    },
    "IsAddressChangeSuspicious": {
      "Type": "Choice",
      "Choices": [
        {
          "Variable": "$.historyCheck.suspiciousScore",
          "NumericGreaterThan": 0.8,
          "Next": "RequireManualApproval"
        }
      ],
      "Default": "UpdateAddressInCoreSystem"
    },
    "UpdateAddressInCoreSystem": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:...:function:${env}-update-core-system-lambda",
      "Next": "SaveAddressHistoryToDynamoDB"
    },
    "SaveAddressHistoryToDynamoDB": {
      "Type": "Task",
      "Resource": "arn:aws:states:::dynamodb:putItem",
      "Parameters": {
        "TableName": "${dynamodb_table_name}",
        "Item": { ... }
      },
      "Next": "PublishEventToMSK"
    }
  }
}
```

**Ce que Terraform/Infrastructure définit :**
- ✅ **Ordre d'exécution** des étapes
- ✅ **Conditions** (Choice states)
- ✅ **Gestion d'erreurs** (Retry, Catch)
- ✅ **Parallélisation** (Parallel states)
- ✅ **Attentes** (Wait states)
- ✅ **Intégrations directes AWS** (DynamoDB, SQS, SNS)
- ✅ **Quelles Lambdas appeler** (ARN des fonctions)

**Ce que Terraform/Infrastructure NE définit PAS :**
- ❌ La logique métier à l'intérieur de chaque Lambda
- ❌ Comment valider une adresse
- ❌ Comment détecter une fraude
- ❌ Comment appeler le système bancaire central

---

#### 2. **mcp-local : LOGIQUE MÉTIER (Code Java)**

**Implémente CE QUE FAIT chaque étape du workflow** :

```java
// ValidateAddressLambda.java
public class ValidateAddressLambda implements RequestHandler<Map<String, Object>, Map<String, Object>> {

    @Override
    public Map<String, Object> handleRequest(Map<String, Object> input, Context context) {
        // ✅ LOGIQUE MÉTIER : Comment valider une adresse
        Map<String, Object> address = (Map<String, Object>) input.get("address");

        // Validation du code postal canadien
        String postalCode = (String) address.get("postalCode");
        if (!postalCode.matches("^[A-Z]\\d[A-Z] \\d[A-Z]\\d$")) {
            throw new ValidationException("Invalid Canadian postal code");
        }

        // Validation de la ville
        if (!isValidCanadianCity((String) address.get("city"))) {
            throw new ValidationException("Invalid city");
        }

        // Validation de la province
        if (!Arrays.asList("QC", "ON", "BC", "AB").contains(address.get("province"))) {
            throw new ValidationException("Invalid province");
        }

        input.put("validationStatus", "VALID");
        return input;
    }

    private boolean isValidCanadianCity(String city) {
        // Logique métier pour valider la ville
        // Appel à une base de données, API externe, etc.
    }
}
```

```java
// CheckAddressHistoryLambda.java
public class CheckAddressHistoryLambda implements RequestHandler<Map<String, Object>, Map<String, Object>> {

    private final DynamoDbClient dynamoDb;

    @Override
    public Map<String, Object> handleRequest(Map<String, Object> input, Context context) {
        // ✅ LOGIQUE MÉTIER : Comment détecter une fraude
        String clientId = (String) input.get("clientId");

        // Récupérer l'historique d'adresses
        List<Address> history = getAddressHistory(clientId);

        // Calculer le score de suspicion
        double suspiciousScore = calculateSuspiciousScore(history, input.get("address"));

        // Logique métier : Plus de 3 changements en 6 mois = suspect
        if (history.size() > 3 && getRecentChanges(history, 6) > 3) {
            suspiciousScore += 0.3;
        }

        // Logique métier : Changement vers zone à risque = suspect
        if (isHighRiskArea((String) ((Map) input.get("address")).get("postalCode"))) {
            suspiciousScore += 0.5;
        }

        Map<String, Object> result = new HashMap<>();
        result.put("suspiciousScore", suspiciousScore);
        result.put("historyCount", history.size());
        input.put("historyCheck", result);

        return input;
    }
}
```

**Ce que le code Java définit :**
- ✅ **Comment** valider une adresse (règles métier)
- ✅ **Comment** calculer un score de fraude (algorithme)
- ✅ **Comment** appeler le système bancaire central (API)
- ✅ **Comment** transformer les données (mappings)
- ✅ **Comment** gérer les erreurs spécifiques (exceptions métier)

**Ce que le code Java NE définit PAS :**
- ❌ L'ordre d'exécution (c'est Step Functions qui décide)
- ❌ Les conditions de branchement (Choice states)
- ❌ Les retries et error handling (sauf erreurs métier)

---

### Schéma : Séparation des responsabilités

```
┌───────────────────────────────────────────────────────────────┐
│ INFRASTRUCTURE (mcp-infrastructure)                           │
│ Responsabilité : ORCHESTRATION                                │
├───────────────────────────────────────────────────────────────┤
│                                                               │
│  Step Functions Workflow (JSON ASL)                           │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │ 1. ValidateAddressData (Lambda ARN)                     │ │
│  │    ↓                                                    │ │
│  │ 2. CheckAddressHistory (Lambda ARN)                     │ │
│  │    ↓                                                    │ │
│  │ 3. IF suspiciousScore > 0.8 THEN ManualApproval        │ │
│  │    ↓                                                    │ │
│  │ 4. UpdateAddressInCoreSystem (Lambda ARN)               │ │
│  │    ↓                                                    │ │
│  │ 5. SaveToDynamoDB (Direct integration)                  │ │
│  │    ↓                                                    │ │
│  │ 6. PublishEventToMSK (Lambda ARN)                       │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                               │
│  Définit : QUOI faire, QUAND, dans QUEL ORDRE                │
└───────────────────────────────────────────────────────────────┘
                            ↓ Appelle
┌───────────────────────────────────────────────────────────────┐
│ SERVICE MÉTIER (mcp-local)                                    │
│ Responsabilité : LOGIQUE MÉTIER                               │
├───────────────────────────────────────────────────────────────┤
│                                                               │
│  ValidateAddressLambda.java                                   │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │ • Valide format code postal canadien                    │ │
│  │ • Vérifie ville existe                                  │ │
│  │ • Valide province                                       │ │
│  │ RETOURNE : validationStatus = "VALID"                   │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                               │
│  CheckAddressHistoryLambda.java                               │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │ • Récupère historique DynamoDB                          │ │
│  │ • Calcule score de fraude (algorithme métier)           │ │
│  │ • Détecte zones à risque                                │ │
│  │ RETOURNE : suspiciousScore = 0.85                       │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                               │
│  UpdateCoreSystemLambda.java                                  │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │ • Appelle API système bancaire central                  │ │
│  │ • Transforme données format interne BNC                 │ │
│  │ • Gère authentification, retry métier                   │ │
│  │ RETOURNE : coreSystemUpdateStatus = "SUCCESS"           │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                               │
│  Définit : COMMENT faire chaque tâche (logique métier)        │
└───────────────────────────────────────────────────────────────┘
```

---

### Pourquoi cette séparation chez BNC ?

| Raison | Explication |
|--------|-------------|
| **Séparation des préoccupations** | L'équipe infrastructure gère l'orchestration, l'équipe dev gère le métier |
| **Réutilisabilité** | Les mêmes Lambdas métier peuvent être utilisées dans différents workflows |
| **Traçabilité** | L'orchestration centralisée facilite l'audit bancaire |
| **Évolutivité** | Modifier la logique métier n'impacte pas l'orchestration (et vice-versa) |
| **Compliance** | Les workflows d'orchestration sont validés une fois, le code métier évolue souvent |
| **Visualisation** | Step Functions offre un graphe visuel du workflow pour la documentation |

---

### Exemple concret : Modification du workflow

**Scénario 1 : Changer l'orchestration (ajouter une étape)**

```
Besoin : Ajouter une vérification KYC (Know Your Customer) avant la mise à jour

Fichier modifié : mcp-infrastructure/modules/step_functions/state_machines/client-address-update.json

AVANT :
  CheckAddressHistory → UpdateAddressInCoreSystem

APRÈS :
  CheckAddressHistory → VerifyKYC → UpdateAddressInCoreSystem

Action :
  1. Modifier le JSON Step Functions
  2. terraform apply (mcp-infrastructure)
  3. Créer KYCLambda.java (mcp-local)
  4. Déployer JAR (mcp-local)
```

**Scénario 2 : Changer la logique métier (modifier algorithme fraude)**

```
Besoin : Améliorer l'algorithme de détection de fraude

Fichier modifié : mcp-local/src/.../CheckAddressHistoryLambda.java

AVANT :
  suspiciousScore = history.size() > 3 ? 0.8 : 0.2

APRÈS :
  suspiciousScore = calculateMLScore(history, newAddress)  // Machine Learning

Action :
  1. Modifier CheckAddressHistoryLambda.java
  2. mvn clean package (mcp-local)
  3. Déployer JAR (mcp-local)
  ❌ PAS BESOIN de toucher mcp-infrastructure !
```

---

### Peut-on faire l'orchestration dans le code Java ?

**Oui, techniquement c'est possible**, mais **NON recommandé pour BNC** :

#### Option alternative (non utilisée par BNC) : Orchestration dans le code

```java
// ❌ Anti-pattern pour BNC (mais possible)
public class ClientAddressUpdateOrchestrator implements RequestHandler<...> {

    @Override
    public APIGatewayProxyResponseEvent handleRequest(...) {
        // Orchestration manuelle dans le code
        try {
            // Étape 1
            Map validation = validateAddressLambda.invoke(input);

            // Étape 2
            Map historyCheck = checkHistoryLambda.invoke(validation);

            // Étape 3 : Décision
            if (historyCheck.get("suspiciousScore") > 0.8) {
                sendToManualReview(historyCheck);
            }

            // Étape 4
            Map updateResult = updateCoreLambda.invoke(historyCheck);

            // Étape 5
            dynamoDb.putItem(updateResult);

            // Étape 6
            publishToMSK(updateResult);

            return success();
        } catch (Exception e) {
            // Gestion d'erreur manuelle
            return error();
        }
    }
}
```

**Pourquoi BNC n'utilise PAS cette approche :**

| Problème | Impact |
|----------|--------|
| **Pas de visibilité** | Aucun graphe visuel du workflow |
| **Gestion d'erreurs complexe** | Retry, catch, timeout à coder manuellement |
| **Pas de traçabilité** | Difficile de savoir où le workflow a échoué |
| **Timeout Lambda** | Lambda max 15 min, workflows peuvent durer plus longtemps |
| **Pas de parallélisation** | Difficile d'exécuter des étapes en parallèle |
| **Coût** | Lambda facturé pendant toute la durée du workflow |
| **Audit** | Auditeurs bancaires veulent voir le workflow visuellement |

**Conclusion pour BNC :**

```
✅ APPROCHE BNC (Step Functions pour orchestration)
   Infrastructure (Terraform) → Workflow Step Functions (JSON ASL)
   Service (Java) → Logique métier de chaque Lambda

❌ APPROCHE NON-BNC (Code pour orchestration)
   Service (Java) → Workflow + Logique métier dans le même code
```

---

## Cas spécifiques de re-déploiement

### Tableau de décision : Quoi déployer ?

| Modification | mcp-infrastructure | mcp-local | Ordre |
|--------------|-------------------|-----------|-------|
| **Code Java uniquement** | ❌ | ✅ | N/A (1 seul repo) |
| **Workflow Step Functions (JSON)** | ✅ | ❌ | N/A (1 seul repo) |
| **Nouvelle table DynamoDB** | ✅ | ❌ | N/A (1 seul repo) |
| **Nouvelle Lambda** | ✅ Puis ✅ | Infrastructure → Code |
| **Variables d'env Lambda** | ✅ | ❌ | N/A (Terraform gère) |
| **Nouvelle route API Gateway** | ✅ Puis ✅ | Infrastructure → Code |
| **Modification IAM policies** | ✅ | ❌ | N/A (1 seul repo) |
| **Ajout étape dans workflow** | ✅ Puis ✅ | Infrastructure → Code |
| **Modification algorithme fraude** | ❌ | ✅ | N/A (1 seul repo) |
| **Upgrade runtime Java (17→21)** | ✅ Puis ✅ | Infrastructure → Code |
| **Nouvelle intégration MSK** | ✅ Puis ✅ | Infrastructure → Code |

---

### Exemples détaillés

#### Exemple 1 : Modifier uniquement le code Java

```bash
# Situation : Améliorer l'algorithme de validation d'adresse
# Fichier modifié : mcp-local/src/.../ValidateAddressLambda.java

# Actions :
cd /Users/fabricefoko/Documents/mcp-local
git checkout -b fix/improve-address-validation
# Modifier ValidateAddressLambda.java
mvn clean package
git commit -m "Improve address validation algorithm"
git push

# Après merge PR :
# GitHub Actions → Deploy Lambda Code (env=dev)
# ✅ Seulement validate-address-lambda mise à jour
# ❌ Pas besoin de toucher mcp-infrastructure
```

#### Exemple 2 : Ajouter une nouvelle étape dans le workflow

```bash
# Situation : Ajouter vérification KYC avant mise à jour

# ÉTAPE 1 : Infrastructure (ajouter étape dans workflow)
cd /Users/fabricefoko/Documents/mcp-infrastructure
git checkout -b feature/add-kyc-check

# Modifier : modules/step_functions/state_machines/client-address-update.json
# Ajouter état "VerifyKYC" entre CheckHistory et UpdateCore

# Modifier : modules/lambda/variables.tf
# Ajouter déclaration verify-kyc-lambda

git commit -m "Add KYC verification step to workflow"
git push

# Après merge PR :
# GitHub Actions → terraform apply (env=dev)
# ✅ Workflow Step Functions mis à jour
# ✅ Lambda verify-kyc créée (placeholder)

# ÉTAPE 2 : Code (implémenter la Lambda KYC)
cd /Users/fabricefoko/Documents/mcp-local
git checkout -b feature/add-kyc-check

# Créer : src/main/java/com/bnc/mcp/lambdas/VerifyKYCLambda.java

git commit -m "Implement KYC verification lambda"
git push

# Après merge PR :
# GitHub Actions → Deploy Lambda Code (env=dev)
# ✅ verify-kyc-lambda mise à jour avec code
```

#### Exemple 3 : Modifier variables d'environnement Lambda

```bash
# Situation : Changer l'URL du système bancaire central

# Actions : Modifier SEULEMENT mcp-infrastructure
cd /Users/fabricefoko/Documents/mcp-infrastructure

# Modifier : modules/lambda/main.tf
resource "aws_lambda_function" "update-core-system" {
  environment {
    variables = {
      CORE_SYSTEM_API_URL = "https://new-api.bnc.ca"  # ← Changé
    }
  }
}

# GitHub Actions → terraform apply (env=dev)
# ✅ Lambda mise à jour avec nouvelle variable d'env
# ❌ Pas besoin de re-déployer le code Java
```

---

## Checklist pour le développeur

### ✅ Avant de commencer

- [ ] Feature définie clairement (User Story, Acceptance Criteria)
- [ ] Architecture discutée (quelles ressources AWS nécessaires ?)
- [ ] Branche créée sur mcp-infrastructure : `feature/xxx`
- [ ] Branche créée sur mcp-local : `feature/xxx`

### ✅ Développement local

**mcp-infrastructure :**
- [ ] Workflow Step Functions créé (JSON ASL)
- [ ] Tables DynamoDB ajoutées si nécessaire
- [ ] Routes API Gateway ajoutées
- [ ] Déclarations Lambda ajoutées
- [ ] IAM policies ajoutées
- [ ] Variables d'environnement définies
- [ ] `terraform plan` local réussi

**mcp-local :**
- [ ] Lambda Controller créée
- [ ] Lambdas métier créées
- [ ] Validators créés
- [ ] Tests unitaires écrits (JUnit)
- [ ] `mvn clean package` réussi
- [ ] Tests locaux réussis (Spring Boot / SAM)

### ✅ Code Review

- [ ] PR mcp-infrastructure créée
- [ ] PR mcp-local créée
- [ ] Tests CI/CD passés (GitHub Actions)
- [ ] Code Review approuvé (2 reviewers min pour BNC)
- [ ] Documentation mise à jour

### ✅ Déploiement DEV

- [ ] PR mcp-infrastructure mergée
- [ ] GitHub Actions : `terraform plan` (env=dev) vérifié
- [ ] GitHub Actions : `terraform apply` (env=dev) exécuté ✅
- [ ] Outputs Terraform vérifiés (ARNs, URLs)
- [ ] PR mcp-local mergée
- [ ] GitHub Actions : Deploy Lambda Code (env=dev) exécuté ✅
- [ ] Vérification AWS Console (Step Functions, Lambdas, API Gateway)

### ✅ Tests sur DEV

- [ ] Test endpoint API Gateway avec Postman/curl
- [ ] Vérification exécution Step Functions (succès)
- [ ] Vérification logs CloudWatch (pas d'erreurs)
- [ ] Vérification DynamoDB (données écrites)
- [ ] Vérification Kafka MSK (événements publiés si applicable)
- [ ] Tests d'intégration E2E passés

### ✅ Déploiement PROD

- [ ] Feature validée sur DEV par Product Owner
- [ ] Tests de non-régression passés
- [ ] GitHub Actions : `terraform plan` (env=prod) vérifié
- [ ] **Demande d'approbation déploiement PROD** (process BNC)
- [ ] GitHub Actions : `terraform apply` (env=prod) exécuté ✅
- [ ] GitHub Actions : Deploy Lambda Code (env=prod) exécuté ✅
- [ ] Smoke tests PROD exécutés
- [ ] Monitoring Datadog/Splunk actif

### ✅ Post-déploiement

- [ ] Documentation mise à jour (Confluence, Wiki)
- [ ] Runbook créé/mis à jour (procédure d'urgence)
- [ ] Équipe support notifiée
- [ ] Monitoring dashboard créé/mis à jour
- [ ] Alertes CloudWatch configurées

---

## Schéma récapitulatif complet

```
┌─────────────────────────────────────────────────────────────────┐
│                    CYCLE DE VIE COMPLET                          │
└─────────────────────────────────────────────────────────────────┘

DÉVELOPPEMENT LOCAL
├─ mcp-infrastructure (Terraform)
│  └─ Définir : Step Functions, DynamoDB, API Gateway, Lambdas
├─ mcp-local (Java)
│  └─ Implémenter : Controllers, Lambdas métier, Validators
└─ Tests locaux (SAM / Spring Boot)

        ↓ git push

CODE REVIEW
├─ PR mcp-infrastructure → Approuvé ✅
└─ PR mcp-local → Approuvé ✅

        ↓ git merge

DÉPLOIEMENT 1 : INFRASTRUCTURE ⭐
├─ GitHub Actions : terraform apply (env=dev)
└─ ✅ Ressources AWS créées (Lambdas = placeholder)

        ↓

DÉPLOIEMENT 2 : CODE JAVA ⭐
├─ GitHub Actions : mvn package + upload JARs
└─ ✅ Lambdas mises à jour avec code réel

        ↓

TESTS & VALIDATION
├─ Test API Gateway endpoint
├─ Vérifier Step Functions execution
└─ Vérifier logs CloudWatch

        ↓

DÉPLOIEMENT PROD
├─ terraform apply (env=prod)
└─ Deploy Lambda Code (env=prod)

        ↓

MONITORING
├─ Datadog metrics
├─ Splunk logs
└─ CloudWatch alarms
```

---

## Résumé des points clés

1. **Ordre impératif** : Infrastructure AVANT Code
2. **Infrastructure déploie** : Ressources AWS (Step Functions, DynamoDB, API Gateway, Lambdas placeholder)
3. **Code déploie** : JARs Java pour les Lambdas
4. **Orchestration** : Définie dans mcp-infrastructure (Step Functions JSON)
5. **Logique métier** : Implémentée dans mcp-local (Lambdas Java)
6. **Séparation des responsabilités** : Infrastructure = QUOI/QUAND, Code = COMMENT
7. **Tests locaux** : Possibles avant déploiement AWS (SAM / Spring Boot)
8. **Déploiement manuel** : Via GitHub Actions avec inputs (branch, env, action)

---

## Références

- [DEPLOYMENT_FLOW.md](./DEPLOYMENT_FLOW.md) - Flux de déploiement détaillé
- [IMPLEMENTING_NEW_WORKFLOW.md](./IMPLEMENTING_NEW_WORKFLOW.md) - Guide d'implémentation
- [LAMBDA_CONTROLLER_PATTERN.md](./LAMBDA_CONTROLLER_PATTERN.md) - Pattern Lambda Controller