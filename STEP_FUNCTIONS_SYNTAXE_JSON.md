# Step Functions : Syntaxe JSON Complète

## 📐 Structure de base d'un workflow

```json
{
  "Comment": "Description du workflow",
  "StartAt": "PremierEtat",
  "States": {
    "PremierEtat": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:ca-central-1:123:function:ma-fonction",
      "End": true
    }
  }
}
```

**Éléments obligatoires :**
- `StartAt` : Nom du premier état à exécuter
- `States` : Objet contenant tous les états du workflow

**Éléments optionnels :**
- `Comment` : Description du workflow
- `TimeoutSeconds` : Timeout global (max 1 an)
- `Version` : Version de l'Amazon States Language (défaut: "1.0")

---

## 🔢 Les 8 types d'états (States)

### 1️⃣ **Task** - Exécuter une tâche

Invoque une Lambda, une activité, ou un service AWS.

```json
{
  "ValidateAddress": {
    "Type": "Task",
    "Resource": "arn:aws:lambda:ca-central-1:123:function:validate-address",
    "Comment": "Valide le format de l'adresse",
    "TimeoutSeconds": 30,
    "HeartbeatSeconds": 10,
    "ResultPath": "$.validationResult",
    "InputPath": "$.addressData",
    "OutputPath": "$.validationResult",
    "Parameters": {
      "address.$": "$.addressData.fullAddress",
      "country": "CA"
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
        "ErrorEquals": ["ValidationError"],
        "ResultPath": "$.error",
        "Next": "HandleValidationError"
      },
      {
        "ErrorEquals": ["States.ALL"],
        "ResultPath": "$.error",
        "Next": "HandleGenericError"
      }
    ],
    "Next": "CheckResult"
  }
}
```

**Paramètres clés :**
- `Resource` : ARN de la ressource à invoquer (Lambda, activité, service AWS)
- `TimeoutSeconds` : Timeout maximum (défaut: 60s, max: 1 an)
- `HeartbeatSeconds` : Délai max entre deux heartbeats (pour activités longues)
- `ResultPath` : Où stocker le résultat (`$.chemin`, `null` pour ignorer, `$` pour remplacer)
- `InputPath` : Sélectionner une partie de l'input
- `OutputPath` : Sélectionner une partie de l'output
- `Parameters` : Transformer l'input avant l'invocation
- `Retry` : Configuration de retry automatique
- `Catch` : Gestion d'erreurs
- `Next` : État suivant (ou `End: true`)

---

### 2️⃣ **Choice** - Branchement conditionnel

Décide de la prochaine étape selon une condition (if/else/switch).

```json
{
  "EvaluateAge": {
    "Type": "Choice",
    "Comment": "Vérifie l'âge du client",
    "Choices": [
      {
        "Variable": "$.age",
        "NumericGreaterThan": 65,
        "Next": "Senior"
      },
      {
        "And": [
          {
            "Variable": "$.age",
            "NumericGreaterThanEquals": 18
          },
          {
            "Variable": "$.age",
            "NumericLessThanEquals": 65
          }
        ],
        "Next": "Adult"
      },
      {
        "Variable": "$.age",
        "NumericLessThan": 18,
        "Next": "Minor"
      }
    ],
    "Default": "InvalidAge"
  }
}
```

**Opérateurs de comparaison :**

| Type | Opérateurs |
|------|-----------|
| **String** | `StringEquals`, `StringLessThan`, `StringGreaterThan`, `StringLessThanEquals`, `StringGreaterThanEquals`, `StringMatches` |
| **Numeric** | `NumericEquals`, `NumericLessThan`, `NumericGreaterThan`, `NumericLessThanEquals`, `NumericGreaterThanEquals` |
| **Boolean** | `BooleanEquals` |
| **Timestamp** | `TimestampEquals`, `TimestampLessThan`, `TimestampGreaterThan`, `TimestampLessThanEquals`, `TimestampGreaterThanEquals` |

