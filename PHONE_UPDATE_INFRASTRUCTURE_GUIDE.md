c# Guide d'Infrastructure : Workflow de Mise à Jour de Téléphone

## 📋 Vue d'ensemble

Ce guide détaille **pas à pas** la création de toutes les ressources AWS nécessaires pour le workflow de mise à jour de téléphone client dans le repo `mcp-infrastructure`.

**Repo concerné :** `/Users/fabricefoko/Documents/mcp-infrastructure`

---

## 📖 Description du Workflow en Langage Humain

### 🎯 Objectif
Permettre à un client de mettre à jour son numéro de téléphone avec validation, vérification de fraude, envoi d'OTP pour confirmation, et synchronisation dans tous les systèmes de la BNC.

### 📋 Étapes du Workflow (en français simple)

#### **Étape 1 : Réception de la requête**
- Le client envoie une requête HTTP `PUT /api/clients/{clientId}/phone` avec son nouveau numéro de téléphone
- API Gateway reçoit la requête et invoque le Lambda Controller
- Retour immédiat au client : `202 Accepted` avec l'ARN d'exécution Step Functions

#### **Étape 2 : Validation initiale (Lambda Controller)**
Le Controller effectue les validations de base :
- Format HTTP correct (JSON valide, headers requis)
- Client authentifié (token JWT valide)
- Données requises présentes (`phoneNumber`, `country`)
- Enrichit la requête avec metadata (timestamp, requestId, user)
- Démarre le workflow Step Functions
- Retourne HTTP 202 Accepted avec l'ARN d'exécution

**Si échec :** Retourne HTTP 400/401/500 immédiatement

#### **Étape 3 : Lire le profil client actuel (Lambda)**
- Lit le profil complet du client dans DynamoDB
- Récupère le numéro de téléphone actuel
- Vérifie que le client existe et est actif
- **Si client n'existe pas :** → Erreur `ClientNotFound` → Fin du workflow avec échec

#### **Étape 4 : Validation du format du téléphone (Lambda)**
Vérifie que le numéro est valide selon le pays :
- **Canada :** `+1 (XXX) XXX-XXXX` (10 chiffres après +1)
- **USA :** `+1 (XXX) XXX-XXXX`
- **France :** `+33 X XX XX XX XX`
- Normalise le format (enlève espaces, parenthèses, tirets)
- Vérifie que ce n'est pas un numéro jetable (VoIP suspect, numéro virtuel)
- Convertit en format E.164 : `+15141234567`

**Si format invalide :** → Notification au client → Fin du workflow avec échec

#### **Étape 5 : Vérifier l'historique de changements (Lambda)**
- Lit l'historique des numéros de téléphone du client (table `PhoneNumberHistory`)
- Compte combien de changements dans les **90 derniers jours**
- Calcule un **score de suspicion** (0.0 à 1.0) :
  - **0 changement en 1 an** = score 0.1 (safe)
  - **1 changement** = score 0.3
  - **2 changements** = score 0.5
  - **3+ changements en 90 jours** = score 0.9 (suspect)
- Détecte des **patterns suspects** :
  - Changement juste après un virement important
  - Numéro similaire à un numéro frauduleux connu
  - Changement depuis un pays différent du profil client

#### **Étape 6 : Évaluer le score de suspicion (Choice)**
**Logique de décision :**

- **SI score > 0.8** (très suspect) :
  - → Aller à l'étape "Approbation manuelle"

- **SI score entre 0.5 et 0.8 ET plus de 3 changements récents** :
  - → Aller à l'étape "Approbation manuelle"

- **SINON** (score < 0.5 ou pas suspect) :
  - → Continuer automatiquement vers envoi OTP

#### **Étape 7 : Approbation manuelle (si suspect)**
**Seulement si le changement est jugé suspect**

1. **Envoie un message SQS** à la queue `fraud-review-queue`
   - Numéro actuel du client
   - Nouveau numéro demandé
   - Score de suspicion + raisons
   - Historique des changements
   - Task Token (pour que le workflow reprenne après approbation)

2. **Attend jusqu'à 24 heures** qu'un agent de fraude examine et décide
   - L'agent voit une interface web avec tous les détails
   - L'agent peut voir l'historique complet des transactions
   - L'agent clique **"Approuver"** ou **"Rejeter"**

3. **Résultats possibles :**
   - **SI approbation timeout (24h dépassées) :** → Notification "Approbation timeout" → Fin (échec)
   - **SI rejeté par l'agent :** → Notification "Changement rejeté" → Fin (échec)
   - **SI approuvé par l'agent :** → Continuer vers envoi OTP

#### **Étape 8 : Envoyer SMS de confirmation OTP (Lambda)**
1. Génère un **code OTP à 6 chiffres** aléatoire (ex: `387542`)
2. Envoie SMS au **nouveau numéro** via AWS SNS
   - Message : `"Votre code de vérification BNC est: 387542. Ce code expire dans 5 minutes."`
3. Stocke le code OTP dans DynamoDB avec :
   - `clientId`, `otpId`, `code`, `phoneNumber`
   - `createdAt`, `expiresAt` (5 minutes)
   - `status = "PENDING"`
4. **Retry automatique** si l'envoi SMS échoue (max 2 tentatives)

**Si tous les envois échouent :** → Erreur → Notification au client

#### **Étape 9 : Attendre la validation OTP (Wait + Polling)**
**Mécanisme choisi pour BNC :** Attente passive (60 secondes)

1. **Le workflow attend 60 secondes**
2. **Pendant ce temps, le client peut :**
   - Recevoir le SMS (généralement < 10 secondes)
   - Appeler l'endpoint API : `POST /api/clients/{clientId}/phone/validate-otp`
   - L'endpoint vérifie le code et met à jour DynamoDB (`status = "VALIDATED"`)
3. **Après 60 secondes, le workflow vérifie** :
   - Lambda `CheckOTPStatus` lit DynamoDB
   - Vérifie si `status == "VALIDATED"`

**Résultats possibles :**
- **SI OTP validé :** → Continuer vers mise à jour MDMAE
- **SI OTP non validé après 60s :** → Notification "OTP timeout" → Fin (échec)
- **SI OTP expiré (> 5 min) :** → Notification "OTP expiré" → Fin (échec)

#### **Étape 10 : Mettre à jour MDMAE (Master Data Management) (Lambda)**
**Étape CRITIQUE - système central**

1. Appelle l'API REST de MDMAE :
   - `PUT https://mdmae-api.bnc.ca/clients/{clientId}/phone`
   - Body : `{"phoneNumber": "+15149876543", "country": "CA"}`
   - Headers : `Idempotency-Key` (pour éviter doublons lors retry)
2. MDMAE met à jour le numéro dans **tous les systèmes centraux**
3. **Retry automatique** avec exponential backoff :
   - Niveau HTTP : 3 tentatives (1s → 2s → 4s)
   - Niveau Step Functions : 3 tentatives (5s → 10s → 20s)
   - Total max : jusqu'à 9 tentatives

**Si erreur permanente :** → Erreur critique → Workflow échoue

#### **Étape 11 : Mises à jour parallèles dans 3 systèmes (Parallel)**
**Les 3 branches s'exécutent en PARALLÈLE (gain de temps)**

**Branche 1 : Mettre à jour FCC (Lambda)**
- FCC = système mainframe IBM pour conformité
- Envoie message via **IBM MQ**
- Format : XML SOAP
- **Non bloquant :** si ça échoue, on log l'erreur mais on continue
- Retry : 3 tentatives

