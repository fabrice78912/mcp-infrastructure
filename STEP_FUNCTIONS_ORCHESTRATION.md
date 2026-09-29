# Step Functions : L'orchestrateur des workflows BNC MCP

## 📌 Table des matières

1. [Introduction : Qu'est-ce qu'un workflow Step Functions ?](#introduction--quest-ce-quun-workflow-step-functions)
2. [POURQUOI Step Functions est dans mcp-infrastructure](#pourquoi-step-functions-est-dans-mcp-infrastructure)
3. [COMMENT fonctionne un workflow Step Functions](#comment-fonctionne-un-workflow-step-functions)
4. [L'importance de Step Functions dans un workflow](#limportance-de-step-functions-dans-un-workflow)
5. [Exemple concret : Workflow "Client Address Update"](#exemple-concret--workflow-client-address-update)
6. [Séparation Infrastructure vs Code Métier](#séparation-infrastructure-vs-code-métier)
7. [Cycle de vie d'un workflow](#cycle-de-vie-dun-workflow)
8. [Avantages pour BNC (Banking Context)](#avantages-pour-bnc-banking-context)
9. [Patterns et bonnes pratiques](#patterns-et-bonnes-pratiques)
10. [Comparaison : Avec vs Sans Step Functions](#comparaison--avec-vs-sans-step-functions)

---

## Introduction : Qu'est-ce qu'un workflow Step Functions ?

### Définition

**AWS Step Functions** est un service d'orchestration serverless qui coordonne l'exécution de plusieurs services AWS (Lambdas, DynamoDB, SQS, etc.) selon un **workflow défini**.

Le workflow est écrit dans un langage JSON appelé **Amazon States Language (ASL)**.

### Analogie simple

Imaginez un **chef d'orchestre** lors d'un concert :

```
Step Functions = Chef d'orchestre
Lambdas        = Musiciens (violon, piano, batterie...)
Workflow JSON  = Partition musicale
```

Le chef d'orchestre (Step Functions) :
- ✅ Lit la partition (workflow JSON)
- ✅ Indique quand chaque musicien doit jouer (invoke Lambda)
- ✅ Coordonne l'ordre des morceaux (séquence d'étapes)
- ✅ Gère les répétitions si un musicien se trompe (retry)
- ✅ Décide quoi faire en cas d'erreur (error handling)

---

## POURQUOI Step Functions est dans mcp-infrastructure

### 🎯 Raison 1 : Séparation des responsabilités

```
┌─────────────────────────────────────────────────────────────┐
│ mcp-infrastructure (Terraform)                              │
│ Responsabilité : ORCHESTRATION                              │
├─────────────────────────────────────────────────────────────┤
│ • QUOI exécuter : Quelles Lambdas appeler                   │
│ • QUAND exécuter : Ordre des étapes                         │
│ • COMMENT gérer les erreurs : Retry, catch, timeout         │
│ • CONDITIONS : If/else, choix de branches                   │
│                                                             │
│ Fichier : step_functions/state_machines/workflow.json      │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ mcp-local (Code Java)                                       │
│ Responsabilité : LOGIQUE MÉTIER                             │
├─────────────────────────────────────────────────────────────┤
│ • COMMENT valider : Règles de validation                    │
│ • COMMENT transformer : Mapping de données                  │
│ • COMMENT appeler APIs : Intégrations externes             │
│ • ALGORITHMES : Calculs, détection fraude, etc.            │
│                                                             │
│ Fichiers : handlers/*.java, services/*.java                │
└─────────────────────────────────────────────────────────────┘
```

**Pourquoi cette séparation ?**

| Aspect | Infrastructure (Terraform) | Code Métier (Java) |
|--------|---------------------------|-------------------|
| **Fréquence de changement** | ⏱️ Rare (1-2 fois/an) | 🔄 Fréquent (1-2 fois/semaine) |
| **Qui modifie** | 👷 Équipe Infrastructure/DevOps | 👨‍💻 Développeurs Backend |
| **Impact du changement** | 🔴 Critique (affect all workflows) | 🟡 Modéré (affect one function) |
| **Validation** | ✅ Audit bancaire, compliance | ✅ Tests unitaires, code review |
| **Déploiement** | 📦 Terraform apply | 🚀 CI/CD (JAR upload) |

**Exemple concret :**

Si vous voulez **changer l'algorithme de détection de fraude** (logique métier) :
- ✅ Modifiez `CheckAddressHistoryLambda.java`
- ✅ Déployez le nouveau JAR
- ❌ **PAS BESOIN** de toucher au workflow Step Functions

Si vous voulez **ajouter une étape de notification email** (orchestration) :
- ✅ Modifiez le workflow JSON Step Functions
- ✅ Terraform apply
- ❌ **PAS BESOIN** de modifier les Lambdas existantes

---

### 🎯 Raison 2 : Déclaratif vs Impératif

**Step Functions (Déclaratif)** : Vous dites **CE QUE** vous voulez, pas **COMMENT** le faire.

```json
{
  "StartAt": "ValidateAddress",
  "States": {
    "ValidateAddress": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:...:validate-address",
      "Next": "CheckHistory",
      "Retry": [
        {
          "ErrorEquals": ["States.TaskFailed"],
          "MaxAttempts": 3
        }
      ]
    }
  }
}
```

**Signification** : "Exécute ValidateAddress, si ça échoue, réessaie 3 fois, puis passe à CheckHistory"

**Alternative sans Step Functions (Impératif dans le code)** :

```java
// ❌ Anti-pattern : Orchestration dans le code
public void processAddressUpdate() {
    int retries = 0;
    while (retries < 3) {
        try {
            validateAddress();
            break;
        } catch (Exception e) {
            retries++;
            if (retries == 3) throw e;
            Thread.sleep(2000);
        }
    }

    checkHistory();
    // ... etc
}
```

**Problèmes de l'approche impérative :**
- ❌ Code verbeux et complexe
- ❌ Difficile à visualiser
- ❌ Gestion manuelle des erreurs
- ❌ Pas de traçabilité visuelle
- ❌ Timeout Lambda (max 15 min)

---

### 🎯 Raison 3 : Infrastructure as Code (IaC)

Le workflow Step Functions est **déployé comme infrastructure** via Terraform car :

**1. Versionnement Git**
```bash
git log -- modules/step_functions/state_machines/client-address-update.json
# Historique complet de tous les changements du workflow
```

**2. Review Process**
```
Developer → Modifie workflow.json → PR → Code Review → Terraform apply
```

**3. Environnements multiples**
```
dev/   → workflow avec logs verbose, timeouts courts
prod/  → workflow optimisé, monitoring avancé
```

**4. Rollback facile**
```bash
# Revenir à la version précédente du workflow
git checkout previous-commit
terraform apply
```

---

### 🎯 Raison 4 : Conformité bancaire BNC

Pour la **Banque Nationale du Canada**, les workflows doivent :

| Exigence bancaire | Comment Step Functions répond |
|-------------------|-------------------------------|
| **Audit trail** | ✅ Historique complet de chaque exécution (CloudWatch) |
| **Traçabilité** | ✅ Graphe visuel de l'exécution dans AWS Console |
| **Compliance** | ✅ Workflow validé une fois, ne change pas sans approbation |
| **Separation of Duties** | ✅ DevOps gère orchestration, Devs gèrent logique métier |
| **Repeatability** | ✅ Même workflow, mêmes résultats (déterministe) |
| **Monitoring** | ✅ Métriques CloudWatch automatiques |

**Exemple d'audit bancaire :**

```
Auditeur : "Montrez-moi toutes les exécutions du workflow d'update d'adresse en septembre 2026"
DevOps   : *Ouvre AWS Console Step Functions*
           → Filtre par date : Sept 2026
           → Export JSON de toutes les exécutions
           → Graphe visuel pour chaque exécution
```

Avec du code Java, l'auditeur devrait :
- ❌ Analyser des logs CloudWatch non structurés
- ❌ Reconstruire le flow manuellement
- ❌ Pas de graphe visuel

---

## COMMENT fonctionne un workflow Step Functions

### Structure d'un workflow Step Functions

Un workflow Step Functions est un **fichier JSON** qui définit une **state machine** (machine à états).

#### Anatomie d'un workflow

```json
{
  "Comment": "Description du workflow",
  "StartAt": "NomDuPremierÉtat",
  "States": {
    "NomDuPremierÉtat": {
      "Type": "Task",
      "Resource": "ARN de la Lambda à invoquer",
      "Next": "NomDuDeuxièmeÉtat"
    },
    "NomDuDeuxièmeÉtat": {
      "Type": "Choice",
      "Choices": [...],
      "Default": "..."
    }
  }
}
```

---

### Types d'états (States)

#### 1. **Task** - Exécuter une action

Invoque une Lambda, appelle une API, écrit dans DynamoDB, etc.

```json
{
  "ValidateAddress": {
    "Type": "Task",
    "Resource": "arn:aws:lambda:ca-central-1:123:function:dev-validate-address",
    "Comment": "Valide le format de l'adresse",
    "TimeoutSeconds": 30,
    "ResultPath": "$.validationResult",
    "Next": "CheckValidation"
  }
}
```

**Paramètres importants :**
- `Resource` : ARN de la Lambda à invoquer
- `TimeoutSeconds` : Timeout max (Lambda peut prendre max 15 min)
- `ResultPath` : Où stocker le résultat dans l'input JSON
- `Next` : Prochain état

---

#### 2. **Choice** - Condition if/else

Décide de la prochaine étape selon une condition.

```json
{
  "CheckValidation": {
    "Type": "Choice",
    "Comment": "Vérifie si la validation a réussi",
    "Choices": [
      {
        "Variable": "$.validationResult.isValid",
        "BooleanEquals": true,
        "Next": "UpdateDatabase"
      },
      {
        "Variable": "$.validationResult.isValid",
        "BooleanEquals": false,
        "Next": "SendErrorNotification"
      }
    ],
    "Default": "HandleUnexpectedError"
  }
}
```

**Opérateurs disponibles :**
- `BooleanEquals`, `NumericEquals`, `StringEquals`
- `NumericGreaterThan`, `NumericLessThan`
- `StringMatches` (regex)
- `And`, `Or`, `Not`

**Exemple concret :**

```json
{
  "Choices": [
    {
      "Variable": "$.amount",
      "NumericGreaterThan": 10000,
      "Next": "RequireManagerApproval"
    },
    {
      "And": [
        {
          "Variable": "$.country",
          "StringEquals": "CA"
        },
        {
          "Variable": "$.province",
          "StringEquals": "QC"
        }
      ],
      "Next": "ApplyQuebecTax"
    }
  ],
  "Default": "StandardProcessing"
}
```

---

#### 3. **Parallel** - Exécution parallèle

Exécute plusieurs branches en même temps.

```json
{
  "ProcessInParallel": {
    "Type": "Parallel",
    "Comment": "Exécute validation et vérification historique en parallèle",
    "Branches": [
      {
        "StartAt": "ValidateAddress",
        "States": {
          "ValidateAddress": {
            "Type": "Task",
            "Resource": "arn:aws:lambda:...:validate-address",
            "End": true
          }
        }
      },
      {
        "StartAt": "CheckHistory",
        "States": {
          "CheckHistory": {
            "Type": "Task",
            "Resource": "arn:aws:lambda:...:check-history",
            "End": true
          }
        }
      }
    ],
    "Next": "MergeResults"
  }
}
```

**Avantages :**
- ✅ Réduit la latence totale (2 tâches de 10s → 10s au lieu de 20s)
- ✅ Optimise les coûts (moins de temps d'exécution)

---

#### 4. **Wait** - Attendre

Pause l'exécution pendant un certain temps.

```json
{
  "WaitBeforeRetry": {
    "Type": "Wait",
    "Seconds": 60,
    "Next": "RetryOperation"
  }
}
```

Ou attendre jusqu'à une date précise :

```json
{
  "WaitUntilMidnight": {
    "Type": "Wait",
    "Timestamp": "2026-09-25T00:00:00Z",
    "Next": "DailyBatchProcess"
  }
}
```

**Cas d'usage :** Polling, batch processing, rate limiting

---

#### 5. **Succeed / Fail** - Terminaison

```json
{
  "WorkflowSuccessful": {
    "Type": "Succeed",
    "Comment": "Workflow terminé avec succès"
  },

  "WorkflowFailed": {
    "Type": "Fail",
    "Error": "ValidationError",
    "Cause": "Address validation failed"
  }
}
```

---

### Gestion d'erreurs et Retry

#### Retry (réessayer automatiquement)

```json
{
  "CallExternalAPI": {
    "Type": "Task",
    "Resource": "arn:aws:lambda:...:call-mdmae-api",
    "Retry": [
      {
        "ErrorEquals": ["States.TaskFailed", "TimeoutError"],
        "IntervalSeconds": 2,
        "MaxAttempts": 3,
        "BackoffRate": 2.0
      }
    ],
    "Next": "ProcessResponse"
  }
}
```

**Paramètres :**
- `ErrorEquals` : Types d'erreurs à réessayer
- `IntervalSeconds` : Délai initial (2s)
- `MaxAttempts` : Nombre max de tentatives (3)
- `BackoffRate` : Multiplicateur du délai (2x → 2s, 4s, 8s)

**Stratégie de retry :**
```
Tentative 1 : Échoue → Attendre 2s
Tentative 2 : Échoue → Attendre 4s (2s × 2)
Tentative 3 : Échoue → Attendre 8s (4s × 2)
Tentative 4 : Abandon → Passe à Catch ou échoue
```

---

#### Catch (gérer les erreurs)

```json
{
  "UpdateDatabase": {
    "Type": "Task",
    "Resource": "arn:aws:lambda:...:update-db",
    "Catch": [
      {
        "ErrorEquals": ["DynamoDBException"],
        "ResultPath": "$.error",
        "Next": "HandleDatabaseError"
      },
      {
        "ErrorEquals": ["States.ALL"],
        "ResultPath": "$.error",
        "Next": "HandleGenericError"
      }
    ],
    "Next": "Success"
  }
}
```

**Hiérarchie d'erreurs :**
1. Erreurs spécifiques (`DynamoDBException`, `ValidationError`)
2. Erreurs génériques (`States.TaskFailed`)
3. Toutes erreurs (`States.ALL`)

---

### Passage de données entre états

Step Functions passe les données via un **JSON d'input/output** entre les états.

#### Exemple de flux de données

**Input initial :**
```json
{
  "clientId": "12345",
  "address": {
    "street": "123 Main St",
    "city": "Montreal"
  }
}
```

**Après ValidateAddress (ResultPath: "$.validationResult") :**
```json
{
  "clientId": "12345",
  "address": {
    "street": "123 Main St",
    "city": "Montreal"
  },
  "validationResult": {
    "isValid": true,
    "normalizedAddress": {
      "street": "123 MAIN ST",
      "city": "MONTREAL"
    }
  }
}
```

**Après CheckHistory (ResultPath: "$.historyCheck") :**
```json
{
  "clientId": "12345",
  "address": {...},
  "validationResult": {...},
  "historyCheck": {
    "suspiciousScore": 0.2,
    "previousAddresses": [...]
  }
}
```

---

### Variables spéciales

Step Functions fournit des variables contextuelles :

```json
{
  "LogExecution": {
    "Type": "Task",
    "Resource": "arn:aws:lambda:...:logger",
    "Parameters": {
      "executionId.$": "$$.Execution.Id",
      "executionName.$": "$$.Execution.Name",
      "stateName.$": "$$.State.Name",
      "enteredTime.$": "$$.State.EnteredTime",
      "inputData.$": "$"
    }
  }
}
```

**Variables disponibles :**
- `$$.Execution.Id` : ID unique de l'exécution
- `$$.Execution.StartTime` : Date de début
- `$$.State.Name` : Nom de l'état actuel
- `$` : Input complet

---

## L'importance de Step Functions dans un workflow

### 🎯 1. Visibilité et observabilité

**Sans Step Functions (Code Java) :**

```
Client → Lambda Controller → ???? (boîte noire)
```

Pour savoir ce qui se passe :
- ❌ Lire les logs CloudWatch (non structurés)
- ❌ Reconstruire le flow manuellement
- ❌ Difficile de débugger

**Avec Step Functions :**

```
Client → Lambda Controller → Step Functions
                              ↓
                    [Graphe visuel temps réel]
                              ↓
                    ValidateAddress ✅
                              ↓
                    CheckHistory ✅
                              ↓
                    UpdateDatabase ⏳ (en cours)
```

**AWS Console Step Functions affiche :**
- ✅ Graphe visuel du workflow
- ✅ État actuel de chaque étape
- ✅ Temps d'exécution de chaque Lambda
- ✅ Input/Output de chaque état
- ✅ Erreurs avec stack trace

**Exemple de graphe visuel :**

```
┌─────────────────────┐
│ ValidateAddress     │ ✅ Success (2.3s)
└──────────┬──────────┘
           ↓
┌─────────────────────┐
│ CheckHistory        │ ✅ Success (1.8s)
└──────────┬──────────┘
           ↓
      ┌────┴────┐
      │ Choice  │
      └────┬────┘
           ↓
  suspiciousScore > 0.8 ?
           │
    ┌──────┴──────┐
    │             │
    NO            YES
    │             │
    ↓             ↓
UpdateDB   ManualReview
  ✅ (3.1s)    ⏳ (waiting)
```

---

### 🎯 2. Gestion automatique des erreurs

**Problème sans Step Functions :**

```java
// ❌ Gestion manuelle complexe
public void updateAddress() {
    try {
        validateAddress();
    } catch (ValidationException e) {
        sendErrorNotification(e);
        return;
    }

    try {
        updateDatabase();
    } catch (DatabaseException e) {
        rollback();
        sendErrorNotification(e);
        return;
    }

    // ... 10+ try/catch blocks
}
```

**Avec Step Functions :**

```json
{
  "ValidateAddress": {
    "Type": "Task",
    "Resource": "...",
    "Catch": [
      {
        "ErrorEquals": ["ValidationException"],
        "Next": "SendErrorNotification"
      }
    ]
  }
}
```

**Avantages :**
- ✅ Déclaratif et clair
- ✅ Retry automatique
- ✅ Pas de code boilerplate
- ✅ Testable visuellement

---

### 🎯 3. Workflows de longue durée

**Limitation Lambda :** Maximum **15 minutes** d'exécution

**Problème :** Workflow qui prend 2 heures (ex: traitement batch, approbation humaine)

**Sans Step Functions :**
```
❌ Impossible avec une seule Lambda
❌ Besoin de SQS + polling + gestion d'état custom
❌ Complexité élevée
```

**Avec Step Functions :**

```json
{
  "WaitForApproval": {
    "Type": "Task",
    "Resource": "arn:aws:states:::sqs:sendMessage.waitForTaskToken",
    "Parameters": {
      "QueueUrl": "https://sqs.ca-central-1.amazonaws.com/...",
      "MessageBody": {
        "taskToken.$": "$$.Task.Token",
        "clientId.$": "$.clientId"
      }
    },
    "TimeoutSeconds": 86400,
    "Next": "ProcessApproval"
  }
}
```

**Signification :**
- Envoie un message SQS avec un **task token**
- Attend jusqu'à **24 heures** (86400s)
- Un humain approuve via un système externe
- Le système externe appelle `SendTaskSuccess` avec le token
- Le workflow reprend

**Cas d'usage BNC :**
- Approbation de transactions > 10,000$
- Revue manuelle de changements suspects
- Traitement batch nocturne

---

### 🎯 4. Scalabilité automatique

**Step Functions gère automatiquement :**
- ✅ Millions d'exécutions concurrentes
- ✅ Pas de serveur à gérer
- ✅ Pas de limite de quota (avec quotas augmentés)

**Exemple :**

```
Scenario : Traitement de 1 million d'adresses à mettre à jour

Avec Step Functions :
→ 1 million d'exécutions parallèles du workflow
→ Chaque exécution indépendante
→ Auto-scaling des Lambdas

Sans Step Functions :
→ Besoin de SQS + worker Lambdas + gestion de concurrence
→ Complexité élevée
```

---

### 🎯 5. Intégrations natives AWS

Step Functions s'intègre directement avec **200+ services AWS** sans Lambda intermédiaire.

**Exemples d'intégrations directes :**

#### DynamoDB PutItem (sans Lambda)

```json
{
  "SaveToDatabase": {
    "Type": "Task",
    "Resource": "arn:aws:states:::dynamodb:putItem",
    "Parameters": {
      "TableName": "dev-mcp-AddressHistory",
      "Item": {
        "PK": {"S.$": "$.clientId"},
        "SK": {"S.$": "$$.Execution.StartTime"},
        "address": {"S.$": "$.address.street"}
      }
    },
    "Next": "Success"
  }
}
```

**Avantages :**
- ✅ Pas de Lambda intermédiaire (économie de coût)
- ✅ Moins de latence
- ✅ Moins de code à maintenir

#### SQS SendMessage (sans Lambda)

```json
{
  "SendToQueue": {
    "Type": "Task",
    "Resource": "arn:aws:states:::sqs:sendMessage",
    "Parameters": {
      "QueueUrl": "https://sqs.ca-central-1.amazonaws.com/...",
      "MessageBody.$": "$"
    },
    "Next": "Success"
  }
}
```

#### SNS Publish (sans Lambda)

```json
{
  "SendNotification": {
    "Type": "Task",
    "Resource": "arn:aws:states:::sns:publish",
    "Parameters": {
      "TopicArn": "arn:aws:sns:ca-central-1:123:address-updates",
      "Message.$": "$.notificationMessage"
    },
    "Next": "Success"
  }
}
```

**Services supportés nativement :**
- DynamoDB (GetItem, PutItem, UpdateItem, Query, Scan)
- SQS (SendMessage, ReceiveMessage)
- SNS (Publish)
- EventBridge (PutEvents)
- ECS (RunTask)
- Batch (SubmitJob)
- Glue (StartJobRun)
- SageMaker (CreateTrainingJob)
- Lambda (bien sûr)

---

## Exemple concret : Workflow "Client Address Update"

### Vue d'ensemble du workflow

```
Objectif : Mettre à jour l'adresse d'un client avec validation, vérification fraude, et notification

Étapes :
1. Lire le profil client actuel (DynamoDB)
2. Valider la nouvelle adresse (Lambda)
3. Vérifier l'historique pour détecter la fraude (Lambda)
4. Si suspicieux → Approbation manuelle
5. Sinon → Mettre à jour MDMAE (Lambda)
6. Envoyer notification FCC (Lambda)
7. Sauvegarder dans l'historique (DynamoDB direct)
8. Publier événement (MSK Kafka)
```

---

### Workflow Step Functions complet

**Fichier :** `modules/step_functions/state_machines/client-address-update.json`

```json
{
  "Comment": "Workflow de mise à jour d'adresse client - Banque Nationale",
  "StartAt": "ReadClientProfile",
  "States": {

    "ReadClientProfile": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:ca-central-1:123456789:function:${env}-client-profile-reader",
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
      "Next": "ValidateAddress"
    },

    "ValidateAddress": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:ca-central-1:123456789:function:${env}-address-validator",
      "Comment": "Valide le format et la cohérence de la nouvelle adresse",
      "TimeoutSeconds": 10,
      "ResultPath": "$.validationResult",
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
          "ErrorEquals": ["ValidationException"],
          "ResultPath": "$.error",
          "Next": "ValidationFailedNotification"
        }
      ],
      "Next": "CheckValidation"
    },

    "CheckValidation": {
      "Type": "Choice",
      "Comment": "Vérifie si la validation a réussi",
      "Choices": [
        {
          "Variable": "$.validationResult.isValid",
          "BooleanEquals": true,
          "Next": "CheckAddressHistory"
        }
      ],
      "Default": "ValidationFailedNotification"
    },

    "CheckAddressHistory": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:ca-central-1:123456789:function:${env}-check-address-history",
      "Comment": "Vérifie l'historique pour détecter les changements suspects",
      "TimeoutSeconds": 15,
      "ResultPath": "$.historyCheck",
      "Next": "EvaluateSuspiciousScore"
    },

    "EvaluateSuspiciousScore": {
      "Type": "Choice",
      "Comment": "Décide si le changement nécessite approbation manuelle",
      "Choices": [
        {
          "Variable": "$.historyCheck.suspiciousScore",
          "NumericGreaterThan": 0.8,
          "Comment": "Score > 0.8 = très suspect",
          "Next": "RequireManualApproval"
        },
        {
          "And": [
            {
              "Variable": "$.historyCheck.suspiciousScore",
              "NumericGreaterThan": 0.5
            },
            {
              "Variable": "$.historyCheck.changeCount",
              "NumericGreaterThan": 3
            }
          ],
          "Comment": "Score > 0.5 ET plus de 3 changements récents",
          "Next": "RequireManualApproval"
        }
      ],
      "Default": "UpdateMDMAE"
    },

    "RequireManualApproval": {
      "Type": "Task",
      "Resource": "arn:aws:states:::sqs:sendMessage.waitForTaskToken",
      "Comment": "Envoie notification à l'équipe fraude avec task token",
      "Parameters": {
        "QueueUrl": "${fraud_review_queue_url}",
        "MessageBody": {
          "taskToken.$": "$$.Task.Token",
          "clientId.$": "$.clientId",
          "currentAddress.$": "$.currentProfile.address",
          "newAddress.$": "$.address",
          "suspiciousScore.$": "$.historyCheck.suspiciousScore",
          "reason.$": "$.historyCheck.reason",
          "executionId.$": "$$.Execution.Id",
          "requestId.$": "$.requestId"
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
          "Next": "UpdateMDMAE"
        },
        {
          "Variable": "$.approvalResult.decision",
          "StringEquals": "REJECTED",
          "Next": "ApprovalRejectedNotification"
        }
      ],
      "Default": "HandleGenericError"
    },

    "UpdateMDMAE": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:ca-central-1:123456789:function:${env}-address-mdmae-client",
      "Comment": "Met à jour l'adresse dans MDMAE (Master Data Management)",
      "TimeoutSeconds": 30,
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
      "Next": "SendFCCNotification"
    },

    "SendFCCNotification": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:ca-central-1:123456789:function:${env}-fcc-sender",
      "Comment": "Envoie notification FCC via IBM MQ",
      "TimeoutSeconds": 20,
      "ResultPath": "$.fccResult",
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
          "ResultPath": "$.error",
          "Next": "LogFCCError"
        }
      ],
      "Next": "SaveAddressHistory"
    },

    "SaveAddressHistory": {
      "Type": "Task",
      "Resource": "arn:aws:states:::dynamodb:putItem",
      "Comment": "Sauvegarde dans l'historique (intégration native DynamoDB)",
      "Parameters": {
        "TableName": "${dynamodb_table_name}",
        "Item": {
          "PK": {
            "S.$": "$.clientId"
          },
          "SK": {
            "S.$": "$$.Execution.StartTime"
          },
          "addressType": {
            "S": "RESIDENTIAL"
          },
          "street": {
            "S.$": "$.validationResult.normalizedAddress.street"
          },
          "city": {
            "S.$": "$.validationResult.normalizedAddress.city"
          },
          "province": {
            "S.$": "$.validationResult.normalizedAddress.province"
          },
          "postalCode": {
            "S.$": "$.validationResult.normalizedAddress.postalCode"
          },
          "country": {
            "S.$": "$.validationResult.normalizedAddress.country"
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
      "Next": "PublishEventToMSK"
    },

    "PublishEventToMSK": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:ca-central-1:123456789:function:${env}-publish-to-msk",
      "Comment": "Publie événement dans MSK Kafka pour systèmes abonnés",
      "Parameters": {
        "topic": "client.address.updated",
        "eventType": "ADDRESS_UPDATE",
        "payload.$": "$"
      },
      "TimeoutSeconds": 10,
      "ResultPath": "$.mskResult",
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "ResultPath": "$.error",
          "Next": "LogMSKError"
        }
      ],
      "Next": "WorkflowSuccessful"
    },

    "WorkflowSuccessful": {
      "Type": "Succeed",
      "Comment": "Workflow terminé avec succès"
    },

    "ClientNotFoundError": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:ca-central-1:123456789:function:${env}-send-notification",
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
      "Resource": "arn:aws:lambda:ca-central-1:123456789:function:${env}-send-notification",
      "Parameters": {
        "notificationType": "VALIDATION_FAILED",
        "clientId.$": "$.clientId",
        "validationErrors.$": "$.validationResult.errors",
        "error.$": "$.error"
      },
      "Next": "WorkflowFailed"
    },

    "ApprovalTimeoutNotification": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:ca-central-1:123456789:function:${env}-send-notification",
      "Parameters": {
        "notificationType": "APPROVAL_TIMEOUT",
        "clientId.$": "$.clientId",
        "waitedSeconds": 86400
      },
      "Next": "WorkflowFailed"
    },

    "ApprovalRejectedNotification": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:ca-central-1:123456789:function:${env}-send-notification",
      "Parameters": {
        "notificationType": "APPROVAL_REJECTED",
        "clientId.$": "$.clientId",
        "rejectionReason.$": "$.approvalResult.reason",
        "rejectedBy.$": "$.approvalResult.reviewerName"
      },
      "Next": "WorkflowFailed"
    },

    "MDMAEUpdateFailedNotification": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:ca-central-1:123456789:function:${env}-send-notification",
      "Parameters": {
        "notificationType": "MDMAE_UPDATE_FAILED",
        "clientId.$": "$.clientId",
        "error.$": "$.error"
      },
      "Next": "WorkflowFailed"
    },

    "LogFCCError": {
      "Type": "Pass",
      "Comment": "Log FCC error but continue (non-blocking)",
      "Result": {
        "fccStatus": "FAILED_NON_BLOCKING"
      },
      "ResultPath": "$.fccResult",
      "Next": "SaveAddressHistory"
    },

    "LogMSKError": {
      "Type": "Pass",
      "Comment": "Log MSK error but consider workflow successful",
      "Result": {
        "mskStatus": "FAILED_NON_BLOCKING"
      },
      "ResultPath": "$.mskResult",
      "Next": "WorkflowSuccessful"
    },

    "HandleGenericError": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:ca-central-1:123456789:function:${env}-send-notification",
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

### Graphe visuel du workflow

```
                    ┌─────────────────────┐
                    │ ReadClientProfile   │
                    └──────────┬──────────┘
                               ↓
                    ┌─────────────────────┐
                    │ ValidateAddress     │
                    └──────────┬──────────┘
                               ↓
                        ┌─────────────┐
                        │ CheckValid? │
                        └──────┬──────┘
                               ↓
                           Valid?
                    ┌──────────┴──────────┐
                   YES                    NO
                    ↓                      ↓
        ┌──────────────────┐   ┌──────────────────────┐
        │CheckAddressHistory│   │ValidationFailedNotif │
        └─────────┬─────────┘   └──────────────────────┘
                  ↓
        ┌──────────────────┐
        │EvaluateSuspicious│
        └─────────┬─────────┘
                  ↓
            Suspicious?
        ┌─────────┴─────────┐
       YES                  NO
        ↓                    ↓
┌──────────────────┐  ┌────────────┐
│ManualApproval    │  │UpdateMDMAE │
│(Wait 24h)        │  └─────┬──────┘
└─────────┬────────┘        │
          ↓                 │
    ┌─────────────┐         │
    │ Approved?   │         │
    └──────┬──────┘         │
       ┌───┴───┐            │
      YES     NO            │
       ↓       ↓            │
       │   Rejected         │
       │       ↓            │
       └───────┼────────────┘
               ↓
        ┌─────────────┐
        │SendFCC      │
        └──────┬──────┘
               ↓
        ┌─────────────┐
        │SaveHistory  │ ← DynamoDB direct
        └──────┬──────┘
               ↓
        ┌─────────────┐
        │PublishMSK   │
        └──────┬──────┘
               ↓
        ┌─────────────┐
        │   Success   │
        └─────────────┘
```

---

### Exemple d'exécution réelle

#### Input initial

```json
{
  "clientId": "123456789",
  "address": {
    "street": "1500 rue Peel",
    "city": "Montreal",
    "province": "QC",
    "postalCode": "H3A1S9",
    "country": "CA",
    "type": "HOME"
  },
  "requestId": "req-abc123",
  "timestamp": "2026-09-24T14:30:00Z",
  "source": "API_GATEWAY",
  "userId": "user-456"
}
```

#### Après ReadClientProfile

```json
{
  "clientId": "123456789",
  "address": {...},
  "requestId": "req-abc123",
  "currentProfile": {
    "clientId": "123456789",
    "name": "Jean Tremblay",
    "address": {
      "street": "100 rue Saint-Jacques",
      "city": "Montreal",
      "province": "QC",
      "postalCode": "H2Y 1L6",
      "country": "CA"
    },
    "accountSince": "2015-03-20"
  }
}
```

#### Après ValidateAddress

```json
{
  ...,
  "validationResult": {
    "isValid": true,
    "errors": [],
    "warnings": [],
    "normalizedAddress": {
      "street": "1500 RUE PEEL",
      "city": "MONTREAL",
      "province": "QC",
      "postalCode": "H3A 1S9",
      "country": "CA",
      "type": "HOME"
    }
  }
}
```

#### Après CheckAddressHistory

```json
{
  ...,
  "historyCheck": {
    "suspiciousScore": 0.3,
    "changeCount": 1,
    "previousAddresses": [
      {
        "street": "100 rue Saint-Jacques",
        "changedAt": "2015-03-20"
      }
    ],
    "reason": "Low risk - stable customer with 1 address change in 11 years"
  }
}
```

#### Décision

```
suspiciousScore = 0.3
0.3 > 0.8 ? NON
0.3 > 0.5 ET changeCount > 3 ? NON

→ Passe directement à UpdateMDMAE (pas d'approbation manuelle)
```

#### Après UpdateMDMAE

```json
{
  ...,
  "mdmaeResult": {
    "status": "SUCCESS",
    "transactionId": "MDMAE-TX-789456",
    "timestamp": "2026-09-24T14:30:15Z"
  }
}
```

#### Output final

```json
{
  "clientId": "123456789",
  "status": "SUCCESS",
  "executionId": "arn:aws:states:ca-central-1:123:execution:dev-client-address-update:exec-abc123",
  "mdmaeTransactionId": "MDMAE-TX-789456",
  "historyRecordId": "123456789#2026-09-24T14:30:00Z",
  "mskEventId": "kafka-event-xyz789",
  "processingTime": "4.5s"
}
```

---

## Séparation Infrastructure vs Code Métier

### Principe de séparation

```
┌────────────────────────────────────────────────────────────────┐
│                   SÉPARATION DES PRÉOCCUPATIONS                 │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  mcp-infrastructure (Terraform)      mcp-local (Java)          │
│  ┌──────────────────────────┐       ┌─────────────────────┐   │
│  │ ORCHESTRATION            │       │ LOGIQUE MÉTIER      │   │
│  ├──────────────────────────┤       ├─────────────────────┤   │
│  │ • Workflow Step Functions│       │ • Validation        │   │
│  │ • Ordre des étapes       │       │ • Transformation    │   │
│  │ • Conditions (if/else)   │       │ • Calculs           │   │
│  │ • Gestion d'erreurs      │       │ • Appels API        │   │
│  │ • Retry/timeout          │       │ • Enrichissement    │   │
│  │ • Intégrations AWS       │       │ • Algorithmes       │   │
│  └──────────────────────────┘       └─────────────────────┘   │
│            │                                  │                │
│            │                                  │                │
│         JSON/HCL                            Java               │
│      (Déclaratif)                       (Impératif)            │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

### Qui modifie quoi ?

| Responsabilité | mcp-infrastructure | mcp-local |
|----------------|-------------------|-----------|
| **Ajouter une nouvelle étape** | ✅ DevOps/Infra | ❌ |
| **Changer l'ordre des étapes** | ✅ DevOps/Infra | ❌ |
| **Modifier la logique de validation** | ❌ | ✅ Développeur |
| **Changer l'algorithme de fraude** | ❌ | ✅ Développeur |
| **Ajouter retry sur une Lambda** | ✅ DevOps/Infra | ❌ |
| **Modifier le timeout** | ✅ DevOps/Infra | ❌ |
| **Changer l'API externe appelée** | ❌ | ✅ Développeur |
| **Ajouter une condition if/else** | ✅ DevOps/Infra | ❌ |

### Exemple de modification

#### Scénario 1 : Améliorer l'algorithme de détection de fraude

**Fichier modifié :** `mcp-local/src/.../CheckAddressHistoryLambda.java`

```java
// AVANT
public double calculateSuspiciousScore(List<Address> history) {
    return history.size() > 3 ? 0.8 : 0.2;
}

// APRÈS (Machine Learning)
public double calculateSuspiciousScore(List<Address> history) {
    return mlModel.predict(extractFeatures(history));
}
```

**Actions :**
1. Modifier le code Java
2. `mvn clean package`
3. GitHub Actions → Deploy Lambda Code
4. ✅ Fini !

**⚠️ Pas besoin de toucher mcp-infrastructure !**

---

---

### ❓ Comment le service métier appelle le workflow Step Functions ?

**Réponse courte :** Le service métier (code Java) **appelle** le workflow Step Functions via le **AWS SDK**.

---

#### 🎯 Question importante : Où vivent les Step Functions ?

**✅ OUI, les Step Functions sont TOUJOURS des ressources AWS créées côté infrastructure**

```
┌─────────────────────────────────────────────────────────────┐
│ mcp-infrastructure (Terraform)                              │
├─────────────────────────────────────────────────────────────┤
│ ✅ Step Functions State Machine (ressource AWS)             │
│ ✅ Définition JSON du workflow                              │
│ ✅ ARN: arn:aws:states:ca-central-1:123:stateMachine:...   │
│                                                             │
│ Créé par: terraform apply                                  │
│ Existe dans: AWS Cloud (région ca-central-1)               │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ mcp-local (Code Java)                                       │
├─────────────────────────────────────────────────────────────┤
│ ❌ PAS de définition Step Functions ici                     │
│ ✅ Lambdas (logique métier)                                 │
│ ✅ Code qui APPELLE Step Functions (via SDK)                │
└─────────────────────────────────────────────────────────────┘
```

**Pourquoi ?**
- Step Functions = **orchestrateur AWS**
- C'est une ressource cloud (comme une table DynamoDB, un bucket S3)
- Créée et gérée par Terraform
- Existe dans AWS, pas dans votre code

---

#### 🔄 Les 2 façons d'appeler un workflow Step Functions

### **Option 1 : Via API Gateway → Lambda Controller → Step Functions (Recommandé BNC)**

```
┌──────────┐      ┌──────────────┐      ┌─────────────────┐      ┌──────────────┐
│  Client  │─────→│ API Gateway  │─────→│ Lambda          │─────→│ Step         │
│  HTTP    │      │              │      │ Controller      │      │ Functions    │
└──────────┘      └──────────────┘      └─────────────────┘      └──────────────┘
                                             (Java Code)           (AWS Resource)
```

**Flux détaillé :**

1. **Client** envoie une requête HTTP
   ```bash
   PUT /api/clients/123/address
   Body: {"street": "123 Main", "city": "Montreal", ...}
   ```

2. **API Gateway** reçoit la requête et invoque la **Lambda Controller**

3. **Lambda Controller** (Java) :
   - Valide la requête
   - Enrichit les données
   - **Démarre Step Functions** via AWS SDK
   - Retourne HTTP 202 Accepted

4. **Step Functions** exécute le workflow

---

**Code Java du Controller :**

```java
package com.bnc.mcp.controllers;

import software.amazon.awssdk.services.sfn.SfnClient;
import software.amazon.awssdk.services.sfn.model.StartExecutionRequest;
import software.amazon.awssdk.services.sfn.model.StartExecutionResponse;

public class ClientAddressUpdateController
    implements RequestHandler<APIGatewayProxyRequestEvent, APIGatewayProxyResponseEvent> {

    private final SfnClient sfnClient;
    private final String stateMachineArn;

    public ClientAddressUpdateController() {
        // 1. Créer le client Step Functions
        this.sfnClient = SfnClient.builder().build();

        // 2. Récupérer l'ARN de la State Machine depuis variable d'environnement
        //    (défini dans Terraform)
        this.stateMachineArn = System.getenv("STATE_MACHINE_ARN");
        //    Ex: "arn:aws:states:ca-central-1:123:stateMachine:dev-mcp-client-address-update"
    }

    @Override
    public APIGatewayProxyResponseEvent handleRequest(
        APIGatewayProxyRequestEvent request,
        Context context) {

        // 3. Valider et extraire les données
        String clientId = request.getPathParameters().get("clientId");
        Address address = parseAddress(request.getBody());

        // 4. Préparer l'input pour Step Functions
        Map<String, Object> stepFunctionInput = Map.of(
            "clientId", clientId,
            "address", address,
            "requestId", context.getRequestId(),
            "timestamp", Instant.now().toString()
        );

        // 5. APPELER STEP FUNCTIONS
        StartExecutionResponse execution = startStepFunction(stepFunctionInput);

        // 6. Retourner HTTP 202 Accepted
        return buildResponse(202, Map.of(
            "message", "Address update request accepted",
            "executionArn", execution.executionArn(),
            "status", "PROCESSING"
        ));
    }

    private StartExecutionResponse startStepFunction(Map<String, Object> input) {
        // Convertir input en JSON
        String inputJson = new ObjectMapper().writeValueAsString(input);

        // Générer un nom d'exécution unique
        String executionName = "address-update-" + System.currentTimeMillis();

        // DÉMARRER LE WORKFLOW STEP FUNCTIONS
        StartExecutionRequest request = StartExecutionRequest.builder()
            .stateMachineArn(stateMachineArn)  // ARN de la State Machine (Terraform)
            .input(inputJson)                   // Données à passer au workflow
            .name(executionName)                // Nom unique de l'exécution
            .build();

        return sfnClient.startExecution(request);
    }
}
```

**Variables d'environnement (définies dans Terraform) :**

```hcl
# Dans mcp-infrastructure/modules/lambda/main.tf
resource "aws_lambda_function" "client_address_update_controller" {
  function_name = "${var.environment}-mcp-client-address-update-controller"
  handler       = "com.bnc.mcp.controllers.ClientAddressUpdateController::handleRequest"

  environment {
    variables = {
      # ARN de la State Machine créée par Terraform
      STATE_MACHINE_ARN = aws_sfn_state_machine.client_address_update.arn
      # Ex: arn:aws:states:ca-central-1:123:stateMachine:dev-mcp-client-address-update
    }
  }
}
```

---

### **Option 2 : Via API Gateway → Step Functions direct (Plus simple, moins flexible)**

```
┌──────────┐      ┌──────────────┐      ┌──────────────┐
│  Client  │─────→│ API Gateway  │─────→│ Step         │
│  HTTP    │      │              │      │ Functions    │
└──────────┘      └──────────────┘      └──────────────┘
                   (Intégration          (AWS Resource)
                    AWS directe)
```

**Configuration dans Terraform :**

```hcl
# API Gateway integration directe avec Step Functions
resource "aws_api_gateway_integration" "put_address_stepfunctions" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.address.id
  http_method = aws_api_gateway_method.put_address.http_method

  integration_http_method = "POST"
  type                    = "AWS"
  uri                     = "arn:aws:apigateway:${var.region}:states:action/StartExecution"
  credentials             = aws_iam_role.api_gateway_stepfunctions.arn

  request_templates = {
    "application/json" = jsonencode({
      stateMachineArn = aws_sfn_state_machine.client_address_update.arn
      input = jsonencode({
        clientId = "$input.params('clientId')"
        address  = "$input.body"
      })
    })
  }
}
```

**Avantages :**
- ✅ Pas de Lambda Controller (économie)
- ✅ Moins de code

**Inconvénients (pourquoi BNC utilise Option 1) :**
- ❌ Pas de validation HTTP custom
- ❌ Logging insuffisant pour audit bancaire
- ❌ Pas d'enrichissement de données
- ❌ Gestion d'erreur limitée

**👉 BNC utilise Option 1 (Lambda Controller) pour la traçabilité bancaire.**

---

#### 🔑 Résumé : Comment appeler Step Functions depuis Java

**1. Ajouter dépendance AWS SDK Step Functions dans `pom.xml` :**

```xml
<dependency>
    <groupId>software.amazon.awssdk</groupId>
    <artifactId>sfn</artifactId>
    <version>2.20.0</version>
</dependency>
```

**2. Créer le client Step Functions :**

```java
import software.amazon.awssdk.services.sfn.SfnClient;

SfnClient sfnClient = SfnClient.builder().build();
```

**3. Démarrer une exécution :**

```java
import software.amazon.awssdk.services.sfn.model.StartExecutionRequest;
import software.amazon.awssdk.services.sfn.model.StartExecutionResponse;

StartExecutionResponse response = sfnClient.startExecution(
    StartExecutionRequest.builder()
        .stateMachineArn("arn:aws:states:ca-central-1:123:stateMachine:dev-workflow")
        .input("{\"clientId\":\"123\",\"data\":\"...\"}")
        .name("execution-" + System.currentTimeMillis())
        .build()
);

String executionArn = response.executionArn();
// Ex: "arn:aws:states:ca-central-1:123:execution:dev-workflow:exec-abc123"
```

**4. (Optionnel) Vérifier le statut d'exécution :**

```java
import software.amazon.awssdk.services.sfn.model.DescribeExecutionRequest;
import software.amazon.awssdk.services.sfn.model.DescribeExecutionResponse;

DescribeExecutionResponse execution = sfnClient.describeExecution(
    DescribeExecutionRequest.builder()
        .executionArn(executionArn)
        .build()
);

String status = execution.statusAsString();
// "RUNNING", "SUCCEEDED", "FAILED", "TIMED_OUT", "ABORTED"
```

---

#### 📊 Comparaison : Où est défini quoi ?

| Élément | Définit dans | Déployé par | Format | Exemple |
|---------|-------------|-------------|--------|---------|
| **State Machine** | `mcp-infrastructure` | Terraform | JSON | `client-address-update.json.tpl` |
| **ARN State Machine** | Créé par AWS | Terraform apply | ARN | `arn:aws:states:ca-central-1:123:stateMachine:dev-...` |
| **Lambda handlers** | `mcp-local` | GitHub Actions | Java JAR | `AddressValidatorHandler.java` |
| **Lambda Controller** | `mcp-local` | GitHub Actions | Java JAR | `ClientAddressUpdateController.java` |
| **Appel Step Functions** | `mcp-local` (Controller) | GitHub Actions | Java code | `sfnClient.startExecution(...)` |
| **API Gateway endpoint** | `mcp-infrastructure` | Terraform | HCL | `PUT /api/clients/{id}/address` |

---

#### Scénario 2 : Ajouter une étape de vérification KYC

**Fichier modifié :** `mcp-infrastructure/modules/step_functions/state_machines/client-address-update.json`

```json
{
  "CheckAddressHistory": {
    "Type": "Task",
    "Resource": "...",
    "Next": "VerifyKYC"  // ← Changé (avant: EvaluateSuspicious)
  },

  // ← NOUVEAU ÉTAT
  "VerifyKYC": {
    "Type": "Task",
    "Resource": "arn:aws:lambda:...:verify-kyc",
    "Comment": "Vérifie le statut KYC du client",
    "ResultPath": "$.kycResult",
    "Next": "EvaluateSuspicious"
  }
}
```

**Actions :**
1. Modifier le workflow JSON
2. `terraform apply` (mcp-infrastructure)
3. Créer `VerifyKYCLambda.java` (mcp-local)
4. Deploy Lambda Code
5. ✅ Fini !

---

### Avantages de cette séparation

| Avantage | Description |
|----------|-------------|
| **Évolutivité** | Modifier la logique métier sans toucher l'orchestration |
| **Testabilité** | Tests unitaires (Java) séparés des tests d'intégration (workflow) |
| **Réutilisabilité** | Mêmes Lambdas utilisables dans différents workflows |
| **Clarté** | Responsabilités bien définies |
| **Traçabilité** | Changements d'orchestration vs changements de code séparés dans Git |
| **Audit** | Workflow d'orchestration validé une fois, code métier évolue librement |

---

## Cycle de vie d'un workflow

### Phases de développement

```
┌──────────────────────────────────────────────────────────────┐
│ PHASE 1 : CONCEPTION                                         │
├──────────────────────────────────────────────────────────────┤
│ • Identifier les étapes du workflow                          │
│ • Dessiner le diagramme de flux                              │
│ • Déterminer les points de décision (Choice)                 │
│ • Identifier les intégrations externes                       │
│ • Définir la gestion d'erreurs                               │
└──────────────────────────────────────────────────────────────┘
                        ↓
┌──────────────────────────────────────────────────────────────┐
│ PHASE 2 : DÉFINITION (mcp-infrastructure)                    │
├──────────────────────────────────────────────────────────────┤
│ • Créer le fichier workflow.json (Amazon States Language)    │
│ • Définir les états (Task, Choice, Parallel, Wait)           │
│ • Configurer retry et catch                                  │
│ • Créer les ressources Terraform (Lambda placeholders)       │
│ • terraform apply → Workflow créé (sans code)                │
└──────────────────────────────────────────────────────────────┘
                        ↓
┌──────────────────────────────────────────────────────────────┐
│ PHASE 3 : IMPLÉMENTATION (mcp-local)                         │
├──────────────────────────────────────────────────────────────┤
│ • Implémenter chaque Lambda en Java                          │
│ • Créer les services, validators, clients                    │
│ • Écrire les tests unitaires                                 │
│ • mvn package → Build JARs                                   │
│ • GitHub Actions → Deploy JARs                               │
└──────────────────────────────────────────────────────────────┘
                        ↓
┌──────────────────────────────────────────────────────────────┐
│ PHASE 4 : TESTS                                              │
├──────────────────────────────────────────────────────────────┤
│ • Tests unitaires (Java - JUnit)                             │
│ • Tests d'intégration (AWS Console - Step Functions)         │
│ • Tests de bout en bout (API Gateway → Workflow → DB)        │
│ • Tests de charge (1000+ exécutions concurrentes)            │
└──────────────────────────────────────────────────────────────┘
                        ↓
┌──────────────────────────────────────────────────────────────┐
│ PHASE 5 : MONITORING & OPTIMISATION                          │
├──────────────────────────────────────────────────────────────┤
│ • Analyser les métriques CloudWatch                          │
│ • Optimiser les timeouts et retry                            │
│ • Ajouter des alarmes                                        │
│ • Améliorer la performance des Lambdas                       │
└──────────────────────────────────────────────────────────────┘
```

---

### Itération sur un workflow existant

#### Scénario : Optimiser le workflow après 3 mois en production

**Observations :**
- ✅ 95% des exécutions réussissent du premier coup
- ⚠️ ValidateAddress échoue parfois temporairement (API externe instable)
- ⚠️ CheckHistory prend trop de temps (5-10s)
- ⚠️ Seulement 2% des cas nécessitent approbation manuelle

**Améliorations :**

1. **Ajouter retry sur ValidateAddress** (Infrastructure)

```json
{
  "ValidateAddress": {
    "Type": "Task",
    "Resource": "...",
    "Retry": [
      {
        "ErrorEquals": ["States.TaskFailed"],
        "IntervalSeconds": 2,
        "MaxAttempts": 3,  // ← AJOUTÉ
        "BackoffRate": 2.0
      }
    ]
  }
}
```

2. **Optimiser CheckHistory avec cache** (Code métier)

```java
// AVANT
public HistoryCheck checkHistory(String clientId) {
    List<Address> history = dynamoDB.query(clientId); // 5-10s
    return analyzeHistory(history);
}

// APRÈS
public HistoryCheck checkHistory(String clientId) {
    String cacheKey = "history:" + clientId;
    List<Address> history = cache.get(cacheKey); // 50ms

    if (history == null) {
        history = dynamoDB.query(clientId);
        cache.put(cacheKey, history, TTL_1_HOUR);
    }

    return analyzeHistory(history);
}
```

3. **Exécuter ValidateAddress et CheckHistory en parallèle** (Infrastructure)

```json
{
  "ProcessInParallel": {
    "Type": "Parallel",
    "Branches": [
      {
        "StartAt": "ValidateAddress",
        "States": {
          "ValidateAddress": {...}
        }
      },
      {
        "StartAt": "CheckHistory",
        "States": {
          "CheckHistory": {...}
        }
      }
    ],
    "Next": "EvaluateResults"
  }
}
```

**Résultat :**
- ✅ Latence réduite de 15s → 8s (parallélisation)
- ✅ Taux de réussite augmenté de 95% → 99.5% (retry)
- ✅ Coûts réduits de 30% (moins d'exécutions échouées)

---

## Avantages pour BNC (Banking Context)

### 🏦 1. Conformité réglementaire

**Exigences bancaires canadiennes :**

| Exigence | Comment Step Functions répond |
|----------|-------------------------------|
| **Traçabilité complète** | ✅ Historique permanent de toutes les exécutions (CloudWatch) |
| **Audit trail** | ✅ Input/output de chaque étape enregistré |
| **Non-répudiation** | ✅ Impossible de modifier l'historique d'exécution |
| **Versionnement** | ✅ Git history du workflow JSON |
| **Separation of Duties** | ✅ Infrastructure (DevOps) vs Code (Dev) |
| **Disaster Recovery** | ✅ Terraform permet de recréer exactement le même workflow |

**Exemple d'audit :**

```bash
# Auditeur : "Montrez toutes les mises à jour d'adresse suspectes en 2026"

# 1. AWS Console → Step Functions → client-address-update
# 2. Filter executions:
#    - Status: All
#    - Date: 2026-01-01 to 2026-12-31
# 3. Export to JSON
# 4. Parse JSON pour trouver executions avec "RequireManualApproval"

# Résultat :
# - 1,234 exécutions totales
# - 23 ont nécessité approbation manuelle (1.8%)
# - 21 approuvées, 2 rejetées
# - Temps moyen d'approbation : 4.2 heures
```

**Avec du code Java :**
- ❌ Logs CloudWatch non structurés
- ❌ Besoin de parsing manuel
- ❌ Pas de graphe visuel
- ❌ Difficile de prouver la conformité

---

### 🏦 2. Gestion des transactions financières

**Workflows bancaires typiques :**

1. **Validation en cascade**

```
Virement > 10,000$ :
  → Vérifier solde
  → Vérifier limite quotidienne
  → Vérifier liste noire (sanctions)
  → Approbation manager
  → Exécuter virement
  → Notifier destinataire
```

2. **Compensation automatique**

```
Si UpdateMDMAE échoue :
  → Rollback DynamoDB
  → Reverser transaction
  → Notifier client
  → Log pour investigation
```

**Step Functions permet :**
- ✅ Transactions atomiques (tout ou rien)
- ✅ Compensation automatique en cas d'erreur
- ✅ Retry avec backoff exponentiel
- ✅ Circuit breaker pattern

---

### 🏦 3. Sécurité et isolation

**Isolation des workflows :**

```
Workflow A : Mise à jour adresse (low risk)
  → Timeout: 5 minutes
  → Retry: 3 fois
  → Pas d'approbation manuelle

Workflow B : Transfert international > 50,000$ (high risk)
  → Timeout: 24 heures (attente approbation)
  → Retry: 0 (pas de retry automatique)
  → Approbation obligatoire (2 managers)
  → Vérification sanctions internationales
```

**Avec Step Functions :**
- ✅ Chaque workflow est isolé
- ✅ Permissions IAM granulaires par workflow
- ✅ Pas de contamination entre workflows

---

### 🏦 4. Scalabilité pour millions de clients

**BNC gère 2.6 millions de clients** :

```
Scénario : Mise à jour massive d'adresses (ex: fusion avec autre banque)
  → 500,000 clients à migrer
  → Workflow d'update d'adresse pour chacun
```

**Avec Step Functions :**

```python
# Déclencher 500,000 workflows en parallèle
for client in clients:
    step_functions.start_execution(
        stateMachineArn=workflow_arn,
        input=json.dumps({"clientId": client.id, "address": client.new_address})
    )
```

**Résultat :**
- ✅ 500,000 exécutions concurrentes
- ✅ Auto-scaling automatique des Lambdas
- ✅ Pas de serveur à gérer
- ✅ Monitoring en temps réel de toutes les exécutions

---

### 🏦 5. Intégration avec systèmes legacy

**BNC utilise des systèmes mainframe + modernes** :

```
Système legacy (IBM Mainframe) :
  → Pas d'API REST moderne
  → Utilise IBM MQ pour communication
  → Batch processing nocturne
```

**Workflow Step Functions permet :**

```json
{
  "SendToMainframe": {
    "Type": "Task",
    "Resource": "arn:aws:lambda:...:ibm-mq-sender",
    "Comment": "Envoie message IBM MQ au mainframe",
    "Next": "WaitForMainframeResponse"
  },

  "WaitForMainframeResponse": {
    "Type": "Task",
    "Resource": "arn:aws:states:::sqs:receiveMessage.waitForTaskToken",
    "Comment": "Attend réponse du mainframe (peut prendre 1-2 heures)",
    "TimeoutSeconds": 7200,
    "Next": "ProcessMainframeResponse"
  }
}
```

**Avantages :**
- ✅ Bridge entre legacy et moderne
- ✅ Gère les délais longs (mainframe batch)
- ✅ Pas besoin de modifier le mainframe

---

## Patterns et bonnes pratiques

### Pattern 1 : Saga Pattern (Distributed Transactions)

**Problème :** Transaction distribuée entre plusieurs services

**Solution Step Functions :**

```json
{
  "StartAt": "ReserveInventory",
  "States": {
    "ReserveInventory": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:...:reserve-inventory",
      "ResultPath": "$.reservation",
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "Next": "WorkflowFailed"
        }
      ],
      "Next": "ChargeCustomer"
    },

    "ChargeCustomer": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:...:charge-customer",
      "ResultPath": "$.payment",
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "Next": "CompensateReserveInventory"
        }
      ],
      "Next": "ShipOrder"
    },

    "ShipOrder": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:...:ship-order",
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "Next": "CompensateChargeCustomer"
        }
      ],
      "Next": "Success"
    },

    "CompensateReserveInventory": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:...:cancel-reservation",
      "Next": "WorkflowFailed"
    },

    "CompensateChargeCustomer": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:...:refund-customer",
      "Next": "CompensateReserveInventory"
    }
  }
}
```

**Résultat :**
- ✅ Si n'importe quelle étape échoue, compensation automatique
- ✅ Consistency garantie

---

### Pattern 2 : Circuit Breaker

**Problème :** Service externe instable, éviter d'overload

**Solution Step Functions :**

```json
{
  "CallExternalAPI": {
    "Type": "Task",
    "Resource": "arn:aws:lambda:...:call-api",
    "Retry": [
      {
        "ErrorEquals": ["Throttling"],
        "IntervalSeconds": 60,
        "MaxAttempts": 5,
        "BackoffRate": 2.0
      }
    ],
    "Catch": [
      {
        "ErrorEquals": ["States.ALL"],
        "Next": "UseCache"
      }
    ],
    "Next": "Success"
  },

  "UseCache": {
    "Type": "Task",
    "Resource": "arn:aws:lambda:...:get-from-cache",
    "Next": "Success"
  }
}
```

---

### Pattern 3 : Human-in-the-Loop

**Problème :** Besoin d'approbation humaine dans le workflow

**Solution Step Functions :**

```json
{
  "RequestApproval": {
    "Type": "Task",
    "Resource": "arn:aws:states:::sqs:sendMessage.waitForTaskToken",
    "Parameters": {
      "QueueUrl": "https://sqs.ca-central-1.amazonaws.com/...",
      "MessageBody": {
        "taskToken.$": "$$.Task.Token",
        "approvalData.$": "$"
      }
    },
    "TimeoutSeconds": 86400,
    "Next": "ProcessApproval"
  }
}
```

**Système d'approbation externe :**

```java
// Approver clicks "Approve" button
stepFunctionsClient.sendTaskSuccess(
    SendTaskSuccessRequest.builder()
        .taskToken(taskToken)
        .output(json.dumps({"decision": "APPROVED"}))
        .build()
);

// Workflow resumes immediately
```

---

### Bonnes pratiques

#### 1. Timeouts appropriés

```json
{
  "QuickValidation": {
    "TimeoutSeconds": 10  // ← Lambda rapide
  },

  "ExternalAPICall": {
    "TimeoutSeconds": 30  // ← API externe
  },

  "BatchProcessing": {
    "TimeoutSeconds": 900  // ← 15 min max (Lambda limit)
  },

  "HumanApproval": {
    "TimeoutSeconds": 86400  // ← 24 heures
  }
}
```

---

#### 2. Retry stratégique

```json
{
  "Retry": [
    {
      "ErrorEquals": ["TemporaryError", "ThrottlingException"],
      "MaxAttempts": 3,
      "BackoffRate": 2.0  // ← Retry avec back-off
    },
    {
      "ErrorEquals": ["PermanentError"],
      "MaxAttempts": 0  // ← Pas de retry
    }
  ]
}
```

---

#### 3. ResultPath pour éviter d'écraser l'input

```json
{
  "ValidateAddress": {
    "Type": "Task",
    "Resource": "...",
    "ResultPath": "$.validationResult"  // ← Ajoute au lieu d'écraser
  }
}
```

**AVANT (sans ResultPath) :**
```json
Input:  {"clientId": "123", "address": {...}}
Output: {"isValid": true}  // ← clientId perdu !
```

**APRÈS (avec ResultPath) :**
```json
Input:  {"clientId": "123", "address": {...}}
Output: {"clientId": "123", "address": {...}, "validationResult": {"isValid": true}}
```

---

#### 4. Catch hiérarchique

```json
{
  "Catch": [
    {
      "ErrorEquals": ["ValidationException"],
      "Next": "HandleValidationError"
    },
    {
      "ErrorEquals": ["DatabaseException"],
      "Next": "HandleDatabaseError"
    },
    {
      "ErrorEquals": ["States.ALL"],  // ← Catch-all en dernier
      "Next": "HandleGenericError"
    }
  ]
}
```

---

#### 5. Nommage descriptif

```json
{
  "States": {
    "ValidateClientAddress": {  // ✅ Descriptif
      "Type": "Task",
      "Comment": "Valide le format de l'adresse selon normes canadiennes"
    },

    "State1": {  // ❌ Non descriptif
      "Type": "Task"
    }
  }
}
```

---

## Comparaison : Avec vs Sans Step Functions

### Scénario : Workflow "Client Address Update"

#### Option A : Avec Step Functions (Recommandé BNC)

**Architecture :**
```
API Gateway → Lambda Controller → Step Functions
                                   ↓
                         ┌─────────┴─────────┐
                         │                   │
                   ValidateAddress    CheckHistory
                         │                   │
                         └─────────┬─────────┘
                                   ↓
                              UpdateMDMAE
```

**Code Infrastructure (50 lignes JSON) :**
```json
{
  "StartAt": "ValidateAddress",
  "States": {
    "ValidateAddress": {...},
    "CheckHistory": {...},
    "UpdateMDMAE": {...}
  }
}
```

**Code Métier (100 lignes Java par Lambda) :**
```java
public class ValidateAddressLambda {
    public ValidationResult handleRequest(Input input) {
        // Logique de validation pure
    }
}
```

**Avantages :**
- ✅ Graphe visuel dans AWS Console
- ✅ Retry/timeout automatiques
- ✅ Traçabilité complète
- ✅ Facile à debugger
- ✅ Scalable (millions d'exécutions)
- ✅ Pas de timeout 15 min

**Inconvénients :**
- ⚠️ Courbe d'apprentissage (JSON ASL)
- ⚠️ Coût légèrement plus élevé (mais marginal)

---

#### Option B : Sans Step Functions (Code Java pur)

**Architecture :**
```
API Gateway → Lambda Orchestrator (fait tout)
```

**Code Java (500+ lignes) :**
```java
@Slf4j
public class AddressUpdateOrchestrator {

    public APIGatewayProxyResponseEvent handleRequest(
            APIGatewayProxyRequestEvent request, Context context) {

        try {
            // 1. Validate address
            ValidationResult validation = validateAddress(input);
            if (!validation.isValid()) {
                return buildErrorResponse(400, validation.getErrors());
            }

            // 2. Check history with retry
            HistoryCheck history = null;
            int retries = 0;
            while (retries < 3) {
                try {
                    history = checkHistory(input.getClientId());
                    break;
                } catch (Exception e) {
                    retries++;
                    if (retries == 3) throw e;
                    Thread.sleep(2000 * retries);
                }
            }

            // 3. Decision logic
            if (history.getSuspiciousScore() > 0.8) {
                // Send to SQS for manual approval
                sendToApprovalQueue(input);

                // PROBLÈME : Comment attendre l'approbation ?
                // Lambda timeout = 15 min max
                // On ne peut pas attendre 24h !
                return buildResponse(202, "Pending approval");
            }

            // 4. Update MDMAE with retry
            MDMAEResult mdmae = null;
            retries = 0;
            while (retries < 3) {
                try {
                    mdmae = updateMDMAE(validation.getNormalizedAddress());
                    break;
                } catch (TemporaryException e) {
                    retries++;
                    Thread.sleep(5000 * retries);
                } catch (PermanentException e) {
                    log.error("MDMAE permanent error", e);
                    sendErrorNotification(e);
                    return buildErrorResponse(500, "MDMAE update failed");
                }
            }

            // 5. Send FCC
            try {
                sendFCC(input);
            } catch (Exception e) {
                // Log but don't fail (non-blocking)
                log.error("FCC send failed", e);
            }

            // 6. Save history
            saveHistory(input, validation, mdmae);

            // 7. Publish to MSK
            try {
                publishToMSK(input);
            } catch (Exception e) {
                log.error("MSK publish failed", e);
            }

            return buildSuccessResponse(200, mdmae);

        } catch (Exception e) {
            log.error("Orchestration error", e);
            return buildErrorResponse(500, "Internal error");
        }
    }

    // + 20 méthodes helper (validateAddress, checkHistory, etc.)
}
```

**Problèmes :**

| Problème | Impact |
|----------|--------|
| **Code verbeux** | 500+ lignes vs 50 lignes JSON |
| **Pas de visibilité** | Impossible de voir où en est le workflow |
| **Timeout Lambda** | Max 15 min, impossible d'attendre approbation humaine |
| **Gestion manuelle des erreurs** | try/catch partout, complexe |
| **Pas de traçabilité** | Logs non structurés, difficile à auditer |
| **Difficile à tester** | Tout dans une seule Lambda |
| **Pas de parallélisation** | Difficile de faire ValidateAddress et CheckHistory en parallèle |
| **Coût** | Lambda facturée pendant toute la durée (vs Step Functions qui ne facture que les transitions) |

---

### Verdict : Pourquoi Step Functions pour BNC

```
┌─────────────────────────────────────────────────────────────┐
│ CONCLUSION : Step Functions est ESSENTIEL pour BNC         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ ✅ Conformité bancaire (audit trail, traçabilité)          │
│ ✅ Workflows de longue durée (approbation manuelle)        │
│ ✅ Gestion automatique des erreurs                         │
│ ✅ Scalabilité (millions de clients)                       │
│ ✅ Visibilité (graphe visuel AWS Console)                  │
│ ✅ Séparation Infrastructure vs Code                       │
│ ✅ Retry et timeout automatiques                           │
│ ✅ Intégrations natives AWS                                │
│ ✅ Coût optimisé (pay-per-transition)                      │
│                                                             │
│ Alternative (code pur) = ❌ Complexité ingérable            │
└─────────────────────────────────────────────────────────────┘
```

---

## Résumé exécutif

### POURQUOI Step Functions dans mcp-infrastructure ?

1. **Séparation des responsabilités** : Orchestration (Infra) vs Logique métier (Code)
2. **Déclaratif** : Définir CE QUE on veut, pas COMMENT le faire
3. **Infrastructure as Code** : Versionné, auditable, reproductible
4. **Conformité bancaire** : Audit trail permanent, traçabilité complète

### COMMENT fonctionne Step Functions ?

1. **Workflow JSON** : Amazon States Language (ASL)
2. **Types d'états** : Task, Choice, Parallel, Wait, Succeed, Fail
3. **Gestion d'erreurs** : Retry automatique avec back-off, Catch pour erreurs
4. **Passage de données** : JSON entre états via ResultPath
5. **Intégrations** : 200+ services AWS natifs

### L'importance de Step Functions

1. **Visibilité** : Graphe visuel en temps réel de l'exécution
2. **Gestion d'erreurs** : Automatique, déclarative, testable
3. **Workflows longs** : Pas de limite 15 min (Lambda), peut durer 1 an
4. **Scalabilité** : Millions d'exécutions concurrentes
5. **Intégrations** : DynamoDB, SQS, SNS sans Lambda intermédiaire

### Pour BNC spécifiquement

- ✅ **2.6 millions de clients** : Scalabilité prouvée
- ✅ **Audit bancaire** : Traçabilité complète requise
- ✅ **Systèmes legacy** : Bridge entre mainframe et cloud
- ✅ **Approbations manuelles** : Workflows de 24h+ supportés
- ✅ **Conformité** : Réglementations bancaires canadiennes

---

**Dernière mise à jour** : 2026-09-24
**Auteur** : Claude Code
**Version** : 1.0