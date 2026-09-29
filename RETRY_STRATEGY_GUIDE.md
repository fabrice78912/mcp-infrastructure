# Guide de Stratégie de Retry - Workflow Phone Update

## 📋 Vue d'ensemble

Ce guide détaille **où, quand et comment** implémenter les mécanismes de retry dans le workflow de mise à jour de téléphone.

**Principe clé :** Les retry doivent être implémentés à **3 niveaux** pour maximiser la résilience.

---

## 🎯 Les 3 Niveaux de Retry

```
┌─────────────────────────────────────────────────────────┐
│                    Niveau 1: Step Functions             │
│  (Retry pour erreurs Lambda, timeouts, throttling)      │
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │              Niveau 2: Lambda Code                 │ │
│  │  (Retry pour appels AWS SDK, API externes)        │ │
│  │                                                    │ │
│  │  ┌──────────────────────────────────────────────┐ │ │
│  │  │        Niveau 3: HTTP Clients               │ │ │
│  │  │  (Retry pour appels HTTP, timeouts réseau) │ │ │
│  │  └──────────────────────────────────────────────┘ │ │
│  └────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

---

## 📊 Matrice de Retry par Étape du Workflow

| Étape | Retry Step Functions | Retry Lambda | Retry HTTP Client | Raison |
|-------|---------------------|--------------|-------------------|---------|
| **1. ReadClientProfile** | ✅ Oui | ✅ Oui | ❌ Non | DynamoDB peut throttle |
| **2. PhoneValidator** | ❌ Non | ❌ Non | ❌ Non | Validation pure (déterministe) |
| **3. CheckPhoneHistory** | ✅ Oui | ✅ Oui | ❌ Non | DynamoDB peut throttle |
| **4. HumanApproval** | ❌ Non | ❌ Non | ❌ Non | Attente événement externe |
| **5. SendOTPSMS** | ✅ Oui | ✅ Oui | ❌ Non | SNS peut échouer temporairement |
| **6. CheckOTPStatus** | ❌ Non | ✅ Oui | ❌ Non | DynamoDB read (polling) |
| **7. UpdateMDMAE** | ✅ Oui | ✅ Oui | ✅ Oui | API externe critique |
| **8. UpdateFCC** | ✅ Oui | ✅ Oui | ✅ Oui | API externe (parallèle) |
| **9. UpdateCRM** | ✅ Oui | ✅ Oui | ✅ Oui | API externe (parallèle) |
| **10. SendNotification** | ✅ Oui | ✅ Oui | ❌ Non | SNS/SQS peut échouer |

---

## 🔧 Niveau 1 : Retry Step Functions

### Où l'implémenter ?
Dans le fichier **Terraform** : `modules/step-functions/state_machine.tf`

### Pourquoi ?
Step Functions peut automatiquement retry les Lambdas qui échouent à cause de :
- **Throttling** (TooManyRequestsException)
- **Timeout** Lambda
- **Erreurs transitoires** (500, 503)
- **Erreurs réseau**

### Configuration par étape

#### ✅ Étapes AVEC retry

```hcl
# Exemple: ReadClientProfile
{
  "Type": "Task",
  "Resource": "${read_client_profile_arn}",
  "Retry": [
    {
      "ErrorEquals": [
        "States.TaskFailed",
        "DynamoDb.ProvisionedThroughputExceededException",
        "DynamoDb.ThrottlingException"
      ],
      "IntervalSeconds": 2,
      "MaxAttempts": 3,
      "BackoffRate": 2.0
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
      "Next": "NotifyFailure"
    }
  ]
}
```

**Explication :**
- **IntervalSeconds: 2** → Attendre 2 secondes avant le 1er retry
- **MaxAttempts: 3** → Maximum 3 tentatives
- **BackoffRate: 2.0** → Doubler le délai à chaque retry (2s → 4s → 8s)

#### ❌ Étapes SANS retry

```hcl
# Exemple: PhoneValidator (validation déterministe)
{
  "Type": "Task",
  "Resource": "${phone_validator_arn}",
  "Retry": [],  # PAS de retry pour validation pure
  "Catch": [
    {
      "ErrorEquals": ["ValidationException"],
      "ResultPath": "$.error",
      "Next": "HandleValidationError"
    }
  ]
}
```

### Configuration détaillée par type d'étape

#### 1. Lectures DynamoDB (ReadClientProfile, CheckPhoneHistory)

```json
"Retry": [
  {
    "ErrorEquals": [
      "DynamoDb.ProvisionedThroughputExceededException",
      "DynamoDb.ThrottlingException",
      "States.TaskFailed"
    ],
    "IntervalSeconds": 2,
    "MaxAttempts": 3,
    "BackoffRate": 2.0
  },
  {
    "ErrorEquals": ["States.Timeout"],
    "IntervalSeconds": 1,
    "MaxAttempts": 2,
    "BackoffRate": 1.5
  }
]
```

**Pourquoi ?**
- DynamoDB peut throttle sous forte charge
- Lectures idempotentes (safe to retry)

#### 2. Envoi SMS (SendOTPSMS)

```json
"Retry": [
  {
    "ErrorEquals": [
      "SNS.ThrottlingException",
      "States.TaskFailed"
    ],
    "IntervalSeconds": 3,
    "MaxAttempts": 2,
    "BackoffRate": 2.0
  }
]
```

**Pourquoi ?**
- SNS peut throttle
- Limité à 2 tentatives pour éviter d'envoyer plusieurs SMS au client

#### 3. Appels API externes (UpdateMDMAE, UpdateFCC, UpdateCRM)

```json
"Retry": [
  {
    "ErrorEquals": [
      "States.TaskFailed",
      "ApiException",
      "TimeoutException",
      "HttpClientException"
    ],
    "IntervalSeconds": 5,
    "MaxAttempts": 3,
    "BackoffRate": 2.0
  },
  {
    "ErrorEquals": ["States.Timeout"],
    "IntervalSeconds": 3,
    "MaxAttempts": 2,
    "BackoffRate": 2.0
  }
]
```

**Pourquoi ?**
- APIs externes peuvent être temporairement indisponibles (503, timeout)
- Délais plus longs (5s) pour laisser l'API récupérer
- MaxAttempts=3 car ces appels sont critiques

#### 4. Validations (PhoneValidator)

```json
"Retry": []  # PAS de retry
```

**Pourquoi ?**
- Opération déterministe (même input = même output)
- Si invalide maintenant, sera invalide après retry
- Économise des invocations Lambda

#### 5. Attente événement (HumanApproval, WaitForOTP)

```json
"Retry": []  # PAS de retry automatique
```

**Pourquoi ?**
- Ce sont des états d'attente (Wait, Task avec callback)
- Le retry est géré par le workflow lui-même (polling, timeout)

---

## 🔄 Niveau 2 : Retry dans le Code Lambda

### Où l'implémenter ?
Dans le **code Java** des clients AWS SDK et services.

### Pourquoi ?
Certaines erreurs surviennent au niveau de l'appel SDK/API, avant même que Step Functions ne détecte une erreur.

### Exemple 1 : DynamoDBClient avec retry

```java
package com.bnc.mcp.clients;