**Branche 2 : Mettre à jour CRM (Lambda)**
- CRM = Salesforce pour service client
- Appelle API Salesforce REST
- Met à jour le contact avec le nouveau numéro
- **Non bloquant :** si ça échoue, on log l'erreur mais on continue
- Retry : 3 tentatives

**Branche 3 : Publier événement Kafka (Lambda)**
- Topic MSK Kafka : `client.phone.updated`
- Payload :
  ```json
  {
    "eventType": "PHONE_UPDATE",
    "clientId": "123456789",
    "oldPhone": "+15141234567",
    "newPhone": "+15149876543",
    "timestamp": "2026-09-25T14:30:00Z",
    "approvalRequired": false,
    "approvedBy": null
  }
  ```
- Autres systèmes BNC abonnés au topic reçoivent l'événement
- **Non bloquant :** si ça échoue, on log l'erreur mais on continue

⏱ **Durée totale des 3 branches :** ~3-5 secondes (exécution parallèle)

#### **Étape 12 : Sauvegarder dans l'historique (DynamoDB direct)**
**Écriture directe depuis Step Functions (pas de Lambda)**

- Table : `PhoneNumberHistory`
- Données sauvegardées :
  - `clientId`, `timestamp`
  - `oldPhone`, `newPhone`
  - `changeReason = "CLIENT_REQUEST"`
  - `approvedBy` (si approbation manuelle)
  - `suspicionScore`
  - `otpValidated = true`
  - `mdmaeTransactionId`

#### **Étape 13 : Mettre à jour le profil client (DynamoDB direct)**
**Écriture directe depuis Step Functions**

- Table : `ClientProfiles`
- Met à jour :
  - `phoneNumber = "+15149876543"`
  - `lastPhoneUpdate = 2026-09-25T14:30:00Z`
  - `phoneUpdateCount += 1`

#### **Étape 14 : Envoyer email de confirmation au client (Lambda)**
Envoie email via **AWS SES** :

**Contenu de l'email :**
```
Objet: Confirmation de mise à jour de votre numéro de téléphone

Bonjour,

Votre numéro de téléphone a été mis à jour avec succès.

Ancien numéro : +1 (514) ***-**67  (masqué)
Nouveau numéro : +1 (514) ***-**43  (masqué)
Date et heure : 25 septembre 2026 à 14:30
Approuvé par : Système automatique

Si ce n'est pas vous qui avez effectué ce changement, veuillez cliquer ici :
[Signaler une activité suspecte]

Merci,
Équipe BNC
```

**Retry :** 3 tentatives si échec (non bloquant)

#### **Étape 15 : Workflow terminé avec succès**
État final : `SUCCEEDED`

Résultat disponible via l'ARN d'exécution :
```json
{
  "status": "SUCCESS",
  "clientId": "CLIENT-12345",
  "oldPhone": "+15141234567",
  "newPhone": "+15149876543",
  "executionId": "arn:aws:states:ca-central-1:123456:execution:...",
  "processingTime": "8.3s",
  "otpValidated": true,
  "approvalRequired": false,
  "mdmaeTransactionId": "txn-abc-123"
}
```

### ⏱ Durée Estimée du Workflow

| Scénario | Durée |
|----------|-------|
| **Cas normal (pas suspect)** | 60-90 secondes |
| **Avec approbation manuelle** | 1 minute à 24 heures |
| **OTP timeout** | 65 secondes (échec) |
| **Erreur MDMAE avec retry** | 2-3 minutes (9 tentatives max) |

### 🚨 Points de Contrôle et Échecs Possibles

| Étape | Raison d'Échec | Action |
|-------|---------------|--------|
| **Validation format** | Format téléphone invalide | Notification immédiate au client |
| **Client inexistant** | Client not found | Workflow échoue |
| **Score suspicion élevé** | > 3 changements en 90 jours | Approbation manuelle requise |
| **Approbation timeout** | Pas de réponse en 24h | Workflow échoue, notification |
| **Envoi OTP échec** | Tous les SMS échouent | Workflow échoue |
| **OTP non validé** | Client n'entre pas le code | Workflow échoue après 60s |
| **MDMAE échec permanent** | API down après 9 tentatives | Workflow échoue (critique) |
| **FCC/CRM échec** | API externe down | Workflow continue (non bloquant) |

---

## 🎯 Architecture du workflow

```
Client Request (PUT /api/clients/{clientId}/phone)
    ↓
API Gateway → Lambda Controller → Step Functions State Machine
    ↓
┌─────────────────── Step Functions Workflow ───────────────────┐
│                                                                 │
│  1. ReadClientProfile (Lambda)                                 │
│  2. ParallelValidations (2 Lambdas en parallèle)              │
│     - PhoneValidator                                           │
│     - CheckPhoneHistory                                        │
│  3. EvaluateFraudRisk (Choice)                                │
│  4. SendToFraudReview (SQS) [si suspect]                      │
│  5. WaitForHumanApproval (Wait + Lambda) [si suspect]         │
│  6. RecordPhoneHistory (DynamoDB direct)                       │
│  7. SendOTPSMS (Lambda → SNS)                                 │
│  8. WaitForOTP (Wait 60s)                                     │
│  9. CheckOTPStatus (Lambda)                                    │
│  10. UpdateMDMAE (Lambda → API MDMAE)                         │
│  11. ParallelSystemUpdates (3 Lambdas en parallèle)           │
│      - SendToFCC                                               │
│      - UpdateCRM                                               │
│      - UpdateNotificationService                               │
│  12. UpdateClientProfileSuccess (DynamoDB direct)              │
│  13. SendConfirmationEmail (Lambda → AWS SES) ⭐ NOUVEAU      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📁 Ressources créées

### 1. Step Functions State Machine
- **Fichier :** `modules/step-functions/state-machines/client-phone-update.json.tpl`
- **Type :** JSON workflow definition
- **États :** 28 états (Task, Choice, Parallel, Wait, Succeed, Fail)

### 2. DynamoDB Tables
- **Fichier :** `modules/dynamodb/phone_update_tables.tf`
- **Tables :**
  - `PhoneNumberHistory` : historique des changements
  - `OTPCodes` : codes OTP temporaires

### 3. SQS Queue
- **Fichier :** `modules/sqs/fraud_review_queue.tf`
- **Queue :** `fraud-review-queue` (+ DLQ)

### 4. Lambda Functions
- **Fichier :** `modules/lambda/phone_update_functions.tf`
- **Lambdas :** 11 fonctions Java

### 5. IAM Roles & Policies
- **Fichier :** `modules/iam/phone_update_policies.tf`
- **Roles :** Lambda execution, Step Functions execution

### 6. API Gateway Endpoint
- **Fichier :** `modules/api-gateway/phone_update_endpoint.tf`
- **Endpoint :** `PUT /api/clients/{clientId}/phone`

### 7. Swagger/OpenAPI Documentation
- **Fichier OpenAPI :** `openapi/phone-update-api.yaml`
- **Fichier Terraform :** `modules/api-gateway/swagger_documentation.tf`
- **Swagger UI :** `modules/api-gateway/swagger-ui/index.html`
- **Resources :**
  - Bucket S3 pour documentation
  - CloudFront distribution (optionnel)
  - API Gateway documentation version

---

## 🔄 Flow de création des ressources (ordre d'exécution)

### Étape 1 : DynamoDB Tables (aucune dépendance)

**Pourquoi en premier ?** Les tables DynamoDB n'ont aucune dépendance et seront référencées par d'autres ressources.

**Fichier créé :** `modules/dynamodb/phone_update_tables.tf`

```hcl
# Table PhoneNumberHistory
resource "aws_dynamodb_table" "phone_number_history" {
  name         = "${var.environment}-PhoneNumberHistory"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "clientId"
  range_key    = "timestamp"

  ttl {
    enabled        = true
    attribute_name = "expiresAt"  # Auto-suppression après 180 jours
  }
}

