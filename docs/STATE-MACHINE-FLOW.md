# 🔄 State Machine Step Functions - Flow Complet

Documentation détaillée du flux de création et d'exécution de la State Machine Step Functions pour le workflow de mise à jour de nom de client.

---

## 📋 Table des Matières

1. [Phase 1: Création des Ressources](#phase-1-création-des-ressources)
2. [Phase 2: Exécution du Workflow](#phase-2-exécution-du-workflow)
3. [Mapping des Ressources](#mapping-des-ressources)
4. [Traçabilité Complète](#traçabilité-complète)
5. [Dépendances des Fichiers Terraform](#dépendances-des-fichiers-terraform)

---

## 🎯 Vue d'Ensemble

Le workflow `client_name_update` est une State Machine AWS Step Functions qui orchestre la mise à jour du nom de famille d'un client à travers plusieurs étapes, chacune invoquant une fonction Lambda spécifique.

---

## Phase 1: Création des Ressources

### Flow de Création Terraform

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📦 PHASE 1: CRÉATION DES RESSOURCES (Terraform Apply)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

environments/dev/main.tf
    │
    ├─► (ligne 195-344) Définit module "lambda"
    │       │ functions = {
    │       │   client_profile_reader = {...}
    │       │   name_validator = {...}
    │       │   mdmae_client = {...}
    │       │   fcc_sender = {...}
    │       │   ...
    │       │ }
    │       ▼
    │   modules/lambda/main.tf
    │       │ Crée les Lambdas dans AWS
    │       │
    │       ▼
    │   ✅ Lambdas créées dans AWS
    │       ├─ dev-mcp-client_profile_reader
    │       │  ARN: arn:aws:lambda:ca-central-1:180111006463:function:dev-mcp-client_profile_reader
    │       │
    │       ├─ dev-mcp-name_validator
    │       │  ARN: arn:aws:lambda:ca-central-1:180111006463:function:dev-mcp-name_validator
    │       │
    │       ├─ dev-mcp-mdmae_client
    │       │  ARN: arn:aws:lambda:ca-central-1:180111006463:function:dev-mcp-mdmae_client
    │       │
    │       └─ dev-mcp-fcc_sender
    │          ARN: arn:aws:lambda:ca-central-1:180111006463:function:dev-mcp-fcc_sender
    │
    └─► (ligne 378-394) Définit module "step_functions"
            │ state_machines = {
            │   client_name_update = {
            │     template_vars = {
            │       client_profile_reader_arn = module.lambda.function_arns["client_profile_reader"]
            │       name_validator_arn        = module.lambda.function_arns["name_validator"]
            │       mdmae_client_arn          = module.lambda.function_arns["mdmae_client"]
            │       fcc_sender_arn            = module.lambda.function_arns["fcc_sender"]
            │       ↑
            │       └── Récupère les ARNs des Lambdas créées ci-dessus
            │     }
            │   }
            │ }
            │
            ▼
        modules/step-functions/main.tf (ligne 7-10)
            │ Appelle: templatefile()
            │ Avec: template_vars contenant les ARNs des Lambdas
            │
            ▼
        modules/step-functions/client-name-update.json.tpl
            │ Template avec ${placeholders}:
            │   "Resource": "${client_profile_reader_arn}"
            │   "Resource": "${name_validator_arn}"
            │   "Resource": "${mdmae_client_arn}"
            │   "Resource": "${fcc_sender_arn}"
            │
            ▼
        templatefile() remplace les ${...}
            │ ${client_profile_reader_arn} → arn:aws:lambda:...:function:dev-mcp-client_profile_reader
            │ ${name_validator_arn}        → arn:aws:lambda:...:function:dev-mcp-name_validator
            │ ${mdmae_client_arn}          → arn:aws:lambda:...:function:dev-mcp-mdmae_client
            │ ${fcc_sender_arn}            → arn:aws:lambda:...:function:dev-mcp-fcc_sender
            │
            ▼
        JSON final (définition complète)
            │ {
            │   "States": {
            │     "ReadClientProfile": {
            │       "Resource": "arn:aws:lambda:...:function:dev-mcp-client_profile_reader"
            │     },
            │     "ValidateName": {
            │       "Resource": "arn:aws:lambda:...:function:dev-mcp-name_validator"
            │     },
            │     "CheckMDMAE": {
            │       "Resource": "arn:aws:lambda:...:function:dev-mcp-mdmae_client"
            │     },
            │     "SendToFCC": {
            │       "Resource": "arn:aws:lambda:...:function:dev-mcp-fcc_sender"
            │     }
            │   }
            │ }
            │
            ▼
        aws_sfn_state_machine (ligne 1)
            │ Crée la State Machine dans AWS
            │ Avec la définition JSON contenant les ARNs des Lambdas
            │
            ▼
        ✅ State Machine AWS créée
            │ Nom: dev-mcp-client_name_update
            │ ARN: arn:aws:states:ca-central-1:180111006463:stateMachine:dev-mcp-client_name_update
            │ Définition: JSON avec les 4 ARNs Lambda configurés
```

### Construction du Nom de la State Machine

```
modules/step-functions/main.tf (ligne 4)
    name = "${var.environment}-${var.project_name}-${each.key}"
             │               │                    │
             │               │                    └─ "client_name_update" (main.tf ligne 379)
             │               └────────────────────── "mcp" (dev.tfvars ligne 6)
             └────────────────────────────────────── "dev" (dev.tfvars ligne 5)

Résultat: dev-mcp-client_name_update
```

### Construction du Role ARN

```
modules/step-functions/main.tf (ligne 5)
    role_arn = each.value.role_arn
                   │
                   └─ Vient de environments/dev/main.tf (ligne 381)
                          role_arn = module.iam.stepfunctions_execution_role_arn
                                         │
                                         └─ Vient de modules/iam/outputs.tf (ligne 13)
                                                value = aws_iam_role.stepfunctions_execution.arn
                                                            │
                                                            └─ Créé dans modules/iam/main.tf (ligne 124)

Résultat: arn:aws:iam::180111006463:role/dev-mcp-stepfunctions-role
```

### Construction de l'ARN de la State Machine

Format automatiquement généré par AWS:

```
arn:aws:states:{région}:{account_id}:stateMachine:{nom}
    │         │    │           │                        │
    │         │    │           │                        └─ Nom (dev-mcp-client_name_update)
    │         │    │           └────────────────────────── Account ID AWS
    │         │    └────────────────────────────────────── Région (ca-central-1)
    │         └─────────────────────────────────────────── Service (Step Functions)
    └───────────────────────────────────────────────────── Partition AWS

Résultat: arn:aws:states:ca-central-1:180111006463:stateMachine:dev-mcp-client_name_update
```

---

## Phase 2: Exécution du Workflow

### Flow d'Exécution Runtime

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚡ PHASE 2: EXÉCUTION DU WORKFLOW (Runtime)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

API Gateway reçoit requête
    │ PUT /api/clients/TEST123/nom
    │ Body: {"newLastName": "Leblanc", "reason": "MARIAGE"}
    │
    ▼
API Gateway → State Machine
    │ Invoke: arn:aws:states:...:stateMachine:dev-mcp-client_name_update
    │ Input: {"clientId": "TEST123", "newLastName": "Leblanc", "reason": "MARIAGE"}
    │
    ▼
╔═══════════════════════════════════════════════════════════════════╗
║ ÉTAPE 1: ReadClientProfile                                        ║
╚═══════════════════════════════════════════════════════════════════╝
State Machine lit la définition JSON
    │ "Resource": "arn:aws:lambda:...:function:dev-mcp-client_profile_reader"
    │
    ▼
State Machine → Lambda.Invoke()
    │ FunctionName: arn:aws:lambda:...:function:dev-mcp-client_profile_reader
    │ Payload: {"clientId": "TEST123", ...}
    │
    ▼
🔷 Lambda dev-mcp-client_profile_reader s'exécute
    │ Runtime: Java 21
    │ Handler: org.springframework.cloud.function.adapter.aws.FunctionInvoker::handleRequest
    │ Function: validationFunction
    │ Environment:
    │   - SPRING_PROFILES_ACTIVE: lambda
    │   - DYNAMODB_TABLE: dev-ClientProfile
    │ Action: DynamoDB.GetItem(dev-ClientProfile, TEST123)
    │
    ▼
Lambda → State Machine (retour)
    │ Output: {"clientId": "TEST123", "firstName": "Jean", "lastName": "Tremblay", ...}
    │ Status: ✅ SUCCESS
    │
    ▼
╔═══════════════════════════════════════════════════════════════════╗
║ ÉTAPE 2: ValidateName                                             ║
╚═══════════════════════════════════════════════════════════════════╝
State Machine lit la définition JSON
    │ "Resource": "arn:aws:lambda:...:function:dev-mcp-name_validator"
    │
    ▼
State Machine → Lambda.Invoke()
    │ FunctionName: arn:aws:lambda:...:function:dev-mcp-name_validator
    │ Payload: {sortie de l'étape précédente + nouveau nom}
    │
    ▼
🔷 Lambda dev-mcp-name_validator s'exécute
    │ Runtime: Java 21
    │ Handler: org.springframework.cloud.function.adapter.aws.FunctionInvoker::handleRequest
    │ Function: matchingFunction
    │ Environment:
    │   - SPRING_PROFILES_ACTIVE: lambda
    │   - MDMAE_API_ENDPOINT: https://mdmae-dev-test.example.com
    │   - DYNAMODB_TABLE: dev-ClientProfile
    │ Action: POST https://mdmae-dev-test.example.com/mdmae/api/v1/match
    │
    ▼
✅ Lambda réussit
    │ Response: {"validationStatus": "success", "duplicates": false}
    │ Status: ✅ SUCCESS
    │
    ▼
Lambda → State Machine (retour)
    │ Output: {résultat de la validation}
    │
    ▼

╔═══════════════════════════════════════════════════════════════════╗
║ ÉTAPE 3: CheckMDMAE                                               ║
╚═══════════════════════════════════════════════════════════════════╝
State Machine lit la définition JSON
    │ "Resource": "arn:aws:lambda:...:function:dev-mcp-mdmae_client"
    │
    ▼
State Machine → Lambda.Invoke()
    │ FunctionName: arn:aws:lambda:...:function:dev-mcp-mdmae_client
    │ Payload: {résultat de la validation}
    │
    ▼
🔷 Lambda dev-mcp-mdmae_client s'exécute
    │ Runtime: Java 21
    │ Handler: org.springframework.cloud.function.adapter.aws.FunctionInvoker::handleRequest
    │ Function: updateProfileFunction
    │ Environment:
    │   - SPRING_PROFILES_ACTIVE: lambda
    │   - MDMAE_API_ENDPOINT: https://mdmae-dev-test.example.com
    │   - DYNAMODB_TABLE: dev-ClientProfile
    │ Actions:
    │   1. Appelle MDMAE pour mettre à jour le profil
    │   2. Met à jour DynamoDB avec le nouveau nom
    │
    ▼
Lambda → State Machine (retour)
    │ Output: {"status": "updated", "clientId": "TEST123", ...}
    │
    ▼
╔═══════════════════════════════════════════════════════════════════╗
║ ÉTAPE 4: SendToFCC                                                ║
╚═══════════════════════════════════════════════════════════════════╝
State Machine lit la définition JSON
    │ "Resource": "arn:aws:lambda:...:function:dev-mcp-fcc_sender"
    │
    ▼
State Machine → Lambda.Invoke()
    │ FunctionName: arn:aws:lambda:...:function:dev-mcp-fcc_sender
    │ Payload: {résultat complet du workflow}
    │
    ▼
🔷 Lambda dev-mcp-fcc_sender s'exécute
    │ Runtime: Java 21
    │ Handler: org.springframework.cloud.function.adapter.aws.FunctionInvoker::handleRequest
    │ Function: publishEventFunction
    │ Environment:
    │   - SPRING_PROFILES_ACTIVE: lambda
    │   - IBM_MQ_SECRET_ARN: arn:aws:secretsmanager:...:secret:dev/mcp/ibmmq-...
    │   - DYNAMODB_TABLE: dev-ClientProfile
    │ Actions:
    │   1. Récupère les credentials IBM MQ depuis Secrets Manager
    │   2. Envoie le message à IBM MQ
    │   3. Publie un événement Kafka
    │
    ▼
Lambda → State Machine (retour)
    │ Output: {"status": "sent", "messageId": "...", ...}
    │
    ▼
✅ State Machine RÉUSSIE
    │ Execution Status: SUCCEEDED
    │ Output: {résultat final du workflow}
    │
    ▼
API Gateway → Client
    │ HTTP 200 OK
    │ Body: {
    │   "message": "Client name update initiated",
    │   "executionArn": "arn:aws:states:...:execution:dev-mcp-client_name_update:xxxxx"
    │ }
```

---

## Mapping des Ressources

### Template Placeholders → ARNs Réels

| Placeholder Template | ARN Réel | Lambda Function |
|---------------------|----------|-----------------|
| `${client_profile_reader_arn}` | `arn:aws:lambda:ca-central-1:180111006463:function:dev-mcp-client_profile_reader` | Lecture du profil client |
| `${name_validator_arn}` | `arn:aws:lambda:ca-central-1:180111006463:function:dev-mcp-name_validator` | Validation du nom via MDMAE |
| `${mdmae_client_arn}` | `arn:aws:lambda:ca-central-1:180111006463:function:dev-mcp-mdmae_client` | Mise à jour du profil |
| `${fcc_sender_arn}` | `arn:aws:lambda:ca-central-1:180111006463:function:dev-mcp-fcc_sender` | Envoi vers FCC |

### Étapes du Workflow → Lambdas

| Étape Step Functions | Lambda Invoquée | Action Principale | Status Actuel |
|---------------------|-----------------|-------------------|---------------|
| **ReadClientProfile** | `dev-mcp-client_profile_reader` | Lit le profil depuis DynamoDB | ✅ Fonctionne |
| **ValidateName** | `dev-mcp-name_validator` | Valide le nom via MDMAE | ✅ Fonctionne |
| **CheckMDMAE** | `dev-mcp-mdmae_client` | Met à jour le profil | ✅ Fonctionne |
| **SendToFCC** | `dev-mcp-fcc_sender` | Envoie à IBM MQ/Kafka | ✅ Fonctionne |

---

## Traçabilité Complète

### Dépendances entre Modules

```
module.lambda (créé en premier)
    │
    │ Produit: function_arns = {
    │   "client_profile_reader": "arn:aws:lambda:..."
    │   "name_validator": "arn:aws:lambda:..."
    │   "mdmae_client": "arn:aws:lambda:..."
    │   "fcc_sender": "arn:aws:lambda:..."
    │ }
    │
    ▼
module.step_functions.template_vars (utilise les ARNs)
    │
    │ Injecte les ARNs dans le template via templatefile()
    │
    ▼
State Machine (référence les Lambdas par leurs ARNs)
    │
    │ Au runtime, invoque chaque Lambda via son ARN
    │
    ▼
Lambdas s'exécutent et retournent les résultats à la State Machine
```

### Variables d'Environnement par Lambda

#### dev-mcp-client_profile_reader
```bash
SPRING_PROFILES_ACTIVE=lambda
SPRING_CLOUD_FUNCTION_DEFINITION=validationFunction
DYNAMODB_TABLE=dev-ClientProfile
LOG_LEVEL=INFO
```

#### dev-mcp-name_validator
```bash
SPRING_PROFILES_ACTIVE=lambda
SPRING_CLOUD_FUNCTION_DEFINITION=matchingFunction
MDMAE_API_ENDPOINT=https://mdmae-dev-test.example.com
DYNAMODB_TABLE=dev-ClientProfile
LOG_LEVEL=INFO
```

#### dev-mcp-mdmae_client
```bash
SPRING_PROFILES_ACTIVE=lambda
SPRING_CLOUD_FUNCTION_DEFINITION=updateProfileFunction
MDMAE_API_ENDPOINT=https://mdmae-dev-test.example.com
DYNAMODB_TABLE=dev-ClientProfile
LOG_LEVEL=INFO
```

#### dev-mcp-fcc_sender
```bash
SPRING_PROFILES_ACTIVE=lambda
SPRING_CLOUD_FUNCTION_DEFINITION=publishEventFunction
IBM_MQ_SECRET_ARN=arn:aws:secretsmanager:ca-central-1:180111006463:secret:dev/mcp/ibmmq-...
DYNAMODB_TABLE=dev-ClientProfile
LOG_LEVEL=INFO
```

---

## Fichiers Impliqués

### Configuration Terraform

| Fichier | Ligne | Rôle |
|---------|-------|------|
| `environments/dev/dev.tfvars` | 5-6 | Définit `environment` et `project_name` |
| `environments/dev/main.tf` | 195-344 | Définit les Lambdas |
| `environments/dev/main.tf` | 378-394 | Définit la State Machine avec template_vars |
| `modules/lambda/main.tf` | - | Crée les fonctions Lambda |
| `modules/step-functions/main.tf` | 1-24 | Crée la State Machine avec `templatefile()` |
| `modules/step-functions/client-name-update.json.tpl` | - | Template de définition du workflow |
| `modules/iam/main.tf` | 124 | Crée le role Step Functions |

### Commandes Utiles

```bash
# Voir les ARNs des Lambdas
terraform output -json lambda_function_arns

# Voir l'ARN de la State Machine
terraform output -json state_machine_arns

# Vérifier la définition de la State Machine
aws stepfunctions describe-state-machine \
  --state-machine-arn "arn:aws:states:ca-central-1:180111006463:stateMachine:dev-mcp-client_name_update"

# Voir les exécutions récentes
aws stepfunctions list-executions \
  --state-machine-arn "arn:aws:states:ca-central-1:180111006463:stateMachine:dev-mcp-client_name_update" \
  --max-results 10

# Voir les détails d'une exécution
aws stepfunctions describe-execution \
  --execution-arn "arn:aws:states:ca-central-1:180111006463:execution:dev-mcp-client_name_update:xxxxx"

# Voir les logs d'une Lambda
aws logs tail /aws/lambda/dev-mcp-name_validator --follow
```

---

## Dépendances des Fichiers Terraform

### Graphe Complet des Dépendances

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📁 DÉPENDANCES DES FICHIERS TERRAFORM
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1️⃣ FICHIERS DE CONFIGURATION (racine)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

environments/dev/dev.tfvars
    │ Contient: environment = "dev", project_name = "mcp"
    │
    └──► lu par ──► environments/dev/main.tf
                        │
                        │ Utilise: var.environment, var.project_name
                        │


2️⃣ MODULE IAM (créé en PREMIER)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

environments/dev/main.tf (ligne 167-189)
    │ Appelle: module "iam"
    │
    └──► modules/iam/main.tf
            │ Crée: aws_iam_role.stepfunctions_execution (ligne 124)
            │        aws_iam_role.lambda_execution
            │        etc.
            │
            └──► modules/iam/outputs.tf
                    │ Exporte: stepfunctions_execution_role_arn (ligne 13)
                    │          lambda_execution_role_arn
                    │
                    └──► UTILISÉ PAR ──► environments/dev/main.tf
                                             │
                                             ├─► module.iam.stepfunctions_execution_role_arn (ligne 381)
                                             └─► module.iam.lambda_execution_role_arn (ligne 201)


3️⃣ MODULE LAMBDA (créé en DEUXIÈME)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

environments/dev/main.tf (ligne 195-344)
    │ Appelle: module "lambda"
    │ Dépend de: module.iam.lambda_execution_role_arn (ligne 201)
    │             ↑
    │             └─── Vient de modules/iam/outputs.tf
    │
    └──► modules/lambda/main.tf
            │ Utilise: var.lambda_execution_role_arn (du module IAM)
            │ Crée: aws_lambda_function.functions["client_profile_reader"]
            │        aws_lambda_function.functions["name_validator"]
            │        aws_lambda_function.functions["mdmae_client"]
            │        aws_lambda_function.functions["fcc_sender"]
            │        etc.
            │
            └──► modules/lambda/outputs.tf
                    │ Exporte: function_arns = {
                    │            "client_profile_reader": "arn:aws:lambda:..."
                    │            "name_validator": "arn:aws:lambda:..."
                    │            "mdmae_client": "arn:aws:lambda:..."
                    │            "fcc_sender": "arn:aws:lambda:..."
                    │         }
                    │
                    └──► UTILISÉ PAR ──► environments/dev/main.tf (ligne 385-389)
                                             │
                                             └─► template_vars = {
                                                   client_profile_reader_arn = module.lambda.function_arns["client_profile_reader"]
                                                   name_validator_arn = module.lambda.function_arns["name_validator"]
                                                   mdmae_client_arn = module.lambda.function_arns["mdmae_client"]
                                                   fcc_sender_arn = module.lambda.function_arns["fcc_sender"]
                                                 }


4️⃣ MODULE STEP FUNCTIONS (créé en TROISIÈME)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

environments/dev/main.tf (ligne 372-395)
    │ Appelle: module "step_functions"
    │ Dépend de:
    │   ├─► module.iam.stepfunctions_execution_role_arn (ligne 381)
    │   │    ↑
    │   │    └─── Vient de modules/iam/outputs.tf
    │   │
    │   └─► module.lambda.function_arns (ligne 385-389)
    │        ↑
    │        └─── Vient de modules/lambda/outputs.tf
    │
    └──► modules/step-functions/main.tf
            │ Utilise: var.state_machines (passé par environments/dev/main.tf)
            │ Utilise: each.value.role_arn (ligne 5)
            │           ↑
            │           └─── = module.iam.stepfunctions_execution_role_arn (ligne 381)
            │
            ├──► modules/step-functions/variables.tf
            │       │ Définit: variable "state_machines"
            │
            └──► modules/step-functions/client-name-update.json.tpl
                    │ Template avec placeholders:
                    │   ${client_profile_reader_arn}
                    │   ${name_validator_arn}
                    │   ${mdmae_client_arn}
                    │   ${fcc_sender_arn}
                    │    ↑
                    │    └─── Remplacés par templatefile() (ligne 7-10 de main.tf)
                    │         avec les valeurs de module.lambda.function_arns
                    │
                    └──► Produit: JSON final avec ARNs réels
                            │
                            └──► Utilisé par: aws_sfn_state_machine (ligne 1)
                                    │
                                    └──► Crée la State Machine dans AWS


5️⃣ OUTPUTS (exposés à l'utilisateur)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

modules/step-functions/main.tf (ligne 1)
    │ Crée: aws_sfn_state_machine.state_machines
    │
    └──► modules/step-functions/outputs.tf
            │ Exporte: state_machine_arns = {
            │            "client_name_update": "arn:aws:states:..."
            │         }
            │
            └──► environments/dev/outputs.tf (ligne 36-39)
                    │ Exporte: output "state_machine_arns"
                    │          value = module.step_functions.state_machine_arns
                    │
                    └──► Visible via: terraform output state_machine_arns
```

### Tableau Récapitulatif des Dépendances

| Fichier Dépendant | Dépend de | Via quelle variable | Ligne |
|-------------------|-----------|---------------------|-------|
| **modules/iam/main.tf** | environments/dev/main.tf | var.environment, var.project_name | - |
| **modules/iam/outputs.tf** | modules/iam/main.tf | aws_iam_role.stepfunctions_execution.arn | 13 |
| **modules/lambda/main.tf** | modules/iam/outputs.tf | var.lambda_execution_role_arn | - |
| **modules/lambda/outputs.tf** | modules/lambda/main.tf | aws_lambda_function.functions | - |
| **environments/dev/main.tf** (Step Functions) | modules/iam/outputs.tf | stepfunctions_execution_role_arn | 381 |
| **environments/dev/main.tf** (Step Functions) | modules/lambda/outputs.tf | function_arns | 385-389 |
| **modules/step-functions/main.tf** | environments/dev/main.tf | each.value.role_arn, each.value.template_vars | 5, 9 |
| **modules/step-functions/main.tf** | client-name-update.json.tpl | Lit le template | 8 |
| **modules/step-functions/outputs.tf** | modules/step-functions/main.tf | aws_sfn_state_machine.state_machines | - |
| **environments/dev/outputs.tf** | modules/step-functions/outputs.tf | state_machine_arns | 38 |

### Ordre de Création (Terraform Graph)

```
1. environments/dev/dev.tfvars
        ↓
2. module.iam
        ├─► Crée les roles
        └─► Produit: stepfunctions_execution_role_arn, lambda_execution_role_arn
                ↓
3. module.lambda (dépend de module.iam)
        ├─► Utilise: lambda_execution_role_arn
        ├─► Crée les fonctions Lambda
        └─► Produit: function_arns
                ↓
4. module.step_functions (dépend de module.iam ET module.lambda)
        ├─► Utilise: stepfunctions_execution_role_arn (de module.iam)
        ├─► Utilise: function_arns (de module.lambda)
        ├─► Lit: client-name-update.json.tpl
        ├─► Remplace les placeholders avec templatefile()
        └─► Crée: State Machine
                ↓
5. outputs.tf
        └─► Expose les ARNs créés
```

---

**Dernière mise à jour**: 2026-10-06
**Version**: 1.1.0
**Status**: ✅ Toutes les étapes fonctionnelles (MDMAE opérationnel)