import software.amazon.awssdk.core.retry.RetryPolicy;
import software.amazon.awssdk.core.retry.backoff.BackoffStrategy;
import software.amazon.awssdk.core.retry.conditions.RetryCondition;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;

import java.time.Duration;

public class DynamoDBClient {
    private final DynamoDbClient dynamoDb;

    public DynamoDBClient() {
        // Configuration retry au niveau SDK
        RetryPolicy retryPolicy = RetryPolicy.builder()
                .numRetries(3)
                .backoffStrategy(BackoffStrategy.defaultThrottlingStrategy())
                .throttlingBackoffStrategy(BackoffStrategy.exponentialDelay(
                    Duration.ofMillis(500),  // Base delay
                    Duration.ofSeconds(20)   // Max delay
                ))
                .build();

        this.dynamoDb = DynamoDbClient.builder()
                .overrideConfiguration(config -> config.retryPolicy(retryPolicy))
                .build();
    }

    public PhoneHistoryCheck getPhoneHistory(String clientId) {
        logger.info("Fetching phone history for client: {}", clientId);

        // Le SDK AWS gérera automatiquement les retry pour:
        // - ProvisionedThroughputExceededException
        // - ThrottlingException
        // - Erreurs réseau transitoires (500, 503)

        try {
            QueryResponse response = dynamoDb.query(request);
            // ... traitement

        } catch (Exception e) {
            // Si tous les retry SDK échouent, propager l'erreur
            logger.error("Failed after retries: {}", e.getMessage());
            throw new RuntimeException("Failed to fetch phone history after retries", e);
        }
    }
}
```

**Pourquoi cette approche ?**
- Le SDK AWS a des retry intelligents built-in
- Gère automatiquement throttling, erreurs 5xx, timeouts réseau
- Exponential backoff optimisé pour AWS

### Exemple 2 : MDMAEClient avec retry manuel

```java
package com.bnc.mcp.clients;