# Table OTPCodes
resource "aws_dynamodb_table" "otp_codes" {
  name         = "${var.environment}-OTPCodes"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "clientId"
  range_key    = "otpId"

  global_secondary_index {
    name     = "OTPIdIndex"
    hash_key = "otpId"
  }

  ttl {
    enabled        = true
    attribute_name = "expiresAt"  # Auto-suppression après 5 min
  }
}
```

**Outputs ajoutés :** `modules/dynamodb/outputs.tf`
- `phone_history_table_name`
- `phone_history_table_arn`
- `otp_codes_table_name`
- `otp_codes_table_arn`

**Commande Terraform :**
```bash
cd /Users/fabricefoko/Documents/mcp-infrastructure
terraform plan -target=module.dynamodb
terraform apply -target=module.dynamodb
```

---

### Étape 2 : SQS Queue (aucune dépendance)

**Pourquoi maintenant ?** La queue SQS est indépendante et sera utilisée par Step Functions et Lambda.

**Fichier créé :** `modules/sqs/fraud_review_queue.tf`

```hcl
resource "aws_sqs_queue" "fraud_review_queue" {
  name                       = "${var.environment}-fraud-review-queue"
  visibility_timeout_seconds = 86400  # 24 heures (timeout Step Functions)
  message_retention_seconds  = 1209600  # 14 jours

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.fraud_review_dlq.arn
    maxReceiveCount     = 3
  })
}

resource "aws_sqs_queue" "fraud_review_dlq" {
  name = "${var.environment}-fraud-review-queue-dlq"
}

# Policy pour Step Functions
resource "aws_sqs_queue_policy" "fraud_review_policy" {
  queue_url = aws_sqs_queue.fraud_review_queue.id

  policy = jsonencode({
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "states.amazonaws.com" }
      Action = ["sqs:SendMessage"]
      Resource = aws_sqs_queue.fraud_review_queue.arn
    }]
  })
}
```

**Outputs ajoutés :** `modules/sqs/outputs.tf`
- `fraud_review_queue_url`
- `fraud_review_queue_arn`

**Variables ajoutées :** `modules/sqs/variables.tf`
- `step_functions_state_machine_arn`

**Commande Terraform :**
```bash
terraform plan -target=module.sqs
terraform apply -target=module.sqs
```

---

### Étape 3 : IAM Roles & Policies (dépend de DynamoDB et SQS)

**Pourquoi maintenant ?** Les roles IAM référencent les ARNs des tables DynamoDB et SQS créées précédemment.

**Fichier créé :** `modules/iam/phone_update_policies.tf`

```hcl
# Lambda permissions
resource "aws_iam_role_policy" "lambda_phone_update_permissions" {
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Statement = [
      {
        # DynamoDB tables
        Action = ["dynamodb:*"]
        Resource = [
          var.phone_history_table_arn,
          var.otp_codes_table_arn
        ]
      },
      {
        # SQS queue
        Action = ["sqs:*"]
        Resource = var.fraud_review_queue_arn
      },
      {
        # SNS pour SMS
        Action = ["sns:Publish"]
        Resource = var.sns_topic_arn
      }
    ]
  })
}

# Step Functions permissions
resource "aws_iam_role_policy" "stepfunctions_phone_update_permissions" {
  role = aws_iam_role.stepfunctions_execution.id

  policy = jsonencode({
    Statement = [
      {
        Action = ["lambda:InvokeFunction"]
        Resource = [
          "arn:aws:lambda:*:*:function:${var.environment}-mcp-phone-*",
          "arn:aws:lambda:*:*:function:${var.environment}-mcp-read-client-profile",
          # ... autres Lambdas
        ]
      },
      {
        Action = ["dynamodb:PutItem", "dynamodb:UpdateItem"]
        Resource = [var.phone_history_table_arn]
      },
      {
        Action = ["sqs:SendMessage"]
        Resource = var.fraud_review_queue_arn
      }
    ]
  })
}
```

**Variables ajoutées :** `modules/iam/variables.tf`
- `phone_history_table_arn`
- `otp_codes_table_arn`
- `fraud_review_queue_arn`
- `sns_topic_arn`
- `phone_update_state_machine_arn`

**Commande Terraform :**
```bash
terraform plan -target=module.iam
terraform apply -target=module.iam
```

---

### Étape 4 : Lambda Functions (dépend de IAM roles)

**Pourquoi maintenant ?** Les Lambdas nécessitent les IAM roles créés à l'étape 3.

**Fichier créé :** `modules/lambda/phone_update_functions.tf`

```hcl
locals {
  phone_update_functions = {
    "phone-update-controller" = {
      handler     = "com.bnc.mcp.controllers.ClientPhoneUpdateController::handleRequest"
      memory_size = 512
      timeout     = 30
      s3_key      = "phone-update/client-phone-update-controller-1.0.0.jar"
    }
    "phone-validator" = {
      handler     = "com.bnc.mcp.handlers.PhoneValidatorHandler::handleRequest"
      memory_size = 256
      timeout     = 10
      s3_key      = "phone-update/phone-validator-1.0.0.jar"
    }
    # ... 9 autres Lambdas
  }
}

