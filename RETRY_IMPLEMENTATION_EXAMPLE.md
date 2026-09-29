# Exemple Complet : Implémentation Retry pour UpdateMDMAE

## 📋 Vue d'ensemble

Cet exemple montre l'implémentation **complète** des 3 niveaux de retry pour l'étape **UpdateMDMAE** (mise à jour du système Master Data Management).

**Étape du workflow :** UpdateMDMAE (étape 7)

**Pourquoi cette étape est critique ?**
- C'est l'étape de mise à jour **principale** du système
- Si elle échoue, **tout le workflow échoue**
- L'API MDMAE peut être temporairement indisponible
- Nécessite idempotence (éviter les doublons lors des retry)

---

## 🎯 Les 3 Niveaux de Retry - Vue d'ensemble

```
┌──────────────────────────────────────────────────────────────┐
│ Niveau 1: Step Functions State Machine (Terraform)          │
│ → Retry si Lambda timeout, throttle, erreur générale        │
│ → MaxAttempts: 3, IntervalSeconds: 5, BackoffRate: 2.0      │
└──────────────────────────────────────────────────────────────┘
                              ↓
┌──────────────────────────────────────────────────────────────┐
│ Niveau 2: Lambda Handler (Java)                             │
│ → Gère les erreurs business et prépare les données          │
│ → Délègue à MDMAEClient qui gère le retry HTTP              │
└──────────────────────────────────────────────────────────────┘
                              ↓
┌──────────────────────────────────────────────────────────────┐
│ Niveau 3: MDMAEClient (Java)                                │
│ → Retry manuel pour HTTP 5xx, timeout, connection errors    │
│ → Exponential backoff: 1s → 2s → 4s                        │
│ → Idempotence avec Idempotency-Key header                   │
└──────────────────────────────────────────────────────────────┘
```

---

## 🔧 Niveau 1 : Configuration Step Functions

### Fichier : `modules/step-functions/state_machine.tf`

```hcl
# ========================================
# Step Functions State Machine Definition
# ========================================

resource "aws_sfn_state_machine" "phone_update" {
  name     = "${var.environment}-mcp-client-phone-update"
  role_arn = aws_iam_role.step_functions_role.arn

  definition = jsonencode({
    Comment = "Phone Update Workflow with Retry Strategy"
    StartAt = "ReadClientProfile"
    States = {
      # ... autres états ...

      # ========================================
      # ÉTAPE 7: Update MDMAE (CRITIQUE)
      # ========================================
      UpdateMDMAE = {
        Type     = "Task"
        Resource = var.phone_mdmae_client_arn

        # PARAMÈTRES DE TIMEOUT
        TimeoutSeconds = 90  # Timeout total: 90 secondes
        HeartbeatSeconds = 30  # Heartbeat: Lambda doit répondre toutes les 30s

        # CONFIGURATION RETRY - NIVEAU 1
        Retry = [
          # Retry #1: Erreurs AWS Lambda (throttling, timeout)
          {
            ErrorEquals = [
              "Lambda.ServiceException",
              "Lambda.AWSLambdaException",
              "Lambda.SdkClientException",
              "Lambda.TooManyRequestsException",
              "States.TaskFailed"
            ]
            IntervalSeconds = 5      # Attendre 5 secondes avant 1er retry
            MaxAttempts     = 3      # Maximum 3 tentatives
            BackoffRate     = 2.0    # Doubler le délai: 5s → 10s → 20s
            Comment         = "Retry for Lambda execution errors"
          },

          # Retry #2: Timeouts spécifiques
          {
            ErrorEquals = [
              "States.Timeout"
            ]
            IntervalSeconds = 3      # Attendre 3 secondes
            MaxAttempts     = 2      # Maximum 2 tentatives pour timeout
            BackoffRate     = 2.0    # 3s → 6s
            Comment         = "Retry for Lambda timeout"
          },

          # Retry #3: Erreurs HTTP transitoires (propagées par Lambda)
          {
            ErrorEquals = [
              "HttpTimeoutException",
              "HttpServerException",
              "ServiceUnavailableException"
            ]
            IntervalSeconds = 10     # Attendre 10 secondes (API externe)
            MaxAttempts     = 3
            BackoffRate     = 2.0    # 10s → 20s → 40s
            Comment         = "Retry for HTTP/API errors from MDMAE"
          }
        ]

        # GESTION DES ERREURS (Catch)
        Catch = [
          # Erreurs client (4xx) - NE PAS RETRY, fail directement
          {
            ErrorEquals = [
              "ValidationException",
              "BadRequestException",
              "UnauthorizedException",
              "NotFoundException"
            ]
            ResultPath = "$.error"
            Next       = "HandleMDMAEClientError"
          },

          # Toutes autres erreurs après retry épuisé
          {
            ErrorEquals = ["States.ALL"]
            ResultPath  = "$.error"
            Next        = "NotifyMDMAEFailure"
          }
        ]

        # Passer les résultats à l'étape suivante
        ResultPath = "$.mdmaeResult"
        Next       = "ParallelUpdates"
      }

      # État d'erreur pour erreurs client
      HandleMDMAEClientError = {
        Type = "Pass"
        Result = {
          status  = "FAILED"
          reason  = "Client error in MDMAE update (4xx)"
          message = "Invalid request, manual intervention required"
        }
        ResultPath = "$.failureInfo"
        Next       = "NotifyMDMAEFailure"
      }

      # Notification d'échec
      NotifyMDMAEFailure = {
        Type     = "Task"
        Resource = var.notification_failure_arn
        End      = true
      }

      # Suite du workflow si succès
      ParallelUpdates = {
        Type = "Parallel"
        Branches = [
          # ... FCC, CRM, etc.
        ]
        Next = "WorkflowComplete"
      }

      # ... autres états ...
    }
  })

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.step_functions.arn}:*"
    include_execution_data = true
    level                  = "ALL"  # Log tous les retry pour debugging
  }

  tags = {
    Name        = "${var.environment}-phone-update-workflow"
    Environment = var.environment
    CriticalStep = "UpdateMDMAE"  # Tag pour identifier les étapes critiques
  }
}

# CloudWatch Log Group pour Step Functions
resource "aws_cloudwatch_log_group" "step_functions" {
  name              = "/aws/states/${var.environment}-mcp-phone-update"
  retention_in_days = 30  # Garder 30 jours pour analyse des retry

  tags = {
    Name = "${var.environment}-sfn-logs"
  }
}
```