import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;

public class MDMAEClient {
    private final HttpClient httpClient;
    private static final int MAX_RETRIES = 3;
    private static final long BASE_DELAY_MS = 1000;

    public MDMAEClient() {
        this.httpClient = HttpClient.newBuilder()
                .connectTimeout(Duration.ofSeconds(10))
                .build();
    }

    public Map<String, Object> updatePhone(MDMAEPhoneUpdateRequest request) {
        logger.info("Updating phone in MDMAE for client: {}", request.getClientId());

        int attempt = 0;
        Exception lastException = null;

        while (attempt < MAX_RETRIES) {
            try {
                HttpResponse<String> response = httpClient.send(httpRequest,
                    HttpResponse.BodyHandlers.ofString());

                // Succès (2xx)
                if (response.statusCode() >= 200 && response.statusCode() < 300) {
                    logger.info("MDMAE update successful on attempt {}", attempt + 1);
                    return buildSuccessResponse(response);
                }

                // Erreur client (4xx) - NE PAS RETRY
                if (response.statusCode() >= 400 && response.statusCode() < 500) {
                    logger.error("Client error {}: no retry", response.statusCode());
                    return buildErrorResponse("Client error: " + response.statusCode());
                }

                // Erreur serveur (5xx) - RETRY
                if (response.statusCode() >= 500) {
                    logger.warn("Server error {} on attempt {}, retrying...",
                        response.statusCode(), attempt + 1);
                    attempt++;
                    if (attempt < MAX_RETRIES) {
                        waitBeforeRetry(attempt);
                    }
                    continue;
                }

            } catch (java.net.http.HttpTimeoutException e) {
                // Timeout - RETRY
                logger.warn("Timeout on attempt {}, retrying...", attempt + 1);
                lastException = e;
                attempt++;
                if (attempt < MAX_RETRIES) {
                    waitBeforeRetry(attempt);
                }

            } catch (java.net.ConnectException e) {
                // Connection refused - RETRY
                logger.warn("Connection error on attempt {}, retrying...", attempt + 1);
                lastException = e;
                attempt++;
                if (attempt < MAX_RETRIES) {
                    waitBeforeRetry(attempt);
                }

            } catch (Exception e) {
                // Autre erreur - NE PAS RETRY
                logger.error("Unexpected error: {}", e.getMessage());
                return buildErrorResponse("Unexpected error: " + e.getMessage());
            }
        }

        // Tous les retry ont échoué
        logger.error("All {} retry attempts failed", MAX_RETRIES);
        throw new RuntimeException("Failed to update MDMAE after " + MAX_RETRIES +
            " attempts", lastException);
    }