**Opérateurs logiques :**
- `And` : Toutes les conditions doivent être vraies
- `Or` : Au moins une condition doit être vraie
- `Not` : Inverse la condition

**Opérateurs de présence :**
- `IsPresent` : Vérifie si la variable existe
- `IsNull` : Vérifie si la variable est null
- `IsNumeric` : Vérifie si c'est un nombre
- `IsString` : Vérifie si c'est une chaîne
- `IsBoolean` : Vérifie si c'est un booléen
- `IsTimestamp` : Vérifie si c'est un timestamp

**Exemple avec conditions complexes :**

```json
{
  "Type": "Choice",
  "Choices": [
    {
      "And": [
        {
          "Variable": "$.transaction.amount",
          "NumericGreaterThan": 10000
        },
        {
          "Or": [
            {
              "Variable": "$.transaction.country",
              "StringEquals": "US"
            },
            {
              "Variable": "$.transaction.country",
              "StringEquals": "CA"
            }
          ]
        },
        {
          "Not": {
            "Variable": "$.user.isVerified",
            "BooleanEquals": true
          }
        }
      ],
      "Next": "RequireAdditionalVerification"
    }
  ],
  "Default": "StandardProcessing"
}
```

---

### 3️⃣ **Parallel** - Exécution parallèle

Exécute plusieurs branches en même temps et attend que toutes se terminent.

```json
{
  "ValidateInParallel": {
    "Type": "Parallel",
    "Comment": "Valide adresse, email et téléphone en parallèle",
    "Branches": [
      {
        "StartAt": "ValidateAddress",
        "States": {
          "ValidateAddress": {
            "Type": "Task",
            "Resource": "arn:aws:lambda:...:function:validate-address",
            "End": true
          }
        }
      },
      {
        "StartAt": "ValidateEmail",
        "States": {
          "ValidateEmail": {
            "Type": "Task",
            "Resource": "arn:aws:lambda:...:function:validate-email",
            "End": true
          }
        }
      },
      {
        "StartAt": "ValidatePhone",
        "States": {
          "ValidatePhone": {
            "Type": "Task",
            "Resource": "arn:aws:lambda:...:function:validate-phone",
            "End": true
          }
        }
      }
    ],
    "ResultPath": "$.validations",
    "Retry": [
      {
        "ErrorEquals": ["States.TaskFailed"],
        "MaxAttempts": 2
      }
    ],
    "Catch": [
      {
        "ErrorEquals": ["States.ALL"],
        "ResultPath": "$.error",
        "Next": "HandleError"
      }
    ],
    "Next": "AggregateResults"
  }
}
```