**Explication détaillée :**

1. **TimeoutSeconds: 90**
   - Chaque invocation Lambda a max 90 secondes
   - Inclut le temps de retry HTTP dans le Lambda

2. **Retry Configuration :**
   - **Retry #1** : Erreurs Lambda (throttle, service errors)
     - 5s → 10s → 20s
   - **Retry #2** : Timeout Lambda
     - 3s → 6s
   - **Retry #3** : Erreurs HTTP propagées (5xx, timeout)
     - 10s → 20s → 40s

3. **Catch pour fail fast :**
   - Erreurs 4xx → pas de retry, fail directement
   - Économise du temps et des invocations

---

## 🔄 Niveau 2 : Lambda Handler

### Fichier : `src/main/java/com/bnc/mcp/handlers/PhoneMDMAEClientHandler.java`

```java
package com.bnc.mcp.handlers;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.bnc.mcp.clients.MDMAEClient;
import com.bnc.mcp.models.MDMAEPhoneUpdateRequest;
import com.bnc.mcp.exceptions.ValidationException;
import com.bnc.mcp.exceptions.HttpTimeoutException;
import com.bnc.mcp.exceptions.HttpServerException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.HashMap;
import java.util.Map;

/**
 * Lambda Handler pour la mise à jour MDMAE
 *
 * Responsabilités:
 * - Valider l'input
 * - Créer la requête MDMAE
 * - Déléguer au MDMAEClient (qui gère le retry HTTP)
 * - Propager les exceptions typées pour Step Functions Catch/Retry
 */
public class PhoneMDMAEClientHandler implements RequestHandler<Map<String, Object>, Map<String, Object>> {
    private static final Logger logger = LoggerFactory.getLogger(PhoneMDMAEClientHandler.class);

    private final MDMAEClient mdmaeClient;

    public PhoneMDMAEClientHandler() {
        this.mdmaeClient = new MDMAEClient();
    }

    // Constructor pour tests
    public PhoneMDMAEClientHandler(MDMAEClient mdmaeClient) {
        this.mdmaeClient = mdmaeClient;
    }

    @Override
    public Map<String, Object> handleRequest(Map<String, Object> input, Context context) {
        logger.info("=== MDMAE Phone Update Handler Started ===");
        logger.info("Request ID: {}", context.getRequestId());
        logger.info("Remaining time: {} ms", context.getRemainingTimeInMillis());

        long startTime = System.currentTimeMillis();

        try {
            // ========================================
            // 1. VALIDATION INPUT
            // ========================================
            String clientId = extractString(input, "clientId");
            String newPhone = extractString(input, "phoneNumber");
            String country = extractString(input, "country");

            logger.info("Processing MDMAE update for client: {}, phone: {}", clientId, maskPhone(newPhone));

            // Validation basique
            if (clientId == null || clientId.isEmpty()) {
                logger.error("Validation failed: clientId is missing");
                throw new ValidationException("clientId is required");
            }

            if (newPhone == null || !newPhone.matches("^\\+[1-9]\\d{1,14}$")) {
                logger.error("Validation failed: invalid phone format: {}", newPhone);
                throw new ValidationException("phoneNumber must be in E.164 format");
            }

            // ========================================
            // 2. CRÉER LA REQUÊTE MDMAE
            // ========================================
            MDMAEPhoneUpdateRequest request = new MDMAEPhoneUpdateRequest(
                clientId,
                newPhone,
                country
            );

            // Ajouter metadata pour traçabilité
            request.setRequestId(context.getRequestId());
            request.setUpdatedBy("MCP-PhoneUpdate-Workflow");

            // ========================================
            // 3. APPELER MDMAE CLIENT (avec retry HTTP)
            // ========================================
            logger.info("Calling MDMAE API...");

            Map<String, Object> mdmaeResponse;
            try {
                // Le MDMAEClient gère le retry HTTP en interne
                mdmaeResponse = mdmaeClient.updatePhone(request);

            } catch (java.net.http.HttpTimeoutException e) {
                // Timeout HTTP - propager pour retry Step Functions
                logger.error("HTTP Timeout calling MDMAE API: {}", e.getMessage());
                throw new HttpTimeoutException("MDMAE API timeout after retries", e);

            } catch (java.io.IOException e) {
                // Erreur réseau - propager pour retry Step Functions
                logger.error("Network error calling MDMAE API: {}", e.getMessage());
                throw new HttpServerException("Network error: " + e.getMessage(), e);

            } catch (Exception e) {
                // Autre erreur - logger et propager
                logger.error("Unexpected error calling MDMAE: {}", e.getMessage(), e);
                throw new RuntimeException("Failed to call MDMAE: " + e.getMessage(), e);
            }

            // ========================================
            // 4. VÉRIFIER LA RÉPONSE
            // ========================================
            boolean success = (boolean) mdmaeResponse.getOrDefault("success", false);

            if (!success) {
                String errorMessage = (String) mdmaeResponse.get("message");
                logger.error("MDMAE update failed: {}", errorMessage);

                // Si erreur 4xx (client error), ne pas retry
                if (errorMessage != null && errorMessage.contains("400")) {
                    throw new ValidationException("MDMAE validation error: " + errorMessage);
                }

                // Si erreur 5xx, propager pour retry
                throw new HttpServerException("MDMAE API error: " + errorMessage);
            }

            // ========================================
            // 5. SUCCÈS - PRÉPARER LA RÉPONSE
            // ========================================
            long duration = System.currentTimeMillis() - startTime;

            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("mdmaeId", mdmaeResponse.get("mdmaeId"));
            response.put("transactionId", mdmaeResponse.get("transactionId"));
            response.put("timestamp", System.currentTimeMillis());
            response.put("durationMs", duration);
            response.put("clientId", clientId);
            response.put("newPhone", newPhone);

            logger.info("=== MDMAE Update Successful ===");
            logger.info("MDMAE Transaction ID: {}", response.get("transactionId"));
            logger.info("Duration: {} ms", duration);

            return response;

        } catch (ValidationException e) {
            // Erreur validation - NE PAS RETRY
            logger.error("Validation error: {}", e.getMessage());
            throw e;  // Step Functions Catch va attraper "ValidationException"

        } catch (HttpTimeoutException e) {
            // Timeout HTTP - RETRY via Step Functions
            logger.error("HTTP Timeout: {}", e.getMessage());
            throw e;  // Step Functions Retry va relancer

        } catch (HttpServerException e) {
            // Erreur serveur - RETRY via Step Functions
            logger.error("HTTP Server Error: {}", e.getMessage());
            throw e;  // Step Functions Retry va relancer

        } catch (Exception e) {
            // Erreur générique - RETRY via Step Functions
            logger.error("Unexpected error: {}", e.getMessage(), e);
            throw new RuntimeException("MDMAE update failed: " + e.getMessage(), e);
        }
    }

    /**
     * Helper: Extraire une valeur String de l'input
     */
    private String extractString(Map<String, Object> input, String key) {
        Object value = input.get(key);
        return value != null ? value.toString() : null;
    }

    /**
     * Helper: Masquer les chiffres du téléphone pour les logs
     */
    private String maskPhone(String phone) {
        if (phone == null || phone.length() < 4) {
            return "****";
        }
        return phone.substring(0, 3) + "****" + phone.substring(phone.length() - 2);
    }
}
```