    /**
     * Exponential backoff avec jitter
     */
    private void waitBeforeRetry(int attemptNumber) {
        try {
            // Exponential: 1s → 2s → 4s
            long delay = BASE_DELAY_MS * (long) Math.pow(2, attemptNumber - 1);

            // Ajouter jitter (±25%) pour éviter thundering herd
            long jitter = (long) (delay * 0.25 * Math.random());
            long totalDelay = delay + jitter;

            logger.info("Waiting {}ms before retry attempt {}", totalDelay, attemptNumber + 1);
            Thread.sleep(totalDelay);

        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new RuntimeException("Retry interrupted", e);
        }
    }
}
```

**Pourquoi cette approche ?**
- **Retry seulement pour erreurs transitoires** : 5xx, timeout, connection error
- **PAS de retry pour 4xx** : ce sont des erreurs client (bad request, unauthorized)
- **Exponential backoff avec jitter** : évite thundering herd
- **Logging détaillé** : facilite le debugging

### Exemple 3 : SNSClient avec retry SDK

```java
package com.bnc.mcp.clients;

import software.amazon.awssdk.core.retry.RetryPolicy;
import software.amazon.awssdk.services.sns.SnsClient;
import software.amazon.awssdk.services.sns.model.PublishRequest;
import software.amazon.awssdk.services.sns.model.PublishResponse;

public class SNSClient {
    private final SnsClient snsClient;

    public SNSClient() {
        RetryPolicy retryPolicy = RetryPolicy.builder()
                .numRetries(2)  // Limité à 2 pour éviter d'envoyer plusieurs SMS
                .build();

        this.snsClient = SnsClient.builder()
                .overrideConfiguration(config -> config.retryPolicy(retryPolicy))
                .build();
    }

    public String sendOTPSMS(String phoneNumber, String otpCode) {
        logger.info("Sending OTP SMS to: {}", phoneNumber);

        try {
            PublishRequest request = PublishRequest.builder()
                    .phoneNumber(phoneNumber)
                    .message(String.format(
                        "Votre code de vérification BNC est: %s. Ce code expire dans 5 minutes.",
                        otpCode
                    ))
                    .build();

            // SDK retry automatique pour throttling
            PublishResponse response = snsClient.publish(request);

            logger.info("OTP SMS sent successfully. MessageId: {}", response.messageId());
            return response.messageId();

        } catch (Exception e) {
            logger.error("Failed to send OTP SMS after retries: {}", e.getMessage());
            throw new RuntimeException("Failed to send OTP SMS", e);
        }
    }
}
```

**Pourquoi numRetries=2 ?**
- Éviter d'envoyer plusieurs SMS au client
- SNS est généralement fiable, 2 retry suffisent

---

## 🌐 Niveau 3 : Retry HTTP Client

### Configuration Java HttpClient

```java
import java.net.http.HttpClient;
import java.time.Duration;

public class BaseHttpClient {

    protected HttpClient createHttpClient() {
        return HttpClient.newBuilder()
                // Timeout connexion
                .connectTimeout(Duration.ofSeconds(10))

                // Suivre les redirects
                .followRedirects(HttpClient.Redirect.NORMAL)

                // HTTP/2 avec fallback HTTP/1.1
                .version(HttpClient.Version.HTTP_2)

                .build();
    }