resource "aws_lambda_function" "phone_update_functions" {
  for_each = local.phone_update_functions

  function_name = "${var.environment}-mcp-${each.key}"
  role          = var.lambda_execution_role_arn

  s3_bucket = var.lambda_code_bucket
  s3_key    = each.value.s3_key

  handler     = each.value.handler
  runtime     = "java17"
  memory_size = each.value.memory_size
  timeout     = each.value.timeout

  environment {
    variables = {
      DYNAMODB_PHONE_HISTORY = var.dynamodb_phone_history_table_name
      DYNAMODB_OTP_TABLE     = var.dynamodb_otp_table_name
      SQS_FRAUD_QUEUE_URL    = var.sqs_fraud_review_queue_url
      # ... autres variables
    }
  }
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "phone_update_lambda_logs" {
  for_each          = local.phone_update_functions
  name              = "/aws/lambda/${var.environment}-mcp-${each.key}"
  retention_in_days = 7
}

# Permissions pour API Gateway
resource "aws_lambda_permission" "phone_update_api_gateway" {
  for_each = {
    for k, v in local.phone_update_functions : k => v
    if k == "phone-update-controller"
  }

  function_name = aws_lambda_function.phone_update_functions[each.key].function_name
  principal     = "apigateway.amazonaws.com"
  action        = "lambda:InvokeFunction"
}

# Permissions pour Step Functions
resource "aws_lambda_permission" "phone_update_step_functions" {
  for_each = {
    for k, v in local.phone_update_functions : k => v
    if k != "phone-update-controller"  # Tous sauf controller
  }

  function_name = aws_lambda_function.phone_update_functions[each.key].function_name
  principal     = "states.amazonaws.com"
  action        = "lambda:InvokeFunction"
}
```

**12 Lambda Functions créées :**
1. `phone-update-controller` (entry point)
2. `read-client-profile`
3. `phone-validator`
4. `check-phone-history`
5. `human-approval-handler`
6. `send-otp-sms`
7. `check-otp-status`
8. `phone-mdmae-client`
9. `fcc-sender-phone`
10. `crm-updater-phone`
11. `notification-updater-phone`
12. `notification-sender-phone` (email confirmation) ⭐ **NOUVEAU**

**Variables ajoutées :** `modules/lambda/variables.tf`
- `lambda_code_bucket`
- `code_version`
- `dynamodb_client_table_name`
- `dynamodb_phone_history_table_name`
- `dynamodb_otp_table_name`
- `sqs_fraud_review_queue_url`
- `mdmae_api_endpoint`
- `fcc_api_endpoint`
- `sns_topic_arn`
- `step_functions_phone_update_arn`

**Outputs ajoutés :** `modules/lambda/outputs.tf`
- `phone_update_function_arns`
- `phone_update_controller_arn`
- `phone_update_controller_invoke_arn`

**Commande Terraform :**
```bash
terraform plan -target=module.lambda
terraform apply -target=module.lambda
```

---

### Étape 5 : Step Functions State Machine (dépend de tout)

**Pourquoi en dernier (presque) ?** La state machine référence toutes les Lambdas, tables DynamoDB, et SQS queue.

**Fichier créé :** `modules/step-functions/state-machines/client-phone-update.json.tpl`

**Note importante :** Cette définition inclut les **retry automatiques** pour toutes les étapes critiques selon la stratégie documentée dans `RETRY_STRATEGY_GUIDE.md`.

```json
{
  "Comment": "Client Phone Update Workflow with Retry Strategy",
  "StartAt": "ReadClientProfile",
  "States": {
    "ReadClientProfile": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "TimeoutSeconds": 30,
      "Parameters": {
        "FunctionName": "${client_profile_reader_arn}",
        "Payload": {
          "clientId.$": "$.clientId"
        }
      },
      "Retry": [
        {
          "ErrorEquals": [
            "States.TaskFailed",
            "DynamoDb.ProvisionedThroughputExceededException",
            "DynamoDb.ThrottlingException"
          ],
          "IntervalSeconds": 2,
          "MaxAttempts": 3,
          "BackoffRate": 2.0,
          "Comment": "Retry for DynamoDB throttling"
        },
        {
          "ErrorEquals": ["States.Timeout"],
          "IntervalSeconds": 1,
          "MaxAttempts": 2,
          "BackoffRate": 1.5
        }
      ],
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "ResultPath": "$.error",
          "Next": "NotifyFailure"
        }
      ],
      "Next": "ParallelValidations"
    },
    "ParallelValidations": {
      "Type": "Parallel",
      "Branches": [
        {
          "StartAt": "ValidatePhoneFormat",
          "States": {
            "ValidatePhoneFormat": {
              "Type": "Task",
              "Resource": "arn:aws:states:::lambda:invoke",
              "TimeoutSeconds": 10,
              "Parameters": {
                "FunctionName": "${phone_validator_arn}"
              },
              "Comment": "No retry - validation is deterministic",
              "Retry": [],
              "Catch": [
                {
                  "ErrorEquals": ["ValidationException"],
                  "ResultPath": "$.validationError",
                  "Next": "ValidationFailed"
                }
              ],
              "End": true
            },
            "ValidationFailed": {
              "Type": "Fail",
              "Error": "PhoneValidationFailed",
              "Cause": "Phone number format is invalid"
            }
          }
        },
        {
          "StartAt": "CheckPhoneHistory",
          "States": {
            "CheckPhoneHistory": {
              "Type": "Task",
              "Resource": "arn:aws:states:::lambda:invoke",
              "TimeoutSeconds": 20,
              "Parameters": {
                "FunctionName": "${check_phone_history_arn}"
              },
              "Retry": [
                {
                  "ErrorEquals": [
                    "DynamoDb.ProvisionedThroughputExceededException",
                    "DynamoDb.ThrottlingException",
                    "States.TaskFailed"
                  ],
                  "IntervalSeconds": 2,
                  "MaxAttempts": 3,
                  "BackoffRate": 2.0,
                  "Comment": "Retry for DynamoDB throttling"
                }
              ],
              "Catch": [
                {
                  "ErrorEquals": ["States.ALL"],
                  "ResultPath": "$.historyError",
                  "Next": "HistoryCheckFailed"
                }
              ],
              "End": true
            },
            "HistoryCheckFailed": {
              "Type": "Fail",
              "Error": "HistoryCheckFailed",
              "Cause": "Failed to check phone history"
            }
          }
        }
      ],
      "Next": "EvaluateFraudRisk"
    },
    "EvaluateFraudRisk": {
      "Type": "Choice",
      "Choices": [
        {
          "Variable": "$.historyCheck.isSuspicious",
          "BooleanEquals": true,
          "Next": "SendToFraudReview"
        }
      ],
      "Default": "RecordPhoneHistory"
    },
    "SendToFraudReview": {
      "Type": "Task",
      "Resource": "arn:aws:states:::sqs:sendMessage.waitForTaskToken",
      "Parameters": {
        "QueueUrl": "${fraud_review_queue_url}",
        "MessageBody": {
          "clientId.$": "$.clientProfile.clientId",
          "taskToken.$": "$$.Task.Token",
          "suspicionScore.$": "$.historyCheck.suspicionScore",
          "reason.$": "$.historyCheck.reason"
        }
      },
      "TimeoutSeconds": 86400,
      "Comment": "Wait for human approval (24 hours max)",
      "Retry": [],
      "Catch": [
        {
          "ErrorEquals": ["States.Timeout"],
          "ResultPath": "$.approvalError",
          "Next": "ApprovalTimeout"
        }
      ],
      "Next": "RecordPhoneHistory"
    },
    "ApprovalTimeout": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${notification_failure_arn}",
        "Payload": {
          "reason": "Human approval timeout after 24 hours"
        }
      },
      "End": true
    },
    "RecordPhoneHistory": {
      "Type": "Task",
      "Resource": "arn:aws:states:::dynamodb:putItem",
      "Parameters": {
        "TableName": "${phone_history_table_name}",
        "Item": {
          "clientId": { "S.$": "$.clientProfile.clientId" },
          "timestamp": { "N.$": "$$.State.EnteredTime" },
          "oldPhone": { "S.$": "$.clientProfile.phoneNumber" },
          "newPhone": { "S.$": "$.phoneNumber" }
        }
      },
      "Retry": [
        {
          "ErrorEquals": [
            "DynamoDb.ProvisionedThroughputExceededException",
            "DynamoDb.ThrottlingException"
          ],
          "IntervalSeconds": 1,
          "MaxAttempts": 3,
          "BackoffRate": 2.0
        }
      ],
      "Next": "SendOTPSMS"
    },
    "SendOTPSMS": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "TimeoutSeconds": 30,
      "Parameters": {
        "FunctionName": "${send_otp_sms_arn}",
        "Payload": {
          "clientId.$": "$.clientProfile.clientId",
          "phoneNumber.$": "$.phoneNumber"
        }
      },
      "Retry": [
        {
          "ErrorEquals": [
            "SNS.ThrottlingException",
            "States.TaskFailed"
          ],
          "IntervalSeconds": 3,
          "MaxAttempts": 2,
          "BackoffRate": 2.0,
          "Comment": "Limited to 2 retries to avoid sending multiple SMS"
        }
      ],
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "ResultPath": "$.otpError",
          "Next": "OTPSendFailed"
        }
      ],
      "Next": "WaitForOTP"
    },
    "WaitForOTP": {
      "Type": "Wait",
      "Seconds": 60,
      "Comment": "Wait 60 seconds for client to validate OTP",
      "Next": "CheckOTPStatus"
    },
    "CheckOTPStatus": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "TimeoutSeconds": 10,
      "Parameters": {
        "FunctionName": "${check_otp_status_arn}",
        "Payload": {
          "clientId.$": "$.clientProfile.clientId",
          "otpId.$": "$.otp.otpId"
        }
      },
      "Comment": "No retry - this is polling, not critical operation",
      "Retry": [],
      "Next": "EvaluateOTPStatus"
    },
    "EvaluateOTPStatus": {
      "Type": "Choice",
      "Choices": [
        {
          "Variable": "$.otpStatus.validated",
          "BooleanEquals": true,
          "Next": "UpdateMDMAE"
        }
      ],
      "Default": "OTPValidationFailed"
    },
    "UpdateMDMAE": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "TimeoutSeconds": 90,
      "Comment": "CRITICAL STEP - Update Master Data Management with retry",
      "Parameters": {
        "FunctionName": "${phone_mdmae_client_arn}",
        "Payload": {
          "clientId.$": "$.clientProfile.clientId",
          "phoneNumber.$": "$.phoneNumber",
          "country.$": "$.country"
        }
      },
      "Retry": [
        {
          "ErrorEquals": [
            "Lambda.ServiceException",
            "Lambda.AWSLambdaException",
            "Lambda.SdkClientException",
            "Lambda.TooManyRequestsException",
            "States.TaskFailed"
          ],
          "IntervalSeconds": 5,
          "MaxAttempts": 3,
          "BackoffRate": 2.0,
          "Comment": "Retry for Lambda execution errors"
        },
        {
          "ErrorEquals": ["States.Timeout"],
          "IntervalSeconds": 3,
          "MaxAttempts": 2,
          "BackoffRate": 2.0
        },
        {
          "ErrorEquals": [
            "HttpTimeoutException",
            "HttpServerException",
            "ServiceUnavailableException"
          ],
          "IntervalSeconds": 10,
          "MaxAttempts": 3,
          "BackoffRate": 2.0,
          "Comment": "Retry for HTTP/API errors from MDMAE"
        }
      ],
      "Catch": [
        {
          "ErrorEquals": [
            "ValidationException",
            "BadRequestException",
            "UnauthorizedException"
          ],
          "ResultPath": "$.mdmaeError",
          "Next": "MDMAEClientError"
        },
        {
          "ErrorEquals": ["States.ALL"],
          "ResultPath": "$.mdmaeError",
          "Next": "MDMAEUpdateFailed"
        }
      ],
      "ResultPath": "$.mdmaeResult",
      "Next": "ParallelSystemUpdates"
    },
    "ParallelSystemUpdates": {
      "Type": "Parallel",
      "Comment": "Update FCC, CRM, and Kafka in parallel (non-blocking)",
      "Branches": [
        {
          "StartAt": "UpdateFCC",
          "States": {
            "UpdateFCC": {
              "Type": "Task",
              "Resource": "arn:aws:states:::lambda:invoke",
              "TimeoutSeconds": 60,
              "Parameters": {
                "FunctionName": "${fcc_sender_arn}",
                "Payload": {
                  "clientId.$": "$.clientProfile.clientId",
                  "newPhone.$": "$.phoneNumber",
                  "mdmaeId.$": "$.mdmaeResult.mdmaeId"
                }
              },
              "Retry": [
                {
                  "ErrorEquals": ["States.TaskFailed", "ApiException"],
                  "IntervalSeconds": 5,
                  "MaxAttempts": 3,
                  "BackoffRate": 2.0
                }
              ],
              "Catch": [
                {
                  "ErrorEquals": ["States.ALL"],
                  "ResultPath": "$.fccError",
                  "Next": "FCCUpdateOptional"
                }
              ],
              "End": true
            },
            "FCCUpdateOptional": {
              "Type": "Pass",
              "Comment": "FCC update failed but continue anyway (non-blocking)",
              "Result": {
                "fccSuccess": false,
                "message": "FCC update failed - logged for manual review"
              },
              "End": true
            }
          }
        },
        {
          "StartAt": "UpdateCRM",
          "States": {
            "UpdateCRM": {
              "Type": "Task",
              "Resource": "arn:aws:states:::lambda:invoke",
              "TimeoutSeconds": 60,
              "Parameters": {
                "FunctionName": "${crm_updater_arn}",
                "Payload": {
                  "clientId.$": "$.clientProfile.clientId",
                  "newPhone.$": "$.phoneNumber"
                }
              },
              "Retry": [
                {
                  "ErrorEquals": ["States.TaskFailed", "ApiException"],
                  "IntervalSeconds": 5,
                  "MaxAttempts": 3,
                  "BackoffRate": 2.0
                }
              ],
              "Catch": [
                {
                  "ErrorEquals": ["States.ALL"],
                  "ResultPath": "$.crmError",
                  "Next": "CRMUpdateOptional"
                }
              ],
              "End": true
            },
            "CRMUpdateOptional": {
              "Type": "Pass",
              "Comment": "CRM update failed but continue anyway (non-blocking)",
              "Result": {
                "crmSuccess": false,
                "message": "CRM update failed - logged for manual review"
              },
              "End": true
            }
          }
        },
        {
          "StartAt": "PublishKafkaEvent",
          "States": {
            "PublishKafkaEvent": {
              "Type": "Task",
              "Resource": "arn:aws:states:::lambda:invoke",
              "TimeoutSeconds": 30,
              "Parameters": {
                "FunctionName": "${notification_updater_arn}",
                "Payload": {
                  "eventType": "PHONE_UPDATE",
                  "clientId.$": "$.clientProfile.clientId",
                  "oldPhone.$": "$.clientProfile.phoneNumber",
                  "newPhone.$": "$.phoneNumber"
                }
              },
              "Retry": [
                {
                  "ErrorEquals": ["States.TaskFailed"],
                  "IntervalSeconds": 2,
                  "MaxAttempts": 3,
                  "BackoffRate": 2.0
                }
              ],
              "Catch": [
                {
                  "ErrorEquals": ["States.ALL"],
                  "ResultPath": "$.kafkaError",
                  "Next": "KafkaPublishOptional"
                }
              ],
              "End": true
            },
            "KafkaPublishOptional": {
              "Type": "Pass",
              "Comment": "Kafka publish failed but continue anyway (non-blocking)",
              "Result": {
                "kafkaSuccess": false,
                "message": "Kafka event not published - logged for manual review"
              },
              "End": true
            }
          }
        }
      ],
      "Next": "UpdateClientProfile"
    },
    "UpdateClientProfile": {
      "Type": "Task",
      "Resource": "arn:aws:states:::dynamodb:updateItem",
      "Parameters": {
        "TableName": "${client_profile_table_name}",
        "Key": {
          "clientId": { "S.$": "$.clientProfile.clientId" }
        },
        "UpdateExpression": "SET phoneNumber = :phone, lastPhoneUpdate = :timestamp",
        "ExpressionAttributeValues": {
          ":phone": { "S.$": "$.phoneNumber" },
          ":timestamp": { "S.$": "$$.State.EnteredTime" }
        }
      },
      "Retry": [
        {
          "ErrorEquals": [
            "DynamoDb.ProvisionedThroughputExceededException",
            "DynamoDb.ThrottlingException"
          ],
          "IntervalSeconds": 1,
          "MaxAttempts": 3,
          "BackoffRate": 2.0
        }
      ],
      "Next": "SendConfirmationEmail"
    },
    "SendConfirmationEmail": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "TimeoutSeconds": 30,
      "Parameters": {
        "FunctionName": "${notification_sender_arn}",
        "Payload": {
          "clientId.$": "$.clientProfile.clientId",
          "oldPhone.$": "$.clientProfile.phoneNumber",
          "newPhone.$": "$.phoneNumber",
          "emailType": "phone_update_confirmation"
        }
      },
      "Retry": [
        {
          "ErrorEquals": ["States.TaskFailed"],
          "IntervalSeconds": 2,
          "MaxAttempts": 3,
          "BackoffRate": 2.0
        }
      ],
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "ResultPath": "$.emailError",
          "Next": "WorkflowComplete"
        }
      ],
      "Next": "WorkflowComplete"
    },
    "WorkflowComplete": {
      "Type": "Succeed",
      "Comment": "Phone update workflow completed successfully"
    },
    "MDMAEClientError": {
      "Type": "Fail",
      "Error": "MDMAEClientError",
      "Cause": "Client error (4xx) from MDMAE API - invalid request"
    },
    "MDMAEUpdateFailed": {
      "Type": "Fail",
      "Error": "MDMAEUpdateFailed",
      "Cause": "Failed to update MDMAE after all retries"
    },
    "OTPSendFailed": {
      "Type": "Fail",
      "Error": "OTPSendFailed",
      "Cause": "Failed to send OTP SMS after retries"
    },
    "OTPValidationFailed": {
      "Type": "Fail",
      "Error": "OTPValidationFailed",
      "Cause": "Client did not validate OTP within timeout period"
    },
    "NotifyFailure": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${notification_failure_arn}",
        "Payload": {
          "error.$": "$.error"
        }
      },
      "End": true
    }
  }
}
```

**Points clés de la stratégie de retry :**

| Étape | Retry | Raison |
|-------|-------|--------|
| **ReadClientProfile** | ✅ 3x (2s → 4s → 8s) | DynamoDB peut throttle |
| **ValidatePhoneFormat** | ❌ Pas de retry | Validation déterministe |
| **CheckPhoneHistory** | ✅ 3x (2s → 4s → 8s) | DynamoDB peut throttle |
| **SendToFraudReview** | ❌ Pas de retry | Attente événement externe |
| **RecordPhoneHistory** | ✅ 3x (1s → 2s → 4s) | Écriture DynamoDB |
| **SendOTPSMS** | ✅ 2x (3s → 6s) | SMS - limité pour éviter doublons |
| **CheckOTPStatus** | ❌ Pas de retry | Polling simple |
| **UpdateMDMAE** | ✅ 9x total | Critique - 3 types de retry |
| **UpdateFCC/CRM** | ✅ 3x (5s → 10s → 20s) | Non bloquant |
| **PublishKafka** | ✅ 3x (2s → 4s → 8s) | Non bloquant |
| **UpdateClientProfile** | ✅ 3x (1s → 2s → 4s) | Écriture DynamoDB finale |
| **SendConfirmationEmail** | ✅ 3x (2s → 4s → 8s) | Non bloquant |

**Voir aussi :**
- `RETRY_STRATEGY_GUIDE.md` - Stratégie complète de retry
- `RETRY_IMPLEMENTATION_EXAMPLE.md` - Exemple d'implémentation UpdateMDMAE

**Configuration Terraform :** `modules/step-functions/main.tf` (déjà existant avec for_each)

**Variables à passer :**
```hcl
state_machines = {
  "client-phone-update" = {
    role_arn            = module.iam.stepfunctions_execution_role_arn
    definition_template = "state-machines/client-phone-update.json.tpl"
    template_vars = {
      client_profile_reader_arn = module.lambda.phone_update_function_arns["read-client-profile"]
      phone_validator_arn       = module.lambda.phone_update_function_arns["phone-validator"]
      check_phone_history_arn   = module.lambda.phone_update_function_arns["check-phone-history"]
      send_otp_sms_arn          = module.lambda.phone_update_function_arns["send-otp-sms"]
      check_otp_status_arn      = module.lambda.phone_update_function_arns["check-otp-status"]
      phone_mdmae_client_arn    = module.lambda.phone_update_function_arns["phone-mdmae-client"]
      fcc_sender_arn            = module.lambda.phone_update_function_arns["fcc-sender-phone"]
      crm_updater_arn           = module.lambda.phone_update_function_arns["crm-updater-phone"]
      notification_updater_arn  = module.lambda.phone_update_function_arns["notification-updater-phone"]
      dynamodb_table_name       = module.dynamodb.table_name
      phone_history_table_name  = module.dynamodb.phone_history_table_name
      fraud_review_queue_url    = module.sqs.fraud_review_queue_url
    }
  }
}
```

**Commande Terraform :**
```bash
terraform plan -target=module.step_functions
terraform apply -target=module.step_functions
```

---

### Étape 6 : API Gateway Endpoint (dépend de Lambda Controller)

**Pourquoi maintenant ?** L'endpoint API Gateway doit invoquer le Lambda Controller créé à l'étape 4.

**Fichier créé :** `modules/api-gateway/phone_update_endpoint.tf`

```hcl
# Resource /phone
resource "aws_api_gateway_resource" "phone" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.client_id.id  # Déjà existant
  path_part   = "phone"
}