**Points clés :**

1. **Validation stricte** : Fail fast pour erreurs client
2. **Exceptions typées** : Permet à Step Functions de différencier les erreurs
3. **Logging détaillé** : Facilite le debugging des retry
4. **Traçabilité** : Request ID pour suivre chaque tentative

---

## 🌐 Niveau 3 : MDMAEClient avec Retry HTTP

### Fichier : `src/main/java/com/bnc/mcp/clients/MDMAEClient.java`

```java
package com.bnc.mcp.clients;

import com.bnc.mcp.models.MDMAEPhoneUpdateRequest;
import com.google.gson.Gson;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

/**
 * Client pour l'API MDMAE avec retry automatique
 *
 * Stratégie de retry:
 * - Max 3 tentatives
 * - Exponential backoff: 1s → 2s → 4s
 * - Jitter pour éviter thundering herd
 * - Retry seulement pour: 5xx, timeout, connection errors
 * - Idempotence avec Idempotency-Key header
 */
public class MDMAEClient {
    private static final Logger logger = LoggerFactory.getLogger(MDMAEClient.class);

    // Configuration retry
    private static final int MAX_RETRIES = 3;
    private static final long BASE_DELAY_MS = 1000;  // 1 seconde
    private static final double JITTER_FACTOR = 0.25;  // ±25%

    private final HttpClient httpClient;
    private final String mdmaeEndpoint;
    private final Gson gson;

    public MDMAEClient() {
        this.httpClient = createHttpClient();
        this.mdmaeEndpoint = System.getenv("MDMAE_API_ENDPOINT");
        this.gson = new Gson();

        logger.info("MDMAEClient initialized with endpoint: {}", mdmaeEndpoint);
    }

    // Constructor pour tests (injection de dépendances)
    public MDMAEClient(HttpClient httpClient, String mdmaeEndpoint) {
        this.httpClient = httpClient;
        this.mdmaeEndpoint = mdmaeEndpoint;
        this.gson = new Gson();
    }

    /**
     * Créer le HttpClient avec configuration optimale
     */
    private HttpClient createHttpClient() {
        return HttpClient.newBuilder()
                // Timeout connexion: 10 secondes
                .connectTimeout(Duration.ofSeconds(10))

                // Suivre les redirects HTTP (301, 302)
                .followRedirects(HttpClient.Redirect.NORMAL)

                // HTTP/2 avec fallback HTTP/1.1
                .version(HttpClient.Version.HTTP_2)

                .build();
    }

    /**
     * Met à jour le numéro de téléphone dans MDMAE
     *
     * Retry automatique pour:
     * - HTTP 5xx (500, 503, 504)
     * - Timeout (ConnectTimeout, ReadTimeout)
     * - Connection errors
     *
     * NO retry pour:
     * - HTTP 4xx (400, 401, 403, 404)
     * - Parsing errors
     */
    public Map<String, Object> updatePhone(MDMAEPhoneUpdateRequest request) {
        logger.info("=== MDMAE updatePhone called ===");
        logger.info("Client ID: {}", request.getClientId());

        // Générer Idempotency Key (pour éviter doublons lors retry)
        String idempotencyKey = generateIdempotencyKey(request);
        logger.info("Idempotency Key: {}", idempotencyKey);

        int attempt = 0;
        Exception lastException = null;

        // ========================================
        // BOUCLE DE RETRY
        // ========================================
        while (attempt < MAX_RETRIES) {
            attempt++;
            logger.info("--- Attempt {} of {} ---", attempt, MAX_RETRIES);

            try {
                // Créer la requête HTTP
                String jsonBody = gson.toJson(request);

                HttpRequest httpRequest = HttpRequest.newBuilder()
                        .uri(URI.create(mdmaeEndpoint + "/clients/" + request.getClientId() + "/phone"))
                        .header("Content-Type", "application/json")
                        .header("Accept", "application/json")

                        // HEADERS POUR IDEMPOTENCE
                        .header("Idempotency-Key", idempotencyKey)
                        .header("X-Request-ID", request.getRequestId())

                        // Headers metadata
                        .header("User-Agent", "MCP-PhoneUpdate/1.0")
                        .header("X-Client-ID", request.getClientId())

                        // Timeout pour cette requête: 30 secondes
                        .timeout(Duration.ofSeconds(30))

                        .PUT(HttpRequest.BodyPublishers.ofString(jsonBody))
                        .build();

                logger.debug("HTTP Request: PUT {}", httpRequest.uri());
                logger.debug("Request body: {}", jsonBody);

                // ========================================
                // ENVOYER LA REQUÊTE HTTP
                // ========================================
                long requestStart = System.currentTimeMillis();

                HttpResponse<String> response = httpClient.send(
                    httpRequest,
                    HttpResponse.BodyHandlers.ofString()
                );

                long requestDuration = System.currentTimeMillis() - requestStart;

                logger.info("HTTP Response: {} (duration: {} ms)",
                    response.statusCode(), requestDuration);

                // ========================================
                // ANALYSER LA RÉPONSE
                // ========================================

                // SUCCÈS (2xx)
                if (response.statusCode() >= 200 && response.statusCode() < 300) {
                    logger.info("✅ MDMAE update successful on attempt {}", attempt);
                    logger.debug("Response body: {}", response.body());

                    return buildSuccessResponse(response, request, attempt, requestDuration);
                }

                // ERREUR CLIENT (4xx) - NE PAS RETRY
                if (response.statusCode() >= 400 && response.statusCode() < 500) {
                    logger.error("❌ Client error {}: {}", response.statusCode(), response.body());
                    logger.error("NO RETRY for 4xx errors");

                    return buildClientErrorResponse(response, request);
                }

                // ERREUR SERVEUR (5xx) - RETRY
                if (response.statusCode() >= 500) {
                    logger.warn("⚠️ Server error {} on attempt {}", response.statusCode(), attempt);

                    if (attempt < MAX_RETRIES) {
                        logger.info("Will retry after backoff...");
                        waitBeforeRetry(attempt);
                        continue;  // Retry
                    } else {
                        logger.error("❌ All {} retry attempts failed with 5xx", MAX_RETRIES);
                        return buildServerErrorResponse(response, request, attempt);
                    }
                }

            } catch (java.net.http.HttpTimeoutException e) {
                // TIMEOUT - RETRY
                logger.warn("⚠️ HTTP Timeout on attempt {}: {}", attempt, e.getMessage());
                lastException = e;

                if (attempt < MAX_RETRIES) {
                    logger.info("Will retry after backoff...");
                    waitBeforeRetry(attempt);
                    continue;  // Retry
                }

            } catch (java.net.ConnectException e) {
                // CONNECTION REFUSED - RETRY
                logger.warn("⚠️ Connection refused on attempt {}: {}", attempt, e.getMessage());
                lastException = e;

                if (attempt < MAX_RETRIES) {
                    logger.info("Will retry after backoff...");
                    waitBeforeRetry(attempt);
                    continue;  // Retry
                }

            } catch (java.io.IOException e) {
                // ERREUR I/O (network, etc.) - RETRY
                logger.warn("⚠️ I/O error on attempt {}: {}", attempt, e.getMessage());
                lastException = e;

                if (attempt < MAX_RETRIES) {
                    logger.info("Will retry after backoff...");
                    waitBeforeRetry(attempt);
                    continue;  // Retry
                }

            } catch (Exception e) {
                // AUTRE ERREUR - NE PAS RETRY
                logger.error("❌ Unexpected error (no retry): {}", e.getMessage(), e);

                Map<String, Object> errorResponse = new HashMap<>();
                errorResponse.put("success", false);
                errorResponse.put("message", "Unexpected error: " + e.getMessage());
                errorResponse.put("errorType", e.getClass().getSimpleName());
                return errorResponse;
            }
        }

        // ========================================
        // TOUS LES RETRY ONT ÉCHOUÉ
        // ========================================
        logger.error("❌ MDMAE update failed after {} attempts", MAX_RETRIES);

        throw new RuntimeException(
            "Failed to update MDMAE after " + MAX_RETRIES + " attempts",
            lastException
        );
    }

    /**
     * Exponential backoff avec jitter
     *
     * Attempt 1: 1s ± 0.25s   → [0.75s - 1.25s]
     * Attempt 2: 2s ± 0.5s    → [1.5s - 2.5s]
     * Attempt 3: 4s ± 1s      → [3s - 5s]
     */
    private void waitBeforeRetry(int attemptNumber) {
        try {
            // Exponential backoff: 1s, 2s, 4s, 8s...
            long baseDelay = BASE_DELAY_MS * (long) Math.pow(2, attemptNumber - 1);

            // Ajouter jitter (±25%) pour éviter thundering herd
            long jitter = (long) (baseDelay * JITTER_FACTOR * (Math.random() - 0.5) * 2);
            long totalDelay = baseDelay + jitter;

            logger.info("⏳ Waiting {} ms before retry attempt {} (base: {} ms, jitter: {} ms)",
                totalDelay, attemptNumber + 1, baseDelay, jitter);

            Thread.sleep(totalDelay);

        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            logger.error("Retry backoff interrupted");
            throw new RuntimeException("Retry interrupted", e);
        }
    }

    /**
     * Génère une clé d'idempotence unique pour éviter doublons
     *
     * Format: <clientId>-<phoneHash>-<timestamp>
     */
    private String generateIdempotencyKey(MDMAEPhoneUpdateRequest request) {
        String data = request.getClientId() + "-" + request.getNewPhoneNumber();
        int hash = data.hashCode();
        return String.format("%s-%d-%s",
            request.getClientId(),
            hash,
            request.getRequestId()
        );
    }

    /**
     * Construire réponse succès
     */
    private Map<String, Object> buildSuccessResponse(
            HttpResponse<String> response,
            MDMAEPhoneUpdateRequest request,
            int attempts,
            long duration) {

        Map<String, Object> result = new HashMap<>();
        result.put("success", true);
        result.put("statusCode", response.statusCode());
        result.put("attempts", attempts);
        result.put("durationMs", duration);

        try {
            // Parser la réponse JSON
            @SuppressWarnings("unchecked")
            Map<String, Object> responseBody = gson.fromJson(response.body(), Map.class);

            result.put("mdmaeId", responseBody.get("id"));
            result.put("transactionId", responseBody.get("transactionId"));
            result.put("message", "Phone updated successfully in MDMAE");

        } catch (Exception e) {
            logger.warn("Could not parse MDMAE response body: {}", e.getMessage());
            result.put("transactionId", "unknown");
        }

        return result;
    }

    /**
     * Construire réponse erreur client (4xx)
     */
    private Map<String, Object> buildClientErrorResponse(
            HttpResponse<String> response,
            MDMAEPhoneUpdateRequest request) {

        Map<String, Object> result = new HashMap<>();
        result.put("success", false);
        result.put("statusCode", response.statusCode());
        result.put("message", "MDMAE API client error: " + response.statusCode());
        result.put("errorType", "ClientError");
        result.put("responseBody", response.body());

        return result;
    }

    /**
     * Construire réponse erreur serveur (5xx)
     */
    private Map<String, Object> buildServerErrorResponse(
            HttpResponse<String> response,
            MDMAEPhoneUpdateRequest request,
            int attempts) {

        Map<String, Object> result = new HashMap<>();
        result.put("success", false);
        result.put("statusCode", response.statusCode());
        result.put("message", "MDMAE API server error after " + attempts + " attempts");
        result.put("errorType", "ServerError");
        result.put("attempts", attempts);
        result.put("responseBody", response.body());

        return result;
    }
}
```