    protected HttpRequest createRequest(String uri, String jsonBody) {
        return HttpRequest.newBuilder()
                .uri(URI.create(uri))
                .header("Content-Type", "application/json")
                .header("User-Agent", "MCP-PhoneUpdate/1.0")

                // Timeout pour la requête complète
                .timeout(Duration.ofSeconds(30))

                .PUT(HttpRequest.BodyPublishers.ofString(jsonBody))
                .build();
    }
}
```

---

## 📋 Règles de Décision : Quand faire un Retry ?

### ✅ FAIRE un retry si :

| Condition | Exemple | Action |
|-----------|---------|--------|
| Erreur 5xx | 500, 503, 504 | Retry avec backoff |
| Timeout réseau | ConnectTimeout, ReadTimeout | Retry avec backoff |
| Throttling | 429 Too Many Requests | Retry avec backoff exponentiel |
| Connection refused | ConnectException | Retry (service peut redémarrer) |
| Erreur transitoire DynamoDB | ProvisionedThroughputExceeded | Retry avec backoff |
| Erreur transitoire SNS | ThrottlingException | Retry (max 2 fois) |

### ❌ NE PAS faire de retry si :

| Condition | Exemple | Action |
|-----------|---------|--------|
| Erreur 4xx client | 400, 401, 403, 404 | Fail fast, logger l'erreur |
| Validation échouée | Format téléphone invalide | Fail fast, retourner erreur |
| Données introuvables | Client not found | Fail fast |
| Business rule violation | Trop de changements (fraude) | Passer à HumanApproval |
| Erreur de logique | NullPointerException | Fail fast, fix le bug |
| Ressource épuisée | OutOfMemoryError | Fail fast |

---

## 🎯 Stratégie de Backoff

### Exponential Backoff

```
Attempt 1: Immédiat
Attempt 2: Attendre 2s
Attempt 3: Attendre 4s
Attempt 4: Attendre 8s
```

**Formule :** `delay = base_delay * 2^(attempt - 1)`

### Exponential Backoff avec Jitter

```
Attempt 1: Immédiat
Attempt 2: Attendre 2s ± 0.5s → [1.5s - 2.5s]
Attempt 3: Attendre 4s ± 1s   → [3s - 5s]
Attempt 4: Attendre 8s ± 2s   → [6s - 10s]
```

**Pourquoi jitter ?**
- Évite que tous les clients retry en même temps (thundering herd)
- Étale la charge sur le service backend

### Backoff pour Throttling (AWS SDK)

```
Attempt 1: Immédiat
Attempt 2: 500ms
Attempt 3: 1s
Attempt 4: 2s
...
Max: 20s
```

AWS SDK utilise un backoff optimisé pour le throttling.

---

## 🚨 Cas Spécifiques

### 1. SendOTPSMS - Limite de retry à 2

**Problème :** Retry excessif peut envoyer plusieurs SMS au client.

**Solution :**
```json
"Retry": [
  {
    "ErrorEquals": ["SNS.ThrottlingException"],
    "MaxAttempts": 2,  # MAXIMUM 2
    "IntervalSeconds": 3,
    "BackoffRate": 2.0
  }
]
```

### 2. UpdateMDMAE - Idempotence requise

**Problème :** Retry peut créer des doublons si l'API n'est pas idempotente.

**Solution :**
```java
public Map<String, Object> updatePhone(MDMAEPhoneUpdateRequest request) {
    // Générer un requestId idempotent
    String idempotencyKey = request.getClientId() + "-" +
        request.getNewPhoneNumber().hashCode();

    HttpRequest httpRequest = HttpRequest.newBuilder()
            .header("Idempotency-Key", idempotencyKey)  // Header idempotence
            .header("X-Request-ID", request.getRequestId())
            // ...
}
```

### 3. Parallel Updates (FCC, CRM) - Circuit Breaker

**Problème :** Si FCC est down, retry infini bloque le workflow.

**Solution :** Implémenter un circuit breaker pattern.

```java
public class FCCClient {
    private CircuitBreakerState state = CircuitBreakerState.CLOSED;
    private int failureCount = 0;
    private static final int FAILURE_THRESHOLD = 5;
    private Instant lastFailureTime;

    public Map<String, Object> sendPhoneUpdate(String clientId, String newPhone) {
        // Si circuit ouvert, fail fast
        if (state == CircuitBreakerState.OPEN) {
            if (Instant.now().isBefore(lastFailureTime.plusSeconds(60))) {
                logger.warn("Circuit breaker OPEN, skipping FCC call");
                return Map.of("success", false, "reason", "Circuit breaker open");
            } else {
                // Tenter de fermer le circuit après 60s
                state = CircuitBreakerState.HALF_OPEN;
            }
        }

        try {
            // Faire l'appel HTTP
            HttpResponse<String> response = httpClient.send(request, ...);

            if (response.statusCode() >= 200 && response.statusCode() < 300) {
                // Succès - réinitialiser le circuit
                state = CircuitBreakerState.CLOSED;
                failureCount = 0;
                return buildSuccessResponse(response);
            }

        } catch (Exception e) {
            failureCount++;
            if (failureCount >= FAILURE_THRESHOLD) {
                state = CircuitBreakerState.OPEN;
                lastFailureTime = Instant.now();
                logger.error("Circuit breaker OPENED after {} failures", failureCount);
            }
            throw e;
        }
    }