# Method PUT
resource "aws_api_gateway_method" "put_phone" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.phone.id
  http_method   = "PUT"
  authorization = "NONE"

  request_validator_id = aws_api_gateway_request_validator.phone_update.id
}

# Request Validator
resource "aws_api_gateway_request_validator" "phone_update" {
  name                        = "${var.environment}-phone-update-validator"
  rest_api_id                 = aws_api_gateway_rest_api.main.id
  validate_request_body       = true
  validate_request_parameters = true
}

# Integration avec Lambda Controller
resource "aws_api_gateway_integration" "phone_lambda" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.phone.id
  http_method = aws_api_gateway_method.put_phone.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.phone_update_controller_invoke_arn
}

# CORS support
resource "aws_api_gateway_method" "options_phone" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.phone.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}
```

**Variables ajoutées :** `modules/api-gateway/variables.tf`
- `phone_update_controller_invoke_arn`

**Endpoint final :** `PUT https://{api-id}.execute-api.ca-central-1.amazonaws.com/dev/api/clients/{clientId}/phone`

**Commande Terraform :**
```bash
terraform plan -target=module.api_gateway
terraform apply -target=module.api_gateway
```

---

### Étape 7 : Swagger/OpenAPI Documentation (dépend de API Gateway)

**Pourquoi en dernier ?** La documentation Swagger référence les endpoints API Gateway et le Lambda Controller.

