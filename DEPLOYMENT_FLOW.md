# Flow de Déploiement - Étape par Étape

Ce document explique **exactement** ce qui se passe quand vous déclenchez manuellement le workflow GitHub Actions.

---

## Table des matières

1. [Rôle détaillé de chaque fichier](#rôle-détaillé-de-chaque-fichier)
2. [Vue d'ensemble](#vue-densemble)
3. [Étapes du déploiement](#étape-1-déclenchement-manuel-vous)
4. [Timeline complète](#timeline-complète-exemple-pour-dev)
5. [Récapitulatif](#récapitulatif-de-lordre-des-fichiers)

---

## Rôle détaillé de chaque fichier

Voici **tous** les fichiers lus pendant le déploiement, dans l'ordre chronologique exact, avec leur rôle précis :

### 1. `.github/workflows/terraform-deploy.yml`

**Quand**: Tout au début, quand vous cliquez "Run workflow"

**Rôle**:
- Définit le workflow GitHub Actions
- Configure les inputs (environment, action)
- Orchestre toutes les étapes (checkout, AWS config, Terraform)
- Injecte les secrets GitHub comme variables d'environnement `TF_VAR_*`

**Lecture par**: GitHub Actions

**Contenu clé**:
```yaml
on:
  workflow_dispatch:  # Permet le déclenchement manuel
    inputs:
      environment: dev/prod
      action: plan/apply/destroy

env:
  TF_VAR_ibm_mq_host: ${{ secrets.DEV_IBM_MQ_HOST }}
  # Injecte les secrets comme variables Terraform
```

---

### 2. `environments/dev/backend.tf`

**Quand**: Pendant `terraform init`

**Rôle**:
- Configure où Terraform stocke son state (fichier de suivi des ressources)
- Définit le bucket S3 pour le state
- Définit la table DynamoDB pour le locking (évite les conflits)

**Lecture par**: Terraform CLI

**Actions déclenchées**:
1. Terraform se connecte à AWS S3 bucket `mcp-terraform-state-dev`
2. Télécharge le state existant `infrastructure/terraform.tfstate` (si c'est un redéploiement)
3. Acquiert un lock dans DynamoDB `mcp-terraform-lock-dev`

**Contenu clé**:
```hcl
terraform {
  backend "s3" {
    bucket         = "mcp-terraform-state-dev"
    key            = "infrastructure/terraform.tfstate"
    region         = "ca-central-1"
    encrypt        = true
    dynamodb_table = "mcp-terraform-lock-dev"
  }
}
```

---

### 3. `environments/dev/variables.tf`

**Quand**: Pendant `terraform plan/apply`, avant de lire `main.tf`

**Rôle**:
- Déclare toutes les variables que Terraform attend
- Définit les types (string, number, bool)
- Marque les variables sensibles (passwords, credentials)

**Lecture par**: Terraform CLI

**Ce qui se passe**:
- Terraform lit les déclarations de variables
- Terraform cherche les valeurs correspondantes dans les `TF_VAR_*` injectées par GitHub

**Contenu clé**:
```hcl
variable "ibm_mq_host" {
  description = "IBM MQ host address"
  type        = string
  sensitive   = true  # Ne sera jamais affiché dans les logs
}

variable "ibm_mq_port" {
  type    = number
  default = 1414
}
# ... toutes les autres variables
```

---

### 4. Variables GitHub → `TF_VAR_*` (Variables d'environnement)

**Quand**: Avant `terraform plan/apply`, configurées par GitHub Actions

**Rôle**:
- Fournir les valeurs réelles pour les variables déclarées dans `variables.tf`
- Injecter les secrets de manière sécurisée (jamais visibles dans les logs)

**Créées par**: GitHub Actions (depuis le workflow)

**Format**:
```bash
# GitHub Actions crée ces variables d'environnement:
TF_VAR_ibm_mq_host="0.tcp.ngrok.io"          # Depuis secrets.DEV_IBM_MQ_HOST
TF_VAR_ibm_mq_port="12345"                   # Depuis secrets.DEV_IBM_MQ_PORT
TF_VAR_ibm_mq_channel="DEV.APP.SVRCONN"      # Depuis secrets.DEV_IBM_MQ_CHANNEL
TF_VAR_ibm_mq_password="passw0rd"            # Depuis secrets.DEV_IBM_MQ_PASSWORD
TF_VAR_mdmae_url="https://mdmae-dev.com/api" # Depuis secrets.DEV_MDMAE_URL
TF_VAR_mdmae_api_key="api-key-123"           # Depuis secrets.DEV_MDMAE_API_KEY
```

**Mapping automatique**:
- `TF_VAR_ibm_mq_host` → `var.ibm_mq_host` dans Terraform
- `TF_VAR_ibm_mq_port` → `var.ibm_mq_port` dans Terraform
- Etc.

---

### 5. `environments/dev/main.tf`

**Quand**: Pendant `terraform plan/apply`, après avoir lu les variables

**Rôle**:
- **FICHIER CENTRAL** qui orchestre tout le déploiement
- Appelle tous les modules (secrets, dynamodb, lambda, etc.)
- Passe les variables aux modules
- Définit les dépendances entre modules

**Lecture par**: Terraform CLI

**Ce qui se passe ligne par ligne**:

```hcl
# Ligne 1-3: Configuration du provider AWS
terraform {
  required_version = ">= 1.9.0"
}
# → Terraform vérifie sa propre version

# Ligne 5-6: Data sources (récupération d'infos AWS)
data "aws_caller_identity" "current" {}
# → API Call: Terraform appelle AWS pour obtenir l'account ID
# → AWS répond: "123456789012"

data "aws_region" "current" {}
# → API Call: Terraform demande la région actuelle
# → AWS répond: "ca-central-1"

# Ligne 12-35: Module Secrets Manager
module "secrets" {
  source = "../../modules/secrets-manager"
  # → Terraform va charger modules/secrets-manager/{main,variables,outputs}.tf

  secrets = {
    ibmmq = {
      description = "IBM MQ credentials for dev"
      secret_data = {
        host     = var.ibm_mq_host        # = "0.tcp.ngrok.io"
        port     = var.ibm_mq_port        # = "12345"
        channel  = var.ibm_mq_channel     # = "DEV.APP.SVRCONN"
        password = var.ibm_mq_password    # = "passw0rd"
      }
    }
    mdmae = {
      description = "MDMAE API credentials for dev"
      secret_data = {
        url     = var.mdmae_url          # = "https://mdmae-dev.com/api"
        api_key = var.mdmae_api_key      # = "api-key-123"
      }
    }
  }
}

# Ligne 41-49: Module DynamoDB
module "dynamodb" {
  source = "../../modules/dynamodb"
  # → Charge modules/dynamodb/{main,variables,outputs}.tf

  environment = "dev"
  table_name  = "ClientProfile"
}

# Ligne 55-68: Module SQS
module "sqs" {
  source = "../../modules/sqs"
  # → Charge modules/sqs/{main,variables,outputs}.tf

  queues = {
    fcc_responses = {
      visibility_timeout_seconds = 300
      message_retention_seconds  = 86400
    }
  }
}

# Ligne 74-83: Module VPC
module "vpc" {
  source = "../../modules/vpc"
  # → Charge modules/vpc/{main,variables,outputs}.tf

  environment = "dev"
  vpc_cidr    = "10.0.0.0/16"
}

# Ligne 89-106: Module MSK
module "msk" {
  source = "../../modules/msk"
  # → Charge modules/msk/{main,variables,outputs}.tf
  # → Dépend de module.vpc (besoin des subnet IDs)

  cluster_name = "dev-mcp-msk"
  subnet_ids   = module.vpc.private_subnet_ids  # Dépendance!
}

# Ligne 112-121: Module IAM
module "iam" {
  source = "../../modules/iam"
  # → Charge modules/iam/{main,variables,outputs}.tf
  # → Dépend de secrets, dynamodb, sqs, msk (besoin des ARNs)

  secrets_arns         = module.secrets.secret_arns
  dynamodb_table_arn   = module.dynamodb.table_arn
  sqs_queue_arns       = module.sqs.queue_arns
  msk_cluster_arn      = module.msk.cluster_arn
}

# Ligne 127-184: Module Lambda
module "lambda" {
  source = "../../modules/lambda"
  # → Charge modules/lambda/{main,variables,outputs}.tf
  # → Dépend de iam, vpc, secrets (besoin des roles, subnets, secret ARNs)

  lambda_execution_role_arn = module.iam.lambda_execution_role_arn
  subnet_ids                = module.vpc.private_subnet_ids
  security_group_ids        = [module.vpc.lambda_security_group_id]

  functions = {
    client-profile-reader = { memory = 512, timeout = 30 }
    name-validator        = { memory = 512, timeout = 30 }
    mdmae-client         = { memory = 1024, timeout = 60 }
    # ... 7 fonctions au total
  }
}

# Ligne 190-205: Module EventBridge
module "eventbridge" {
  source = "../../modules/eventbridge"
  # → Charge modules/eventbridge/{main,variables,outputs}.tf
  # → Dépend de lambda (besoin des function ARNs)

  lambda_function_arns = module.lambda.function_arns
}

# Ligne 211-237: Module Step Functions
module "step_functions" {
  source = "../../modules/step-functions"
  # → Charge modules/step-functions/{main,variables,outputs}.tf
  # → Charge aussi state-machines/client-name-update.json.tpl
  # → Dépend de lambda, iam (besoin des function ARNs et role ARN)

  lambda_function_arns      = module.lambda.function_arns
  step_functions_role_arn   = module.iam.step_functions_role_arn
}

# Ligne 243-258: Module API Gateway
module "api_gateway" {
  source = "../../modules/api-gateway"
  # → Charge modules/api-gateway/{main,variables,outputs}.tf
  # → Dépend de step_functions (besoin du state machine ARN)

  state_machine_arn = module.step_functions.state_machine_arns["client-name-update"]
}

# Ligne 264-290: Module CloudWatch
module "cloudwatch" {
  source = "../../modules/cloudwatch"
  # → Charge modules/cloudwatch/{main,variables,outputs}.tf
  # → Dépend de lambda, step_functions (besoin des ARNs pour les alarms)

  lambda_function_arns     = module.lambda.function_arns
  state_machine_arns       = module.step_functions.state_machine_arns
  enable_alarms            = true
}
```

**Résultat**: Terraform a maintenant chargé **tous** les modules et connaît toutes les dépendances

---

### 6. Modules individuels (chargés par `main.tf`)

Chaque module est composé de 3 fichiers standards:

#### 6.1 `modules/secrets-manager/*.tf`

**Rôle**: Créer et gérer les secrets dans AWS Secrets Manager

**Fichiers**:
- `main.tf`: Définit les ressources `aws_secretsmanager_secret` et `aws_secretsmanager_secret_version`
- `variables.tf`: Déclare les inputs (secrets map)
- `outputs.tf`: Exporte les ARNs des secrets créés

**API Calls générés**:
```
POST https://secretsmanager.ca-central-1.amazonaws.com/
Body: {
  "Name": "dev/mcp/ibmmq",
  "Description": "IBM MQ credentials for dev"
}

PUT https://secretsmanager.ca-central-1.amazonaws.com/
Body: {
  "SecretId": "arn:aws:...",
  "SecretString": "{\"host\":\"0.tcp.ngrok.io\",\"port\":\"12345\",...}"
}
```

---

#### 6.2 `modules/dynamodb/*.tf`

**Rôle**: Créer la table DynamoDB pour stocker les profils clients

**Fichiers**:
- `main.tf`: Définit la ressource `aws_dynamodb_table`
- `variables.tf`: Inputs (environment, table_name, billing_mode)
- `outputs.tf`: Exporte le nom et l'ARN de la table

**API Call généré**:
```
POST https://dynamodb.ca-central-1.amazonaws.com/
Body: {
  "TableName": "dev-mcp-ClientProfile",
  "KeySchema": [{"AttributeName": "clientId", "KeyType": "HASH"}],
  "BillingMode": "PAY_PER_REQUEST",
  "SSESpecification": {"Enabled": true}
}
```

---

#### 6.3 `modules/sqs/*.tf`

**Rôle**: Créer les queues SQS et leurs Dead Letter Queues (DLQ)

**Fichiers**:
- `main.tf`: Définit `aws_sqs_queue` (queue principale + DLQ)
- `variables.tf`: Inputs (queues map, retention, timeout)
- `outputs.tf`: Exporte les URLs et ARNs des queues

**API Calls générés**:
```
POST https://sqs.ca-central-1.amazonaws.com/
Body: {
  "QueueName": "dev-mcp-fcc_responses",
  "Attributes": {
    "VisibilityTimeout": "300",
    "MessageRetentionPeriod": "86400"
  }
}

POST https://sqs.ca-central-1.amazonaws.com/
Body: {
  "QueueName": "dev-mcp-fcc_responses-dlq",
  "Attributes": {"MessageRetentionPeriod": "1209600"}
}
```

---

#### 6.4 `modules/vpc/*.tf`

**Rôle**: Créer le réseau privé (VPC, subnets, security groups)

**Fichiers**:
- `main.tf`: Définit VPC, subnets, security groups, route tables
- `variables.tf`: Inputs (vpc_cidr, environment)
- `outputs.tf`: Exporte VPC ID, subnet IDs, security group IDs

**API Calls générés**:
```
# VPC
POST https://ec2.ca-central-1.amazonaws.com/
Body: {
  "CidrBlock": "10.0.0.0/16",
  "EnableDnsHostnames": true,
  "EnableDnsSupport": true
}

# Subnets (x2)
POST https://ec2.ca-central-1.amazonaws.com/
Body: {
  "VpcId": "vpc-123abc",
  "CidrBlock": "10.0.1.0/24",
  "AvailabilityZone": "ca-central-1a"
}

# Security Groups (x2)
POST https://ec2.ca-central-1.amazonaws.com/
Body: {
  "GroupName": "dev-mcp-msk-sg",
  "VpcId": "vpc-123abc",
  "Description": "Security group for MSK cluster"
}
```

---

#### 6.5 `modules/msk/*.tf`

**Rôle**: Créer le cluster Kafka MSK Serverless

**Fichiers**:
- `main.tf`: Définit `aws_msk_serverless_cluster`
- `variables.tf`: Inputs (cluster_name, subnet_ids, security_group_ids)
- `outputs.tf`: Exporte cluster ARN, bootstrap brokers

**Dépendances**: Attend que VPC et subnets soient créés

**API Call généré**:
```
POST https://kafka.ca-central-1.amazonaws.com/
Body: {
  "ClusterName": "dev-mcp-msk",
  "Serverless": {
    "VpcConfigs": [{
      "SubnetIds": ["subnet-123", "subnet-456"],
      "SecurityGroupIds": ["sg-789"]
    }],
    "ClientAuthentication": {
      "Sasl": {"Iam": {"Enabled": true}}
    }
  }
}
```

**⏳ Durée**: 14-15 minutes (la ressource la plus longue!)

---

#### 6.6 `modules/iam/*.tf`

**Rôle**: Créer les rôles et policies IAM pour Lambda, Step Functions, etc.

**Fichiers**:
- `main.tf`: Définit les rôles, policies, attachments
- `variables.tf`: Inputs (ARNs des ressources à autoriser)
- `outputs.tf`: Exporte les ARNs des rôles créés

**Dépendances**: Attend secrets, dynamodb, sqs, msk (besoin des ARNs)

**API Calls générés**:
```
# Rôle Lambda
POST https://iam.amazonaws.com/
Body: {
  "RoleName": "dev-mcp-lambda-execution-role",
  "AssumeRolePolicyDocument": "{\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"lambda.amazonaws.com\"},\"Action\":\"sts:AssumeRole\"}]}"
}

# Policy Lambda
PUT https://iam.amazonaws.com/
Body: {
  "RoleName": "dev-mcp-lambda-execution-role",
  "PolicyName": "lambda-execution-policy",
  "PolicyDocument": {
    "Statement": [
      {"Effect": "Allow", "Action": ["dynamodb:*"], "Resource": "arn:aws:dynamodb:...:table/dev-mcp-ClientProfile"},
      {"Effect": "Allow", "Action": ["secretsmanager:GetSecretValue"], "Resource": "arn:aws:secretsmanager:...:secret:dev/mcp/ibmmq"},
      {"Effect": "Allow", "Action": ["sqs:*"], "Resource": "arn:aws:sqs:...:dev-mcp-fcc_responses"},
      {"Effect": "Allow", "Action": ["kafka:*"], "Resource": "arn:aws:kafka:...:cluster/dev-mcp-msk"}
    ]
  }
}
```

---

#### 6.7 `modules/lambda/*.tf`

**Rôle**: Déployer les 7 fonctions Lambda (JARs Java)

**Fichiers**:
- `main.tf`: Définit `aws_lambda_function`, CloudWatch log groups, event source mappings
- `variables.tf`: Inputs (function configs, role ARN, VPC config)
- `outputs.tf`: Exporte les ARNs des fonctions

**Dépendances**: Attend IAM, VPC, Secrets Manager

**Fonctions déployées**:
1. `client-profile-reader` - Lit DynamoDB
2. `name-validator` - Valide les noms
3. `mdmae-client` - Appelle l'API MDMAE
4. `fcc-sender` - Envoie les messages FCC
5. `human-review-handler` - Gère les revues manuelles
6. `mq-poller` - Lit les messages IBM MQ
7. `fcc-response-processor` - Traite les réponses FCC de SQS

**API Calls générés** (x7):
```
POST https://lambda.ca-central-1.amazonaws.com/2015-03-31/functions
Body: {
  "FunctionName": "dev-mcp-client-profile-reader",
  "Runtime": "java17",
  "Role": "arn:aws:iam::123:role/dev-mcp-lambda-execution-role",
  "Handler": "com.bnc.mcp.api.LambdaHandler::handleRequest",
  "Code": {
    "ZipFile": "<binary JAR content, 45 MB>"
  },
  "MemorySize": 512,
  "Timeout": 30,
  "VpcConfig": {
    "SubnetIds": ["subnet-123", "subnet-456"],
    "SecurityGroupIds": ["sg-789"]
  },
  "Environment": {
    "Variables": {
      "DYNAMODB_TABLE": "dev-mcp-ClientProfile",
      "IBM_MQ_SECRET_ARN": "arn:aws:secretsmanager:...:secret:dev/mcp/ibmmq"
    }
  }
}
```

**⏳ Durée**: 1m15s (upload de 7 JARs en parallèle)

---

#### 6.8 `modules/eventbridge/*.tf`

**Rôle**: Créer les règles EventBridge pour déclencher les Lambdas périodiquement

**Fichiers**:
- `main.tf`: Définit `aws_cloudwatch_event_rule` et `aws_cloudwatch_event_target`
- `variables.tf`: Inputs (rules map, lambda ARNs)
- `outputs.tf`: Exporte les ARNs des règles

**Dépendances**: Attend Lambda, IAM

**API Calls générés**:
```
POST https://events.ca-central-1.amazonaws.com/
Body: {
  "Name": "dev-mcp-mq-poller-schedule",
  "ScheduleExpression": "rate(1 minute)",
  "State": "ENABLED"
}

PUT https://events.ca-central-1.amazonaws.com/
Body: {
  "Rule": "dev-mcp-mq-poller-schedule",
  "Targets": [{
    "Id": "1",
    "Arn": "arn:aws:lambda:...:function:dev-mcp-mq-poller"
  }]
}
```

---

#### 6.9 `modules/step-functions/*.tf` + `state-machines/*.json.tpl`

**Rôle**: Créer les workflows Step Functions (orchestration)

**Fichiers**:
- `main.tf`: Définit `aws_sfn_state_machine` avec templatefile()
- `variables.tf`: Inputs (state_machines map, lambda ARNs, role ARN)
- `outputs.tf`: Exporte les ARNs des state machines
- `state-machines/client-name-update.json.tpl`: Template de la définition JSON

**Dépendances**: Attend Lambda, IAM

**Ce qui se passe**:
1. Terraform lit `client-name-update.json.tpl`
2. Terraform remplace les variables `${client_profile_reader_arn}` par les ARNs réels
3. Terraform envoie la définition JSON complète à AWS

**Template (`state-machines/client-name-update.json.tpl`)**:
```json
{
  "Comment": "Client Name Update Workflow",
  "StartAt": "ReadClientProfile",
  "States": {
    "ReadClientProfile": {
      "Type": "Task",
      "Resource": "${client_profile_reader_arn}",
      "Next": "ValidateName"
    },
    "ValidateName": {
      "Type": "Task",
      "Resource": "${name_validator_arn}",
      "Next": "CallMDMAE"
    },
    "CallMDMAE": {
      "Type": "Task",
      "Resource": "${mdmae_client_arn}",
      "Next": "SendFCC"
    },
    "SendFCC": {
      "Type": "Task",
      "Resource": "${fcc_sender_arn}",
      "End": true
    }
  }
}
```

**Définition finale** (après remplacement):
```json
{
  "Comment": "Client Name Update Workflow",
  "StartAt": "ReadClientProfile",
  "States": {
    "ReadClientProfile": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:ca-central-1:123:function:dev-mcp-client-profile-reader",
      "Next": "ValidateName"
    },
    "ValidateName": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:ca-central-1:123:function:dev-mcp-name-validator",
      "Next": "CallMDMAE"
    }
    // ... etc
  }
}
```

**API Call généré**:
```
POST https://states.ca-central-1.amazonaws.com/
Body: {
  "name": "dev-mcp-client-name-update",
  "roleArn": "arn:aws:iam::123:role/dev-mcp-step-functions-role",
  "definition": "<JSON complet ci-dessus>",
  "type": "STANDARD"
}
```

---

#### 6.10 `modules/api-gateway/*.tf`

**Rôle**: Créer l'API REST publique qui déclenche Step Functions

**Fichiers**:
- `main.tf`: Définit REST API, resources, methods, integrations, deployment, stage
- `variables.tf`: Inputs (api_name, state_machine_arn)
- `outputs.tf`: Exporte l'URL de l'API

**Dépendances**: Attend Step Functions (besoin du state machine ARN)

**Structure créée**:
```
API Gateway REST API
├─ /api
│  └─ /clients
│     └─ /{clientId}
│        └─ /nom
│           └─ PUT method
│              └─ Integration: Step Functions
└─ Deployment → Stage "dev"
```

**API Calls générés**:
```
# REST API
POST https://apigateway.ca-central-1.amazonaws.com/restapis
Body: {
  "name": "dev-mcp-api",
  "description": "MCP Client Name Update API"
}

# Resources (4x: api, clients, {clientId}, nom)
POST https://apigateway.ca-central-1.amazonaws.com/restapis/abc123/resources
Body: {"parentId": "root", "pathPart": "api"}

# Method
PUT https://apigateway.ca-central-1.amazonaws.com/restapis/abc123/resources/xyz789/methods/PUT
Body: {
  "authorizationType": "AWS_IAM",
  "requestParameters": {"method.request.path.clientId": true}
}

# Integration
PUT https://apigateway.ca-central-1.amazonaws.com/restapis/abc123/resources/xyz789/methods/PUT/integration
Body: {
  "type": "AWS",
  "integrationHttpMethod": "POST",
  "uri": "arn:aws:apigateway:ca-central-1:states:action/StartExecution",
  "requestTemplates": {
    "application/json": "{\"stateMachineArn\":\"arn:aws:states:...:stateMachine:dev-mcp-client-name-update\",\"input\":\"{\\\"clientId\\\":\\\"$input.params('clientId')\\\"}\"}"
  }
}

# Deployment
POST https://apigateway.ca-central-1.amazonaws.com/restapis/abc123/deployments
Body: {"stageName": "dev"}
```

**URL finale**: `https://abc123.execute-api.ca-central-1.amazonaws.com/dev/api/clients/{clientId}/nom`

---

#### 6.11 `modules/cloudwatch/*.tf`

**Rôle**: Créer les alarmes CloudWatch pour surveiller les erreurs

**Fichiers**:
- `main.tf`: Définit `aws_cloudwatch_metric_alarm` pour Lambda, Step Functions, etc.
- `variables.tf`: Inputs (enable_alarms, lambda ARNs, thresholds)
- `outputs.tf`: Exporte les ARNs des alarmes

**Dépendances**: Attend Lambda, Step Functions

**API Calls générés** (x20+):
```
PUT https://monitoring.ca-central-1.amazonaws.com/
Body: {
  "AlarmName": "dev-mcp-lambda-client-profile-reader-errors",
  "ComparisonOperator": "GreaterThanThreshold",
  "EvaluationPeriods": 1,
  "MetricName": "Errors",
  "Namespace": "AWS/Lambda",
  "Period": 60,
  "Statistic": "Sum",
  "Threshold": 5,
  "Dimensions": [{
    "Name": "FunctionName",
    "Value": "dev-mcp-client-profile-reader"
  }]
}
```

---

### 7. `environments/dev/outputs.tf`

**Quand**: À la toute fin, après que toutes les ressources sont créées

**Rôle**:
- Définit ce que Terraform affiche comme résultat
- Exporte les informations importantes (URLs, ARNs, noms de ressources)

**Lecture par**: Terraform CLI

**Contenu clé**:
```hcl
output "api_gateway_url" {
  description = "URL de l'API Gateway"
  value       = module.api_gateway.api_url
}

output "dynamodb_table_name" {
  value = module.dynamodb.table_name
}

output "lambda_function_arns" {
  value     = module.lambda.function_arns
  sensitive = false
}

output "msk_cluster_arn" {
  value = module.msk.cluster_arn
}
```

**Affichage final dans les logs**:
```
Outputs:

api_gateway_url = "https://abc123.execute-api.ca-central-1.amazonaws.com/dev/api/clients/{clientId}/nom"
dynamodb_table_name = "dev-mcp-ClientProfile"
lambda_function_arns = {
  "client-profile-reader" = "arn:aws:lambda:ca-central-1:123:function:dev-mcp-client-profile-reader"
  "name-validator" = "arn:aws:lambda:ca-central-1:123:function:dev-mcp-name-validator"
  # ... 7 fonctions
}
msk_cluster_arn = "arn:aws:kafka:ca-central-1:123:cluster/dev-mcp-msk/..."
```

---

## Vue d'ensemble

```
Clic "Run workflow"
    ↓
GitHub Actions démarre
    ↓
Configure AWS credentials
    ↓
Terraform init (charge les modules)
    ↓
Terraform plan/apply (crée les ressources)
    ↓
Upload des outputs
    ↓
Déploiement terminé ✅
```

---

## Étape 1: Déclenchement manuel (Vous)

**Action:** Vous cliquez sur "Run workflow" dans GitHub

**Interface GitHub:**
```
Repository → Actions → Terraform Deploy → Run workflow

Inputs:
├─ Branch: main
├─ Environment: dev (ou prod)
└─ Action: plan (ou apply ou destroy)
```

**Ce qui se passe:**
- GitHub reçoit votre demande
- GitHub lit `.github/workflows/terraform-deploy.yml`
- GitHub crée un "runner" (machine virtuelle Ubuntu)

**Fichier lu:** `.github/workflows/terraform-deploy.yml`

---

## Étape 2: GitHub Actions démarre (GitHub)

**GitHub Actions lit le workflow:**

```yaml
# .github/workflows/terraform-deploy.yml
name: Terraform Deploy

on:
  workflow_dispatch:
    inputs:
      environment:
        type: choice
        options: [dev, prod]
      action:
        type: choice
        options: [plan, apply, destroy]
```

**Ce qui se passe:**
1. GitHub crée une VM Ubuntu (le "runner")
2. GitHub clone votre repository dans `/home/runner/work/mcp-infrastructure/mcp-infrastructure`
3. GitHub charge les variables d'entrée:
   - `${{ inputs.environment }}` = "dev" (ou "prod")
   - `${{ inputs.action }}` = "plan" (ou "apply")

**Logs visibles:**
```
Set up job
  ✓ Virtual machine created
  ✓ Repository cloned
```

---

## Étape 3: Checkout du code (GitHub Actions)

```yaml
- name: Checkout code
  uses: actions/checkout@v4
```

**Ce qui se passe:**
- GitHub clone votre repo dans le runner
- Tous les fichiers sont maintenant disponibles:
  ```
  /home/runner/work/mcp-infrastructure/mcp-infrastructure/
  ├── modules/
  ├── environments/
  ├── scripts/
  └── .github/
  ```

**Logs visibles:**
```
Checkout code
  ✓ Fetching the repository
  ✓ Checking out ref: main
```

---

## Étape 4: Configuration AWS (GitHub Actions)

```yaml
- name: Configure AWS credentials
  uses: aws-actions/configure-aws-credentials@v4
  with:
    aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
    aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
    aws-region: ${{ secrets.AWS_REGION }}
```

**Ce qui se passe:**
1. GitHub lit les secrets que vous avez configurés
2. GitHub crée un fichier `~/.aws/credentials`:
   ```ini
   [default]
   aws_access_key_id = AKIAIOSFODNN7EXAMPLE
   aws_secret_access_key = wJalrXUtnFEMI/K7MDENG/...
   region = ca-central-1
   ```
3. AWS CLI est maintenant configuré

**Logs visibles:**
```
Configure AWS credentials
  ✓ Credentials configured
  ✓ Region: ca-central-1
```

---

## Étape 5: Installation de Terraform (GitHub Actions)

```yaml
- name: Setup Terraform
  uses: hashicorp/setup-terraform@v3
  with:
    terraform_version: 1.9.0
```

**Ce qui se passe:**
1. GitHub télécharge Terraform 1.9.0
2. GitHub installe Terraform dans `/usr/local/bin/terraform`
3. Terraform est maintenant disponible en ligne de commande

**Logs visibles:**
```
Setup Terraform
  ✓ Downloading Terraform 1.9.0
  ✓ Terraform installed
```

---

## Étape 6: Terraform Init (Terraform commence ici!)

```yaml
- name: Terraform Init
  working-directory: environments/${{ inputs.environment }}
  run: terraform init
```

**Exemple: Si vous avez sélectionné "dev"**

**Répertoire de travail:** `environments/dev/`

**Terraform lit:** `environments/dev/backend.tf`

```hcl
terraform {
  backend "s3" {
    bucket         = "mcp-terraform-state-dev"
    key            = "infrastructure/terraform.tfstate"
    region         = "ca-central-1"
    encrypt        = true
    dynamodb_table = "mcp-terraform-lock-dev"
  }
}
```

**Ce qui se passe:**
1. Terraform se connecte à AWS
2. Terraform vérifie que le bucket S3 `mcp-terraform-state-dev` existe
3. Terraform télécharge le fichier `terraform.tfstate` depuis S3 (s'il existe)
4. Terraform acquiert un lock dans DynamoDB `mcp-terraform-lock-dev`
5. Terraform télécharge les providers AWS depuis le Terraform Registry

**Fichiers créés localement:**
```
environments/dev/
├── .terraform/              ← Nouveau dossier créé
│   ├── providers/
│   │   └── registry.terraform.io/
│   │       └── hashicorp/aws/5.x.x/
│   └── terraform.tfstate    ← State téléchargé de S3
└── .terraform.lock.hcl      ← Lock file
```

**Logs visibles:**
```
Terraform Init
  ✓ Initializing the backend...
  ✓ Downloading state from S3
  ✓ Acquiring lock from DynamoDB
  ✓ Downloading provider: hashicorp/aws v5.x.x
  ✓ Terraform has been successfully initialized!
```

---

## Étape 7: Terraform Plan ou Apply (Le déploiement!)

### Si action = "plan"

```yaml
- name: Terraform Plan
  working-directory: environments/${{ inputs.environment }}
  run: terraform plan -out=tfplan
  env:
    TF_VAR_ibm_mq_host: ${{ secrets.DEV_IBM_MQ_HOST }}
    TF_VAR_ibm_mq_port: ${{ secrets.DEV_IBM_MQ_PORT }}
    # ... autres variables
```

**Terraform lit les fichiers dans cet ordre exact:**

#### 7.1 - Lecture de `backend.tf`
```hcl
# Déjà lu pendant init
```

#### 7.2 - Lecture de `variables.tf`
```hcl
# environments/dev/variables.tf
variable "ibm_mq_host" {
  type = string
  sensitive = true
}
# ... toutes les variables déclarées
```

**Terraform note:** "J'ai besoin de valeurs pour ces variables"

#### 7.3 - Lecture des variables d'environnement
```bash
# Les secrets GitHub sont injectés comme variables d'environnement
TF_VAR_ibm_mq_host="0.tcp.ngrok.io"
TF_VAR_ibm_mq_port="12345"
TF_VAR_ibm_mq_channel="DEV.APP.SVRCONN"
# ...
```

**Terraform note:** "OK, j'ai les valeurs maintenant!"

#### 7.4 - Lecture de `main.tf`
```hcl
# environments/dev/main.tf

# Terraform lit ligne par ligne:

data "aws_caller_identity" "current" {}
# → Terraform appelle AWS pour obtenir l'account ID

module "secrets" {
  source = "../../modules/secrets-manager"
  # → Terraform va lire modules/secrets-manager/
}
```

**Terraform charge TOUS les modules référencés:**

```
Chargement des modules:
  ✓ modules/secrets-manager/
      ├─ main.tf
      ├─ variables.tf
      └─ outputs.tf
  ✓ modules/dynamodb/
      ├─ main.tf
      ├─ variables.tf
      └─ outputs.tf
  ✓ modules/sqs/
  ✓ modules/vpc/
  ✓ modules/msk/
  ✓ modules/iam/
  ✓ modules/lambda/
  ✓ modules/eventbridge/
  ✓ modules/step-functions/
      ├─ main.tf
      ├─ variables.tf
      ├─ outputs.tf
      └─ state-machines/
          └─ client-name-update.json.tpl
  ✓ modules/api-gateway/
  ✓ modules/cloudwatch/
```

#### 7.5 - Terraform construit le graphe de dépendances

**Terraform analyse les dépendances:**

```
secrets-manager  ─┐
                  ├─→ iam ─┐
dynamodb ─────────┘        │
sqs ──────────────┐        │
                  ├────────┼─→ lambda ─┐
vpc ─┐            │        │           │
     ├─→ msk ─────┘        │           │
     └─────────────────────┘           │
                                       │
                                       ├─→ step-functions ─→ api-gateway
                                       │
                                       └─→ eventbridge
                                       │
                                       └─→ cloudwatch
```

**Ordre de création déterminé:**
1. secrets-manager (indépendant)
2. dynamodb (indépendant)
3. sqs (indépendant)
4. vpc (indépendant)
5. msk (dépend de vpc)
6. iam (dépend de secrets, dynamodb, sqs, msk)
7. lambda (dépend de iam)
8. eventbridge (dépend de lambda, iam)
9. step-functions (dépend de lambda, iam)
10. api-gateway (dépend de step-functions, iam)
11. cloudwatch (dépend de lambda, step-functions)

#### 7.6 - Terraform Plan affiche les changements

**Logs visibles:**
```
Terraform will perform the following actions:

  # module.secrets.aws_secretsmanager_secret.secrets["ibmmq"] will be created
  + resource "aws_secretsmanager_secret" "secrets" {
      + name = "dev/mcp/ibmmq"
      + arn  = (known after apply)
    }

  # module.dynamodb.aws_dynamodb_table.client_profile will be created
  + resource "aws_dynamodb_table" "client_profile" {
      + name         = "dev-mcp-ClientProfile"
      + billing_mode = "PAY_PER_REQUEST"
      + hash_key     = "clientId"
    }

  # module.lambda.aws_lambda_function.functions["client-profile-reader"] will be created
  + resource "aws_lambda_function" "functions" {
      + function_name = "dev-mcp-client-profile-reader"
      + handler       = "com.bnc.mcp.api.LambdaHandler::handleRequest"
      + runtime       = "java17"
      + memory_size   = 512
    }

  # ... 50+ autres ressources ...

Plan: 57 to add, 0 to change, 0 to destroy.
```

**Fichier créé:** `tfplan` (plan binaire)

---

### Si action = "apply"

```yaml
- name: Terraform Apply
  working-directory: environments/${{ inputs.environment }}
  run: terraform apply -auto-approve
```

**Terraform exécute le plan précédent et crée RÉELLEMENT les ressources AWS:**

#### 7.7 - Création séquentielle des ressources

**Ressource 1: Secrets Manager**

```
module.secrets.aws_secretsmanager_secret.secrets["ibmmq"]: Creating...
  ↓ Terraform appelle AWS API
  POST https://secretsmanager.ca-central-1.amazonaws.com/
  {
    "Name": "dev/mcp/ibmmq",
    "Description": "IBM MQ credentials for dev"
  }
  ↓ AWS répond
  {
    "ARN": "arn:aws:secretsmanager:ca-central-1:123456789:secret:dev/mcp/ibmmq-AbCdEf",
    "Name": "dev/mcp/ibmmq"
  }
  ✓ Created (2s)
```

**Ressource 2: Secrets Manager Version**

```
module.secrets.aws_secretsmanager_secret_version.secrets["ibmmq"]: Creating...
  ↓ Terraform appelle AWS API
  PUT https://secretsmanager.ca-central-1.amazonaws.com/
  {
    "SecretId": "arn:aws:secretsmanager:...:secret:dev/mcp/ibmmq-AbCdEf",
    "SecretString": "{\"host\":\"0.tcp.ngrok.io\",\"port\":\"12345\",...}"
  }
  ✓ Created (1s)
```

**Ressource 3: DynamoDB Table**

```
module.dynamodb.aws_dynamodb_table.client_profile: Creating...
  ↓ Terraform appelle AWS API
  POST https://dynamodb.ca-central-1.amazonaws.com/
  {
    "TableName": "dev-mcp-ClientProfile",
    "KeySchema": [{"AttributeName": "clientId", "KeyType": "HASH"}],
    "BillingMode": "PAY_PER_REQUEST"
  }
  ↓ AWS crée la table (peut prendre 30-60s)
  ✓ Created (45s)
```

**Ressource 4: SQS Queue**

```
module.sqs.aws_sqs_queue.queues["fcc_responses"]: Creating...
  ↓ API Call
  POST https://sqs.ca-central-1.amazonaws.com/
  {
    "QueueName": "dev-mcp-fcc_responses",
    "Attributes": {
      "VisibilityTimeout": "300",
      "MessageRetentionPeriod": "86400"
    }
  }
  ✓ Created (3s)
```

**Ressource 5: SQS DLQ**

```
module.sqs.aws_sqs_queue.dlq["fcc_responses"]: Creating...
  ✓ Created (3s)
```

**Ressource 6: VPC**

```
module.vpc.aws_vpc.main: Creating...
  ↓ API Call
  POST https://ec2.ca-central-1.amazonaws.com/
  {
    "CidrBlock": "10.0.0.0/16",
    "EnableDnsHostnames": true
  }
  ✓ Created (5s)
```

**Ressource 7-8: Subnets**

```
module.vpc.aws_subnet.private[0]: Creating...
module.vpc.aws_subnet.private[1]: Creating...
  ↓ Terraform crée EN PARALLÈLE (car indépendants)
  ✓ Created (7s)
  ✓ Created (7s)
```

**Ressource 9-10: Security Groups**

```
module.vpc.aws_security_group.msk: Creating...
module.vpc.aws_security_group.lambda: Creating...
  ✓ Created (4s)
  ✓ Created (4s)
```

**Ressource 11: MSK Cluster**

```
module.msk.aws_msk_serverless_cluster.main: Creating...
  ↓ Création MSK (TRÈS LONG: 10-15 minutes!)
  ⏳ Still creating... [1m0s elapsed]
  ⏳ Still creating... [2m0s elapsed]
  ⏳ Still creating... [3m0s elapsed]
  ...
  ⏳ Still creating... [14m0s elapsed]
  ✓ Created (14m23s)
```

**Ressource 12: IAM Role Lambda**

```
module.iam.aws_iam_role.lambda_execution: Creating...
  ✓ Created (2s)
```

**Ressource 13: IAM Policy Lambda**

```
module.iam.aws_iam_role_policy.lambda_execution: Creating...
  ✓ Created (1s)
```

**Ressources 14-20: Lambda Functions (EN PARALLÈLE)**

```
module.lambda.aws_lambda_function.functions["client-profile-reader"]: Creating...
module.lambda.aws_lambda_function.functions["name-validator"]: Creating...
module.lambda.aws_lambda_function.functions["mdmae-client"]: Creating...
module.lambda.aws_lambda_function.functions["fcc-sender"]: Creating...
module.lambda.aws_lambda_function.functions["human-review-handler"]: Creating...
module.lambda.aws_lambda_function.functions["mq-poller"]: Creating...
module.lambda.aws_lambda_function.functions["fcc-response-processor"]: Creating...

  ↓ Terraform upload les JARs vers AWS Lambda
  ⏳ Uploading function.jar (45 MB)... [30s]
  ⏳ Uploading function.jar (45 MB)... [30s]
  ⏳ Uploading function.jar (45 MB)... [30s]
  ...
  ✓ All created (1m15s)
```

**Ressource 21: CloudWatch Log Groups (7x)**

```
module.lambda.aws_cloudwatch_log_group.lambda_logs["client-profile-reader"]: Creating...
  ✓ Created (1s)
... (x7)
```

**Ressource 22: EventBridge Rule**

```
module.eventbridge.aws_cloudwatch_event_rule.rules["mq-poller"]: Creating...
  ✓ Created (2s)
```

**Ressource 23: EventBridge Target**

```
module.eventbridge.aws_cloudwatch_event_target.lambda_targets["mq-poller"]: Creating...
  ✓ Created (1s)
```

**Ressource 24: Step Functions State Machine**

```
module.step_functions.aws_sfn_state_machine.state_machines["client-name-update"]: Creating...
  ↓ Terraform lit le template
  templatefile("state-machines/client-name-update.json.tpl", {...})
  ↓ Remplace les variables
  "${client_profile_reader_arn}" → "arn:aws:lambda:ca-central-1:123:function:dev-mcp-client-profile-reader"
  ↓ Envoie la définition JSON à AWS
  ✓ Created (3s)
```

**Ressource 25: API Gateway REST API**

```
module.api_gateway.aws_api_gateway_rest_api.main: Creating...
  ✓ Created (2s)
```

**Ressources 26-30: API Gateway Resources**

```
module.api_gateway.aws_api_gateway_resource.api: Creating...
module.api_gateway.aws_api_gateway_resource.clients: Creating...
module.api_gateway.aws_api_gateway_resource.client_id: Creating...
module.api_gateway.aws_api_gateway_resource.nom: Creating...
  ✓ Created (1s each)
```

**Ressource 31: API Gateway Method**

```
module.api_gateway.aws_api_gateway_method.put_nom: Creating...
  ✓ Created (1s)
```

**Ressource 32: API Gateway Integration**

```
module.api_gateway.aws_api_gateway_integration.stepfunctions: Creating...
  ✓ Created (1s)
```

**Ressource 33: API Gateway Deployment**

```
module.api_gateway.aws_api_gateway_deployment.main: Creating...
  ✓ Created (2s)
```

**Ressource 34: API Gateway Stage**

```
module.api_gateway.aws_api_gateway_stage.main: Creating...
  ✓ Created (1s)
```

**Ressources 35-50+: CloudWatch Alarms (si enable_alarms=true)**

```
module.cloudwatch.aws_cloudwatch_metric_alarm.lambda_errors["client-profile-reader"]: Creating...
  ✓ Created (1s)
... (x20+)
```

---

#### 7.8 - Sauvegarde du state

**Après chaque ressource créée:**

```
Terraform met à jour le state en mémoire:
{
  "version": 4,
  "terraform_version": "1.9.0",
  "resources": [
    {
      "type": "aws_secretsmanager_secret",
      "name": "secrets",
      "instances": [{
        "attributes": {
          "arn": "arn:aws:secretsmanager:ca-central-1:123:secret:dev/mcp/ibmmq-AbCdEf",
          "name": "dev/mcp/ibmmq"
        }
      }]
    },
    ...
  ]
}
```

**À la fin du apply:**

```
Terraform upload le state vers S3:
  ↓ Upload vers s3://mcp-terraform-state-dev/infrastructure/terraform.tfstate
  ✓ State saved
  ↓ Release lock dans DynamoDB
  ✓ Lock released
```

**Logs visibles:**
```
Apply complete! Resources: 57 added, 0 changed, 0 destroyed.

Outputs:

api_gateway_url = "https://abc123.execute-api.ca-central-1.amazonaws.com/dev/api/clients/{clientId}/nom"
dynamodb_table_name = "dev-mcp-ClientProfile"
lambda_function_arns = {
  "client-profile-reader" = "arn:aws:lambda:ca-central-1:123:function:dev-mcp-client-profile-reader"
  ...
}
```

---

## Étape 8: Upload des Outputs (GitHub Actions)

```yaml
- name: Upload Terraform Outputs
  uses: actions/upload-artifact@v4
  with:
    name: terraform-outputs-${{ inputs.environment }}
    path: environments/${{ inputs.environment }}/terraform.tfstate
```

**Ce qui se passe:**
1. GitHub Actions lit le fichier `terraform.tfstate`
2. GitHub upload ce fichier comme "artifact"
3. Vous pouvez le télécharger depuis l'interface GitHub

**Interface GitHub:**
```
Workflow run #123
  ✓ Job completed
  📦 Artifacts
     └─ terraform-outputs-dev (5.2 MB)
```

---

## Étape 9: Cleanup (GitHub Actions)

**Ce qui se passe:**
1. GitHub supprime la VM (le runner)
2. Toutes les données locales sont effacées
3. Seul le state dans S3 persiste

---

## Timeline complète (exemple pour dev)

```
00:00 - Clic "Run workflow"
00:01 - VM créée, code cloné
00:02 - AWS credentials configurées
00:03 - Terraform installé
00:04 - Terraform init
        ├─ Connexion S3 (2s)
        ├─ Download state (1s)
        ├─ Acquire lock (1s)
        └─ Download providers (5s)
00:13 - Terraform plan/apply démarre
00:14 - Secrets Manager créé (2s)
00:16 - DynamoDB créé (45s)
01:01 - SQS créé (6s)
01:07 - VPC créé (5s)
01:12 - Subnets créés (7s)
01:19 - Security Groups créés (4s)
01:23 - MSK Cluster démarre (14 min!)
15:46 - MSK Cluster terminé
15:48 - IAM Roles créés (3s)
15:51 - Lambda Functions créées (1m15s)
17:06 - EventBridge créé (3s)
17:09 - Step Functions créé (3s)
17:12 - API Gateway créé (10s)
17:22 - CloudWatch créé (5s)
17:27 - State uploadé vers S3 (2s)
17:29 - ✅ TERMINÉ!
```

**Durée totale: ~17-20 minutes** (principalement à cause de MSK)

---

## Récapitulatif de l'ordre des fichiers

### Fichiers lus par GitHub Actions:
1. `.github/workflows/terraform-deploy.yml`

### Fichiers lus par Terraform (dans l'ordre):
1. `environments/dev/backend.tf` (pendant init)
2. `environments/dev/variables.tf`
3. Variables d'environnement (`TF_VAR_*`)
4. `environments/dev/main.tf`
5. Tous les modules référencés:
   - `modules/secrets-manager/{main,variables,outputs}.tf`
   - `modules/dynamodb/{main,variables,outputs}.tf`
   - `modules/sqs/{main,variables,outputs}.tf`
   - `modules/vpc/{main,variables,outputs}.tf`
   - `modules/msk/{main,variables,outputs}.tf`
   - `modules/iam/{main,variables,outputs}.tf`
   - `modules/lambda/{main,variables,outputs}.tf`
   - `modules/eventbridge/{main,variables,outputs}.tf`
   - `modules/step-functions/{main,variables,outputs}.tf`
     - `modules/step-functions/state-machines/client-name-update.json.tpl`
   - `modules/api-gateway/{main,variables,outputs}.tf`
   - `modules/cloudwatch/{main,variables,outputs}.tf`
6. `environments/dev/outputs.tf`

### Fichiers créés par Terraform:
1. `.terraform/` (providers téléchargés)
2. `.terraform.lock.hcl` (lock file)
3. `tfplan` (si action=plan)

### Fichiers sur AWS S3:
1. `s3://mcp-terraform-state-dev/infrastructure/terraform.tfstate`

### Fichiers sur AWS DynamoDB:
1. Lock dans table `mcp-terraform-lock-dev`

---

## Comment suivre en temps réel

Dans GitHub Actions, cliquez sur le job en cours d'exécution pour voir:

```
Run terraform apply
  ↓
module.secrets.aws_secretsmanager_secret.secrets["ibmmq"]: Creating...
module.secrets.aws_secretsmanager_secret.secrets["ibmmq"]: Creation complete after 2s
module.dynamodb.aws_dynamodb_table.client_profile: Creating...
module.dynamodb.aws_dynamodb_table.client_profile: Still creating... [10s elapsed]
module.dynamodb.aws_dynamodb_table.client_profile: Still creating... [20s elapsed]
module.dynamodb.aws_dynamodb_table.client_profile: Creation complete after 45s
...
```

Vous voyez **en temps réel** chaque ressource AWS se créer!

---

**Dernière mise à jour**: 2026-09-23
**Auteur**: Claude Code