**Comportement :**
- Exécute **toutes** les branches simultanément
- Attend que **toutes** les branches se terminent
- Résultat = tableau des résultats de chaque branche (dans l'ordre)
- Si **une seule** branche échoue → tout le Parallel échoue

**Exemple de résultat :**
```json
{
  "validations": [
    {"isValid": true, "address": "..."},    // Branche 1
    {"isValid": true, "email": "..."},      // Branche 2
    {"isValid": false, "phone": "..."}      // Branche 3
  ]
}
```

---

### 4️⃣ **Wait** - Pause / Attente

Attend un certain temps ou jusqu'à une date/heure spécifique.

**Option A : Durée fixe en secondes**
```json
{
  "Wait5Minutes": {
    "Type": "Wait",
    "Seconds": 300,
    "Next": "ContinueProcessing"
  }
}
```

**Option B : Jusqu'à une date/heure précise**
```json
{
  "WaitUntilDate": {
    "Type": "Wait",
    "Timestamp": "2026-12-31T23:59:59Z",
    "Next": "NewYearProcessing"
  }
}
```

**Option C : Durée dynamique (depuis l'input)**
```json
{
  "WaitDynamic": {
    "Type": "Wait",
    "SecondsPath": "$.delayInSeconds",
    "Next": "ContinueProcessing"
  }
}
```

**Option D : Date dynamique (depuis l'input)**
```json
{
  "WaitUntilDynamicDate": {
    "Type": "Wait",
    "TimestampPath": "$.scheduledTime",
    "Next": "ContinueProcessing"
  }
}
```

**Limites :**
- Maximum : **1 an** (365 jours)

---

### 5️⃣ **Pass** - État de passage

Ne fait aucun traitement, sert à transformer ou injecter des données.

```json
{
  "AddMetadata": {
    "Type": "Pass",
    "Comment": "Ajoute des métadonnées statiques",
    "Result": {
      "status": "PROCESSING",
      "timestamp": "2026-09-24T10:00:00Z",
      "environment": "DEV"
    },
    "ResultPath": "$.metadata",
    "Next": "ProcessData"
  }
}
```

**Utilisations courantes :**

**1. Ajouter des données statiques :**
```json
{
  "Type": "Pass",
  "Result": {"status": "PENDING"},
  "ResultPath": "$.status",
  "Next": "..."
}
```

**2. Transformer la structure de données :**
```json
{
  "Type": "Pass",
  "Parameters": {
    "clientId.$": "$.client.id",
    "name.$": "$.client.fullName",
    "timestamp.$": "$$.State.EnteredTime"
  },
  "Next": "..."
}
```

**3. Debug (inspecter les données) :**
```json
{
  "Type": "Pass",
  "Comment": "État de debug pour voir les données",
  "Next": "RealProcessing"
}
```

---

### 6️⃣ **Succeed** - Fin avec succès

Termine le workflow avec succès.

```json
{
  "Success": {
    "Type": "Succeed",
    "Comment": "Workflow terminé avec succès"
  }
}
```

**Caractéristiques :**
- Pas de paramètre `Next` (c'est la fin)
- Retourne l'input final comme résultat de l'exécution
- Status de l'exécution : `SUCCEEDED`

---

### 7️⃣ **Fail** - Fin avec échec

Termine le workflow en échec.

```json
{
  "ValidationFailed": {
    "Type": "Fail",
    "Error": "ValidationError",
    "Cause": "L'adresse fournie ne correspond à aucun format valide. Codes postaux acceptés: CA (H1A 1A1) et US (12345)."
  }
}
```

**Paramètres :**
- `Error` : Code d'erreur (type d'erreur, ex: "ValidationError", "TimeoutError")
- `Cause` : Message d'erreur détaillé (description de ce qui s'est passé)

**Caractéristiques :**
- Status de l'exécution : `FAILED`
- L'erreur et la cause apparaissent dans l'historique de l'exécution

---

### 8️⃣ **Map** - Itération sur un tableau

Exécute un workflow pour chaque élément d'un tableau.

```json
{
  "ProcessAllClients": {
    "Type": "Map",
    "Comment": "Traite tous les clients du tableau",
    "ItemsPath": "$.clients",
    "MaxConcurrency": 10,
    "Parameters": {
      "client.$": "$$.Map.Item.Value",
      "index.$": "$$.Map.Item.Index",
      "metadata.$": "$.metadata"
    },
    "Iterator": {
      "StartAt": "ValidateClient",
      "States": {
        "ValidateClient": {
          "Type": "Task",
          "Resource": "arn:aws:lambda:...:function:validate-client",
          "ResultPath": "$.validation",
          "Next": "CheckValidation"
        },
        "CheckValidation": {
          "Type": "Choice",
          "Choices": [
            {
              "Variable": "$.validation.isValid",
              "BooleanEquals": true,
              "Next": "SaveClient"
            }
          ],
          "Default": "MarkInvalid"
        },
        "SaveClient": {
          "Type": "Task",
          "Resource": "arn:aws:lambda:...:function:save-client",
          "End": true
        },
        "MarkInvalid": {
          "Type": "Pass",
          "Result": {"status": "INVALID"},
          "ResultPath": "$.result",
          "End": true
        }
      }
    },
    "ResultPath": "$.processedClients",
    "Next": "GenerateReport"
  }
}
```

**Paramètres clés :**
- `ItemsPath` : Chemin vers le tableau dans l'input (ex: `$.clients`)
- `MaxConcurrency` : Nombre d'itérations parallèles max (défaut: 0 = illimité)
- `Iterator` : Workflow à exécuter pour chaque élément
- `Parameters` : Données passées à chaque itération

**Variables spéciales Map :**
- `$$.Map.Item.Value` : Valeur de l'élément actuel
- `$$.Map.Item.Index` : Index de l'élément actuel (0, 1, 2...)

**Exemple d'input :**
```json
{
  "clients": [
    {"id": "123", "name": "Alice"},
    {"id": "456", "name": "Bob"},
    {"id": "789", "name": "Charlie"}
  ],
  "metadata": {"region": "CA"}
}
```

**Résultat :**
```json
{
  "clients": [...],
  "metadata": {...},
  "processedClients": [
    {"status": "VALID", "client": {"id": "123", "name": "Alice"}},
    {"status": "VALID", "client": {"id": "456", "name": "Bob"}},
    {"status": "INVALID", "result": {"status": "INVALID"}}
  ]
}
```

---

## 📦 Passage de données entre états

### Les 4 paramètres de manipulation de données

```json
{
  "MonEtat": {
    "Type": "Task",
    "Resource": "arn:aws:lambda:...",
    "InputPath": "$.donnees",        // 1️⃣ Sélectionner input
    "Parameters": {                   // 2️⃣ Transformer input
      "clientId.$": "$.id",
      "fixedValue": "constant"
    },
    "ResultPath": "$.resultat",      // 3️⃣ Où stocker le résultat
    "OutputPath": "$.finalOutput",   // 4️⃣ Sélectionner output
    "Next": "EtatSuivant"
  }
}
```

---

### 1️⃣ **InputPath** - Filtrer l'input

Sélectionne une partie de l'input à passer à l'état.

**Exemple :**
```json
// Input complet :
{
  "clientId": "123",
  "donnees": {"nom": "Dupont", "age": 30},
  "metadata": {"region": "QC"}
}

// Avec InputPath: "$.donnees"
{
  "InputPath": "$.donnees"
}

// La Lambda reçoit seulement :
{
  "nom": "Dupont",
  "age": 30
}
```

**Valeurs spéciales :**
- `"$"` : Passer tout l'input (défaut)
- `null` : Passer un objet vide `{}`

---

### 2️⃣ **Parameters** - Transformer l'input

Construit un nouvel input en combinant des valeurs de l'input, des constantes, et des variables contextuelles.

**Syntaxe :**
- Clé sans `.$` : Valeur **statique**
- Clé avec `.$` : Valeur **dynamique** (chemin JSON)

**Exemple :**
```json
{
  "Parameters": {
    "clientId.$": "$.client.id",              // Depuis input
    "timestamp.$": "$$.State.EnteredTime",     // Variable contextuelle
    "environment": "DEV",                      // Valeur fixe
    "fullInput.$": "$"                         // Input complet
  }
}
```

**Variables contextuelles (`$$`) :**

| Variable | Description | Exemple |
|----------|-------------|---------|
| `$$.Execution.Id` | ID unique de l'exécution | `"arn:aws:states:ca-central-1:123:execution:workflow:abc-123"` |
| `$$.Execution.Name` | Nom de l'exécution | `"address-update-1234567890"` |
| `$$.Execution.StartTime` | Timestamp de début | `"2026-09-24T10:00:00.000Z"` |
| `$$.State.EnteredTime` | Timestamp d'entrée dans l'état | `"2026-09-24T10:00:05.123Z"` |
| `$$.State.Name` | Nom de l'état actuel | `"ValidateAddress"` |
| `$$.StateMachine.Id` | ARN de la state machine | `"arn:aws:states:ca-central-1:123:stateMachine:workflow"` |
| `$$.StateMachine.Name` | Nom de la state machine | `"client-address-update"` |

**Exemple complet :**
```json
// Input :
{
  "clientId": "123",
  "address": {"street": "123 Main", "city": "Montreal"}
}

// Parameters :
{
  "Parameters": {
    "client.$": "$.clientId",
    "addressData.$": "$.address",
    "requestId.$": "$$.Execution.Id",
    "timestamp.$": "$$.State.EnteredTime",
    "source": "API_GATEWAY",
    "environment": "DEV"
  }
}

// Lambda reçoit :
{
  "client": "123",
  "addressData": {"street": "123 Main", "city": "Montreal"},
  "requestId": "arn:aws:states:ca-central-1:123:execution:workflow:abc-123",
  "timestamp": "2026-09-24T10:00:05.123Z",
  "source": "API_GATEWAY",
  "environment": "DEV"
}
```

---

### 3️⃣ **ResultPath** - Où stocker le résultat

Détermine où placer le résultat de l'état dans l'input.

**Exemple A : Ajouter le résultat dans un nouveau champ**
```json
// Input :
{"clientId": "123", "nom": "Dupont"}

// Résultat de la Lambda :
{"isValid": true, "score": 95}

// Avec ResultPath: "$.validation"
{
  "ResultPath": "$.validation"
}

// Output :
{
  "clientId": "123",
  "nom": "Dupont",
  "validation": {"isValid": true, "score": 95}  // ← Ajouté
}
```

**Exemple B : Remplacer tout l'input par le résultat**
```json
// Avec ResultPath: "$"
{
  "ResultPath": "$"
}

// Output :
{"isValid": true, "score": 95}  // Input original perdu
```

**Exemple C : Ignorer le résultat (garder input original)**
```json
// Avec ResultPath: null
{
  "ResultPath": null
}

// Output :
{"clientId": "123", "nom": "Dupont"}  // Résultat ignoré
```

**Valeurs spéciales :**
- `"$"` : Remplacer tout l'input par le résultat (défaut)
- `null` : Ignorer le résultat, garder l'input original
- `"$.chemin"` : Ajouter le résultat dans `$.chemin`

---

### 4️⃣ **OutputPath** - Filtrer l'output

Sélectionne une partie de l'output à passer à l'état suivant.

**Exemple :**
```json
// Après ResultPath, on a :
{
  "clientId": "123",
  "nom": "Dupont",
  "validation": {"isValid": true, "score": 95}
}

// Avec OutputPath: "$.validation.isValid"
{
  "OutputPath": "$.validation.isValid"
}

// L'état suivant reçoit :
true
```

**Valeurs spéciales :**
- `"$"` : Passer tout l'output (défaut)
- `null` : Passer un objet vide `{}`

---

### 🔄 Ordre d'exécution des transformations

```
1. InputPath       → Filtrer l'input
2. Parameters      → Transformer l'input
3. [État exécuté]  → Lambda, Task, etc.
4. ResultPath      → Stocker le résultat
5. OutputPath      → Filtrer l'output
6. → État suivant
```

---

## 🛡️ Gestion d'erreurs

### Retry - Réessayer automatiquement

```json
{
  "Retry": [
    {
      "ErrorEquals": ["States.Timeout"],
      "IntervalSeconds": 2,
      "MaxAttempts": 3,
      "BackoffRate": 2.0
    },
    {
      "ErrorEquals": ["CustomError.Temporary"],
      "IntervalSeconds": 5,
      "MaxAttempts": 2,
      "BackoffRate": 1.5
    },
    {
      "ErrorEquals": ["States.ALL"],
      "IntervalSeconds": 10,
      "MaxAttempts": 1
    }
  ]
}
```

**Paramètres :**
- `ErrorEquals` : Liste des codes d'erreur à attraper
- `IntervalSeconds` : Délai avant le 1er retry (en secondes)
- `MaxAttempts` : Nombre max de tentatives
- `BackoffRate` : Facteur multiplicatif du délai (exponentiel)

**Codes d'erreur prédéfinis :**
- `States.ALL` : Toutes les erreurs
- `States.Timeout` : Timeout dépassé
- `States.TaskFailed` : Tâche échouée
- `States.Permissions` : Erreur de permissions IAM
- `States.ResultPathMatchFailure` : ResultPath invalide
- `States.ParameterPathFailure` : Parameters invalide
- `States.BranchFailed` : Une branche Parallel a échoué
- `States.NoChoiceMatched` : Aucun Choice ne match

**Calcul du délai entre tentatives :**
```
Tentative 1 → Échec → Attendre IntervalSeconds
Tentative 2 → Échec → Attendre IntervalSeconds × BackoffRate
Tentative 3 → Échec → Attendre IntervalSeconds × BackoffRate²
...
```

**Exemple :** `IntervalSeconds: 2, BackoffRate: 2.0`
- Essai 1 → Échec → Attendre **2 secondes**
- Essai 2 → Échec → Attendre **4 secondes** (2 × 2)
- Essai 3 → Échec → Attendre **8 secondes** (2 × 2²)

---

### Catch - Gérer les erreurs après retry

```json
{
  "Catch": [
    {
      "ErrorEquals": ["ValidationError"],
      "ResultPath": "$.error",
      "Next": "HumanReview"
    },
    {
      "ErrorEquals": ["States.Timeout"],
      "ResultPath": "$.error",
      "Next": "NotifyTimeout"
    },
    {
      "ErrorEquals": ["States.ALL"],
      "ResultPath": "$.error",
      "Next": "GenericErrorHandler"
    }
  ]
}
```

**Paramètres :**
- `ErrorEquals` : Liste des codes d'erreur à attraper
- `ResultPath` : Où stocker les détails de l'erreur
- `Next` : État suivant en cas d'erreur

**Structure de l'erreur stockée :**
```json
{
  "error": {
    "Error": "ValidationError",
    "Cause": "Invalid postal code format"
  }
}
```

---

### Ordre d'exécution : Retry → Catch

```
1. État exécuté → Erreur
2. Chercher dans Retry (dans l'ordre) → Si match :
   - Essayer MaxAttempts fois
   - Si une tentative réussit → Continuer normalement
   - Si toutes échouent → Passer au Catch
3. Chercher dans Catch (dans l'ordre) → Si match :
   - Exécuter l'état spécifié dans "Next"
4. Si aucun Catch ne match → Workflow échoue
```

---

## 📊 Exemples complets

### Exemple 1 : Validation simple avec retry et catch

```json
{
  "Comment": "Valider une adresse avec gestion d'erreur complète",
  "StartAt": "ValidateAddress",
  "States": {
    "ValidateAddress": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:ca-central-1:123:function:validate-address",
      "Comment": "Valide le format de l'adresse",
      "TimeoutSeconds": 30,
      "ResultPath": "$.validationResult",
      "Retry": [
        {
          "ErrorEquals": ["States.Timeout"],
          "IntervalSeconds": 2,
          "MaxAttempts": 3,
          "BackoffRate": 2.0
        },
        {
          "ErrorEquals": ["States.TaskFailed"],
          "IntervalSeconds": 1,
          "MaxAttempts": 2,
          "BackoffRate": 1.5
        }
      ],
      "Catch": [
        {
          "ErrorEquals": ["ValidationError"],
          "ResultPath": "$.error",
          "Next": "ValidationFailed"
        },
        {
          "ErrorEquals": ["States.ALL"],
          "ResultPath": "$.error",
          "Next": "GenericError"
        }
      ],
      "Next": "CheckValidationResult"
    },
    "CheckValidationResult": {
      "Type": "Choice",
      "Choices": [
        {
          "Variable": "$.validationResult.isValid",
          "BooleanEquals": true,
          "Next": "Success"
        }
      ],
      "Default": "ValidationFailed"
    },
    "ValidationFailed": {
      "Type": "Fail",
      "Error": "ValidationError",
      "Cause": "L'adresse fournie est invalide"
    },
    "GenericError": {
      "Type": "Fail",
      "Error": "UnexpectedError",
      "Cause": "Une erreur inattendue s'est produite"
    },
    "Success": {
      "Type": "Succeed"
    }
  }
}
```

---

### Exemple 2 : Workflow avec traitement parallèle et agrégation

```json
{
  "Comment": "Valide client avec vérifications parallèles",
  "StartAt": "ParallelValidations",
  "States": {
    "ParallelValidations": {
      "Type": "Parallel",
      "Comment": "Exécute validations adresse, email, téléphone en parallèle",
      "Branches": [
        {
          "StartAt": "ValidateAddress",
          "States": {
            "ValidateAddress": {
              "Type": "Task",
              "Resource": "arn:aws:lambda:ca-central-1:123:function:validate-address",
              "Parameters": {
                "address.$": "$.address"
              },
              "End": true
            }
          }
        },
        {
          "StartAt": "ValidateEmail",
          "States": {
            "ValidateEmail": {
              "Type": "Task",
              "Resource": "arn:aws:lambda:ca-central-1:123:function:validate-email",
              "Parameters": {
                "email.$": "$.email"
              },
              "End": true
            }
          }
        },
        {
          "StartAt": "ValidatePhone",
          "States": {
            "ValidatePhone": {
              "Type": "Task",
              "Resource": "arn:aws:lambda:ca-central-1:123:function:validate-phone",
              "Parameters": {
                "phone.$": "$.phone"
              },
              "End": true
            }
          }
        }
      ],
      "ResultPath": "$.validations",
      "Retry": [
        {
          "ErrorEquals": ["States.TaskFailed"],
          "MaxAttempts": 2
        }
      ],
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "ResultPath": "$.error",
          "Next": "HandleError"
        }
      ],
      "Next": "AggregateResults"
    },
    "AggregateResults": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:ca-central-1:123:function:aggregate-validations",
      "Comment": "Agrège les résultats de validation",
      "InputPath": "$.validations",
      "ResultPath": "$.aggregatedResult",
      "Next": "CheckAllValid"
    },
    "CheckAllValid": {
      "Type": "Choice",
      "Choices": [
        {
          "Variable": "$.aggregatedResult.allValid",
          "BooleanEquals": true,
          "Next": "SaveClient"
        }
      ],
      "Default": "HumanReview"
    },
    "SaveClient": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:ca-central-1:123:function:save-client",
      "End": true
    },
    "HumanReview": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:ca-central-1:123:function:send-for-review",
      "End": true
    },
    "HandleError": {
      "Type": "Fail",
      "Error": "ValidationProcessError",
      "Cause": "Une erreur s'est produite durant le processus de validation"
    }
  }
}
```

---

### Exemple 3 : Map avec traitement par lots

```json
{
  "Comment": "Traite plusieurs clients en parallèle avec Map",
  "StartAt": "ProcessAllClients",
  "States": {
    "ProcessAllClients": {
      "Type": "Map",
      "Comment": "Traite chaque client du tableau",
      "ItemsPath": "$.clients",
      "MaxConcurrency": 10,
      "Parameters": {
        "client.$": "$$.Map.Item.Value",
        "index.$": "$$.Map.Item.Index",
        "executionId.$": "$$.Execution.Id",
        "metadata.$": "$.metadata"
      },
      "Iterator": {
        "StartAt": "EnrichClient",
        "States": {
          "EnrichClient": {
            "Type": "Pass",
            "Parameters": {
              "clientData.$": "$.client",
              "processedAt.$": "$$.State.EnteredTime",
              "batchMetadata.$": "$.metadata"
            },
            "Next": "ValidateClient"
          },
          "ValidateClient": {
            "Type": "Task",
            "Resource": "arn:aws:lambda:ca-central-1:123:function:validate-client",
            "ResultPath": "$.validation",
            "Retry": [
              {
                "ErrorEquals": ["States.TaskFailed"],
                "MaxAttempts": 2
              }
            ],
            "Catch": [
              {
                "ErrorEquals": ["States.ALL"],
                "ResultPath": "$.error",
                "Next": "MarkFailed"
              }
            ],
            "Next": "CheckValidation"
          },
          "CheckValidation": {
            "Type": "Choice",
            "Choices": [
              {
                "Variable": "$.validation.isValid",
                "BooleanEquals": true,
                "Next": "SaveClient"
              }
            ],
            "Default": "MarkInvalid"
          },
          "SaveClient": {
            "Type": "Task",
            "Resource": "arn:aws:lambda:ca-central-1:123:function:save-client",
            "ResultPath": "$.saveResult",
            "Next": "MarkSuccess"
          },
          "MarkSuccess": {
            "Type": "Pass",
            "Result": {"status": "SUCCESS"},
            "ResultPath": "$.finalStatus",
            "End": true
          },
          "MarkInvalid": {
            "Type": "Pass",
            "Result": {"status": "INVALID"},
            "ResultPath": "$.finalStatus",
            "End": true
          },
          "MarkFailed": {
            "Type": "Pass",
            "Result": {"status": "FAILED"},
            "ResultPath": "$.finalStatus",
            "End": true
          }
        }
      },
      "ResultPath": "$.processedClients",
      "Next": "GenerateReport"
    },
    "GenerateReport": {
      "Type": "Task",
      "Resource": "arn:aws:lambda:ca-central-1:123:function:generate-report",
      "Parameters": {
        "results.$": "$.processedClients",
        "totalClients.$": "$.metadata.totalCount",
        "executionId.$": "$$.Execution.Id"
      },
      "End": true
    }
  }
}
```

---

## 📝 Résumé : Syntaxe minimale par type d'état

### Task
```json
{
  "MonTask": {
    "Type": "Task",
    "Resource": "arn:aws:lambda:...",
    "Next": "EtatSuivant"
  }
}
```

### Choice
```json
{
  "MonChoice": {
    "Type": "Choice",
    "Choices": [
      {"Variable": "$.valeur", "NumericGreaterThan": 10, "Next": "Grand"}
    ],
    "Default": "Petit"
  }
}
```

### Parallel
```json
{
  "MonParallel": {
    "Type": "Parallel",
    "Branches": [
      {"StartAt": "Tache1", "States": {...}},
      {"StartAt": "Tache2", "States": {...}}
    ],
    "Next": "EtatSuivant"
  }
}
```

### Wait
```json
{
  "MonWait": {
    "Type": "Wait",
    "Seconds": 60,
    "Next": "EtatSuivant"
  }
}
```

### Pass
```json
{
  "MonPass": {
    "Type": "Pass",
    "Result": {"statique": "valeur"},
    "Next": "EtatSuivant"
  }
}
```

### Succeed
```json
{
  "MonSucces": {
    "Type": "Succeed"
  }
}
```

### Fail
```json
{
  "MonEchec": {
    "Type": "Fail",
    "Error": "CodeErreur",
    "Cause": "Description de l'erreur"
  }
}
```

### Map
```json
{
  "MonMap": {
    "Type": "Map",
    "ItemsPath": "$.tableau",
    "Iterator": {
      "StartAt": "Traiter",
      "States": {...}
    },
    "Next": "EtatSuivant"
  }
}
```

---

**Dernière mise à jour** : 2026-09-24
**Auteur** : Claude Code