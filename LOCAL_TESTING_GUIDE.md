# Guide de test local avant déploiement automatique

## 📌 Table des matières

1. [Vue d'ensemble](#vue-densemble)
2. [Option 1 : Test Lambda isolée (Recommandé pour développement rapide)](#option-1--test-lambda-isolée-recommandé-pour-développement-rapide)
3. [Option 2 : Test avec AWS SAM CLI (Simulation locale complète)](#option-2--test-avec-aws-sam-cli-simulation-locale-complète)
4. [Option 3 : Déploiement Terraform local (Test sur AWS réel)](#option-3--déploiement-terraform-local-test-sur-aws-réel)
5. [Option 4 : Spring Boot wrapper (Développement rapide)](#option-4--spring-boot-wrapper-développement-rapide)
6. [Workflow recommandé BNC](#workflow-recommandé-bnc)

---

## Vue d'ensemble

### ⚠️ IMPORTANT : Approche moderne vs ancienne

**AVANT (Approche manuelle - NON recommandée) :**
```bash
# ❌ Ne plus faire ça avec GitHub Actions
mvn clean package
cp target/*.jar mcp-infrastructure/modules/lambda/functions/
cd mcp-infrastructure
terraform apply
```

**MAINTENANT (Approche automatique - Recommandée BNC) :**
```bash
# ✅ Tests locaux d'abord
mvn clean package
# Tests unitaires, SAM local, Spring Boot wrapper...

# ✅ Puis déploiement automatique via GitHub Actions
git push → PR → Merge → GitHub Actions déploie automatiquement
```

---

### Les 4 options de test local

| Option | Rapidité | Réalisme | Complexité | Cas d'usage |
|--------|----------|----------|-----------|-------------|
| **1. Lambda isolée** | ⚡ Très rapide | ⭐ Faible | ⭐ Simple | Tests unitaires, validation code |
| **2. AWS SAM CLI** | ⚡ Rapide | ⭐⭐⭐ Moyen | ⭐⭐ Moyen | Test workflow complet localement |
| **3. Terraform local** | 🐌 Lent | ⭐⭐⭐⭐ Élevé | ⭐⭐⭐ Complexe | Test sur AWS avant PR |
| **4. Spring Boot** | ⚡ Très rapide | ⭐⭐ Faible | ⭐ Simple | Développement itératif rapide |

---

## Option 1 : Test Lambda isolée (Recommandé pour développement rapide)

### 🎯 Objectif

Tester la **logique métier** d'une Lambda sans déployer sur AWS, sans API Gateway, sans Step Functions.

### Prérequis

- Java 17 installé
- Maven installé
- Code Lambda implémenté

### Étapes

#### 1. Créer une classe de test local

**Créer `src/test/java/com/bnc/mcp/local/LocalLambdaTest.java`** :

```java
package com.bnc.mcp.local;

import com.amazonaws.services.lambda.runtime.Context;
import com.bnc.mcp.handlers.AddressValidatorHandler;
import com.bnc.mcp.models.AddressValidationResult;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;

import java.util.HashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

public class LocalLambdaTest {

    @Test
    public void testAddressValidatorLocally() {
        // Arrange
        AddressValidatorHandler handler = new AddressValidatorHandler();
        Context mockContext = Mockito.mock(Context.class);
        Mockito.when(mockContext.getRequestId()).thenReturn("local-test-123");

        Map<String, Object> input = new HashMap<>();
        input.put("clientId", "123456789");

        Map<String, String> address = new HashMap<>();
        address.put("street", "1500 rue Peel");
        address.put("city", "Montreal");
        address.put("province", "QC");
        address.put("postalCode", "H3A1S9");
        address.put("country", "CA");
        input.put("address", address);

        // Act
        AddressValidationResult result = handler.handleRequest(input, mockContext);

        // Assert
        assertTrue(result.isValid(), "Address should be valid");
        assertEquals("H3A 1S9", result.getNormalizedAddress().getPostalCode(), "Postal code should be normalized");

        System.out.println("✅ Test passed!");
        System.out.println("Result: " + result);
    }
}
```

#### 2. Exécuter le test

```bash
cd /Users/fabricefoko/Downloads/mcp-local

# Exécuter tous les tests
mvn test

# Exécuter un test spécifique
mvn test -Dtest=LocalLambdaTest#testAddressValidatorLocally

# Avec logs détaillés
mvn test -Dtest=LocalLambdaTest -X
```

**Output attendu :**
```
[INFO] Running com.bnc.mcp.local.LocalLambdaTest
✅ Test passed!
Result: AddressValidationResult(isValid=true, errors=[], normalizedAddress=Address(street=1500 RUE PEEL, city=MONTREAL, province=QC, postalCode=H3A 1S9, country=CA))
[INFO] Tests run: 1, Failures: 0, Errors: 0, Skipped: 0
[INFO] BUILD SUCCESS
```

---

### Avantages

- ✅ **Très rapide** (< 5 secondes)
- ✅ **Pas besoin d'AWS**
- ✅ **Pas besoin d'Internet**
- ✅ **Itération rapide** (modifier code → tester)
- ✅ **Debugging facile** (IDE breakpoints)

### Inconvénients

- ❌ Ne teste pas l'intégration avec Step Functions
- ❌ Ne teste pas API Gateway
- ❌ Ne teste pas les permissions IAM
- ❌ Ne teste pas le workflow complet

---

## Option 2 : Test avec AWS SAM CLI (Simulation locale complète)

### 🎯 Objectif

Simuler **API Gateway + Lambda** localement sans déployer sur AWS.

### Prérequis

```bash
# Installer AWS SAM CLI
brew install aws-sam-cli

# Vérifier installation
sam --version
# SAM CLI, version 1.100.0
```

### Étapes

#### 1. Créer template SAM

**Créer `template.yaml` à la racine de `mcp-local`** :

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Transform: AWS::Serverless-2016-10-31
Description: Local testing template for BNC MCP Lambdas

Globals:
  Function:
    Timeout: 30
    MemorySize: 512
    Runtime: java17
    Environment:
      Variables:
        AWS_REGION: ca-central-1
        LOCAL_MODE: "true"

Resources:
  # Lambda Controller
  ClientAddressUpdateController:
    Type: AWS::Serverless::Function
    Properties:
      Handler: com.bnc.mcp.controllers.ClientAddressUpdateController::handleRequest
      CodeUri: target/client-address-update-controller-1.0.0.jar
      Environment:
        Variables:
          STATE_MACHINE_ARN: "arn:aws:states:local:123456789:stateMachine:local-test"
      Events:
        UpdateAddress:
          Type: Api
          Properties:
            Path: /api/clients/{clientId}/address
            Method: PUT

  # Lambda Validator
  AddressValidator:
    Type: AWS::Serverless::Function
    Properties:
      Handler: com.bnc.mcp.handlers.AddressValidatorHandler::handleRequest
      CodeUri: target/address-validator-1.0.0.jar
      Events:
        ValidateAddress:
          Type: Api
          Properties:
            Path: /validate/address
            Method: POST

  # Lambda History Check
  CheckAddressHistory:
    Type: AWS::Serverless::Function
    Properties:
      Handler: com.bnc.mcp.handlers.CheckAddressHistoryHandler::handleRequest
      CodeUri: target/check-address-history-1.0.0.jar
      Environment:
        Variables:
          DYNAMODB_TABLE_NAME: "local-address-history"
```

#### 2. Modifier le code pour supporter le mode local

**Modifier les Lambdas pour détecter le mode local :**

```java
// Dans ClientAddressUpdateController.java
public class ClientAddressUpdateController implements RequestHandler<APIGatewayProxyRequestEvent, APIGatewayProxyResponseEvent> {

    private final SfnClient sfnClient;
    private final boolean isLocalMode;

    public ClientAddressUpdateController() {
        this.isLocalMode = "true".equals(System.getenv("LOCAL_MODE"));

        if (isLocalMode) {
            this.sfnClient = null; // Mode local : pas besoin de Step Functions
            System.out.println("🧪 Running in LOCAL MODE");
        } else {
            this.sfnClient = SfnClient.builder().build();
        }
    }

    @Override
    public APIGatewayProxyResponseEvent handleRequest(APIGatewayProxyRequestEvent request, Context context) {
        // ... validation, enrichissement ...

        if (isLocalMode) {
            // Mode local : simuler Step Functions
            String executionArn = "arn:aws:states:local:123:execution:mock-" + System.currentTimeMillis();
            log.info("🧪 LOCAL MODE: Simulating Step Functions execution: {}", executionArn);

            return buildSuccessResponse(202, Map.of(
                "message", "Address update request accepted (LOCAL MODE)",
                "executionArn", executionArn,
                "mode", "LOCAL"
            ));
        } else {
            // Mode AWS réel
            StartExecutionResponse response = sfnClient.startExecution(...);
            return buildSuccessResponse(202, Map.of(
                "message", "Address update request accepted",
                "executionArn", response.executionArn()
            ));
        }
    }
}
```

#### 3. Build les JARs

```bash
cd /Users/fabricefoko/Downloads/mcp-local

# Build tous les JARs
mvn clean package

# Vérifier que les JARs existent
ls -lh target/*.jar
```

#### 4. Démarrer SAM local

```bash
# Démarrer l'API Gateway simulée
sam local start-api --template template.yaml

# Output :
# Mounting AddressValidator at http://127.0.0.1:3000/validate/address [POST]
# Mounting ClientAddressUpdateController at http://127.0.0.1:3000/api/clients/{clientId}/address [PUT]
# You can now browse to the above endpoints to invoke your functions.
```

#### 5. Tester avec curl/Postman

**Terminal 2 :**

```bash
# Test du Controller
curl -X PUT http://localhost:3000/api/clients/123456789/address \
  -H "Content-Type: application/json" \
  -d '{
    "street": "1500 rue Peel",
    "city": "Montreal",
    "province": "QC",
    "postalCode": "H3A1S9",
    "country": "CA"
  }'

# Réponse attendue :
# {
#   "message": "Address update request accepted (LOCAL MODE)",
#   "executionArn": "arn:aws:states:local:123:execution:mock-1726315800000",
#   "mode": "LOCAL"
# }

# Test du Validator
curl -X POST http://localhost:3000/validate/address \
  -H "Content-Type: application/json" \
  -d '{
    "clientId": "123456789",
    "address": {
      "street": "1500 rue Peel",
      "city": "Montreal",
      "province": "QC",
      "postalCode": "H3A1S9",
      "country": "CA"
    }
  }'

# Réponse attendue :
# {
#   "isValid": true,
#   "errors": [],
#   "normalizedAddress": {
#     "street": "1500 RUE PEEL",
#     "city": "MONTREAL",
#     "province": "QC",
#     "postalCode": "H3A 1S9",
#     "country": "CA"
#   }
# }
```

---

### Avantages

- ✅ **Simule API Gateway** (routes HTTP réelles)
- ✅ **Simule Lambda** (invocation locale)
- ✅ **Test complet** du controller et validation
- ✅ **Pas de coût AWS**
- ✅ **Itération rapide**

### Inconvénients

- ❌ Ne simule pas Step Functions (voir Option 2B ci-dessous)
- ❌ Ne teste pas DynamoDB réel
- ❌ Ne teste pas IAM permissions
- ⚠️ Nécessite AWS SAM CLI installé

---

## Option 2B : Test avec Step Functions Local (Optionnel - Test workflow complet)

### 🎯 Objectif

Si vous voulez tester **API Gateway + Lambda + Step Functions** localement (workflow complet), combinez SAM CLI avec **Step Functions Local**.

### Prérequis

```bash
# Docker doit être installé et démarré
docker --version
# Docker version 20.10.x ou supérieur
```

### Étapes

#### 1. Démarrer Step Functions Local

**Terminal 1 - Démarrer Step Functions Local :**

```bash
# Démarrer Step Functions Local sur port 8083
docker run -p 8083:8083 \
  --env-file stepfunctions-local.env \
  amazon/aws-stepfunctions-local:latest
```

**Créer `stepfunctions-local.env`** :
```bash
# stepfunctions-local.env
LAMBDA_ENDPOINT=http://host.docker.internal:3001
AWS_REGION=ca-central-1
AWS_DEFAULT_REGION=ca-central-1
```

**Vérifier que Step Functions Local fonctionne :**
```bash
curl http://localhost:8083/
# Output : {"status":"ok"}
```

#### 2. Démarrer SAM CLI pour Lambda

**Terminal 2 - Démarrer SAM local en mode Lambda invoke :**

```bash
# Démarrer SAM local Lambda endpoint (pas start-api)
sam local start-lambda --template template.yaml --port 3001
```

**Output attendu :**
```
Starting the Local Lambda Service. You can now invoke your Lambda Functions defined in your template through the endpoint.
2026-09-24 10:00:00  * Running on http://127.0.0.1:3001/ (Press CTRL+C to quit)
```

#### 3. Créer le State Machine dans Step Functions Local

**Terminal 3 - Créer le state machine :**

```bash
# Créer le state machine avec la définition
aws stepfunctions create-state-machine \
  --endpoint-url http://localhost:8083 \
  --name client-address-update-local \
  --definition file://state-machine.json \
  --role-arn arn:aws:iam::123456789:role/DummyRole
```

**Créer `state-machine.json`** (copier depuis `mcp-infrastructure/modules/step-functions/state-machines/client-address-update.json.tpl` et remplacer les variables) :

```json
{
  "Comment": "Client Address Update Workflow - Local Testing",
  "StartAt": "ValidateAddress",
  "States": {
    "ValidateAddress": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:ca-central-1:123456789:function:address-validator",
      "ResultPath": "$.validationResult",
      "Next": "CheckValidation",
      "Catch": [{
        "ErrorEquals": ["States.ALL"],
        "ResultPath": "$.error",
        "Next": "HandleError"
      }]
    },
    "CheckValidation": {
      "Type": "Choice",
      "Choices": [{
        "Variable": "$.validationResult.isValid",
        "BooleanEquals": true,
        "Next": "CallMDMAE"
      }],
      "Default": "HumanReview"
    },
    "CallMDMAE": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:ca-central-1:123456789:function:address-mdmae-client",
      "ResultPath": "$.mdmaeResult",
      "Next": "Success"
    },
    "HumanReview": {
      "Type": "Pass",
      "Result": {"status": "NEEDS_REVIEW"},
      "End": true
    },
    "HandleError": {
      "Type": "Pass",
      "Result": {"status": "FAILED"},
      "End": true
    },
    "Success": {
      "Type": "Succeed"
    }
  }
}
```

#### 4. Tester le workflow complet

**Exécuter le state machine :**

```bash
# Démarrer une exécution
aws stepfunctions start-execution \
  --endpoint-url http://localhost:8083 \
  --state-machine-arn arn:aws:states:ca-central-1:123456789:stateMachine:client-address-update-local \
  --name test-execution-$(date +%s) \
  --input '{
    "clientId": "123456789",
    "address": {
      "street": "1500 rue Peel",
      "city": "Montreal",
      "province": "QC",
      "postalCode": "H3A1S9",
      "country": "CA"
    }
  }'
```

**Vérifier l'exécution :**

```bash
# Lister les exécutions
aws stepfunctions list-executions \
  --endpoint-url http://localhost:8083 \
  --state-machine-arn arn:aws:states:ca-central-1:123456789:stateMachine:client-address-update-local

# Obtenir les détails d'une exécution
aws stepfunctions describe-execution \
  --endpoint-url http://localhost:8083 \
  --execution-arn <execution-arn-from-start-execution>

# Obtenir l'historique de l'exécution
aws stepfunctions get-execution-history \
  --endpoint-url http://localhost:8083 \
  --execution-arn <execution-arn>
```

**Logs attendus dans les 3 terminaux :**

**Terminal 1 (Step Functions Local) :**
```
2026-09-24 10:05:00 INFO  Execution started: arn:aws:states:ca-central-1:123456789:execution:client-address-update-local:test-execution-1234567890
2026-09-24 10:05:00 INFO  State entered: ValidateAddress
2026-09-24 10:05:01 INFO  Invoking Lambda: arn:aws:lambda:ca-central-1:123456789:function:address-validator
```

**Terminal 2 (SAM Lambda) :**
```
2026-09-24 10:05:01 Invoking com.bnc.mcp.handlers.AddressValidatorHandler::handleRequest (java17)
2026-09-24 10:05:02 START RequestId: 12345-67890
2026-09-24 10:05:02 Validating address for country: CA
2026-09-24 10:05:02 Validation result: isValid=true
2026-09-24 10:05:02 END RequestId: 12345-67890
```

---

### Avantages Option 2B

- ✅ **Workflow complet** testé localement
- ✅ **Step Functions** simulé (transitions, Choice states, Catch)
- ✅ **Lambda** invoquées localement via SAM
- ✅ **Pas de coût AWS**
- ✅ **Debugging** facile (breakpoints dans Lambda)

### Inconvénients Option 2B

- ❌ **Complexe** à configurer (3 terminaux)
- ❌ Ne teste pas DynamoDB réel (besoin de mock)
- ❌ Ne teste pas API Gateway (uniquement Step Functions)
- ❌ **Lent** (Step Functions Local + SAM)
- ⚠️ Nécessite Docker + SAM CLI

---

### Quand utiliser Option 2B ?

Utilisez **Option 2B** (Step Functions Local) uniquement si :
- ✅ Vous voulez tester la **logique du workflow** (transitions Choice, Parallel, Catch)
- ✅ Vous voulez déboguer des **erreurs de séquence** Step Functions
- ✅ Vous avez un workflow **complexe** avec conditions multiples

**Pour la majorité des cas**, **Option 2 (SAM CLI seul)** suffit pour tester les Lambdas individuelles.

---

### Comparaison : SAM CLI vs Step Functions Local

| Outil | Simule | Image Docker | Port | Commande |
|-------|--------|--------------|------|----------|
| **AWS SAM CLI** | API Gateway + Lambda | Runtime-specific (java17, python3.9, etc.) | 3000 (API), 3001 (Lambda) | `sam local start-api` |
| **Step Functions Local** | Step Functions workflows | `amazon/aws-stepfunctions-local:latest` | 8083 | `docker run -p 8083:8083 amazon/aws-stepfunctions-local` |

**Les deux peuvent être combinés** pour tester le workflow complet localement.

---

## Option 3 : Déploiement Terraform local (Test sur AWS réel)

### 🎯 Objectif

Déployer sur **AWS réel** (environnement DEV) **avant** de créer une PR, pour tester le workflow complet.

### ⚠️ ATTENTION

Cette approche déploie sur AWS réel. Utilisez-la uniquement si :
- Vous avez accès AWS avec credentials configurés
- Vous voulez tester sur AWS avant la PR
- Vous acceptez les coûts AWS (minimes pour tests)

---

### Prérequis

```bash
# Installer Terraform
brew install terraform

# Configurer AWS credentials
aws configure
# AWS Access Key ID: ...
# AWS Secret Access Key: ...
# Default region: ca-central-1

# Vérifier
aws sts get-caller-identity
```

---

### Étapes

#### 1. Build les JARs localement

```bash
cd /Users/fabricefoko/Downloads/mcp-local

# Build tous les JARs
mvn clean package

# Vérifier
ls -lh target/*.jar
```

#### 2. Copier les JARs vers un bucket S3 temporaire

**Option A : Créer un bucket S3 de test personnel**

```bash
# Créer un bucket S3 personnel pour tests
aws s3 mb s3://bnc-mcp-lambda-artifacts-test-$(whoami)

# Copier les JARs
aws s3 sync target/ s3://bnc-mcp-lambda-artifacts-test-$(whoami)/ \
  --exclude "*" \
  --include "*.jar"

# Vérifier
aws s3 ls s3://bnc-mcp-lambda-artifacts-test-$(whoami)/
```

**Option B : Utiliser le bucket existant (avec tag test)**

```bash
# Copier les JARs dans un dossier "test"
aws s3 sync target/ s3://bnc-mcp-lambda-artifacts/test-$(whoami)/ \
  --exclude "*" \
  --include "*.jar"
```

#### 3. Modifier Terraform pour pointer vers vos JARs de test

**Option : Créer un environnement "test" temporaire**

```bash
cd /Users/fabricefoko/Documents/mcp-infrastructure

# Copier l'environnement dev vers test
cp -r environments/dev environments/test

# Modifier environments/test/terraform.tfvars
# (ou créer le fichier s'il n'existe pas)
```

**Créer `environments/test/terraform.tfvars`** :

```hcl
environment  = "test"
project_name = "mcp"

# Utiliser votre bucket de test
lambda_artifacts_bucket = "bnc-mcp-lambda-artifacts-test-YOUR_USERNAME"
lambda_artifacts_prefix = ""

# Autres variables (secrets, etc.)
# Copier depuis environments/dev/terraform.tfvars
```

**Modifier `environments/test/main.tf`** pour utiliser les JARs de test :

```hcl
module "lambda" {
  source = "../../modules/lambda"

  environment  = var.environment
  project_name = var.project_name

  # Pointer vers vos JARs de test
  lambda_artifacts_bucket = var.lambda_artifacts_bucket

  functions = {
    address-validator = {
      handler     = "com.bnc.mcp.handlers.AddressValidatorHandler::handleRequest"
      runtime     = "java17"
      memory_size = 512
      timeout     = 30

      # S3 pour le code (bucket de test)
      s3_bucket = var.lambda_artifacts_bucket
      s3_key    = "address-validator-1.0.0.jar"
    }
    # ... autres Lambdas
  }
}
```

#### 4. Déployer avec Terraform

```bash
cd /Users/fabricefoko/Documents/mcp-infrastructure/environments/test

# Initialiser Terraform
terraform init

# Vérifier ce qui sera créé
terraform plan

# Output :
# Plan: 15 to add, 0 to change, 0 to destroy.
```

**Examiner le plan attentivement :**

```
Terraform will perform the following actions:

  # module.lambda.aws_lambda_function.address_validator will be created
  + resource "aws_lambda_function" "address_validator" {
      + function_name = "test-mcp-address-validator"
      + handler       = "com.bnc.mcp.handlers.AddressValidatorHandler::handleRequest"
      + runtime       = "java17"
      + s3_bucket     = "bnc-mcp-lambda-artifacts-test-YOUR_USERNAME"
      + s3_key        = "address-validator-1.0.0.jar"
    }
```

**Si le plan semble correct, appliquer :**

```bash
# Déployer
terraform apply

# Terraform demandera confirmation
# Do you want to perform these actions? yes
```

**Attendre la fin du déploiement** (5-10 minutes)

```
Apply complete! Resources: 15 added, 0 changed, 0 destroyed.

Outputs:
api_gateway_url = "https://xyz123test.execute-api.ca-central-1.amazonaws.com/test"
state_machine_arn = "arn:aws:states:ca-central-1:123:stateMachine:test-client-address-update"
```

#### 5. Tester sur AWS réel

```bash
# Récupérer l'URL de l'API Gateway
API_URL=$(terraform output -raw api_gateway_url)

# Tester l'endpoint
curl -X PUT "${API_URL}/api/clients/123456789/address" \
  -H "Content-Type: application/json" \
  -H "Authorization: AWS4-HMAC-SHA256 ..." \
  -d '{
    "street": "1500 rue Peel",
    "city": "Montreal",
    "province": "QC",
    "postalCode": "H3A1S9",
    "country": "CA"
  }'
```

**Vérifier l'exécution dans AWS Console :**

1. Step Functions → State machines → `test-client-address-update`
2. Voir les exécutions
3. Vérifier les logs CloudWatch

#### 6. Détruire l'environnement de test (après tests)

```bash
# IMPORTANT : Détruire les ressources pour éviter les coûts
cd /Users/fabricefoko/Documents/mcp-infrastructure/environments/test

terraform destroy

# Confirmer : yes
```

**Nettoyer le bucket S3 :**

```bash
# Supprimer les JARs de test
aws s3 rm s3://bnc-mcp-lambda-artifacts-test-$(whoami)/ --recursive

# Supprimer le bucket
aws s3 rb s3://bnc-mcp-lambda-artifacts-test-$(whoami)
```

---

### Avantages

- ✅ **Test sur AWS réel** (Step Functions, DynamoDB, API Gateway)
- ✅ **Test du workflow complet**
- ✅ **Test des permissions IAM**
- ✅ **Environnement isolé** (ne touche pas DEV)

### Inconvénients

- ❌ **Lent** (10-15 min pour deploy + destroy)
- ❌ **Coût AWS** (minime mais existant)
- ❌ **Risque d'oublier de détruire** → coûts
- ❌ **Complexe** (Terraform, S3, IAM)

---

## Option 4 : Spring Boot wrapper (Développement rapide)

### 🎯 Objectif

Wrapper les Lambdas dans une application **Spring Boot** pour tester rapidement avec **HTTP REST** classique.

### Étapes

#### 1. Ajouter dépendances Spring Boot

**Modifier `pom.xml`** :

```xml
<dependencies>
    <!-- Dépendances Lambda existantes -->
    <!-- ... -->

    <!-- Spring Boot (pour tests locaux uniquement) -->
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-web</artifactId>
        <version>3.1.5</version>
        <scope>test</scope>
    </dependency>
</dependencies>
```

#### 2. Créer un wrapper Spring Boot

**Créer `src/test/java/com/bnc/mcp/local/LocalTestServer.java`** :

```java
package com.bnc.mcp.local;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.events.APIGatewayProxyRequestEvent;
import com.amazonaws.services.lambda.runtime.events.APIGatewayProxyResponseEvent;
import com.bnc.mcp.controllers.ClientAddressUpdateController;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@SpringBootApplication
@RestController
@RequestMapping("/api/clients")
public class LocalTestServer {

    private final ClientAddressUpdateController controller = new ClientAddressUpdateController();
    private final ObjectMapper objectMapper = new ObjectMapper();

    public static void main(String[] args) {
        System.out.println("🚀 Starting Local Test Server...");
        System.out.println("📍 Server will be available at http://localhost:8080");
        SpringApplication.run(LocalTestServer.class, args);
    }

    @PutMapping("/{clientId}/address")
    public ResponseEntity<Map<String, Object>> updateAddress(
            @PathVariable String clientId,
            @RequestBody Map<String, Object> address) throws Exception {

        System.out.println("🔵 Request received: PUT /api/clients/" + clientId + "/address");

        // Convertir HTTP request vers API Gateway event
        APIGatewayProxyRequestEvent event = new APIGatewayProxyRequestEvent();
        event.setPathParameters(Map.of("clientId", clientId));
        event.setBody(objectMapper.writeValueAsString(address));

        // Mock Context
        Context mockContext = new Context() {
            @Override
            public String getRequestId() { return "local-" + System.currentTimeMillis(); }
            @Override
            public String getFunctionName() { return "local-test"; }
            // ... autres méthodes
        };

        // Invoquer le Lambda Controller
        APIGatewayProxyResponseEvent response = controller.handleRequest(event, mockContext);

        // Convertir API Gateway response vers HTTP response
        Map<String, Object> body = objectMapper.readValue(response.getBody(), Map.class);

        System.out.println("✅ Response: " + response.getStatusCode());

        return ResponseEntity
                .status(response.getStatusCode())
                .body(body);
    }
}
```

#### 3. Démarrer le serveur local

```bash
cd /Users/fabricefoko/Downloads/mcp-local

# Démarrer Spring Boot
mvn spring-boot:run -Dspring-boot.run.mainClass=com.bnc.mcp.local.LocalTestServer

# Output :
# 🚀 Starting Local Test Server...
# 📍 Server will be available at http://localhost:8080
# Tomcat started on port(s): 8080 (http)
```

#### 4. Tester avec Postman/curl

```bash
# Test avec curl
curl -X PUT http://localhost:8080/api/clients/123456789/address \
  -H "Content-Type: application/json" \
  -d '{
    "street": "1500 rue Peel",
    "city": "Montreal",
    "province": "QC",
    "postalCode": "H3A1S9",
    "country": "CA"
  }'

# Réponse :
# {
#   "message": "Address update request accepted (LOCAL MODE)",
#   "executionArn": "arn:aws:states:local:123:execution:mock-1726315800000",
#   "clientId": "123456789",
#   "status": "PROCESSING"
# }
```

**Ou avec Postman :**

```
PUT http://localhost:8080/api/clients/123456789/address
Headers:
  Content-Type: application/json
Body:
{
  "street": "1500 rue Peel",
  "city": "Montreal",
  "province": "QC",
  "postalCode": "H3A1S9",
  "country": "CA"
}
```

---

### Avantages

- ✅ **Très rapide** (démarrage < 10 secondes)
- ✅ **HTTP REST classique** (Postman, curl, Swagger)
- ✅ **Hot reload** (modifier code → redémarrer → tester)
- ✅ **Debugging facile** (IDE breakpoints)
- ✅ **Familier** (Spring Boot connu des devs Java)

### Inconvénients

- ❌ Ne teste pas Step Functions
- ❌ Ne teste pas API Gateway réel
- ❌ Ne teste pas IAM
- ⚠️ Nécessite Spring Boot (dépendance supplémentaire)

---

## Workflow recommandé BNC

### 🎯 Approche en 4 phases

```
Phase 1 : DÉVELOPPEMENT LOCAL (Spring Boot / Tests unitaires)
  ↓
Phase 2 : VALIDATION LOCALE (AWS SAM CLI)
  ↓
Phase 3 : TEST AWS OPTIONNEL (Terraform local sur environnement test)
  ↓
Phase 4 : DÉPLOIEMENT AUTOMATIQUE (GitHub Actions → DEV)
```

---

### Détails de chaque phase

#### Phase 1 : Développement local (1-2 jours)

**Objectif :** Coder et valider la logique métier

```bash
# 1. Développer le code
# Créer Controllers, Handlers, Validators, Services

# 2. Tests unitaires
mvn test

# 3. Spring Boot wrapper (optionnel)
mvn spring-boot:run -Dspring-boot.run.mainClass=com.bnc.mcp.local.LocalTestServer

# Test avec Postman
PUT http://localhost:8080/api/clients/123/address
```

**Critères de succès :**
- ✅ Tous les tests unitaires passent
- ✅ Logique métier validée
- ✅ Code coverage > 80%

---

#### Phase 2 : Validation locale (30 min - 1 heure)

**Objectif :** Valider l'intégration API Gateway + Lambda

```bash
# 1. Build JARs
mvn clean package

# 2. Démarrer SAM local
sam local start-api --template template.yaml

# 3. Tester avec curl
curl -X PUT http://localhost:3000/api/clients/123/address \
  -H "Content-Type: application/json" \
  -d '{"street":"123 Main","city":"Montreal","province":"QC","postalCode":"H1A 1A1","country":"CA"}'
```

**Critères de succès :**
- ✅ API Gateway simulé fonctionne
- ✅ Lambda invoquée correctement
- ✅ Validation HTTP OK
- ✅ Format de réponse correct

---

#### Phase 3 : Test AWS optionnel (1-2 heures)

**Objectif :** Tester sur AWS réel AVANT la PR (optionnel)

**⚠️ Seulement si :**
- Feature complexe (Step Functions, DynamoDB, IAM)
- Besoin de valider permissions
- Besoin de tester workflow complet

```bash
# 1. Build JARs
mvn clean package

# 2. Upload JARs vers S3 de test
aws s3 sync target/ s3://bnc-mcp-lambda-artifacts-test-$(whoami)/ \
  --exclude "*" --include "*.jar"

# 3. Déployer avec Terraform
cd /Users/fabricefoko/Documents/mcp-infrastructure/environments/test
terraform init
terraform plan
terraform apply

# 4. Tester sur AWS
curl -X PUT "https://xyz.execute-api.ca-central-1.amazonaws.com/test/api/clients/123/address" \
  -H "Content-Type: application/json" \
  -d '{"street":"123 Main","city":"Montreal",...}'

# 5. Vérifier AWS Console
# Step Functions → Executions
# CloudWatch Logs

# 6. DÉTRUIRE après tests
terraform destroy
```

**Critères de succès :**
- ✅ Workflow Step Functions exécuté
- ✅ DynamoDB écrit correctement
- ✅ Logs CloudWatch corrects
- ✅ Pas d'erreur IAM

---

#### Phase 4 : Déploiement automatique (10 min)

**Objectif :** Déployer sur DEV via GitHub Actions

```bash
# 1. Commit et push
git add .
git commit -m "feat: implement client address update workflow"
git push origin feature/client-address-update

# 2. Créer Pull Request
# GitHub → mcp-local → New Pull Request

# 3. Code Review
# Attendre approbation

# 4. Merger
# Merge Pull Request

# 5. Déployer via GitHub Actions
# GitHub → mcp-local → Actions → Deploy Lambda Code
# → Run workflow
#   Branch: main
#   Environment: dev
```

**GitHub Actions fait automatiquement :**
- ✅ Build JARs (`mvn clean package`)
- ✅ Upload S3 (`s3://bnc-mcp-lambda-artifacts/dev/`)
- ✅ Update Lambdas (`aws lambda update-function-code`)
- ✅ Vérification déploiements
- ✅ Résumé dans GitHub Summary

**Critères de succès :**
- ✅ GitHub Actions workflow vert
- ✅ JARs uploadés sur S3
- ✅ Lambdas mises à jour (CodeSha256 changed)
- ✅ Tests smoke passent

---

### Tableau récapitulatif

| Phase | Durée | Objectif | Outils | Obligatoire ? |
|-------|-------|----------|--------|---------------|
| **1. Développement local** | 1-2 jours | Coder + tests unitaires | Maven, JUnit, Spring Boot | ✅ OUI |
| **2. Validation locale** | 30 min | Valider API Gateway + Lambda | AWS SAM CLI | ✅ OUI (recommandé) |
| **3. Test AWS** | 1-2 heures | Tester workflow complet | Terraform, S3, AWS | ⚠️ Optionnel (features complexes) |
| **4. Déploiement auto** | 10 min | Déployer sur DEV | GitHub Actions | ✅ OUI |

---

## Résumé : Ne PAS copier les JARs manuellement

### ❌ Ancienne approche (manuelle)

```bash
# ❌ NE PLUS FAIRE
mvn clean package
cp target/*.jar /Users/fabricefoko/Documents/mcp-infrastructure/modules/lambda/functions/
cd mcp-infrastructure
terraform apply
```

**Problèmes :**
- ❌ Processus manuel (erreurs)
- ❌ Pas de traçabilité Git
- ❌ Pas de CI/CD
- ❌ Difficile de rollback
- ❌ Pas de review

---

### ✅ Nouvelle approche (automatique)

```bash
# ✅ FAIRE maintenant
# 1. Développer localement
mvn test
sam local start-api  # Tests locaux

# 2. Commit + Push
git push

# 3. GitHub Actions déploie automatiquement
# → Build JARs
# → Upload S3
# → Update Lambdas
# → Vérifications
```

**Avantages :**
- ✅ **Automatique** (pas d'erreur manuelle)
- ✅ **Traçabilité** (Git + GitHub Actions logs)
- ✅ **CI/CD** (intégré dans workflow)
- ✅ **Rollback facile** (redéployer commit précédent)
- ✅ **Code review** (PR obligatoire)

---

## Checklist de test local

### Avant de créer une PR

- [ ] Tests unitaires passent (`mvn test`)
- [ ] Build réussi (`mvn clean package`)
- [ ] JARs créés dans `target/`
- [ ] Tests locaux avec SAM CLI (`sam local start-api`)
- [ ] Test endpoint avec curl/Postman
- [ ] Validation HTTP OK
- [ ] Format de réponse correct
- [ ] Logs structurés (JSON)
- [ ] (Optionnel) Test sur AWS avec Terraform
- [ ] Code committé et pushé
- [ ] PR créée avec description claire

### Après le déploiement GitHub Actions

- [ ] Workflow GitHub Actions vert
- [ ] JARs uploadés sur S3 (`aws s3 ls s3://bnc-mcp-lambda-artifacts/dev/`)
- [ ] Lambdas mises à jour (vérifier CodeSha256)
- [ ] Test endpoint AWS réel
- [ ] Vérifier exécution Step Functions
- [ ] Vérifier logs CloudWatch
- [ ] Vérifier données DynamoDB
- [ ] Métriques CloudWatch (invocations, erreurs, latence)

---

**Dernière mise à jour** : 2026-09-24
**Auteur** : Claude Code