**Points clés :**

1. **Exponential backoff avec jitter** : 1s → 2s → 4s (avec variation ±25%)
2. **Idempotency-Key** : Évite les doublons si MDMAE reçoit plusieurs fois la même requête
3. **Retry intelligent** :
   - ✅ Retry pour 5xx, timeout, connection errors
   - ❌ Pas de retry pour 4xx (erreurs client)
4. **Logging exhaustif** : Facilite le debugging

---

## 📦 Exceptions Personnalisées

### Fichier : `src/main/java/com/bnc/mcp/exceptions/ValidationException.java`

```java
package com.bnc.mcp.exceptions;

/**
 * Exception pour erreurs de validation
 * Step Functions Catch: "ValidationException"
 */
public class ValidationException extends RuntimeException {
    public ValidationException(String message) {
        super(message);
    }

    public ValidationException(String message, Throwable cause) {
        super(message, cause);
    }
}
```

### Fichier : `src/main/java/com/bnc/mcp/exceptions/HttpTimeoutException.java`

```java
package com.bnc.mcp.exceptions;

/**
 * Exception pour timeout HTTP
 * Step Functions Retry: "HttpTimeoutException"
 */
public class HttpTimeoutException extends RuntimeException {
    public HttpTimeoutException(String message) {
        super(message);
    }

    public HttpTimeoutException(String message, Throwable cause) {
        super(message, cause);
    }
}
```