#### 7.1 Spécification OpenAPI

**Fichier créé :** `openapi/phone-update-api.yaml`

```yaml
openapi: 3.0.3
info:
  title: MCP Phone Update API
  description: API de mise à jour des numéros de téléphone clients
  version: 1.0.0
  contact:
    name: Équipe MCP
    email: mcp-team@bnc.ca

servers:
  - url: https://{apiId}.execute-api.ca-central-1.amazonaws.com/{stage}

paths:
  /api/clients/{clientId}/phone:
    put:
      summary: Mettre à jour le numéro de téléphone d'un client
      operationId: updateClientPhone
      parameters:
        - name: clientId
          in: path
          required: true
          schema:
            type: string
          example: "CLIENT-12345"
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              required:
                - phoneNumber
                - country
              properties:
                phoneNumber:
                  type: string
                  pattern: '^\+[1-9]\d{1,14}$'
                  example: "+15141234567"
                country:
                  type: string
                  pattern: '^[A-Z]{2}$'
                  example: "CA"
      responses:
        '200':
          description: Workflow démarré avec succès
          content:
            application/json:
              schema:
                type: object
                properties:
                  message:
                    type: string
                  executionArn:
                    type: string
                  timestamp:
                    type: string
        '400':
          description: Requête invalide
        '500':
          description: Erreur serveur interne
```

