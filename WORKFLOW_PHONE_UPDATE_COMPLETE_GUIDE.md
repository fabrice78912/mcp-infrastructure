# Workflow : Mise à jour numéro de téléphone - Guide complet

## 📌 Table des matières

1. [Description du workflow en langage humain](#description-du-workflow-en-langage-humain)
2. [Traduction en Step Functions JSON](#traduction-en-step-functions-json)
3. [Flow d'implémentation étape par étape](#flow-dimplémentation-étape-par-étape)

---

## Description du workflow en langage humain

### 🎯 Objectif

Permettre à un client de mettre à jour son numéro de téléphone avec validation, vérification de fraude, et synchronisation dans tous les systèmes de la BNC.

---

### 📋 Étapes du workflow (en français simple)

#### **Étape 1 : Réception de la requête**
- Le client envoie une requête HTTP PUT avec son nouveau numéro de téléphone
- API Gateway reçoit la requête et invoque le **Lambda Controller**

#### **Étape 2 : Validation initiale (Lambda Controller)**
- Le Controller valide :
  - Format HTTP correct
  - Client authentifié
  - Données requises présentes
- Enrichit la requête avec metadata (timestamp, requestId)
- **Démarre le workflow Step Functions**
- Retourne HTTP 202 Accepted au client

#### **Étape 3 : Lire le profil client actuel (Lambda)**
- Lit le profil complet du client dans DynamoDB
- Récupère le numéro de téléphone actuel
- Vérifie que le client existe
- **SI client n'existe pas** → Erreur "ClientNotFound" → Fin du workflow

#### **Étape 4 : Validations en parallèle (2 Lambdas en même temps)**

**Branche A : Valider le format du téléphone (Lambda)**
- Vérifie que le numéro est valide selon le pays
  - Canada : +1 (XXX) XXX-XXXX
  - USA : +1 (XXX) XXX-XXXX
  - France : +33 X XX XX XX XX
- Normalise le format (enlève espaces, parenthèses)
- Vérifie que ce n'est pas un numéro jetable (VoIP suspect)

**Branche B : Vérifier l'historique de changements (Lambda)**
- Lit l'historique des numéros de téléphone du client
- Compte combien de changements dans les 30 derniers jours
- Calcule un score de suspicion (0.0 à 1.0)
  - 0 changement en 1 an = score 0.1 (safe)
  - 3+ changements en 30 jours = score 0.9 (suspect)
- Détecte des patterns suspects :
  - Changement juste après un virement important
  - Numéro similaire à un numéro frauduleux connu

**⏱ Durée : Les 2 branches s'exécutent en parallèle (gain de temps)**

#### **Étape 5 : Vérifier les résultats de validation (Choice)**

**SI le format du téléphone est invalide** :
- → Envoyer notification d'erreur au client
- → Fin du workflow (échec)

**SI le format est valide** :
- → Continuer

#### **Étape 6 : Évaluer le score de suspicion (Choice)**

**SI score > 0.8 (très suspect)** :
- → Aller à l'étape "Approbation manuelle"

**SI score entre 0.5 et 0.8 ET plus de 3 changements récents** :
- → Aller à l'étape "Approbation manuelle"

**SINON (score < 0.5 ou pas suspect)** :
- → Continuer automatiquement

#### **Étape 7A : Approbation manuelle (si suspect)**

- Envoie un message SQS à la queue "fraud-review-queue"
- Le message contient :
  - Numéro actuel
  - Nouveau numéro demandé
  - Score de suspicion
  - Raison de la suspicion
  - **Task Token** (pour que le workflow reprenne après approbation)
- **Attend jusqu'à 24 heures** qu'un agent de fraude approuve ou rejette
- L'agent voit une interface web avec les détails
- L'agent clique "Approuver" ou "Rejeter"

**SI approbation timeout (24h dépassées)** :
- → Envoyer notification "Approbation timeout"
- → Fin du workflow (échec)

**SI rejeté par l'agent** :
- → Envoyer notification "Changement rejeté"
- → Fin du workflow (échec)

**SI approuvé par l'agent** :
- → Continuer

#### **Étape 8 : Envoyer SMS de confirmation OTP (Lambda)**

- Génère un code OTP à 6 chiffres (ex: 123456)
- Envoie SMS au **nouveau** numéro avec le code
- Stocke le code OTP dans DynamoDB avec TTL de 5 minutes
- **Retry automatique** si l'envoi SMS échoue (3 tentatives)

#### **Étape 9 : Attendre la validation OTP (Wait + Lambda polling)**

**Option choisie pour BNC : Attente passive**
- Le workflow **attend 5 minutes maximum**
- Pendant ce temps, le client peut :
  - Recevoir le SMS
  - Appeler un endpoint API pour soumettre le code OTP
  - L'endpoint API vérifie le code et met à jour DynamoDB

**Après 5 minutes** :
- Le workflow **vérifie** dans DynamoDB si l'OTP a été validé

**SI OTP non validé après 5 minutes** :
- → Envoyer notification "OTP timeout"
- → Fin du workflow (échec)

**SI OTP validé** :
- → Continuer

#### **Étape 10 : Mettre à jour MDMAE (Master Data Management) (Lambda)**

- Appelle l'API REST de MDMAE
- Envoie le nouveau numéro de téléphone
- MDMAE met à jour dans tous les systèmes centraux
- **Retry automatique** si erreur temporaire (3 tentatives avec backoff exponentiel)
- **SI erreur permanente** → Erreur critique → Compensation

#### **Étape 11 : Synchronisation parallèle dans 3 systèmes (Parallel - 3 branches)**

**Branche 1 : Mettre à jour DynamoDB (direct - pas de Lambda)**
- Écrit directement dans DynamoDB (intégration native Step Functions)
- Table : `ClientProfiles`
- Met à jour le champ `phoneNumber`
- Ajoute `lastPhoneUpdate` timestamp

**Branche 2 : Envoyer notification FCC (Lambda)**
- FCC = système mainframe IBM
- Envoie message via IBM MQ
- Format : XML SOAP
- **Non bloquant** : si ça échoue, on log mais on continue

**Branche 3 : Publier événement MSK Kafka (Lambda)**
- Topic : `client.phone.updated`
- Payload :
  ```json
  {
    "eventType": "PHONE_UPDATE",
    "clientId": "123456789",
    "oldPhone": "+15141234567",
    "newPhone": "+15149876543",
    "timestamp": "2026-09-24T14:30:00Z",
    "approvalRequired": false
  }
  ```
- Autres systèmes BNC abonnés au topic reçoivent l'événement
- **Non bloquant** : si ça échoue, on log mais on continue

**⏱ Durée : Les 3 branches s'exécutent en parallèle**

#### **Étape 12 : Sauvegarder dans l'historique (DynamoDB direct)**

- Écrit dans table `PhoneNumberHistory`
- Partition Key : `clientId`
- Sort Key : `timestamp`
- Données :
  - Ancien numéro
  - Nouveau numéro
  - Raison du changement
  - Approuvé par (si approbation manuelle)
  - Score de suspicion

#### **Étape 13 : Envoyer email de confirmation au client (Lambda)**

- Envoie email via AWS SES
- Contenu :
  - "Votre numéro de téléphone a été mis à jour"
  - Ancien numéro (masqué : +1 (514) ***-**67)
  - Nouveau numéro (masqué : +1 (514) ***-**43)
  - Date et heure de changement
  - Lien "Ce n'est pas moi" pour signaler fraude

#### **Étape 14 : Workflow terminé avec succès**

- État final : SUCCEEDED
- Retour au client (via l'exécution ARN) :
  ```json
  {
    "status": "SUCCESS",
    "oldPhone": "+15141234567",
    "newPhone": "+15149876543",
    "executionId": "arn:aws:states:...",
    "processingTime": "8.3s"
  }
  ```

---

### 📊 Résumé visuel du flow

```
Client → API Gateway → Lambda Controller → Step Functions
                                               ↓
                                    ┌──────────┴──────────┐
                                    │ ReadClientProfile   │
                                    └──────────┬──────────┘
                                               ↓
                                    ┌──────────┴────────────────┐
                                    │ Parallel Validations       │
                                    ├───────────┬────────────────┤
                                    │           │                │
                            ValidatePhone   CheckHistory
                                    │           │
                                    └───────────┴────────────────┘
                                               ↓
                                    ┌──────────┴──────────┐
                                    │ Check Valid?        │
                                    └──────────┬──────────┘
                                          Valid?
                                    ┌──────────┴──────────┐
                                   YES                   NO
                                    ↓                     ↓
                          ┌─────────────────┐    ┌──────────────┐
                          │ Check Suspicious │    │ Send Error   │
                          └─────────┬────────┘    └──────────────┘
                                    ↓
                             Suspicious?
                        ┌────────────┴────────────┐
                       YES                        NO
                        ↓                          ↓
              ┌──────────────────┐      ┌──────────────────┐
              │ Manual Approval  │      │ Send OTP SMS     │
              │ (Wait 24h)       │      └─────────┬────────┘
              └─────────┬────────┘                ↓
                        ↓                  ┌──────────────────┐
                  Approved?                │ Wait 5 min       │
                ┌───────┴───────┐         └─────────┬────────┘
               YES              NO                   ↓
                ↓               ↓            ┌──────────────────┐
                │          Rejected          │ Check OTP Valid? │
                │               ↓            └─────────┬────────┘
                └───────────────┼────────────────Valid?┘
                                ↓                      ↓
                       ┌────────────────┐    ┌──────────────────┐
                       │ Update MDMAE   │    │ OTP Timeout      │
                       └────────┬───────┘    └──────────────────┘
                                ↓
                    ┌───────────┴────────────────────┐
                    │ Parallel Synchronization       │
                    ├───────────┬──────────┬─────────┤
                    │           │          │         │
                DynamoDB      FCC      MSK Kafka
                    │           │          │
                    └───────────┴──────────┴─────────┘
                                ↓
                       ┌────────────────┐
                       │ Save History   │
                       └────────┬───────┘
                                ↓
                       ┌────────────────┐
                       │ Send Email     │
                       └────────┬───────┘
                                ↓
                       ┌────────────────┐
                       │    SUCCESS     │
                       └────────────────┘
```

---

### 🔢 Statistiques du workflow

- **Nombre d'états** : 18 états
- **Lambdas utilisées** : 7 Lambdas
- **Intégrations natives** : 2 (DynamoDB direct)
- **États parallèles** : 2 (Parallel states)
- **États de décision** : 4 (Choice states)
- **États d'attente** : 2 (Wait states)
- **Retry configurés** : 3 états
- **Catch configurés** : 5 états
- **Durée moyenne** : 8-10 secondes (sans approbation manuelle)
- **Durée max** : 24 heures (avec approbation manuelle)

---

## 🏗️ Flow de création des ressources AWS (Repo Infrastructure)

Avant de traduire en JSON, il faut créer toutes les ressources AWS dans l'ordre via Terraform dans le repo `mcp-infrastructure`.

### 📂 Repository : `mcp-infrastructure`

**Chemin :** `/Users/fabricefoko/Documents/mcp-infrastructure`

---

### 🔢 Ordre de création des ressources

#### **1. Tables DynamoDB** ⚡ (Créer en premier - pas de dépendances)

**Fichier :** `modules/dynamodb/phone_update_tables.tf`

**Ressources à créer :**

**Table 1 : `PhoneNumberHistory`**
```hcl
resource "aws_dynamodb_table" "phone_number_history" {
  name           = "${var.environment}-PhoneNumberHistory"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "clientId"
  range_key      = "timestamp"

  attribute {
    name = "clientId"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "N"
  }

  ttl {
    attribute_name = "expiresAt"
    enabled        = true
  }

  tags = {
    Name        = "${var.environment}-PhoneNumberHistory"
    Environment = var.environment
    Purpose     = "Store phone number change history"
  }
}
```

**Table 2 : `OTPCodes`**
```hcl
resource "aws_dynamodb_table" "otp_codes" {
  name           = "${var.environment}-OTPCodes"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "clientId"
  range_key      = "phoneNumber"

  attribute {
    name = "clientId"
    type = "S"
  }

  attribute {
    name = "phoneNumber"
    type = "S"
  }

  ttl {
    attribute_name = "expiresAt"
    enabled        = true
  }

  tags = {
    Name        = "${var.environment}-OTPCodes"
    Environment = var.environment
    Purpose     = "Store OTP codes for phone verification"
  }
}
```

**Outputs :**
```hcl
output "phone_history_table_name" {
  value = aws_dynamodb_table.phone_number_history.name
}

output "phone_history_table_arn" {
  value = aws_dynamodb_table.phone_number_history.arn
}

output "otp_table_name" {
  value = aws_dynamodb_table.otp_codes.name
}

output "otp_table_arn" {
  value = aws_dynamodb_table.otp_codes.arn
}
```

---

#### **2. SQS Queue** 📨 (Créer en deuxième - pas de dépendances)

**Fichier :** `modules/sqs/fraud_review_queue.tf`

**Ressources à créer :**

**Dead Letter Queue :**
```hcl
resource "aws_sqs_queue" "fraud_review_dlq" {
  name                      = "${var.environment}-fraud-review-dlq"
  message_retention_seconds = 1209600  # 14 days

  tags = {
    Name        = "${var.environment}-fraud-review-dlq"
    Environment = var.environment
  }
}
```

**Main Queue :**
```hcl
resource "aws_sqs_queue" "fraud_review_queue" {
  name                       = "${var.environment}-fraud-review-queue"
  delay_seconds              = 0
  max_message_size           = 262144
  message_retention_seconds  = 86400  # 1 day
  receive_wait_time_seconds  = 10
  visibility_timeout_seconds = 300    # 5 minutes

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.fraud_review_dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    Name        = "${var.environment}-fraud-review-queue"
    Environment = var.environment
    Purpose     = "Manual fraud review for phone updates"
  }
}
```

**Outputs :**
```hcl
output "fraud_queue_url" {
  value = aws_sqs_queue.fraud_review_queue.url
}

output "fraud_queue_arn" {
  value = aws_sqs_queue.fraud_review_queue.arn
}
```

---

#### **3. IAM Roles** 🔐 (Créer en troisième - avant Lambdas et Step Functions)

**Fichier :** `modules/iam/phone_update_roles.tf`

**Ressources à créer :**

**Role 1 : Lambda Execution Role**
```hcl
resource "aws_iam_role" "phone_update_lambda_role" {
  name = "${var.environment}-phone-update-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.phone_update_lambda_role.name
}

resource "aws_iam_role_policy" "lambda_dynamodb_policy" {
  name = "${var.environment}-lambda-dynamodb-policy"
  role = aws_iam_role.phone_update_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.phone_number_history.arn,
          aws_dynamodb_table.otp_codes.arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_sns_policy" {
  name = "${var.environment}-lambda-sns-policy"
  role = aws_iam_role.phone_update_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = "*"
      }
    ]
  })
}
```

**Role 2 : Step Functions Execution Role**
```hcl
resource "aws_iam_role" "phone_update_sfn_role" {
  name = "${var.environment}-phone-update-sfn-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "sfn_lambda_invoke" {
  name = "${var.environment}-sfn-lambda-invoke"
  role = aws_iam_role.phone_update_sfn_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${var.environment}-mcp-*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "sfn_dynamodb_access" {
  name = "${var.environment}-sfn-dynamodb-access"
  role = aws_iam_role.phone_update_sfn_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem"
        ]
        Resource = [
          aws_dynamodb_table.phone_number_history.arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "sfn_sqs_sendmessage" {
  name = "${var.environment}-sfn-sqs-sendmessage"
  role = aws_iam_role.phone_update_sfn_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage"
        ]
        Resource = aws_sqs_queue.fraud_review_queue.arn
      }
    ]
  })
}
```

**Outputs :**
```hcl
output "lambda_role_arn" {
  value = aws_iam_role.phone_update_lambda_role.arn
}

output "sfn_role_arn" {
  value = aws_iam_role.phone_update_sfn_role.arn
}
```

---

#### **4. Lambda Functions** 🔧 (Créer en quatrième - dépend des IAM roles)

**Fichier :** `modules/lambda/phone_update_lambdas.tf`

**Ressources à créer (7 Lambdas) :**

```hcl
# Lambda 1: Phone Update Controller
resource "aws_lambda_function" "phone_update_controller" {
  function_name = "${var.environment}-mcp-phone-update-controller"
  role          = aws_iam_role.phone_update_lambda_role.arn
  handler       = "com.bnc.mcp.controllers.ClientPhoneUpdateController::handleRequest"
  runtime       = "java17"
  timeout       = 30
  memory_size   = 512

  s3_bucket = var.lambda_code_bucket
  s3_key    = "phone-update/client-phone-update-controller-${var.code_version}.jar"

  environment {
    variables = {
      ENVIRONMENT         = var.environment
      STATE_MACHINE_ARN   = aws_sfn_state_machine.phone_update_workflow.arn
      REGION              = var.aws_region
    }
  }

  tags = {
    Name        = "${var.environment}-mcp-phone-update-controller"
    Environment = var.environment
  }
}

# Lambda 2: Phone Validator
resource "aws_lambda_function" "phone_validator" {
  function_name = "${var.environment}-mcp-phone-validator"
  role          = aws_iam_role.phone_update_lambda_role.arn
  handler       = "com.bnc.mcp.handlers.PhoneValidatorHandler::handleRequest"
  runtime       = "java17"
  timeout       = 10
  memory_size   = 256

  s3_bucket = var.lambda_code_bucket
  s3_key    = "phone-update/phone-validator-${var.code_version}.jar"

  environment {
    variables = {
      ENVIRONMENT = var.environment
    }
  }

  tags = {
    Name        = "${var.environment}-mcp-phone-validator"
    Environment = var.environment
  }
}

# Lambda 3: Check Phone History
resource "aws_lambda_function" "check_phone_history" {
  function_name = "${var.environment}-mcp-check-phone-history"
  role          = aws_iam_role.phone_update_lambda_role.arn
  handler       = "com.bnc.mcp.handlers.CheckPhoneHistoryHandler::handleRequest"
  runtime       = "java17"
  timeout       = 15
  memory_size   = 256

  s3_bucket = var.lambda_code_bucket
  s3_key    = "phone-update/check-phone-history-${var.code_version}.jar"

  environment {
    variables = {
      ENVIRONMENT          = var.environment
      PHONE_HISTORY_TABLE  = aws_dynamodb_table.phone_number_history.name
    }
  }

  tags = {
    Name        = "${var.environment}-mcp-check-phone-history"
    Environment = var.environment
  }
}

# Lambda 4: Send OTP SMS
resource "aws_lambda_function" "send_otp_sms" {
  function_name = "${var.environment}-mcp-send-otp-sms"
  role          = aws_iam_role.phone_update_lambda_role.arn
  handler       = "com.bnc.mcp.handlers.SendOTPSMSHandler::handleRequest"
  runtime       = "java17"
  timeout       = 10
  memory_size   = 256

  s3_bucket = var.lambda_code_bucket
  s3_key    = "phone-update/send-otp-sms-${var.code_version}.jar"

  environment {
    variables = {
      ENVIRONMENT = var.environment
      OTP_TABLE   = aws_dynamodb_table.otp_codes.name
    }
  }

  tags = {
    Name        = "${var.environment}-mcp-send-otp-sms"
    Environment = var.environment
  }
}

# Lambda 5: Check OTP Status
resource "aws_lambda_function" "check_otp_status" {
  function_name = "${var.environment}-mcp-check-otp-status"
  role          = aws_iam_role.phone_update_lambda_role.arn
  handler       = "com.bnc.mcp.handlers.CheckOTPStatusHandler::handleRequest"
  runtime       = "java17"
  timeout       = 10
  memory_size   = 256

  s3_bucket = var.lambda_code_bucket
  s3_key    = "phone-update/check-otp-status-${var.code_version}.jar"

  environment {
    variables = {
      ENVIRONMENT = var.environment
      OTP_TABLE   = aws_dynamodb_table.otp_codes.name
    }
  }

  tags = {
    Name        = "${var.environment}-mcp-check-otp-status"
    Environment = var.environment
  }
}

# Lambda 6: Phone MDMAE Client
resource "aws_lambda_function" "phone_mdmae_client" {
  function_name = "${var.environment}-mcp-phone-mdmae-client"
  role          = aws_iam_role.phone_update_lambda_role.arn
  handler       = "com.bnc.mcp.handlers.PhoneMDMAEClientHandler::handleRequest"
  runtime       = "java17"
  timeout       = 30
  memory_size   = 512

  s3_bucket = var.lambda_code_bucket
  s3_key    = "phone-update/phone-mdmae-client-${var.code_version}.jar"

  environment {
    variables = {
      ENVIRONMENT      = var.environment
      MDMAE_API_URL    = var.mdmae_api_url
      MDMAE_API_KEY    = var.mdmae_api_key
    }
  }

  tags = {
    Name        = "${var.environment}-mcp-phone-mdmae-client"
    Environment = var.environment
  }
}

# Lambda 7: Read Client Profile
resource "aws_lambda_function" "read_client_profile" {
  function_name = "${var.environment}-mcp-read-client-profile"
  role          = aws_iam_role.phone_update_lambda_role.arn
  handler       = "com.bnc.mcp.handlers.ReadClientProfileHandler::handleRequest"
  runtime       = "java17"
  timeout       = 10
  memory_size   = 256

  s3_bucket = var.lambda_code_bucket
  s3_key    = "phone-update/read-client-profile-${var.code_version}.jar"

  environment {
    variables = {
      ENVIRONMENT         = var.environment
      CLIENT_PROFILE_TABLE = var.client_profile_table_name
    }
  }

  tags = {
    Name        = "${var.environment}-mcp-read-client-profile"
    Environment = var.environment
  }
}
```

**Outputs :**
```hcl
output "lambda_arns" {
  value = {
    controller           = aws_lambda_function.phone_update_controller.arn
    phone_validator      = aws_lambda_function.phone_validator.arn
    check_phone_history  = aws_lambda_function.check_phone_history.arn
    send_otp_sms         = aws_lambda_function.send_otp_sms.arn
    check_otp_status     = aws_lambda_function.check_otp_status.arn
    phone_mdmae_client   = aws_lambda_function.phone_mdmae_client.arn
    read_client_profile  = aws_lambda_function.read_client_profile.arn
  }
}
```

---

#### **5. Step Functions State Machine** 🔀 (Créer en cinquième - dépend des Lambdas, DynamoDB, SQS, IAM)

**Fichier :** `modules/step_functions/state_machines/client-phone-update.json.tpl`

C'est le fichier JSON du workflow (voir section suivante pour le contenu complet).

**Fichier Terraform :** `modules/step_functions/phone_update.tf`

```hcl
resource "aws_sfn_state_machine" "phone_update_workflow" {
  name     = "${var.environment}-mcp-client-phone-update"
  role_arn = aws_iam_role.phone_update_sfn_role.arn

  definition = templatefile("${path.module}/state_machines/client-phone-update.json.tpl", {
    # Lambda ARNs
    read_client_profile_arn  = aws_lambda_function.read_client_profile.arn
    phone_validator_arn      = aws_lambda_function.phone_validator.arn
    check_phone_history_arn  = aws_lambda_function.check_phone_history.arn
    send_otp_sms_arn         = aws_lambda_function.send_otp_sms.arn
    check_otp_status_arn     = aws_lambda_function.check_otp_status.arn
    phone_mdmae_client_arn   = aws_lambda_function.phone_mdmae_client.arn

    # DynamoDB Tables
    phone_history_table_name = aws_dynamodb_table.phone_number_history.name

    # SQS Queue
    fraud_queue_url          = aws_sqs_queue.fraud_review_queue.url

    # Config
    environment              = var.environment
    region                   = var.aws_region
  })

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.sfn_logs.arn}:*"
    include_execution_data = true
    level                  = "ALL"
  }

  tags = {
    Name        = "${var.environment}-mcp-client-phone-update"
    Environment = var.environment
    Purpose     = "Phone number update workflow"
  }
}

resource "aws_cloudwatch_log_group" "sfn_logs" {
  name              = "/aws/states/${var.environment}-mcp-client-phone-update"
  retention_in_days = 30

  tags = {
    Name        = "${var.environment}-phone-update-sfn-logs"
    Environment = var.environment
  }
}
```

**Outputs :**
```hcl
output "state_machine_arn" {
  value = aws_sfn_state_machine.phone_update_workflow.arn
}

output "state_machine_name" {
  value = aws_sfn_state_machine.phone_update_workflow.name
}
```

---

#### **6. API Gateway** 🌐 (Créer en sixième - dépend du Lambda Controller)

**Fichier :** `modules/api_gateway/phone_update_endpoint.tf`

```hcl
# API Gateway REST API (assume already exists)
data "aws_api_gateway_rest_api" "mcp_api" {
  name = "${var.environment}-mcp-api"
}

# Get the /clients/{clientId} resource
data "aws_api_gateway_resource" "clients_resource" {
  rest_api_id = data.aws_api_gateway_rest_api.mcp_api.id
  path        = "/clients/{clientId}"
}

# Create /phone resource under /clients/{clientId}
resource "aws_api_gateway_resource" "phone" {
  rest_api_id = data.aws_api_gateway_rest_api.mcp_api.id
  parent_id   = data.aws_api_gateway_resource.clients_resource.id
  path_part   = "phone"
}

# PUT method
resource "aws_api_gateway_method" "put_phone" {
  rest_api_id   = data.aws_api_gateway_rest_api.mcp_api.id
  resource_id   = aws_api_gateway_resource.phone.id
  http_method   = "PUT"
  authorization = "AWS_IAM"
}

# Lambda integration
resource "aws_api_gateway_integration" "put_phone_lambda" {
  rest_api_id             = data.aws_api_gateway_rest_api.mcp_api.id
  resource_id             = aws_api_gateway_resource.phone.id
  http_method             = aws_api_gateway_method.put_phone.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.phone_update_controller.invoke_arn
}

# Lambda permission
resource "aws_lambda_permission" "apigw_phone_update" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.phone_update_controller.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${data.aws_api_gateway_rest_api.mcp_api.execution_arn}/*/*"
}

# Deploy API
resource "aws_api_gateway_deployment" "phone_update" {
  rest_api_id = data.aws_api_gateway_rest_api.mcp_api.id
  stage_name  = var.environment

  depends_on = [
    aws_api_gateway_integration.put_phone_lambda
  ]

  lifecycle {
    create_before_destroy = true
  }
}
```

**Outputs :**
```hcl
output "api_endpoint" {
  value = "${data.aws_api_gateway_rest_api.mcp_api.execution_arn}/${var.environment}/clients/{clientId}/phone"
}
```

---

#### **7. CloudWatch Alarms** 📊 (Créer en dernier - pour monitoring)

**Fichier :** `modules/cloudwatch/phone_update_alarms.tf`

```hcl
# Step Functions failure alarm
resource "aws_cloudwatch_metric_alarm" "sfn_failures" {
  alarm_name          = "${var.environment}-phone-update-sfn-failures"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ExecutionsFailed"
  namespace           = "AWS/States"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "Phone update workflow has too many failures"
  alarm_actions       = [var.sns_alert_topic_arn]

  dimensions = {
    StateMachineArn = aws_sfn_state_machine.phone_update_workflow.arn
  }
}

# Lambda errors alarm
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.environment}-phone-validator-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "Phone validator Lambda has too many errors"
  alarm_actions       = [var.sns_alert_topic_arn]

  dimensions = {
    FunctionName = aws_lambda_function.phone_validator.function_name
  }
}
```

---

### 📝 Ordre final résumé

```
1. ✅ DynamoDB Tables
   ├── PhoneNumberHistory
   └── OTPCodes

2. ✅ SQS Queue
   ├── fraud-review-queue
   └── fraud-review-dlq

3. ✅ IAM Roles
   ├── Lambda Execution Role
   └── Step Functions Execution Role

4. ✅ Lambda Functions (7)
   ├── phone-update-controller
   ├── phone-validator
   ├── check-phone-history
   ├── send-otp-sms
   ├── check-otp-status
   ├── phone-mdmae-client
   └── read-client-profile

5. ✅ Step Functions State Machine
   └── client-phone-update (définition JSON)

6. ✅ API Gateway
   └── PUT /clients/{clientId}/phone

7. ✅ CloudWatch Alarms
   ├── SFN failures alarm
   └── Lambda errors alarm
```

---

### 🚀 Commandes de déploiement

```bash
# 1. Aller dans le repo infrastructure
cd /Users/fabricefoko/Documents/mcp-infrastructure

# 2. Aller dans l'environnement dev
cd environments/dev

# 3. Initialiser Terraform (première fois)
terraform init

# 4. Voir le plan de déploiement
terraform plan

# 5. Déployer toutes les ressources
terraform apply

# 6. Vérifier les outputs
terraform output
```

**Résultat attendu :**
```
phone_history_table_name = "dev-PhoneNumberHistory"
otp_table_name = "dev-OTPCodes"
fraud_queue_url = "https://sqs.ca-central-1.amazonaws.com/123/dev-fraud-review-queue"
state_machine_arn = "arn:aws:states:ca-central-1:123:stateMachine:dev-mcp-client-phone-update"
api_endpoint = "https://abc123.execute-api.ca-central-1.amazonaws.com/dev/clients/{clientId}/phone"
```

---

## Traduction en Step Functions JSON

### Fichier : `client-phone-update.json`

```json
{
  "Comment": "Workflow de mise à jour du numéro de téléphone - Banque Nationale du Canada",
  "StartAt": "ReadClientProfile",
  "TimeoutSeconds": 86400,
  "States": {

    "ReadClientProfile": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:ca-central-1:123456789:function:${env}-mcp-client-profile-reader",
      "Comment": "Lit le profil client actuel depuis DynamoDB",
      "TimeoutSeconds": 10,
      "ResultPath": "$.currentProfile",
      "Retry": [
        {
          "ErrorEquals": ["States.TaskFailed"],
          "IntervalSeconds": 1,
          "MaxAttempts": 2,
          "BackoffRate": 2.0
        }
      ],
      "Catch": [
        {
          "ErrorEquals": ["ClientNotFoundException"],
          "ResultPath": "$.error",
          "Next": "ClientNotFoundError"
        },
        {
          "ErrorEquals": ["States.ALL"],
          "ResultPath": "$.error",
          "Next": "HandleGenericError"
        }
      ],
      "Next": "ParallelValidations"
    },

    "ParallelValidations": {
      "Type": "Parallel",
      "Comment": "Exécute validation téléphone et vérification historique en parallèle",
      "Branches": [
        {
          "StartAt": "ValidatePhoneNumber",
          "States": {
            "ValidatePhoneNumber": {
              "Type": "Task",
              "Resource": "arn:aws:lambda:ca-central-1:123456789:function:${env}-mcp-phone-validator",
              "Comment": "Valide le format et la légitimité du numéro de téléphone",
              "TimeoutSeconds": 10,
              "Parameters": {
                "phoneNumber.$": "$.phoneNumber",
                "country.$": "$.country",
                "clientId.$": "$.clientId"
              },
              "Retry": [
                {
                  "ErrorEquals": ["States.TaskFailed"],
                  "IntervalSeconds": 2,
                  "MaxAttempts": 2,
                  "BackoffRate": 2.0
                }
              ],
              "End": true
            }
          }
        },
        {
          "StartAt": "CheckPhoneHistory",
          "States": {
            "CheckPhoneHistory": {
              "Type": "Task",
              "Resource": "arn:aws:lambda:ca-central-1:123456789:function:${env}-mcp-check-phone-history",
              "Comment": "Vérifie l'historique des changements de téléphone pour détecter fraude",
              "TimeoutSeconds": 15,
              "Parameters": {
                "clientId.$": "$.clientId",
                "newPhoneNumber.$": "$.phoneNumber",
                "currentPhoneNumber.$": "$.currentProfile.phoneNumber"
              },
              "End": true
            }
          }
        }
      ],
      "ResultPath": "$.validationResults",
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "ResultPath": "$.error",
          "Next": "HandleValidationError"
        }
      ],
      "Next": "CheckValidationResults"
    },

    "CheckValidationResults": {
      "Type": "Choice",
      "Comment": "Vérifie si la validation du format a réussi",
      "Choices": [
        {
          "Variable": "$.validationResults[0].isValid",
          "BooleanEquals": false,
          "Next": "ValidationFailedNotification"
        }
      ],
      "Default": "EvaluateSuspiciousScore"
    },

    "EvaluateSuspiciousScore": {
      "Type": "Choice",
      "Comment": "Décide si le changement nécessite approbation manuelle",
      "Choices": [
        {
          "Variable": "$.validationResults[1].suspiciousScore",
          "NumericGreaterThan": 0.8,
          "Comment": "Score > 0.8 = très suspect",
          "Next": "RequireManualApproval"
        },
        {
          "And": [
            {
              "Variable": "$.validationResults[1].suspiciousScore",
              "NumericGreaterThan": 0.5
            },
            {
              "Variable": "$.validationResults[1].changeCount",
              "NumericGreaterThan": 3
            }
          ],
          "Comment": "Score > 0.5 ET plus de 3 changements récents",
          "Next": "RequireManualApproval"
        }
      ],
      "Default": "SendOTPSMS"
    },

    "RequireManualApproval": {
      "Type": "Task",
      "Resource": "arn:aws:states:::sqs:sendMessage.waitForTaskToken",
      "Comment": "Envoie notification à l'équipe fraude avec task token pour approbation",
      "Parameters": {
        "QueueUrl": "${fraud_review_queue_url}",
        "MessageBody": {
          "taskToken.$": "$$.Task.Token",
          "clientId.$": "$.clientId",
          "currentPhone.$": "$.currentProfile.phoneNumber",
          "newPhone.$": "$.phoneNumber",
          "suspiciousScore.$": "$.validationResults[1].suspiciousScore",
          "reason.$": "$.validationResults[1].reason",
          "changeHistory.$": "$.validationResults[1].history",
          "executionId.$": "$$.Execution.Id",
          "requestId.$": "$.requestId",
          "timestamp.$": "$$.State.EnteredTime"
        }
      },
      "TimeoutSeconds": 86400,
      "ResultPath": "$.approvalResult",
      "Catch": [
        {
          "ErrorEquals": ["States.Timeout"],
          "ResultPath": "$.error",
          "Next": "ApprovalTimeoutNotification"
        }
      ],
      "Next": "CheckApprovalDecision"
    },

    "CheckApprovalDecision": {
      "Type": "Choice",
      "Comment": "Vérifie la décision de l'approbateur",
      "Choices": [
        {
          "Variable": "$.approvalResult.decision",
          "StringEquals": "APPROVED",
          "Next": "SendOTPSMS"
        },
        {
          "Variable": "$.approvalResult.decision",
          "StringEquals": "REJECTED",
          "Next": "ApprovalRejectedNotification"
        }
      ],
      "Default": "HandleGenericError"
    },

    "SendOTPSMS": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:ca-central-1:123456789:function:${env}-mcp-send-otp-sms",
      "Comment": "Envoie un code OTP à 6 chiffres au nouveau numéro de téléphone",
      "TimeoutSeconds": 15,
      "Parameters": {
        "phoneNumber.$": "$.phoneNumber",
        "clientId.$": "$.clientId",
        "executionId.$": "$$.Execution.Id"
      },
      "ResultPath": "$.otpResult",
      "Retry": [
        {
          "ErrorEquals": ["SMSDeliveryException", "States.TaskFailed"],
          "IntervalSeconds": 3,
          "MaxAttempts": 3,
          "BackoffRate": 2.0
        }
      ],
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "ResultPath": "$.error",
          "Next": "OTPSendFailedNotification"
        }
      ],
      "Next": "WaitForOTPValidation"
    },

    "WaitForOTPValidation": {
      "Type": "Wait",
      "Comment": "Attend 5 minutes que le client valide l'OTP",
      "Seconds": 300,
      "Next": "CheckOTPValidated"
    },

    "CheckOTPValidated": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:ca-central-1:123456789:function:${env}-mcp-check-otp-status",
      "Comment": "Vérifie si l'OTP a été validé par le client dans les 5 minutes",
      "TimeoutSeconds": 10,
      "Parameters": {
        "clientId.$": "$.clientId",
        "executionId.$": "$$.Execution.Id"
      },
      "ResultPath": "$.otpCheckResult",
      "Next": "EvaluateOTPStatus"
    },

    "EvaluateOTPStatus": {
      "Type": "Choice",
      "Comment": "Décide si l'OTP a été validé ou si timeout",
      "Choices": [
        {
          "Variable": "$.otpCheckResult.isValidated",
          "BooleanEquals": true,
          "Next": "UpdateMDMAE"
        }
      ],
      "Default": "OTPTimeoutNotification"
    },

    "UpdateMDMAE": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:ca-central-1:123456789:function:${env}-mcp-phone-mdmae-client",
      "Comment": "Met à jour le numéro de téléphone dans MDMAE (Master Data Management)",
      "TimeoutSeconds": 30,
      "Parameters": {
        "clientId.$": "$.clientId",
        "oldPhoneNumber.$": "$.currentProfile.phoneNumber",
        "newPhoneNumber.$": "$.validationResults[0].normalizedPhone",
        "updatedBy.$": "$.metadata.userId",
        "approvalRequired.$": "$.approvalResult.decision",
        "approvedBy.$": "$.approvalResult.reviewerName"
      },
      "ResultPath": "$.mdmaeResult",
      "Retry": [
        {
          "ErrorEquals": ["MDMAETemporaryError", "States.TaskFailed"],
          "IntervalSeconds": 5,
          "MaxAttempts": 3,
          "BackoffRate": 2.0
        }
      ],
      "Catch": [
        {
          "ErrorEquals": ["MDMAEPermanentError"],
          "ResultPath": "$.error",
          "Next": "MDMAEUpdateFailedNotification"
        },
        {
          "ErrorEquals": ["States.ALL"],
          "ResultPath": "$.error",
          "Next": "HandleGenericError"
        }
      ],
      "Next": "ParallelSynchronization"
    },

    "ParallelSynchronization": {
      "Type": "Parallel",
      "Comment": "Synchronise le nouveau numéro dans tous les systèmes en parallèle",
      "Branches": [
        {
          "StartAt": "UpdateDynamoDB",
          "States": {
            "UpdateDynamoDB": {
              "Type": "Task",
              "Resource": "arn:aws:states:::dynamodb:updateItem",
              "Comment": "Met à jour DynamoDB directement (intégration native)",
              "Parameters": {
                "TableName": "${dynamodb_table_name}",
                "Key": {
                  "PK": {
                    "S.$": "$.clientId"
                  },
                  "SK": {
                    "S": "PROFILE"
                  }
                },
                "UpdateExpression": "SET phoneNumber = :newPhone, lastPhoneUpdate = :timestamp, updatedBy = :userId",
                "ExpressionAttributeValues": {
                  ":newPhone": {
                    "S.$": "$.validationResults[0].normalizedPhone"
                  },
                  ":timestamp": {
                    "S.$": "$$.State.EnteredTime"
                  },
                  ":userId": {
                    "S.$": "$.metadata.userId"
                  }
                }
              },
              "End": true
            }
          }
        },
        {
          "StartAt": "SendFCCNotification",
          "States": {
            "SendFCCNotification": {
              "Type": "Task",
              "Resource": "arn:aws:lambda:ca-central-1:123456789:function:${env}-mcp-fcc-sender",
              "Comment": "Envoie notification au mainframe FCC via IBM MQ (non-bloquant)",
              "TimeoutSeconds": 20,
              "Parameters": {
                "eventType": "PHONE_UPDATE",
                "clientId.$": "$.clientId",
                "newPhone.$": "$.validationResults[0].normalizedPhone"
              },
              "Retry": [
                {
                  "ErrorEquals": ["States.TaskFailed"],
                  "IntervalSeconds": 3,
                  "MaxAttempts": 2,
                  "BackoffRate": 2.0
                }
              ],
              "Catch": [
                {
                  "ErrorEquals": ["States.ALL"],
                  "ResultPath": "$.fccError",
                  "Next": "LogFCCError"
                }
              ],
              "End": true
            },
            "LogFCCError": {
              "Type": "Pass",
              "Comment": "Log FCC error but continue (non-blocking)",
              "Result": {
                "fccStatus": "FAILED_NON_BLOCKING"
              },
              "End": true
            }
          }
        },
        {
          "StartAt": "PublishToMSK",
          "States": {
            "PublishToMSK": {
              "Type": "Task",
              "Resource": "arn:aws:lambda:ca-central-1:123456789:function:${env}-mcp-publish-to-msk",
              "Comment": "Publie événement dans MSK Kafka pour systèmes abonnés (non-bloquant)",
              "TimeoutSeconds": 10,
              "Parameters": {
                "topic": "client.phone.updated",
                "eventType": "PHONE_UPDATE",
                "payload": {
                  "clientId.$": "$.clientId",
                  "oldPhone.$": "$.currentProfile.phoneNumber",
                  "newPhone.$": "$.validationResults[0].normalizedPhone",
                  "timestamp.$": "$$.State.EnteredTime",
                  "approvalRequired.$": "$.approvalResult.decision",
                  "executionId.$": "$$.Execution.Id"
                }
              },
              "Catch": [
                {
                  "ErrorEquals": ["States.ALL"],
                  "ResultPath": "$.mskError",
                  "Next": "LogMSKError"
                }
              ],
              "End": true
            },
            "LogMSKError": {
              "Type": "Pass",
              "Comment": "Log MSK error but continue (non-blocking)",
              "Result": {
                "mskStatus": "FAILED_NON_BLOCKING"
              },
              "End": true
            }
          }
        }
      ],
      "ResultPath": "$.syncResults",
      "Next": "SavePhoneHistory"
    },

    "SavePhoneHistory": {
      "Type": "Task",
      "Resource": "arn:aws:states:::dynamodb:putItem",
      "Comment": "Sauvegarde dans l'historique des numéros de téléphone (intégration native DynamoDB)",
      "Parameters": {
        "TableName": "${phone_history_table_name}",
        "Item": {
          "PK": {
            "S.$": "$.clientId"
          },
          "SK": {
            "S.$": "$$.Execution.StartTime"
          },
          "oldPhoneNumber": {
            "S.$": "$.currentProfile.phoneNumber"
          },
          "newPhoneNumber": {
            "S.$": "$.validationResults[0].normalizedPhone"
          },
          "changeReason": {
            "S": "CLIENT_REQUEST"
          },
          "suspiciousScore": {
            "N.$": "States.Format('{}', $.validationResults[1].suspiciousScore)"
          },
          "approvalRequired": {
            "BOOL.$": "States.StringToJson(States.Format('{}', $.approvalResult.decision == 'APPROVED'))"
          },
          "approvedBy": {
            "S.$": "$.approvalResult.reviewerName"
          },
          "updatedBy": {
            "S.$": "$.metadata.userId"
          },
          "timestamp": {
            "S.$": "$$.Execution.StartTime"
          },
          "executionId": {
            "S.$": "$$.Execution.Id"
          },
          "requestId": {
            "S.$": "$.requestId"
          }
        }
      },
      "ResultPath": "$.historyResult",
      "Next": "SendConfirmationEmail"
    },

    "SendConfirmationEmail": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:ca-central-1:123456789:function:${env}-mcp-send-email",
      "Comment": "Envoie email de confirmation au client",
      "TimeoutSeconds": 10,
      "Parameters": {
        "emailType": "PHONE_UPDATE_CONFIRMATION",
        "clientId.$": "$.clientId",
        "clientEmail.$": "$.currentProfile.email",
        "oldPhone.$": "$.currentProfile.phoneNumber",
        "newPhone.$": "$.validationResults[0].normalizedPhone",
        "timestamp.$": "$$.State.EnteredTime"
      },
      "ResultPath": "$.emailResult",
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "ResultPath": "$.emailError",
          "Next": "LogEmailError"
        }
      ],
      "Next": "WorkflowSuccessful"
    },

    "LogEmailError": {
      "Type": "Pass",
      "Comment": "Log email error but consider workflow successful",
      "Result": {
        "emailStatus": "FAILED_NON_BLOCKING"
      },
      "ResultPath": "$.emailResult",
      "Next": "WorkflowSuccessful"
    },

    "WorkflowSuccessful": {
      "Type": "Succeed",
      "Comment": "Workflow terminé avec succès"
    },

    "ClientNotFoundError": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:ca-central-1:123456789:function:${env}-mcp-send-notification",
      "Parameters": {
        "notificationType": "CLIENT_NOT_FOUND",
        "clientId.$": "$.clientId",
        "error.$": "$.error",
        "executionId.$": "$$.Execution.Id"
      },
      "Next": "WorkflowFailed"
    },

    "ValidationFailedNotification": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:ca-central-1:123456789:function:${env}-mcp-send-notification",
      "Parameters": {
        "notificationType": "PHONE_VALIDATION_FAILED",
        "clientId.$": "$.clientId",
        "phoneNumber.$": "$.phoneNumber",
        "validationErrors.$": "$.validationResults[0].errors",
        "error.$": "$.error"
      },
      "Next": "WorkflowFailed"
    },

    "HandleValidationError": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:ca-central-1:123456789:function:${env}-mcp-send-notification",
      "Parameters": {
        "notificationType": "VALIDATION_PROCESS_ERROR",
        "clientId.$": "$.clientId",
        "error.$": "$.error",
        "executionId.$": "$$.Execution.Id"
      },
      "Next": "WorkflowFailed"
    },

    "ApprovalTimeoutNotification": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:ca-central-1:123456789:function:${env}-mcp-send-notification",
      "Parameters": {
        "notificationType": "APPROVAL_TIMEOUT",
        "clientId.$": "$.clientId",
        "phoneNumber.$": "$.phoneNumber",
        "waitedSeconds": 86400
      },
      "Next": "WorkflowFailed"
    },

    "ApprovalRejectedNotification": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:ca-central-1:123456789:function:${env}-mcp-send-notification",
      "Parameters": {
        "notificationType": "PHONE_CHANGE_REJECTED",
        "clientId.$": "$.clientId",
        "phoneNumber.$": "$.phoneNumber",
        "rejectionReason.$": "$.approvalResult.reason",
        "rejectedBy.$": "$.approvalResult.reviewerName"
      },
      "Next": "WorkflowFailed"
    },

    "OTPSendFailedNotification": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:ca-central-1:123456789:function:${env}-mcp-send-notification",
      "Parameters": {
        "notificationType": "OTP_SEND_FAILED",
        "clientId.$": "$.clientId",
        "phoneNumber.$": "$.phoneNumber",
        "error.$": "$.error"
      },
      "Next": "WorkflowFailed"
    },

    "OTPTimeoutNotification": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:ca-central-1:123456789:function:${env}-mcp-send-notification",
      "Parameters": {
        "notificationType": "OTP_TIMEOUT",
        "clientId.$": "$.clientId",
        "phoneNumber.$": "$.phoneNumber",
        "waitedSeconds": 300
      },
      "Next": "WorkflowFailed"
    },

    "MDMAEUpdateFailedNotification": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:ca-central-1:123456789:function:${env}-mcp-send-notification",
      "Parameters": {
        "notificationType": "MDMAE_UPDATE_FAILED",
        "clientId.$": "$.clientId",
        "phoneNumber.$": "$.phoneNumber",
        "error.$": "$.error"
      },
      "Next": "WorkflowFailed"
    },

    "HandleGenericError": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:ca-central-1:123456789:function:${env}-mcp-send-notification",
      "Parameters": {
        "notificationType": "GENERIC_ERROR",
        "clientId.$": "$.clientId",
        "error.$": "$.error",
        "executionId.$": "$$.Execution.Id"
      },
      "Next": "WorkflowFailed"
    },

    "WorkflowFailed": {
      "Type": "Fail",
      "Comment": "Workflow échoué"
    }

  }
}
```

---

## Flow d'implémentation étape par étape

### 📋 Vue d'ensemble

**Durée totale estimée : 3-4 jours**

- Phase 1 : Infrastructure (mcp-infrastructure) - 4-5 heures
- Phase 2 : Code métier (mcp-local) - 2-3 jours
- Phase 3 : Tests et déploiement - 4-6 heures

---

## PHASE 1 : Infrastructure (mcp-infrastructure)

### ✅ Checklist Phase 1

- [ ] 1. Créer le workflow JSON Step Functions
- [ ] 2. Créer les ressources Terraform Step Functions
- [ ] 3. Créer les ressources Terraform Lambda (placeholders)
- [ ] 4. Créer les tables DynamoDB
- [ ] 5. Créer la SQS queue pour approbation manuelle
- [ ] 6. Configurer IAM roles et permissions
- [ ] 7. Déployer l'infrastructure avec Terraform

---

### Étape 1.1 : Créer le workflow JSON Step Functions

**Repo :** `mcp-infrastructure`

**Fichier à créer :** `modules/step_functions/state_machines/client-phone-update.json.tpl`

**Action :**
```bash
cd /Users/fabricefoko/Documents/mcp-infrastructure
mkdir -p modules/step_functions/state_machines
```

**Contenu :** Copier le JSON complet du workflow ci-dessus dans ce fichier.

**Variables Terraform à remplacer :**
- `${env}` → Environnement (dev, prod)
- `${fraud_review_queue_url}` → URL de la SQS queue
- `${dynamodb_table_name}` → Nom de la table DynamoDB ClientProfiles
- `${phone_history_table_name}` → Nom de la table PhoneNumberHistory

---

### Étape 1.2 : Créer la ressource Terraform Step Functions

**Repo :** `mcp-infrastructure`

**Fichier à créer :** `modules/step_functions/phone_update.tf`

**Contenu :**

```hcl
# modules/step_functions/phone_update.tf

resource "aws_sfn_state_machine" "client_phone_update" {
  name     = "${var.environment}-mcp-client-phone-update"
  role_arn = aws_iam_role.step_functions_execution.arn

  definition = templatefile("${path.module}/state_machines/client-phone-update.json.tpl", {
    env                       = var.environment
    fraud_review_queue_url    = aws_sqs_queue.fraud_review.url
    dynamodb_table_name       = aws_dynamodb_table.client_profiles.name
    phone_history_table_name  = aws_dynamodb_table.phone_history.name
  })

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.step_functions_phone_update.arn}:*"
    include_execution_data = true
    level                  = "ALL"
  }

  tracing_configuration {
    enabled = true
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
    Workflow    = "client-phone-update"
  }
}

# CloudWatch Log Group pour les logs Step Functions
resource "aws_cloudwatch_log_group" "step_functions_phone_update" {
  name              = "/aws/stepfunctions/${var.environment}-mcp-client-phone-update"
  retention_in_days = 30

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# Output : ARN de la State Machine
output "phone_update_state_machine_arn" {
  value       = aws_sfn_state_machine.client_phone_update.arn
  description = "ARN de la State Machine pour mise à jour téléphone"
}
```

---

### Étape 1.3 : Créer les ressources Lambda (placeholders)

**Repo :** `mcp-infrastructure`

**Fichier à modifier :** `modules/lambda/main.tf`

**Ajouter :**

```hcl
# modules/lambda/main.tf

# Lambda Controller - Point d'entrée
resource "aws_lambda_function" "client_phone_update_controller" {
  function_name = "${var.environment}-mcp-client-phone-update-controller"
  role          = aws_iam_role.lambda_execution.arn
  handler       = "com.bnc.mcp.controllers.ClientPhoneUpdateController::handleRequest"
  runtime       = "java17"
  timeout       = 30
  memory_size   = 512

  s3_bucket = var.lambda_artifacts_bucket
  s3_key    = "client-phone-update-controller-1.0.0.jar"

  environment {
    variables = {
      STATE_MACHINE_ARN = var.phone_update_state_machine_arn
      ENVIRONMENT       = var.environment
    }
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# Lambda 1 : Phone Validator
resource "aws_lambda_function" "phone_validator" {
  function_name = "${var.environment}-mcp-phone-validator"
  role          = aws_iam_role.lambda_execution.arn
  handler       = "com.bnc.mcp.handlers.PhoneValidatorHandler::handleRequest"
  runtime       = "java17"
  timeout       = 10
  memory_size   = 256

  s3_bucket = var.lambda_artifacts_bucket
  s3_key    = "phone-validator-1.0.0.jar"

  environment {
    variables = {
      ENVIRONMENT = var.environment
    }
  }
}

# Lambda 2 : Check Phone History
resource "aws_lambda_function" "check_phone_history" {
  function_name = "${var.environment}-mcp-check-phone-history"
  role          = aws_iam_role.lambda_execution.arn
  handler       = "com.bnc.mcp.handlers.CheckPhoneHistoryHandler::handleRequest"
  runtime       = "java17"
  timeout       = 15
  memory_size   = 512

  s3_bucket = var.lambda_artifacts_bucket
  s3_key    = "check-phone-history-1.0.0.jar"

  environment {
    variables = {
      PHONE_HISTORY_TABLE = var.phone_history_table_name
      ENVIRONMENT         = var.environment
    }
  }
}

# Lambda 3 : Send OTP SMS
resource "aws_lambda_function" "send_otp_sms" {
  function_name = "${var.environment}-mcp-send-otp-sms"
  role          = aws_iam_role.lambda_execution.arn
  handler       = "com.bnc.mcp.handlers.SendOTPSMSHandler::handleRequest"
  runtime       = "java17"
  timeout       = 15
  memory_size   = 256

  s3_bucket = var.lambda_artifacts_bucket
  s3_key    = "send-otp-sms-1.0.0.jar"

  environment {
    variables = {
      OTP_TABLE   = var.otp_table_name
      ENVIRONMENT = var.environment
    }
  }
}

# Lambda 4 : Check OTP Status
resource "aws_lambda_function" "check_otp_status" {
  function_name = "${var.environment}-mcp-check-otp-status"
  role          = aws_iam_role.lambda_execution.arn
  handler       = "com.bnc.mcp.handlers.CheckOTPStatusHandler::handleRequest"
  runtime       = "java17"
  timeout       = 10
  memory_size   = 256

  s3_bucket = var.lambda_artifacts_bucket
  s3_key    = "check-otp-status-1.0.0.jar"

  environment {
    variables = {
      OTP_TABLE   = var.otp_table_name
      ENVIRONMENT = var.environment
    }
  }
}

# Lambda 5 : Update MDMAE
resource "aws_lambda_function" "phone_mdmae_client" {
  function_name = "${var.environment}-mcp-phone-mdmae-client"
  role          = aws_iam_role.lambda_execution.arn
  handler       = "com.bnc.mcp.handlers.PhoneMDMAEClientHandler::handleRequest"
  runtime       = "java17"
  timeout       = 30
  memory_size   = 512

  s3_bucket = var.lambda_artifacts_bucket
  s3_key    = "phone-mdmae-client-1.0.0.jar"

  environment {
    variables = {
      MDMAE_API_URL = var.mdmae_api_url
      ENVIRONMENT   = var.environment
    }
  }
}

# Lambda 6 : Send FCC Notification
# (réutilise la Lambda FCC existante)

# Lambda 7 : Publish to MSK
# (réutilise la Lambda MSK existante)

# Lambda 8 : Send Email
# (réutilise la Lambda email existante)

# Lambda 9 : Send Notification
# (réutilise la Lambda notification existante)
```

---

### Étape 1.4 : Créer les tables DynamoDB

**Repo :** `mcp-infrastructure`

**Fichier à créer :** `modules/dynamodb/phone_update_tables.tf`

**Contenu :**

```hcl
# modules/dynamodb/phone_update_tables.tf

# Table : Phone Number History
resource "aws_dynamodb_table" "phone_history" {
  name           = "${var.environment}-mcp-PhoneNumberHistory"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "PK"
  range_key      = "SK"

  attribute {
    name = "PK"
    type = "S"
  }

  attribute {
    name = "SK"
    type = "S"
  }

  ttl {
    attribute_name = "expiresAt"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
    Table       = "PhoneNumberHistory"
  }
}

# Table : OTP Codes (avec TTL 5 minutes)
resource "aws_dynamodb_table" "otp_codes" {
  name           = "${var.environment}-mcp-OTPCodes"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "PK"
  range_key      = "SK"

  attribute {
    name = "PK"
    type = "S"
  }

  attribute {
    name = "SK"
    type = "S"
  }

  ttl {
    attribute_name = "expiresAt"
    enabled        = true
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
    Table       = "OTPCodes"
  }
}

# Outputs
output "phone_history_table_name" {
  value = aws_dynamodb_table.phone_history.name
}

output "otp_table_name" {
  value = aws_dynamodb_table.otp_codes.name
}
```

---

### Étape 1.5 : Créer la SQS queue pour approbation manuelle

**Repo :** `mcp-infrastructure`

**Fichier à créer :** `modules/sqs/fraud_review_queue.tf`

**Contenu :**

```hcl
# modules/sqs/fraud_review_queue.tf

resource "aws_sqs_queue" "fraud_review" {
  name                       = "${var.environment}-mcp-fraud-review-queue"
  delay_seconds              = 0
  max_message_size           = 262144
  message_retention_seconds  = 86400  # 24 heures
  receive_wait_time_seconds  = 10
  visibility_timeout_seconds = 300

  tags = {
    Environment = var.environment
    Project     = var.project_name
    Purpose     = "fraud-review"
  }
}

# Dead Letter Queue
resource "aws_sqs_queue" "fraud_review_dlq" {
  name = "${var.environment}-mcp-fraud-review-dlq"

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# Output
output "fraud_review_queue_url" {
  value = aws_sqs_queue.fraud_review.url
}

output "fraud_review_queue_arn" {
  value = aws_sqs_queue.fraud_review.arn
}
```

---

### Étape 1.6 : Configurer IAM roles et permissions

**Repo :** `mcp-infrastructure`

**Fichier à modifier :** `modules/iam/step_functions_role.tf`

**Ajouter :**

```hcl
# modules/iam/step_functions_role.tf

# Policy pour Step Functions : permettre DynamoDB direct
data "aws_iam_policy_document" "step_functions_dynamodb" {
  statement {
    effect = "Allow"
    actions = [
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:GetItem"
    ]
    resources = [
      var.client_profiles_table_arn,
      var.phone_history_table_arn
    ]
  }
}

resource "aws_iam_policy" "step_functions_dynamodb" {
  name        = "${var.environment}-step-functions-dynamodb-policy"
  description = "Allow Step Functions to write to DynamoDB directly"
  policy      = data.aws_iam_policy_document.step_functions_dynamodb.json
}

resource "aws_iam_role_policy_attachment" "step_functions_dynamodb" {
  role       = aws_iam_role.step_functions_execution.name
  policy_arn = aws_iam_policy.step_functions_dynamodb.arn
}

# Policy pour Step Functions : permettre SQS SendMessage
data "aws_iam_policy_document" "step_functions_sqs" {
  statement {
    effect = "Allow"
    actions = [
      "sqs:SendMessage"
    ]
    resources = [
      var.fraud_review_queue_arn
    ]
  }
}

resource "aws_iam_policy" "step_functions_sqs" {
  name        = "${var.environment}-step-functions-sqs-policy"
  description = "Allow Step Functions to send messages to SQS"
  policy      = data.aws_iam_policy_document.step_functions_sqs.json
}

resource "aws_iam_role_policy_attachment" "step_functions_sqs" {
  role       = aws_iam_role.step_functions_execution.name
  policy_arn = aws_iam_policy.step_functions_sqs.arn
}
```

---

### Étape 1.7 : Créer API Gateway endpoint

**Repo :** `mcp-infrastructure`

**Fichier à modifier :** `modules/api_gateway/endpoints.tf`

**Ajouter :**

```hcl
# modules/api_gateway/endpoints.tf

# Resource: /clients/{clientId}/phone
resource "aws_api_gateway_resource" "client_phone" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.client.id
  path_part   = "phone"
}

# Method: PUT /clients/{clientId}/phone
resource "aws_api_gateway_method" "put_phone" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.client_phone.id
  http_method   = "PUT"
  authorization = "AWS_IAM"
}

# Integration: Lambda Controller
resource "aws_api_gateway_integration" "put_phone_lambda" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.client_phone.id
  http_method             = aws_api_gateway_method.put_phone.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.phone_update_controller_invoke_arn
}

# Lambda permission
resource "aws_lambda_permission" "api_gateway_phone_update" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.phone_update_controller_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}
```

---

### Étape 1.8 : Déployer l'infrastructure

**Repo :** `mcp-infrastructure`

**Actions :**

```bash
cd /Users/fabricefoko/Documents/mcp-infrastructure/environments/dev

# 1. Initialiser Terraform
terraform init

# 2. Planifier les changements
terraform plan

# 3. Vérifier le plan (vérifier que tout est correct)
# Output attendu :
# Plan: 15 to add, 0 to change, 0 to destroy.

# 4. Appliquer
terraform apply

# Confirmer : yes

# 5. Vérifier les outputs
terraform output
```

**Outputs attendus :**
```
phone_update_state_machine_arn = "arn:aws:states:ca-central-1:123:stateMachine:dev-mcp-client-phone-update"
fraud_review_queue_url = "https://sqs.ca-central-1.amazonaws.com/123/dev-mcp-fraud-review-queue"
phone_history_table_name = "dev-mcp-PhoneNumberHistory"
otp_table_name = "dev-mcp-OTPCodes"
api_gateway_url = "https://abc123.execute-api.ca-central-1.amazonaws.com/dev"
```

---

## ✅ Fin de la Phase 1 : Infrastructure déployée

À ce stade :
- ✅ Step Functions State Machine créée
- ✅ Lambdas créées (mais sans code - code placeholder)
- ✅ Tables DynamoDB créées
- ✅ SQS queue créée
- ✅ API Gateway endpoint créé
- ✅ IAM permissions configurées

**Prochaine étape : Implémenter le code métier dans mcp-local**

---

## PHASE 2 : Code métier (mcp-local)

### ✅ Checklist Phase 2

- [ ] 1. Structure du projet Maven
- [ ] 2. Configurer pom.xml avec dépendances
- [ ] 3. Créer le Lambda Controller
- [ ] 4. Créer les 7 Lambdas handlers
- [ ] 5. Créer les modèles (POJOs)
- [ ] 6. Créer les validators
- [ ] 7. Créer les services
- [ ] 8. Créer les clients (MDMAE, SMS, etc.)
- [ ] 9. Créer les utils
- [ ] 10. Créer les tests unitaires
- [ ] 11. Build et déploiement

---

### Étape 2.1 : Structure du projet

**Repo :** `mcp-local`

**Structure complète à créer :**

```
mcp-local/
├── pom.xml
├── src/
│   ├── main/
│   │   ├── java/
│   │   │   └── com/
│   │   │       └── bnc/
│   │   │           └── mcp/
│   │   │               ├── controllers/
│   │   │               │   └── ClientPhoneUpdateController.java
│   │   │               ├── handlers/
│   │   │               │   ├── PhoneValidatorHandler.java
│   │   │               │   ├── CheckPhoneHistoryHandler.java
│   │   │               │   ├── SendOTPSMSHandler.java
│   │   │               │   ├── CheckOTPStatusHandler.java
│   │   │               │   └── PhoneMDMAEClientHandler.java
│   │   │               ├── models/
│   │   │               │   ├── PhoneNumber.java
│   │   │               │   ├── PhoneValidationResult.java
│   │   │               │   ├── PhoneHistoryCheck.java
│   │   │               │   ├── OTPCode.java
│   │   │               │   └── MDMAEPhoneUpdateRequest.java
│   │   │               ├── validators/
│   │   │               │   ├── PhoneNumberValidator.java
│   │   │               │   └── CountryPhoneValidator.java
│   │   │               ├── services/
│   │   │               │   ├── PhoneValidationService.java
│   │   │               │   ├── PhoneHistoryService.java
│   │   │               │   ├── OTPService.java
│   │   │               │   └── FraudDetectionService.java
│   │   │               ├── clients/
│   │   │               │   ├── MDMAEClient.java
│   │   │               │   ├── SMSClient.java
│   │   │               │   └── DynamoDBClient.java
│   │   │               └── utils/
│   │   │                   ├── PhoneUtils.java
│   │   │                   ├── LoggingUtils.java
│   │   │                   └── MetricsUtils.java
│   │   └── resources/
│   │       ├── application.properties
│   │       └── logback.xml
│   └── test/
│       └── java/
│           └── com/
│               └── bnc/
│                   └── mcp/
│                       ├── handlers/
│                       │   ├── PhoneValidatorHandlerTest.java
│                       │   └── CheckPhoneHistoryHandlerTest.java
│                       ├── services/
│                       │   └── PhoneValidationServiceTest.java
│                       └── validators/
│                           └── PhoneNumberValidatorTest.java
```

---

### Étape 2.2 : Configurer pom.xml

**Repo :** `mcp-local`

**Fichier à modifier :** `pom.xml`

**Ajouter les dépendances :**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0
         http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <groupId>com.bnc.mcp</groupId>
    <artifactId>mcp-phone-update</artifactId>
    <version>1.0.0</version>
    <packaging>jar</packaging>

    <properties>
        <maven.compiler.source>17</maven.compiler.source>
        <maven.compiler.target>17</maven.compiler.target>
        <aws.sdk.version>2.20.0</aws.sdk.version>
        <lombok.version>1.18.30</lombok.version>
        <junit.version>5.10.0</junit.version>
    </properties>

    <dependencies>
        <!-- AWS Lambda Core -->
        <dependency>
            <groupId>com.amazonaws</groupId>
            <artifactId>aws-lambda-java-core</artifactId>
            <version>1.2.3</version>
        </dependency>

        <!-- AWS Lambda Events -->
        <dependency>
            <groupId>com.amazonaws</groupId>
            <artifactId>aws-lambda-java-events</artifactId>
            <version>3.11.3</version>
        </dependency>

        <!-- AWS SDK v2 - Step Functions -->
        <dependency>
            <groupId>software.amazon.awssdk</groupId>
            <artifactId>sfn</artifactId>
            <version>${aws.sdk.version}</version>
        </dependency>

        <!-- AWS SDK v2 - DynamoDB -->
        <dependency>
            <groupId>software.amazon.awssdk</groupId>
            <artifactId>dynamodb</artifactId>
            <version>${aws.sdk.version}</version>
        </dependency>

        <!-- AWS SDK v2 - SNS (pour SMS) -->
        <dependency>
            <groupId>software.amazon.awssdk</groupId>
            <artifactId>sns</artifactId>
            <version>${aws.sdk.version}</version>
        </dependency>

        <!-- Lombok -->
        <dependency>
            <groupId>org.projectlombok</groupId>
            <artifactId>lombok</artifactId>
            <version>${lombok.version}</version>
            <scope>provided</scope>
        </dependency>

        <!-- Jackson (JSON) -->
        <dependency>
            <groupId>com.fasterxml.jackson.core</groupId>
            <artifactId>jackson-databind</artifactId>
            <version>2.15.2</version>
        </dependency>

        <!-- libphonenumber (Google) - validation téléphone -->
        <dependency>
            <groupId>com.googlecode.libphonenumber</groupId>
            <artifactId>libphonenumber</artifactId>
            <version>8.13.23</version>
        </dependency>

        <!-- SLF4J -->
        <dependency>
            <groupId>org.slf4j</groupId>
            <artifactId>slf4j-api</artifactId>
            <version>2.0.9</version>
        </dependency>

        <!-- Logback -->
        <dependency>
            <groupId>ch.qos.logback</groupId>
            <artifactId>logback-classic</artifactId>
            <version>1.4.11</version>
        </dependency>

        <!-- JUnit 5 -->
        <dependency>
            <groupId>org.junit.jupiter</groupId>
            <artifactId>junit-jupiter</artifactId>
            <version>${junit.version}</version>
            <scope>test</scope>
        </dependency>

        <!-- Mockito -->
        <dependency>
            <groupId>org.mockito</groupId>
            <artifactId>mockito-core</artifactId>
            <version>5.6.0</version>
            <scope>test</scope>
        </dependency>

        <!-- AssertJ -->
        <dependency>
            <groupId>org.assertj</groupId>
            <artifactId>assertj-core</artifactId>
            <version>3.24.2</version>
            <scope>test</scope>
        </dependency>
    </dependencies>

    <build>
        <plugins>
            <!-- Maven Compiler -->
            <plugin>
                <groupId>org.apache.maven.plugins</groupId>
                <artifactId>maven-compiler-plugin</artifactId>
                <version>3.11.0</version>
                <configuration>
                    <source>17</source>
                    <target>17</target>
                </configuration>
            </plugin>

            <!-- Maven Shade (créer JAR avec dépendances) -->
            <plugin>
                <groupId>org.apache.maven.plugins</groupId>
                <artifactId>maven-shade-plugin</artifactId>
                <version>3.5.0</version>
                <executions>
                    <execution>
                        <phase>package</phase>
                        <goals>
                            <goal>shade</goal>
                        </goals>
                        <configuration>
                            <createDependencyReducedPom>false</createDependencyReducedPom>
                        </configuration>
                    </execution>
                </executions>
            </plugin>
        </plugins>
    </build>
</project>
```

---

### Étape 2.3 : Créer le Lambda Controller

**Repo :** `mcp-local`

**Fichier à créer :** `src/main/java/com/bnc/mcp/controllers/ClientPhoneUpdateController.java`

**Contenu dans le prochain message (trop long)...**

Voulez-vous que je continue avec la Phase 2 complète (code Java de tous les handlers, services, models, etc.) ? Je peux créer chaque fichier Java avec le code complet.