    enum CircuitBreakerState {
        CLOSED,      // Normal, requests passent
        OPEN,        // Échecs répétés, fail fast
        HALF_OPEN    // Test de récupération
    }
}
```

---

## 📊 Configuration Recommandée par Environnement

### DEV

```
MaxAttempts: 2
IntervalSeconds: 1
BackoffRate: 1.5
Timeout Lambda: 30s
```

**Pourquoi ?**
- Feedback rapide pendant le développement
- Logs plus simples à analyser

### QA

```
MaxAttempts: 3
IntervalSeconds: 2
BackoffRate: 2.0
Timeout Lambda: 60s
```

**Pourquoi ?**
- Reproduire les conditions réelles
- Tester la résilience

### PROD

```
MaxAttempts: 3-5
IntervalSeconds: 3-5
BackoffRate: 2.0
Timeout Lambda: 90s
```

**Pourquoi ?**
- Maximiser les chances de succès
- Délais plus longs pour laisser le temps aux services de récupérer

---

## ✅ Checklist d'Implémentation

### Step Functions
- [ ] Configurer retry pour ReadClientProfile (DynamoDB throttling)
- [ ] Configurer retry pour CheckPhoneHistory (DynamoDB throttling)
- [ ] Configurer retry pour SendOTPSMS (SNS throttling, max 2)
- [ ] Configurer retry pour UpdateMDMAE (API externe)
- [ ] Configurer retry pour UpdateFCC (API externe)
- [ ] Configurer retry pour UpdateCRM (API externe)
- [ ] PAS de retry pour PhoneValidator (validation pure)
- [ ] PAS de retry pour HumanApproval (attente événement)

### Code Lambda
- [ ] Configurer RetryPolicy dans DynamoDBClient
- [ ] Configurer RetryPolicy dans SNSClient (max 2)
- [ ] Implémenter retry manuel dans MDMAEClient avec exponential backoff
- [ ] Implémenter retry manuel dans FCCClient avec circuit breaker
- [ ] Implémenter retry manuel dans CRMClient
- [ ] Ajouter jitter dans les backoff
- [ ] Logger tous les retry avec niveau WARN

### Tests
- [ ] Tester retry DynamoDB avec throttling simulé
- [ ] Tester retry SNS avec throttling simulé
- [ ] Tester retry API externe avec timeout simulé
- [ ] Tester circuit breaker avec pannes répétées
- [ ] Vérifier que PhoneValidator ne retry jamais

---

## 🎯 Résumé : Où mettre les Retry ?

```
┌─────────────────────────────────────────────────────────────────┐
│  ÉTAPE                  │ Step Functions │ Lambda │ HTTP Client │
├─────────────────────────────────────────────────────────────────┤
│ 1. ReadClientProfile    │      ✅ (3x)   │  ✅ SDK│      -      │
│ 2. PhoneValidator       │      ❌        │   ❌   │      -      │
│ 3. CheckPhoneHistory    │      ✅ (3x)   │  ✅ SDK│      -      │
│ 4. HumanApproval        │      ❌        │   ❌   │      -      │
│ 5. SendOTPSMS           │      ✅ (2x)   │  ✅ SDK│      -      │
│ 6. CheckOTPStatus       │      ❌        │  ✅ SDK│      -      │
│ 7. UpdateMDMAE          │      ✅ (3x)   │  ✅ (3x│  ✅ (timeout│
│ 8. UpdateFCC            │      ✅ (3x)   │  ✅ (3x│  ✅ (CB)    │
│ 9. UpdateCRM            │      ✅ (3x)   │  ✅ (3x│  ✅ (timeout│
│ 10. SendNotification    │      ✅ (3x)   │  ✅ SDK│      -      │
└─────────────────────────────────────────────────────────────────┘

Légende:
✅ (3x) = Retry avec max 3 tentatives
✅ SDK = Retry géré par AWS SDK
✅ (CB) = Retry avec Circuit Breaker
❌ = Pas de retry
```

---

**Dernière mise à jour :** 2026-09-25
**Version :** 1.0.0
**Auteur :** MCP Infrastructure Team