**Note :** Le fichier complet contient également :
- Endpoint de vérification de statut
- Schémas détaillés
- Exemples de requêtes/réponses
- Documentation des erreurs

#### 7.2 Infrastructure Swagger (S3 + CloudFront)

**Fichier créé :** `modules/api-gateway/swagger_documentation.tf`

```hcl
# Bucket S3 pour héberger la documentation Swagger
resource "aws_s3_bucket" "swagger_docs" {
  bucket = "${var.environment}-mcp-api-docs"

  tags = {
    Name        = "${var.environment}-mcp-api-docs"
    Environment = var.environment
    Project     = "MCP"
  }
}

# Configuration publique pour lecture seule
resource "aws_s3_bucket_public_access_block" "swagger_docs" {
  bucket = aws_s3_bucket.swagger_docs.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# Policy pour permettre la lecture publique
resource "aws_s3_bucket_policy" "swagger_docs_public_read" {
  bucket = aws_s3_bucket.swagger_docs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PublicReadGetObject"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.swagger_docs.arn}/*"
    }]
  })
}

# Configuration du bucket pour hébergement web
resource "aws_s3_bucket_website_configuration" "swagger_docs" {
  bucket = aws_s3_bucket.swagger_docs.id

  index_document {
    suffix = "index.html"
  }
}

# Upload du fichier OpenAPI spec (YAML)
resource "aws_s3_object" "openapi_spec" {
  bucket       = aws_s3_bucket.swagger_docs.id
  key          = "phone-update/openapi.yaml"
  content      = templatefile("${path.module}/../../openapi/phone-update-api.yaml", {
    phone_update_controller_arn = var.phone_update_controller_arn
  })
  content_type = "application/x-yaml"
  etag         = filemd5("${path.module}/../../openapi/phone-update-api.yaml")
}

# Upload de Swagger UI (HTML)
resource "aws_s3_object" "swagger_ui_index" {
  bucket = aws_s3_bucket.swagger_docs.id
  key    = "phone-update/index.html"
  content = templatefile("${path.module}/swagger-ui/index.html", {
    openapi_spec_url = "https://${aws_s3_bucket.swagger_docs.id}.s3.ca-central-1.amazonaws.com/phone-update/openapi.yaml"
  })
  content_type = "text/html"
}

# CloudFront distribution pour servir Swagger UI (optionnel)
resource "aws_cloudfront_distribution" "swagger_docs" {
  count = var.enable_cloudfront ? 1 : 0

  enabled             = true
  default_root_object = "phone-update/index.html"

  origin {
    domain_name = aws_s3_bucket_website_configuration.swagger_docs.website_endpoint
    origin_id   = "S3-swagger-docs"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3-swagger-docs"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
```

#### 7.3 Swagger UI HTML

**Fichier créé :** `modules/api-gateway/swagger-ui/index.html`

```html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>MCP Phone Update API - Swagger UI</title>
    <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5.10.0/swagger-ui.css">
    <style>
        .topbar { background-color: #003366; }
        .custom-header {
            background-color: #003366;
            color: white;
            padding: 20px;
            text-align: center;
        }
    </style>
</head>
<body>
    <div class="custom-header">
        <h1>MCP Phone Update API</h1>
        <p>Master Client Profile - Documentation API</p>
    </div>
    <div id="swagger-ui"></div>
    <script src="https://unpkg.com/swagger-ui-dist@5.10.0/swagger-ui-bundle.js"></script>
    <script>
        window.onload = function() {
            SwaggerUIBundle({
                url: "${openapi_spec_url}",
                dom_id: '#swagger-ui',
                deepLinking: true,
                docExpansion: "list",
                tryItOutEnabled: true
            });
        };
    </script>
</body>
</html>
```

**Variables ajoutées :** `modules/api-gateway/variables.tf`
```hcl
variable "enable_cloudfront" {
  description = "Enable CloudFront distribution for Swagger UI"
  type        = bool
  default     = false
}

variable "api_version" {
  description = "API version for documentation"
  type        = string
  default     = "1.0.0"
}
```

**Outputs ajoutés :** `modules/api-gateway/outputs.tf`
```hcl
output "swagger_ui_url" {
  description = "URL de la documentation Swagger UI"
  value       = var.enable_cloudfront ?
    "https://${aws_cloudfront_distribution.swagger_docs[0].domain_name}/phone-update/index.html" :
    "http://${aws_s3_bucket_website_configuration.swagger_docs.website_endpoint}/phone-update/index.html"
}

output "openapi_spec_url" {
  description = "URL de la spécification OpenAPI"
  value       = "https://${aws_s3_bucket.swagger_docs.id}.s3.ca-central-1.amazonaws.com/phone-update/openapi.yaml"
}
```

**Commande Terraform :**
```bash
# Déployer la documentation Swagger
terraform plan -target=module.api_gateway
terraform apply -target=module.api_gateway

# Afficher l'URL Swagger UI
terraform output swagger_ui_url
```

**Accès à la documentation :**
```bash
# Sans CloudFront (dev)
http://dev-mcp-api-docs.s3-website.ca-central-1.amazonaws.com/phone-update/index.html

# Avec CloudFront (prod)
https://d123456abcdef.cloudfront.net/phone-update/index.html

# Spec OpenAPI directe
https://dev-mcp-api-docs.s3.ca-central-1.amazonaws.com/phone-update/openapi.yaml
```

---

## 📊 Résumé des fichiers créés

| Fichier | Type | Ressources créées |
|---------|------|-------------------|
| `modules/step-functions/state-machines/client-phone-update.json.tpl` | JSON | State machine workflow (28 états) |
| `modules/dynamodb/phone_update_tables.tf` | Terraform | 2 tables DynamoDB |
| `modules/dynamodb/outputs.tf` | Terraform | 4 outputs ajoutés |
| `modules/sqs/fraud_review_queue.tf` | Terraform | 1 queue SQS + 1 DLQ + policy |
| `modules/sqs/outputs.tf` | Terraform | 4 outputs ajoutés |
| `modules/sqs/variables.tf` | Terraform | 1 variable ajoutée |
| `modules/lambda/phone_update_functions.tf` | Terraform | 12 Lambda functions + logs + permissions |
| `modules/lambda/variables.tf` | Terraform | 12 variables ajoutées |
| `modules/lambda/outputs.tf` | Terraform | 4 outputs ajoutés |
| `modules/iam/phone_update_policies.tf` | Terraform | 3 IAM policies |
| `modules/iam/variables.tf` | Terraform | 6 variables ajoutées |
| `modules/api-gateway/phone_update_endpoint.tf` | Terraform | 1 endpoint API + CORS + validator |
| `modules/api-gateway/variables.tf` | Terraform | 3 variables ajoutées |
| `modules/api-gateway/swagger_documentation.tf` | Terraform | Bucket S3 + CloudFront + OpenAPI uploads |
| `modules/api-gateway/outputs.tf` | Terraform | 2 outputs Swagger ajoutés |
| `openapi/phone-update-api.yaml` | OpenAPI | Spécification API complète |
| `modules/api-gateway/swagger-ui/index.html` | HTML | Interface Swagger UI |

