
# Guide : Implémenter un Nouveau Workflow

Ce document explique **étape par étape** comment implémenter un nouveau workflow de bout en bout, de la création des ressources AWS (Terraform) jusqu'à l'implémentation du code (Service Java).

---

## Table des matières

1. [Vue d'ensemble du processus](#vue-densemble-du-processus)
2. [Étape 1 : Analyser les besoins du workflow](#étape-1--analyser-les-besoins-du-workflow)
3. [Étape 2 : Créer les ressources Terraform (mcp-infrastructure)](#étape-2--créer-les-ressources-terraform-mcp-infrastructure)
4. [Étape 3 : Déployer l'infrastructure](#étape-3--déployer-linfrastructure)
5. [Étape 4 : Implémenter le code service (mcp-local)](#étape-4--implémenter-le-code-service-mcp-local)
6. [Étape 5 : Tester le workflow complet](#étape-5--tester-le-workflow-complet)
7. [Exemple complet : Workflow "Client Address Update"](#exemple-complet--workflow-client-address-update)

---

## Vue d'ensemble du processus

```
┌─────────────────────────────────────────────────────────────────────┐
│                    NOUVEAU WORKFLOW À IMPLÉMENTER                    │
│              Exemple: "Mise à jour d'adresse client"                │
└─────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────┐
│ ÉTAPE 1: ANALYSE                                                     │
│ ┌─────────────────────────────────────────────────────────────────┐ │
│ │ • Quel est le déclencheur? (API, EventBridge, SQS, MQ...)       │ │
│ │ • Quelles sont les étapes du workflow?                          │ │
│ │ • Quelles données stocker? (DynamoDB, S3...)                    │ │
│ │ • Quels systèmes externes appeler? (MDMAE, FCC, autres APIs...) │ │
│ │ • Quelles files SQS pour les réponses asynchrones?              │ │
│ └─────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────┐
│ ÉTAPE 2: TERRAFORM (mcp-infrastructure repo)                        │
│ ┌─────────────────────────────────────────────────────────────────┐ │
│ │ A. Secrets Manager (si nouveaux credentials)                    │ │
│ │ B. DynamoDB (si nouvelles tables)                               │ │
│ │ C. SQS (si nouvelles queues)                                    │ │
│ │ D. Lambda (nouvelles fonctions)                                 │ │
│ │ E. Step Functions (nouveau state machine)                       │ │
│ │ F. API Gateway (nouveaux endpoints si besoin)                   │ │
│ │ G. EventBridge (nouvelles règles si besoin)                     │ │
│ │ H. IAM (nouvelles permissions)                                  │ │
│ │ I. CloudWatch (nouvelles alarmes)                               │ │
│ └─────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────┐
│ ÉTAPE 3: DÉPLOIEMENT                                                 │
│ ┌─────────────────────────────────────────────────────────────────┐ │
│ │ • terraform plan (vérification)                                 │ │
│ │ • terraform apply (création des ressources AWS)                 │ │
│ │ • Récupération des ARNs et URLs                                 │ │
│ └─────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────┐
│ ÉTAPE 4: CODE SERVICE (mcp-local repo)                              │
│ ┌─────────────────────────────────────────────────────────────────┐ │
│ │ A. Créer les Lambda Handlers (Java)                             │ │
│ │ B. Créer les modèles de données (DTOs)                          │ │
│ │ C. Créer les clients (DynamoDB, SQS, APIs externes)             │ │
│ │ D. Implémenter la logique métier                                │ │
│ │ E. Créer les tests unitaires                                    │ │
│ │ F. Compiler les JARs                                            │ │
│ │ G. Placer les JARs dans mcp-infrastructure/modules/lambda/      │ │
│ └─────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────┐
│ ÉTAPE 5: TEST & VALIDATION                                          │
│ ┌─────────────────────────────────────────────────────────────────┐ │
│ │ • Redéployer Terraform avec les nouveaux JARs                   │ │
│ │ • Tester via API Gateway / EventBridge                          │ │
│ │ • Vérifier les logs CloudWatch                                  │ │
│ │ • Vérifier les données DynamoDB                                 │ │
│ │ • Tester les scénarios d'erreur                                 │ │
│ └─────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
                                    ↓
                            ✅ WORKFLOW PRÊT!
```

---

## Étape 1 : Analyser les besoins du workflow

Avant de créer quoi que ce soit, répondez à ces questions :

### Questions clés :

#### 1. Déclenchement

**Comment le workflow est déclenché?**

- [ ] **API REST** → Besoin d'un endpoint API Gateway
- [ ] **Événement planifié** (ex: toutes les 5 min) → Besoin d'EventBridge schedule
- [ ] **Message SQS** → Besoin d'une queue SQS + event source mapping
- [ ] **Message IBM MQ** → Lambda poller existant peut déclencher
- [ ] **Webhook externe** → API Gateway + validation

**Exemple** : Pour "Client Address Update", c'est un **API REST PUT /api/clients/{clientId}/address**

---

#### 2. Étapes du workflow

**Quelles sont les étapes séquentielles?**

Listez chaque étape :

1. Lire les données actuelles (DynamoDB? API externe?)
2. Valider les nouvelles données (règles métier)
3. Appeler un système externe (MDMAE? Autre?)
4. Envoyer un message à un autre système (FCC via IBM MQ?)
5. Sauvegarder le résultat (DynamoDB? S3?)
6. (Optionnel) Gérer la revue humaine si validation échoue

**Exemple pour "Client Address Update"** :
1. `ReadClientProfile` - Lire le profil client depuis DynamoDB
2. `ValidateAddress` - Valider la nouvelle adresse (format, code postal, etc.)
3. `CallMDMAE` - Envoyer la mise à jour à MDMAE
4. `SendFCC` - Envoyer notification FCC via IBM MQ
5. `UpdateProfile` - Mettre à jour DynamoDB avec la nouvelle adresse

---

#### 3. Stockage de données

**Quelles données doivent être stockées?**

- [ ] **DynamoDB** : Données structurées (profils clients, transactions, états)
- [ ] **S3** : Fichiers volumineux (documents, images, logs)
- [ ] **ElastiCache** : Cache temporaire (sessions, résultats API)

**Exemple** :
- Table DynamoDB existante `ClientProfile` peut être réutilisée
- Ou nouvelle table `AddressHistory` pour tracer les changements

---

#### 4. Intégrations externes

**Quels systèmes externes appeler?**

- [ ] **MDMAE API** → Besoin du secret ARN existant `dev/mcp/mdmae`
- [ ] **IBM MQ** → Besoin du secret ARN existant `dev/mcp/ibmmq`
- [ ] **Nouvelle API tierce** → Créer un nouveau secret dans Secrets Manager

**Exemple** : MDMAE API (déjà configuré) + FCC via IBM MQ (déjà configuré)

---

#### 5. Files SQS

**Besoin de queues SQS pour messages asynchrones?**

- [ ] Queue de requêtes entrantes
- [ ] Queue de réponses d'un système externe
- [ ] Dead Letter Queue (DLQ) pour les erreurs

**Exemple** : Réutiliser la queue existante `fcc_responses` si FCC envoie une confirmation

---

#### 6. Lambdas nécessaires

**Combien de Lambdas pour ce workflow?**

Chaque étape du workflow = généralement 1 Lambda

**Exemple pour "Address Update"** :
1. `address-validator` - Nouvelle Lambda
2. `address-mdmae-client` - Nouvelle Lambda (ou réutiliser `mdmae-client`?)
3. Réutiliser `client-profile-reader`
4. Réutiliser `fcc-sender`

---

## Étape 2 : Créer les ressources Terraform (mcp-infrastructure)

Maintenant qu'on sait ce qu'on a besoin, créons les ressources Terraform.

### Structure des modifications :

```
mcp-infrastructure/
├── environments/dev/
│   ├── main.tf                          ← MODIFIER : Ajouter nouveaux modules
│   └── variables.tf                     ← MODIFIER si nouveaux secrets
│
├── modules/
│   ├── secrets-manager/                 ← MODIFIER si nouveaux credentials
│   │   └── (pas de changement si réutilisation)
│   │
│   ├── dynamodb/                        ← MODIFIER si nouvelles tables
│   │   └── main.tf
│   │
│   ├── sqs/                             ← MODIFIER si nouvelles queues
│   │   └── main.tf
│   │
│   ├── lambda/                          ← MODIFIER : Nouvelles fonctions
│   │   ├── main.tf
│   │   └── functions/
│   │       ├── address-validator/
│   │       │   └── function.jar         ← AJOUTER (vide pour l'instant)
│   │       └── address-mdmae-client/
│   │           └── function.jar         ← AJOUTER (vide pour l'instant)
│   │
│   ├── step-functions/                  ← MODIFIER : Nouveau state machine
│   │   ├── main.tf
│   │   └── state-machines/
│   │       └── client-address-update.json.tpl  ← CRÉER
│   │
│   ├── api-gateway/                     ← MODIFIER : Nouveau endpoint
│   │   └── main.tf
│   │
│   └── iam/                             ← MODIFIER : Nouvelles permissions
│       └── main.tf
```

---

### A. Secrets Manager (si nécessaire)

**Quand l'ajouter?** Uniquement si vous avez de **nouveaux credentials** pour un système externe.

#### Si réutilisation des secrets existants (MDMAE, IBM MQ) :
✅ **Rien à faire!** Les secrets existent déjà.

#### Si nouveau système externe :

**1. Ajouter la variable dans `environments/dev/variables.tf`** :

```hcl
# Nouveau système (exemple: API SAP)
variable "sap_api_url" {
  description = "SAP API URL"
  type        = string
  sensitive   = true
}

variable "sap_api_key" {
  description = "SAP API Key"
  type        = string
  sensitive   = true
}
```

**2. Ajouter le secret dans `environments/dev/main.tf`** :

```hcl
module "secrets" {
  source = "../../modules/secrets-manager"

  environment = var.environment
  project_name = var.project_name

  secrets = {
    ibmmq = {
      description = "IBM MQ credentials for ${var.environment}"
      secret_data = {
        host     = var.ibm_mq_host
        port     = var.ibm_mq_port
        channel  = var.ibm_mq_channel
        password = var.ibm_mq_password
      }
    }
    mdmae = {
      description = "MDMAE API credentials for ${var.environment}"
      secret_data = {
        url     = var.mdmae_url
        api_key = var.mdmae_api_key
      }
    }
    # ← NOUVEAU SECRET
    sap = {
      description = "SAP API credentials for ${var.environment}"
      secret_data = {
        url     = var.sap_api_url
        api_key = var.sap_api_key
      }
    }
  }
}
```

**3. Ajouter les secrets GitHub** :

Dans GitHub → Settings → Secrets and variables → Actions :
- `DEV_SAP_API_URL` = `https://sap-dev.example.com/api`
- `DEV_SAP_API_KEY` = `your-api-key-here`

**4. Modifier `.github/workflows/terraform-deploy.yml`** :

```yaml
env:
  # Existants
  TF_VAR_ibm_mq_host: ${{ secrets.DEV_IBM_MQ_HOST }}
  TF_VAR_mdmae_url: ${{ secrets.DEV_MDMAE_URL }}

  # ← NOUVEAUX
  TF_VAR_sap_api_url: ${{ secrets.DEV_SAP_API_URL }}
  TF_VAR_sap_api_key: ${{ secrets.DEV_SAP_API_KEY }}
```

---

### B. DynamoDB (si nouvelles tables)

#### Si réutilisation de la table existante `ClientProfile` :
✅ **Rien à faire!** Juste ajouter de nouveaux attributs dans votre code Java.

#### Si nouvelle table nécessaire :

**Modifier `modules/dynamodb/main.tf`** :

```hcl
# Table existante
resource "aws_dynamodb_table" "client_profile" {
  name         = "${var.environment}-${var.project_name}-ClientProfile"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "clientId"

  attribute {
    name = "clientId"
    type = "S"
  }

  # ... reste de la config
}

# ← NOUVELLE TABLE
resource "aws_dynamodb_table" "address_history" {
  name         = "${var.environment}-${var.project_name}-AddressHistory"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "clientId"
  range_key    = "timestamp"

  attribute {
    name = "clientId"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "N"
  }

  ttl {
    attribute_name = "expirationTime"
    enabled        = true
  }

  tags = {
    Name        = "${var.environment}-${var.project_name}-AddressHistory"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}
```

**Ajouter l'output dans `modules/dynamodb/outputs.tf`** :

```hcl
output "address_history_table_name" {
  description = "Name of the AddressHistory DynamoDB table"
  value       = aws_dynamodb_table.address_history.name
}

output "address_history_table_arn" {
  description = "ARN of the AddressHistory DynamoDB table"
  value       = aws_dynamodb_table.address_history.arn
}
```

---

### C. SQS (si nouvelles queues)

#### Si réutilisation des queues existantes :
✅ **Rien à faire!**

#### Si nouvelle queue :

**Modifier `environments/dev/main.tf`** dans le module SQS :

```hcl
module "sqs" {
  source = "../../modules/sqs"

  environment  = var.environment
  project_name = var.project_name

  queues = {
    fcc_responses = {
      visibility_timeout_seconds = 300
      message_retention_seconds  = 86400
      max_receive_count          = 3
    }
    # ← NOUVELLE QUEUE
    address_validation_results = {
      visibility_timeout_seconds = 180
      message_retention_seconds  = 43200  # 12 heures
      max_receive_count          = 5
    }
  }
}
```

---

### D. Lambda (nouvelles fonctions)

**C'est ici qu'on définit les NOUVELLES Lambdas pour le workflow.**

#### 1. Créer les dossiers vides pour les JARs :

```bash
cd mcp-infrastructure
mkdir -p modules/lambda/functions/address-validator
mkdir -p modules/lambda/functions/address-mdmae-client

# Créer des fichiers JAR vides (placeholders)
touch modules/lambda/functions/address-validator/function.jar
touch modules/lambda/functions/address-mdmae-client/function.jar
```

#### 2. Modifier `environments/dev/main.tf` dans le module Lambda :

```hcl
module "lambda" {
  source = "../../modules/lambda"

  environment  = var.environment
  project_name = var.project_name

  lambda_execution_role_arn = module.iam.lambda_execution_role_arn
  subnet_ids                = module.vpc.private_subnet_ids
  security_group_ids        = [module.vpc.lambda_security_group_id]

  functions = {
    # Fonctions existantes
    client-profile-reader = {
      handler          = "com.bnc.mcp.api.ClientProfileReaderHandler::handleRequest"
      runtime          = "java17"
      memory_size      = 512
      timeout          = 30
      environment_vars = {
        DYNAMODB_TABLE = module.dynamodb.table_name
      }
      vpc_config = {
        subnet_ids         = module.vpc.private_subnet_ids
        security_group_ids = [module.vpc.lambda_security_group_id]
      }
    }

    # ← NOUVELLES FONCTIONS
    address-validator = {
      handler          = "com.bnc.mcp.api.AddressValidatorHandler::handleRequest"
      runtime          = "java17"
      memory_size      = 512
      timeout          = 30
      environment_vars = {
        ALLOWED_COUNTRIES = "CA,US"
      }
      vpc_config = null  # Pas de VPC si pas d'accès à des ressources privées
    }

    address-mdmae-client = {
      handler          = "com.bnc.mcp.api.AddressMdmaeClientHandler::handleRequest"
      runtime          = "java17"
      memory_size      = 1024
      timeout          = 60
      environment_vars = {
        MDMAE_SECRET_ARN = module.secrets.secret_arns["mdmae"]
      }
      vpc_config = {
        subnet_ids         = module.vpc.private_subnet_ids
        security_group_ids = [module.vpc.lambda_security_group_id]
      }
    }
  }
}
```

---

### E. Step Functions (nouveau state machine)

**Créer la définition du workflow.**

#### 1. Créer le template JSON :

**Créer `modules/step-functions/state-machines/client-address-update.json.tpl`** :

```json
{
  "Comment": "Client Address Update Workflow",
  "StartAt": "ReadClientProfile",
  "States": {
    "ReadClientProfile": {
      "Type": "Task",
      "Resource": "${client_profile_reader_arn}",
      "Comment": "Récupère le profil client actuel depuis DynamoDB",
      "ResultPath": "$.currentProfile",
      "Next": "ValidateAddress",
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "ResultPath": "$.error",
          "Next": "HandleError"
        }
      ]
    },

    "ValidateAddress": {
      "Type": "Task",
      "Resource": "${address_validator_arn}",
      "Comment": "Valide le format et la cohérence de la nouvelle adresse",
      "ResultPath": "$.validationResult",
      "Next": "CheckValidation",
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "ResultPath": "$.error",
          "Next": "HandleError"
        }
      ]
    },

    "CheckValidation": {
      "Type": "Choice",
      "Comment": "Vérifie si la validation a réussi",
      "Choices": [
        {
          "Variable": "$.validationResult.isValid",
          "BooleanEquals": true,
          "Next": "CallMDMAE"
        }
      ],
      "Default": "HumanReview"
    },

    "CallMDMAE": {
      "Type": "Task",
      "Resource": "${address_mdmae_client_arn}",
      "Comment": "Envoie la mise à jour à MDMAE",
      "ResultPath": "$.mdmaeResult",
      "Next": "SendFCC",
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "ResultPath": "$.error",
          "Next": "HandleError"
        }
      ]
    },

    "SendFCC": {
      "Type": "Task",
      "Resource": "${fcc_sender_arn}",
      "Comment": "Envoie notification FCC via IBM MQ",
      "ResultPath": "$.fccResult",
      "Next": "Success",
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "ResultPath": "$.error",
          "Next": "HandleError"
        }
      ]
    },

    "HumanReview": {
      "Type": "Task",
      "Resource": "${human_review_handler_arn}",
      "Comment": "Envoie pour revue humaine si validation échoue",
      "ResultPath": "$.reviewResult",
      "Next": "Success"
    },

    "HandleError": {
      "Type": "Pass",
      "Comment": "Gère les erreurs et log les détails",
      "Result": {
        "status": "FAILED"
      },
      "End": true
    },

    "Success": {
      "Type": "Succeed",
      "Comment": "Workflow terminé avec succès"
    }
  }
}
```

#### 2. Modifier `environments/dev/main.tf` pour ajouter le state machine :

```hcl
module "step_functions" {
  source = "../../modules/step-functions"

  environment  = var.environment
  project_name = var.project_name

  step_functions_role_arn = module.iam.step_functions_role_arn

  state_machines = {
    client-name-update = {
      definition_file = "client-name-update.json.tpl"
      variables = {
        client_profile_reader_arn = module.lambda.function_arns["client-profile-reader"]
        name_validator_arn        = module.lambda.function_arns["name-validator"]
        mdmae_client_arn          = module.lambda.function_arns["mdmae-client"]
        fcc_sender_arn            = module.lambda.function_arns["fcc-sender"]
        human_review_handler_arn  = module.lambda.function_arns["human-review-handler"]
      }
    }
    # ← NOUVEAU STATE MACHINE
    client-address-update = {
      definition_file = "client-address-update.json.tpl"
      variables = {
        client_profile_reader_arn = module.lambda.function_arns["client-profile-reader"]
        address_validator_arn     = module.lambda.function_arns["address-validator"]
        address_mdmae_client_arn  = module.lambda.function_arns["address-mdmae-client"]
        fcc_sender_arn            = module.lambda.function_arns["fcc-sender"]
        human_review_handler_arn  = module.lambda.function_arns["human-review-handler"]
      }
    }
  }
}
```

---

### F. API Gateway (nouveau endpoint)

**Ajouter un nouveau endpoint REST pour déclencher le workflow.**

**Modifier `modules/api-gateway/main.tf`** :

```hcl
# Resource: /api/clients/{clientId}/nom (existant)
resource "aws_api_gateway_resource" "nom" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.client_id.id
  path_part   = "nom"
}

# ← NOUVEAU : /api/clients/{clientId}/address
resource "aws_api_gateway_resource" "address" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.client_id.id
  path_part   = "address"
}

# ← NOUVEAU : PUT /api/clients/{clientId}/address
resource "aws_api_gateway_method" "put_address" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.address.id
  http_method   = "PUT"
  authorization = "AWS_IAM"

  request_parameters = {
    "method.request.path.clientId" = true
  }
}

# ← NOUVEAU : Intégration avec Step Functions
resource "aws_api_gateway_integration" "put_address_stepfunctions" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.address.id
  http_method = aws_api_gateway_method.put_address.http_method

  integration_http_method = "POST"
  type                    = "AWS"
  uri                     = "arn:aws:apigateway:${data.aws_region.current.name}:states:action/StartExecution"
  credentials             = var.api_gateway_role_arn

  request_templates = {
    "application/json" = jsonencode({
      stateMachineArn = var.state_machine_arns["client-address-update"]
      input = jsonencode({
        clientId = "$input.params('clientId')",
        address  = "$input.body"
      })
    })
  }
}
```

---

### G. IAM (nouvelles permissions)

**Les nouvelles Lambdas ont besoin de permissions.**

**Modifier `modules/iam/main.tf`** :

```hcl
resource "aws_iam_role_policy" "lambda_execution" {
  name = "${var.environment}-${var.project_name}-lambda-execution-policy"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # DynamoDB (existant)
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          var.dynamodb_table_arn,
          "${var.dynamodb_table_arn}/index/*",
          # ← NOUVELLE TABLE
          var.address_history_table_arn,
          "${var.address_history_table_arn}/index/*"
        ]
      },
      # Secrets Manager
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = concat(
          values(var.secrets_arns),
          # ← NOUVEAU SECRET si ajouté
          # [var.sap_secret_arn]
        )
      },
      # SQS
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = values(var.sqs_queue_arns)
      },
      # CloudWatch Logs
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      # VPC (si Lambdas dans VPC)
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface"
        ]
        Resource = "*"
      }
    ]
  })
}
```

---

### H. CloudWatch (nouvelles alarmes)

**Ajouter des alarmes pour surveiller les nouvelles Lambdas.**

Les alarmes sont automatiquement créées par le module CloudWatch pour toutes les Lambdas définies dans `module.lambda.function_arns`.

✅ **Rien à modifier!** Les nouvelles Lambdas seront automatiquement surveillées.

Si vous voulez des alarmes personnalisées :

```hcl
# Dans modules/cloudwatch/main.tf
resource "aws_cloudwatch_metric_alarm" "address_validator_errors" {
  alarm_name          = "${var.environment}-${var.project_name}-address-validator-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "Alarm when address validator errors exceed 5 per minute"

  dimensions = {
    FunctionName = "${var.environment}-${var.project_name}-address-validator"
  }
}
```

---

## Étape 3 : Déployer l'infrastructure

Maintenant que toutes les ressources Terraform sont définies dans le repo **mcp-infrastructure**, déployons-les via le **pipeline GitHub Actions** (déclenchement manuel).

### Méthode recommandée : GitHub Actions (Déclenchement manuel)

Le déploiement se fait via le workflow GitHub Actions `.github/workflows/terraform-deploy.yml` avec un **déclenchement manuel** (`workflow_dispatch`).

#### 1. Aller sur GitHub Actions

```
Repository mcp-infrastructure → Actions → Terraform Deploy → Run workflow
```

#### 2. Configurer les inputs du workflow

Le workflow demande **3 inputs obligatoires** :

| Input | Options | Description |
|-------|---------|-------------|
| **Branch** | `main`, `develop`, feature branches | La branche Git à déployer |
| **Environment** | `dev`, `prod` | L'environnement AWS cible |
| **Action** | `plan`, `apply`, `destroy` | L'action Terraform à exécuter |

**Interface GitHub Actions** :

```
Run workflow
┌────────────────────────────────────────┐
│ Use workflow from                      │
│ Branch: [main ▼]                       │
│                                        │
│ Environment                            │
│ ○ dev  ○ prod                          │
│                                        │
│ Action                                 │
│ ○ plan  ○ apply  ○ destroy             │
│                                        │
│         [Run workflow]                 │
└────────────────────────────────────────┘
```

#### 3. Exemples de configurations

**Exemple 1 : Vérifier les changements (plan) en DEV**
- Branch: `main`
- Environment: `dev`
- Action: `plan`

→ Terraform affichera les ressources à créer/modifier sans les créer

**Exemple 2 : Déployer en DEV (apply)**
- Branch: `main`
- Environment: `dev`
- Action: `apply`

→ Terraform créera réellement les ressources AWS

**Exemple 3 : Déployer en PROD (apply)**
- Branch: `main`
- Environment: `prod`
- Action: `apply`

→ Terraform créera les ressources en environnement production

**Exemple 4 : Détruire l'infrastructure DEV (destroy)**
- Branch: `main`
- Environment: `dev`
- Action: `destroy`

→ ⚠️ Supprimera toutes les ressources AWS de l'environnement dev

#### 4. Workflow déclenché

Une fois le workflow lancé, GitHub Actions :

1. **Clone le repository** depuis la branche sélectionnée
2. **Configure AWS credentials** (depuis GitHub Secrets)
3. **Installe Terraform** 1.9.0
4. **Terraform init** : Charge le backend S3 et les providers
5. **Terraform plan/apply/destroy** : Exécute l'action sélectionnée dans `environments/<environment>/`
6. **Upload des outputs** : Sauvegarde le state comme artifact

**Logs visibles en temps réel** :

```
Run Terraform Deploy
├─ Set up job (30s)
├─ Checkout code (5s)
├─ Configure AWS credentials (2s)
├─ Setup Terraform (10s)
├─ Terraform Init (15s)
│  ✓ Backend initialized (S3)
│  ✓ Providers downloaded
│
├─ Terraform Apply (17 minutes)
│  ✓ module.secrets.aws_secretsmanager_secret.secrets["ibmmq"]: Creating...
│  ✓ module.dynamodb.aws_dynamodb_table.client_profile: Creating...
│  ✓ module.lambda.aws_lambda_function.functions["address-validator"]: Creating...
│  ✓ module.step_functions.aws_sfn_state_machine.state_machines["client-address-update"]: Creating...
│  ...
│  Apply complete! Resources: 8 added, 0 changed, 0 destroyed.
│
└─ Upload Terraform Outputs (5s)
   ✓ Artifact uploaded: terraform-outputs-dev
```

#### 5. Récupérer les ARNs et URLs

**Après le déploiement réussi**, les outputs Terraform sont affichés dans les logs :

```
Outputs:

address_validator_arn = "arn:aws:lambda:ca-central-1:123456789:function:dev-mcp-address-validator"
address_mdmae_client_arn = "arn:aws:lambda:ca-central-1:123456789:function:dev-mcp-address-mdmae-client"
api_gateway_url = "https://abc123.execute-api.ca-central-1.amazonaws.com/dev/api/clients/{clientId}/address"
state_machine_arn = "arn:aws:states:ca-central-1:123456789:stateMachine:dev-mcp-client-address-update"
```

**Notez ces valeurs** dans un fichier (ex: `deployment-outputs.txt`) pour référence future.

#### 6. Télécharger le state (optionnel)

Le state Terraform est uploadé comme **artifact GitHub Actions** :

```
Workflow run #123
  ✓ Job completed successfully
  📦 Artifacts
     └─ terraform-outputs-dev (5.2 MB)  ← Téléchargeable
```

Pour télécharger :
1. Cliquer sur l'artifact
2. Extraire le fichier `terraform.tfstate`

---

### Méthode alternative : Terraform en local (développement)

**⚠️ Utilisez cette méthode uniquement pour le développement/test local**

Si vous voulez tester localement avant de pousser sur GitHub :

#### 1. Configurer AWS credentials localement

```bash
# Configure AWS CLI avec vos credentials
aws configure

# Vérifier
aws sts get-caller-identity
```

#### 2. Définir les variables Terraform

Créer un fichier `environments/dev/terraform.tfvars` (NON versionné dans Git) :

```hcl
# environments/dev/terraform.tfvars
ibm_mq_host     = "0.tcp.ngrok.io"
ibm_mq_port     = 12345
ibm_mq_channel  = "DEV.APP.SVRCONN"
ibm_mq_password = "passw0rd"

mdmae_url     = "https://mdmae-dev.com/api"
mdmae_api_key = "your-api-key"
```

**⚠️ IMPORTANT** : Ajouter à `.gitignore` :

```gitignore
# .gitignore
*.tfvars
!terraform.tfvars.example
```

#### 3. Plan local

```bash
cd mcp-infrastructure/environments/dev
terraform init
terraform plan
```

**Vérifiez la sortie** :

```
Plan: 8 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + address_validator_arn = (known after apply)
  + address_mdmae_client_arn = (known after apply)
```

#### 4. Apply local

```bash
terraform apply
```

Terraform demandera confirmation :

```
Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes
```

---

### Comparaison des deux méthodes

| Critère | GitHub Actions (Recommandé) | Terraform Local |
|---------|----------------------------|-----------------|
| **Sécurité** | ✅ Secrets stockés dans GitHub | ⚠️ Credentials en local |
| **Traçabilité** | ✅ Logs permanents | ❌ Logs locaux uniquement |
| **Collaboration** | ✅ Toute l'équipe utilise le même processus | ❌ Chacun configure différemment |
| **Audit** | ✅ Historique complet des déploiements | ❌ Difficile de savoir qui a déployé quoi |
| **CI/CD** | ✅ Intégré avec Git workflow | ❌ Manuel |
| **Rollback** | ✅ Facile (redéployer une branche précédente) | ⚠️ Manuel via state |
| **Environnements** | ✅ dev/prod séparés automatiquement | ⚠️ Risque de confusion |

**Recommandation** : Utilisez **toujours GitHub Actions** pour les déploiements officiels (dev, prod). N'utilisez Terraform local que pour tester des changements avant de les committer.

---

## Étape 4 : Implémenter le code service (mcp-local)

Maintenant que l'infrastructure existe, implémentons le **code Java** dans le repo `mcp-local`.

### Structure du code :

```
/Users/fabricefoko/Downloads/mcp-local/
├── src/main/java/com/bnc/mcp/
│   ├── controllers/                              ← NOUVEAU (Couche API)
│   │   └── ClientAddressUpdateController.java   ← CRÉER (Lambda Controller)
│   │
│   ├── handlers/                                 ← Couche métier (Step Functions)
│   │   ├── ClientProfileReaderHandler.java       ← Existant
│   │   ├── NameValidatorHandler.java             ← Existant
│   │   ├── AddressValidatorHandler.java          ← CRÉER
│   │   └── AddressMdmaeClientHandler.java        ← CRÉER
│   │
│   ├── models/
│   │   ├── ClientProfile.java                    ← Existant
│   │   ├── Address.java                          ← CRÉER
│   │   └── AddressValidationResult.java          ← CRÉER
│   │
│   ├── validators/                               ← NOUVEAU (Validation réutilisable)
│   │   ├── ClientIdValidator.java                ← CRÉER
│   │   └── AddressValidator.java                 ← CRÉER
│   │
│   ├── clients/
│   │   ├── DynamoDBClient.java                   ← Existant (réutiliser)
│   │   ├── MdmaeClient.java                      ← Existant (réutiliser)
│   │   └── SecretsManagerClient.java             ← Existant (réutiliser)
│   │
│   ├── services/
│   │   ├── AddressValidationService.java         ← CRÉER
│   │   └── AddressMdmaeService.java              ← CRÉER
│   │
│   └── utils/
│       ├── AddressUtils.java                     ← CRÉER
│       ├── LoggingUtils.java                     ← CRÉER (Logs structurés)
│       └── MetricsUtils.java                     ← CRÉER (Métriques Datadog)
│
├── src/test/java/com/bnc/mcp/
│   ├── controllers/
│   │   └── ClientAddressUpdateControllerTest.java ← CRÉER
│   │
│   ├── handlers/
│   │   ├── AddressValidatorHandlerTest.java      ← CRÉER
│   │   └── AddressMdmaeClientHandlerTest.java    ← CRÉER
│   │
│   ├── validators/
│   │   └── AddressValidatorTest.java             ← CRÉER
│   │
│   └── services/
│       └── AddressValidationServiceTest.java     ← CRÉER
│
└── pom.xml                                        ← Modifier (dépendances)
```

---

### A. Choix de l'architecture : Controller ou Intégration directe ?

**⚠️ IMPORTANT** : Il existe deux approches pour exposer un workflow via API Gateway.

#### Approche 1 : Intégration directe (❌ Non recommandé pour BNC)

```
API Gateway → Step Functions → Lambda Handlers
```

**Avantages** :
- Moins de code
- Une Lambda de moins (économie)

**Inconvénients pour contexte bancaire** :
- ❌ Pas de validation HTTP custom
- ❌ Logging insuffisant pour audit bancaire
- ❌ Pas d'enrichissement des données (requestId, userId)
- ❌ Gestion d'erreur limitée (pas de codes HTTP précis)
- ❌ Pas de contrôle d'accès fin

---

#### Approche 2 : Lambda Controller (✅ Recommandé BNC)

```
API Gateway → Lambda Controller → Step Functions → Lambda Handlers
```

**Avantages pour BNC/MCP** :
- ✅ **Validation stricte** : Rejette requêtes invalides (HTTP 400)
- ✅ **Logging exhaustif** : Datadog/Splunk pour audit bancaire
- ✅ **Enrichissement** : Ajoute requestId, userId, timestamp, source
- ✅ **Codes HTTP appropriés** : 200, 202, 400, 401, 403, 404, 500
- ✅ **Sécurité** : Authentification, autorisation, rate limiting
- ✅ **Observabilité** : Métriques custom, tracing distribué
- ✅ **Traçabilité** : "Meilleure traçabilité des transactions" (requis BNC)
- ✅ **Qualité des données** : "Amélioration de la qualité" (objectif MCP)

**Contexte BNC** :
> Le programme MCP vise la "centralisation des données clients" et "l'amélioration de la qualité".
> Un Lambda Controller permet de valider et enrichir AVANT Step Functions.

**Recommandation** : **Utilisez TOUJOURS l'Approche 2** pour BNC/MCP.

📘 **Guide détaillé** : Voir `LAMBDA_CONTROLLER_PATTERN.md` pour le code complet production-ready.

---

### B. Créer le Lambda Controller (Approche recommandée)

**`ClientAddressUpdateController.java`**

Ce controller :
1. Reçoit la requête HTTP (API Gateway)
2. Valide strictement les données
3. Enrichit avec metadata (requestId, userId, timestamp)
4. Log pour audit (Datadog/Splunk)
5. Démarre Step Functions
6. Retourne HTTP 202 Accepted

```java
package com.bnc.mcp.controllers;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.lambda.runtime.events.APIGatewayProxyRequestEvent;
import com.amazonaws.services.lambda.runtime.events.APIGatewayProxyResponseEvent;
import com.bnc.mcp.models.Address;
import com.bnc.mcp.validators.ClientIdValidator;
import com.bnc.mcp.validators.AddressValidator;
import com.bnc.mcp.utils.LoggingUtils;
import com.bnc.mcp.utils.MetricsUtils;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;
import software.amazon.awssdk.services.sfn.SfnClient;
import software.amazon.awssdk.services.sfn.model.StartExecutionRequest;
import software.amazon.awssdk.services.sfn.model.StartExecutionResponse;

import java.time.Instant;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

/**
 * Lambda Controller pour la mise à jour d'adresse client
 *
 * @author Équipe MCP - Banque Nationale
 */
@Slf4j
public class ClientAddressUpdateController implements RequestHandler<APIGatewayProxyRequestEvent, APIGatewayProxyResponseEvent> {

    private final SfnClient sfnClient;
    private final ObjectMapper objectMapper;
    private final String stateMachineArn;
    private final ClientIdValidator clientIdValidator;
    private final AddressValidator addressValidator;
    private final MetricsUtils metricsUtils;

    public ClientAddressUpdateController() {
        this.sfnClient = SfnClient.builder().build();
        this.objectMapper = new ObjectMapper();
        this.stateMachineArn = System.getenv("STATE_MACHINE_ARN");
        this.clientIdValidator = new ClientIdValidator();
        this.addressValidator = new AddressValidator();
        this.metricsUtils = new MetricsUtils();
    }

    @Override
    public APIGatewayProxyResponseEvent handleRequest(APIGatewayProxyRequestEvent request, Context context) {
        String requestId = context.getRequestId();
        long startTime = System.currentTimeMillis();

        // 1. LOGGING - Requête reçue (audit bancaire)
        log.info("ADDRESS_UPDATE_REQUEST_RECEIVED", LoggingUtils.buildLogContext(
            "event", "REQUEST_RECEIVED",
            "requestId", requestId,
            "path", request.getPath(),
            "sourceIp", request.getRequestContext().getIdentity().getSourceIp(),
            "timestamp", Instant.now().toString()
        ));

        try {
            // 2. EXTRACTION - Client ID
            String clientId = extractClientId(request);
            if (clientId == null) {
                metricsUtils.incrementCounter("address_update.missing_client_id");
                return buildErrorResponse(400, "Missing clientId in path", requestId);
            }

            // 3. VALIDATION - Client ID format
            if (!clientIdValidator.isValid(clientId)) {
                log.warn("INVALID_CLIENT_ID", LoggingUtils.buildLogContext(
                    "requestId", requestId,
                    "clientId", clientId
                ));
                metricsUtils.incrementCounter("address_update.invalid_client_id");
                return buildErrorResponse(400, "Invalid client ID format", requestId);
            }

            // 4. PARSING - Body JSON
            Address address = parseAddress(request.getBody());
            if (address == null) {
                metricsUtils.incrementCounter("address_update.missing_body");
                return buildErrorResponse(400, "Missing or invalid request body", requestId);
            }

            // 5. VALIDATION - Address fields
            Map<String, String> validationErrors = addressValidator.validate(address);
            if (!validationErrors.isEmpty()) {
                log.warn("VALIDATION_FAILED", LoggingUtils.buildLogContext(
                    "requestId", requestId,
                    "clientId", clientId,
                    "errors", validationErrors
                ));
                metricsUtils.incrementCounter("address_update.validation_failed");
                return buildValidationErrorResponse(validationErrors, requestId);
            }

            // 6. ENRICHISSEMENT - Ajouter metadata
            Map<String, Object> stepFunctionInput = Map.of(
                "clientId", clientId,
                "address", address,
                "requestId", requestId,
                "timestamp", Instant.now().toString(),
                "source", "API_GATEWAY",
                "userId", extractUserId(request)
            );

            // 7. DÉMARRER - Step Functions
            StartExecutionResponse execution = startStepFunction(stepFunctionInput, clientId);

            // 8. LOGGING - Succès
            log.info("STEP_FUNCTION_STARTED", LoggingUtils.buildLogContext(
                "requestId", requestId,
                "clientId", clientId,
                "executionArn", execution.executionArn()
            ));

            // 9. MÉTRIQUES
            metricsUtils.incrementCounter("address_update.success");
            metricsUtils.recordLatency("address_update.controller_latency",
                System.currentTimeMillis() - startTime);

            // 10. RETOUR - HTTP 202 Accepted
            return buildSuccessResponse(202, Map.of(
                "message", "Address update request accepted",
                "executionArn", execution.executionArn(),
                "clientId", clientId,
                "status", "PROCESSING",
                "requestId", requestId
            ));

        } catch (Exception e) {
            log.error("CONTROLLER_ERROR", LoggingUtils.buildLogContext(
                "requestId", requestId,
                "error", e.getMessage()
            ), e);
            metricsUtils.incrementCounter("address_update.error");
            return buildErrorResponse(500, "Internal server error", requestId);
        }
    }

    private String extractClientId(APIGatewayProxyRequestEvent request) {
        return request.getPathParameters() != null
            ? request.getPathParameters().get("clientId")
            : null;
    }

    private Address parseAddress(String body) {
        try {
            return objectMapper.readValue(body, Address.class);
        } catch (Exception e) {
            return null;
        }
    }

    private String extractUserId(APIGatewayProxyRequestEvent request) {
        // Extraire du JWT Cognito ou header custom
        if (request.getRequestContext().getAuthorizer() != null) {
            var claims = request.getRequestContext().getAuthorizer().getClaims();
            if (claims != null && claims.containsKey("sub")) {
                return (String) claims.get("sub");
            }
        }
        return "ANONYMOUS";
    }

    private StartExecutionResponse startStepFunction(Map<String, Object> input, String clientId)
            throws Exception {
        String inputJson = objectMapper.writeValueAsString(input);
        String executionName = String.format("address-update-%s-%d",
            clientId, System.currentTimeMillis());

        return sfnClient.startExecution(StartExecutionRequest.builder()
            .stateMachineArn(stateMachineArn)
            .input(inputJson)
            .name(executionName)
            .build());
    }

    private APIGatewayProxyResponseEvent buildSuccessResponse(int statusCode, Map<String, Object> body) {
        try {
            return new APIGatewayProxyResponseEvent()
                .withStatusCode(statusCode)
                .withHeaders(Map.of(
                    "Content-Type", "application/json",
                    "Access-Control-Allow-Origin", "*"
                ))
                .withBody(objectMapper.writeValueAsString(body));
        } catch (Exception e) {
            return buildErrorResponse(500, "Error building response", UUID.randomUUID().toString());
        }
    }

    private APIGatewayProxyResponseEvent buildErrorResponse(int statusCode, String message, String requestId) {
        Map<String, Object> error = Map.of(
            "error", message,
            "statusCode", statusCode,
            "requestId", requestId,
            "timestamp", Instant.now().toString()
        );
        try {
            return new APIGatewayProxyResponseEvent()
                .withStatusCode(statusCode)
                .withHeaders(Map.of("Content-Type", "application/json"))
                .withBody(objectMapper.writeValueAsString(error));
        } catch (Exception e) {
            return new APIGatewayProxyResponseEvent()
                .withStatusCode(500)
                .withBody("{\"error\":\"Internal server error\"}");
        }
    }

    private APIGatewayProxyResponseEvent buildValidationErrorResponse(
            Map<String, String> errors, String requestId) {
        Map<String, Object> error = Map.of(
            "error", "Validation failed",
            "validationErrors", errors,
            "requestId", requestId,
            "timestamp", Instant.now().toString()
        );
        try {
            return new APIGatewayProxyResponseEvent()
                .withStatusCode(400)
                .withHeaders(Map.of("Content-Type", "application/json"))
                .withBody(objectMapper.writeValueAsString(error));
        } catch (Exception e) {
            return buildErrorResponse(500, "Error building response", requestId);
        }
    }
}
```

**📘 Note** : Pour le code complet avec tous les utilitaires (`LoggingUtils`, `MetricsUtils`, `Validators`),
voir le fichier `LAMBDA_CONTROLLER_PATTERN.md`.

---

### C. Créer les modèles de données

#### 1. `Address.java`

```java
package com.bnc.mcp.models;

import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class Address {

    @JsonProperty("street")
    private String street;

    @JsonProperty("city")
    private String city;

    @JsonProperty("province")
    private String province;

    @JsonProperty("postalCode")
    private String postalCode;

    @JsonProperty("country")
    private String country;

    @JsonProperty("type")
    private String type; // "HOME", "WORK", "BILLING"
}
```

#### 2. `AddressValidationResult.java`

```java
package com.bnc.mcp.models;

import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.List;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class AddressValidationResult {

    @JsonProperty("isValid")
    private boolean isValid;

    @JsonProperty("errors")
    private List<String> errors;

    @JsonProperty("warnings")
    private List<String> warnings;

    @JsonProperty("normalizedAddress")
    private Address normalizedAddress;
}
```

---

### B. Créer le service de validation

#### `AddressValidationService.java`

```java
package com.bnc.mcp.services;

import com.bnc.mcp.models.Address;
import com.bnc.mcp.models.AddressValidationResult;
import lombok.extern.slf4j.Slf4j;

import java.util.ArrayList;
import java.util.List;
import java.util.regex.Pattern;

@Slf4j
public class AddressValidationService {

    private static final Pattern CANADIAN_POSTAL_CODE = Pattern.compile("^[A-Z]\\d[A-Z] ?\\d[A-Z]\\d$");
    private static final Pattern US_ZIP_CODE = Pattern.compile("^\\d{5}(-\\d{4})?$");

    private static final List<String> ALLOWED_COUNTRIES = List.of("CA", "US");
    private static final List<String> CANADIAN_PROVINCES = List.of(
        "AB", "BC", "MB", "NB", "NL", "NS", "NT", "NU", "ON", "PE", "QC", "SK", "YT"
    );

    public AddressValidationResult validate(Address address) {
        log.info("Validating address for country: {}", address.getCountry());

        List<String> errors = new ArrayList<>();
        List<String> warnings = new ArrayList<>();

        // Validation 1: Country
        if (!ALLOWED_COUNTRIES.contains(address.getCountry())) {
            errors.add("Country must be CA or US");
        }

        // Validation 2: Street
        if (address.getStreet() == null || address.getStreet().trim().isEmpty()) {
            errors.add("Street is required");
        }

        // Validation 3: City
        if (address.getCity() == null || address.getCity().trim().isEmpty()) {
            errors.add("City is required");
        }

        // Validation 4: Province/State
        if (address.getProvince() == null || address.getProvince().trim().isEmpty()) {
            errors.add("Province/State is required");
        } else if ("CA".equals(address.getCountry()) && !CANADIAN_PROVINCES.contains(address.getProvince())) {
            errors.add("Invalid Canadian province code");
        }

        // Validation 5: Postal Code
        if (address.getPostalCode() == null || address.getPostalCode().trim().isEmpty()) {
            errors.add("Postal code is required");
        } else {
            String postalCode = address.getPostalCode().toUpperCase().trim();
            if ("CA".equals(address.getCountry())) {
                if (!CANADIAN_POSTAL_CODE.matcher(postalCode).matches()) {
                    errors.add("Invalid Canadian postal code format (e.g., H1A 1A1)");
                }
            } else if ("US".equals(address.getCountry())) {
                if (!US_ZIP_CODE.matcher(postalCode).matches()) {
                    errors.add("Invalid US ZIP code format (e.g., 12345 or 12345-6789)");
                }
            }
        }

        // Normalize address
        Address normalizedAddress = normalizeAddress(address);

        boolean isValid = errors.isEmpty();

        log.info("Validation result: isValid={}, errors={}, warnings={}", isValid, errors.size(), warnings.size());

        return AddressValidationResult.builder()
            .isValid(isValid)
            .errors(errors)
            .warnings(warnings)
            .normalizedAddress(normalizedAddress)
            .build();
    }

    private Address normalizeAddress(Address address) {
        return Address.builder()
            .street(normalizeString(address.getStreet()))
            .city(normalizeString(address.getCity()))
            .province(address.getProvince() != null ? address.getProvince().toUpperCase() : null)
            .postalCode(normalizePostalCode(address.getPostalCode(), address.getCountry()))
            .country(address.getCountry() != null ? address.getCountry().toUpperCase() : null)
            .type(address.getType() != null ? address.getType().toUpperCase() : "HOME")
            .build();
    }

    private String normalizeString(String value) {
        if (value == null) return null;
        return value.trim().replaceAll("\\s+", " ");
    }

    private String normalizePostalCode(String postalCode, String country) {
        if (postalCode == null) return null;
        String normalized = postalCode.toUpperCase().trim();

        // Canadian postal code: Add space if missing (H1A1A1 → H1A 1A1)
        if ("CA".equals(country) && normalized.length() == 6) {
            return normalized.substring(0, 3) + " " + normalized.substring(3);
        }

        return normalized;
    }
}
```

---

### C. Créer les Lambda Handlers

#### 1. `AddressValidatorHandler.java`

```java
package com.bnc.mcp.handlers;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.bnc.mcp.models.Address;
import com.bnc.mcp.models.AddressValidationResult;
import com.bnc.mcp.services.AddressValidationService;
import lombok.extern.slf4j.Slf4j;

import java.util.Map;

@Slf4j
public class AddressValidatorHandler implements RequestHandler<Map<String, Object>, AddressValidationResult> {

    private final AddressValidationService validationService;

    public AddressValidatorHandler() {
        this.validationService = new AddressValidationService();
    }

    // Constructor for testing
    public AddressValidatorHandler(AddressValidationService validationService) {
        this.validationService = validationService;
    }

    @Override
    public AddressValidationResult handleRequest(Map<String, Object> input, Context context) {
        log.info("AddressValidatorHandler invoked with requestId: {}", context.getRequestId());

        try {
            // Extract address from Step Functions input
            Map<String, String> addressMap = (Map<String, String>) input.get("address");

            Address address = Address.builder()
                .street(addressMap.get("street"))
                .city(addressMap.get("city"))
                .province(addressMap.get("province"))
                .postalCode(addressMap.get("postalCode"))
                .country(addressMap.get("country"))
                .type(addressMap.getOrDefault("type", "HOME"))
                .build();

            log.info("Validating address: {}", address);

            AddressValidationResult result = validationService.validate(address);

            log.info("Validation completed: isValid={}", result.isValid());

            return result;

        } catch (Exception e) {
            log.error("Error validating address", e);
            return AddressValidationResult.builder()
                .isValid(false)
                .errors(List.of("Internal validation error: " + e.getMessage()))
                .build();
        }
    }
}
```

#### 2. `AddressMdmaeClientHandler.java`

```java
package com.bnc.mcp.handlers;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.bnc.mcp.clients.MdmaeClient;
import com.bnc.mcp.clients.SecretsManagerClient;
import com.bnc.mcp.models.Address;
import lombok.extern.slf4j.Slf4j;

import java.util.Map;

@Slf4j
public class AddressMdmaeClientHandler implements RequestHandler<Map<String, Object>, Map<String, Object>> {

    private final MdmaeClient mdmaeClient;

    public AddressMdmaeClientHandler() {
        String secretArn = System.getenv("MDMAE_SECRET_ARN");
        SecretsManagerClient secretsClient = new SecretsManagerClient();
        Map<String, String> credentials = secretsClient.getSecret(secretArn);

        this.mdmaeClient = new MdmaeClient(
            credentials.get("url"),
            credentials.get("api_key")
        );
    }

    // Constructor for testing
    public AddressMdmaeClientHandler(MdmaeClient mdmaeClient) {
        this.mdmaeClient = mdmaeClient;
    }

    @Override
    public Map<String, Object> handleRequest(Map<String, Object> input, Context context) {
        log.info("AddressMdmaeClientHandler invoked with requestId: {}", context.getRequestId());

        try {
            String clientId = (String) input.get("clientId");
            Map<String, Object> validationResult = (Map<String, Object>) input.get("validationResult");
            Map<String, String> normalizedAddress = (Map<String, String>)
                validationResult.get("normalizedAddress");

            log.info("Sending address update to MDMAE for client: {}", clientId);

            // Call MDMAE API
            Map<String, Object> mdmaeRequest = Map.of(
                "clientId", clientId,
                "address", normalizedAddress,
                "action", "UPDATE_ADDRESS"
            );

            Map<String, Object> mdmaeResponse = mdmaeClient.updateAddress(mdmaeRequest);

            log.info("MDMAE response: {}", mdmaeResponse);

            return Map.of(
                "status", "SUCCESS",
                "mdmaeTransactionId", mdmaeResponse.get("transactionId"),
                "timestamp", System.currentTimeMillis()
            );

        } catch (Exception e) {
            log.error("Error calling MDMAE", e);
            return Map.of(
                "status", "FAILED",
                "error", e.getMessage(),
                "timestamp", System.currentTimeMillis()
            );
        }
    }
}
```

---

### D. Créer les tests

#### `AddressValidatorHandlerTest.java`

```java
package com.bnc.mcp.handlers;

import com.amazonaws.services.lambda.runtime.Context;
import com.bnc.mcp.models.AddressValidationResult;
import com.bnc.mcp.services.AddressValidationService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;

import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

class AddressValidatorHandlerTest {

    @Mock
    private AddressValidationService validationService;

    @Mock
    private Context context;

    private AddressValidatorHandler handler;

    @BeforeEach
    void setUp() {
        MockitoAnnotations.openMocks(this);
        handler = new AddressValidatorHandler(validationService);
        when(context.getRequestId()).thenReturn("test-request-id");
    }

    @Test
    void testValidAddress() {
        // Arrange
        Map<String, Object> input = Map.of(
            "clientId", "12345",
            "address", Map.of(
                "street", "123 Main St",
                "city", "Montreal",
                "province", "QC",
                "postalCode", "H1A 1A1",
                "country", "CA"
            )
        );

        AddressValidationResult expectedResult = AddressValidationResult.builder()
            .isValid(true)
            .errors(List.of())
            .build();

        when(validationService.validate(any())).thenReturn(expectedResult);

        // Act
        AddressValidationResult result = handler.handleRequest(input, context);

        // Assert
        assertTrue(result.isValid());
        verify(validationService, times(1)).validate(any());
    }

    @Test
    void testInvalidAddress() {
        // Arrange
        Map<String, Object> input = Map.of(
            "clientId", "12345",
            "address", Map.of(
                "street", "",
                "city", "Montreal",
                "province", "QC",
                "postalCode", "INVALID",
                "country", "CA"
            )
        );

        AddressValidationResult expectedResult = AddressValidationResult.builder()
            .isValid(false)
            .errors(List.of("Street is required", "Invalid postal code"))
            .build();

        when(validationService.validate(any())).thenReturn(expectedResult);

        // Act
        AddressValidationResult result = handler.handleRequest(input, context);

        // Assert
        assertFalse(result.isValid());
        assertEquals(2, result.getErrors().size());
    }
}
```

---

### E. Configurer GitHub Actions pour build et déploiement automatique (Recommandé BNC)

**⚠️ IMPORTANT** : À la BNC, le build et le déploiement des JARs Lambda se font automatiquement via GitHub Actions. **Ne copiez JAMAIS les JARs manuellement** dans mcp-infrastructure.

#### 1. Créer le workflow GitHub Actions

**Créer `.github/workflows/deploy-lambdas.yml` dans le repo `mcp-local`** :

```yaml
name: Deploy Lambda Code

on:
  workflow_dispatch:
    inputs:
      environment:
        description: 'Environment to deploy to'
        required: true
        type: choice
        options:
          - dev
          - prod
        default: 'dev'

jobs:
  build-and-deploy:
    name: Build JARs and Deploy to AWS Lambda
    runs-on: ubuntu-latest

    permissions:
      id-token: write
      contents: read

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up JDK 17
        uses: actions/setup-java@v4
        with:
          java-version: '17'
          distribution: 'corretto'
          cache: 'maven'

      - name: Build JARs with Maven
        run: |
          echo "Building Lambda JARs for environment: ${{ inputs.environment }}"
          mvn clean package -DskipTests=false
          echo "✅ Build completed successfully"

      - name: List built JARs
        run: |
          echo "Built JARs:"
          ls -lh target/*.jar

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: ca-central-1

      - name: Upload JARs to S3
        run: |
          echo "Uploading JARs to S3 bucket: bnc-mcp-lambda-artifacts"

          # Upload tous les JARs vers S3
          for jar in target/*.jar; do
            if [[ -f "$jar" ]]; then
              jar_name=$(basename "$jar")
              echo "Uploading $jar_name..."
              aws s3 cp "$jar" \
                "s3://bnc-mcp-lambda-artifacts/${{ inputs.environment }}/${jar_name}" \
                --metadata "git-commit=${{ github.sha }},build-date=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
            fi
          done

          echo "✅ All JARs uploaded to S3"

      - name: Update Lambda Functions
        run: |
          echo "Updating Lambda functions with new code..."

          # Liste des Lambdas et leurs JARs correspondants
          declare -A lambda_mappings=(
            ["client-address-update-controller"]="client-address-update-controller-1.0.0.jar"
            ["address-validator"]="address-validator-1.0.0.jar"
            ["address-mdmae-client"]="address-mdmae-client-1.0.0.jar"
            ["check-address-history"]="check-address-history-1.0.0.jar"
            ["update-core-system"]="update-core-system-1.0.0.jar"
            ["publish-to-msk"]="publish-to-msk-1.0.0.jar"
          )

          # Mettre à jour chaque Lambda
          for lambda_name in "${!lambda_mappings[@]}"; do
            jar_name="${lambda_mappings[$lambda_name]}"
            function_name="${{ inputs.environment }}-mcp-${lambda_name}"

            echo "Updating function: $function_name with JAR: $jar_name"

            # Vérifier si la fonction existe
            if aws lambda get-function --function-name "$function_name" >/dev/null 2>&1; then
              # Mettre à jour le code de la Lambda
              aws lambda update-function-code \
                --function-name "$function_name" \
                --s3-bucket "bnc-mcp-lambda-artifacts" \
                --s3-key "${{ inputs.environment }}/${jar_name}" \
                --publish

              echo "✅ Updated: $function_name"

              # Attendre que la mise à jour soit terminée
              aws lambda wait function-updated \
                --function-name "$function_name"
            else
              echo "⚠️  Function $function_name does not exist, skipping..."
            fi
          done

          echo "✅ All Lambda functions updated successfully"

      - name: Verify Lambda updates
        run: |
          echo "Verifying Lambda updates..."

          # Vérifier chaque Lambda
          declare -a lambdas=(
            "client-address-update-controller"
            "address-validator"
            "address-mdmae-client"
          )

          for lambda_name in "${lambdas[@]}"; do
            function_name="${{ inputs.environment }}-mcp-${lambda_name}"

            if aws lambda get-function --function-name "$function_name" >/dev/null 2>&1; then
              # Récupérer les détails de la Lambda
              code_sha=$(aws lambda get-function \
                --function-name "$function_name" \
                --query 'Configuration.CodeSha256' \
                --output text)

              last_modified=$(aws lambda get-function \
                --function-name "$function_name" \
                --query 'Configuration.LastModified' \
                --output text)

              echo "✅ $function_name"
              echo "   CodeSha256: $code_sha"
              echo "   LastModified: $last_modified"
            fi
          done

      - name: Post-deployment summary
        run: |
          echo "╔════════════════════════════════════════════════════════════╗"
          echo "║           DEPLOYMENT SUMMARY                               ║"
          echo "╠════════════════════════════════════════════════════════════╣"
          echo "║ Environment:       ${{ inputs.environment }}                                     ║"
          echo "║ Git Commit:        ${{ github.sha }}              ║"
          echo "║ Deployment Date:   $(date -u +%Y-%m-%d\ %H:%M:%S\ UTC)     ║"
          echo "║ Status:            ✅ SUCCESS                               ║"
          echo "╚════════════════════════════════════════════════════════════╝"

```

#### 2. Configurer les secrets GitHub

Dans le repo `mcp-local`, ajouter les secrets suivants dans **Settings → Secrets and variables → Actions** :

| Secret | Valeur | Description |
|--------|--------|-------------|
| `AWS_ROLE_ARN` | `arn:aws:iam::123456789:role/GitHubActionsDeployRole` | Rôle IAM pour GitHub Actions |

#### 3. Créer le rôle IAM pour GitHub Actions (une seule fois)

**Dans AWS Console IAM**, créer un rôle avec :

**Trust Policy** (permet à GitHub Actions d'assumer le rôle) :
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::123456789:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:bnc/mcp-local:*"
        }
      }
    }
  ]
}
```

**Permissions Policy** :
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::bnc-mcp-lambda-artifacts",
        "arn:aws:s3:::bnc-mcp-lambda-artifacts/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "lambda:UpdateFunctionCode",
        "lambda:GetFunction",
        "lambda:PublishVersion"
      ],
      "Resource": [
        "arn:aws:lambda:ca-central-1:123456789:function:dev-mcp-*",
        "arn:aws:lambda:ca-central-1:123456789:function:prod-mcp-*"
      ]
    }
  ]
}
```

#### 4. Utilisation du workflow

**Pour déployer les Lambdas sur DEV** :

1. Aller sur GitHub : `mcp-local` → **Actions** → **Deploy Lambda Code**
2. Cliquer sur **Run workflow**
3. Sélectionner :
   - **Branch** : `main`
   - **Environment** : `dev`
4. Cliquer sur **Run workflow**

**Logs attendus** :

```
Build JARs with Maven
[INFO] Building client-address-update-controller 1.0.0
[INFO] Building address-validator 1.0.0
[INFO] Building address-mdmae-client 1.0.0
[INFO] ------------------------------------------------------------------------
[INFO] BUILD SUCCESS
[INFO] ------------------------------------------------------------------------
[INFO] Total time: 1:23 min

Upload JARs to S3
Uploading client-address-update-controller-1.0.0.jar...
upload: target/client-address-update-controller-1.0.0.jar to s3://bnc-mcp-lambda-artifacts/dev/
Uploading address-validator-1.0.0.jar...
upload: target/address-validator-1.0.0.jar to s3://bnc-mcp-lambda-artifacts/dev/
Uploading address-mdmae-client-1.0.0.jar...
upload: target/address-mdmae-client-1.0.0.jar to s3://bnc-mcp-lambda-artifacts/dev/
✅ All JARs uploaded to S3

Update Lambda Functions
Updating function: dev-mcp-client-address-update-controller with JAR: client-address-update-controller-1.0.0.jar
{
  "FunctionName": "dev-mcp-client-address-update-controller",
  "FunctionArn": "arn:aws:lambda:ca-central-1:123456789:function:dev-mcp-client-address-update-controller:5",
  "CodeSha256": "abc123def456...",
  "LastModified": "2026-09-24T10:30:00.000+0000",
  "State": "Active"
}
✅ Updated: dev-mcp-client-address-update-controller

Updating function: dev-mcp-address-validator with JAR: address-validator-1.0.0.jar
✅ Updated: dev-mcp-address-validator

Updating function: dev-mcp-address-mdmae-client with JAR: address-mdmae-client-1.0.0.jar
✅ Updated: dev-mcp-address-mdmae-client

✅ All Lambda functions updated successfully

Verify Lambda updates
✅ dev-mcp-client-address-update-controller
   CodeSha256: abc123def456...
   LastModified: 2026-09-24T10:30:00.000+0000
✅ dev-mcp-address-validator
   CodeSha256: ghi789jkl012...
   LastModified: 2026-09-24T10:30:05.000+0000

╔════════════════════════════════════════════════════════════╗
║           DEPLOYMENT SUMMARY                               ║
╠════════════════════════════════════════════════════════════╣
║ Environment:       dev                                     ║
║ Git Commit:        a1b2c3d4e5f6g7h8i9j0                   ║
║ Deployment Date:   2026-09-24 10:30:15 UTC                ║
║ Status:            ✅ SUCCESS                               ║
╚════════════════════════════════════════════════════════════╝
```

---

### F. Vérification locale avant déploiement (optionnel)

Si vous voulez tester la compilation localement AVANT de déployer via GitHub Actions :

```bash
cd /Users/fabricefoko/Downloads/mcp-local

# Build local
mvn clean package

# Vérifier que les JARs sont créés
ls -lh target/*.jar
```

**Output attendu** :
```
-rw-r--r--  1 user  staff   3.2M Sep 24 10:25 client-address-update-controller-1.0.0.jar
-rw-r--r--  1 user  staff   1.8M Sep 24 10:25 address-validator-1.0.0.jar
-rw-r--r--  1 user  staff   2.1M Sep 24 10:25 address-mdmae-client-1.0.0.jar
```

**⚠️ IMPORTANT** :
- Ce build local est **uniquement pour vérification**
- **NE COPIEZ PAS** ces JARs dans `mcp-infrastructure`
- Le déploiement réel se fait **TOUJOURS** via GitHub Actions

---

## Étape 5 : Tester le workflow complet

### Vue d'ensemble du processus de test

Après avoir déployé l'infrastructure (Étape 3) et le code Lambda (Étape 4), vous pouvez maintenant tester le workflow complet.

**Prérequis** :
- ✅ Infrastructure déployée via `mcp-infrastructure` (Step Functions, API Gateway, Lambdas créées)
- ✅ Code Lambda déployé via GitHub Actions `mcp-local` (JARs uploadés et Lambdas mises à jour)

---

### 1. Vérifier que les Lambdas sont à jour

Avant de tester, vérifiez que les Lambdas ont bien été mises à jour avec le code récent :

```bash
# Vérifier la Lambda Controller
aws lambda get-function \
  --function-name dev-mcp-client-address-update-controller \
  --query 'Configuration.[FunctionName,LastModified,CodeSha256]' \
  --output table

# Vérifier la Lambda Validator
aws lambda get-function \
  --function-name dev-mcp-address-validator \
  --query 'Configuration.[FunctionName,LastModified,CodeSha256]' \
  --output table
```

**Output attendu** :
```
-------------------------------------------------------------------
|                        GetFunction                              |
+---------------------------------------+-------------------------+
|  dev-mcp-client-address-update-controller                       |
|  2026-09-24T10:30:00.000+0000                                   |
|  abc123def456...                                                |
+---------------------------------------+-------------------------+
```

**⚠️ Important** : Si `LastModified` est ancien (plus de quelques heures), re-exécutez le workflow GitHub Actions "Deploy Lambda Code".

---

### 2. Tester via API Gateway

```bash
# Récupérer l'URL de l'API depuis les outputs Terraform
API_URL="https://abc123.execute-api.ca-central-1.amazonaws.com/dev"

# Tester l'endpoint
curl -X PUT \
  "${API_URL}/api/clients/12345/address" \
  -H "Content-Type: application/json" \
  -H "Authorization: AWS4-HMAC-SHA256 ..." \
  -d '{
    "street": "123 Main Street",
    "city": "Montreal",
    "province": "QC",
    "postalCode": "H1A 1A1",
    "country": "CA",
    "type": "HOME"
  }'
```

**Réponse attendue** :
```json
{
  "executionArn": "arn:aws:states:ca-central-1:123:execution:dev-mcp-client-address-update:abc-123",
  "startDate": "2026-09-23T10:30:00.000Z"
}
```

### 3. Vérifier les logs CloudWatch

```bash
# Logs de address-validator
aws logs tail /aws/lambda/dev-mcp-address-validator --follow

# Logs de address-mdmae-client
aws logs tail /aws/lambda/dev-mcp-address-mdmae-client --follow
```

### 4. Vérifier l'exécution Step Functions

Dans AWS Console :
1. Step Functions → State machines
2. Cliquer sur `dev-mcp-client-address-update`
3. Voir les exécutions récentes
4. Cliquer sur une exécution pour voir le détail de chaque étape

### 5. Vérifier les données DynamoDB

```bash
aws dynamodb get-item \
  --table-name dev-mcp-ClientProfile \
  --key '{"clientId": {"S": "12345"}}'
```

---

## Exemple complet : Workflow "Client Address Update"

Récapitulatif de tout ce qu'on a créé pour ce workflow :

### Ressources Terraform créées :

| Ressource | Nom | Description |
|-----------|-----|-------------|
| Lambda | `address-validator` | Valide le format de l'adresse |
| Lambda | `address-mdmae-client` | Envoie l'adresse à MDMAE |
| Step Functions | `client-address-update` | Orchestre le workflow |
| API Gateway | `PUT /api/clients/{clientId}/address` | Endpoint REST |
| CloudWatch Logs | `/aws/lambda/dev-mcp-address-validator` | Logs de validation |
| CloudWatch Logs | `/aws/lambda/dev-mcp-address-mdmae-client` | Logs MDMAE |
| CloudWatch Alarm | `address-validator-errors` | Alarme d'erreurs |

### Code Java créé :

| Fichier | Description |
|---------|-------------|
| `Address.java` | Modèle de données adresse |
| `AddressValidationResult.java` | Résultat de validation |
| `AddressValidationService.java` | Logique de validation |
| `AddressValidatorHandler.java` | Lambda handler validation |
| `AddressMdmaeClientHandler.java` | Lambda handler MDMAE |
| `AddressValidatorHandlerTest.java` | Tests unitaires |

### Flow complet :

```
1. API Request
   PUT /api/clients/12345/address
   Body: {"street": "123 Main St", "city": "Montreal", ...}

   ↓

2. API Gateway
   Déclenche Step Functions "client-address-update"

   ↓

3. Step Functions démarre

   ↓

4. Lambda: client-profile-reader
   Lit le profil actuel depuis DynamoDB

   ↓

5. Lambda: address-validator
   Valide le format de l'adresse
   • Code postal valide?
   • Province valide?
   • Pays valide?

   ↓

6. Choice: Validation réussie?

   OUI ↓                    NON ↓

7. Lambda: address-         Lambda: human-review-handler
   mdmae-client             Envoie pour revue manuelle
   Envoie à MDMAE

   ↓

8. Lambda: fcc-sender
   Envoie notification FCC

   ↓

9. Success
   Workflow terminé
```

---

## Checklist complète

Utilisez cette checklist pour chaque nouveau workflow :

### Phase 1 : Analyse
- [ ] Identifier le déclencheur (API, EventBridge, SQS, MQ)
- [ ] Lister toutes les étapes du workflow
- [ ] Identifier les données à stocker (DynamoDB, S3)
- [ ] Identifier les systèmes externes (MDMAE, FCC, autres)
- [ ] Déterminer les Lambdas nécessaires
- [ ] Dessiner le diagramme du workflow

### Phase 2 : Terraform
- [ ] Créer les secrets (si nouveaux credentials)
- [ ] Créer les tables DynamoDB (si nouvelles tables)
- [ ] Créer les queues SQS (si nouvelles queues)
- [ ] Créer les dossiers Lambda avec JARs vides
- [ ] Ajouter les Lambdas dans `environments/dev/main.tf`
- [ ] Créer le template Step Functions (`.json.tpl`)
- [ ] Ajouter le state machine dans `environments/dev/main.tf`
- [ ] Créer les endpoints API Gateway (si besoin)
- [ ] Ajouter les permissions IAM
- [ ] Vérifier les alarmes CloudWatch

### Phase 3 : Déploiement Infrastructure
- [ ] `terraform plan` pour vérifier
- [ ] `terraform apply` pour créer les ressources
- [ ] Noter les ARNs et URLs dans un fichier
- [ ] Vérifier que toutes les ressources sont créées (AWS Console)

### Phase 4 : Code Java
- [ ] Créer les modèles de données (DTOs)
- [ ] Créer les services (logique métier)
- [ ] Créer les Lambda handlers
- [ ] Créer les tests unitaires
- [ ] Exécuter les tests (`mvn test`)
- [ ] Compiler les JARs (`mvn package`)
- [ ] Copier les JARs dans `mcp-infrastructure/modules/lambda/functions/`

### Phase 5 : Déploiement Code
- [ ] Redéployer Terraform avec les nouveaux JARs
- [ ] Vérifier que les Lambdas sont mises à jour (AWS Console)
- [ ] Vérifier les variables d'environnement des Lambdas

### Phase 6 : Tests
- [ ] Tester l'API avec curl/Postman
- [ ] Vérifier les logs CloudWatch
- [ ] Vérifier l'exécution Step Functions
- [ ] Vérifier les données DynamoDB
- [ ] Tester les scénarios d'erreur
- [ ] Tester les alarmes CloudWatch

### Phase 7 : Documentation
- [ ] Mettre à jour `README.md`
- [ ] Documenter l'API (Swagger/OpenAPI)
- [ ] Ajouter des exemples de requêtes
- [ ] Documenter les variables d'environnement
- [ ] Créer un runbook pour les opérations

---

## Bonnes pratiques

### 1. Tester localement avant déploiement

**📘 Voir le guide complet** : [`LOCAL_TESTING_GUIDE.md`](./LOCAL_TESTING_GUIDE.md)

Avant de déployer via GitHub Actions, testez votre code localement avec l'une de ces 4 options :

| Option | Rapidité | Réalisme | Utilisation |
|--------|----------|----------|-------------|
| **1. Tests unitaires** | ⚡ Très rapide | ⭐ Faible | Valider la logique métier |
| **2. AWS SAM CLI** | ⚡ Rapide | ⭐⭐⭐ Moyen | Simuler API Gateway + Lambda localement |
| **3. Terraform local** | 🐌 Lent | ⭐⭐⭐⭐ Élevé | Tester sur AWS avant PR |
| **4. Spring Boot wrapper** | ⚡ Très rapide | ⭐⭐ Faible | Développement itératif rapide |

**Recommandation BNC** : Utilisez **Option 2 (AWS SAM CLI)** pour valider l'intégration complète avant de créer une PR.

**Exemple rapide avec SAM CLI** :
```bash
# 1. Build les JARs
mvn clean package

# 2. Démarrer SAM local (simule API Gateway + Lambda)
sam local start-api --template template.yaml

# 3. Tester avec curl
curl -X PUT http://localhost:3000/api/clients/123/address \
  -H "Content-Type: application/json" \
  -d '{"street":"123 Main","city":"Montreal","province":"QC","postalCode":"H1A1A1","country":"CA"}'
```

**⚠️ IMPORTANT** : Ne copiez JAMAIS les JARs manuellement dans `mcp-infrastructure`. Le déploiement se fait automatiquement via GitHub Actions.

---

### 2. Nommage cohérent

**Lambdas** : `<action>-<resource>` ou `<resource>-<action>`
- Bon : `address-validator`, `client-profile-reader`
- Mauvais : `validateAddr`, `readProf`

**State Machines** : `<resource>-<action>`
- Bon : `client-address-update`, `client-name-update`
- Mauvais : `updateAddress`, `nameChange`

**Tables DynamoDB** : `PascalCase` avec suffixe descriptif
- Bon : `ClientProfile`, `AddressHistory`
- Mauvais : `clients`, `addr_hist`

### 2. Gestion des erreurs

- Toujours utiliser `Catch` dans Step Functions
- Logger tous les détails d'erreur
- Créer des alarmes pour les taux d'erreur élevés
- Implémenter des DLQ pour SQS

### 3. Sécurité

- Toujours marquer les secrets comme `sensitive = true`
- Utiliser AWS Secrets Manager (jamais de hardcode)
- Activer le chiffrement S3 et DynamoDB
- Utiliser IAM avec principe du moindre privilège

### 4. Performance

- Optimiser la taille mémoire Lambda (512 MB par défaut)
- Ajuster les timeouts (30s pour simple, 60s+ pour appels externes)
- Utiliser VPC uniquement si nécessaire (cold start plus lent)
- Mettre en cache les clients AWS (DynamoDB, Secrets Manager)

### 5. Coûts

- Utiliser `PAY_PER_REQUEST` pour DynamoDB (évite over-provisioning)
- Configurer la rétention CloudWatch Logs (ex: 7 jours pour dev)
- Utiliser ARM64 pour Lambda (20% moins cher)
- Supprimer les anciennes versions Lambda

---

**Dernière mise à jour** : 2026-09-23
**Auteur** : Claude Code