### Fichier : `src/main/java/com/bnc/mcp/exceptions/HttpServerException.java`

```java
package com.bnc/mcp/exceptions;

/**
 * Exception pour erreurs serveur HTTP (5xx)
 * Step Functions Retry: "HttpServerException"
 */
public class HttpServerException extends RuntimeException {
    public HttpServerException(String message) {
        super(message);
    }

    public HttpServerException(String message, Throwable cause) {
        super(message, cause);
    }
}
```

---

## 🧪 Tests Unitaires

### Fichier : `src/test/java/com/bnc/mcp/MDMAEClientRetryTest.java`

```java
package com.bnc.mcp;

import com.bnc.mcp.clients.MDMAEClient;
import com.bnc.mcp.models.MDMAEPhoneUpdateRequest;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;

import java.net.http.HttpClient;
import java.net.http.HttpResponse;
import java.net.http.HttpTimeoutException;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

class MDMAEClientRetryTest {

    @Mock
    private HttpClient mockHttpClient;

    @Mock
    private HttpResponse<String> mockResponse;

    private MDMAEClient mdmaeClient;

    @BeforeEach
    void setUp() {
        MockitoAnnotations.openMocks(this);
        mdmaeClient = new MDMAEClient(mockHttpClient, "https://mdmae-api.example.com");
    }

    /**
     * Test: Succès au 1er essai
     */
    @Test
    void testUpdatePhone_SuccessFirstAttempt() throws Exception {
        // Arrange
        when(mockResponse.statusCode()).thenReturn(200);
        when(mockResponse.body()).thenReturn("{\"id\":\"123\",\"transactionId\":\"txn-456\"}");
        when(mockHttpClient.send(any(), any())).thenReturn(mockResponse);

        MDMAEPhoneUpdateRequest request = new MDMAEPhoneUpdateRequest(
            "CLIENT-123",
            "+15141234567",
            "CA"
        );
        request.setRequestId("req-001");

        // Act
        Map<String, Object> result = mdmaeClient.updatePhone(request);

        // Assert
        assertTrue((Boolean) result.get("success"));
        assertEquals(1, result.get("attempts"));  // 1 seule tentative
        assertEquals("txn-456", result.get("transactionId"));

        // Vérifier qu'on a appelé HTTP 1 seule fois
        verify(mockHttpClient, times(1)).send(any(), any());
    }

    /**
     * Test: Retry après erreur 503, puis succès
     */
    @Test
    void testUpdatePhone_RetryAfter503() throws Exception {
        // Arrange
        HttpResponse<String> errorResponse = mock(HttpResponse.class);
        when(errorResponse.statusCode()).thenReturn(503);
        when(errorResponse.body()).thenReturn("Service Unavailable");

        HttpResponse<String> successResponse = mock(HttpResponse.class);
        when(successResponse.statusCode()).thenReturn(200);
        when(successResponse.body()).thenReturn("{\"id\":\"123\",\"transactionId\":\"txn-456\"}");

        // 1er appel: 503, 2e appel: 200
        when(mockHttpClient.send(any(), any()))
            .thenReturn(errorResponse)
            .thenReturn(successResponse);

        MDMAEPhoneUpdateRequest request = new MDMAEPhoneUpdateRequest(
            "CLIENT-123",
            "+15141234567",
            "CA"
        );

        // Act
        Map<String, Object> result = mdmaeClient.updatePhone(request);

        // Assert
        assertTrue((Boolean) result.get("success"));
        assertEquals(2, result.get("attempts"));  // 2 tentatives

        // Vérifier qu'on a appelé HTTP 2 fois
        verify(mockHttpClient, times(2)).send(any(), any());
    }

    /**
     * Test: Erreur 400 - Pas de retry
     */
    @Test
    void testUpdatePhone_NoRetryFor400() throws Exception {
        // Arrange
        when(mockResponse.statusCode()).thenReturn(400);
        when(mockResponse.body()).thenReturn("{\"error\":\"Invalid phone number\"}");
        when(mockHttpClient.send(any(), any())).thenReturn(mockResponse);

        MDMAEPhoneUpdateRequest request = new MDMAEPhoneUpdateRequest(
            "CLIENT-123",
            "invalid",
            "CA"
        );

        // Act
        Map<String, Object> result = mdmaeClient.updatePhone(request);

        // Assert
        assertFalse((Boolean) result.get("success"));
        assertEquals(400, result.get("statusCode"));
        assertEquals("ClientError", result.get("errorType"));

        // Vérifier qu'on a appelé HTTP 1 seule fois (pas de retry)
        verify(mockHttpClient, times(1)).send(any(), any());
    }

    /**
     * Test: Échec après 3 retry (timeout)
     */
    @Test
    void testUpdatePhone_FailAfter3Retries() throws Exception {
        // Arrange
        when(mockHttpClient.send(any(), any()))
            .thenThrow(new HttpTimeoutException("Timeout"));

        MDMAEPhoneUpdateRequest request = new MDMAEPhoneUpdateRequest(
            "CLIENT-123",
            "+15141234567",
            "CA"
        );

        // Act & Assert
        assertThrows(RuntimeException.class, () -> {
            mdmaeClient.updatePhone(request);
        });

        // Vérifier qu'on a appelé HTTP 3 fois (max retry)
        verify(mockHttpClient, times(3)).send(any(), any());
    }
}
```