**Total :** 16 fichiers créés/modifiés

---

## 🚀 Déploiement complet

### Option 1 : Déploiement par étapes (recommandé)

```bash
cd /Users/fabricefoko/Documents/mcp-infrastructure

# Étape 1 : DynamoDB
terraform plan -target=module.dynamodb
terraform apply -target=module.dynamodb

# Étape 2 : SQS
terraform plan -target=module.sqs
terraform apply -target=module.sqs

# Étape 3 : IAM
terraform plan -target=module.iam
terraform apply -target=module.iam

# Étape 4 : Lambda
terraform plan -target=module.lambda
terraform apply -target=module.lambda

# Étape 5 : Step Functions
terraform plan -target=module.step_functions
terraform apply -target=module.step_functions

# Étape 6 : API Gateway
terraform plan -target=module.api_gateway
terraform apply -target=module.api_gateway

# Étape 7 : Swagger Documentation (déjà inclus dans api_gateway)
# Afficher l'URL Swagger
terraform output swagger_ui_url
terraform output openapi_spec_url
```

### Option 2 : Déploiement global

```bash
cd /Users/fabricefoko/Documents/mcp-infrastructure
terraform init
terraform plan
terraform apply
```

**Durée estimée :** 5-10 minutes

---

## ✅ Validation du déploiement

### 1. Vérifier les tables DynamoDB

```bash
aws dynamodb list-tables --region ca-central-1 | grep PhoneNumberHistory
aws dynamodb list-tables --region ca-central-1 | grep OTPCodes
```

### 2. Vérifier la SQS queue

```bash
aws sqs list-queues --region ca-central-1 | grep fraud-review-queue
```

### 3. Vérifier les Lambdas

```bash
aws lambda list-functions --region ca-central-1 | grep phone
```

Devrait lister 12 fonctions :
- dev-mcp-phone-update-controller
- dev-mcp-read-client-profile
- dev-mcp-phone-validator
- dev-mcp-check-phone-history
- dev-mcp-human-approval-handler
- dev-mcp-send-otp-sms
- dev-mcp-check-otp-status
- dev-mcp-phone-mdmae-client
- dev-mcp-fcc-sender-phone
- dev-mcp-crm-updater-phone
- dev-mcp-notification-updater-phone
- dev-mcp-notification-sender-phone ⭐ **NOUVEAU**

### 4. Vérifier la state machine

```bash
aws stepfunctions list-state-machines --region ca-central-1 | grep phone-update
```

### 5. Vérifier l'endpoint API Gateway

```bash
aws apigateway get-rest-apis --region ca-central-1 | grep mcp-api
```

### 6. Test end-to-end

```bash
API_URL=$(terraform output -raw api_gateway_url)
curl -X PUT "${API_URL}/api/clients/123/phone" \
  -H "Content-Type: application/json" \
  -d '{"phoneNumber":"+15141234567","country":"CA"}'
```

**Réponse attendue :**
```json
{
  "message": "Phone update workflow initiated",
  "executionArn": "arn:aws:states:ca-central-1:123456:execution:dev-mcp-client-phone-update:abc-123",
  "timestamp": "2026-09-25T10:30:00Z"
}
```

### 7. Vérifier Swagger UI

```bash
# Afficher l'URL de la documentation
SWAGGER_URL=$(terraform output -raw swagger_ui_url)
echo "Documentation Swagger disponible à : $SWAGGER_URL"

# Ouvrir dans le navigateur (Mac)
open $SWAGGER_URL

# Ouvrir dans le navigateur (Linux)
xdg-open $SWAGGER_URL

# Télécharger la spec OpenAPI
OPENAPI_URL=$(terraform output -raw openapi_spec_url)
curl -o phone-update-openapi.yaml $OPENAPI_URL
```

**Vérifications Swagger UI :**
- ✅ Interface Swagger UI s'affiche correctement
- ✅ Endpoint `PUT /api/clients/{clientId}/phone` est visible
- ✅ Endpoint `GET /api/clients/{clientId}/phone/status/{executionId}` est visible
- ✅ Schémas de requête/réponse sont documentés
- ✅ Bouton "Try it out" fonctionne
- ✅ Exemples de requêtes sont présents

---

## 🔍 Diagramme de dépendances

```
DynamoDB Tables ────┐
                    ├──→ IAM Roles ──→ Lambda Functions ──→ Step Functions ──→ API Gateway ──→ Swagger Docs
SQS Queue ─────────┘
```

**Ordre de création :**
1. DynamoDB Tables (aucune dépendance)
2. SQS Queue (aucune dépendance)
3. IAM Roles (référence DynamoDB et SQS)
4. Lambda Functions (référence IAM roles)
5. Step Functions (référence Lambdas, DynamoDB, SQS)
6. API Gateway (référence Lambda Controller)
7. Swagger Documentation (référence API Gateway et Lambda Controller)

---

## 📝 Notes importantes

### Variables d'environnement requises

Dans votre configuration d'environnement (ex: `environments/dev/terraform.tfvars`), vous devez définir :

```hcl
# S3 bucket pour les JARs Lambda
lambda_code_bucket = "bnc-lambda-code-dev"

# Endpoints API externes
mdmae_api_endpoint = "https://mdmae.bnc.ca/api/v1"
fcc_api_endpoint   = "https://fcc.bnc.ca/api/v1"
crm_api_endpoint   = "https://crm.bnc.ca/api/v1"

# SNS topic pour SMS OTP
sns_topic_arn = "arn:aws:sns:ca-central-1:123456:otp-sms-topic"

# AWS Account ID
aws_account_id = "123456789012"
```

### Coûts estimés (environnement dev)

| Service | Coût mensuel estimé |
|---------|---------------------|
| DynamoDB (PAY_PER_REQUEST) | $1-5 |
| SQS | $0-1 |
| Lambda (12 functions) | $5-20 |
| Step Functions | $1-10 |
| API Gateway | $3-10 |
| CloudWatch Logs | $2-5 |
| AWS SES (email confirmation) | $0-1 |
| **Total** | **$13-52** |

---

## 🎯 Prochaines étapes

1. **Déployer le code métier Java** (repo `mcp-local`)
   - Voir `WORKFLOW_PHONE_UPDATE_PHASE2_CODE_JAVA.md`

2. **Tester le workflow complet**
   - Voir `WORKFLOW_PHONE_UPDATE_PHASE3_TESTS.md`

3. **Configurer le monitoring**
   - CloudWatch Dashboard
   - Alarmes sur erreurs Lambda
   - Métriques Step Functions

4. **Documentation opérationnelle**
   - Runbook pour les opérations
   - Guide de dépannage

---

**Dernière mise à jour :** 2026-09-25
**Version :** 1.0.0
**Statut :** ✅ Prêt pour déploiement