---

## 📊 Exemple de Flow Complet

### Scénario : MDMAE API est temporairement down, puis récupère

```
Timeline:

T=0s    : Step Functions démarre UpdateMDMAE
          └─> Lambda invoqué (Tentative #1)
              └─> MDMAEClient: HTTP call #1
                  └─> Timeout (30s)

T=30s   : MDMAEClient: Retry HTTP call #2 après 1s backoff
          └─> HTTP 503 (Service Unavailable)

T=31s   : MDMAEClient: Retry HTTP call #3 après 2s backoff
          └─> HTTP 200 (Success!)

T=33s   : Lambda retourne succès
          └─> Step Functions continue vers ParallelUpdates

Total: 33 secondes, 3 tentatives HTTP, succès!
```

### Logs CloudWatch

```
2026-09-25T10:00:00Z [INFO] === MDMAE updatePhone called ===
2026-09-25T10:00:00Z [INFO] Client ID: CLIENT-12345
2026-09-25T10:00:00Z [INFO] Idempotency Key: CLIENT-12345-789-req-001
2026-09-25T10:00:00Z [INFO] --- Attempt 1 of 3 ---
2026-09-25T10:00:30Z [WARN] ⚠️ HTTP Timeout on attempt 1: request timed out
2026-09-25T10:00:30Z [INFO] Will retry after backoff...
2026-09-25T10:00:30Z [INFO] ⏳ Waiting 1200 ms before retry attempt 2 (base: 1000 ms, jitter: 200 ms)
2026-09-25T10:00:31Z [INFO] --- Attempt 2 of 3 ---
2026-09-25T10:00:31Z [INFO] HTTP Response: 503 (duration: 150 ms)
2026-09-25T10:00:31Z [WARN] ⚠️ Server error 503 on attempt 2
2026-09-25T10:00:31Z [INFO] Will retry after backoff...
2026-09-25T10:00:31Z [INFO] ⏳ Waiting 2100 ms before retry attempt 3 (base: 2000 ms, jitter: 100 ms)
2026-09-25T10:00:33Z [INFO] --- Attempt 3 of 3 ---
2026-09-25T10:00:33Z [INFO] HTTP Response: 200 (duration: 250 ms)
2026-09-25T10:00:33Z [INFO] ✅ MDMAE update successful on attempt 3
```

---

## 🎯 Résumé

### Configuration complète pour UpdateMDMAE

| Niveau | Configuration | Retry pour | Max Attempts |
|--------|--------------|------------|--------------|
| **1. Step Functions** | Terraform | Lambda errors, timeouts | 3 |
| **2. Lambda Handler** | Java code | Propagation exceptions typées | - |
| **3. MDMAEClient** | Java code | HTTP 5xx, timeout, network | 3 |

### Total retry possible

Dans le pire cas :
- MDMAEClient retry : 3 fois
- Step Functions retry Lambda : 3 fois
- **Total maximum** : 3 x 3 = **9 tentatives**

### Temps maximum

- MDMAEClient backoff : 1s + 2s + 4s = 7s
- Timeout HTTP par call : 30s x 3 = 90s
- Step Functions backoff : 5s + 10s + 20s = 35s
- **Total max** : ~130 secondes (2 minutes)

---

**Prochaine étape :** Implémenter ce pattern pour les autres API externes (FCC, CRM).